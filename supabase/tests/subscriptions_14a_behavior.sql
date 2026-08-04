-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14A plans + company_subscriptions behavior
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
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO anon;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_new_company UUID;
  v_count BIGINT;
  v_limit INTEGER;
  v_code TEXT;
  v_status TEXT;
  v_trial_active BOOLEAN;
  v_eff TEXT;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin14a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager14a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee14a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Company 14A A', 'company-14a-a-' || substr(v_company_a::text, 1, 8)),
    (v_company_b, 'Company 14A B', 'company-14a-b-' || substr(v_company_b::text, 1, 8));

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner');

  -- Backfill already ran in migration for companies present at migrate time.
  -- These companies were inserted after migration in this transaction: seed Free manually
  -- to mirror production backfill semantics for late inserts outside create_company.
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_company_a, 'free', 'free', 'none'), (v_company_b, 'free', 'free', 'none')
  ON CONFLICT (company_id) DO NOTHING;

  INSERT INTO private.company_billing (company_id)
  VALUES (v_company_a), (v_company_b)
  ON CONFLICT (company_id) DO NOTHING;

  -- Plans seed
  SELECT document_monthly_limit INTO v_limit FROM public.plans WHERE code = 'free';
  PERFORM pg_temp.record_result('plan_free_limit_30', v_limit = 30, NULL, v_limit::text);

  SELECT document_monthly_limit INTO v_limit FROM public.plans WHERE code = 'premium';
  PERFORM pg_temp.record_result('plan_premium_limit_null', v_limit IS NULL, NULL, COALESCE(v_limit::text, 'null'));

  SELECT count(*) INTO v_count FROM public.plans WHERE code IN ('free', 'premium') AND is_active;
  PERFORM pg_temp.record_result('plans_active_seed', v_count = 2, NULL, v_count::text);

  -- Backfill / one subscription
  SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result('one_subscription_per_company', v_count = 1, NULL, v_count::text);

  SELECT plan_code, status, trial_started_at IS NULL AND trial_ends_at IS NULL AND trial_used_at IS NULL
  INTO v_code, v_status, v_trial_active
  FROM public.company_subscriptions WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'existing_company_free_no_trial',
    v_code = 'free' AND v_status = 'free' AND v_trial_active,
    NULL,
    v_code || '/' || v_status
  );

  -- Idempotent conflict
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_company_a, 'free', 'free', 'none')
  ON CONFLICT (company_id) DO NOTHING;
  SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result('backfill_idempotent', v_count = 1, NULL, v_count::text);

  -- Authenticated reads plans
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT count(*) INTO v_count FROM public.plans WHERE is_active;
    PERFORM pg_temp.record_result('auth_reads_active_plans', v_count >= 2, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_reads_active_plans', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.plans (code, name, document_monthly_limit)
    VALUES ('hacker', 'Hacker', 1);
    PERFORM pg_temp.record_result('auth_insert_plans_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_insert_plans_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_insert_plans_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.plans SET name = 'X' WHERE code = 'free';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('auth_update_plans_noop_or_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_update_plans_noop_or_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_update_plans_noop_or_denied', false, v_sqlstate, v_err);
  END;

  -- Members read subscription (all roles)
  BEGIN
    SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('owner_reads_subscription', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_reads_subscription', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('admin_reads_subscription', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_reads_subscription', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('manager_reads_subscription', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_reads_subscription', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('employee_reads_subscription', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_reads_subscription', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('outsider_subscription_hidden', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('outsider_subscription_hidden', false, v_sqlstate, v_err);
  END;

  -- Direct mutations denied
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    UPDATE public.company_subscriptions SET plan_code = 'premium', status = 'active'
    WHERE company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('auth_update_subscription_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_update_subscription_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_update_subscription_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM public.company_subscriptions WHERE company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('auth_delete_subscription_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_delete_subscription_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_delete_subscription_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.company_subscriptions (company_id, plan_code, status)
    VALUES (v_company_a, 'premium', 'active');
    PERFORM pg_temp.record_result('auth_insert_subscription_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_insert_subscription_denied', true, '42501', 'rejected');
  WHEN unique_violation THEN
    PERFORM pg_temp.record_result('auth_insert_subscription_denied', true, '23505', 'unique');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'auth_insert_subscription_denied',
      v_sqlstate IN ('42501', '23505'),
      v_sqlstate,
      v_err
    );
  END;

  -- Effective plan Free
  SELECT effective_plan_code, document_monthly_limit, is_trial_active
  INTO v_eff, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'effective_free',
    v_eff = 'free' AND v_limit = 30 AND v_trial_active = FALSE,
    NULL,
    v_eff || '/' || COALESCE(v_limit::text, 'null')
  );

  -- Switch to trialing active (as postgres role for integrity setup)
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET plan_code = 'premium',
      status = 'trialing',
      entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '1 day',
      trial_ends_at = now() + interval '10 days',
      trial_used_at = now() - interval '1 day'
  WHERE company_id = v_company_a;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, document_monthly_limit, is_trial_active
  INTO v_eff, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'effective_trialing_active',
    v_eff = 'premium' AND v_limit IS NULL AND v_trial_active = TRUE,
    NULL,
    v_eff || '/' || COALESCE(v_limit::text, 'null')
  );

  RESET ROLE;
  UPDATE public.company_subscriptions
  SET trial_started_at = now() - interval '10 days',
      trial_ends_at = now() - interval '1 day'
  WHERE company_id = v_company_a;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, document_monthly_limit, is_trial_active
  INTO v_eff, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'effective_trialing_expired',
    v_eff = 'free' AND v_limit = 30 AND v_trial_active = FALSE,
    NULL,
    v_eff || '/' || COALESCE(v_limit::text, 'null')
  );

  RESET ROLE;
  UPDATE public.company_subscriptions
  SET status = 'active',
      plan_code = 'premium',
      entitlement_origin = 'manual',
      trial_started_at = NULL,
      trial_ends_at = NULL,
      trial_used_at = now()
  WHERE company_id = v_company_a;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, document_monthly_limit
  INTO v_eff, v_limit
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'effective_active_premium',
    v_eff = 'premium' AND v_limit IS NULL,
    NULL,
    v_eff || '/' || COALESCE(v_limit::text, 'null')
  );

  -- Outsider RPC denied
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM * FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('outsider_rpc_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('outsider_rpc_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('outsider_rpc_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  -- create_company Free subscription
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  SELECT id INTO v_new_company
  FROM public.create_company('New 14A Co', 'new-14a-' || substr(gen_random_uuid()::text, 1, 8));

  RESET ROLE;
  SELECT plan_code, status INTO v_code, v_status
  FROM public.company_subscriptions WHERE company_id = v_new_company;
  SELECT count(*) INTO v_count FROM public.company_members
  WHERE company_id = v_new_company AND user_id = v_owner AND role = 'owner';
  PERFORM pg_temp.record_result(
    'create_company_free_subscription',
    v_code = 'free' AND v_status = 'free' AND v_count = 1,
    NULL,
    COALESCE(v_code, 'null') || '/' || COALESCE(v_status, 'null')
  );

  -- Duplicate subscription PK
  BEGIN
    INSERT INTO public.company_subscriptions (company_id, plan_code, status)
    VALUES (v_new_company, 'free', 'free');
    PERFORM pg_temp.record_result('duplicate_subscription_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('duplicate_subscription_denied', true, '23505', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('duplicate_subscription_denied', v_sqlstate = '23505', v_sqlstate, v_err);
  END;

  -- Invalid plan FK
  BEGIN
    INSERT INTO public.company_subscriptions (company_id, plan_code, status)
    VALUES (gen_random_uuid(), 'does-not-exist', 'free');
    PERFORM pg_temp.record_result('invalid_plan_fk_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('invalid_plan_fk_denied', true, '23503', 'rejected');
  WHEN check_violation THEN
    PERFORM pg_temp.record_result('invalid_plan_fk_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'invalid_plan_fk_denied',
      v_sqlstate IN ('23503', '23514'),
      v_sqlstate,
      v_err
    );
  END;

  -- Delete used plan denied
  BEGIN
    DELETE FROM public.plans WHERE code = 'free';
    PERFORM pg_temp.record_result('delete_used_plan_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('delete_used_plan_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('delete_used_plan_denied', v_sqlstate = '23503', v_sqlstate, v_err);
  END;

  -- Constraint: free with trial dates invalid
  BEGIN
    UPDATE public.company_subscriptions
    SET trial_started_at = now()
    WHERE company_id = v_new_company;
    PERFORM pg_temp.record_result('free_with_trial_start_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('free_with_trial_start_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('free_with_trial_start_denied', v_sqlstate = '23514', v_sqlstate, v_err);
  END;

  -- Free with trial_used_at allowed (historical trial marker)
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET plan_code = 'free',
      status = 'free',
      entitlement_origin = 'none',
      trial_started_at = NULL,
      trial_ends_at = NULL,
      trial_used_at = now()
  WHERE company_id = v_company_a;
  SELECT count(*) INTO v_count
  FROM public.company_subscriptions
  WHERE company_id = v_company_a AND status = 'free' AND trial_used_at IS NOT NULL;
  PERFORM pg_temp.record_result('free_with_trial_used_at_allowed', v_count = 1, NULL, v_count::text);

  -- Premium active + premium plan inactive → overview still resolves
  UPDATE public.company_subscriptions
  SET plan_code = 'premium',
      status = 'active',
      entitlement_origin = 'manual',
      trial_started_at = NULL,
      trial_ends_at = NULL,
      trial_used_at = now()
  WHERE company_id = v_company_a;
  UPDATE public.plans SET is_active = false WHERE code = 'premium';

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, effective_plan_name, document_monthly_limit, is_trial_active
  INTO v_eff, v_code, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'inactive_premium_active_overview',
    v_eff = 'premium' AND v_code = 'Premium' AND v_limit IS NULL AND v_trial_active = FALSE,
    NULL,
    COALESCE(v_eff, 'null') || '/' || COALESCE(v_code, 'null')
  );

  -- Direct SELECT must not see inactive premium
  SELECT count(*) INTO v_count FROM public.plans WHERE code = 'premium';
  PERFORM pg_temp.record_result(
    'direct_select_inactive_premium_hidden',
    v_count = 0,
    NULL,
    v_count::text
  );

  -- Outsider still denied while premium inactive
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM * FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('outsider_inactive_plan_rpc_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('outsider_inactive_plan_rpc_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'outsider_inactive_plan_rpc_denied',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  -- Employee overview with inactive premium
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code INTO v_eff
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result('employee_inactive_premium_overview', v_eff = 'premium', NULL, v_eff);

  -- Admin / manager overview with inactive premium
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code INTO v_eff
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result('admin_inactive_premium_overview', v_eff = 'premium', NULL, v_eff);

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code INTO v_eff
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result('manager_inactive_premium_overview', v_eff = 'premium', NULL, v_eff);

  -- Trial active + premium inactive
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET status = 'trialing',
      plan_code = 'premium',
      entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '1 day',
      trial_ends_at = now() + interval '10 days',
      trial_used_at = now() - interval '1 day'
  WHERE company_id = v_company_a;
  -- premium still inactive
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, document_monthly_limit, is_trial_active
  INTO v_eff, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'inactive_premium_trialing_overview',
    v_eff = 'premium' AND v_limit IS NULL AND v_trial_active = TRUE,
    NULL,
    v_eff || '/' || COALESCE(v_limit::text, 'null')
  );

  -- Trial expired + free inactive → effective Free still resolved
  RESET ROLE;
  UPDATE public.plans SET is_active = true WHERE code = 'premium';
  UPDATE public.plans SET is_active = false WHERE code = 'free';
  UPDATE public.company_subscriptions
  SET trial_started_at = now() - interval '10 days',
      trial_ends_at = now() - interval '1 day'
  WHERE company_id = v_company_a;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT effective_plan_code, effective_plan_name, document_monthly_limit, is_trial_active
  INTO v_eff, v_code, v_limit, v_trial_active
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'inactive_free_effective_after_trial',
    v_eff = 'free' AND v_code = 'Free' AND v_limit = 30 AND v_trial_active = FALSE,
    NULL,
    COALESCE(v_eff, 'null') || '/' || COALESCE(v_code, 'null') || '/' || COALESCE(v_limit::text, 'null')
  );

  SELECT count(*) INTO v_count FROM public.plans WHERE code = 'free';
  PERFORM pg_temp.record_result(
    'direct_select_inactive_free_hidden',
    v_count = 0,
    NULL,
    v_count::text
  );

  -- Restore active seed plans for remaining tests
  RESET ROLE;
  UPDATE public.plans SET is_active = true WHERE code IN ('free', 'premium');

  -- Physical Plan not found: effective Free row missing
  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'trialing',
      entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '10 days',
      trial_ends_at = now() - interval '1 day',
      trial_used_at = now() - interval '10 days'
  WHERE company_id = v_company_a;
  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active',
      entitlement_origin = 'manual',
      trial_started_at = NULL, trial_ends_at = NULL
  WHERE plan_code = 'free';
  DELETE FROM public.plans WHERE code = 'free';

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM * FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('missing_effective_plan_not_found', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'missing_effective_plan_not_found',
      v_err = 'ATLAS_PLAN_NOT_FOUND',
      v_sqlstate,
      v_err
    );
  END;

  RESET ROLE;
  INSERT INTO public.plans (code, name, document_monthly_limit, is_active)
  VALUES ('free', 'Free', 30, true)
  ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name,
      document_monthly_limit = EXCLUDED.document_monthly_limit,
      is_active = true;

  -- create_company fails atomically when Free plan missing
  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active',
      entitlement_origin = 'manual',
      trial_started_at = NULL, trial_ends_at = NULL
  WHERE plan_code = 'free';
  DELETE FROM public.plans WHERE code = 'free';

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_company(
      'Should Fail No Free',
      'should-fail-nofree-' || substr(gen_random_uuid()::text, 1, 8)
    );
    PERFORM pg_temp.record_result('create_company_missing_free_fails', false, NULL, 'expected fail');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'create_company_missing_free_fails',
      true,
      v_sqlstate,
      left(v_err, 120)
    );
  END;
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.companies WHERE name = 'Should Fail No Free';
  PERFORM pg_temp.record_result('create_company_missing_free_no_company', v_count = 0, NULL, v_count::text);
  SELECT count(*) INTO v_count FROM public.company_members m
  JOIN public.companies c ON c.id = m.company_id
  WHERE c.name = 'Should Fail No Free';
  PERFORM pg_temp.record_result('create_company_missing_free_no_member', v_count = 0, NULL, v_count::text);
  SELECT count(*) INTO v_count FROM public.company_subscriptions s
  JOIN public.companies c ON c.id = s.company_id
  WHERE c.name = 'Should Fail No Free';
  PERFORM pg_temp.record_result('create_company_missing_free_no_sub', v_count = 0, NULL, v_count::text);

  INSERT INTO public.plans (code, name, document_monthly_limit, is_active)
  VALUES ('free', 'Free', 30, true), ('premium', 'Premium', NULL, true)
  ON CONFLICT (code) DO UPDATE
  SET is_active = true,
      name = EXCLUDED.name,
      document_monthly_limit = EXCLUDED.document_monthly_limit;

  -- auth.uid() NULL denied
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM * FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('null_uid_overview_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'null_uid_overview_denied',
      v_sqlstate IN ('28000', '42501')
        OR v_err ILIKE '%Not authenticated%'
        OR v_err ILIKE '%Not a company member%',
      v_sqlstate,
      v_err
    );
  END;

  -- EXECUTE grants: anon/public must not execute
  RESET ROLE;
  SELECT NOT has_function_privilege('anon', 'public.get_company_subscription_overview(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('public', 'public.get_company_subscription_overview(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.get_company_subscription_overview(uuid)', 'EXECUTE')
  INTO v_trial_active;
  PERFORM pg_temp.record_result(
    'overview_execute_grants',
    v_trial_active,
    NULL,
    v_trial_active::text
  );

  SELECT p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres'
  INTO v_trial_active
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'get_company_subscription_overview';
  PERFORM pg_temp.record_result(
    'overview_security_definer_owner_postgres',
    v_trial_active,
    NULL,
    v_trial_active::text
  );

  -- Delete company cascades subscription (verify FK action; avoid last-owner trigger)
  SELECT COUNT(*) INTO v_count
  FROM pg_constraint
  WHERE conname = 'company_subscriptions_company_id_fkey'
    AND confdeltype = 'c'; -- CASCADE
  PERFORM pg_temp.record_result(
    'company_delete_cascades_subscription',
    v_count = 1,
    NULL,
    v_count::text
  );

  DELETE FROM public.company_subscriptions WHERE company_id = v_new_company;
  DELETE FROM public.company_members WHERE company_id = v_new_company AND user_id <> v_owner;
  -- leave company for ROLLBACK cleanup; membership remains until rollback
  SELECT count(*) INTO v_count FROM public.company_subscriptions WHERE company_id = v_new_company;
  PERFORM pg_temp.record_result(
    'subscription_row_removed_for_cleanup',
    v_count = 0,
    NULL,
    v_count::text
  );

  -- Anon cannot read plans
  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO v_count FROM public.plans;
    PERFORM pg_temp.record_result('anon_plans_denied_or_empty', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('anon_plans_denied_or_empty', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('anon_plans_denied_or_empty', false, v_sqlstate, v_err);
  END;

  RESET ROLE;
END $$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed,
  count(*) FILTER (WHERE NOT passed) AS failed,
  count(*) AS total
FROM test_results;

DO $$
DECLARE
  v_failed BIGINT;
BEGIN
  SELECT count(*) INTO v_failed FROM test_results WHERE NOT passed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION 'Step 14A behavior tests failed: %', v_failed;
  END IF;
END $$;

ROLLBACK;
