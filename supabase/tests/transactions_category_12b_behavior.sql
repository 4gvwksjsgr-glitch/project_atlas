-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 12B behavioral checks for transactions.category_id
--
-- Single explicit transaction: BEGIN … ROLLBACK (no residual local data).
-- Nested BEGIN blocks act as savepoints for expected failures.
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

CREATE TEMP TABLE test_ctx (
  key TEXT PRIMARY KEY,
  uuid_value UUID
) ON COMMIT DROP;

GRANT SELECT, INSERT, UPDATE, DELETE ON test_ctx TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.set_ctx(p_key TEXT, p_uuid UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  INSERT INTO test_ctx(key, uuid_value) VALUES (p_key, p_uuid)
  ON CONFLICT (key) DO UPDATE SET uuid_value = EXCLUDED.uuid_value;
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

REVOKE ALL ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.set_ctx(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_temp.get_uuid(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION pg_temp.set_ctx(TEXT, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION pg_temp.get_uuid(TEXT) TO authenticated, anon;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_cat_exp UUID := gen_random_uuid();
  v_cat_inc UUID := gen_random_uuid();
  v_cat_arch UUID := gen_random_uuid();
  v_cat_b UUID := gen_random_uuid();
  v_cat_del UUID := gen_random_uuid();
  v_txn UUID;
  v_txn_del UUID;
  v_sqlstate TEXT;
  v_err TEXT;
  v_count BIGINT;
  v_income NUMERIC;
  v_company_id UUID;
  v_kind TEXT;
  v_category_id UUID;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner12b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin12b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager12b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee12b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Company A 12B', 'company-a-12b'),
    (v_company_b, 'Company B 12B', 'company-b-12b');

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_owner, 'owner');

  INSERT INTO public.transaction_categories (id, company_id, name, kind, is_active)
  VALUES
    (v_cat_exp, v_company_a, 'Software', 'expense', true),
    (v_cat_inc, v_company_a, 'Vendite', 'income', true),
    (v_cat_arch, v_company_a, 'Legacy Soft', 'expense', false),
    (v_cat_b, v_company_b, 'Altro Soft', 'expense', true);

  PERFORM pg_temp.set_ctx('owner', v_owner);
  PERFORM pg_temp.set_ctx('admin', v_admin);
  PERFORM pg_temp.set_ctx('manager', v_manager);
  PERFORM pg_temp.set_ctx('employee', v_employee);
  PERFORM pg_temp.set_ctx('company_a', v_company_a);
  PERFORM pg_temp.set_ctx('company_b', v_company_b);
  PERFORM pg_temp.set_ctx('cat_exp', v_cat_exp);
  PERFORM pg_temp.set_ctx('cat_inc', v_cat_inc);
  PERFORM pg_temp.set_ctx('cat_arch', v_cat_arch);
  PERFORM pg_temp.set_ctx('cat_b', v_cat_b);

  -- Pre-existing style row without category (as postgres) remains null
  INSERT INTO public.transactions (
    company_id, kind, amount, occurred_on, description, category_id
  ) VALUES (
    v_company_a, 'expense', 5.00, CURRENT_DATE, 'legacy-null-cat', NULL
  );

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 10.00, CURRENT_DATE, 'no-cat', NULL
    ) RETURNING id INTO v_txn;
    PERFORM pg_temp.set_ctx('txn', v_txn);
    PERFORM pg_temp.record_result('txn_without_category', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('txn_without_category', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 11.00, CURRENT_DATE, 'with-exp', v_cat_exp
    );
    PERFORM pg_temp.record_result('compatible_category', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('compatible_category', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 12.00, CURRENT_DATE, 'income-on-expense', v_cat_inc
    );
    PERFORM pg_temp.record_result('income_on_expense_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('income_on_expense_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('income_on_expense_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'income', 13.00, CURRENT_DATE, 'expense-on-income', v_cat_exp
    );
    PERFORM pg_temp.record_result('expense_on_income_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('expense_on_income_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('expense_on_income_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 14.00, CURRENT_DATE, 'other-company', v_cat_b
    );
    PERFORM pg_temp.record_result('other_company_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('other_company_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('other_company_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 15.00, CURRENT_DATE, 'missing-cat', gen_random_uuid()
    );
    PERFORM pg_temp.record_result('missing_category_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('missing_category_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('missing_category_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transactions
    SET kind = 'income'
    WHERE id = pg_temp.get_uuid('txn') AND company_id = v_company_a
      AND category_id IS NULL;
    -- attach expense cat then change kind
    UPDATE public.transactions
    SET category_id = v_cat_exp
    WHERE id = pg_temp.get_uuid('txn');
    UPDATE public.transactions
    SET kind = 'income'
    WHERE id = pg_temp.get_uuid('txn');
    PERFORM pg_temp.record_result('kind_change_incompatible_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('kind_change_incompatible_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('kind_change_incompatible_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transactions
    SET category_id = NULL
    WHERE id = pg_temp.get_uuid('txn') AND company_id = v_company_a;
    PERFORM pg_temp.record_result('clear_category_allowed', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('clear_category_allowed', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 16.00, CURRENT_DATE, 'archived-keep', v_cat_arch
    ) RETURNING id INTO v_txn;
    UPDATE public.transactions
    SET description = 'archived-kept'
    WHERE id = v_txn AND category_id = v_cat_arch;
    PERFORM pg_temp.record_result('archived_assigned_kept', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('archived_assigned_kept', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 17.00, CURRENT_DATE, 'new-archived-link', v_cat_arch
    );
    PERFORM pg_temp.record_result('new_archived_link_db_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('new_archived_link_db_ok', false, v_sqlstate, v_err);
  END;

  -- admin create
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'income', 18.00, CURRENT_DATE, 'admin-ok', v_cat_inc
    );
    PERFORM pg_temp.record_result('admin_create_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_create_ok', false, v_sqlstate, v_err);
  END;

  -- manager create
  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 19.00, CURRENT_DATE, 'manager-ok', v_cat_exp
    );
    PERFORM pg_temp.record_result('manager_create_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_create_ok', false, v_sqlstate, v_err);
  END;

  -- employee denied
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 20.00, CURRENT_DATE, 'emp-denied', v_cat_exp
    );
    PERFORM pg_temp.record_result('employee_create_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_create_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_create_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.transactions
    SET description = 'hacked'
    WHERE company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_update_denied', v_count = 0, NULL, COALESCE(v_count::text, '0'));
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_update_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_update_denied', false, v_sqlstate, v_err);
  END;

  -- legacy null still present + cash summary style aggregate still works
  RESET ROLE;
  SELECT count(*) INTO v_count
  FROM public.transactions
  WHERE company_id = v_company_a AND description = 'legacy-null-cat' AND category_id IS NULL;
  PERFORM pg_temp.record_result('legacy_null_preserved', v_count = 1, NULL, v_count::text);

  SELECT COALESCE(SUM(amount), 0) INTO v_income
  FROM public.transactions
  WHERE company_id = v_company_a AND kind = 'income';
  PERFORM pg_temp.record_result('summary_query_ok', v_income >= 0, NULL, v_income::text);

  -- ON DELETE SET NULL (category_id): privileged local role, no policy/migration changes
  BEGIN
    INSERT INTO public.transaction_categories (id, company_id, name, kind, is_active)
    VALUES (v_cat_del, v_company_a, 'Delete Probe', 'expense', true);

    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description, category_id
    ) VALUES (
      v_company_a, 'expense', 21.00, CURRENT_DATE, 'on-delete-set-null-probe', v_cat_del
    ) RETURNING id INTO v_txn_del;

    SELECT company_id, kind, category_id
    INTO v_company_id, v_kind, v_category_id
    FROM public.transactions
    WHERE id = v_txn_del;

    IF v_company_id IS DISTINCT FROM v_company_a
       OR v_kind IS DISTINCT FROM 'expense'
       OR v_category_id IS DISTINCT FROM v_cat_del THEN
      RAISE EXCEPTION 'precondition failed before category delete';
    END IF;

    DELETE FROM public.transaction_categories WHERE id = v_cat_del;

    SELECT company_id, kind, category_id
    INTO v_company_id, v_kind, v_category_id
    FROM public.transactions
    WHERE id = v_txn_del;

    IF NOT FOUND THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_category_id', false, NULL, 'transaction missing'
      );
    ELSIF v_category_id IS NOT NULL THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_category_id', false, NULL, 'category_id not null'
      );
    ELSIF v_company_id IS DISTINCT FROM v_company_a THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_category_id', false, NULL, 'company_id changed'
      );
    ELSIF v_kind IS DISTINCT FROM 'expense' THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_category_id', false, NULL, 'kind changed'
      );
    ELSE
      PERFORM pg_temp.record_result(
        'on_delete_set_null_category_id', true, NULL, 'category_id null only'
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'on_delete_set_null_category_id', false, v_sqlstate, v_err
    );
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

ROLLBACK;
