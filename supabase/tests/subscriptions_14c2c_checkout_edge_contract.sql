-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2C checkout edge contract
-- reserve runtime outputs, eligibility gates, service_role grants.
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
  v_company UUID;
  v_trial_co UUID;
  v_manual_co UUID;
  v_sync_co UUID;
  v_linked_co UUID;
  v_ended_co UUID;
  v_provider_co UUID;
  v_offer_id UUID;
  v_price_id UUID;
  v_cfg_id UUID;
  v_company_row public.companies%ROWTYPE;
  v_reserve RECORD;
  v_bool BOOLEAN;
  v_sqlstate TEXT;
  v_err TEXT;
  v_names TEXT[];
  v_types TEXT[];
  v_session_count INTEGER;
  v_price_ext TEXT;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14c2c@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'member14c2c@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Free Co',
    'company-14c2c-free-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Trial Co',
    'company-14c2c-trial-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_trial_co := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Manual Co',
    'company-14c2c-manual-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_manual_co := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Sync Co',
    'company-14c2c-sync-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_sync_co := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Linked Co',
    'company-14c2c-linked-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_linked_co := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Ended Linked Co',
    'company-14c2c-ended-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_ended_co := v_company_row.id;

  SELECT * INTO v_company_row
  FROM public.create_company(
    '14c2c Provider Premium Co',
    'company-14c2c-prov-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_provider_co := v_company_row.id;
  RESET ROLE;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_company, v_member, 'employee')
  ON CONFLICT DO NOTHING;

  -- -------------------------------------------------------------------------
  -- Grants: service_role only on reserve wrapper
  -- -------------------------------------------------------------------------
  PERFORM pg_temp.record_result(
    'reserve_server_service_role_execute',
    has_function_privilege(
      'service_role',
      'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
      'EXECUTE'
    )
  );
  PERFORM pg_temp.record_result(
    'reserve_server_anon_no_execute',
    NOT has_function_privilege(
      'anon',
      'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
      'EXECUTE'
    )
  );
  PERFORM pg_temp.record_result(
    'reserve_server_authenticated_no_execute',
    NOT has_function_privilege(
      'authenticated',
      'public.reserve_billing_checkout_session_server(uuid,uuid,text,text,timestamptz)',
      'EXECUTE'
    )
  );

  -- Output column order + exact types: original 14 first, then 5 runtime fields
  SELECT
    array_agg(argument.argument_name ORDER BY argument.ordinality),
    array_agg(format_type(argument.type_oid, NULL) ORDER BY argument.ordinality)
  INTO v_names, v_types
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL unnest(
    p.proargnames,
    p.proallargtypes,
    p.proargmodes
  ) WITH ORDINALITY AS argument(
    argument_name,
    type_oid,
    argument_mode,
    ordinality
  )
  WHERE n.nspname = 'public'
    AND p.proname = 'reserve_billing_checkout_session_server'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_company_id uuid, p_actor_user_id uuid, p_offer_code text, p_idempotency_key text, p_now timestamp with time zone'
    AND argument.argument_mode IN ('t', 'o', 'b');

  PERFORM pg_temp.record_result(
    'reserve_output_column_order',
    v_names = ARRAY[
      'session_id',
      'reuse',
      'provider_environment',
      'billing_provider_price_id',
      'external_price_id',
      'atlas_plan_code',
      'offer_code',
      'checkout_status',
      'provider_create_status',
      'return_token_plain',
      'return_token_version',
      'expires_at',
      'existing_checkout_url',
      'existing_external_transaction_id',
      'provider_code',
      'payment_page_origin',
      'checkout_path',
      'return_path',
      'checkout_page_url'
    ]::text[],
    NULL,
    array_to_string(v_names, ',')
  );

  PERFORM pg_temp.record_result(
    'reserve_output_column_types',
    v_types = ARRAY[
      'uuid',
      'boolean',
      'text',
      'uuid',
      'text',
      'text',
      'text',
      'text',
      'text',
      'text',
      'integer',
      'timestamp with time zone',
      'text',
      'text',
      'text',
      'text',
      'text',
      'text',
      'text'
    ]::text[],
    NULL,
    array_to_string(v_types, ',')
  );

  -- Fail-closed: no active config
  DELETE FROM private.billing_runtime_config;

  -- 14C-2E seed installs one current active paddle/test price. End it so this
  -- suite can insert isolated fixture prices (transaction rolls back).
  UPDATE private.billing_provider_prices p
  SET is_active = false,
      valid_to = now()
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active IS TRUE
    AND p.valid_to IS NULL;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_false_without_runtime_config', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-no-cfg', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_without_runtime_config', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_without_runtime_config',
      v_err = 'ATLAS_CHECKOUT_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Seed active config + price
  INSERT INTO private.billing_runtime_config (
    provider_code, provider_environment, checkout_enabled,
    payment_page_origin, checkout_path, return_path, is_active
  ) VALUES (
    'paddle', 'test', true,
    'https://pay.atlas.test', '/billing/checkout', '/billing/return', true
  )
  RETURNING id INTO v_cfg_id;

  SELECT id INTO v_offer_id
  FROM private.billing_offers WHERE offer_code = 'premium_monthly';

  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_test_14c2c', 'pri_test_14c2c',
    11.99, 'EUR', now() - interval '1 hour', NULL, true
  )
  RETURNING id INTO v_price_id;

  -- Disabled config
  UPDATE private.billing_runtime_config
  SET checkout_enabled = false
  WHERE id = v_cfg_id;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_false_when_checkout_disabled', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-disabled', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_when_checkout_disabled', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_when_checkout_disabled',
      v_err = 'ATLAS_CHECKOUT_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  UPDATE private.billing_runtime_config
  SET checkout_enabled = true
  WHERE id = v_cfg_id;

  -- Unlinked free owner eligible
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_true_unlinked_free_owner', v_bool = TRUE, NULL, v_bool::text
  );
  RESET ROLE;

  -- -------------------------------------------------------------------------
  -- Provider price fail-closed: inactive / ended / missing (restore after each)
  -- -------------------------------------------------------------------------
  SELECT count(*)::integer INTO v_session_count
  FROM private.billing_checkout_sessions
  WHERE company_id = v_company;

  -- A. price exists but is_active = false
  UPDATE private.billing_provider_prices
  SET is_active = false
  WHERE id = v_price_id;

  SELECT private.is_company_checkout_eligible(v_company, v_owner, now())
  INTO v_bool;
  PERFORM pg_temp.record_result(
    'eligible_false_price_inactive', v_bool = FALSE, NULL, v_bool::text
  );

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-price-inactive', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_price_inactive', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_price_inactive',
      v_err = 'ATLAS_PRICE_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'no_session_created_price_inactive',
    (
      SELECT count(*)::integer
      FROM private.billing_checkout_sessions
      WHERE company_id = v_company
    ) = v_session_count
  );

  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_test_14c2c',
    'pri_test_14c2c_a_' || substr(gen_random_uuid()::text, 1, 8),
    11.99, 'EUR', now() - interval '1 hour', NULL, true
  )
  RETURNING id INTO v_price_id;

  -- B. price exists but valid_to IS NOT NULL
  UPDATE private.billing_provider_prices
  SET valid_to = now()
  WHERE id = v_price_id;

  SELECT private.is_company_checkout_eligible(v_company, v_owner, now())
  INTO v_bool;
  PERFORM pg_temp.record_result(
    'eligible_false_price_ended', v_bool = FALSE, NULL, v_bool::text
  );

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-price-ended', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_price_ended', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_price_ended',
      v_err = 'ATLAS_PRICE_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'no_session_created_price_ended',
    (
      SELECT count(*)::integer
      FROM private.billing_checkout_sessions
      WHERE company_id = v_company
    ) = v_session_count
  );

  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_test_14c2c',
    'pri_test_14c2c_b_' || substr(gen_random_uuid()::text, 1, 8),
    11.99, 'EUR', now() - interval '1 hour', NULL, true
  )
  RETURNING id INTO v_price_id;

  -- C. no matching current provider-price row
  UPDATE private.billing_provider_prices
  SET is_active = false, valid_to = coalesce(valid_to, now())
  WHERE id = v_price_id;

  SELECT private.is_company_checkout_eligible(v_company, v_owner, now())
  INTO v_bool;
  PERFORM pg_temp.record_result(
    'eligible_false_price_missing', v_bool = FALSE, NULL, v_bool::text
  );

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-price-missing', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_price_missing', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_price_missing',
      v_err = 'ATLAS_PRICE_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'no_session_created_price_missing',
    (
      SELECT count(*)::integer
      FROM private.billing_checkout_sessions
      WHERE company_id = v_company
    ) = v_session_count
  );

  INSERT INTO private.billing_provider_prices (
    offer_id, provider_code, provider_environment,
    external_product_id, external_price_id,
    base_amount, currency, valid_from, valid_to, is_active
  ) VALUES (
    v_offer_id, 'paddle', 'test',
    'pro_test_14c2c',
    'pri_test_14c2c_ok_' || substr(gen_random_uuid()::text, 1, 8),
    11.99, 'EUR', now() - interval '1 hour', NULL, true
  )
  RETURNING id, external_price_id INTO v_price_id, v_price_ext;

  SELECT private.is_company_checkout_eligible(v_company, v_owner, now())
  INTO v_bool;
  PERFORM pg_temp.record_result(
    'eligible_true_after_price_restore', v_bool = TRUE, NULL, v_bool::text
  );

  -- Member not eligible
  PERFORM pg_temp.set_auth(v_member);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_false_member', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- Reserve success with appended runtime outputs
  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-ok-1', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_original_columns_present',
      v_reserve.session_id IS NOT NULL
        AND v_reserve.reuse = FALSE
        AND v_reserve.provider_environment = 'test'
        AND v_reserve.external_price_id = v_price_ext
        AND v_reserve.atlas_plan_code = 'premium'
        AND v_reserve.offer_code = 'premium_monthly'
        AND v_reserve.checkout_status = 'created'
        AND v_reserve.provider_create_status = 'not_started'
        AND v_reserve.return_token_plain IS NOT NULL
        AND v_reserve.return_token_version = 1
        AND v_reserve.expires_at IS NOT NULL
        AND v_reserve.existing_checkout_url IS NULL
        AND v_reserve.existing_external_transaction_id IS NULL
    );
    PERFORM pg_temp.record_result(
      'reserve_runtime_outputs_correct',
      v_reserve.provider_code = 'paddle'
        AND v_reserve.payment_page_origin = 'https://pay.atlas.test'
        AND v_reserve.checkout_path = '/billing/checkout'
        AND v_reserve.return_path = '/billing/return'
        AND v_reserve.checkout_page_url = 'https://pay.atlas.test/billing/checkout',
      NULL,
      coalesce(v_reserve.checkout_page_url, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_original_columns_present', false, v_sqlstate, v_err
    );
    PERFORM pg_temp.record_result(
      'reserve_runtime_outputs_correct', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  -- Open non-expired checkout session blocks eligibility
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_company);
  PERFORM pg_temp.record_result(
    'eligible_false_open_checkout_session', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- Trial remains eligible
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  PERFORM public.activate_company_premium_trial(v_trial_co);
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_trial_co);
  PERFORM pg_temp.record_result(
    'eligible_true_during_atlas_trial', v_bool = TRUE, NULL, v_bool::text
  );
  RESET ROLE;

  -- Manual Premium blocked
  UPDATE public.company_subscriptions
  SET status = 'active',
      plan_code = 'premium',
      entitlement_origin = 'manual'
  WHERE company_id = v_manual_co;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_manual_co);
  PERFORM pg_temp.record_result(
    'eligible_false_manual_premium', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_manual_co, v_owner, 'premium_monthly', 'idem-manual', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_manual_premium', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_manual_premium',
      v_err = 'ATLAS_CHECKOUT_NOT_ELIGIBLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Non-idle sync blocked
  UPDATE private.company_billing
  SET sync_status = 'pending'
  WHERE company_id = v_sync_co;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_sync_co);
  PERFORM pg_temp.record_result(
    'eligible_false_non_idle_sync', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_sync_co, v_owner, 'premium_monthly', 'idem-sync', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_non_idle_sync', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_non_idle_sync',
      v_err = 'ATLAS_CHECKOUT_NOT_ELIGIBLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Provider-linked blocked
  UPDATE private.company_billing
  SET provider_code = 'paddle',
      provider_environment = 'test',
      external_customer_id = 'ctm_test_14c2c'
  WHERE company_id = v_linked_co;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_linked_co);
  PERFORM pg_temp.record_result(
    'eligible_false_provider_linked', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_linked_co, v_owner, 'premium_monthly', 'idem-linked', now()
    );
    PERFORM pg_temp.record_result(
      'reserve_fails_provider_linked', false, NULL, 'expected exception'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'reserve_fails_provider_linked',
      v_err = 'ATLAS_CHECKOUT_NOT_ELIGIBLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Ended-but-linked billing remains ineligible
  UPDATE public.company_subscriptions
  SET status = 'free',
      plan_code = 'free',
      entitlement_origin = 'provider'
  WHERE company_id = v_ended_co;
  UPDATE private.company_billing
  SET provider_code = 'paddle',
      provider_environment = 'test',
      external_customer_id = 'ctm_ended_14c2c',
      external_subscription_id = 'sub_ended_14c2c',
      subscription_status = 'ended',
      provider_access_status = 'ended'
  WHERE company_id = v_ended_co;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_ended_co);
  PERFORM pg_temp.record_result(
    'eligible_false_ended_but_linked', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- Provider-derived active Premium blocks eligibility
  UPDATE public.company_subscriptions
  SET status = 'active',
      plan_code = 'premium',
      entitlement_origin = 'provider'
  WHERE company_id = v_provider_co;
  UPDATE private.company_billing
  SET provider_code = 'paddle',
      provider_environment = 'test',
      external_customer_id = 'ctm_prov_14c2c',
      external_subscription_id = 'sub_prov_14c2c',
      subscription_status = 'active',
      provider_access_status = 'entitled',
      provider_access_ends_at = now() + interval '30 days'
  WHERE company_id = v_provider_co;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT is_checkout_eligible INTO v_bool
  FROM public.get_company_subscription_overview(v_provider_co);
  PERFORM pg_temp.record_result(
    'eligible_false_provider_active_premium', v_bool = FALSE, NULL, v_bool::text
  );
  RESET ROLE;

  -- Ambiguous config: deactivate unique active constraint path by inserting
  -- a second inactive row is fine; true ambiguity is impossible with one_active
  -- unique index, so verify the unique index still exists.
  PERFORM pg_temp.record_result(
    'runtime_config_one_active_index_present',
    EXISTS (
      SELECT 1
      FROM pg_indexes
      WHERE schemaname = 'private'
        AND indexname = 'billing_runtime_config_one_active_uidx'
    )
  );

  -- Anon cannot execute wrapper (role switch) — privilege only (SQLSTATE 42501)
  SET LOCAL ROLE anon;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-anon', now()
    );
    PERFORM pg_temp.record_result(
      'anon_cannot_execute_reserve_server', false, NULL, 'expected privilege error'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'anon_cannot_execute_reserve_server',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'anon_cannot_execute_reserve_server',
      false,
      v_sqlstate,
      'expected 42501, got: ' || coalesce(v_err, '')
    );
  END;
  RESET ROLE;

  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT * INTO v_reserve
    FROM public.reserve_billing_checkout_session_server(
      v_company, v_owner, 'premium_monthly', 'idem-auth', now()
    );
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_reserve_server',
      false,
      NULL,
      'expected privilege error'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_reserve_server',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_reserve_server',
      false,
      v_sqlstate,
      'expected 42501, got: ' || coalesce(v_err, '')
    );
  END;
  RESET ROLE;
END;
$$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) AS total,
  count(*) FILTER (WHERE passed) AS passed,
  count(*) FILTER (WHERE NOT passed) AS failed
FROM test_results;

DO $$
DECLARE
  v_failed INTEGER;
BEGIN
  SELECT count(*)::integer INTO v_failed FROM test_results WHERE NOT passed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION '14C-2C contract tests failed: %', v_failed;
  END IF;
END;
$$;

ROLLBACK;
