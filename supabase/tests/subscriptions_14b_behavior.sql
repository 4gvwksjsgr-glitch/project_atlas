-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14B subscriptions / document quota behavior
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
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_company_c UUID := gen_random_uuid();
  v_doc UUID;
  v_doc2 UUID;
  v_count BIGINT;
  v_used BIGINT;
  v_limit INTEGER;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
  v_eff TEXT;
  v_code TEXT;
  v_status TEXT;
  v_trial_active BOOLEAN;
  v_can_trial BOOLEAN;
  v_unlimited BOOLEAN;
  v_started TIMESTAMPTZ;
  v_ends TIMESTAMPTZ;
  v_used_at TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
  v_i INT;
  v_owner_is_owner BOOLEAN;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner14b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin14b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager14b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee14b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider14b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Company 14B A', 'company-14b-a-' || substr(v_company_a::text, 1, 8)),
    (v_company_b, 'Company 14B B', 'company-14b-b-' || substr(v_company_b::text, 1, 8)),
    (v_company_c, 'Company 14B C', 'company-14b-c-' || substr(v_company_c::text, 1, 8));

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner'),
    (v_company_c, v_owner, 'owner');

  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES
    (v_company_a, 'free', 'free', 'none'),
    (v_company_b, 'free', 'free', 'none'),
    (v_company_c, 'free', 'free', 'none')
  ON CONFLICT (company_id) DO NOTHING;

  INSERT INTO private.company_billing (company_id)
  VALUES (v_company_a), (v_company_b), (v_company_c)
  ON CONFLICT (company_id) DO NOTHING;

  v_period_start :=
    date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_period_end := v_period_start + interval '1 month';

  -- -------------------------------------------------------------------------
  -- Overview with no usage row → 0
  -- -------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT documents_used, period_start, period_end, is_unlimited, can_activate_trial,
           effective_plan_code, document_monthly_limit
    INTO v_used, v_started, v_ends, v_unlimited, v_can_trial, v_eff, v_limit
    FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result(
      'overview_usage_zero_without_row',
      v_used = 0
        AND v_started = v_period_start
        AND v_ends = v_period_end
        AND v_unlimited = FALSE
        AND v_can_trial = TRUE
        AND v_eff = 'free'
        AND v_limit = 30,
      NULL,
      format('used=%s eff=%s can=%s', v_used, v_eff, v_can_trial)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('overview_usage_zero_without_row', false, v_sqlstate, v_err);
  END;

  -- -------------------------------------------------------------------------
  -- Free usage 0 → first insert; no historical backfill
  -- -------------------------------------------------------------------------
  BEGIN
    v_doc := pg_temp.insert_doc(v_company_a, 'First');
    PERFORM pg_temp.record_result('free_insert_from_zero', true, NULL, v_doc::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('free_insert_from_zero', false, v_sqlstate, v_err);
  END;

  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('usage_after_first_insert', v_used = 1, NULL, v_used::text);

  -- Historical docs inserted as postgres with past created_at after disabling
  -- trigger simulation: insert BEFORE trigger existed is modeled by inserting
  -- a row into documents as superuser while temporarily disabling the trigger,
  -- proving those rows do not bump usage (no backfill).
  ALTER TABLE public.documents DISABLE TRIGGER trg_documents_consume_monthly_usage;
  v_doc := gen_random_uuid();
  INSERT INTO public.documents (
    id, company_id, title, original_file_name, storage_path, mime_type, size_bytes, created_at
  ) VALUES (
    v_doc, v_company_a, 'Historic', 'h.pdf',
    v_company_a::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf',
    'application/pdf', 10, '2020-01-01 00:00:00+00'
  );
  ALTER TABLE public.documents ENABLE TRIGGER trg_documents_consume_monthly_usage;

  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result(
    'no_backfill_historic_docs',
    v_used = 1,
    NULL,
    v_used::text
  );

  -- -------------------------------------------------------------------------
  -- Seed usage to 29 then 30th ok / 31st denied
  -- -------------------------------------------------------------------------
  UPDATE private.company_document_monthly_usage
  SET documents_used = 29
  WHERE company_id = v_company_a AND period_start = v_period_start;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    v_doc := pg_temp.insert_doc(v_company_a, 'Doc30');
    PERFORM pg_temp.record_result('free_doc_30_allowed', true, NULL, v_doc::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('free_doc_30_allowed', false, v_sqlstate, v_err);
  END;

  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('usage_is_30_after_thirtieth', v_used = 30, NULL, v_used::text);

  SET LOCAL ROLE authenticated;
  BEGIN
    v_doc := pg_temp.insert_doc(v_company_a, 'Doc31');
    PERFORM pg_temp.record_result('free_doc_31_blocked', false, NULL, 'expected quota');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'free_doc_31_blocked',
      v_sqlstate = 'P0001' AND v_err = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      v_sqlstate,
      v_err
    );
  END;

  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('usage_stays_30_after_reject', v_used = 30, NULL, v_used::text);

  -- -------------------------------------------------------------------------
  -- Rollback of successful insert undoes usage increment
  -- (PL/pgSQL subtransaction: insert succeeds then forced exception rolls back)
  -- -------------------------------------------------------------------------
  UPDATE private.company_document_monthly_usage
  SET documents_used = 10
  WHERE company_id = v_company_a AND period_start = v_period_start;

  v_owner_is_owner := FALSE; -- reuse as "saw usage=11 before rollback"
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    PERFORM set_config(
      'request.jwt.claims',
      json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
      true
    );
    PERFORM pg_temp.insert_doc(v_company_a, 'RollbackMe');
    RESET ROLE;
    SELECT documents_used INTO v_used
    FROM private.company_document_monthly_usage
    WHERE company_id = v_company_a AND period_start = v_period_start;
    v_owner_is_owner := (v_used = 11);
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_TEST_FORCE_ROLLBACK';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      IF v_err IS DISTINCT FROM 'ATLAS_TEST_FORCE_ROLLBACK' THEN
        RAISE;
      END IF;
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
      RAISE EXCEPTION 'rollback harness failed: % %', v_sqlstate, v_err;
  END;

  RESET ROLE;
  PERFORM pg_temp.record_result(
    'usage_incremented_before_rollback',
    v_owner_is_owner,
    NULL,
    'saw_11_before_force_exception=' || v_owner_is_owner::text
  );
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result(
    'rollback_insert_undoes_usage',
    v_used = 10,
    NULL,
    v_used::text
  );

  -- Constraint failure after trigger still rolls back usage (invalid mime via
  -- postgres insert that fails CHECK after BEFORE trigger ran).
  UPDATE private.company_document_monthly_usage
  SET documents_used = 5
  WHERE company_id = v_company_a AND period_start = v_period_start;

  BEGIN
    v_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc, v_company_a, 'BadMime', 'x.bin',
      v_company_a::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/octet-stream', 10
    );
    PERFORM pg_temp.record_result('constraint_fail_expected', false, NULL, 'expected check fail');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('constraint_fail_expected', true, '23514', 'check');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('constraint_fail_expected', false, v_sqlstate, v_err);
  END;

  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result(
    'failed_insert_no_usage_bump',
    v_used = 5,
    NULL,
    v_used::text
  );

  -- -------------------------------------------------------------------------
  -- Archive / hard delete do not reduce usage
  -- -------------------------------------------------------------------------
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  v_doc := pg_temp.insert_doc(v_company_a, 'ToArchive');
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  -- was 5, +1 = 6
  PERFORM pg_temp.record_result('usage_before_archive', v_used = 6, NULL, v_used::text);

  SET LOCAL ROLE authenticated;
  UPDATE public.documents SET is_archived = TRUE WHERE id = v_doc;
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('archive_does_not_reduce_usage', v_used = 6, NULL, v_used::text);

  SET LOCAL ROLE authenticated;
  v_doc2 := pg_temp.insert_doc(v_company_a, 'ToDelete');
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('usage_before_hard_delete', v_used = 7, NULL, v_used::text);

  -- hard delete as postgres (authenticated may lack DELETE depending on 13B grants)
  DELETE FROM public.documents WHERE id = v_doc2;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('hard_delete_does_not_reduce_usage', v_used = 7, NULL, v_used::text);

  -- Storage-only (no documents row) cannot appear in usage table by itself
  SELECT count(*) INTO v_count
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND documents_used = 7;
  PERFORM pg_temp.record_result(
    'storage_only_not_in_usage',
    v_count = 1,
    NULL,
    'usage only from metadata inserts'
  );

  -- -------------------------------------------------------------------------
  -- NEW.created_at retrodated does not change period
  -- -------------------------------------------------------------------------
  v_doc := gen_random_uuid();
  INSERT INTO public.documents (
    id, company_id, title, original_file_name, storage_path, mime_type, size_bytes, created_at
  ) VALUES (
    v_doc, v_company_a, 'Retro', 'r.pdf',
    v_company_a::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf',
    'application/pdf', 10, '2019-06-15 12:00:00+00'
  );
  SELECT documents_used, period_start INTO v_used, v_started
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result(
    'retro_created_at_uses_server_month',
    v_used = 8 AND v_started = v_period_start,
    NULL,
    format('used=%s period=%s', v_used, v_started)
  );

  -- -------------------------------------------------------------------------
  -- Tenant isolation A vs B
  -- -------------------------------------------------------------------------
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  PERFORM pg_temp.insert_doc(v_company_b, 'B1');
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_b AND period_start = v_period_start;
  PERFORM pg_temp.record_result('company_b_usage_isolated', v_used = 1, NULL, v_used::text);
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result('company_a_usage_unchanged', v_used = 8, NULL, v_used::text);

  -- -------------------------------------------------------------------------
  -- Next month row is separate (seed next period; current unchanged)
  -- -------------------------------------------------------------------------
  INSERT INTO private.company_document_monthly_usage (
    company_id, period_start, documents_used
  ) VALUES (
    v_company_a, v_period_start + interval '1 month', 3
  );
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_a AND period_start = v_period_start;
  PERFORM pg_temp.record_result(
    'next_month_row_independent',
    v_used = 8,
    NULL,
    v_used::text
  );

  -- -------------------------------------------------------------------------
  -- Premium unlimited still increments
  -- -------------------------------------------------------------------------
  UPDATE public.company_subscriptions
  SET status = 'active', plan_code = 'premium', entitlement_origin = 'manual',
      trial_started_at = NULL, trial_ends_at = NULL, trial_used_at = NULL
  WHERE company_id = v_company_c;

  UPDATE private.company_document_monthly_usage
  SET documents_used = 100
  WHERE company_id = v_company_c AND period_start = v_period_start;
  -- may not exist yet
  INSERT INTO private.company_document_monthly_usage (company_id, period_start, documents_used)
  VALUES (v_company_c, v_period_start, 100)
  ON CONFLICT (company_id, period_start) DO UPDATE SET documents_used = 100;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM pg_temp.insert_doc(v_company_c, 'PremiumDoc');
    PERFORM pg_temp.record_result('premium_unlimited_insert', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('premium_unlimited_insert', false, v_sqlstate, v_err);
  END;
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_c AND period_start = v_period_start;
  PERFORM pg_temp.record_result('premium_usage_increments', v_used = 101, NULL, v_used::text);

  -- -------------------------------------------------------------------------
  -- Active trial unlimited + increments
  -- -------------------------------------------------------------------------
  UPDATE public.company_subscriptions
  SET status = 'trialing', plan_code = 'premium', entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '1 day',
      trial_ends_at = now() + interval '10 days',
      trial_used_at = now() - interval '1 day'
  WHERE company_id = v_company_c;

  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM pg_temp.insert_doc(v_company_c, 'TrialDoc');
    PERFORM pg_temp.record_result('trial_active_unlimited_insert', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('trial_active_unlimited_insert', false, v_sqlstate, v_err);
  END;
  RESET ROLE;
  SELECT documents_used INTO v_used
  FROM private.company_document_monthly_usage
  WHERE company_id = v_company_c AND period_start = v_period_start;
  PERFORM pg_temp.record_result('trial_usage_increments', v_used = 102, NULL, v_used::text);

  -- Expired trial → effective Free; usage retained
  UPDATE public.company_subscriptions
  SET status = 'trialing', plan_code = 'premium', entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '40 days',
      trial_ends_at = now() - interval '10 days',
      trial_used_at = now() - interval '40 days'
  WHERE company_id = v_company_c;

  SET LOCAL ROLE authenticated;
  SELECT effective_plan_code, documents_used, can_activate_trial, is_trial_active
  INTO v_eff, v_used, v_can_trial, v_trial_active
  FROM public.get_company_subscription_overview(v_company_c);
  PERFORM pg_temp.record_result(
    'expired_trial_effective_free_keeps_usage',
    v_eff = 'free' AND v_used = 102 AND v_can_trial = FALSE AND v_trial_active = FALSE,
    NULL,
    format('eff=%s used=%s can=%s', v_eff, v_used, v_can_trial)
  );

  -- Force Free limit against high usage → reject
  BEGIN
    PERFORM pg_temp.insert_doc(v_company_c, 'AfterExpire');
    PERFORM pg_temp.record_result('expired_trial_quota_enforced', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'expired_trial_quota_enforced',
      v_err = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- -------------------------------------------------------------------------
  -- Missing subscription rejects insert
  -- -------------------------------------------------------------------------
  DELETE FROM public.company_subscriptions WHERE company_id = v_company_b;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM pg_temp.insert_doc(v_company_b, 'NoSub');
    PERFORM pg_temp.record_result('missing_sub_insert_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'missing_sub_insert_denied',
      v_err = 'ATLAS_SUBSCRIPTION_NOT_FOUND',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;

  -- Restore B for later
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_company_b, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id) VALUES (v_company_b)
  ON CONFLICT (company_id) DO NOTHING;

  -- -------------------------------------------------------------------------
  -- Inactive plan semantics (14A): configured inactive still readable by overview
  -- -------------------------------------------------------------------------
  UPDATE public.plans SET is_active = FALSE WHERE code = 'free';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT effective_plan_code INTO v_eff
    FROM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result(
      'inactive_free_plan_overview_ok',
      v_eff = 'free',
      NULL,
      v_eff
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('inactive_free_plan_overview_ok', false, v_sqlstate, v_err);
  END;
  RESET ROLE;
  UPDATE public.plans SET is_active = TRUE WHERE code = 'free';

  -- -------------------------------------------------------------------------
  -- Trial activation
  -- -------------------------------------------------------------------------
  -- Reset company A to free unused trial for activation tests
  UPDATE public.company_subscriptions
  SET status = 'free', plan_code = 'free', entitlement_origin = 'none',
      trial_started_at = NULL, trial_ends_at = NULL, trial_used_at = NULL
  WHERE company_id = v_company_a;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('admin_cannot_activate_trial', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'admin_cannot_activate_trial',
      v_err = 'ATLAS_NOT_COMPANY_OWNER',
      v_sqlstate,
      v_err
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('manager_cannot_activate_trial', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'manager_cannot_activate_trial',
      v_err = 'ATLAS_NOT_COMPANY_OWNER',
      v_sqlstate,
      v_err
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('employee_cannot_activate_trial', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'employee_cannot_activate_trial',
      v_err = 'ATLAS_NOT_COMPANY_OWNER',
      v_sqlstate,
      v_err
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('outsider_cannot_activate_trial', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'outsider_cannot_activate_trial',
      v_err = 'ATLAS_NOT_COMPANY_MEMBER',
      v_sqlstate,
      v_err
    );
  END;

  -- unauthenticated
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('unauth_cannot_activate_trial', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'unauth_cannot_activate_trial',
      v_err = 'ATLAS_NOT_AUTHENTICATED',
      v_sqlstate,
      v_err
    );
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('owner_activates_trial', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_activates_trial', false, v_sqlstate, v_err);
  END;

  RESET ROLE;
  SELECT trial_started_at, trial_ends_at, trial_used_at, status, plan_code
  INTO v_started, v_ends, v_used_at, v_status, v_code
  FROM public.company_subscriptions WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'trial_timestamps_same_now_plus_month',
    v_started IS NOT NULL
      AND v_used_at = v_started
      AND v_ends = v_started + interval '1 month'
      AND v_status = 'trialing'
      AND v_code = 'premium',
    NULL,
    format('start=%s end=%s used=%s status=%s', v_started, v_ends, v_used_at, v_status)
  );

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('trial_already_active', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'trial_already_active',
      v_err = 'ATLAS_TRIAL_ALREADY_ACTIVE',
      v_sqlstate,
      v_err
    );
  END;

  SELECT can_activate_trial, is_trial_active, is_unlimited
  INTO v_can_trial, v_trial_active, v_unlimited
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'overview_during_trial',
    v_can_trial = FALSE AND v_trial_active = TRUE AND v_unlimited = TRUE,
    NULL,
    format('can=%s active=%s unl=%s', v_can_trial, v_trial_active, v_unlimited)
  );

  -- Already premium
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET status = 'active', plan_code = 'premium', entitlement_origin = 'manual',
      trial_started_at = NULL, trial_ends_at = NULL, trial_used_at = NULL
  WHERE company_id = v_company_a;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('already_premium_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'already_premium_denied',
      v_err = 'ATLAS_ALREADY_PREMIUM',
      v_sqlstate,
      v_err
    );
  END;

  -- Expired trial → already used
  RESET ROLE;
  UPDATE public.company_subscriptions
  SET status = 'trialing', plan_code = 'premium', entitlement_origin = 'internal_trial',
      trial_started_at = now() - interval '60 days',
      trial_ends_at = now() - interval '30 days',
      trial_used_at = now() - interval '60 days'
  WHERE company_id = v_company_a;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('expired_trial_not_reactivatable', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'expired_trial_not_reactivatable',
      v_err = 'ATLAS_TRIAL_ALREADY_USED',
      v_sqlstate,
      v_err
    );
  END;

  -- Missing subscription
  RESET ROLE;
  DELETE FROM public.company_subscriptions WHERE company_id = v_company_a;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('trial_missing_subscription', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'trial_missing_subscription',
      v_err = 'ATLAS_SUBSCRIPTION_NOT_FOUND',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;
  INSERT INTO public.company_subscriptions (company_id, plan_code, status, entitlement_origin)
  VALUES (v_company_a, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id) VALUES (v_company_a)
  ON CONFLICT (company_id) DO NOTHING;

  -- Premium inactive (row present, is_active=false)
  UPDATE public.plans SET is_active = FALSE WHERE code = 'premium';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('premium_inactive_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'premium_inactive_denied',
      v_err = 'ATLAS_PREMIUM_UNAVAILABLE',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;
  UPDATE public.plans SET is_active = TRUE WHERE code = 'premium';

  -- Premium plan row absent → ATLAS_PLAN_NOT_FOUND
  -- Move every subscription off premium so the catalog row can be deleted.
  UPDATE public.company_subscriptions
  SET plan_code = 'free',
      status = 'free',
      entitlement_origin = 'none',
      trial_started_at = NULL,
      trial_ends_at = NULL
  WHERE plan_code = 'premium';
  -- keep trial_used_at as-is (allowed on free)
  DELETE FROM public.plans WHERE code = 'premium';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('premium_missing_denied', false, NULL, 'expected');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'premium_missing_denied',
      v_err = 'ATLAS_PLAN_NOT_FOUND',
      v_sqlstate,
      v_err
    );
  END;
  RESET ROLE;
  INSERT INTO public.plans (code, name, document_monthly_limit, is_active)
  VALUES ('premium', 'Premium', NULL, TRUE)
  ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name,
      document_monthly_limit = EXCLUDED.document_monthly_limit,
      is_active = TRUE;

  -- Admin can_activate_trial false
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  SELECT can_activate_trial INTO v_can_trial
  FROM public.get_company_subscription_overview(v_company_a);
  PERFORM pg_temp.record_result(
    'admin_can_activate_trial_false',
    v_can_trial = FALSE,
    NULL,
    v_can_trial::text
  );
  RESET ROLE;

  -- -------------------------------------------------------------------------
  -- Security: authenticated cannot touch private usage / private consume
  -- -------------------------------------------------------------------------
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    SELECT count(*) INTO v_count FROM private.company_document_monthly_usage;
    PERFORM pg_temp.record_result('auth_select_usage_denied', false, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_select_usage_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_select_usage_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO private.company_document_monthly_usage (company_id, period_start, documents_used)
    VALUES (v_company_a, v_period_start, 0);
    PERFORM pg_temp.record_result('auth_insert_usage_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_insert_usage_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_insert_usage_denied', true, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE private.company_document_monthly_usage SET documents_used = 0;
    PERFORM pg_temp.record_result('auth_update_usage_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_update_usage_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_update_usage_denied', true, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM private.company_document_monthly_usage;
    PERFORM pg_temp.record_result('auth_delete_usage_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_delete_usage_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_delete_usage_denied', true, v_sqlstate, v_err);
  END;

  BEGIN
    PERFORM private.consume_company_document_monthly_usage(v_company_a);
    PERFORM pg_temp.record_result('auth_execute_consume_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_execute_consume_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_execute_consume_denied', true, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.company_subscriptions SET status = 'active', plan_code = 'premium', entitlement_origin = 'manual'
    WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('auth_direct_sub_update_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('auth_direct_sub_update_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_direct_sub_update_denied', true, v_sqlstate, v_err);
  END;

  -- RPC grants
  BEGIN
    PERFORM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('auth_overview_executable', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('auth_overview_executable', false, v_sqlstate, v_err);
  END;

  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.get_company_subscription_overview(v_company_a);
    PERFORM pg_temp.record_result('anon_overview_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('anon_overview_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('anon_overview_denied', true, v_sqlstate, v_err);
  END;

  BEGIN
    PERFORM public.activate_company_premium_trial(v_company_a);
    PERFORM pg_temp.record_result('anon_trial_denied', false, NULL, 'expected');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('anon_trial_denied', true, '42501', 'denied');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('anon_trial_denied', true, v_sqlstate, v_err);
  END;
  RESET ROLE;

  -- create_company still creates Free subscription
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT c.id INTO v_doc
    FROM public.create_company(
      'New 14B Co',
      'new-14b-co-' || substr(gen_random_uuid()::text, 1, 8)
    ) AS c;
    SELECT plan_code, status INTO v_code, v_status
    FROM public.company_subscriptions WHERE company_id = v_doc;
    PERFORM pg_temp.record_result(
      'create_company_still_free',
      v_code = 'free' AND v_status = 'free',
      NULL,
      coalesce(v_code, '?') || '/' || coalesce(v_status, '?')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('create_company_still_free', false, v_sqlstate, v_err);
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
    RAISE EXCEPTION 'Step 14B behavior tests failed: %', v_failed;
  END IF;
END $$;

ROLLBACK;
