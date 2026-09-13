-- =============================================================================
-- Project Atlas — Step 14C-2J Phase B2/C
-- Shared normalized Paddle subscription applicator + provider-state fence.
--
-- Adds:
--   - private.company_billing.last_provider_subscription_state_fingerprint
--   - private.billing_paddle_subscription_snapshot_fingerprint
--   - private.map_paddle_sandbox_subscription_targets
--   - private.apply_normalized_paddle_sandbox_subscription_state
--   - CREATE OR REPLACE private.apply_paddle_sandbox_webhook_event
--     (webhook shell keeps inbox/watermark/P0-P2; shared core applies state)
--
-- Does NOT:
--   - edit B1 migration
--   - implement Paddle GET / reconciliation Edge / public reconcile apply RPC
--   - populate fence for legacy rows (NULL bootstrap remains intentional)
--   - change transaction.completed non-authoritative semantics
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema: paired provider snapshot fingerprint (with B1 version fence)
-- -----------------------------------------------------------------------------
ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_provider_subscription_state_fingerprint TEXT NULL;

COMMENT ON COLUMN private.company_billing.last_provider_subscription_state_fingerprint IS
  'Step 14C-2J B2/C: canonical md5 fingerprint of the last accepted normalized '
  'Paddle subscription snapshot. Paired with last_provider_subscription_updated_at. '
  'Shared by webhook + reconciliation. NOT the webhook event watermark '
  '(last_subscription_event_occurred_at). NOT the B1 local-state concurrency '
  'fingerprint. No historical backfill; existing rows remain NULL.';

-- -----------------------------------------------------------------------------
-- Snapshot fingerprint (provider content only; excludes provider_updated_at)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  p_external_subscription_id TEXT,
  p_external_customer_id TEXT,
  p_external_price_id TEXT,
  p_provider_subscription_status TEXT,
  p_current_period_start TIMESTAMPTZ,
  p_current_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT pg_catalog.md5(
    pg_catalog.jsonb_build_array(
      p_external_subscription_id,
      p_external_customer_id,
      p_external_price_id,
      p_provider_subscription_status,
      private.billing_reconciliation_ts_token(p_current_period_start),
      private.billing_reconciliation_ts_token(p_current_period_end),
      p_cancel_at_period_end,
      private.billing_reconciliation_ts_token(p_canceled_at)
    )::text
  );
$$;

COMMENT ON FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) IS
  'Step 14C-2J B2/C: canonical provider snapshot fingerprint. Ordered jsonb array; '
  'NULL≠empty; BOOLEAN null/false distinct; excludes provider_updated_at.';

ALTER FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM authenticated;
REVOKE ALL ON FUNCTION private.billing_paddle_subscription_snapshot_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM service_role;

-- -----------------------------------------------------------------------------
-- Shared status → Atlas targets mapper (single source; no webhook/reconcile fork)
-- -----------------------------------------------------------------------------
-- Signature change (B2/C-FIX8): add p_provider_updated_at for deterministic
-- canceled_at fallback. Drop prior overload so CREATE OR REPLACE does not leave
-- an ambiguous second signature in already-applied local DBs.
DROP FUNCTION IF EXISTS private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION private.map_paddle_sandbox_subscription_targets(
  p_paddle_status TEXT,
  p_period_start TIMESTAMPTZ,
  p_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ,
  p_provider_updated_at TIMESTAMPTZ,
  p_price_id TEXT,
  p_bill_payment_status TEXT,
  p_sub_entitlement_origin TEXT,
  p_sub_plan_code TEXT,
  p_sub_status TEXT,
  p_sub_trial_started_at TIMESTAMPTZ,
  p_sub_trial_ends_at TIMESTAMPTZ,
  p_sub_trial_used_at TIMESTAMPTZ,
  p_now TIMESTAMPTZ
)
RETURNS TABLE (
  target_subscription_status TEXT,
  target_payment_status TEXT,
  target_provider_access_status TEXT,
  target_provider_access_ends_at TIMESTAMPTZ,
  target_grace_ends_at TIMESTAMPTZ,
  target_cancel_at_period_end BOOLEAN,
  target_canceled_at TIMESTAMPTZ,
  target_period_start TIMESTAMPTZ,
  target_period_end TIMESTAMPTZ,
  target_cs_origin TEXT,
  target_cs_plan TEXT,
  target_cs_status TEXT,
  target_cs_trial_started_at TIMESTAMPTZ,
  target_cs_trial_ends_at TIMESTAMPTZ,
  target_cs_trial_used_at TIMESTAMPTZ,
  mutate_company_subscriptions BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_status TEXT := lower(btrim(COALESCE(p_paddle_status, '')));
  v_cancel BOOLEAN := COALESCE(p_cancel_at_period_end, FALSE);
BEGIN
  IF p_period_start IS NOT NULL
    AND p_period_end IS NOT NULL
    AND p_period_end <= p_period_start THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
  END IF;

  IF v_status = 'trialing' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED';
  END IF;

  IF v_status = 'active' THEN
    IF p_period_start IS NULL OR p_period_end IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
    END IF;
    IF p_period_end <= p_now THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
    END IF;
    IF p_price_id IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;

    target_subscription_status := 'active';
    target_payment_status := 'ok';
    target_provider_access_status := 'entitled';
    target_provider_access_ends_at := p_period_end;
    target_grace_ends_at := NULL;
    target_cancel_at_period_end := v_cancel;
    target_canceled_at := NULL;
    target_period_start := p_period_start;
    target_period_end := p_period_end;
    target_cs_origin := 'provider';
    target_cs_plan := 'premium';
    target_cs_status := 'active';
    target_cs_trial_used_at := p_sub_trial_used_at;
    target_cs_trial_started_at := NULL;
    target_cs_trial_ends_at := NULL;
    mutate_company_subscriptions := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_status = 'past_due' THEN
    target_subscription_status := 'active';
    target_payment_status := 'past_due';
    target_provider_access_status := 'blocked';
    target_provider_access_ends_at := NULL;
    target_grace_ends_at := NULL;
    target_cancel_at_period_end := FALSE;
    target_canceled_at := NULL;
    target_period_start := p_period_start;
    target_period_end := p_period_end;
    target_cs_origin := 'provider';
    target_cs_plan := 'premium';
    target_cs_status := 'active';
    target_cs_trial_used_at := p_sub_trial_used_at;
    target_cs_trial_started_at := NULL;
    target_cs_trial_ends_at := NULL;
    mutate_company_subscriptions := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_status = 'paused' THEN
    target_subscription_status := 'paused';
    target_payment_status := CASE
      WHEN p_bill_payment_status IN (
        'none', 'ok', 'pending', 'past_due', 'failed', 'refunded', 'unknown'
      ) THEN p_bill_payment_status
      ELSE 'unknown'
    END;
    target_provider_access_status := 'blocked';
    target_provider_access_ends_at := NULL;
    target_grace_ends_at := NULL;
    target_cancel_at_period_end := FALSE;
    target_canceled_at := NULL;
    target_period_start := p_period_start;
    target_period_end := p_period_end;
    target_cs_origin := 'provider';
    target_cs_plan := 'free';
    target_cs_status := 'free';
    target_cs_trial_used_at := p_sub_trial_used_at;
    target_cs_trial_started_at := NULL;
    target_cs_trial_ends_at := NULL;
    mutate_company_subscriptions := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_status = 'canceled' THEN
    target_subscription_status := 'ended';
    target_payment_status := CASE
      WHEN p_bill_payment_status IN (
        'none', 'ok', 'past_due', 'failed', 'refunded', 'pending', 'unknown'
      ) THEN p_bill_payment_status
      ELSE 'unknown'
    END;
    target_provider_access_status := 'ended';
    target_provider_access_ends_at := NULL;
    target_grace_ends_at := NULL;
    target_cancel_at_period_end := FALSE;
    -- Deterministic: never substitute invocation clock for missing provider
    -- canceled_at. Same provider version+snapshot must map to the same target.
    target_canceled_at := COALESCE(p_canceled_at, p_provider_updated_at);
    target_period_start := p_period_start;
    target_period_end := p_period_end;
    target_cs_origin := 'provider';
    target_cs_plan := 'free';
    target_cs_status := 'free';
    target_cs_trial_used_at := p_sub_trial_used_at;
    target_cs_trial_started_at := NULL;
    target_cs_trial_ends_at := NULL;
    mutate_company_subscriptions := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_status IN ('incomplete', 'pending') THEN
    target_subscription_status := 'incomplete';
    target_payment_status := 'pending';
    target_provider_access_status := 'blocked';
    target_provider_access_ends_at := NULL;
    target_grace_ends_at := NULL;
    target_cancel_at_period_end := FALSE;
    target_canceled_at := NULL;
    target_period_start := p_period_start;
    target_period_end := p_period_end;
    target_cs_origin := CASE
      WHEN p_sub_entitlement_origin = 'provider' THEN 'provider'
      WHEN p_sub_entitlement_origin = 'internal_trial' THEN 'internal_trial'
      ELSE 'none'
    END;
    IF target_cs_origin = 'provider' THEN
      target_cs_plan := 'free';
      target_cs_status := 'free';
      target_cs_trial_used_at := p_sub_trial_used_at;
      target_cs_trial_started_at := NULL;
      target_cs_trial_ends_at := NULL;
      mutate_company_subscriptions := TRUE;
    ELSIF target_cs_origin = 'internal_trial' THEN
      target_cs_plan := p_sub_plan_code;
      target_cs_status := p_sub_status;
      target_cs_trial_used_at := p_sub_trial_used_at;
      target_cs_trial_started_at := p_sub_trial_started_at;
      target_cs_trial_ends_at := p_sub_trial_ends_at;
      mutate_company_subscriptions := FALSE;
    ELSE
      target_cs_plan := 'free';
      target_cs_status := 'free';
      target_cs_trial_used_at := p_sub_trial_used_at;
      target_cs_trial_started_at := NULL;
      target_cs_trial_ends_at := NULL;
      mutate_company_subscriptions := TRUE;
    END IF;
    RETURN NEXT;
    RETURN;
  END IF;

  RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'ATLAS_PROVIDER_STATUS_UNSUPPORTED';
END;
$$;

COMMENT ON FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) IS
  'Step 14C-2J B2/C-FIX8: shared paddle/test subscription → Atlas target mapping. '
  'Canceled fallback canceled_at = COALESCE(provider canceled_at, provider_updated_at).';

ALTER FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) FROM authenticated;
REVOKE ALL ON FUNCTION private.map_paddle_sandbox_subscription_targets(
  TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT,
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ
) FROM service_role;

-- -----------------------------------------------------------------------------
-- Shared applicator (caller must already hold sub + billing row locks)
-- Does NOT write webhook watermark. Does NOT touch inbox.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  p_company_id UUID,
  p_external_subscription_id TEXT,
  p_external_customer_id TEXT,
  p_external_price_id TEXT,
  p_provider_subscription_status TEXT,
  p_current_period_start TIMESTAMPTZ,
  p_current_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ,
  p_provider_updated_at TIMESTAMPTZ,
  p_allow_provider_fence_bootstrap BOOLEAN,
  p_now TIMESTAMPTZ DEFAULT clock_timestamp()
)
RETURNS TABLE (
  outcome TEXT,
  company_id UUID
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_provider_code TEXT := 'paddle';
  v_provider_environment TEXT := 'test';
  v_bill private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;
  v_tgt RECORD;
  v_incoming_fp TEXT;
  v_effective_price TEXT;
  v_local_match BOOLEAN;
  v_stored_version TIMESTAMPTZ;
  v_stored_fp TEXT;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_provider_updated_at IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_UPDATED_AT_REQUIRED';
  END IF;

  IF p_external_subscription_id IS NULL OR p_external_customer_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  IF v_sub.entitlement_origin = 'manual' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT';
  END IF;

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  v_stored_version := v_bill.last_provider_subscription_updated_at;
  v_stored_fp := v_bill.last_provider_subscription_state_fingerprint;

  -- Fence integrity (paired version + fingerprint)
  IF v_stored_version IS NULL AND v_stored_fp IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY';
  END IF;
  IF v_stored_version IS NOT NULL AND v_stored_fp IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY';
  END IF;

  -- NULL fence bootstrap policy (explicit; default fail-closed)
  IF v_stored_version IS NULL AND v_stored_fp IS NULL THEN
    IF p_allow_provider_fence_bootstrap IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_STATE_FENCE_UNINITIALIZED';
    END IF;
  ELSIF p_provider_updated_at < v_stored_version THEN
    outcome := 'stale_provider_state';
    company_id := p_company_id;
    RETURN NEXT;
    RETURN;
  ELSIF p_provider_updated_at = v_stored_version THEN
    v_incoming_fp := private.billing_paddle_subscription_snapshot_fingerprint(
      p_external_subscription_id,
      p_external_customer_id,
      p_external_price_id,
      lower(btrim(p_provider_subscription_status)),
      p_current_period_start,
      p_current_period_end,
      COALESCE(p_cancel_at_period_end, FALSE),
      p_canceled_at
    );
    IF v_incoming_fp IS DISTINCT FROM v_stored_fp THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS';
    END IF;
    -- same version + same snapshot fingerprint → idempotent or local repair
  ELSIF p_provider_updated_at <= v_stored_version THEN
    -- defensive (should be covered above)
    outcome := 'stale_provider_state';
    company_id := p_company_id;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT *
  INTO v_tgt
  FROM private.map_paddle_sandbox_subscription_targets(
    p_provider_subscription_status,
    p_current_period_start,
    p_current_period_end,
    COALESCE(p_cancel_at_period_end, FALSE),
    p_canceled_at,
    p_provider_updated_at,
    p_external_price_id,
    v_bill.payment_status,
    v_sub.entitlement_origin,
    v_sub.plan_code,
    v_sub.status,
    v_sub.trial_started_at,
    v_sub.trial_ends_at,
    v_sub.trial_used_at,
    p_now
  );

  v_effective_price := COALESCE(p_external_price_id, v_bill.external_price_id);

  v_incoming_fp := private.billing_paddle_subscription_snapshot_fingerprint(
    p_external_subscription_id,
    p_external_customer_id,
    p_external_price_id,
    lower(btrim(p_provider_subscription_status)),
    p_current_period_start,
    p_current_period_end,
    COALESCE(p_cancel_at_period_end, FALSE),
    p_canceled_at
  );

  v_local_match := (
    v_bill.provider_code IS NOT DISTINCT FROM v_provider_code
    AND v_bill.provider_environment IS NOT DISTINCT FROM v_provider_environment
    AND v_bill.external_customer_id IS NOT DISTINCT FROM p_external_customer_id
    AND v_bill.external_subscription_id IS NOT DISTINCT FROM p_external_subscription_id
    AND (p_external_price_id IS NULL
      OR v_bill.external_price_id IS NOT DISTINCT FROM p_external_price_id)
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_tgt.target_subscription_status
    AND v_bill.payment_status IS NOT DISTINCT FROM v_tgt.target_payment_status
    AND v_bill.provider_access_status IS NOT DISTINCT FROM v_tgt.target_provider_access_status
    AND v_bill.provider_access_ends_at IS NOT DISTINCT FROM v_tgt.target_provider_access_ends_at
    AND v_bill.grace_ends_at IS NOT DISTINCT FROM v_tgt.target_grace_ends_at
    AND v_bill.cancel_at_period_end IS NOT DISTINCT FROM v_tgt.target_cancel_at_period_end
    AND v_bill.canceled_at IS NOT DISTINCT FROM v_tgt.target_canceled_at
    AND v_bill.current_period_start IS NOT DISTINCT FROM v_tgt.target_period_start
    AND v_bill.current_period_end IS NOT DISTINCT FROM v_tgt.target_period_end
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM p_provider_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_incoming_fp
    AND (
      v_tgt.mutate_company_subscriptions IS DISTINCT FROM TRUE
      OR (
        v_sub.entitlement_origin IS NOT DISTINCT FROM v_tgt.target_cs_origin
        AND v_sub.plan_code IS NOT DISTINCT FROM v_tgt.target_cs_plan
        AND v_sub.status IS NOT DISTINCT FROM v_tgt.target_cs_status
        AND v_sub.trial_started_at IS NOT DISTINCT FROM v_tgt.target_cs_trial_started_at
        AND v_sub.trial_ends_at IS NOT DISTINCT FROM v_tgt.target_cs_trial_ends_at
        AND v_sub.trial_used_at IS NOT DISTINCT FROM v_tgt.target_cs_trial_used_at
      )
    )
  );

  IF v_local_match
    AND v_stored_version IS NOT NULL
    AND p_provider_updated_at = v_stored_version
  THEN
    outcome := 'already_applied';
    company_id := p_company_id;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    UPDATE private.company_billing b
    SET
      provider_code = v_provider_code,
      provider_environment = v_provider_environment,
      external_customer_id = p_external_customer_id,
      external_subscription_id = p_external_subscription_id,
      external_price_id = v_effective_price,
      subscription_status = v_tgt.target_subscription_status,
      payment_status = v_tgt.target_payment_status,
      cancel_at_period_end = v_tgt.target_cancel_at_period_end,
      current_period_start = v_tgt.target_period_start,
      current_period_end = v_tgt.target_period_end,
      canceled_at = v_tgt.target_canceled_at,
      provider_access_status = v_tgt.target_provider_access_status,
      provider_access_ends_at = v_tgt.target_provider_access_ends_at,
      grace_ends_at = v_tgt.target_grace_ends_at,
      sync_status = 'idle',
      last_sync_result = 'succeeded',
      last_synced_at = p_now,
      last_sync_error_sanitized = NULL,
      last_provider_subscription_updated_at = p_provider_updated_at,
      last_provider_subscription_state_fingerprint = v_incoming_fp,
      updated_at = p_now
    WHERE b.company_id = p_company_id;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END;

  IF v_tgt.mutate_company_subscriptions IS TRUE THEN
    UPDATE public.company_subscriptions cs
    SET
      entitlement_origin = v_tgt.target_cs_origin,
      plan_code = v_tgt.target_cs_plan,
      status = v_tgt.target_cs_status,
      trial_started_at = v_tgt.target_cs_trial_started_at,
      trial_ends_at = v_tgt.target_cs_trial_ends_at,
      trial_used_at = v_tgt.target_cs_trial_used_at,
      updated_at = p_now
    WHERE cs.company_id = p_company_id;
  END IF;

  IF v_stored_version IS NOT NULL
    AND p_provider_updated_at = v_stored_version
    AND v_incoming_fp IS NOT DISTINCT FROM v_stored_fp
  THEN
    outcome := 'repaired_same_version';
  ELSE
    outcome := 'applied';
  END IF;
  company_id := p_company_id;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) IS
  'Step 14C-2J B2/C: shared paddle/test subscription applicator with provider '
  'version+snapshot fence. Does not write webhook watermark. Bootstrap only when '
  'p_allow_provider_fence_bootstrap=true. Outcomes: applied|already_applied|'
  'repaired_same_version|stale_provider_state.';

ALTER FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM authenticated;
REVOKE ALL ON FUNCTION private.apply_normalized_paddle_sandbox_subscription_state(
  UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ,
  TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ
) FROM service_role;


-- -----------------------------------------------------------------------------
-- Webhook apply refactor: shell keeps inbox/P0-P2/watermark; shared applicator
-- applies normalized subscription state + provider fence.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.apply_paddle_sandbox_webhook_event(
  p_inbox_event_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  company_id UUID,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_provider_code TEXT := 'paddle';
  v_provider_environment TEXT := 'test';
  v_now TIMESTAMPTZ := clock_timestamp();
  v_row private.billing_provider_events%ROWTYPE;
  v_payload JSONB;
  v_data JSONB;
  v_event_type TEXT;
  v_is_subscription BOOLEAN;
  v_is_transaction BOOLEAN;
  v_paddle_status TEXT;
  v_customer_id TEXT;
  v_subscription_id TEXT;
  v_transaction_id TEXT;
  v_price_id TEXT;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
  v_canceled_at TIMESTAMPTZ;
  v_cancel_at_period_end BOOLEAN := FALSE;
  v_custom JSONB;
  v_schema_version INTEGER;
  v_atlas_company_id UUID;
  v_atlas_session_id UUID;
  v_atlas_offer_code TEXT;
  v_company_id UUID;
  v_bill private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;
  v_sess private.billing_checkout_sessions%ROWTYPE;
  v_price private.billing_provider_prices%ROWTYPE;
  v_owner_by_sub UUID;
  v_owner_by_cus UUID;
  v_need_session_lock BOOLEAN := FALSE;
  v_tmp TEXT;
  v_tmp_num NUMERIC;
  v_provider_updated_at TIMESTAMPTZ;
  v_allow_bootstrap BOOLEAN;
  v_apply_out TEXT;
  v_incoming_snapshot_fp TEXT;
BEGIN
  IF p_inbox_event_id IS NULL THEN
    outcome := 'not_found';
    inbox_event_id := NULL;
    processing_status := NULL;
    company_id := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 1) Lock inbox
  SELECT e.*
  INTO v_row
  FROM private.billing_provider_events e
  WHERE e.id = p_inbox_event_id
    AND e.provider_code = v_provider_code
    AND e.provider_environment = v_provider_environment
  FOR UPDATE;

  IF NOT FOUND THEN
    outcome := 'not_found';
    inbox_event_id := p_inbox_event_id;
    processing_status := NULL;
    company_id := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.verification_status IS DISTINCT FROM 'verified' THEN
    outcome := 'not_verified';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Simulator hard firewall — never mutate billing/subs
  IF v_row.external_event_id ~ '^ntfsimevt_[a-z0-9]{26}$' THEN
    IF v_row.processing_status = 'processed' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_SIMULATOR_PROCESSED_INVARIANT';
    END IF;
    IF v_row.processing_status IS DISTINCT FROM 'ignored' THEN
      UPDATE private.billing_provider_events e
      SET
        processing_status = 'ignored',
        processed_at = v_now,
        error_sanitized = 'simulator_event'
      WHERE e.id = v_row.id;
    END IF;
    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := 'ignored';
    company_id := NULL;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status = 'processed' THEN
    outcome := 'already_processed';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status = 'ignored' THEN
    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status IS DISTINCT FROM 'processing' THEN
    outcome := 'invalid_state';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.payload_json IS NULL OR jsonb_typeof(v_row.payload_json) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING';
  END IF;

  IF v_row.external_event_id !~ '^evt_[a-z0-9]{26}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  v_payload := v_row.payload_json;
  v_event_type := v_row.event_type;

  IF v_event_type IS NULL OR v_event_type NOT IN (
    'subscription.created',
    'subscription.updated',
    'subscription.activated',
    'subscription.canceled',
    'subscription.past_due',
    'transaction.completed'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED';
  END IF;

  v_is_subscription := v_event_type LIKE 'subscription.%';
  v_is_transaction := v_event_type = 'transaction.completed';

  v_data := v_payload -> 'data';
  IF v_data IS NULL OR jsonb_typeof(v_data) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  -- Root occurred_at must match inbox.provider_created_at when present
  IF v_payload ? 'occurred_at' THEN
    BEGIN
      IF (v_payload ->> 'occurred_at')::timestamptz IS DISTINCT FROM v_row.provider_created_at THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
      END IF;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  IF v_row.provider_created_at IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  -- Extract IDs / status
  v_paddle_status := lower(btrim(COALESCE(v_data ->> 'status', '')));
  IF v_paddle_status = '' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  v_customer_id := btrim(COALESCE(v_data ->> 'customer_id', ''));
  IF v_customer_id = '' OR v_customer_id !~ '^ctm_[a-z0-9]{26}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  IF v_is_subscription THEN
    v_subscription_id := btrim(COALESCE(v_data ->> 'id', ''));
    IF v_subscription_id = '' OR v_subscription_id !~ '^sub_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
  ELSE
    v_transaction_id := btrim(COALESCE(v_data ->> 'id', ''));
    IF v_transaction_id = '' OR v_transaction_id !~ '^txn_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
    v_subscription_id := btrim(COALESCE(v_data ->> 'subscription_id', ''));
    IF v_subscription_id = '' OR v_subscription_id !~ '^sub_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
  END IF;

  -- Price id from items[0].price.id
  v_price_id := NULL;
  IF jsonb_typeof(v_data -> 'items') = 'array'
    AND jsonb_array_length(v_data -> 'items') > 0 THEN
    v_tmp := btrim(COALESCE(v_data -> 'items' -> 0 -> 'price' ->> 'id', ''));
    IF v_tmp <> '' THEN
      IF v_tmp !~ '^pri_[a-z0-9]{26}$' THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
      END IF;
      v_price_id := v_tmp;
    END IF;
  END IF;

  -- Period bounds (subscription events)
  v_period_start := NULL;
  v_period_end := NULL;
  IF v_is_subscription
    AND jsonb_typeof(v_data -> 'current_billing_period') = 'object' THEN
    BEGIN
      IF (v_data -> 'current_billing_period') ? 'starts_at'
        AND nullif(btrim(v_data -> 'current_billing_period' ->> 'starts_at'), '') IS NOT NULL THEN
        v_period_start := (v_data -> 'current_billing_period' ->> 'starts_at')::timestamptz;
      END IF;
      IF (v_data -> 'current_billing_period') ? 'ends_at'
        AND nullif(btrim(v_data -> 'current_billing_period' ->> 'ends_at'), '') IS NOT NULL THEN
        v_period_end := (v_data -> 'current_billing_period' ->> 'ends_at')::timestamptz;
      END IF;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  v_canceled_at := NULL;
  IF v_is_subscription
    AND nullif(btrim(COALESCE(v_data ->> 'canceled_at', '')), '') IS NOT NULL THEN
    BEGIN
      v_canceled_at := (v_data ->> 'canceled_at')::timestamptz;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  -- Scheduled cancellation while still active
  IF v_is_subscription
    AND jsonb_typeof(v_data -> 'scheduled_change') = 'object'
    AND lower(btrim(COALESCE(v_data -> 'scheduled_change' ->> 'action', ''))) = 'cancel'
  THEN
    v_cancel_at_period_end := TRUE;
  END IF;

  -- Provider object version = data.updated_at (NOT event occurred_at)
  v_provider_updated_at := NULL;
  IF v_is_subscription THEN
    IF nullif(btrim(COALESCE(v_data ->> 'updated_at', '')), '') IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_UPDATED_AT_REQUIRED';
    END IF;
    BEGIN
      v_provider_updated_at := (v_data ->> 'updated_at')::timestamptz;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_UPDATED_AT_REQUIRED';
    END;
    IF v_provider_updated_at IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_UPDATED_AT_REQUIRED';
    END IF;
  END IF;

  -- custom_data (optional unless first-link)
  v_custom := NULL;
  IF v_data ? 'custom_data' AND jsonb_typeof(v_data -> 'custom_data') = 'object' THEN
    v_custom := v_data -> 'custom_data';
  END IF;

  v_schema_version := NULL;
  v_atlas_company_id := NULL;
  v_atlas_session_id := NULL;
  v_atlas_offer_code := NULL;
  IF v_custom IS NOT NULL THEN
    BEGIN
      IF v_custom ? 'atlas_schema_version' THEN
        v_tmp_num := (v_custom ->> 'atlas_schema_version')::numeric;
        IF v_tmp_num <> trunc(v_tmp_num) THEN
          RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA';
        END IF;
        v_schema_version := v_tmp_num::integer;
        IF v_schema_version IS DISTINCT FROM 1 THEN
          RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA';
        END IF;
      END IF;
      IF v_custom ? 'atlas_company_id'
        AND nullif(btrim(v_custom ->> 'atlas_company_id'), '') IS NOT NULL THEN
        v_atlas_company_id := (v_custom ->> 'atlas_company_id')::uuid;
      END IF;
      IF v_custom ? 'atlas_checkout_session_id'
        AND nullif(btrim(v_custom ->> 'atlas_checkout_session_id'), '') IS NOT NULL THEN
        v_atlas_session_id := (v_custom ->> 'atlas_checkout_session_id')::uuid;
      END IF;
      IF v_custom ? 'atlas_offer_code' THEN
        v_atlas_offer_code := lower(btrim(COALESCE(v_custom ->> 'atlas_offer_code', '')));
        IF v_atlas_offer_code = '' THEN
          v_atlas_offer_code := NULL;
        END IF;
      END IF;
    EXCEPTION
      WHEN others THEN
        IF SQLERRM LIKE 'ATLAS_%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  -- Resolve existing owners (read-only evidence before row locks)
  SELECT b.company_id
  INTO v_owner_by_sub
  FROM private.company_billing b
  WHERE b.provider_code = v_provider_code
    AND b.provider_environment = v_provider_environment
    AND b.external_subscription_id = v_subscription_id
  LIMIT 1;

  SELECT b.company_id
  INTO v_owner_by_cus
  FROM private.company_billing b
  WHERE b.provider_code = v_provider_code
    AND b.provider_environment = v_provider_environment
    AND b.external_customer_id = v_customer_id
  LIMIT 1;

  IF v_owner_by_sub IS NOT NULL AND v_owner_by_cus IS NOT NULL
    AND v_owner_by_sub IS DISTINCT FROM v_owner_by_cus THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF v_owner_by_sub IS NOT NULL THEN
    v_company_id := v_owner_by_sub;
  ELSIF v_owner_by_cus IS NOT NULL THEN
    v_company_id := v_owner_by_cus;
  ELSE
    -- P2 first-link: full checkout proof required
    IF v_atlas_company_id IS NULL
      OR v_atlas_session_id IS NULL
      OR v_atlas_offer_code IS NULL
      OR v_schema_version IS DISTINCT FROM 1
      OR v_price_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_UNLINKED';
    END IF;

    SELECT s.*
    INTO v_sess
    FROM private.billing_checkout_sessions s
    WHERE s.id = v_atlas_session_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_UNLINKED';
    END IF;

    -- Session must be an open, non-expired, provider-created checkout.
    -- Note: sessions do NOT store customer_id or subscription_id; those
    -- cannot be cross-checked against checkout rows with the current schema.
    IF v_sess.company_id IS DISTINCT FROM v_atlas_company_id
      OR v_sess.provider_code IS DISTINCT FROM v_provider_code
      OR v_sess.provider_environment IS DISTINCT FROM v_provider_environment
      OR v_sess.offer_code IS DISTINCT FROM v_atlas_offer_code
      OR v_atlas_offer_code IS DISTINCT FROM 'premium_monthly'
      OR v_sess.checkout_status NOT IN ('created', 'opened')
      OR v_sess.expires_at <= v_now
      OR v_sess.provider_create_status IS DISTINCT FROM 'created'
      OR v_sess.external_transaction_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;

    SELECT p.*
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.id = v_sess.billing_provider_price_id;

    IF NOT FOUND
      OR v_price.provider_code IS DISTINCT FROM v_provider_code
      OR v_price.provider_environment IS DISTINCT FROM v_provider_environment
      OR v_price.external_price_id IS DISTINCT FROM v_price_id
      OR v_price.is_active IS DISTINCT FROM TRUE
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PRICE_MISMATCH';
    END IF;

    -- Transaction id must match session when applying transaction.completed.
    -- subscription.* first-link cannot compare txn id from subscription payload;
    -- session.external_transaction_id presence was already required above.
    IF v_is_transaction
      AND v_sess.external_transaction_id IS DISTINCT FROM v_transaction_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;

    v_company_id := v_sess.company_id;
    v_need_session_lock := TRUE;
  END IF;

  -- Linked path: if custom_data company present it must match
  IF v_atlas_company_id IS NOT NULL
    AND v_atlas_company_id IS DISTINCT FROM v_company_id THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- Price required when establishing or changing price / entitled path
  IF v_price_id IS NOT NULL THEN
    SELECT p.*
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.provider_code = v_provider_code
      AND p.provider_environment = v_provider_environment
      AND p.external_price_id = v_price_id
      AND p.is_active IS TRUE
    LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PRICE_MISMATCH';
    END IF;
  END IF;

  -- 3) Lock subscriptions then billing (global order)
  SELECT cs.*
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  IF v_sub.entitlement_origin = 'manual' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT';
  END IF;

  SELECT b.*
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  -- Refuse overwriting a different provider / environment link
  IF (
      v_bill.provider_code IS NOT NULL
      AND v_bill.provider_code IS DISTINCT FROM v_provider_code
    )
    OR (
      v_bill.provider_environment IS NOT NULL
      AND v_bill.provider_environment IS DISTINCT FROM v_provider_environment
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- Re-validate unique ownership under locks
  IF v_bill.external_subscription_id IS NOT NULL
    AND v_bill.external_subscription_id IS DISTINCT FROM v_subscription_id
    AND v_owner_by_sub IS NULL THEN
    -- company already has a different subscription
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.company_billing b
    WHERE b.provider_code = v_provider_code
      AND b.provider_environment = v_provider_environment
      AND b.external_subscription_id = v_subscription_id
      AND b.company_id IS DISTINCT FROM v_company_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.company_billing b
    WHERE b.provider_code = v_provider_code
      AND b.provider_environment = v_provider_environment
      AND b.external_customer_id = v_customer_id
      AND b.company_id IS DISTINCT FROM v_company_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- 5) Checkout session lock last (first-link only)
  IF v_need_session_lock THEN
    SELECT s.*
    INTO v_sess
    FROM private.billing_checkout_sessions s
    WHERE s.id = v_atlas_session_id
    FOR UPDATE;

    IF NOT FOUND
      OR v_sess.company_id IS DISTINCT FROM v_company_id
      OR v_sess.offer_code IS DISTINCT FROM v_atlas_offer_code
      OR v_sess.checkout_status NOT IN ('created', 'opened')
      OR v_sess.expires_at <= v_now
      OR v_sess.provider_create_status IS DISTINCT FROM 'created'
      OR v_sess.external_transaction_id IS NULL
      OR (
        v_is_transaction
        AND v_sess.external_transaction_id IS DISTINCT FROM v_transaction_id
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;
  END IF;

  -- Paddle trialing = configuration drift (no provider trial)
  IF v_is_subscription AND v_paddle_status = 'trialing' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED';
  END IF;

  -- Transaction.completed: linkage + payment assist only (non-authoritative)
  IF v_is_transaction THEN
    IF v_paddle_status IS DISTINCT FROM 'completed' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
    IF v_price_id IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;

    BEGIN
      UPDATE private.company_billing b
      SET
        provider_code = v_provider_code,
        provider_environment = v_provider_environment,
        external_customer_id = v_customer_id,
        external_subscription_id = v_subscription_id,
        external_price_id = v_price_id,
        payment_status = CASE
          WHEN b.provider_access_status = 'entitled' THEN 'ok'
          WHEN b.payment_status = 'past_due' THEN b.payment_status
          ELSE 'ok'
        END,
        sync_status = 'idle',
        last_sync_result = 'succeeded',
        last_synced_at = v_now,
        last_sync_error_sanitized = NULL,
        updated_at = v_now
      WHERE b.company_id = v_company_id;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END;

    -- Do NOT mutate company_subscriptions entitlement from transaction alone.
    -- Do NOT advance last_subscription_event_occurred_at.

    UPDATE private.billing_provider_events e
    SET
      company_id = v_company_id,
      external_subscription_id = v_subscription_id,
      processing_status = 'processed',
      processed_at = v_now,
      error_sanitized = NULL
    WHERE e.id = v_row.id;

    outcome := 'applied';
    inbox_event_id := v_row.id;
    processing_status := 'processed';
    company_id := v_company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Authoritative subscription-state ordering gate
  IF v_bill.last_subscription_event_occurred_at IS NOT NULL THEN
    IF v_row.provider_created_at < v_bill.last_subscription_event_occurred_at THEN
      UPDATE private.billing_provider_events e
      SET
        company_id = COALESCE(e.company_id, v_company_id),
        processing_status = 'ignored',
        processed_at = v_now,
        error_sanitized = 'stale_event'
      WHERE e.id = v_row.id;

      outcome := 'stale';
      inbox_event_id := v_row.id;
      processing_status := 'ignored';
      company_id := v_company_id;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  -- Canonical incoming provider snapshot fingerprint (shared helper; no fork).
  -- Provider fence validation must run before any processed terminalization.
  v_incoming_snapshot_fp := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subscription_id,
    v_customer_id,
    v_price_id,
    v_paddle_status,
    v_period_start,
    v_period_end,
    v_cancel_at_period_end,
    v_canceled_at
  );

  -- Equal webhook event watermark: enforce provider-state fence first.
  -- Local business-state equivalence must NOT bypass the fence.
  IF v_bill.last_subscription_event_occurred_at IS NOT NULL
    AND v_row.provider_created_at = v_bill.last_subscription_event_occurred_at THEN
    -- 3A fence pair integrity
    IF (
      v_bill.last_provider_subscription_updated_at IS NULL
      AND v_bill.last_provider_subscription_state_fingerprint IS NOT NULL
    ) OR (
      v_bill.last_provider_subscription_updated_at IS NOT NULL
      AND v_bill.last_provider_subscription_state_fingerprint IS NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY';
    END IF;

    -- 3B legacy uninitialized fence (watermark already non-NULL here)
    IF v_bill.last_provider_subscription_updated_at IS NULL
      AND v_bill.last_provider_subscription_state_fingerprint IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_STATE_FENCE_UNINITIALIZED';
    END IF;

    -- 3C incoming provider object older than fence
    IF v_provider_updated_at < v_bill.last_provider_subscription_updated_at THEN
      UPDATE private.billing_provider_events e
      SET
        company_id = COALESCE(e.company_id, v_company_id),
        processing_status = 'ignored',
        processed_at = v_now,
        error_sanitized = 'stale_provider_state'
      WHERE e.id = v_row.id;

      -- Map to contract-compatible webhook outcome `stale` (ignored terminal).
      outcome := 'stale';
      inbox_event_id := v_row.id;
      processing_status := 'ignored';
      company_id := v_company_id;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    -- 3D same event clock + newer provider object version → fail closed
    IF v_provider_updated_at > v_bill.last_provider_subscription_updated_at THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS';
    END IF;

    -- 3E same provider version + different snapshot
    IF v_provider_updated_at = v_bill.last_provider_subscription_updated_at
      AND v_incoming_snapshot_fp IS DISTINCT FROM
        v_bill.last_provider_subscription_state_fingerprint
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS';
    END IF;

    -- 3F same provider version + same snapshot → shared applicator authority
    -- (already_applied or repaired_same_version). No bootstrap. No watermark advance.
    SELECT a.outcome
    INTO v_apply_out
    FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company_id,
      v_subscription_id,
      v_customer_id,
      v_price_id,
      v_paddle_status,
      v_period_start,
      v_period_end,
      v_cancel_at_period_end,
      v_canceled_at,
      v_provider_updated_at,
      FALSE, -- never bootstrap on equal-watermark path
      v_now
    ) a;

    IF v_apply_out IS DISTINCT FROM 'already_applied'
      AND v_apply_out IS DISTINCT FROM 'repaired_same_version'
      AND v_apply_out IS DISTINCT FROM 'applied'
    THEN
      -- Unexpected internal outcome on equal-version/same-fp path.
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_INVALID_REQUEST';
    END IF;

    UPDATE private.billing_provider_events e
    SET
      company_id = v_company_id,
      external_subscription_id = v_subscription_id,
      processing_status = 'processed',
      processed_at = v_now,
      error_sanitized = NULL
    WHERE e.id = v_row.id;

    -- Do NOT advance webhook watermark (already equal).
    -- Normalize successful internal outcomes to contract-compatible `applied`.
    outcome := 'applied';
    inbox_event_id := v_row.id;
    processing_status := 'processed';
    company_id := v_company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Non-equal event timestamp path (watermark NULL or strictly newer event clock).
  -- Explicit fence bootstrap policy for webhook:
  -- allow only when fence pair is NULL and there is no prior authoritative
  -- subscription webhook state (true first-link OR txn-link without sub apply).
  -- Legacy linked rows with watermark set but fence NULL => fail-closed.
  v_allow_bootstrap := (
    v_bill.last_provider_subscription_updated_at IS NULL
    AND v_bill.last_provider_subscription_state_fingerprint IS NULL
    AND (
      v_bill.external_subscription_id IS NULL
      OR v_bill.last_subscription_event_occurred_at IS NULL
    )
  );

  SELECT a.outcome
  INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company_id,
    v_subscription_id,
    v_customer_id,
    v_price_id,
    v_paddle_status,
    v_period_start,
    v_period_end,
    v_cancel_at_period_end,
    v_canceled_at,
    v_provider_updated_at,
    v_allow_bootstrap,
    v_now
  ) a;

  IF v_apply_out = 'stale_provider_state' THEN
    -- Event clock may be newer; provider object state is older than fence.
    -- Do NOT mutate business/fence/snapshot; do NOT advance webhook watermark.
    UPDATE private.billing_provider_events e
    SET
      company_id = COALESCE(e.company_id, v_company_id),
      processing_status = 'ignored',
      processed_at = v_now,
      error_sanitized = 'stale_provider_state'
    WHERE e.id = v_row.id;

    -- Contract-compatible webhook outcome (Edge/workflows allowlist: stale).
    outcome := 'stale';
    inbox_event_id := v_row.id;
    processing_status := 'ignored';
    company_id := v_company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Successful shared apply (applied|already_applied|repaired_same_version):
  -- advance WEBHOOK watermark only (reconciliation never writes this).
  UPDATE private.company_billing b
  SET
    last_subscription_event_occurred_at = v_row.provider_created_at,
    updated_at = v_now
  WHERE b.company_id = v_company_id;

  UPDATE private.billing_provider_events e
  SET
    company_id = v_company_id,
    external_subscription_id = v_subscription_id,
    processing_status = 'processed',
    processed_at = v_now,
    error_sanitized = NULL
  WHERE e.id = v_row.id;

  -- Normalize richer internal outcomes to existing webhook contract `applied`.
  outcome := 'applied';
  inbox_event_id := v_row.id;
  processing_status := 'processed';
  company_id := v_company_id;
  attempt_count := v_row.attempt_count;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) IS
  '14C-2J B2/C-FIX1: apply verified paddle/test inbox event via shared applicator. '
  'Equal event watermark enforces provider updated_at + snapshot fence before any '
  'processed terminal. Webhook outcomes normalized to applied|stale|… for processor '
  'contract; error_sanitized retains stale_provider_state. Watermark webhook-only.';

ALTER FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) OWNER TO postgres;

REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM service_role;
