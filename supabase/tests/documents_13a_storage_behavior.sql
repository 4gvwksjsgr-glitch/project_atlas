-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 13A Storage API behavioral checks (storage.objects)
-- BEGIN … ROLLBACK
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
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated, anon;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_doc UUID := gen_random_uuid();
  v_obj UUID := gen_random_uuid();
  v_path TEXT;
  v_bad TEXT;
  v_sqlstate TEXT;
  v_err TEXT;
  v_count BIGINT;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner13as@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee13as@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider13as@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Storage Co A', 'storage-co-a-13a'),
    (v_company_b, 'Storage Co B', 'storage-co-b-13a');

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner');

  v_path := v_company_a::text || '/' || v_doc::text || '/' || v_obj::text || '.pdf';

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner, metadata)
    VALUES (
      'company-documents',
      v_path,
      v_owner,
      jsonb_build_object('mimetype', 'application/pdf', 'size', 100)
    );
    PERFORM pg_temp.record_result('storage_owner_upload_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_owner_upload_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM storage.objects
    WHERE bucket_id = 'company-documents' AND name = v_path;
    PERFORM pg_temp.record_result('storage_owner_select_ok', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_owner_select_ok', false, v_sqlstate, v_err);
  END;

  v_bad := v_company_b::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf';
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('company-documents', v_bad, v_owner);
    PERFORM pg_temp.record_result('storage_other_company_path_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('storage_other_company_path_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'storage_other_company_path_denied',
      v_err ILIKE '%policy%' OR v_sqlstate IN ('42501', '23514'),
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES ('company-documents', 'invalid/path', v_owner);
    PERFORM pg_temp.record_result('storage_malformed_path_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('storage_malformed_path_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'storage_malformed_path_denied',
      v_err ILIKE '%policy%' OR v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES (
      'company-documents',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.exe',
      v_owner
    );
    PERFORM pg_temp.record_result('storage_bad_extension_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('storage_bad_extension_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'storage_bad_extension_denied',
      v_err ILIKE '%policy%' OR v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  -- employee cannot upload
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner)
    VALUES (
      'company-documents',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      v_employee
    );
    PERFORM pg_temp.record_result('storage_employee_upload_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('storage_employee_upload_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'storage_employee_upload_denied',
      v_err ILIKE '%policy%' OR v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM storage.objects
    WHERE bucket_id = 'company-documents' AND name = v_path;
    PERFORM pg_temp.record_result('storage_employee_select_ok', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_employee_select_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM storage.objects WHERE bucket_id = 'company-documents' AND name = v_path;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('storage_employee_delete_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('storage_employee_delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_employee_delete_denied', false, v_sqlstate, v_err);
  END;

  -- other tenant cannot read
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count
    FROM storage.objects
    WHERE bucket_id = 'company-documents' AND name = v_path;
    PERFORM pg_temp.record_result('storage_other_tenant_select_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_other_tenant_select_denied', false, v_sqlstate, v_err);
  END;

  -- owner cleanup delete: SQL diretto su storage.objects è bloccato dal
  -- motore Storage ("Use the Storage API instead"). Verifichiamo policy +
  -- helper; il DELETE effettivo è coperto dal test Storage API REST.
  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'company_documents_delete_owner_admin_manager'
      AND cmd = 'DELETE';
    PERFORM pg_temp.record_result(
      'storage_owner_cleanup_delete_policy',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'storage_owner_cleanup_delete_policy',
      false,
      v_sqlstate,
      v_err
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
