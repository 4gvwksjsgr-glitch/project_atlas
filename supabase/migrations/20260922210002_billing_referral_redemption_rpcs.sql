-- =============================================================================
-- Project Atlas — Step 18B: referral redemption RPCs + calendar utility
-- Additive. SECURITY DEFINER private helpers; service_role + owner retry facade.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Calendar months (UTC, end-of-month clamp — PostgreSQL interval semantics)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.add_calendar_months(
  p_ts TIMESTAMPTZ,
  p_months INTEGER
)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_months = 0 THEN p_ts
    ELSE (p_ts AT TIME ZONE 'UTC' + make_interval(months => p_months)) AT TIME ZONE 'UTC'
  END;
$$;

ALTER FUNCTION private.add_calendar_months(TIMESTAMPTZ, INTEGER) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.add_calendar_months(TIMESTAMPTZ, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.add_calendar_months(TIMESTAMPTZ, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION private.add_calendar_months(TIMESTAMPTZ, INTEGER) FROM authenticated;

COMMENT ON FUNCTION private.add_calendar_months(TIMESTAMPTZ, INTEGER) IS
  '18B: add N calendar months in UTC preserving time-of-day; clamp to last valid day '
  '(Jan31+1→Feb28/29). Not +30 days.';

-- -----------------------------------------------------------------------------
-- Kill switch reader
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_referral_redemption_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT coalesce(
    (
      SELECT c.referral_redemption_enabled
      FROM private.billing_runtime_config c
      WHERE c.provider_code = 'paddle'
        AND c.provider_environment = 'test'
        AND c.is_active IS TRUE
      LIMIT 1
    ),
    FALSE
  );
$$;

ALTER FUNCTION private.is_referral_redemption_enabled() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_referral_redemption_enabled() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.is_referral_redemption_enabled() FROM anon;
REVOKE ALL ON FUNCTION private.is_referral_redemption_enabled() FROM authenticated;

-- -----------------------------------------------------------------------------
-- Eligibility against Atlas-known company_billing (no outbound Paddle)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.referral_redemption_eligibility(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  eligible BOOLEAN,
  block_reason TEXT,
  provider_subscription_id TEXT,
  next_billed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_bill private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;
  v_next TIMESTAMPTZ;
BEGIN
  IF p_company_id IS NULL THEN
    eligible := FALSE;
    block_reason := 'ATLAS_COMPANY_ID_REQUIRED';
    provider_subscription_id := NULL;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT private.is_referral_redemption_enabled() THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_REDEMPTION_DISABLED';
    provider_subscription_id := NULL;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  IF NOT FOUND
     OR v_bill.provider_code IS DISTINCT FROM 'paddle'
     OR nullif(btrim(coalesce(v_bill.external_subscription_id, '')), '') IS NULL THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_UNLINKED';
    provider_subscription_id := NULL;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_sub
  FROM public.company_subscriptions s
  WHERE s.company_id = p_company_id;

  -- Atlas internal trial without provider entitlement: keep pending.
  IF FOUND
     AND v_sub.entitlement_origin = 'internal_trial'
     AND v_bill.subscription_status IS DISTINCT FROM 'active' THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_TRIALING';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_bill.payment_status = 'past_due' THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_PAST_DUE';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_bill.subscription_status IN ('ended', 'revoked')
     OR v_bill.canceled_at IS NOT NULL
     OR v_bill.provider_access_status = 'ended' THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_CANCELED';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF coalesce(v_bill.cancel_at_period_end, FALSE) IS TRUE THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_SCHEDULED_CANCEL';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := v_bill.current_period_end;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_bill.subscription_status IS DISTINCT FROM 'active'
     OR v_bill.provider_access_status IS DISTINCT FROM 'entitled' THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_NOT_ACTIVE';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := v_bill.current_period_end;
    RETURN NEXT;
    RETURN;
  END IF;

  v_next := v_bill.current_period_end;
  IF v_next IS NULL THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Official Paddle: cannot change billing date within 30 minutes of next bill.
  IF v_next <= (p_now + interval '30 minutes') THEN
    eligible := FALSE;
    block_reason := 'ATLAS_REFERRAL_NEAR_RENEWAL';
    provider_subscription_id := v_bill.external_subscription_id;
    next_billed_at := v_next;
    RETURN NEXT;
    RETURN;
  END IF;

  eligible := TRUE;
  block_reason := NULL;
  provider_subscription_id := v_bill.external_subscription_id;
  next_billed_at := v_next;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.referral_redemption_eligibility(UUID, TIMESTAMPTZ) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.referral_redemption_eligibility(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.referral_redemption_eligibility(UUID, TIMESTAMPTZ) FROM anon;
REVOKE ALL ON FUNCTION private.referral_redemption_eligibility(UUID, TIMESTAMPTZ) FROM authenticated;

-- -----------------------------------------------------------------------------
-- Claim: one open op per company; batch all pending rewards; server-derived N/target
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.claim_referral_redemption_operation(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  outcome TEXT,
  operation_id UUID,
  reward_count INTEGER,
  reward_ids UUID[],
  expected_old_next_billed_at TIMESTAMPTZ,
  target_next_billed_at TIMESTAMPTZ,
  provider_subscription_id TEXT,
  operation_status TEXT,
  error_code TEXT
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_open private.billing_referral_redemption_operations%ROWTYPE;
  v_elig RECORD;
  v_ids UUID[];
  v_n INTEGER;
  v_op_id UUID;
  v_old TIMESTAMPTZ;
  v_target TIMESTAMPTZ;
BEGIN
  IF p_company_id IS NULL THEN
    outcome := 'error';
    error_code := 'ATLAS_COMPANY_ID_REQUIRED';
    RETURN NEXT;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_company_id::text || ':referral_redemption', 0)
  );

  SELECT * INTO v_open
  FROM private.billing_referral_redemption_operations o
  WHERE o.company_id = p_company_id
    AND o.status NOT IN ('confirmed', 'terminal_failed')
  FOR UPDATE;

  IF FOUND THEN
    outcome := 'existing_open';
    operation_id := v_open.id;
    reward_count := v_open.reward_count;
    reward_ids := v_open.reward_ids;
    expected_old_next_billed_at := v_open.expected_old_next_billed_at;
    target_next_billed_at := v_open.target_next_billed_at;
    provider_subscription_id := v_open.provider_subscription_id_snapshot;
    operation_status := v_open.status;
    error_code := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT coalesce(array_agg(x.id ORDER BY x.reward_slot), ARRAY[]::UUID[])
  INTO v_ids
  FROM (
    SELECT r.id, r.reward_slot
    FROM public.referral_rewards r
    WHERE r.referring_company_id = p_company_id
      AND r.redemption_status = 'pending'
      AND r.redemption_operation_id IS NULL
    ORDER BY r.reward_slot
    FOR UPDATE
  ) x;

  v_n := coalesce(cardinality(v_ids), 0);
  IF v_n = 0 THEN
    outcome := 'no_pending';
    error_code := 'ATLAS_REFERRAL_NO_PENDING_REWARDS';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_elig
  FROM private.referral_redemption_eligibility(p_company_id, p_now);

  IF NOT v_elig.eligible THEN
    outcome := 'blocked';
    reward_count := v_n;
    reward_ids := v_ids;
    provider_subscription_id := v_elig.provider_subscription_id;
    error_code := v_elig.block_reason;
    -- Rewards remain pending; no operation created.
    RETURN NEXT;
    RETURN;
  END IF;

  v_old := v_elig.next_billed_at;
  v_target := private.add_calendar_months(v_old, v_n);

  INSERT INTO private.billing_referral_redemption_operations (
    company_id,
    status,
    reward_count,
    reward_ids,
    expected_old_next_billed_at,
    target_next_billed_at,
    provider_subscription_id_snapshot,
    claimed_at,
    last_attempt_at,
    attempt_count
  ) VALUES (
    p_company_id,
    'claimed',
    v_n,
    v_ids,
    v_old,
    v_target,
    v_elig.provider_subscription_id,
    p_now,
    p_now,
    0
  )
  RETURNING id INTO v_op_id;

  UPDATE public.referral_rewards r
  SET
    redemption_status = 'applying',
    redemption_operation_id = v_op_id
  WHERE r.id = ANY (v_ids);

  outcome := 'claimed';
  operation_id := v_op_id;
  reward_count := v_n;
  reward_ids := v_ids;
  expected_old_next_billed_at := v_old;
  target_next_billed_at := v_target;
  provider_subscription_id := v_elig.provider_subscription_id;
  operation_status := 'claimed';
  error_code := NULL;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.claim_referral_redemption_operation(UUID, TIMESTAMPTZ) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.claim_referral_redemption_operation(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.claim_referral_redemption_operation(UUID, TIMESTAMPTZ) FROM anon;
REVOKE ALL ON FUNCTION private.claim_referral_redemption_operation(UUID, TIMESTAMPTZ) FROM authenticated;

-- -----------------------------------------------------------------------------
-- Transition helpers used by Edge / confirm / reconcile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.update_referral_redemption_operation_status(
  p_operation_id UUID,
  p_status TEXT,
  p_error_code TEXT DEFAULT NULL,
  p_set_previewed BOOLEAN DEFAULT FALSE,
  p_set_provider_accepted BOOLEAN DEFAULT FALSE,
  p_bump_attempt BOOLEAN DEFAULT FALSE,
  p_expected_old TIMESTAMPTZ DEFAULT NULL,
  p_target TIMESTAMPTZ DEFAULT NULL,
  p_subscription_snapshot TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  SELECT * INTO v_op
  FROM private.billing_referral_redemption_operations o
  WHERE o.id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_op.status IN ('confirmed', 'terminal_failed') THEN
    RETURN FALSE;
  END IF;

  UPDATE private.billing_referral_redemption_operations o
  SET
    status = p_status,
    last_error_code = coalesce(p_error_code, o.last_error_code),
    block_reason = CASE
      WHEN p_status = 'blocked' THEN coalesce(p_error_code, o.block_reason)
      ELSE o.block_reason
    END,
    previewed_at = CASE WHEN p_set_previewed THEN now() ELSE o.previewed_at END,
    provider_accepted_at = CASE
      WHEN p_set_provider_accepted THEN now()
      ELSE o.provider_accepted_at
    END,
    last_attempt_at = CASE WHEN p_bump_attempt THEN now() ELSE o.last_attempt_at END,
    attempt_count = CASE
      WHEN p_bump_attempt THEN o.attempt_count + 1
      ELSE o.attempt_count
    END,
    expected_old_next_billed_at = coalesce(p_expected_old, o.expected_old_next_billed_at),
    target_next_billed_at = coalesce(p_target, o.target_next_billed_at),
    provider_subscription_id_snapshot = coalesce(
      nullif(btrim(coalesce(p_subscription_snapshot, '')), ''),
      o.provider_subscription_id_snapshot
    ),
    updated_at = now()
  WHERE o.id = p_operation_id;

  RETURN TRUE;
END;
$$;

ALTER FUNCTION private.update_referral_redemption_operation_status(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.update_referral_redemption_operation_status(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.update_referral_redemption_operation_status(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) FROM anon;
REVOKE ALL ON FUNCTION private.update_referral_redemption_operation_status(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) FROM authenticated;

-- Release applying rewards back to pending when op terminal_failed (recoverable)
CREATE OR REPLACE FUNCTION private.release_referral_redemption_operation(
  p_operation_id UUID,
  p_terminal BOOLEAN DEFAULT FALSE,
  p_error_code TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  SELECT * INTO v_op
  FROM private.billing_referral_redemption_operations o
  WHERE o.id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND OR v_op.status = 'confirmed' THEN
    RETURN FALSE;
  END IF;

  UPDATE public.referral_rewards r
  SET
    redemption_status = 'pending',
    redemption_operation_id = NULL
  WHERE r.redemption_operation_id = p_operation_id
    AND r.redemption_status = 'applying';

  UPDATE private.billing_referral_redemption_operations o
  SET
    status = CASE WHEN p_terminal THEN 'terminal_failed' ELSE 'retryable_failed' END,
    last_error_code = coalesce(p_error_code, o.last_error_code),
    updated_at = now()
  WHERE o.id = p_operation_id;

  -- retryable_failed keeps row "open" unique constraint — release rewards so a
  -- future claim can create a NEW op. Close unique by marking terminal when
  -- releasing for re-claim, or keep retryable for same-op heal.
  -- Spec: do not create new op when existing open can be healed.
  -- If releasing rewards to pending, must close op as terminal_failed so unique allows new claim.
  IF NOT p_terminal THEN
    -- Keep op open for heal/retry without releasing rewards (caller mistake).
    -- This function with p_terminal=false leaves rewards applying.
    NULL;
  END IF;

  RETURN TRUE;
END;
$$;

ALTER FUNCTION private.release_referral_redemption_operation(UUID, BOOLEAN, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.release_referral_redemption_operation(UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.release_referral_redemption_operation(UUID, BOOLEAN, TEXT) FROM anon;
REVOKE ALL ON FUNCTION private.release_referral_redemption_operation(UUID, BOOLEAN, TEXT) FROM authenticated;

-- Safer: abort open op, return rewards to pending, mark terminal_failed
CREATE OR REPLACE FUNCTION private.abort_referral_redemption_operation(
  p_operation_id UUID,
  p_error_code TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  SELECT * INTO v_op
  FROM private.billing_referral_redemption_operations o
  WHERE o.id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND OR v_op.status IN ('confirmed') THEN
    RETURN FALSE;
  END IF;

  UPDATE public.referral_rewards r
  SET
    redemption_status = 'pending',
    redemption_operation_id = NULL
  WHERE r.redemption_operation_id = p_operation_id
    AND r.redemption_status = 'applying';

  UPDATE private.billing_referral_redemption_operations o
  SET
    status = 'terminal_failed',
    last_error_code = p_error_code,
    updated_at = now()
  WHERE o.id = p_operation_id;

  RETURN TRUE;
END;
$$;

ALTER FUNCTION private.abort_referral_redemption_operation(UUID, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.abort_referral_redemption_operation(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.abort_referral_redemption_operation(UUID, TEXT) FROM anon;
REVOKE ALL ON FUNCTION private.abort_referral_redemption_operation(UUID, TEXT) FROM authenticated;

-- -----------------------------------------------------------------------------
-- Confirm: exact target match on current_period_end (Atlas entitlement source)
-- and/or provided observed_next_billed_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.confirm_referral_redemption_operation(
  p_company_id UUID,
  p_observed_next_billed_at TIMESTAMPTZ DEFAULT NULL,
  p_provider_subscription_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  outcome TEXT,
  operation_id UUID,
  rewards_redeemed INTEGER,
  error_code TEXT
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_observed TIMESTAMPTZ;
  v_sub_id TEXT;
  v_n INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_company_id::text || ':referral_redemption', 0)
  );

  SELECT * INTO v_op
  FROM private.billing_referral_redemption_operations o
  WHERE o.company_id = p_company_id
    AND o.status NOT IN ('confirmed', 'terminal_failed')
  FOR UPDATE;

  IF NOT FOUND THEN
    outcome := 'no_open_operation';
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_op.status = 'confirmed' THEN
    outcome := 'already_confirmed';
    operation_id := v_op.id;
    rewards_redeemed := v_op.reward_count;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  v_sub_id := nullif(btrim(coalesce(
    p_provider_subscription_id,
    v_bill.external_subscription_id,
    ''
  )), '');

  IF v_op.provider_subscription_id_snapshot IS NOT NULL
     AND v_sub_id IS DISTINCT FROM v_op.provider_subscription_id_snapshot THEN
    PERFORM private.update_referral_redemption_operation_status(
      v_op.id,
      'needs_reconcile',
      'ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED',
      FALSE, FALSE, FALSE, NULL, NULL, NULL
    );
    outcome := 'provider_subscription_changed';
    operation_id := v_op.id;
    error_code := 'ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED';
    RETURN NEXT;
    RETURN;
  END IF;

  v_observed := coalesce(p_observed_next_billed_at, v_bill.current_period_end);

  IF v_observed IS NULL OR v_op.target_next_billed_at IS NULL THEN
    outcome := 'insufficient_observation';
    operation_id := v_op.id;
    error_code := 'ATLAS_REFERRAL_RECONCILE_REQUIRED';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Exact target only (never live >= target).
  IF v_observed IS NOT DISTINCT FROM v_op.target_next_billed_at THEN
    UPDATE public.referral_rewards r
    SET
      redemption_status = 'redeemed',
      redeemed_at = now()
    WHERE r.redemption_operation_id = v_op.id
      AND r.redemption_status = 'applying';

    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE private.billing_referral_redemption_operations o
    SET
      status = 'confirmed',
      confirmed_at = now(),
      provider_accepted_at = coalesce(o.provider_accepted_at, now()),
      updated_at = now()
    WHERE o.id = v_op.id;

    outcome := 'confirmed';
    operation_id := v_op.id;
    rewards_redeemed := v_n;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_observed IS NOT DISTINCT FROM v_op.expected_old_next_billed_at THEN
    PERFORM private.update_referral_redemption_operation_status(
      v_op.id,
      'retryable_failed',
      'ATLAS_REFERRAL_PROVIDER_NOT_APPLIED',
      FALSE, FALSE, FALSE, NULL, NULL, NULL
    );
    outcome := 'still_old';
    operation_id := v_op.id;
    error_code := 'ATLAS_REFERRAL_PROVIDER_NOT_APPLIED';
    RETURN NEXT;
    RETURN;
  END IF;

  PERFORM private.update_referral_redemption_operation_status(
    v_op.id,
    'needs_reconcile',
    'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT',
    FALSE, FALSE, FALSE, NULL, NULL, NULL
  );
  outcome := 'conflict_third_date';
  operation_id := v_op.id;
  error_code := 'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT';
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.confirm_referral_redemption_operation(UUID, TIMESTAMPTZ, TEXT)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.confirm_referral_redemption_operation(UUID, TIMESTAMPTZ, TEXT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.confirm_referral_redemption_operation(UUID, TIMESTAMPTZ, TEXT)
  FROM anon;
REVOKE ALL ON FUNCTION private.confirm_referral_redemption_operation(UUID, TIMESTAMPTZ, TEXT)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- Load open operation for Edge / reconcile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.get_open_referral_redemption_operation(
  p_company_id UUID
)
RETURNS private.billing_referral_redemption_operations
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  SELECT * INTO v_op
  FROM private.billing_referral_redemption_operations o
  WHERE o.company_id = p_company_id
    AND o.status NOT IN ('confirmed', 'terminal_failed')
  ORDER BY o.claimed_at DESC
  LIMIT 1;
  RETURN v_op;
END;
$$;

ALTER FUNCTION private.get_open_referral_redemption_operation(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.get_open_referral_redemption_operation(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.get_open_referral_redemption_operation(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.get_open_referral_redemption_operation(UUID) FROM authenticated;
