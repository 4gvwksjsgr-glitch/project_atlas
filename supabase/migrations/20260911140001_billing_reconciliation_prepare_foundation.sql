-- =============================================================================
-- Project Atlas — Step 14C-2J Phase B1
-- Billing reconciliation schema foundation + prepare RPC (local DB only).
--
-- Adds:
--   - private.company_billing.last_provider_subscription_updated_at
--     (shared monotonic provider subscription-state freshness fence;
--      source = Paddle subscription.updated_at; NOT the webhook event watermark)
--   - reconciliation audit metadata columns
--   - private.prepare_company_billing_reconciliation
--   - public.prepare_company_billing_reconciliation_server (service_role only)
--
-- Does NOT:
--   - populate the provider-state fence
--   - write last_subscription_event_occurred_at (webhook watermark)
--   - change webhook apply / entitlement behavior
--   - call Paddle / deploy Edge / arm scheduler
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Schema: provider-state fence + reconciliation audit metadata
-- -----------------------------------------------------------------------------
ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_provider_subscription_updated_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN private.company_billing.last_provider_subscription_updated_at IS
  'Step 14C-2J B1: shared monotonic subscription-state freshness fence. '
  'Source = Paddle subscription.updated_at. Separate from webhook event watermark '
  'last_subscription_event_occurred_at (which reconciliation MUST NEVER write). '
  'Do NOT reuse provider_object_version(_at) for ordering. '
  'Future shared applicator (webhook + reconciliation) may advance this field. '
  'B1 does NOT populate it; existing rows bootstrap as NULL intentionally.';

ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_reconciled_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN private.company_billing.last_reconciled_at IS
  'Step 14C-2J B1: timestamp of the most recent reconciliation attempt/result. '
  'B1 prepare does not write this column.';

ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_reconciliation_result TEXT NULL;

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_last_reconciliation_result_allowed;

ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_last_reconciliation_result_allowed
  CHECK (
    last_reconciliation_result IS NULL
    OR last_reconciliation_result IN (
      'in_sync',
      'updated',
      'stale_snapshot',
      'busy',
      'conflict',
      'not_found',
      'invalid_provider_response',
      'unsupported_state',
      'catalog_mismatch',
      'provider_error',
      'unlinked',
      'stale_provider_state'
    )
  );

COMMENT ON COLUMN private.company_billing.last_reconciliation_result IS
  'Step 14C-2J B1: V1 reconciliation outcome vocabulary (NULL until a later phase writes). '
  'Allowlist CHECK matches repository billing enum conventions. '
  'B1 prepare does not write this column.';

ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_reconciliation_error_sanitized TEXT NULL;

COMMENT ON COLUMN private.company_billing.last_reconciliation_error_sanitized IS
  'Step 14C-2J B1: sanitized error from the most recent reconciliation attempt. '
  'No secrets/raw provider payloads. B1 prepare does not write this column.';

ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_reconciliation_provider_updated_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN private.company_billing.last_reconciliation_provider_updated_at IS
  'Step 14C-2J B1: audit observation of Paddle subscription.updated_at from the most '
  'recent reconciliation attempt/result. NOT the ordering fence. '
  'Ordering fence = last_provider_subscription_updated_at. '
  'B1 prepare does not write this column.';

-- -----------------------------------------------------------------------------
-- Future shared applicator fence rules (documented for B2/C; NOT enforced in B1)
-- -----------------------------------------------------------------------------
-- stored last_provider_subscription_updated_at IS NULL
--   => first valid provider snapshot may bootstrap the fence
-- incoming updated_at < stored fence
--   => stale_provider_state; no business mutation
-- incoming == stored + identical normalized fingerprint
--   => idempotent / no-op
-- incoming == stored + different normalized fingerprint
--   => ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS; fail closed
-- incoming > stored
--   => eligible to apply and advance fence atomically with business state
-- Webhook inbox processing_status remains:
--   received | processing | processed | ignored | failed
-- (no new inbox status in B1; future stale_provider_state uses existing terminals)

-- -----------------------------------------------------------------------------
-- Fingerprint helpers (deterministic; identity vs business-state concurrency)
-- Canonical serialization: ordered jsonb_build_array(... )::text then md5.
-- Preserves NULL vs '', embedded '|', escaping, and BOOLEAN true/false/null.
-- -----------------------------------------------------------------------------
-- Timestamps: UTC fixed format; NULL input remains SQL NULL (JSON null in array).
CREATE OR REPLACE FUNCTION private.billing_reconciliation_ts_token(
  p_ts TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_ts IS NULL THEN NULL
    ELSE to_char(p_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'
  END;
$$;

COMMENT ON FUNCTION private.billing_reconciliation_ts_token(TIMESTAMPTZ) IS
  'Step 14C-2J B1-FIX1: UTC timestamp token for reconciliation fingerprints. '
  'NULL input returns SQL NULL (not empty string) so jsonb arrays preserve JSON null.';

ALTER FUNCTION private.billing_reconciliation_ts_token(TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_reconciliation_ts_token(TIMESTAMPTZ)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_reconciliation_ts_token(TIMESTAMPTZ)
  FROM anon;
REVOKE ALL ON FUNCTION private.billing_reconciliation_ts_token(TIMESTAMPTZ)
  FROM authenticated;

-- LINKAGE fingerprint (identity only), fixed order:
--   provider_code, provider_environment, external_customer_id,
--   external_subscription_id, external_price_id
CREATE OR REPLACE FUNCTION private.billing_reconciliation_linkage_fingerprint(
  p_provider_code TEXT,
  p_provider_environment TEXT,
  p_external_customer_id TEXT,
  p_external_subscription_id TEXT,
  p_external_price_id TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT pg_catalog.md5(
    pg_catalog.jsonb_build_array(
      p_provider_code,
      p_provider_environment,
      p_external_customer_id,
      p_external_subscription_id,
      p_external_price_id
    )::text
  );
$$;

COMMENT ON FUNCTION private.billing_reconciliation_linkage_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT
) IS
  'Step 14C-2J B1-FIX1: deterministic linkage fingerprint via ordered jsonb array. '
  'Fields: provider_code, provider_environment, external_customer_id, '
  'external_subscription_id, external_price_id. NULL ≠ empty string; `|`-safe.';

ALTER FUNCTION private.billing_reconciliation_linkage_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_reconciliation_linkage_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_reconciliation_linkage_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT
) FROM anon;
REVOKE ALL ON FUNCTION private.billing_reconciliation_linkage_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT
) FROM authenticated;

-- LOCAL STATE fingerprint (business state relevant to reconcile concurrency):
-- company_subscriptions: plan_code, status, entitlement_origin
-- company_billing: subscription_status, payment_status, provider_access_status,
--   external_price_id, current_period_start/end, cancel_at_period_end, canceled_at,
--   provider_access_ends_at, grace_ends_at, sync_status, last_sync_result,
--   last_provider_subscription_updated_at
-- Excludes: generic updated_at, webhook watermark, reconciliation audit metadata,
--   opaque provider_object_version(_at), raw payloads.
CREATE OR REPLACE FUNCTION private.billing_reconciliation_local_state_fingerprint(
  p_plan_code TEXT,
  p_subscription_status TEXT,
  p_entitlement_origin TEXT,
  p_billing_subscription_status TEXT,
  p_payment_status TEXT,
  p_provider_access_status TEXT,
  p_external_price_id TEXT,
  p_current_period_start TIMESTAMPTZ,
  p_current_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ,
  p_provider_access_ends_at TIMESTAMPTZ,
  p_grace_ends_at TIMESTAMPTZ,
  p_sync_status TEXT,
  p_last_sync_result TEXT,
  p_last_provider_subscription_updated_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT pg_catalog.md5(
    pg_catalog.jsonb_build_array(
      p_plan_code,
      p_subscription_status,
      p_entitlement_origin,
      p_billing_subscription_status,
      p_payment_status,
      p_provider_access_status,
      p_external_price_id,
      private.billing_reconciliation_ts_token(p_current_period_start),
      private.billing_reconciliation_ts_token(p_current_period_end),
      p_cancel_at_period_end,
      private.billing_reconciliation_ts_token(p_canceled_at),
      private.billing_reconciliation_ts_token(p_provider_access_ends_at),
      private.billing_reconciliation_ts_token(p_grace_ends_at),
      p_sync_status,
      p_last_sync_result,
      private.billing_reconciliation_ts_token(p_last_provider_subscription_updated_at)
    )::text
  );
$$;

COMMENT ON FUNCTION private.billing_reconciliation_local_state_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
  TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2J B1-FIX1: deterministic local-state fingerprint via ordered jsonb array. '
  'BOOLEAN kept as JSON true/false/null; timestamps via UTC token (NULL→JSON null). '
  'Excludes volatile updated_at, webhook watermark, reconcile audit, raw payloads.';

ALTER FUNCTION private.billing_reconciliation_local_state_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
  TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_reconciliation_local_state_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
  TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_reconciliation_local_state_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
  TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.billing_reconciliation_local_state_fingerprint(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ,
  TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.prepare_company_billing_reconciliation
-- Short local read/lock only. Does NOT call Paddle. Does NOT mutate billing.
-- Lock order matches billing apply: company_subscriptions → company_billing.
-- Future apply re-locks and rechecks fingerprints / anchors.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.prepare_company_billing_reconciliation(
  p_company_id UUID,
  p_actor_user_id UUID
)
RETURNS TABLE (
  company_id UUID,
  provider_code TEXT,
  provider_environment TEXT,
  external_subscription_id TEXT,
  external_customer_id TEXT,
  external_price_id TEXT,
  expected_webhook_watermark TIMESTAMPTZ,
  expected_provider_state_version TIMESTAMPTZ,
  expected_linkage_fingerprint TEXT,
  expected_local_state_fingerprint TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_sub public.company_subscriptions%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_linkage TEXT;
  v_local TEXT;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  -- Minimum locking for a consistent prepare snapshot; released at txn end.
  -- Do NOT hold locks across a later Paddle HTTP call (that is outside this RPC).
  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  IF NOT private.is_company_member(p_company_id, p_actor_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  -- Linked-state gates (DB-resolved only; client cannot inject provider IDs).
  IF v_bill.external_subscription_id IS NULL
    OR v_bill.external_customer_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_RECONCILIATION_UNLINKED';
  END IF;

  IF v_bill.provider_code IS DISTINCT FROM 'paddle' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_PROVIDER';
  END IF;

  IF v_bill.provider_environment IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_ENVIRONMENT';
  END IF;

  v_linkage := private.billing_reconciliation_linkage_fingerprint(
    v_bill.provider_code,
    v_bill.provider_environment,
    v_bill.external_customer_id,
    v_bill.external_subscription_id,
    v_bill.external_price_id
  );

  v_local := private.billing_reconciliation_local_state_fingerprint(
    v_sub.plan_code,
    v_sub.status,
    v_sub.entitlement_origin,
    v_bill.subscription_status,
    v_bill.payment_status,
    v_bill.provider_access_status,
    v_bill.external_price_id,
    v_bill.current_period_start,
    v_bill.current_period_end,
    v_bill.cancel_at_period_end,
    v_bill.canceled_at,
    v_bill.provider_access_ends_at,
    v_bill.grace_ends_at,
    v_bill.sync_status,
    v_bill.last_sync_result,
    v_bill.last_provider_subscription_updated_at
  );

  company_id := v_bill.company_id;
  provider_code := v_bill.provider_code;
  provider_environment := v_bill.provider_environment;
  external_subscription_id := v_bill.external_subscription_id;
  external_customer_id := v_bill.external_customer_id;
  external_price_id := v_bill.external_price_id;
  expected_webhook_watermark := v_bill.last_subscription_event_occurred_at;
  expected_provider_state_version := v_bill.last_provider_subscription_updated_at;
  expected_linkage_fingerprint := v_linkage;
  expected_local_state_fingerprint := v_local;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.prepare_company_billing_reconciliation(UUID, UUID) IS
  'Step 14C-2J B1: owner-gated prepare for paddle/test linked reconciliation. '
  'Returns DB-resolved anchors + fingerprints. Reads but does not modify webhook '
  'watermark or provider-state fence. No Paddle HTTP. No entitlement mutation.';

ALTER FUNCTION private.prepare_company_billing_reconciliation(UUID, UUID)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.prepare_company_billing_reconciliation(UUID, UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.prepare_company_billing_reconciliation(UUID, UUID)
  FROM anon;
REVOKE ALL ON FUNCTION private.prepare_company_billing_reconciliation(UUID, UUID)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.prepare_company_billing_reconciliation_server (service_role only)
-- Edge will verify JWT then pass jwt.sub as p_actor_user_id.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_company_billing_reconciliation_server(
  p_company_id UUID,
  p_actor_user_id UUID
)
RETURNS TABLE (
  company_id UUID,
  provider_code TEXT,
  provider_environment TEXT,
  external_subscription_id TEXT,
  external_customer_id TEXT,
  external_price_id TEXT,
  expected_webhook_watermark TIMESTAMPTZ,
  expected_provider_state_version TIMESTAMPTZ,
  expected_linkage_fingerprint TEXT,
  expected_local_state_fingerprint TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.prepare_company_billing_reconciliation(
    p_company_id,
    p_actor_user_id
  );
END;
$$;

COMMENT ON FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID) IS
  'Step 14C-2J B1: service_role only. EF authenticates JWT then passes actor UUID.';

ALTER FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID)
  FROM anon;
REVOKE ALL ON FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_company_billing_reconciliation_server(UUID, UUID)
  TO service_role;
