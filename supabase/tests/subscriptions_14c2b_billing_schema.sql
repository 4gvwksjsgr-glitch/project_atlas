-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2B billing schema behavior
-- provider_environment, billing_runtime_config, catalog (offers/prices),
-- checkout sessions + server RPCs, overview is_checkout_eligible.
-- BEGIN … ROLLBACK: nessun residuo locale.
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

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_member UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();

  v_free UUID;
  v_checkout_co UUID;
  v_company2 UUID;
  v_company3 UUID;
  v_trial_ov UUID;
  v_entitled_ov UUID;
  v_ended_ov UUID;
  v_ttl_co UUID;
  v_reuse_co UUID;
  v_guard_co UUID;
  v_side_co UUID;

  v_uniq_a UUID := gen_random_uuid();
  v_uniq_b UUID := gen_random_uuid();
  v_uniq_c UUID := gen_random_uuid();
  v_evt_co UUID := gen_random_uuid();

  v_company public.companies%ROWTYPE;

  v_offer_id UUID;
  v_price1_id UUID;
  v_price3_id UUID;
  v_seed_price_id UUID;
  v_price_p1 UUID;
  v_price_p2 UUID;
  v_cfg_id UUID;

  v_session1 UUID;
  v_session_co2_1 UUID;
  v_session_co2_2 UUID;
  v_session_co3_1 UUID;
  v_session_ttl_old UUID;
  v_session_ttl_new UUID;
  v_session_reuse UUID;
  v_session_reuse_new UUID;
  v_session_guard UUID;
  v_session_guard_failed UUID;
  v_session_guard_abandoned UUID;
  v_session_side UUID;

  v_token1 TEXT;
  v_token2 TEXT;
  v_token_guard TEXT;
  v_token_side TEXT;
  v_ext_p1 TEXT;
  v_ext_p2 TEXT;

  v_bool BOOLEAN;
  v_text TEXT;
  v_text2 TEXT;
  v_int INT;

  v_sqlstate TEXT;
  v_err TEXT;

  v_reserve RECORD;
  v_attach RECORD;
  v_confirm RECORD;
  v_sess_snap RECORD;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14c2b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'member14c2b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14c2b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  -- =========================================================================
  -- COMPANY SETUP — all owner-owned companies via create_company (free/unlinked)
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT * INTO v_company
    FROM public.create_company(
      'Company 14C2B Free',
      'company-14c2b-free-' || substr(gen_random_uuid()::text, 1, 8)
    );
    v_free := v_company.id;
    PERFORM pg_temp.record_result('create_company_free_ok', v_free IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('create_company_free_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_company
    FROM public.create_company(
      'Company 14C2B Checkout',
      'company-14c2b-checkout-' || substr(gen_random_uuid()::text, 1, 8)
    );
    v_checkout_co := v_company.id;
    PERFORM pg_temp.record_result('create_company_checkout_ok', v_checkout_co IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('create_company_checkout_ok', false, v_sqlstate, v_err);
  END;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Two',
    'company-14c2b-two-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company2 := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Three',
    'company-14c2b-three-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company3 := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Trial Overview',
    'company-14c2b-trialov-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_trial_ov := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Entitled Overview',
    'company-14c2b-entov-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_entitled_ov := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Ended Overview',
    'company-14c2b-endov-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_ended_ov := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B TTL',
    'company-14c2b-ttl-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_ttl_co := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Reuse',
    'company-14c2b-reuse-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_reuse_co := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B Guard',
    'company-14c2b-guard-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_guard_co := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2B SideEffects',
    'company-14c2b-side-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_side_co := v_company.id;

  RESET ROLE;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_checkout_co, v_member, 'employee');

  -- =========================================================================
  -- PROVIDER ENVIRONMENT
  -- =========================================================================
  SELECT b.provider_environment INTO v_text
  FROM private.company_billing b
  WHERE b.company_id = v_free;
  PERFORM pg_temp.record_result(
    'company_billing_unlinked_provider_environment_null',
    v_text IS NULL,
    NULL,
    coalesce(v_text, 'null')
  );

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'paddle'
    WHERE company_id = v_free;
    PERFORM pg_temp.record_result(
      'linked_without_environment_fails', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('linked_without_environment_fails', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'linked_without_environment_fails', false, v_sqlstate, v_err
    );
  END;

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_uniq_a, 'Uniq Env A', 'company-14c2b-uniqa-' || substr(v_uniq_a::text, 1, 8)),
    (v_uniq_b, 'Uniq Env B', 'company-14c2b-uniqb-' || substr(v_uniq_b::text, 1, 8)),
    (v_uniq_c, 'Uniq Env C', 'company-14c2b-uniqc-' || substr(v_uniq_c::text, 1, 8));
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES
    (v_uniq_a, 'free', 'free', 'none'),
    (v_uniq_b, 'free', 'free', 'none'),
    (v_uniq_c, 'free', 'free', 'none');
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id
  ) VALUES (v_uniq_a, 'paddle', 'test', 'cus_env_shared');
  INSERT INTO private.company_billing (company_id) VALUES (v_uniq_b), (v_uniq_c);

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'paddle',
        provider_environment = 'live',
        external_customer_id = 'cus_env_shared'
    WHERE company_id = v_uniq_b;
    PERFORM pg_temp.record_result('same_customer_id_across_envs_allowed', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'same_customer_id_across_envs_allowed', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'paddle',
        provider_environment = 'test',
        external_customer_id = 'cus_env_shared'
    WHERE company_id = v_uniq_c;
    PERFORM pg_temp.record_result(
      'same_customer_id_same_env_fails', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('same_customer_id_same_env_fails', true, '23505', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'same_customer_id_same_env_fails', false, v_sqlstate, v_err
    );
  END;

  -- =========================================================================
  -- EVENTS — ambient provider_environment uniqueness / NOT NULL
  -- =========================================================================
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_evt_co, 'Events Env Co', 'company-14c2b-evt-' || substr(v_evt_co::text, 1, 8));
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_evt_co, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id) VALUES (v_evt_co);

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash, payload_json,
      retention_expires_at
    ) VALUES (
      'paddle', 'test', 'evt_env_shared', 'subscription.updated', v_evt_co,
      'verified', now(), 'hash_env_1', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result('event_env_test_insert_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('event_env_test_insert_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash, payload_json,
      retention_expires_at
    ) VALUES (
      'paddle', 'live', 'evt_env_shared', 'subscription.updated', v_evt_co,
      'verified', now(), 'hash_env_2', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result('event_same_id_across_envs_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('event_same_id_across_envs_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash, payload_json,
      retention_expires_at
    ) VALUES (
      'paddle', 'test', 'evt_env_shared', 'subscription.updated', v_evt_co,
      'verified', now(), 'hash_env_3', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result(
      'event_duplicate_same_env_fails', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('event_duplicate_same_env_fails', true, '23505', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'event_duplicate_same_env_fails', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash, payload_json,
      retention_expires_at
    ) VALUES (
      'paddle', 'evt_env_noenv', 'subscription.updated', v_evt_co,
      'verified', now(), 'hash_noenv', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result(
      'event_missing_environment_fails', false, NULL, 'expected not null violation'
    );
  EXCEPTION WHEN not_null_violation THEN
    PERFORM pg_temp.record_result('event_missing_environment_fails', true, '23502', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'event_missing_environment_fails', false, v_sqlstate, v_err
    );
  END;

  -- =========================================================================
  -- RUNTIME CONFIG
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT is_checkout_eligible INTO v_bool
    FROM public.get_company_subscription_overview(v_checkout_co);
    PERFORM pg_temp.record_result(
      'checkout_eligible_false_zero_config', v_bool = FALSE, NULL, v_bool::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'checkout_eligible_false_zero_config', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', true,
      'https://atlas.example', '/billing/checkout', '/billing/return', true
    )
    RETURNING id INTO v_cfg_id;
    PERFORM pg_temp.record_result('runtime_config_insert_active_ok', v_cfg_id IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('runtime_config_insert_active_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'live', true,
      'https://atlas.example', '/billing/checkout', '/billing/return', true
    );
    PERFORM pg_temp.record_result(
      'runtime_config_second_active_fails', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('runtime_config_second_active_fails', true, '23505', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_config_second_active_fails', false, v_sqlstate, v_err
    );
  END;

  -- Exact allowlisted paths only
  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', false,
      'https://atlas.example', '/checkout', '/billing/return', false
    );
    PERFORM pg_temp.record_result(
      'runtime_path_checkout_rejected', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('runtime_path_checkout_rejected', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_path_checkout_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', false,
      'https://atlas.example', '/billing/other', '/billing/return', false
    );
    PERFORM pg_temp.record_result(
      'runtime_path_other_rejected', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('runtime_path_other_rejected', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_path_other_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', false,
      'https://atlas.example', '/billing/checkout?x=1', '/billing/return', false
    );
    PERFORM pg_temp.record_result(
      'runtime_path_query_rejected', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('runtime_path_query_rejected', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_path_query_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', false,
      'https://atlas.example', '/billing/checkout#frag', '/billing/return', false
    );
    PERFORM pg_temp.record_result(
      'runtime_path_fragment_rejected', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('runtime_path_fragment_rejected', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_path_fragment_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'test', false,
      'https://atlas.example', 'https://evil.example/billing/checkout', '/billing/return', false
    );
    PERFORM pg_temp.record_result(
      'runtime_path_absolute_rejected', false, NULL, 'expected check violation'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('runtime_path_absolute_rejected', true, '23514', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'runtime_path_absolute_rejected', false, v_sqlstate, v_err
    );
  END;

  PERFORM pg_temp.record_result(
    'runtime_config_no_cancel_path_column',
    NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'private'
        AND c.table_name = 'billing_runtime_config'
        AND c.column_name = 'cancel_path'
    )
  );

  UPDATE private.billing_runtime_config SET checkout_enabled = false WHERE id = v_cfg_id;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_checkout_co);
  PERFORM pg_temp.record_result(
    'checkout_eligible_false_when_disabled', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  UPDATE private.billing_runtime_config SET checkout_enabled = true WHERE id = v_cfg_id;

  PERFORM pg_temp.record_result(
    'runtime_config_no_client_select',
    NOT has_table_privilege('anon', 'private.billing_runtime_config', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'private.billing_runtime_config', 'SELECT')
  );

  -- =========================================================================
  -- CATALOG (offers + provider prices)
  -- =========================================================================
  SELECT id INTO v_offer_id
  FROM private.billing_offers WHERE offer_code = 'premium_monthly';

  SELECT atlas_plan_code, billing_interval, interval_count, is_active
  INTO v_text, v_text2, v_int, v_bool
  FROM private.billing_offers WHERE offer_code = 'premium_monthly';
  PERFORM pg_temp.record_result(
    'premium_monthly_offer_shape',
    v_offer_id IS NOT NULL
      AND v_text = 'premium'
      AND v_text2 = 'month'
      AND v_int = 1
      AND v_bool = TRUE,
    NULL,
    format('plan=%s interval=%s/%s active=%s', v_text, v_text2, v_int, v_bool)
  );

  SELECT count(*)::int INTO v_int FROM private.billing_offers;
  PERFORM pg_temp.record_result('no_annual_offer', v_int = 1, NULL, v_int::text);

  BEGIN
    INSERT INTO private.billing_provider_prices (
      offer_id, provider_code, provider_environment,
      external_product_id, external_price_id,
      base_amount, currency, valid_from, valid_to, is_active
    ) VALUES (
      v_offer_id, 'paddle', 'test',
      'pro_catalog_1', 'pri_catalog_a',
      9.99, 'EUR', now() - interval '1 day', NULL, true
    )
    RETURNING id INTO v_price1_id;
    PERFORM pg_temp.record_result('price_insert_first_active_ok', v_price1_id IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('price_insert_first_active_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.billing_provider_prices (
      offer_id, provider_code, provider_environment,
      external_product_id, external_price_id,
      base_amount, currency, valid_from, valid_to, is_active
    ) VALUES (
      v_offer_id, 'paddle', 'test',
      'pro_catalog_2', 'pri_catalog_b',
      9.99, 'EUR', now() - interval '1 day', NULL, true
    );
    PERFORM pg_temp.record_result(
      'price_second_active_same_scope_fails', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result(
      'price_second_active_same_scope_fails', true, '23505', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_second_active_same_scope_fails', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_provider_prices (
      offer_id, provider_code, provider_environment,
      external_product_id, external_price_id,
      base_amount, currency, valid_from, valid_to, is_active
    ) VALUES (
      v_offer_id, 'paddle', 'live',
      'pro_catalog_1', 'pri_catalog_a',
      9.99, 'EUR', now() - interval '1 day', NULL, true
    )
    RETURNING id INTO v_price3_id;
    PERFORM pg_temp.record_result(
      'price_same_external_id_diff_env_ok', v_price3_id IS NOT NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_same_external_id_diff_env_ok', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET base_amount = 19.99
    WHERE id = v_price1_id;
    PERFORM pg_temp.record_result(
      'price_update_base_amount_immutable', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_update_base_amount_immutable',
      v_err = 'ATLAS_BILLING_PRICE_IMMUTABLE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET is_active = false
    WHERE id = v_price1_id;
    PERFORM pg_temp.record_result('price_deactivate_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('price_deactivate_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET is_active = true
    WHERE id = v_price1_id;
    PERFORM pg_temp.record_result(
      'price_reactivate_forbidden', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_reactivate_forbidden',
      v_err = 'ATLAS_BILLING_PRICE_REACTIVATE_FORBIDDEN',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET valid_to = now()
    WHERE id = v_price1_id;
    PERFORM pg_temp.record_result('price_set_valid_to_once_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('price_set_valid_to_once_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET valid_to = now() + interval '1 day'
    WHERE id = v_price1_id;
    PERFORM pg_temp.record_result(
      'price_change_valid_to_again_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_change_valid_to_again_fails',
      v_err = 'ATLAS_BILLING_PRICE_VALID_TO_LOCKED',
      v_sqlstate,
      v_err
    );
  END;

  PERFORM pg_temp.record_result(
    'catalog_tables_no_client_select',
    NOT has_table_privilege('anon', 'private.billing_offers', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'private.billing_offers', 'SELECT')
      AND NOT has_table_privilege('anon', 'private.billing_provider_prices', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'private.billing_provider_prices', 'SELECT')
  );

  -- Real seed price consumed by the checkout RPC flows below.
  BEGIN
    INSERT INTO private.billing_provider_prices (
      offer_id, provider_code, provider_environment,
      external_product_id, external_price_id,
      base_amount, currency, valid_from, valid_to, is_active
    ) VALUES (
      v_offer_id, 'paddle', 'test',
      'pro_test_1', 'pri_test_1',
      11.99, 'EUR', now() - interval '1 day', NULL, true
    )
    RETURNING id INTO v_seed_price_id;
    PERFORM pg_temp.record_result('rpc_seed_price_insert_ok', v_seed_price_id IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('rpc_seed_price_insert_ok', false, v_sqlstate, v_err);
  END;

  -- =========================================================================
  -- OVERVIEW — eligibility true (owner) / false (member) BEFORE any session
  -- is opened on the checkout company (open sessions would flip this false).
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_checkout_co);
  PERFORM pg_temp.record_result(
    'checkout_eligible_true_owner_free_company', v_bool = TRUE, NULL, v_bool::text
  );
  RESET ROLE;

  PERFORM pg_temp.set_auth(v_member);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_checkout_co);
  PERFORM pg_temp.record_result(
    'checkout_eligible_false_member', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- =========================================================================
  -- CHECKOUT SESSION / RPC
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'server_rpc_execute_grants',
    NOT has_function_privilege(
      'authenticated',
      'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
      'EXECUTE'
    )
      AND NOT has_function_privilege(
        'anon',
        'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
        'EXECUTE'
      )
      AND has_function_privilege(
        'service_role',
        'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
        'EXECUTE'
      )
      AND NOT has_function_privilege(
        'authenticated',
        'public.attach_billing_checkout_provider_result_server(uuid,uuid,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      )
      AND NOT has_function_privilege(
        'anon',
        'public.attach_billing_checkout_provider_result_server(uuid,uuid,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      )
      AND has_function_privilege(
        'service_role',
        'public.attach_billing_checkout_provider_result_server(uuid,uuid,text,text,text,text,text,timestamptz)',
        'EXECUTE'
      )
      AND NOT has_function_privilege(
        'authenticated',
        'public.confirm_billing_checkout_browser_signal_server(uuid,uuid,text,text,timestamptz)',
        'EXECUTE'
      )
      AND NOT has_function_privilege(
        'anon',
        'public.confirm_billing_checkout_browser_signal_server(uuid,uuid,text,text,timestamptz)',
        'EXECUTE'
      )
      AND has_function_privilege(
        'service_role',
        'public.confirm_billing_checkout_browser_signal_server(uuid,uuid,text,text,timestamptz)',
        'EXECUTE'
      )
  );

  SET LOCAL ROLE service_role;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_checkout_co, v_member, 'premium_monthly', 'idem-neg-member', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_member_not_owner_denied', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_member_not_owner_denied',
      v_err = 'ATLAS_NOT_COMPANY_OWNER',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_checkout_co, v_outsider, 'premium_monthly', 'idem-neg-outsider', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_outsider_not_member_denied', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_outsider_not_member_denied',
      v_err = 'ATLAS_NOT_COMPANY_MEMBER',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_checkout_co, v_owner, 'premium_monthly', 'idem-1', now()
    );
    v_session1 := v_reserve.session_id;
    v_token1 := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result(
      'reserve_owner_ok_created_not_started',
      v_reserve.reuse = FALSE
        AND v_reserve.checkout_status = 'created'
        AND v_reserve.provider_create_status = 'not_started'
        AND v_reserve.return_token_plain IS NOT NULL,
      NULL,
      format(
        'reuse=%s status=%s/%s',
        v_reserve.reuse, v_reserve.checkout_status, v_reserve.provider_create_status
      )
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_owner_ok_created_not_started', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_checkout_co, v_owner, 'premium_monthly', 'idem-1', now()
    );
    v_token2 := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result(
      'reserve_idempotency_reuse',
      v_reserve.reuse = TRUE
        AND v_reserve.return_token_version = 2
        AND v_reserve.session_id = v_session1,
      NULL,
      format('reuse=%s version=%s', v_reserve.reuse, v_reserve.return_token_version)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('reserve_idempotency_reuse', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session1, v_owner, v_token1, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_old_token_invalid', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_old_token_invalid',
      v_err = 'ATLAS_RETURN_TOKEN_INVALID',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session1, v_owner, v_token2, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_new_token_ok_opened',
      v_confirm.ok = TRUE AND v_confirm.checkout_status = 'opened',
      NULL,
      format('ok=%s status=%s', v_confirm.ok, v_confirm.checkout_status)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('confirm_new_token_ok_opened', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session1, v_owner, v_token2, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_second_time_consumed', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_second_time_consumed',
      v_err = 'ATLAS_RETURN_TOKEN_CONSUMED',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_checkout_co, v_owner, 'premium_monthly', 'idem-2', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_other_key_while_open_denied', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_other_key_while_open_denied',
      v_err = 'ATLAS_CHECKOUT_ALREADY_OPEN',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session1, v_owner, 'not_started', 'processing', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_not_started_to_processing_ok',
      v_attach.applied = TRUE AND v_attach.provider_create_status = 'processing',
      NULL,
      format('applied=%s status=%s', v_attach.applied, v_attach.provider_create_status)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_not_started_to_processing_ok', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session1, v_owner, 'processing', 'created', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_processing_to_created_missing_fields', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_processing_to_created_missing_fields',
      v_err = 'ATLAS_CHECKOUT_PROVIDER_RESULT_INCOMPLETE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session1, v_owner, 'processing', 'created',
      'txn_co1_1', 'https://checkout.paddle.example/txn_co1_1', NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_processing_to_created_ok',
      v_attach.applied = TRUE AND v_attach.provider_create_status = 'created',
      NULL,
      format('applied=%s status=%s', v_attach.applied, v_attach.provider_create_status)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('attach_processing_to_created_ok', false, v_sqlstate, v_err);
  END;

  -- ---- Company 2: failed path, then a new open session on another key ----
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company2, v_owner, 'premium_monthly', 'idem-co2-1', now()
    );
    v_session_co2_1 := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'company2_reserve_1_ok',
      v_reserve.checkout_status = 'created'
        AND v_reserve.provider_create_status = 'not_started'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('company2_reserve_1_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co2_1, v_owner, 'not_started', 'processing', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'company2_attach_processing_ok',
      v_attach.applied = TRUE AND v_attach.provider_create_status = 'processing'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('company2_attach_processing_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co2_1, v_owner, 'processing', 'failed', NULL, NULL, 'sanitized error', now()
    );
    PERFORM pg_temp.record_result(
      'company2_attach_failed_sets_checkout_failed',
      v_attach.applied = TRUE
        AND v_attach.provider_create_status = 'failed'
        AND v_attach.checkout_status = 'failed',
      NULL,
      format('status=%s/%s', v_attach.checkout_status, v_attach.provider_create_status)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'company2_attach_failed_sets_checkout_failed', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company2, v_owner, 'premium_monthly', 'idem-co2-2', now()
    );
    v_session_co2_2 := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'company2_new_reserve_after_failed_ok',
      v_reserve.reuse = FALSE AND v_reserve.checkout_status = 'created'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'company2_new_reserve_after_failed_ok', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co2_2, v_owner, 'not_started', 'created',
      'txn_arbitrary', 'https://checkout.paddle.example/txn_arbitrary', NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_arbitrary_not_started_to_created_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_arbitrary_not_started_to_created_fails',
      v_err = 'ATLAS_INVALID_PROVIDER_CREATE_TRANSITION',
      v_sqlstate,
      v_err
    );
  END;

  -- ---- Company 3: provider outcome_unknown path ----
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company3, v_owner, 'premium_monthly', 'idem-co3-1', now()
    );
    v_session_co3_1 := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'company3_reserve_1_ok',
      v_reserve.checkout_status = 'created'
        AND v_reserve.provider_create_status = 'not_started'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('company3_reserve_1_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co3_1, v_owner, 'not_started', 'processing', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'company3_attach_processing_ok', v_attach.applied = TRUE
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('company3_attach_processing_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co3_1, v_owner, 'processing', 'outcome_unknown',
      NULL, NULL, 'provider timeout', now()
    );
    PERFORM pg_temp.record_result(
      'company3_attach_outcome_unknown_ok',
      v_attach.applied = TRUE
        AND v_attach.provider_create_status = 'outcome_unknown'
        AND v_attach.checkout_status IN ('created', 'opened'),
      NULL,
      format('status=%s/%s', v_attach.checkout_status, v_attach.provider_create_status)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'company3_attach_outcome_unknown_ok', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company3, v_owner, 'premium_monthly', 'idem-co3-2', now()
    );
    PERFORM pg_temp.record_result(
      'company3_other_key_while_open_denied', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'company3_other_key_while_open_denied',
      v_err = 'ATLAS_CHECKOUT_ALREADY_OPEN',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_co3_1, v_owner, 'outcome_unknown', 'created',
      'txn_co3', 'https://checkout.paddle.example/txn_co3', NULL, now()
    );
    PERFORM pg_temp.record_result(
      'company3_outcome_unknown_to_created_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'company3_outcome_unknown_to_created_fails',
      v_err = 'ATLAS_INVALID_PROVIDER_CREATE_TRANSITION',
      v_sqlstate,
      v_err
    );
  END;

  RESET ROLE;

  -- =========================================================================
  -- OVERVIEW — trial / entitled+grace / ended subscription / open session
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial_ov);
    PERFORM pg_temp.record_result('activate_trial_for_overview_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('activate_trial_for_overview_ok', false, v_sqlstate, v_err);
  END;

  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_trial_ov);
  PERFORM pg_temp.record_result(
    'checkout_eligible_true_during_trial', v_bool = TRUE, NULL, v_bool::text
  );
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET status = 'active', plan_code = 'premium', entitlement_origin = 'provider'
  WHERE company_id = v_entitled_ov;
  UPDATE private.company_billing
  SET provider_code = 'paddle',
      provider_environment = 'test',
      external_customer_id = 'cus_entitled_ov',
      external_subscription_id = 'sub_entitled_ov',
      subscription_status = 'active',
      provider_access_status = 'entitled',
      provider_access_ends_at = now() + interval '30 days'
  WHERE company_id = v_entitled_ov;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_entitled_ov);
  PERFORM pg_temp.record_result(
    'checkout_eligible_false_entitled', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET status = 'free', plan_code = 'free', entitlement_origin = 'provider'
  WHERE company_id = v_ended_ov;
  UPDATE private.company_billing
  SET provider_code = 'paddle',
      provider_environment = 'test',
      external_customer_id = 'cus_ended_ov',
      external_subscription_id = 'sub_ended_ov',
      subscription_status = 'ended',
      provider_access_status = 'ended'
  WHERE company_id = v_ended_ov;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_ended_ov);
  PERFORM pg_temp.record_result(
    'checkout_eligible_true_ended_subscription', v_bool = TRUE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_ended_ov, v_owner, 'premium_monthly', 'idem-ended-1', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_on_ended_company_ok', v_reserve.session_id IS NOT NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('reserve_on_ended_company_ok', false, v_sqlstate, v_err);
  END;
  RESET ROLE;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_ended_ov);
  PERFORM pg_temp.record_result(
    'checkout_eligible_false_open_session', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- =========================================================================
  -- TTL eligibility (no UPDATE from helper) + reserve materializes expired
  -- =========================================================================
  INSERT INTO private.billing_checkout_sessions (
    id, company_id, provider_code, provider_environment,
    billing_provider_price_id, atlas_plan_code, offer_code,
    initiated_by_user_id, checkout_status, provider_create_status,
    idempotency_key, return_token_hash, return_token_version,
    allowed_return_origin, checkout_path, return_path,
    expires_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_ttl_co, 'paddle', 'test',
    v_seed_price_id, 'premium', 'premium_monthly',
    v_owner, 'created', 'not_started',
    'idem-ttl-stale', encode(extensions.digest(convert_to('ttl-stale', 'UTF8'), 'sha256'), 'hex'), 1,
    'https://atlas.example', '/billing/checkout', '/billing/return',
    now() - interval '1 minute', now() - interval '50 minutes', now() - interval '50 minutes'
  )
  RETURNING id INTO v_session_ttl_old;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_ttl_co);
  PERFORM pg_temp.record_result(
    'ttl_stale_open_does_not_block_eligible',
    v_bool = TRUE,
    NULL,
    v_bool::text
  );
  RESET ROLE;

  SELECT checkout_status INTO v_text
  FROM private.billing_checkout_sessions WHERE id = v_session_ttl_old;
  PERFORM pg_temp.record_result(
    'ttl_helper_does_not_expire_row',
    v_text = 'created',
    NULL,
    v_text
  );

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_ttl_co, v_owner, 'premium_monthly', 'idem-ttl-new', now()
    );
    v_session_ttl_new := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'ttl_reserve_creates_new_after_stale',
      v_reserve.reuse = FALSE AND v_session_ttl_new IS DISTINCT FROM v_session_ttl_old
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'ttl_reserve_creates_new_after_stale', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  SELECT checkout_status INTO v_text
  FROM private.billing_checkout_sessions WHERE id = v_session_ttl_old;
  PERFORM pg_temp.record_result(
    'ttl_reserve_marks_stale_expired',
    v_text = 'expired',
    NULL,
    v_text
  );

  -- =========================================================================
  -- Reuse keeps session price FK snapshot (P1) after catalog moves to P2
  -- =========================================================================
  v_price_p1 := v_seed_price_id;
  SELECT external_price_id INTO v_ext_p1
  FROM private.billing_provider_prices WHERE id = v_price_p1;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_reuse_co, v_owner, 'premium_monthly', 'idem-reuse-p1', now()
    );
    v_session_reuse := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'reuse_reserve_p1_ok',
      v_reserve.billing_provider_price_id = v_price_p1
        AND v_reserve.external_price_id = v_ext_p1
        AND v_reserve.reuse = FALSE
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('reuse_reserve_p1_ok', false, v_sqlstate, v_err);
  END;
  RESET ROLE;

  -- Append-only: close P1 current, insert P2 current
  UPDATE private.billing_provider_prices
  SET is_active = false, valid_to = now()
  WHERE id = v_price_p1;

  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_test_p2', 'pri_test_p2',
    12.99, 'EUR', now() - interval '1 minute', NULL, true
  )
  RETURNING id, external_price_id INTO v_price_p2, v_ext_p2;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_reuse_co, v_owner, 'premium_monthly', 'idem-reuse-p1', now()
    );
    PERFORM pg_temp.record_result(
      'reuse_keeps_p1_price_after_catalog_change',
      v_reserve.reuse = TRUE
        AND v_reserve.session_id = v_session_reuse
        AND v_reserve.billing_provider_price_id = v_price_p1
        AND v_reserve.external_price_id = v_ext_p1
        AND v_reserve.return_token_version = 2
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reuse_keeps_p1_price_after_catalog_change', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  -- Close reuse session so a new key can reserve with P2
  UPDATE private.billing_checkout_sessions
  SET checkout_status = 'abandoned', updated_at = now()
  WHERE id = v_session_reuse;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_reuse_co, v_owner, 'premium_monthly', 'idem-reuse-p2', now()
    );
    v_session_reuse_new := v_reserve.session_id;
    PERFORM pg_temp.record_result(
      'new_session_uses_p2_after_catalog_change',
      v_reserve.reuse = FALSE
        AND v_reserve.billing_provider_price_id = v_price_p2
        AND v_reserve.external_price_id = v_ext_p2
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'new_session_uses_p2_after_catalog_change', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  -- =========================================================================
  -- Attach / confirm guards on failed / expired / abandoned
  -- =========================================================================
  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_guard_co, v_owner, 'premium_monthly', 'idem-guard-open', now()
    );
    v_session_guard := v_reserve.session_id;
    v_token_guard := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result(
      'guard_open_reserve_ok', v_session_guard IS NOT NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('guard_open_reserve_ok', false, v_sqlstate, v_err);
  END;

  -- Clone-like sessions for failed/abandoned/expired via additional reserves then force status
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_guard_co, v_owner, 'premium_monthly', 'idem-guard-failed', now()
    );
    PERFORM pg_temp.record_result(
      'guard_second_open_denied_while_first_open', false, NULL, 'expected already open'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'guard_second_open_denied_while_first_open',
      v_err = 'ATLAS_CHECKOUT_ALREADY_OPEN',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Force open session past TTL (keep status created; backdate created_at for CHECK)
  UPDATE private.billing_checkout_sessions
  SET
    created_at = now() - interval '1 hour',
    expires_at = now() - interval '1 second',
    updated_at = now()
  WHERE id = v_session_guard;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_guard, v_owner, 'not_started', 'processing', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_on_expired_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_on_expired_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session_guard, v_owner, v_token_guard, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_on_expired_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_on_expired_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  SELECT
    provider_create_status AS pcs,
    checkout_status AS cs,
    external_transaction_id AS txn,
    checkout_url AS url,
    return_token_consumed_at AS consumed,
    browser_signal AS sig
  INTO v_sess_snap
  FROM private.billing_checkout_sessions WHERE id = v_session_guard;

  PERFORM pg_temp.record_result(
    'attach_confirm_expired_no_mutation',
    v_sess_snap.pcs = 'not_started'
      AND v_sess_snap.cs = 'created'
      AND v_sess_snap.consumed IS NULL
      AND v_sess_snap.sig = 'none'
      AND v_sess_snap.txn IS NULL
      AND v_sess_snap.url IS NULL
  );

  -- Materialize expired status so unique open slot frees; then create failed/abandoned cases
  UPDATE private.billing_checkout_sessions
  SET checkout_status = 'expired', updated_at = now()
  WHERE id = v_session_guard;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_guard_co, v_owner, 'premium_monthly', 'idem-guard-failed', now()
    );
    v_session_guard_failed := v_reserve.session_id;
    v_token_guard := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result(
      'guard_failed_session_reserve_ok', v_session_guard_failed IS NOT NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'guard_failed_session_reserve_ok', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  UPDATE private.billing_checkout_sessions
  SET
    provider_create_status = 'failed',
    checkout_status = 'failed',
    updated_at = now()
  WHERE id = v_session_guard_failed;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_guard_failed, v_owner, 'failed', 'created',
      'txn_bad', 'https://checkout.paddle.example/bad', NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_on_failed_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_on_failed_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session_guard_failed, v_owner, v_token_guard, 'checkout_closed', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_on_failed_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_on_failed_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'confirm_on_failed_token_not_consumed',
    (SELECT return_token_consumed_at FROM private.billing_checkout_sessions
      WHERE id = v_session_guard_failed) IS NULL
  );

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_guard_co, v_owner, 'premium_monthly', 'idem-guard-abandoned', now()
    );
    v_session_guard_abandoned := v_reserve.session_id;
    v_token_guard := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result(
      'guard_abandoned_session_reserve_ok', v_session_guard_abandoned IS NOT NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'guard_abandoned_session_reserve_ok', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  UPDATE private.billing_checkout_sessions
  SET checkout_status = 'abandoned', updated_at = now()
  WHERE id = v_session_guard_abandoned;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_guard_abandoned, v_owner, 'not_started', 'processing',
      NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_on_abandoned_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'attach_on_abandoned_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session_guard_abandoned, v_owner, v_token_guard, 'checkout_closed', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_on_abandoned_fails', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_on_abandoned_fails',
      v_err = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'confirm_on_abandoned_token_not_consumed',
    (SELECT return_token_consumed_at FROM private.billing_checkout_sessions
      WHERE id = v_session_guard_abandoned) IS NULL
  );

  -- Open non-expired attach+confirm still works (side-effects company)
  SELECT b.external_customer_id, b.external_subscription_id, b.sync_status,
         b.provider_access_status, s.entitlement_origin, s.plan_code
  INTO v_text, v_text2, v_token1, v_token2, v_ext_p1, v_ext_p2
  FROM private.company_billing b
  JOIN public.company_subscriptions s ON s.company_id = b.company_id
  WHERE b.company_id = v_side_co;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_side_co, v_owner, 'premium_monthly', 'idem-side-1', now()
    );
    v_session_side := v_reserve.session_id;
    v_token_side := v_reserve.return_token_plain;
    PERFORM pg_temp.record_result('side_reserve_ok', v_session_side IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('side_reserve_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_attach
    FROM public.attach_billing_checkout_provider_result_server(
      v_session_side, v_owner, 'not_started', 'processing', NULL, NULL, NULL, now()
    );
    PERFORM pg_temp.record_result(
      'attach_on_open_still_works',
      v_attach.applied = TRUE AND v_attach.provider_create_status = 'processing'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('attach_on_open_still_works', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session_side, v_owner, v_token_side, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_on_open_still_works',
      v_confirm.ok = TRUE AND v_confirm.checkout_status = 'opened'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('confirm_on_open_still_works', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_confirm
    FROM public.confirm_billing_checkout_browser_signal_server(
      v_session_side, v_owner, v_token_side, 'completion_signaled', now()
    );
    PERFORM pg_temp.record_result(
      'confirm_second_use_still_fails', false, NULL, 'expected consumed'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'confirm_second_use_still_fails',
      v_err = 'ATLAS_RETURN_TOKEN_CONSUMED',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'side_effects_billing_unchanged',
    EXISTS (
      SELECT 1
      FROM private.company_billing b
      JOIN public.company_subscriptions s ON s.company_id = b.company_id
      WHERE b.company_id = v_side_co
        AND b.external_customer_id IS NOT DISTINCT FROM v_text
        AND b.external_subscription_id IS NOT DISTINCT FROM v_text2
        AND b.sync_status IS NOT DISTINCT FROM v_token1
        AND b.provider_access_status IS NOT DISTINCT FROM v_token2
        AND s.entitlement_origin IS NOT DISTINCT FROM v_ext_p1
        AND s.plan_code IS NOT DISTINCT FROM v_ext_p2
    )
  );

  -- =========================================================================
  -- SCHEMA SHAPE — sessions table must not carry cancel_path / external_customer_id
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'sessions_no_cancel_path_column',
    NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'private'
        AND c.table_name = 'billing_checkout_sessions'
        AND c.column_name = 'cancel_path'
    )
  );
  PERFORM pg_temp.record_result(
    'sessions_no_external_customer_id_column',
    NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'private'
        AND c.table_name = 'billing_checkout_sessions'
        AND c.column_name = 'external_customer_id'
    )
  );

END;
$$;

SELECT test_name, passed FROM test_results ORDER BY 1;
SELECT count(*) FILTER (WHERE NOT passed) AS failed FROM test_results;

ROLLBACK;
