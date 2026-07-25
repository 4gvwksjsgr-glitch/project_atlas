-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 12A behavioral checks for public.transaction_categories
--
-- Utilizzo: dopo `supabase db reset` sul stack locale.
-- Nota: i check su updated_at usano DO blocks separati (transazioni distinte),
-- perché NOW() è stabile all'interno della stessa transazione.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
);

CREATE TEMP TABLE test_ctx (
  key TEXT PRIMARY KEY,
  uuid_value UUID,
  tstz_value TIMESTAMPTZ
);

GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_ctx TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_ctx TO anon;

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

CREATE OR REPLACE FUNCTION pg_temp.set_ctx(
  p_key TEXT,
  p_uuid UUID DEFAULT NULL,
  p_tstz TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  INSERT INTO test_ctx(key, uuid_value, tstz_value)
  VALUES (p_key, p_uuid, p_tstz)
  ON CONFLICT (key) DO UPDATE
  SET uuid_value = COALESCE(EXCLUDED.uuid_value, test_ctx.uuid_value),
      tstz_value = COALESCE(EXCLUDED.tstz_value, test_ctx.tstz_value);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.get_uuid(p_key TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
  SELECT uuid_value FROM test_ctx WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION pg_temp.get_tstz(p_key TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
  SELECT tstz_value FROM test_ctx WHERE key = p_key;
$$;

REVOKE ALL ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.set_ctx(TEXT, UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.get_uuid(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.get_tstz(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION pg_temp.set_ctx(TEXT, UUID, TIMESTAMPTZ) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION pg_temp.get_uuid(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION pg_temp.get_tstz(TEXT) TO authenticated, anon;

-- Seed identities / companies (postgres)
DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  )
  VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner12a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin12a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager12a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee12a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider12a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug)
  VALUES
    (v_company_a, 'Company A 12A', 'company-a-12a'),
    (v_company_b, 'Company B 12A', 'company-b-12a');

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_owner, 'owner');

  PERFORM pg_temp.set_ctx('owner', v_owner);
  PERFORM pg_temp.set_ctx('admin', v_admin);
  PERFORM pg_temp.set_ctx('manager', v_manager);
  PERFORM pg_temp.set_ctx('employee', v_employee);
  PERFORM pg_temp.set_ctx('outsider', v_outsider);
  PERFORM pg_temp.set_ctx('company_a', v_company_a);
  PERFORM pg_temp.set_ctx('company_b', v_company_b);
END $$;

-- Owner create (transaction 1)
DO $$
DECLARE
  v_cat UUID;
  v_updated_at TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('owner')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('owner')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (pg_temp.get_uuid('company_a'), 'Software', 'expense', true)
    RETURNING id, updated_at INTO v_cat, v_updated_at;
    PERFORM pg_temp.set_ctx('owner_cat', v_cat, v_updated_at);
    PERFORM pg_temp.record_result('owner_create', true, NULL, v_cat::text);
    PERFORM pg_temp.record_result(
      'defaults_id_timestamps',
      (v_cat IS NOT NULL AND v_updated_at IS NOT NULL),
      NULL,
      'ok'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_create', false, v_sqlstate, v_err);
    PERFORM pg_temp.record_result('defaults_id_timestamps', false, v_sqlstate, v_err);
  END;

  -- Duplicates while name is still "Software"
  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (pg_temp.get_uuid('company_a'), 'software', 'expense', true);
    PERFORM pg_temp.record_result('dup_software_lower', false, NULL, 'expected unique');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('dup_software_lower', true, '23505', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('dup_software_lower', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (pg_temp.get_uuid('company_a'), 'SOFTWARE', 'expense', true);
    PERFORM pg_temp.record_result('dup_software_upper', false, NULL, 'expected unique');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('dup_software_upper', true, '23505', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('dup_software_upper', false, v_sqlstate, v_err);
  END;
END $$;

SELECT pg_sleep(1.1);

-- Owner rename + updated_at (transaction 2 — NOW() differs)
DO $$
DECLARE
  v_updated_at_2 TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('owner')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('owner')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    UPDATE public.transaction_categories
    SET name = 'Licenze'
    WHERE id = pg_temp.get_uuid('owner_cat')
      AND company_id = pg_temp.get_uuid('company_a')
    RETURNING updated_at INTO v_updated_at_2;
    IF v_updated_at_2 <= pg_temp.get_tstz('owner_cat') THEN
      RAISE EXCEPTION 'updated_at not advanced';
    END IF;
    PERFORM pg_temp.set_ctx('owner_cat', pg_temp.get_uuid('owner_cat'), v_updated_at_2);
    PERFORM pg_temp.record_result('owner_rename_updated_at', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_rename_updated_at', false, v_sqlstate, v_err);
  END;
END $$;

-- Owner constraints / archive / immutability / delete / cross-company name
DO $$
DECLARE
  v_sqlstate TEXT;
  v_err TEXT;
  v_company_a UUID := pg_temp.get_uuid('company_a');
  v_company_b UUID := pg_temp.get_uuid('company_b');
  v_cat UUID := pg_temp.get_uuid('owner_cat');
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('owner')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('owner')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, ' Software ', 'expense', true);
    PERFORM pg_temp.record_result('name_trim_check', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('name_trim_check', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('name_trim_check', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, 'Licenze', 'income', true);
    PERFORM pg_temp.record_result('same_name_diff_kind', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('same_name_diff_kind', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, '', 'expense', true);
    PERFORM pg_temp.record_result('empty_name', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('empty_name', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('empty_name', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, repeat('x', 81), 'expense', true);
    PERFORM pg_temp.record_result('name_too_long', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('name_too_long', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('name_too_long', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET is_active = false
    WHERE id = v_cat AND company_id = v_company_a;
    UPDATE public.transaction_categories
    SET is_active = true
    WHERE id = v_cat AND company_id = v_company_a;
    PERFORM pg_temp.record_result('owner_archive_reactivate', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_archive_reactivate', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET is_active = false
    WHERE id = v_cat AND company_id = v_company_a;
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, 'Licenze', 'expense', true);
    PERFORM pg_temp.record_result('archived_name_blocks', false, NULL, 'expected unique');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.record_result('archived_name_blocks', true, '23505', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('archived_name_blocks', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET company_id = v_company_b
    WHERE id = v_cat;
    PERFORM pg_temp.record_result('immutable_company_id', false, NULL, 'expected deny');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('immutable_company_id', true, '23514', 'rejected');
  WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('immutable_company_id', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('immutable_company_id', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET kind = 'income'
    WHERE id = v_cat AND company_id = v_company_a;
    PERFORM pg_temp.record_result('immutable_kind', false, NULL, 'expected deny');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('immutable_kind', true, '23514', 'rejected');
  WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('immutable_kind', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('immutable_kind', false, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM public.transaction_categories WHERE id = v_cat;
    PERFORM pg_temp.record_result('delete_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('delete_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_b, 'Licenze', 'expense', true);
    PERFORM pg_temp.record_result('same_name_other_company', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('same_name_other_company', false, v_sqlstate, v_err);
  END;
END $$;

-- Admin create
DO $$
DECLARE
  v_admin_cat UUID;
  v_updated_at TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('admin')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('admin')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (pg_temp.get_uuid('company_a'), 'AdminCat', 'income', true)
    RETURNING id, updated_at INTO v_admin_cat, v_updated_at;
    PERFORM pg_temp.set_ctx('admin_cat', v_admin_cat, v_updated_at);
    PERFORM pg_temp.record_result('admin_create', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_create', false, v_sqlstate, v_err);
  END;
END $$;

SELECT pg_sleep(1.1);

DO $$
DECLARE
  v_updated_at_2 TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('admin')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('admin')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    UPDATE public.transaction_categories
    SET name = 'AdminCatRenamed'
    WHERE id = pg_temp.get_uuid('admin_cat')
      AND company_id = pg_temp.get_uuid('company_a')
    RETURNING updated_at INTO v_updated_at_2;
    IF v_updated_at_2 <= pg_temp.get_tstz('admin_cat') THEN
      RAISE EXCEPTION 'updated_at not advanced';
    END IF;
    UPDATE public.transaction_categories
    SET is_active = false
    WHERE id = pg_temp.get_uuid('admin_cat');
    UPDATE public.transaction_categories
    SET is_active = true
    WHERE id = pg_temp.get_uuid('admin_cat');
    PERFORM pg_temp.record_result('admin_rename_archive_reactivate', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_rename_archive_reactivate', false, v_sqlstate, v_err);
  END;
END $$;

-- Manager create
DO $$
DECLARE
  v_manager_cat UUID;
  v_updated_at TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('manager')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('manager')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (pg_temp.get_uuid('company_a'), 'ManagerCat', 'expense', true)
    RETURNING id, updated_at INTO v_manager_cat, v_updated_at;
    PERFORM pg_temp.set_ctx('manager_cat', v_manager_cat, v_updated_at);
    PERFORM pg_temp.record_result('manager_create', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_create', false, v_sqlstate, v_err);
  END;
END $$;

SELECT pg_sleep(1.1);

DO $$
DECLARE
  v_updated_at_2 TIMESTAMPTZ;
  v_sqlstate TEXT;
  v_err TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('manager')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('manager')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    UPDATE public.transaction_categories
    SET name = 'ManagerCatRenamed'
    WHERE id = pg_temp.get_uuid('manager_cat')
      AND company_id = pg_temp.get_uuid('company_a')
    RETURNING updated_at INTO v_updated_at_2;
    IF v_updated_at_2 <= pg_temp.get_tstz('manager_cat') THEN
      RAISE EXCEPTION 'updated_at not advanced';
    END IF;
    UPDATE public.transaction_categories
    SET is_active = false
    WHERE id = pg_temp.get_uuid('manager_cat');
    UPDATE public.transaction_categories
    SET is_active = true
    WHERE id = pg_temp.get_uuid('manager_cat');
    PERFORM pg_temp.record_result('manager_rename_archive_reactivate', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_rename_archive_reactivate', false, v_sqlstate, v_err);
  END;
END $$;

-- Employee + outsider + cross-tenant
DO $$
DECLARE
  v_count BIGINT;
  v_sqlstate TEXT;
  v_err TEXT;
  v_company_a UUID := pg_temp.get_uuid('company_a');
  v_company_b UUID := pg_temp.get_uuid('company_b');
  v_cat UUID := pg_temp.get_uuid('owner_cat');
BEGIN
  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('employee')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('employee')::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    SELECT count(*) INTO v_count
    FROM public.transaction_categories
    WHERE company_id = v_company_a;
    IF v_count < 1 THEN
      RAISE EXCEPTION 'employee cannot select';
    END IF;
    PERFORM pg_temp.record_result('employee_select', true, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_select', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, 'EmpCat', 'expense', true);
    PERFORM pg_temp.record_result('employee_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_insert_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_insert_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET name = 'Hacked'
    WHERE id = v_cat AND company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_rename_denied', v_count = 0, NULL, COALESCE(v_count::text, '0'));
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_rename_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_rename_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET is_active = false
    WHERE id = v_cat AND company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_archive_denied', v_count = 0, NULL, COALESCE(v_count::text, '0'));
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_archive_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_archive_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET is_active = true
    WHERE id = v_cat AND company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_reactivate_denied', v_count = 0, NULL, COALESCE(v_count::text, '0'));
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_reactivate_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_reactivate_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM public.transaction_categories WHERE id = v_cat;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result(
      'employee_delete_denied',
      (v_count = 0),
      NULL,
      COALESCE(v_count::text, '0')
    );
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_delete_denied', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('outsider')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('outsider')::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    SELECT count(*) INTO v_count
    FROM public.transaction_categories
    WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('outsider_select_empty', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('outsider_select_empty', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_a, 'CrossTenant', 'expense', true);
    PERFORM pg_temp.record_result('outsider_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('outsider_insert_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('outsider_insert_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('admin')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('admin')::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    INSERT INTO public.transaction_categories (company_id, name, kind, is_active)
    VALUES (v_company_b, 'AdminOnB', 'expense', true);
    PERFORM pg_temp.record_result('cross_tenant_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('cross_tenant_insert_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('cross_tenant_insert_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transaction_categories
    SET name = 'HackedB'
    WHERE company_id = v_company_b;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('cross_tenant_update_denied', v_count = 0, NULL, COALESCE(v_count::text, '0'));
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('cross_tenant_update_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('cross_tenant_update_denied', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', pg_temp.get_uuid('manager')::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', pg_temp.get_uuid('manager')::text, 'role', 'authenticated')::text,
    true
  );

  BEGIN
    SELECT count(*) INTO v_count
    FROM public.transaction_categories
    WHERE company_id = v_company_b;
    PERFORM pg_temp.record_result('manager_cross_tenant_select_empty', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_cross_tenant_select_empty', false, v_sqlstate, v_err);
  END;
END $$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed,
  count(*) FILTER (WHERE NOT passed) AS failed,
  count(*) AS total
FROM test_results;
