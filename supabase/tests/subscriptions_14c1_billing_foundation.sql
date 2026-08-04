-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-1 billing foundation behavior
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
  TO authenticated, anon;

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

CREATE OR REPLACE FUNCTION pg_temp.insert_doc(
  p_company_id UUID,
  p_title TEXT DEFAULT 'Doc'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp, pg_catalog
AS $$
DECLARE
  v_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.documents (
    id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
  ) VALUES (
    v_id,
    p_company_id,
    p_title,
    p_title || '.pdf',
    p_company_id::text || '/' || v_id::text || '/' || gen_random_uuid()::text || '.pdf',
    'application/pdf',
    1024
  );
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.insert_doc(UUID, TEXT) TO authenticated;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_member UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();

  v_free UUID;
  v_manual UUID := gen_random_uuid();
  v_trial UUID;
  v_prov UUID := gen_random_uuid();
  v_uniq_a UUID := gen_random_uuid();
  v_uniq_b UUID := gen_random_uuid();
  v_quota_free UUID := gen_random_uuid();
  v_quota_manual UUID := gen_random_uuid();
  v_quota_prov UUID := gen_random_uuid();
  v_evt_co UUID := gen_random_uuid();
  v_trial_linked UUID := gen_random_uuid();
  v_trial_sync UUID := gen_random_uuid();
  v_trial_prov UUID := gen_random_uuid();

  v_company public.companies%ROWTYPE;
  v_origin TEXT;
  v_eff TEXT;
  v_status TEXT;
  v_sync TEXT;
  v_trial_active BOOLEAN;
  v_prov_grace BOOLEAN;
  v_can_trial BOOLEAN;
  v_portal BOOLEAN;
  v_linked BOOLEAN;
  v_doc UUID;
  v_used BIGINT;
  v_period_start TIMESTAMPTZ;
  v_event_id UUID;
  v_evt_company UUID;
  v_sqlstate TEXT;
  v_err TEXT;
  v_cnt INT;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14c1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_member, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'member14c1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14c1@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  v_period_start :=
    date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  -- =========================================================================
  -- SCHEMA / BACKFILL via create_company + fixtures
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT * INTO v_company
    FROM public.create_company(
      'Company 14C1 Free',
      'company-14c1-free-' || substr(gen_random_uuid()::text, 1, 8)
    );
    v_free := v_company.id;
    PERFORM pg_temp.record_result('create_company_returns_row', v_free IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('create_company_returns_row', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT * INTO v_company
    FROM public.create_company(
      'Company 14C1 Trial',
      'company-14c1-trial-' || substr(gen_random_uuid()::text, 1, 8)
    );
    v_trial := v_company.id;
    PERFORM pg_temp.record_result('create_company_trial_base', v_trial IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('create_company_trial_base', false, v_sqlstate, v_err);
  END;

  RESET ROLE;

  SELECT b.subscription_status, b.sync_status, b.provider_access_status
  INTO v_status, v_sync, v_eff
  FROM private.company_billing b
  WHERE b.company_id = v_free;
  SELECT cs.entitlement_origin INTO v_origin
  FROM public.company_subscriptions cs WHERE cs.company_id = v_free;
  PERFORM pg_temp.record_result(
    'create_company_billing_none_idle',
    v_status = 'none' AND v_sync = 'idle' AND v_eff = 'none',
    NULL,
    format('sub=%s sync=%s access=%s', v_status, v_sync, v_eff)
  );
  PERFORM pg_temp.record_result(
    'free_company_origin_none',
    v_origin = 'none',
    NULL,
    v_origin
  );

  -- Manual premium fixture (postgres)
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_manual, 'Company 14C1 Manual', 'company-14c1-manual-' || substr(v_manual::text, 1, 8));
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_manual, v_owner, 'owner'),
    (v_manual, v_member, 'employee');
  INSERT INTO public.company_subscriptions (
    company_id, plan_code, status, entitlement_origin
  ) VALUES (v_manual, 'premium', 'active', 'manual');
  INSERT INTO private.company_billing (company_id) VALUES (v_manual);

  SELECT entitlement_origin INTO v_origin
  FROM public.company_subscriptions WHERE company_id = v_manual;
  PERFORM pg_temp.record_result(
    'manual_premium_fixture_origin',
    v_origin = 'manual',
    NULL,
    v_origin
  );
  PERFORM pg_temp.record_result(
    'manual_premium_has_billing_row',
    EXISTS (SELECT 1 FROM private.company_billing WHERE company_id = v_manual)
  );

  -- Activate trial → origin internal_trial
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial);
    PERFORM pg_temp.record_result('activate_trial_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('activate_trial_ok', false, v_sqlstate, v_err);
  END;
  RESET ROLE;

  SELECT entitlement_origin, status INTO v_origin, v_status
  FROM public.company_subscriptions WHERE company_id = v_trial;
  PERFORM pg_temp.record_result(
    'trial_origin_internal_trial',
    v_origin = 'internal_trial' AND v_status = 'trialing',
    NULL,
    format('origin=%s status=%s', v_origin, v_status)
  );

  -- =========================================================================
  -- UNIQUENESS (provider_code + external ids)
  -- =========================================================================
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_uniq_a, 'Uniq A', 'company-14c1-uniq-a-' || substr(v_uniq_a::text, 1, 8)),
    (v_uniq_b, 'Uniq B', 'company-14c1-uniq-b-' || substr(v_uniq_b::text, 1, 8));
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_uniq_a, v_owner, 'owner'),
    (v_uniq_b, v_owner, 'owner');
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES
    (v_uniq_a, 'free', 'free', 'none'),
    (v_uniq_b, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id, provider_code, provider_environment, external_subscription_id, external_customer_id)
  VALUES (v_uniq_a, 'stripe', 'test', 'sub_shared', 'cus_shared');
  INSERT INTO private.company_billing (company_id) VALUES (v_uniq_b);

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'stripe', provider_environment = 'test', external_subscription_id = 'sub_shared'
    WHERE company_id = v_uniq_b;
    PERFORM pg_temp.record_result('uniq_subscription_id_blocks', false, NULL, 'expected unique');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('uniq_subscription_id_blocks', true, '23505', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uniq_subscription_id_blocks', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'stripe', provider_environment = 'test', external_customer_id = 'cus_shared'
    WHERE company_id = v_uniq_b;
    PERFORM pg_temp.record_result('uniq_customer_id_blocks', false, NULL, 'expected unique');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('uniq_customer_id_blocks', true, '23505', 'ok');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uniq_customer_id_blocks', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE private.company_billing
    SET provider_code = 'paddle',
        provider_environment = 'test',
        external_subscription_id = 'sub_shared',
        external_customer_id = 'cus_shared'
    WHERE company_id = v_uniq_b;
    PERFORM pg_temp.record_result('uniq_different_provider_ok', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uniq_different_provider_ok', false, v_sqlstate, v_err);
  END;

  UPDATE private.company_billing
  SET provider_code = NULL,
      provider_environment = NULL,
      external_subscription_id = NULL,
      external_customer_id = NULL
  WHERE company_id IN (v_uniq_a, v_uniq_b);

  BEGIN
    UPDATE private.company_billing
    SET provider_code = NULL,
        provider_environment = NULL,
        external_subscription_id = NULL,
        external_customer_id = NULL
    WHERE company_id IN (v_uniq_a, v_uniq_b);
    PERFORM pg_temp.record_result(
      'uniq_null_ids_ok',
      (SELECT count(*) FROM private.company_billing
       WHERE company_id IN (v_uniq_a, v_uniq_b)
         AND external_subscription_id IS NULL
         AND external_customer_id IS NULL) = 2
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uniq_null_ids_ok', false, v_sqlstate, v_err);
  END;

  -- =========================================================================
  -- RESOLVER (postgres / SECURITY INVOKER with table access)
  -- =========================================================================
  -- free
  SELECT r.effective_plan_code, r.is_trial_active, r.is_provider_grace
  INTO v_eff, v_trial_active, v_prov_grace
  FROM private.resolve_company_entitlement(v_free, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_free',
    v_eff = 'free' AND v_trial_active = FALSE AND v_prov_grace = FALSE,
    NULL,
    v_eff
  );

  -- manual premium
  SELECT r.effective_plan_code, r.is_manual_premium
  INTO v_eff, v_trial_active
  FROM private.resolve_company_entitlement(v_manual, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_manual_premium',
    v_eff = 'premium' AND v_trial_active = TRUE,
    NULL,
    format('eff=%s manual=%s', v_eff, v_trial_active)
  );

  -- trial active
  SELECT r.effective_plan_code, r.is_trial_active
  INTO v_eff, v_trial_active
  FROM private.resolve_company_entitlement(v_trial, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_trial_active',
    v_eff = 'premium' AND v_trial_active = TRUE,
    NULL,
    format('eff=%s trial=%s', v_eff, v_trial_active)
  );

  -- trial expired
  UPDATE public.company_subscriptions
  SET trial_started_at = now() - interval '60 days',
      trial_ends_at = now() - interval '1 day',
      trial_used_at = now() - interval '60 days'
  WHERE company_id = v_trial;
  SELECT r.effective_plan_code, r.is_trial_active
  INTO v_eff, v_trial_active
  FROM private.resolve_company_entitlement(v_trial, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_trial_expired_free',
    v_eff = 'free' AND v_trial_active = FALSE,
    NULL,
    format('eff=%s trial=%s', v_eff, v_trial_active)
  );

  -- Provider fixture company
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_prov, 'Company 14C1 Prov', 'company-14c1-prov-' || substr(v_prov::text, 1, 8));
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_prov, v_owner, 'owner'),
    (v_prov, v_member, 'employee');
  INSERT INTO public.company_subscriptions (
    company_id, plan_code, status, entitlement_origin
  ) VALUES (v_prov, 'premium', 'active', 'provider');
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id, external_subscription_id,
    subscription_status, provider_access_status, provider_access_ends_at
  ) VALUES (
    v_prov, 'stripe', 'test', 'cus_prov', 'sub_prov',
    'active', 'entitled', now() + interval '30 days'
  );

  SELECT r.effective_plan_code, r.is_provider_premium
  INTO v_eff, v_trial_active
  FROM private.resolve_company_entitlement(v_prov, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_provider_entitled_future',
    v_eff = 'premium' AND v_trial_active = TRUE,
    NULL,
    format('eff=%s prem=%s', v_eff, v_trial_active)
  );

  -- entitled + NULL ends → CHECK fail (cannot insert/update)
  BEGIN
    UPDATE private.company_billing
    SET provider_access_status = 'entitled',
        provider_access_ends_at = NULL
    WHERE company_id = v_prov;
    PERFORM pg_temp.record_result(
      'provider_entitled_null_ends_check',
      false, NULL, 'expected check'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result(
      'provider_entitled_null_ends_check', true, '23514', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'provider_entitled_null_ends_check', false, v_sqlstate, v_err
    );
  END;

  UPDATE private.company_billing
  SET provider_access_status = 'entitled',
      provider_access_ends_at = now() - interval '1 day'
  WHERE company_id = v_prov;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_prov, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_provider_entitled_past_free',
    v_eff = 'free',
    NULL,
    v_eff
  );

  UPDATE private.company_billing
  SET provider_access_status = 'grace',
      grace_ends_at = now() + interval '7 days',
      provider_access_ends_at = now() - interval '1 day'
  WHERE company_id = v_prov;
  SELECT r.effective_plan_code, r.is_provider_grace
  INTO v_eff, v_prov_grace
  FROM private.resolve_company_entitlement(v_prov, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_provider_grace_future',
    v_eff = 'premium' AND v_prov_grace = TRUE,
    NULL,
    format('eff=%s grace=%s', v_eff, v_prov_grace)
  );

  UPDATE private.company_billing
  SET provider_access_status = 'grace',
      grace_ends_at = now() - interval '1 day'
  WHERE company_id = v_prov;
  SELECT r.effective_plan_code, r.is_provider_grace
  INTO v_eff, v_prov_grace
  FROM private.resolve_company_entitlement(v_prov, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_provider_grace_past_free',
    v_eff = 'free' AND v_prov_grace = FALSE,
    NULL,
    format('eff=%s grace=%s', v_eff, v_prov_grace)
  );

  FOREACH v_status IN ARRAY ARRAY['blocked', 'ended', 'unknown']
  LOOP
    UPDATE private.company_billing
    SET provider_access_status = v_status,
        provider_access_ends_at = NULL,
        grace_ends_at = NULL
    WHERE company_id = v_prov;
    SELECT r.effective_plan_code INTO v_eff
    FROM private.resolve_company_entitlement(v_prov, now()) r;
    PERFORM pg_temp.record_result(
      'resolve_provider_' || v_status || '_free',
      v_eff = 'free',
      NULL,
      v_eff
    );
  END LOOP;

  -- origin provider + atlas active premium + access ended → free
  UPDATE private.company_billing
  SET provider_access_status = 'ended',
      provider_access_ends_at = NULL,
      grace_ends_at = NULL
  WHERE company_id = v_prov;
  SELECT r.effective_plan_code, r.atlas_plan_code, r.atlas_status, r.entitlement_origin
  INTO v_eff, v_origin, v_status, v_sync
  FROM private.resolve_company_entitlement(v_prov, now()) r;
  PERFORM pg_temp.record_result(
    'resolve_provider_atlas_active_access_ended_free',
    v_eff = 'free'
      AND v_origin = 'premium'
      AND v_status = 'active'
      AND v_sync = 'provider',
    NULL,
    format('eff=%s atlas=%s/%s origin=%s', v_eff, v_origin, v_status, v_sync)
  );

  -- delete billing temporarily → still free, no crash; re-insert
  DELETE FROM private.company_billing WHERE company_id = v_prov;
  BEGIN
    SELECT r.effective_plan_code, r.billing_linked
    INTO v_eff, v_linked
    FROM private.resolve_company_entitlement(v_prov, now()) r;
    PERFORM pg_temp.record_result(
      'resolve_without_billing_row',
      v_eff = 'free' AND v_linked = FALSE,
      NULL,
      format('eff=%s linked=%s', v_eff, v_linked)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('resolve_without_billing_row', false, v_sqlstate, v_err);
  END;
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id, external_subscription_id,
    subscription_status, provider_access_status
  ) VALUES (
    v_prov, 'stripe', 'test', 'cus_prov', 'sub_prov', 'ended', 'ended'
  );
  PERFORM pg_temp.record_result(
    'billing_row_reinserted',
    EXISTS (SELECT 1 FROM private.company_billing WHERE company_id = v_prov)
  );

  -- =========================================================================
  -- TRIAL gates vs billing
  -- =========================================================================
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_trial_linked, 'Trial Linked', 'company-14c1-tlink-' || substr(v_trial_linked::text, 1, 8)),
    (v_trial_sync, 'Trial Sync', 'company-14c1-tsync-' || substr(v_trial_sync::text, 1, 8)),
    (v_trial_prov, 'Trial Prov', 'company-14c1-tprov-' || substr(v_trial_prov::text, 1, 8));
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_trial_linked, v_owner, 'owner'),
    (v_trial_sync, v_owner, 'owner'),
    (v_trial_prov, v_owner, 'owner');
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES
    (v_trial_linked, 'free', 'free', 'none'),
    (v_trial_sync, 'free', 'free', 'none'),
    (v_trial_prov, 'free', 'free', 'provider');
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id, sync_status
  ) VALUES
    (v_trial_linked, 'stripe', 'test', 'cus_linked', 'idle'),
    (v_trial_sync, NULL, NULL, NULL, 'pending');
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id, external_subscription_id,
    provider_access_status
  ) VALUES (
    v_trial_prov, 'stripe', 'test', 'cus_tprov', 'sub_tprov', 'blocked'
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  SELECT can_activate_trial INTO v_can_trial
  FROM public.get_company_subscription_overview(v_trial_linked);
  PERFORM pg_temp.record_result(
    'can_activate_trial_false_when_linked',
    v_can_trial = FALSE,
    NULL,
    v_can_trial::text
  );

  SELECT can_activate_trial INTO v_can_trial
  FROM public.get_company_subscription_overview(v_trial_sync);
  PERFORM pg_temp.record_result(
    'can_activate_trial_false_when_sync_pending',
    v_can_trial = FALSE,
    NULL,
    v_can_trial::text
  );

  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial_sync);
    PERFORM pg_temp.record_result('activate_sync_pending_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_sync_pending_denied',
      v_err = 'ATLAS_BILLING_SYNC_PENDING',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial_linked);
    PERFORM pg_temp.record_result('activate_billing_linked_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_billing_linked_denied',
      v_err = 'ATLAS_BILLING_LINKED',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial_prov);
    PERFORM pg_temp.record_result(
      'activate_provider_origin_blocked_denied', false, NULL, 'expected'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_provider_origin_blocked_denied',
      v_err = 'ATLAS_BILLING_LINKED',
      v_sqlstate,
      v_err
    );
  END;

  RESET ROLE;

  -- Exact precedence: active Atlas trial
  -- (v_trial was expired earlier for resolve_trial_expired_free; restore active)
  UPDATE public.company_subscriptions
  SET status = 'trialing',
      plan_code = 'premium',
      entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '1 day',
      trial_ends_at = now() + interval '10 days',
      trial_used_at = now() - interval '1 day'
  WHERE company_id = v_trial;
  UPDATE private.company_billing
  SET provider_code = NULL,
      provider_environment = NULL,
      external_customer_id = NULL,
      external_subscription_id = NULL,
      sync_status = 'idle',
      provider_access_status = 'none',
      provider_access_ends_at = NULL
  WHERE company_id = v_trial;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.activate_company_premium_trial(v_trial);
    PERFORM pg_temp.record_result(
      'activate_trial_already_active_exact', false, NULL, 'expected'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_trial_already_active_exact',
      v_err = 'ATLAS_TRIAL_ALREADY_ACTIVE',
      v_sqlstate,
      v_err
    );
  END;

  -- Exact precedence: manual Premium
  BEGIN
    PERFORM public.activate_company_premium_trial(v_manual);
    PERFORM pg_temp.record_result(
      'activate_manual_premium_exact', false, NULL, 'expected'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_manual_premium_exact',
      v_err = 'ATLAS_ALREADY_PREMIUM',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Exact precedence: trial used but expired (not active)
  UPDATE public.company_subscriptions
  SET status = 'trialing',
      plan_code = 'premium',
      entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '40 days',
      trial_ends_at = now() - interval '10 days',
      trial_used_at = now() - interval '40 days'
  WHERE company_id = v_free;
  -- ensure billing clean for free company
  UPDATE private.company_billing
  SET provider_code = NULL,
      provider_environment = NULL,
      external_customer_id = NULL,
      external_subscription_id = NULL,
      sync_status = 'idle'
  WHERE company_id = v_free;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.activate_company_premium_trial(v_free);
    PERFORM pg_temp.record_result(
      'activate_trial_already_used_exact', false, NULL, 'expected'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'activate_trial_already_used_exact',
      v_err = 'ATLAS_TRIAL_ALREADY_USED',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- restore free company (trial historically used marker allowed on free)
  UPDATE public.company_subscriptions
  SET status = 'free',
      plan_code = 'free',
      entitlement_origin = 'none',
      trial_started_at = NULL,
      trial_ends_at = NULL,
      trial_used_at = now()
  WHERE company_id = v_free;


  SELECT entitlement_origin INTO v_origin
  FROM public.company_subscriptions WHERE company_id = v_trial_prov;
  PERFORM pg_temp.record_result(
    'cannot_overwrite_provider_origin',
    v_origin = 'provider',
    NULL,
    v_origin
  );

  -- =========================================================================
  -- QUOTA
  -- =========================================================================
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_quota_free, 'Quota Free', 'company-14c1-qfree-' || substr(v_quota_free::text, 1, 8)),
    (v_quota_manual, 'Quota Manual', 'company-14c1-qman-' || substr(v_quota_manual::text, 1, 8)),
    (v_quota_prov, 'Quota Prov', 'company-14c1-qprov-' || substr(v_quota_prov::text, 1, 8));
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_quota_free, v_owner, 'owner'),
    (v_quota_manual, v_owner, 'owner'),
    (v_quota_prov, v_owner, 'owner');
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES
    (v_quota_free, 'free', 'free', 'none'),
    (v_quota_manual, 'premium', 'active', 'manual'),
    (v_quota_prov, 'premium', 'active', 'provider');
  INSERT INTO private.company_billing (company_id) VALUES (v_quota_free), (v_quota_manual);
  INSERT INTO private.company_billing (
    company_id, provider_code, provider_environment, external_customer_id, external_subscription_id,
    subscription_status, provider_access_status, provider_access_ends_at
  ) VALUES (
    v_quota_prov, 'stripe', 'test', 'cus_q', 'sub_q',
    'active', 'entitled', now() + interval '30 days'
  );

  INSERT INTO private.company_document_monthly_usage (company_id, period_start, documents_used)
  VALUES
    (v_quota_free, v_period_start, 29),
    (v_quota_manual, v_period_start, 30),
    (v_quota_prov, v_period_start, 30);

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  BEGIN
    v_doc := pg_temp.insert_doc(v_quota_free, 'Doc30');
    PERFORM pg_temp.record_result('quota_free_30_ok', true, NULL, v_doc::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('quota_free_30_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_doc := pg_temp.insert_doc(v_quota_free, 'Doc31');
    PERFORM pg_temp.record_result('quota_free_31_blocked', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'quota_free_31_blocked',
      v_sqlstate = 'P0001' AND v_err = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    v_doc := pg_temp.insert_doc(v_quota_manual, 'Doc31Manual');
    PERFORM pg_temp.record_result('quota_manual_unlimited_31_ok', true, NULL, v_doc::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('quota_manual_unlimited_31_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_doc := pg_temp.insert_doc(v_quota_prov, 'Doc31Prov');
    PERFORM pg_temp.record_result('quota_provider_entitled_unlimited', true, NULL, v_doc::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'quota_provider_entitled_unlimited', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  UPDATE private.company_billing
  SET provider_access_status = 'ended',
      provider_access_ends_at = NULL,
      grace_ends_at = NULL,
      subscription_status = 'ended'
  WHERE company_id = v_quota_prov;
  -- usage already 31 from unlimited insert; free limit 30 → next insert denied
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  BEGIN
    v_doc := pg_temp.insert_doc(v_quota_prov, 'DocAfterEnded');
    PERFORM pg_temp.record_result(
      'quota_provider_ended_applies_free', false, NULL, 'expected'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'quota_provider_ended_applies_free',
      v_sqlstate = 'P0001' AND v_err = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- =========================================================================
  -- EVENTS
  -- =========================================================================
  INSERT INTO public.companies (id, name, slug) VALUES
    (v_evt_co, 'Events Co', 'company-14c1-evt-' || substr(v_evt_co::text, 1, 8));
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_evt_co, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id) VALUES (v_evt_co);

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash,
      payload_json, retention_expires_at
    ) VALUES (
      'stripe', 'test', 'evt_14c1_ok', 'customer.updated', v_evt_co,
      'verified', now(), 'hash_ok', '{"a":1}'::jsonb, now() + interval '30 days'
    )
    RETURNING id INTO v_event_id;
    PERFORM pg_temp.record_result(
      'event_verified_with_signature',
      v_event_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM private.billing_provider_events e
          WHERE e.id = v_event_id AND e.signature_verified_at IS NOT NULL
        )
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('event_verified_with_signature', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash,
      payload_json, retention_expires_at
    ) VALUES (
      'stripe', 'test', 'evt_14c1_nosig', 'invoice.paid', v_evt_co,
      'verified', NULL, 'hash_nosig', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result(
      'event_verified_without_signature_fails', false, NULL, 'expected'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result(
      'event_verified_without_signature_fails', true, '23514', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'event_verified_without_signature_fails', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      processing_status, verification_status, signature_verified_at,
      payload_hash, payload_json, retention_expires_at
    ) VALUES (
      'stripe', 'test', 'evt_14c1_proc', 'invoice.paid', v_evt_co,
      'processed', 'unverified', NULL,
      'hash_proc', '{}'::jsonb, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result(
      'event_processed_unverified_fails', false, NULL, 'expected'
    );
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result(
      'event_processed_unverified_fails', true, '23514', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'event_processed_unverified_fails', false, v_sqlstate, v_err
    );
  END;

  UPDATE private.billing_provider_events
  SET payload_json = NULL
  WHERE external_event_id = 'evt_14c1_ok';

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code, provider_environment, external_event_id, event_type, company_id,
      verification_status, signature_verified_at, payload_hash,
      payload_json, retention_expires_at
    ) VALUES (
      'stripe', 'test', 'evt_14c1_ok', 'customer.updated', v_evt_co,
      'verified', now(), 'hash_dup', NULL, now() + interval '30 days'
    );
    PERFORM pg_temp.record_result(
      'event_unique_after_payload_null', false, NULL, 'expected unique'
    );
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result(
      'event_unique_after_payload_null', true, '23505', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'event_unique_after_payload_null', false, v_sqlstate, v_err
    );
  END;

  DELETE FROM public.companies WHERE id = v_evt_co;
  SELECT e.company_id INTO v_evt_company
  FROM private.billing_provider_events e
  WHERE e.external_event_id = 'evt_14c1_ok';
  PERFORM pg_temp.record_result(
    'event_company_id_set_null_on_delete',
    v_evt_company IS NULL,
    NULL,
    coalesce(v_evt_company::text, 'null')
  );

  -- =========================================================================
  -- OVERVIEW
  -- =========================================================================
  -- grace → client subscription_status active
  UPDATE private.company_billing
  SET provider_access_status = 'grace',
      grace_ends_at = now() + interval '5 days',
      provider_access_ends_at = now() - interval '1 day',
      subscription_status = 'active'
  WHERE company_id = v_prov;

  PERFORM pg_temp.set_auth(v_member);
  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT
      can_open_billing_portal,
      entitlement_origin,
      subscription_status,
      effective_plan_code,
      is_provider_grace
    INTO v_portal, v_origin, v_status, v_eff, v_prov_grace
    FROM public.get_company_subscription_overview(v_prov);
    PERFORM pg_temp.record_result(
      'overview_member_portal_false_origin_present',
      v_portal = FALSE AND v_origin = 'provider',
      NULL,
      format('portal=%s origin=%s', v_portal, v_origin)
    );
    PERFORM pg_temp.record_result(
      'overview_grace_subscription_status_active',
      v_status = 'active' AND v_eff = 'premium' AND v_prov_grace = TRUE,
      NULL,
      format('status=%s eff=%s grace=%s', v_status, v_eff, v_prov_grace)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'overview_member_portal_false_origin_present', false, v_sqlstate, v_err
    );
    PERFORM pg_temp.record_result(
      'overview_grace_subscription_status_active', false, v_sqlstate, v_err
    );
  END;
  RESET ROLE;

  UPDATE private.company_billing
  SET provider_access_status = 'blocked',
      grace_ends_at = NULL,
      provider_access_ends_at = NULL
  WHERE company_id = v_prov;

  PERFORM pg_temp.set_auth(v_member);
  SET LOCAL ROLE authenticated;
  SELECT subscription_status, effective_plan_code
  INTO v_status, v_eff
  FROM public.get_company_subscription_overview(v_prov);
  PERFORM pg_temp.record_result(
    'overview_blocked_free',
    v_status = 'free' AND v_eff = 'free',
    NULL,
    format('status=%s eff=%s', v_status, v_eff)
  );

  PERFORM pg_temp.set_auth(v_outsider);
  BEGIN
    PERFORM public.get_company_subscription_overview(v_prov);
    PERFORM pg_temp.record_result('overview_outsider_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'overview_outsider_denied',
      v_sqlstate = '42501' OR v_err = 'Not a company member',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- =========================================================================
  -- SECURITY
  -- =========================================================================
  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  BEGIN
    PERFORM 1 FROM private.company_billing LIMIT 1;
    PERFORM pg_temp.record_result(
      'authenticated_cannot_select_company_billing', false, NULL, 'expected deny'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result(
      'authenticated_cannot_select_company_billing', true, '42501', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_cannot_select_company_billing',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    PERFORM private.resolve_company_entitlement(v_free, now());
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_resolve', false, NULL, 'expected deny'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_resolve', true, '42501', 'ok'
    );
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute_resolve',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  RESET ROLE;
END;
$$;

SELECT test_name, passed FROM test_results ORDER BY 1;
SELECT count(*) FILTER (WHERE NOT passed) AS failed FROM test_results;

ROLLBACK;
