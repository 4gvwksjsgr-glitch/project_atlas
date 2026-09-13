-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2J Phase B1
-- Reconciliation schema foundation + prepare RPC
-- (migration 20260911140001_billing_reconciliation_prepare_foundation).
-- BEGIN … ROLLBACK: no local residue.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO anon;

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

REVOKE ALL ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT)
  TO authenticated, anon, service_role;

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

GRANT EXECUTE ON FUNCTION pg_temp.set_auth(UUID) TO authenticated;

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

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_member UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();

  v_linked UUID;
  v_unlinked UUID;
  v_missing_bill UUID;
  v_wrong_provider UUID;
  v_wrong_env UUID;
  v_no_sub UUID;

  v_company public.companies%ROWTYPE;
  v_prep RECORD;
  v_prep2 RECORD;
  v_bill private.company_billing%ROWTYPE;
  v_bill_before private.company_billing%ROWTYPE;
  v_bill_after private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;

  v_wm TIMESTAMPTZ := TIMESTAMPTZ '2026-09-07 12:45:59.831588+00';
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_fence_null TIMESTAMPTZ := NULL;

  v_cust TEXT := 'ctm_b1_test_customer_001';
  v_subid TEXT := 'sub_b1_test_subscription_001';
  v_price TEXT := 'pri_b1_test_price_001';

  v_fp_link TEXT;
  v_fp_link2 TEXT;
  v_fp_local TEXT;
  v_fp_local2 TEXT;
  v_fp_local3 TEXT;

  v_col_count INT;
  v_null_fence_count INT;
  v_existing_billing_count INT;
  v_existing_billing_count_after INT;

  v_msg TEXT;
  v_sqlstate TEXT;
  v_bool BOOLEAN;
  v_tz_before TEXT;
  v_fp_tz1 TEXT;
  v_fp_tz2 TEXT;

  v_priv_sig TEXT :=
    'private.prepare_company_billing_reconciliation(uuid,uuid)';
  v_pub_sig TEXT :=
    'public.prepare_company_billing_reconciliation_server(uuid,uuid)';

  v_inbox_vals TEXT;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14c2jb1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'member14c2jb1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14c2jb1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2J B1 Linked',
    'company-14c2j-b1-linked-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_linked := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2J B1 Unlinked',
    'company-14c2j-b1-unlinked-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_unlinked := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2J B1 Missing Bill',
    'company-14c2j-b1-missbill-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_missing_bill := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2J B1 Wrong Provider',
    'company-14c2j-b1-wrongprov-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_wrong_provider := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2J B1 Wrong Env',
    'company-14c2j-b1-wrongenv-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_wrong_env := v_company.id;

  RESET ROLE;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_linked, v_member, 'employee');

  -- Linked paddle/test company with watermark + business state
  UPDATE private.company_billing b
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
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = v_wm,
    last_provider_subscription_updated_at = NULL,
    last_reconciled_at = NULL,
    last_reconciliation_result = NULL,
    last_reconciliation_error_sanitized = NULL,
    last_reconciliation_provider_updated_at = NULL
  WHERE b.company_id = v_linked;

  UPDATE public.company_subscriptions cs
  SET
    plan_code = 'premium',
    status = 'active',
    entitlement_origin = 'provider'
  WHERE cs.company_id = v_linked;

  -- Wrong provider (still "linked" IDs)
  UPDATE private.company_billing b
  SET
    provider_code = 'stripe',
    provider_environment = 'test',
    external_customer_id = 'cus_wrong_provider',
    external_subscription_id = 'sub_wrong_provider',
    external_price_id = 'price_wrong_provider'
  WHERE b.company_id = v_wrong_provider;

  -- Wrong environment
  UPDATE private.company_billing b
  SET
    provider_code = 'paddle',
    provider_environment = 'live',
    external_customer_id = 'ctm_wrong_env',
    external_subscription_id = 'sub_wrong_env',
    external_price_id = 'pri_wrong_env'
  WHERE b.company_id = v_wrong_env;

  -- Missing billing row (subscription remains)
  DELETE FROM private.company_billing WHERE company_id = v_missing_bill;

  -- =========================================================================
  -- B1-01 migration columns present and NULL-safe defaults
  -- =========================================================================
  SELECT count(*)::int
  INTO v_col_count
  FROM information_schema.columns c
  WHERE c.table_schema = 'private'
    AND c.table_name = 'company_billing'
    AND c.column_name IN (
      'last_provider_subscription_updated_at',
      'last_reconciled_at',
      'last_reconciliation_result',
      'last_reconciliation_error_sanitized',
      'last_reconciliation_provider_updated_at'
    );

  PERFORM pg_temp.record_result('B1-01_columns_added', v_col_count = 5);

  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'company_billing_last_reconciliation_result_allowed'
  ) INTO v_bool;
  PERFORM pg_temp.record_result(
    'B1-01_reconciliation_result_check_exists',
    v_bool
  );

  -- =========================================================================
  -- B1-02 / B1-03 existing billing rows: fence NULL, no forced backfill
  -- =========================================================================
  SELECT count(*)::int INTO v_existing_billing_count
  FROM private.company_billing;

  SELECT count(*)::int INTO v_null_fence_count
  FROM private.company_billing
  WHERE last_provider_subscription_updated_at IS NULL;

  PERFORM pg_temp.record_result(
    'B1-03_provider_fence_null_for_existing',
    v_null_fence_count = v_existing_billing_count
  );

  SELECT * INTO v_bill_before
  FROM private.company_billing
  WHERE company_id = v_linked;

  -- Snapshot of non-new columns for B1-02 after prepare
  -- (asserted after successful prepare below)

  -- =========================================================================
  -- B1-04 prepare owner succeeds for linked paddle/test
  -- =========================================================================
  BEGIN
    SELECT * INTO v_prep
    FROM public.prepare_company_billing_reconciliation_server(v_linked, v_owner);
    PERFORM pg_temp.record_result(
      'B1-04_prepare_owner_succeeds',
      v_prep.company_id = v_linked
      AND v_prep.provider_code = 'paddle'
      AND v_prep.provider_environment = 'test'
      AND v_prep.external_subscription_id = v_subid
      AND v_prep.external_customer_id = v_cust
      AND v_prep.external_price_id = v_price
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'B1-04_prepare_owner_succeeds', false, v_sqlstate, v_msg
    );
  END;

  -- =========================================================================
  -- B1-12 signature accepts company/actor only (no provider ID params)
  -- =========================================================================
  SELECT NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'prepare_company_billing_reconciliation_server'
      AND pg_get_function_identity_arguments(p.oid) <> 'p_company_id uuid, p_actor_user_id uuid'
  ) INTO v_bool;

  PERFORM pg_temp.record_result(
    'B1-12_server_rpc_company_actor_only',
    (
      SELECT pg_get_function_identity_arguments(p.oid)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'prepare_company_billing_reconciliation_server'
    ) = 'p_company_id uuid, p_actor_user_id uuid'
  );

  PERFORM pg_temp.record_result(
    'B1-12_private_rpc_company_actor_only',
    (
      SELECT pg_get_function_identity_arguments(p.oid)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'private'
        AND p.proname = 'prepare_company_billing_reconciliation'
    ) = 'p_company_id uuid, p_actor_user_id uuid'
  );

  -- =========================================================================
  -- B1-13 returned anchor matches stored linkage
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'B1-13_anchor_matches_stored_linkage',
    v_prep.external_subscription_id = v_bill_before.external_subscription_id
    AND v_prep.external_customer_id = v_bill_before.external_customer_id
    AND v_prep.external_price_id = v_bill_before.external_price_id
    AND v_prep.provider_code = v_bill_before.provider_code
    AND v_prep.provider_environment = v_bill_before.provider_environment
    AND v_prep.expected_webhook_watermark
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_prep.expected_provider_state_version
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
  );

  -- =========================================================================
  -- B1-14 / B1-15 fingerprints deterministic
  -- =========================================================================
  v_fp_link := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );
  v_fp_link2 := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );
  PERFORM pg_temp.record_result(
    'B1-14_linkage_fingerprint_deterministic',
    v_fp_link = v_fp_link2
    AND v_prep.expected_linkage_fingerprint = v_fp_link
  );

  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_linked;
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_linked;

  v_fp_local := private.billing_reconciliation_local_state_fingerprint(
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
  v_fp_local2 := private.billing_reconciliation_local_state_fingerprint(
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
  PERFORM pg_temp.record_result(
    'B1-15_local_state_fingerprint_deterministic',
    v_fp_local = v_fp_local2
    AND v_prep.expected_local_state_fingerprint = v_fp_local
  );

  -- =========================================================================
  -- B1-16 linkage change changes linkage fingerprint
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'B1-16_linkage_change_changes_fp',
    private.billing_reconciliation_linkage_fingerprint(
      'paddle', 'test', v_cust, v_subid, 'pri_other'
    ) IS DISTINCT FROM v_fp_link
  );

  -- =========================================================================
  -- B1-17 relevant business state change changes local fingerprint
  -- =========================================================================
  v_fp_local3 := private.billing_reconciliation_local_state_fingerprint(
    v_sub.plan_code,
    v_sub.status,
    v_sub.entitlement_origin,
    'ended', -- changed billing subscription_status
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
  PERFORM pg_temp.record_result(
    'B1-17_business_state_change_changes_fp',
    v_fp_local3 IS DISTINCT FROM v_fp_local
  );

  -- =========================================================================
  -- B1-18 volatile metadata (updated_at / raw / reconcile audit) ignored
  -- =========================================================================
  -- Touch updated_at + raw + reconcile audit without changing fingerprint fields
  UPDATE private.company_billing b
  SET
    provider_subscription_raw = '{"touched":true}',
    last_sync_error_sanitized = 'noise',
    last_reconciled_at = now(),
    last_reconciliation_result = 'in_sync',
    last_reconciliation_error_sanitized = 'noise',
    last_reconciliation_provider_updated_at = now(),
    updated_at = now() + interval '1 second'
  WHERE b.company_id = v_linked;

  SELECT * INTO v_prep2
  FROM public.prepare_company_billing_reconciliation_server(v_linked, v_owner);

  PERFORM pg_temp.record_result(
    'B1-18_volatile_metadata_does_not_change_fp',
    v_prep2.expected_local_state_fingerprint = v_prep.expected_local_state_fingerprint
    AND v_prep2.expected_linkage_fingerprint = v_prep.expected_linkage_fingerprint
  );

  -- Restore reconcile audit to NULL for subsequent non-mutation asserts
  UPDATE private.company_billing b
  SET
    provider_subscription_raw = NULL,
    last_sync_error_sanitized = NULL,
    last_reconciled_at = NULL,
    last_reconciliation_result = NULL,
    last_reconciliation_error_sanitized = NULL,
    last_reconciliation_provider_updated_at = NULL
  WHERE b.company_id = v_linked;

  -- =========================================================================
  -- B1-19 / B1-20 / B1-21 prepare does not mutate watermark / fence / metadata
  -- =========================================================================
  SELECT * INTO v_bill_before
  FROM private.company_billing WHERE company_id = v_linked;

  SELECT * INTO v_prep
  FROM public.prepare_company_billing_reconciliation_server(v_linked, v_owner);

  SELECT * INTO v_bill_after
  FROM private.company_billing WHERE company_id = v_linked;

  PERFORM pg_temp.record_result(
    'B1-19_webhook_watermark_read_not_modified',
    v_prep.expected_webhook_watermark IS NOT DISTINCT FROM v_wm
    AND v_bill_after.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  PERFORM pg_temp.record_result(
    'B1-20_provider_fence_read_not_modified',
    v_prep.expected_provider_state_version IS NULL
    AND v_bill_after.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
  );

  PERFORM pg_temp.record_result(
    'B1-21_reconcile_metadata_unchanged_by_prepare',
    v_bill_after.last_reconciled_at IS NULL
    AND v_bill_after.last_reconciliation_result IS NULL
    AND v_bill_after.last_reconciliation_error_sanitized IS NULL
    AND v_bill_after.last_reconciliation_provider_updated_at IS NULL
  );

  -- B1-02: core billing values unchanged by prepare
  PERFORM pg_temp.record_result(
    'B1-02_existing_billing_data_unchanged',
    v_bill_after.provider_code IS NOT DISTINCT FROM v_bill_before.provider_code
    AND v_bill_after.provider_environment
      IS NOT DISTINCT FROM v_bill_before.provider_environment
    AND v_bill_after.external_customer_id
      IS NOT DISTINCT FROM v_bill_before.external_customer_id
    AND v_bill_after.external_subscription_id
      IS NOT DISTINCT FROM v_bill_before.external_subscription_id
    AND v_bill_after.external_price_id
      IS NOT DISTINCT FROM v_bill_before.external_price_id
    AND v_bill_after.subscription_status
      IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill_after.payment_status
      IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill_after.provider_access_status
      IS NOT DISTINCT FROM v_bill_before.provider_access_status
    AND v_bill_after.sync_status IS NOT DISTINCT FROM v_bill_before.sync_status
    AND v_bill_after.last_sync_result
      IS NOT DISTINCT FROM v_bill_before.last_sync_result
    AND v_bill_after.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  SELECT count(*)::int INTO v_existing_billing_count_after
  FROM private.company_billing;
  PERFORM pg_temp.record_result(
    'B1-02_billing_row_count_stable',
    v_existing_billing_count_after = v_existing_billing_count
  );

  -- =========================================================================
  -- Negative paths
  -- =========================================================================
  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_linked, v_member
    );
    PERFORM pg_temp.record_result('B1-05_non_owner_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-05_non_owner_rejected', 'ATLAS_NOT_COMPANY_OWNER', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_linked, v_outsider
    );
    PERFORM pg_temp.record_result('B1-06_non_member_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-06_non_member_rejected', 'ATLAS_NOT_COMPANY_MEMBER', v_sqlstate, v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      gen_random_uuid(), v_owner
    );
    PERFORM pg_temp.record_result('B1-07_unknown_company_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-07_unknown_company_rejected',
      'ATLAS_SUBSCRIPTION_NOT_FOUND',
      v_sqlstate,
      v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_missing_bill, v_owner
    );
    PERFORM pg_temp.record_result('B1-08_missing_company_billing_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-08_missing_company_billing_rejected',
      'ATLAS_BILLING_NOT_FOUND',
      v_sqlstate,
      v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_unlinked, v_owner
    );
    PERFORM pg_temp.record_result('B1-09_missing_external_subscription_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-09_missing_external_subscription_rejected',
      'ATLAS_BILLING_RECONCILIATION_UNLINKED',
      v_sqlstate,
      v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_wrong_provider, v_owner
    );
    PERFORM pg_temp.record_result('B1-10_wrong_provider_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-10_wrong_provider_rejected',
      'ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_PROVIDER',
      v_sqlstate,
      v_msg
    );
  END;

  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_wrong_env, v_owner
    );
    PERFORM pg_temp.record_result('B1-11_wrong_environment_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1-11_wrong_environment_rejected',
      'ATLAS_BILLING_RECONCILIATION_UNSUPPORTED_ENVIRONMENT',
      v_sqlstate,
      v_msg
    );
  END;

  -- Null inputs
  BEGIN
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      NULL, v_owner
    );
    PERFORM pg_temp.record_result('B1_null_company_rejected', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'B1_null_company_rejected',
      'ATLAS_COMPANY_ID_REQUIRED',
      v_sqlstate,
      v_msg
    );
  END;

  -- =========================================================================
  -- B1-22 / B1-23 / B1-24 / B1-25 privileges
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'B1-22_anon_cannot_execute_server',
    NOT has_function_privilege('anon', v_pub_sig, 'EXECUTE')
  );
  PERFORM pg_temp.record_result(
    'B1-23_authenticated_cannot_execute_server',
    NOT has_function_privilege('authenticated', v_pub_sig, 'EXECUTE')
  );
  PERFORM pg_temp.record_result(
    'B1-24_service_role_execute_grant',
    has_function_privilege('service_role', v_pub_sig, 'EXECUTE')
  );
  PERFORM pg_temp.record_result(
    'B1-25_private_not_client_executable',
    NOT has_function_privilege('anon', v_priv_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_priv_sig, 'EXECUTE')
    AND NOT has_function_privilege('service_role', v_priv_sig, 'EXECUTE')
  );

  -- Role-switch execute attempts
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_linked, v_owner
    );
    RESET ROLE;
    PERFORM pg_temp.record_result('B1-22_anon_execute_blocked', false);
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      PERFORM pg_temp.record_result('B1-22_anon_execute_blocked', true);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      RESET ROLE;
      PERFORM pg_temp.record_result(
        'B1-22_anon_execute_blocked', false, v_sqlstate, v_msg
      );
  END;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM 1 FROM public.prepare_company_billing_reconciliation_server(
      v_linked, v_owner
    );
    RESET ROLE;
    PERFORM pg_temp.record_result('B1-23_authenticated_execute_blocked', false);
  EXCEPTION
    WHEN insufficient_privilege THEN
      RESET ROLE;
      PERFORM pg_temp.record_result('B1-23_authenticated_execute_blocked', true);
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      RESET ROLE;
      PERFORM pg_temp.record_result(
        'B1-23_authenticated_execute_blocked', false, v_sqlstate, v_msg
      );
  END;

  BEGIN
    SET LOCAL ROLE service_role;
    SELECT * INTO v_prep
    FROM public.prepare_company_billing_reconciliation_server(v_linked, v_owner);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'B1-24_service_role_execute_ok',
      v_prep.company_id = v_linked
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'B1-24_service_role_execute_ok', false, v_sqlstate, v_msg
    );
  END;

  -- =========================================================================
  -- B1-FIX1 canonical fingerprint properties (JSON-array serialization)
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'B1-FP-01_linkage_null_vs_empty_price',
    private.billing_reconciliation_linkage_fingerprint(
      'paddle', 'test', v_cust, v_subid, NULL
    ) IS DISTINCT FROM private.billing_reconciliation_linkage_fingerprint(
      'paddle', 'test', v_cust, v_subid, ''
    )
  );

  -- Would collide under concat_ws('|', ...): ('paddle|test','x',...) vs ('paddle','test|x',...)
  PERFORM pg_temp.record_result(
    'B1-FP-02_linkage_delimiter_safety',
    private.billing_reconciliation_linkage_fingerprint(
      'paddle|test', 'x', 'c', 's', 'p'
    ) IS DISTINCT FROM private.billing_reconciliation_linkage_fingerprint(
      'paddle', 'test|x', 'c', 's', 'p'
    )
  );

  PERFORM pg_temp.record_result(
    'B1-FP-03_local_null_vs_empty_text',
    private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      NULL,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    ) IS DISTINCT FROM private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      '',
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    )
  );

  PERFORM pg_temp.record_result(
    'B1-FP-04_local_cancel_null_vs_false',
    private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, NULL, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    ) IS DISTINCT FROM private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    )
  );

  PERFORM pg_temp.record_result(
    'B1-FP-05_timestamp_null_vs_value',
    private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      NULL, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    ) IS DISTINCT FROM private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    )
  );

  BEGIN
    v_tz_before := current_setting('TimeZone');
    PERFORM set_config('TimeZone', 'UTC', true);
    v_fp_tz1 := private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    );
    PERFORM set_config('TimeZone', 'America/New_York', true);
    v_fp_tz2 := private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    );
    PERFORM set_config('TimeZone', v_tz_before, true);
    PERFORM pg_temp.record_result(
      'B1-FP-06_timestamp_timezone_invariant',
      v_fp_tz1 = v_fp_tz2
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    BEGIN
      PERFORM set_config('TimeZone', v_tz_before, true);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM pg_temp.record_result(
      'B1-FP-06_timestamp_timezone_invariant', false, v_sqlstate, v_msg
    );
  END;

  v_fp_link := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );
  v_fp_link2 := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );
  PERFORM pg_temp.record_result(
    'B1-FP-07_identical_inputs_deterministic',
    v_fp_link = v_fp_link2
    AND private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    ) = private.billing_reconciliation_local_state_fingerprint(
      'premium', 'active', 'provider', 'active', 'ok', 'entitled',
      v_price,
      v_period_start, v_period_end, false, NULL, v_period_end, NULL,
      'idle', 'succeeded', NULL
    )
  );

  SELECT * INTO v_prep
  FROM public.prepare_company_billing_reconciliation_server(v_linked, v_owner);
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_linked;
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_linked;
  PERFORM pg_temp.record_result(
    'B1-FP-08_prepare_matches_direct_helpers',
    v_prep.expected_linkage_fingerprint
      = private.billing_reconciliation_linkage_fingerprint(
        v_bill.provider_code,
        v_bill.provider_environment,
        v_bill.external_customer_id,
        v_bill.external_subscription_id,
        v_bill.external_price_id
      )
    AND v_prep.expected_local_state_fingerprint
      = private.billing_reconciliation_local_state_fingerprint(
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
      )
  );

  -- Future fence readiness (schema only; no webhook behavior change)
  PERFORM pg_temp.record_result(
    'B1_fence_bootstrap_null_documented',
    v_bill_after.last_provider_subscription_updated_at IS NULL
  );

  -- Current inbox processing_status contract (lock decision for Phase C)
  SELECT pg_get_constraintdef(c.oid)
  INTO v_inbox_vals
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'private'
    AND t.relname = 'billing_provider_events'
    AND c.conname = 'billing_provider_events_processing_status_allowed';

  PERFORM pg_temp.record_result(
    'B1_inbox_processing_status_unchanged',
    v_inbox_vals LIKE '%received%'
    AND v_inbox_vals LIKE '%processing%'
    AND v_inbox_vals LIKE '%processed%'
    AND v_inbox_vals LIKE '%ignored%'
    AND v_inbox_vals LIKE '%failed%'
  );

  -- Security definer / invoker shape
  SELECT
    p.prosecdef
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg IN ('search_path=', 'search_path=""')
    )
  INTO v_bool
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'prepare_company_billing_reconciliation_server';
  PERFORM pg_temp.record_result(
    'B1_public_security_definer_empty_path',
    COALESCE(v_bool, FALSE)
  );

  SELECT
    NOT p.prosecdef
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg IN ('search_path=', 'search_path=""')
    )
  INTO v_bool
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'prepare_company_billing_reconciliation';
  PERFORM pg_temp.record_result(
    'B1_private_security_invoker_empty_path',
    COALESCE(v_bool, FALSE)
  );
END;
$$;

-- Summary
SELECT
  test_name,
  passed,
  sqlstate,
  detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

DO $$
DECLARE
  v_failed INT;
BEGIN
  SELECT count(*)::int INTO v_failed FROM test_results WHERE NOT passed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION '14C-2J B1 tests failed: % case(s)', v_failed;
  END IF;
END;
$$;

ROLLBACK;
