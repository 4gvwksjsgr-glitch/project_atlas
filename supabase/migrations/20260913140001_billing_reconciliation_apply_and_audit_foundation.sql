-- =============================================================================
-- Project Atlas — Step 14C-2J Phase D1
-- Reconciliation apply + audit finalizer foundation (local source only).
--
-- Adds:
--   - private.apply_company_billing_reconciliation
--   - public.apply_company_billing_reconciliation_server (service_role only)
--   - private.record_company_billing_reconciliation_result
--   - public.record_company_billing_reconciliation_result_server (service_role only)
--
-- Does NOT:
--   - call Paddle / deploy Edge
--   - write last_subscription_event_occurred_at (webhook watermark)
--   - change webhook apply / checkout / processor kill switches
--   - enable first-link / customer discovery
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.apply_company_billing_reconciliation
-- Short locked apply: NOWAIT → owner/linkage revalidation → catalog → shared
-- applicator (reconcile bootstrap) → reconciliation audit metadata.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.apply_company_billing_reconciliation(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_expected_external_subscription_id TEXT,
  p_expected_external_customer_id TEXT,
  p_expected_linkage_fingerprint TEXT,
  p_external_price_id TEXT,
  p_provider_subscription_status TEXT,
  p_current_period_start TIMESTAMPTZ,
  p_current_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ,
  p_provider_updated_at TIMESTAMPTZ
)
RETURNS TABLE (
  result TEXT,
  company_id UUID,
  provider_updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_sub public.company_subscriptions%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_linkage TEXT;
  v_allow_bootstrap BOOLEAN := FALSE;
  v_apply_out TEXT;
  v_err TEXT;
  v_result TEXT;
  v_err_sanitized TEXT;
  v_price_id TEXT;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_expected_external_subscription_id IS NULL
    OR p_expected_external_customer_id IS NULL
    OR p_expected_linkage_fingerprint IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  -- NOWAIT locks: company_subscriptions → company_billing (global order).
  BEGIN
    SELECT *
    INTO v_sub
    FROM public.company_subscriptions cs
    WHERE cs.company_id = p_company_id
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
    END IF;

    SELECT *
    INTO v_bill
    FROM private.company_billing b
    WHERE b.company_id = p_company_id
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
    END IF;
  EXCEPTION
    WHEN lock_not_available THEN
      -- Do not write audit: billing row was not safely locked.
      result := 'busy';
      company_id := p_company_id;
      provider_updated_at := NULL;
      RETURN NEXT;
      RETURN;
  END;

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

  -- Manual entitlement conflict: audit + return before unlinked/catalog/shared.
  IF v_sub.entitlement_origin = 'manual' THEN
    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = 'conflict',
      last_reconciliation_error_sanitized =
        'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT',
      last_reconciliation_provider_updated_at = p_provider_updated_at,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := 'conflict';
    company_id := p_company_id;
    provider_updated_at := p_provider_updated_at;
    RETURN NEXT;
    RETURN;
  END IF;

  -- UNLINKED: required Paddle linkage missing.
  IF v_bill.external_subscription_id IS NULL
    OR v_bill.external_customer_id IS NULL
  THEN
    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = 'unlinked',
      last_reconciliation_error_sanitized = 'ATLAS_BILLING_RECONCILIATION_UNLINKED',
      last_reconciliation_provider_updated_at = NULL,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := 'unlinked';
    company_id := p_company_id;
    provider_updated_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Hard prepare expectation revalidation (linked row still present).
  v_linkage := private.billing_reconciliation_linkage_fingerprint(
    v_bill.provider_code,
    v_bill.provider_environment,
    v_bill.external_customer_id,
    v_bill.external_subscription_id,
    v_bill.external_price_id
  );

  IF v_bill.provider_code IS DISTINCT FROM 'paddle'
    OR v_bill.provider_environment IS DISTINCT FROM 'test'
    OR v_bill.external_subscription_id
      IS DISTINCT FROM p_expected_external_subscription_id
    OR v_bill.external_customer_id
      IS DISTINCT FROM p_expected_external_customer_id
    OR v_linkage IS DISTINCT FROM p_expected_linkage_fingerprint
  THEN
    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = 'stale_snapshot',
      last_reconciliation_error_sanitized = 'ATLAS_BILLING_RECONCILIATION_STALE_SNAPSHOT',
      last_reconciliation_provider_updated_at = NULL,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := 'stale_snapshot';
    company_id := p_company_id;
    provider_updated_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Catalog validation (exact webhook linked-path rule). Price required.
  v_price_id := nullif(btrim(COALESCE(p_external_price_id, '')), '');
  IF v_price_id IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM private.billing_provider_prices p
      WHERE p.provider_code = v_bill.provider_code
        AND p.provider_environment = v_bill.provider_environment
        AND p.external_price_id = v_price_id
        AND p.is_active IS TRUE
    )
  THEN
    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = 'catalog_mismatch',
      last_reconciliation_error_sanitized = 'ATLAS_PROVIDER_PRICE_MISMATCH',
      last_reconciliation_provider_updated_at = p_provider_updated_at,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := 'catalog_mismatch';
    company_id := p_company_id;
    provider_updated_at := p_provider_updated_at;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Reconcile-specific fence bootstrap (linked paddle/test only).
  IF v_bill.last_provider_subscription_updated_at IS NULL
    AND v_bill.last_provider_subscription_state_fingerprint IS NULL
  THEN
    v_allow_bootstrap := TRUE;
  ELSE
    v_allow_bootstrap := FALSE;
  END IF;

  -- Shared applicator in nested subtransaction.
  BEGIN
    SELECT a.outcome
    INTO v_apply_out
    FROM private.apply_normalized_paddle_sandbox_subscription_state(
      p_company_id,
      p_expected_external_subscription_id,
      p_expected_external_customer_id,
      v_price_id,
      p_provider_subscription_status,
      p_current_period_start,
      p_current_period_end,
      COALESCE(p_cancel_at_period_end, FALSE),
      p_canceled_at,
      p_provider_updated_at,
      v_allow_bootstrap,
      v_now
    ) a;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      IF v_err IN (
        'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY',
        'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS',
        'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS',
        'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT',
        'ATLAS_PROVIDER_LINK_CONFLICT'
      ) THEN
        v_result := 'conflict';
        v_err_sanitized := v_err;
      ELSIF v_err IN (
        'ATLAS_PROVIDER_TRIALING_UNSUPPORTED',
        'ATLAS_PROVIDER_STATUS_UNSUPPORTED',
        'ATLAS_PROVIDER_PERIOD_INVALID'
      ) THEN
        v_result := 'unsupported_state';
        v_err_sanitized := v_err;
      ELSIF v_err IN (
        'ATLAS_PROVIDER_UPDATED_AT_REQUIRED',
        'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD'
      ) THEN
        v_result := 'invalid_provider_response';
        v_err_sanitized := v_err;
      ELSE
        RAISE;
      END IF;

      UPDATE private.company_billing b
      SET
        last_reconciled_at = v_now,
        last_reconciliation_result = v_result,
        last_reconciliation_error_sanitized = v_err_sanitized,
        last_reconciliation_provider_updated_at = p_provider_updated_at,
        updated_at = v_now
      WHERE b.company_id = p_company_id;

      result := v_result;
      company_id := p_company_id;
      provider_updated_at := p_provider_updated_at;
      RETURN NEXT;
      RETURN;
  END;

  IF v_apply_out = 'applied' OR v_apply_out = 'repaired_same_version' THEN
    v_result := 'updated';
    v_err_sanitized := NULL;
  ELSIF v_apply_out = 'already_applied' THEN
    v_result := 'in_sync';
    v_err_sanitized := NULL;
  ELSIF v_apply_out = 'stale_provider_state' THEN
    v_result := 'stale_provider_state';
    v_err_sanitized := 'stale_provider_state';
  ELSE
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INTERNAL_ERROR';
  END IF;

  UPDATE private.company_billing b
  SET
    last_reconciled_at = v_now,
    last_reconciliation_result = v_result,
    last_reconciliation_error_sanitized = v_err_sanitized,
    last_reconciliation_provider_updated_at = p_provider_updated_at,
    updated_at = v_now
  WHERE b.company_id = p_company_id;

  -- Never write last_subscription_event_occurred_at (webhook watermark).
  result := v_result;
  company_id := p_company_id;
  provider_updated_at := p_provider_updated_at;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) IS
  'Step 14C-2J D1: owner-gated reconciliation apply for paddle/test linked '
  'companies. NOWAIT locks; hard prepare revalidation; webhook linked-path '
  'catalog check; shared applicator with reconcile fence bootstrap; writes '
  'reconciliation audit only (never webhook watermark).';

ALTER FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM authenticated;
REVOKE ALL ON FUNCTION private.apply_company_billing_reconciliation(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM service_role;

-- -----------------------------------------------------------------------------
-- public.apply_company_billing_reconciliation_server (service_role only)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_company_billing_reconciliation_server(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_expected_external_subscription_id TEXT,
  p_expected_external_customer_id TEXT,
  p_expected_linkage_fingerprint TEXT,
  p_external_price_id TEXT,
  p_provider_subscription_status TEXT,
  p_current_period_start TIMESTAMPTZ,
  p_current_period_end TIMESTAMPTZ,
  p_cancel_at_period_end BOOLEAN,
  p_canceled_at TIMESTAMPTZ,
  p_provider_updated_at TIMESTAMPTZ
)
RETURNS TABLE (
  result TEXT,
  company_id UUID,
  provider_updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.apply_company_billing_reconciliation(
    p_company_id,
    p_actor_user_id,
    p_expected_external_subscription_id,
    p_expected_external_customer_id,
    p_expected_linkage_fingerprint,
    p_external_price_id,
    p_provider_subscription_status,
    p_current_period_start,
    p_current_period_end,
    p_cancel_at_period_end,
    p_canceled_at,
    p_provider_updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) IS
  'Step 14C-2J D1: service_role only. EF authenticates JWT then passes actor.';

ALTER FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_company_billing_reconciliation_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ
) TO service_role;

-- -----------------------------------------------------------------------------
-- private.record_company_billing_reconciliation_result
-- Audit-only finalizer for provider-observed failures after prepare / before
-- a valid shared-apply snapshot. Caller may request ONLY:
--   provider_error | not_found | invalid_provider_response
-- Server may derive: busy | unlinked | stale_snapshot
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.record_company_billing_reconciliation_result(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_expected_external_subscription_id TEXT,
  p_expected_external_customer_id TEXT,
  p_expected_linkage_fingerprint TEXT,
  p_result TEXT,
  p_error_sanitized TEXT,
  p_provider_updated_at TIMESTAMPTZ
)
RETURNS TABLE (
  result TEXT,
  company_id UUID,
  recorded BOOLEAN
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_sub public.company_subscriptions%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_linkage TEXT;
  v_result TEXT;
  v_err TEXT;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_expected_external_subscription_id IS NULL
    OR p_expected_external_customer_id IS NULL
    OR p_expected_linkage_fingerprint IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  -- Caller may request ONLY provider-observed failure results.
  IF p_result IS DISTINCT FROM 'provider_error'
    AND p_result IS DISTINCT FROM 'not_found'
    AND p_result IS DISTINCT FROM 'invalid_provider_response'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  -- Bound sanitized error metadata (matches Edge sanitizeProviderMessage 200).
  v_err := NULL;
  IF p_error_sanitized IS NOT NULL THEN
    v_err := left(btrim(p_error_sanitized), 200);
    IF v_err = '' THEN
      v_err := NULL;
    END IF;
  END IF;

  BEGIN
    SELECT *
    INTO v_sub
    FROM public.company_subscriptions cs
    WHERE cs.company_id = p_company_id
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
    END IF;

    SELECT *
    INTO v_bill
    FROM private.company_billing b
    WHERE b.company_id = p_company_id
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
    END IF;
  EXCEPTION
    WHEN lock_not_available THEN
      result := 'busy';
      company_id := p_company_id;
      recorded := FALSE;
      RETURN NEXT;
      RETURN;
  END;

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

  IF v_bill.external_subscription_id IS NULL
    OR v_bill.external_customer_id IS NULL
  THEN
    v_result := 'unlinked';
    v_err := 'ATLAS_BILLING_RECONCILIATION_UNLINKED';

    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = v_result,
      last_reconciliation_error_sanitized = v_err,
      last_reconciliation_provider_updated_at = NULL,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := v_result;
    company_id := p_company_id;
    recorded := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  v_linkage := private.billing_reconciliation_linkage_fingerprint(
    v_bill.provider_code,
    v_bill.provider_environment,
    v_bill.external_customer_id,
    v_bill.external_subscription_id,
    v_bill.external_price_id
  );

  IF v_bill.provider_code IS DISTINCT FROM 'paddle'
    OR v_bill.provider_environment IS DISTINCT FROM 'test'
    OR v_bill.external_subscription_id
      IS DISTINCT FROM p_expected_external_subscription_id
    OR v_bill.external_customer_id
      IS DISTINCT FROM p_expected_external_customer_id
    OR v_linkage IS DISTINCT FROM p_expected_linkage_fingerprint
  THEN
    v_result := 'stale_snapshot';
    v_err := 'ATLAS_BILLING_RECONCILIATION_STALE_SNAPSHOT';

    UPDATE private.company_billing b
    SET
      last_reconciled_at = v_now,
      last_reconciliation_result = v_result,
      last_reconciliation_error_sanitized = v_err,
      last_reconciliation_provider_updated_at = NULL,
      updated_at = v_now
    WHERE b.company_id = p_company_id;

    result := v_result;
    company_id := p_company_id;
    recorded := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Record caller-requested provider-observed failure.
  UPDATE private.company_billing b
  SET
    last_reconciled_at = v_now,
    last_reconciliation_result = p_result,
    last_reconciliation_error_sanitized = v_err,
    last_reconciliation_provider_updated_at = p_provider_updated_at,
    updated_at = v_now
  WHERE b.company_id = p_company_id;

  result := p_result;
  company_id := p_company_id;
  recorded := TRUE;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2J D1: audit-only reconciliation finalizer. Caller may request '
  'provider_error|not_found|invalid_provider_response only. Derives '
  'busy|unlinked|stale_snapshot. No business/fence/watermark mutation.';

ALTER FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
REVOKE ALL ON FUNCTION private.record_company_billing_reconciliation_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM service_role;

-- -----------------------------------------------------------------------------
-- public.record_company_billing_reconciliation_result_server (service_role only)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_company_billing_reconciliation_result_server(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_expected_external_subscription_id TEXT,
  p_expected_external_customer_id TEXT,
  p_expected_linkage_fingerprint TEXT,
  p_result TEXT,
  p_error_sanitized TEXT,
  p_provider_updated_at TIMESTAMPTZ
)
RETURNS TABLE (
  result TEXT,
  company_id UUID,
  recorded BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.record_company_billing_reconciliation_result(
    p_company_id,
    p_actor_user_id,
    p_expected_external_subscription_id,
    p_expected_external_customer_id,
    p_expected_linkage_fingerprint,
    p_result,
    p_error_sanitized,
    p_provider_updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2J D1: service_role only audit finalizer wrapper.';

ALTER FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_company_billing_reconciliation_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) TO service_role;
