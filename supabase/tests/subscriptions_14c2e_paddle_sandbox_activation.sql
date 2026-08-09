-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2E-C-B
-- Paddle Sandbox fail-closed seed (migration 20260809122001 only).
-- Does NOT require or assume checkout_enabled=true.
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
  v_company UUID;
  v_company_row public.companies%ROWTYPE;
  v_offer_id UUID;
  v_price_id UUID;
  v_cfg_id UUID;
  v_bool BOOLEAN;
  v_int INTEGER;
  v_text TEXT;
  v_text2 TEXT;
  v_sqlstate TEXT;
  v_err TEXT;
  v_reserve RECORD;

  v_plan TEXT;
  v_status TEXT;
  v_origin TEXT;
  v_provider_code TEXT;
  v_access TEXT;
  v_sync TEXT;
  v_ext_customer TEXT;
  v_ext_sub TEXT;
  v_ext_price TEXT;
  v_product_id TEXT;
  v_price_ext TEXT;
  v_amount TEXT;
  v_currency TEXT;
  v_valid_from TIMESTAMPTZ;
  v_valid_to_null BOOLEAN;
  v_price_active BOOLEAN;
  v_sessions_before INTEGER;
  v_events_before INTEGER;
  v_sessions_after INTEGER;
  v_events_after INTEGER;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2e@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    '14C2E Seed Co',
    'company-14c2e-seed-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  -- =========================================================================
  -- A. Logical offer
  -- =========================================================================
  SELECT count(*)::integer INTO v_int
  FROM private.billing_offers
  WHERE offer_code = 'premium_monthly';
  PERFORM pg_temp.record_result('offer_premium_monthly_once', v_int = 1, NULL, v_int::text);

  SELECT id, atlas_plan_code, billing_interval, interval_count::text, is_active::text
  INTO v_offer_id, v_text, v_text2, v_plan, v_status
  FROM private.billing_offers
  WHERE offer_code = 'premium_monthly';

  PERFORM pg_temp.record_result(
    'offer_premium_monthly_shape',
    v_offer_id IS NOT NULL
      AND v_text = 'premium'
      AND v_text2 = 'month'
      AND v_plan = '1'
      AND v_status = 'true',
    NULL,
    format('%s/%s/%s/%s', v_text, v_text2, v_plan, v_status)
  );

  -- =========================================================================
  -- B. Provider price (seed)
  -- =========================================================================
  SELECT count(*)::integer INTO v_int
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer_id
    AND p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active IS TRUE
    AND p.valid_to IS NULL;
  PERFORM pg_temp.record_result(
    'price_current_active_once', v_int = 1, NULL, v_int::text
  );

  SELECT p.id,
         p.external_product_id,
         p.external_price_id,
         p.base_amount::text,
         p.currency,
         p.valid_from,
         (p.valid_to IS NULL),
         p.is_active
  INTO v_price_id,
       v_product_id,
       v_price_ext,
       v_amount,
       v_currency,
       v_valid_from,
       v_valid_to_null,
       v_price_active
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer_id
    AND p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active IS TRUE
    AND p.valid_to IS NULL;

  PERFORM pg_temp.record_result(
    'price_external_product_id',
    v_product_id = 'pro_01kze8m55z7c6vdp4pe66bkrch',
    NULL,
    v_product_id
  );
  PERFORM pg_temp.record_result(
    'price_external_price_id',
    v_price_ext = 'pri_01kze90z27wy6m0fpxpebaewjv',
    NULL,
    v_price_ext
  );
  PERFORM pg_temp.record_result(
    'price_base_amount_eur',
    v_amount = '11.99' AND v_currency = 'EUR',
    NULL,
    format('%s %s', v_amount, v_currency)
  );
  PERFORM pg_temp.record_result(
    'price_valid_from_fixed',
    v_valid_from = TIMESTAMPTZ '2026-08-09 00:00:00+00',
    NULL,
    v_valid_from::text
  );
  PERFORM pg_temp.record_result(
    'price_valid_to_null_active',
    v_valid_to_null IS TRUE AND v_price_active IS TRUE
  );

  -- =========================================================================
  -- C. Runtime config (fail-closed)
  -- =========================================================================
  SELECT count(*)::integer INTO v_int FROM private.billing_runtime_config;
  PERFORM pg_temp.record_result('runtime_config_exactly_one', v_int = 1, NULL, v_int::text);

  SELECT c.id,
         c.provider_code,
         c.provider_environment,
         c.payment_page_origin,
         c.checkout_path,
         c.return_path,
         c.is_active,
         c.checkout_enabled
  INTO v_cfg_id,
       v_provider_code,
       v_access,
       v_text,
       v_text2,
       v_origin,
       v_bool,
       v_price_active
  FROM private.billing_runtime_config c;

  PERFORM pg_temp.record_result(
    'runtime_provider_paddle_test',
    v_provider_code = 'paddle' AND v_access = 'test',
    NULL,
    format('%s/%s', v_provider_code, v_access)
  );
  PERFORM pg_temp.record_result(
    'runtime_origin_exact',
    v_text = 'https://project-atlas-bxh.pages.dev',
    NULL,
    v_text
  );
  PERFORM pg_temp.record_result(
    'runtime_paths_exact',
    v_text2 = '/billing/checkout' AND v_origin = '/billing/return',
    NULL,
    format('%s|%s', v_text2, v_origin)
  );
  PERFORM pg_temp.record_result(
    'runtime_active_checkout_disabled',
    v_bool IS TRUE AND v_price_active IS FALSE
  );

  -- =========================================================================
  -- D. Fail-closed behavior
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_false_while_checkout_disabled',
    v_bool = FALSE,
    NULL,
    v_bool::text
  );
  RESET ROLE;

  SELECT private.is_company_checkout_eligible(v_company, v_owner, now())
  INTO v_bool;
  PERFORM pg_temp.record_result(
    'private_eligible_false_while_disabled',
    v_bool = FALSE,
    NULL,
    v_bool::text
  );

  SELECT count(*)::integer INTO v_sessions_before
  FROM private.billing_checkout_sessions;
  SELECT count(*)::integer INTO v_events_before
  FROM private.billing_provider_events;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-14c2e-disabled', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_unavailable_while_disabled', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_unavailable_while_disabled',
      v_err = 'ATLAS_CHECKOUT_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  SELECT count(*)::integer INTO v_sessions_after
  FROM private.billing_checkout_sessions;
  SELECT count(*)::integer INTO v_events_after
  FROM private.billing_provider_events;

  PERFORM pg_temp.record_result(
    'no_session_created_by_disabled_reserve',
    v_sessions_after = v_sessions_before,
    NULL,
    format('%s->%s', v_sessions_before, v_sessions_after)
  );
  PERFORM pg_temp.record_result(
    'no_provider_events_from_disabled_reserve',
    v_events_after = v_events_before,
    NULL,
    format('%s->%s', v_events_before, v_events_after)
  );

  -- Seed alone must not create checkout sessions globally (beyond fixtures none)
  PERFORM pg_temp.record_result(
    'seed_created_zero_checkout_sessions',
    (
      SELECT count(*)::integer
      FROM private.billing_checkout_sessions
    ) = 0
  );

  -- =========================================================================
  -- E. Entitlement integrity for fixture company
  -- =========================================================================
  SELECT s.plan_code, s.status, s.entitlement_origin,
         b.provider_code, b.provider_access_status, b.sync_status,
         b.external_customer_id, b.external_subscription_id, b.external_price_id
  INTO v_plan, v_status, v_origin,
       v_provider_code, v_access, v_sync,
       v_ext_customer, v_ext_sub, v_ext_price
  FROM public.company_subscriptions s
  JOIN private.company_billing b ON b.company_id = s.company_id
  WHERE s.company_id = v_company;

  PERFORM pg_temp.record_result(
    'entitlement_unchanged_free_none',
    v_plan = 'free'
      AND v_status = 'free'
      AND v_origin = 'none'
      AND v_provider_code IS NULL
      AND v_access = 'none'
      AND v_sync = 'idle'
      AND v_ext_customer IS NULL
      AND v_ext_sub IS NULL
      AND v_ext_price IS NULL,
    NULL,
    format('%s/%s/%s/%s/%s', v_plan, v_status, v_origin, v_access, v_sync)
  );

  -- =========================================================================
  -- F. Invariants
  -- =========================================================================
  BEGIN
    INSERT INTO private.billing_provider_prices (
      offer_id, provider_code, provider_environment,
      external_product_id, external_price_id,
      base_amount, currency, valid_from, valid_to, is_active
    ) VALUES (
      v_offer_id, 'paddle', 'test',
      'pro_dup_14c2e', 'pri_dup_14c2e_active',
      11.99, 'EUR', TIMESTAMPTZ '2026-08-09 00:00:00+00', NULL, TRUE
    );
    PERFORM pg_temp.record_result(
      'duplicate_current_active_price_rejected', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result(
      'duplicate_current_active_price_rejected', true, '23505', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'duplicate_current_active_price_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_runtime_config (
      provider_code, provider_environment, checkout_enabled,
      payment_page_origin, checkout_path, return_path, is_active
    ) VALUES (
      'paddle', 'live', false,
      'https://project-atlas-bxh.pages.dev',
      '/billing/checkout', '/billing/return', TRUE
    );
    PERFORM pg_temp.record_result(
      'second_active_runtime_config_rejected', false, NULL, 'expected unique violation'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result(
      'second_active_runtime_config_rejected', true, '23505', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'second_active_runtime_config_rejected', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET base_amount = 12.99
    WHERE id = v_price_id;
    PERFORM pg_temp.record_result(
      'price_immutable_base_amount', false, NULL, 'expected immutable guard'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_immutable_base_amount',
      v_err = 'ATLAS_BILLING_PRICE_IMMUTABLE',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    UPDATE private.billing_provider_prices
    SET external_price_id = 'pri_mutated_forbidden'
    WHERE id = v_price_id;
    PERFORM pg_temp.record_result(
      'price_immutable_external_price_id', false, NULL, 'expected immutable guard'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'price_immutable_external_price_id',
      v_err = 'ATLAS_BILLING_PRICE_IMMUTABLE',
      v_sqlstate,
      v_err
    );
  END;

  -- Confirm seed still fail-closed after invariant probes
  SELECT checkout_enabled INTO v_bool
  FROM private.billing_runtime_config
  WHERE id = v_cfg_id;
  PERFORM pg_temp.record_result(
    'checkout_enabled_still_false_after_probes',
    v_bool IS FALSE
  );
END;
$$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY 1;

SELECT
  count(*) FILTER (WHERE passed) AS passed,
  count(*) FILTER (WHERE NOT passed) AS failed,
  count(*) AS total
FROM test_results;

ROLLBACK;
