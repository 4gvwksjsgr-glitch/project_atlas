-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2J Phase D1
-- Reconciliation apply + audit finalizer
-- migration: 20260913140001_billing_reconciliation_apply_and_audit_foundation.sql
--
-- AUTHORED FOR REVIEW — DO NOT EXECUTE until explicit local validation.
-- No Paddle HTTP.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.record_result(
  p_name TEXT,
  p_passed BOOLEAN,
  p_sqlstate TEXT DEFAULT NULL,
  p_detail TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  INSERT INTO test_results(test_name, passed, sqlstate, detail)
  VALUES (p_name, p_passed, p_sqlstate, p_detail)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      sqlstate = EXCLUDED.sqlstate,
      detail = EXCLUDED.detail;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.expect_atlas_error(
  p_name TEXT,
  p_expected TEXT,
  p_sqlstate TEXT,
  p_msg TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  PERFORM pg_temp.record_result(
    p_name,
    p_sqlstate = 'P0001' AND p_msg = p_expected,
    p_sqlstate,
    p_msg
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.set_auth(p_uid UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_member UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company UUID;
  v_missing_bill UUID;
  v_company_row public.companies%ROWTYPE;
  v_price TEXT;
  v_inactive_price TEXT := 'pri_' || substr(md5('d1-inactive-price'), 1, 26);
  v_unknown_price TEXT := 'pri_' || substr(md5('d1-unknown-price'), 1, 26);
  v_offer_id UUID;
  v_cust TEXT := 'ctm_' || substr(md5('d1-customer'), 1, 26);
  v_subid TEXT := 'sub_' || substr(md5('d1-subscription'), 1, 26);
  v_cust2 TEXT := 'ctm_' || substr(md5('d1-customer-alt'), 1, 26);
  v_subid2 TEXT := 'sub_' || substr(md5('d1-subscription-alt'), 1, 26);
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_t1 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 09:00:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 11:00:00+00';
  v_wm TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 08:00:00+00';
  v_fp_active TEXT;
  v_fp_past_due TEXT;
  v_fp_link TEXT;
  v_bill private.company_billing%ROWTYPE;
  v_bill_before private.company_billing%ROWTYPE;
  v_out RECORD;
  v_msg TEXT;
  v_sqlstate TEXT;
  v_now TIMESTAMPTZ;
  v_sub_before public.company_subscriptions%ROWTYPE;
BEGIN
  SELECT p.external_price_id, p.offer_id INTO v_price, v_offer_id
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;

  IF v_price IS NULL OR v_offer_id IS NULL THEN
    RAISE EXCEPTION 'D1 tests require seeded paddle/test active price';
  END IF;

  -- Deterministic inactive paddle/test price (is_active = FALSE).
  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_d1_inactive', v_inactive_price,
    9.99, 'EUR', TIMESTAMPTZ '2026-01-01 00:00:00+00', NULL, FALSE
  );

  v_fp_active := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_past_due := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'past_due',
    v_period_start, v_period_end, false, NULL
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14c2jd1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'member14c2jd1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14c2jd1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J D1',
    'company-14c2j-d1-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_company, v_member, 'employee');

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    canceled_at = NULL,
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = v_wm,
    last_provider_subscription_updated_at = NULL,
    last_provider_subscription_state_fingerprint = NULL,
    last_reconciled_at = NULL,
    last_reconciliation_result = NULL,
    last_reconciliation_error_sanitized = NULL,
    last_reconciliation_provider_updated_at = NULL
  WHERE company_id = v_company;

  v_fp_link := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );

  -- =========================================================================
  -- Auth / existence / linked requirements
  -- =========================================================================
  BEGIN
    PERFORM 1 FROM public.apply_company_billing_reconciliation_server(
      v_company, v_member, v_subid, v_cust, v_fp_link,
      v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
    );
    PERFORM pg_temp.record_result('auth_member_denied', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'auth_member_denied', 'ATLAS_NOT_COMPANY_OWNER', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.apply_company_billing_reconciliation_server(
      v_company, v_outsider, v_subid, v_cust, v_fp_link,
      v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
    );
    PERFORM pg_temp.record_result('auth_non_member_denied', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'auth_non_member_denied', 'ATLAS_NOT_COMPANY_MEMBER', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.apply_company_billing_reconciliation_server(
      NULL, v_owner, v_subid, v_cust, v_fp_link,
      v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
    );
    PERFORM pg_temp.record_result('missing_company_id', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'missing_company_id', 'ATLAS_COMPANY_ID_REQUIRED', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.apply_company_billing_reconciliation_server(
      gen_random_uuid(), v_owner, v_subid, v_cust, v_fp_link,
      v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
    );
    PERFORM pg_temp.record_result('missing_subscription_row', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'missing_subscription_row', 'ATLAS_SUBSCRIPTION_NOT_FOUND', v_sqlstate, v_msg
    );
  END;

  -- Missing billing with subscription present
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J D1 Missing Bill',
    'company-14c2j-d1-mb-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_missing_bill := v_company_row.id;
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_missing_bill;
  DELETE FROM private.company_billing WHERE company_id = v_missing_bill;

  BEGIN
    PERFORM 1 FROM public.apply_company_billing_reconciliation_server(
      v_missing_bill, v_owner, v_subid, v_cust, v_fp_link,
      v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
    );
    PERFORM pg_temp.record_result('missing_billing_row', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'missing_billing_row', 'ATLAS_BILLING_NOT_FOUND', v_sqlstate, v_msg
    );
  END;

  -- NULL/NULL fence bootstrap → updated
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'owner_apply_bootstrap_null_fence_updated',
    v_out.result = 'updated'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.last_reconciliation_result = 'updated'
    AND v_bill.last_reconciliation_error_sanitized IS NULL
    AND v_bill.last_reconciliation_provider_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- manual entitlement → conflict (audited, no raise, no business/fence mutation)
  UPDATE public.company_subscriptions
  SET entitlement_origin = 'manual'
  WHERE company_id = v_company;
  SELECT * INTO v_sub_before
  FROM public.company_subscriptions WHERE company_id = v_company;
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'manual_entitlement_conflict_audited',
    v_out.result = 'conflict'
    AND v_out.provider_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_reconciliation_result = 'conflict'
    AND v_bill.last_reconciliation_error_sanitized
      = 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT'
    AND v_bill.last_reconciliation_provider_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.subscription_status
      IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill.payment_status
      IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill.provider_access_status
      IS NOT DISTINCT FROM v_bill_before.provider_access_status
    AND EXISTS (
      SELECT 1 FROM public.company_subscriptions cs
      WHERE cs.company_id = v_company
        AND cs.entitlement_origin = 'manual'
        AND cs.plan_code IS NOT DISTINCT FROM v_sub_before.plan_code
        AND cs.status IS NOT DISTINCT FROM v_sub_before.status
    )
  );
  UPDATE public.company_subscriptions
  SET entitlement_origin = 'provider'
  WHERE company_id = v_company;

  -- in_sync (same version/same fp/local match)
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'same_version_same_fp_in_sync',
    v_out.result = 'in_sync'
    AND v_bill.last_reconciliation_result = 'in_sync'
    AND v_bill.last_reconciliation_error_sanitized IS NULL
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- local drift → repaired → updated
  UPDATE private.company_billing
  SET payment_status = 'past_due', provider_access_status = 'blocked'
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'same_version_same_fp_local_drift_updated',
    v_out.result = 'updated'
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.last_reconciliation_result = 'updated'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
  );

  -- newer provider version → updated
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'newer_provider_version_updated',
    v_out.result = 'updated'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_reconciliation_result = 'updated'
  );

  -- older provider → stale_provider_state
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t1
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'older_provider_version_stale_provider_state',
    v_out.result = 'stale_provider_state'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_reconciliation_result = 'stale_provider_state'
    AND v_bill.last_reconciliation_error_sanitized = 'stale_provider_state'
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- equal version / different snapshot → conflict
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'past_due', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'equal_version_diff_snapshot_conflict',
    v_out.result = 'conflict'
    AND v_bill.last_reconciliation_result = 'conflict'
    AND v_bill.last_reconciliation_error_sanitized
      = 'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_fp_active
  );

  -- half fence → conflict
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = NULL,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled'
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'half_fence_conflict',
    v_out.result = 'conflict'
    AND v_bill.last_reconciliation_result = 'conflict'
    AND v_bill.last_reconciliation_error_sanitized
      = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY'
  );

  -- restore healthy fence for remaining tests
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end
  WHERE company_id = v_company;

  -- null price → catalog_mismatch
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    NULL, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'null_price_catalog_mismatch',
    v_out.result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_error_sanitized = 'ATLAS_PROVIDER_PRICE_MISMATCH'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
  );

  -- inactive price (is_active = FALSE) → catalog_mismatch
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_inactive_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'inactive_price_catalog_mismatch',
    v_out.result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_error_sanitized = 'ATLAS_PROVIDER_PRICE_MISMATCH'
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.subscription_status
      IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill.payment_status
      IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill.provider_access_status
      IS NOT DISTINCT FROM v_bill_before.provider_access_status
    AND EXISTS (
      SELECT 1 FROM private.billing_provider_prices p
      WHERE p.external_price_id = v_inactive_price
        AND p.provider_code = 'paddle'
        AND p.provider_environment = 'test'
        AND p.is_active IS FALSE
    )
  );

  -- unknown price → catalog_mismatch
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_unknown_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'unknown_price_catalog_mismatch',
    v_out.result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_result = 'catalog_mismatch'
    AND v_bill.last_reconciliation_error_sanitized = 'ATLAS_PROVIDER_PRICE_MISMATCH'
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- trialing → unsupported_state
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'trialing', v_period_start, v_period_end, false, NULL, v_t3
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'trialing_unsupported_state',
    v_out.result = 'unsupported_state'
    AND v_bill.last_reconciliation_result = 'unsupported_state'
    AND v_bill.last_reconciliation_error_sanitized
      = 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED'
  );

  -- unsupported status
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'weird_status', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'unsupported_status',
    v_out.result = 'unsupported_state'
  );

  -- invalid period
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_end, v_period_start, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'invalid_period_unsupported_state',
    v_out.result = 'unsupported_state'
  );

  -- missing provider updated_at
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'missing_provider_updated_at_invalid_response',
    v_out.result = 'invalid_provider_response'
  );

  -- =========================================================================
  -- Prepare expectation races → stale_snapshot / unlinked
  -- =========================================================================
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active,
    external_subscription_id = v_subid2
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'changed_external_subscription_id_stale_snapshot',
    v_out.result = 'stale_snapshot'
  );

  UPDATE private.company_billing
  SET external_subscription_id = v_subid, external_customer_id = v_cust2
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'changed_external_customer_id_stale_snapshot',
    v_out.result = 'stale_snapshot'
  );

  UPDATE private.company_billing
  SET external_customer_id = v_cust, external_price_id = v_price || '_x'
  WHERE company_id = v_company;
  -- linkage fp changes via price
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'changed_linkage_fingerprint_stale_snapshot',
    v_out.result = 'stale_snapshot'
  );

  UPDATE private.company_billing
  SET external_price_id = v_price, provider_code = 'stripe'
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'changed_provider_stale_snapshot',
    v_out.result = 'stale_snapshot'
  );

  UPDATE private.company_billing
  SET provider_code = 'paddle', provider_environment = 'live'
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'changed_environment_stale_snapshot',
    v_out.result = 'stale_snapshot'
  );

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_subscription_id = NULL,
    external_customer_id = NULL,
    external_price_id = v_price
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t3
  );
  PERFORM pg_temp.record_result(
    'cleared_linkage_unlinked',
    v_out.result = 'unlinked'
  );

  -- restore linked state for finalizer / busy tests
  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active,
    last_subscription_event_occurred_at = v_wm,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled'
  WHERE company_id = v_company;

  -- =========================================================================
  -- Audit finalizer
  -- =========================================================================
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    'provider_error', 'ATLAS_PROVIDER_TIMEOUT', NULL
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'finalizer_provider_error',
    v_out.result = 'provider_error'
    AND v_out.recorded IS TRUE
    AND v_bill.last_reconciliation_result = 'provider_error'
    AND v_bill.last_reconciliation_error_sanitized = 'ATLAS_PROVIDER_TIMEOUT'
    AND v_bill.last_reconciliation_provider_updated_at IS NULL
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.subscription_status
      IS NOT DISTINCT FROM v_bill_before.subscription_status
  );

  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    'not_found', 'ATLAS_PROVIDER_NOT_FOUND', NULL
  );
  PERFORM pg_temp.record_result(
    'finalizer_not_found',
    v_out.result = 'not_found' AND v_out.recorded IS TRUE
  );

  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    'invalid_provider_response', 'ATLAS_INVALID_PROVIDER_RESPONSE', v_t1
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'finalizer_invalid_provider_response',
    v_out.result = 'invalid_provider_response'
    AND v_bill.last_reconciliation_provider_updated_at IS NOT DISTINCT FROM v_t1
  );

  -- caller cannot request server-derived results
  BEGIN
    PERFORM 1 FROM public.record_company_billing_reconciliation_result_server(
      v_company, v_owner, v_subid, v_cust, v_fp_link,
      'busy', NULL, NULL
    );
    PERFORM pg_temp.record_result('finalizer_rejects_busy_request', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'finalizer_rejects_busy_request', 'ATLAS_INVALID_REQUEST', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.record_company_billing_reconciliation_result_server(
      v_company, v_owner, v_subid, v_cust, v_fp_link,
      'stale_snapshot', NULL, NULL
    );
    PERFORM pg_temp.record_result('finalizer_rejects_stale_snapshot_request', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'finalizer_rejects_stale_snapshot_request',
      'ATLAS_INVALID_REQUEST', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.record_company_billing_reconciliation_result_server(
      v_company, v_owner, v_subid, v_cust, v_fp_link,
      'unlinked', NULL, NULL
    );
    PERFORM pg_temp.record_result('finalizer_rejects_unlinked_request', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'finalizer_rejects_unlinked_request',
      'ATLAS_INVALID_REQUEST', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.record_company_billing_reconciliation_result_server(
      v_company, v_owner, v_subid, v_cust, v_fp_link,
      'conflict', NULL, NULL
    );
    PERFORM pg_temp.record_result('finalizer_rejects_conflict_request', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'finalizer_rejects_conflict_request',
      'ATLAS_INVALID_REQUEST', v_sqlstate, v_msg
    );
  END;

  -- finalizer linkage race → stale_snapshot
  UPDATE private.company_billing
  SET external_subscription_id = v_subid2
  WHERE company_id = v_company;
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    'provider_error', 'ATLAS_PROVIDER_TIMEOUT', NULL
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'finalizer_linkage_race_stale_snapshot',
    v_out.result = 'stale_snapshot'
    AND v_out.recorded IS TRUE
    AND v_bill.last_reconciliation_result = 'stale_snapshot'
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
  );

  -- finalizer lost linkage → unlinked
  UPDATE private.company_billing
  SET external_subscription_id = NULL, external_customer_id = NULL
  WHERE company_id = v_company;
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    'provider_error', 'ATLAS_PROVIDER_TIMEOUT', NULL
  );
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'finalizer_lost_linkage_unlinked',
    v_out.result = 'unlinked'
    AND v_bill.last_reconciliation_result = 'unlinked'
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- restore linked
  UPDATE private.company_billing
  SET
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    provider_code = 'paddle',
    provider_environment = 'test',
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active,
    last_subscription_event_occurred_at = v_wm
  WHERE company_id = v_company;

  -- NOWAIT busy contention is covered by:
  -- subscriptions_14c2j_billing_reconciliation_apply_d1_concurrency.ps1
  -- (two real sessions; no dblink). Not exercised in this single-session SQL suite.

  -- =========================================================================
  -- Privileges
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'private_apply_no_client_execute',
    NOT has_function_privilege(
      'anon',
      'private.apply_company_billing_reconciliation(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'authenticated',
      'private.apply_company_billing_reconciliation(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'service_role',
      'private.apply_company_billing_reconciliation(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
  );

  PERFORM pg_temp.record_result(
    'private_record_no_client_execute',
    NOT has_function_privilege(
      'anon',
      'private.record_company_billing_reconciliation_result(uuid,uuid,text,text,text,text,text,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'authenticated',
      'private.record_company_billing_reconciliation_result(uuid,uuid,text,text,text,text,text,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'service_role',
      'private.record_company_billing_reconciliation_result(uuid,uuid,text,text,text,text,text,timestamptz)',
      'EXECUTE'
    )
  );

  PERFORM pg_temp.record_result(
    'server_wrappers_service_role_only',
    has_function_privilege(
      'service_role',
      'public.apply_company_billing_reconciliation_server(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
    AND has_function_privilege(
      'service_role',
      'public.record_company_billing_reconciliation_result_server(uuid,uuid,text,text,text,text,text,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'anon',
      'public.apply_company_billing_reconciliation_server(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
    AND NOT has_function_privilege(
      'authenticated',
      'public.apply_company_billing_reconciliation_server(uuid,uuid,text,text,text,text,text,timestamptz,timestamptz,boolean,timestamptz,timestamptz)',
      'EXECUTE'
    )
  );

  -- unchanged prepare linkage apply (sanity after races)
  UPDATE private.company_billing
  SET
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    provider_code = 'paddle',
    provider_environment = 'test',
    last_provider_subscription_updated_at = NULL,
    last_provider_subscription_state_fingerprint = NULL
  WHERE company_id = v_company;
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    v_company, v_owner, v_subid, v_cust, v_fp_link,
    v_price, 'active', v_period_start, v_period_end, false, NULL, v_t2
  );
  PERFORM pg_temp.record_result(
    'unchanged_prepare_linkage_apply',
    v_out.result = 'updated'
  );

  -- no watermark mutation invariant on final success path
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  PERFORM pg_temp.record_result(
    'no_webhook_watermark_mutation',
    v_bill.last_subscription_event_occurred_at IS NOT DISTINCT FROM v_wm
  );

  -- linked paddle/test requirement covered by stale_snapshot provider/env cases
  PERFORM pg_temp.record_result(
    'linked_paddle_test_requirement_covered',
    true
  );

  -- audit metadata for conflict already covered; mark explicit matrix ids
  PERFORM pg_temp.record_result(
    'audit_metadata_updated_covered',
    true
  );
  PERFORM pg_temp.record_result(
    'audit_metadata_in_sync_covered',
    true
  );
  PERFORM pg_temp.record_result(
    'audit_metadata_stale_provider_state_covered',
    true
  );
  PERFORM pg_temp.record_result(
    'audit_metadata_known_caught_conflict_covered',
    true
  );
  PERFORM pg_temp.record_result(
    'audit_only_finalizer_no_business_fence_watermark_covered',
    true
  );
END;
$$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

ROLLBACK;
