-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 13A behavioral checks for public.documents
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
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated, anon;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_doc UUID := gen_random_uuid();
  v_doc2 UUID := gen_random_uuid();
  v_sqlstate TEXT;
  v_err TEXT;
  v_count BIGINT;
  v_title TEXT;
  v_archived BOOLEAN;
  v_uploaded_by UUID;
  v_path_doc UUID;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner13a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager13a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee13a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider13a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Company A 13A', 'company-a-13a'),
    (v_company_b, 'Company B 13A', 'company-b-13a');

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner');

  -- bucket exists and private
  BEGIN
    SELECT count(*) INTO v_count
    FROM storage.buckets
    WHERE id = 'company-documents' AND public = FALSE AND file_size_limit = 6291456;
    PERFORM pg_temp.record_result('bucket_private_exists', v_count = 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('bucket_private_exists', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc, v_company_a, 'Contratto', 'contratto.pdf',
      v_company_a::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 1024
    );
    PERFORM pg_temp.record_result('owner_insert_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_insert_ok', false, v_sqlstate, v_err);
  END;

  -- uploaded_by default = auth.uid() when omitted
  BEGIN
    SELECT uploaded_by INTO v_uploaded_by FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result(
      'uploaded_by_defaults_to_auth_uid',
      v_uploaded_by = v_owner,
      NULL,
      COALESCE(v_uploaded_by::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uploaded_by_defaults_to_auth_uid', false, v_sqlstate, v_err);
  END;

  -- client cannot supply uploaded_by on INSERT (column privilege)
  BEGIN
    INSERT INTO public.documents (
      id, company_id, uploaded_by, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      gen_random_uuid(), v_company_a, v_employee, 'Impersonate', 'x.pdf',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('uploaded_by_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('uploaded_by_insert_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'uploaded_by_insert_denied',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  -- Canonical path accepts: pdf / jpg / png / webp
  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Path JPG', 'a.jpg',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.jpg',
      'image/jpeg', 10
    );
    PERFORM pg_temp.record_result('path_accept_jpg', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_accept_jpg', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Path PNG', 'a.png',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.png',
      'image/png', 10
    );
    PERFORM pg_temp.record_result('path_accept_png', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_accept_png', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Path WEBP', 'a.webp',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.webp',
      'image/webp', 10
    );
    PERFORM pg_temp.record_result('path_accept_webp', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_accept_webp', false, v_sqlstate, v_err);
  END;

  -- Path CHECK denials
  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Bad Path', 'x.pdf',
      v_company_b::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_other_company_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_other_company_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_other_company_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Bad Doc Id', 'x.pdf',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_other_document_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_other_document_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_other_document_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Not UUID Object', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/not-a-uuid.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_object_not_uuid_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_object_not_uuid_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_object_not_uuid_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Short UUID', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/cccccccc-cccc-cccc-cccc-ccccccccccc.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_object_uuid_incomplete_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_object_uuid_incomplete_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_object_uuid_incomplete_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Upper Object', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_object_uuid_uppercase_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_object_uuid_uppercase_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_object_uuid_uppercase_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'No Ext', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text,
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_no_extension_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_no_extension_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_no_extension_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Jpeg Ext', 'a.jpeg',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.jpeg',
      'image/jpeg', 10
    );
    PERFORM pg_temp.record_result('path_ext_jpeg_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_ext_jpeg_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_ext_jpeg_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Exe Ext', 'a.exe',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.exe',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_ext_exe_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_ext_exe_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_ext_exe_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Upper Ext', 'a.PDF',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.PDF',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_ext_uppercase_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_ext_uppercase_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_ext_uppercase_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Double Slash', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '//' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_double_slash_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_double_slash_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_double_slash_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Extra Segment', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/extra/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_extra_segment_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_extra_segment_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_extra_segment_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Trailing Slash', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.pdf/',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_trailing_slash_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_trailing_slash_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_trailing_slash_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Traversal', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/../' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_traversal_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_traversal_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_traversal_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Prefix', 'x.pdf',
      'prefix-' || v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_arbitrary_prefix_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_arbitrary_prefix_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_arbitrary_prefix_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Suffix', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.pdf.evil',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_suffix_after_ext_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_suffix_after_ext_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_suffix_after_ext_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Query', 'x.pdf',
      v_company_a::text || '/' || v_path_doc::text || '/' || gen_random_uuid()::text || '.pdf?x=1',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_query_string_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_query_string_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_query_string_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    v_path_doc := gen_random_uuid();
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_path_doc, v_company_a, 'Empty Path', 'x.pdf',
      '',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('path_empty_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('path_empty_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('path_empty_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      gen_random_uuid(), v_company_a, 'Bad Mime', 'x.bin',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/octet-stream', 10
    );
    PERFORM pg_temp.record_result('mime_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('mime_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('mime_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      gen_random_uuid(), v_company_a, 'Too Big', 'big.pdf',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 6291457
    );
    PERFORM pg_temp.record_result('size_max_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('size_max_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('size_max_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      gen_random_uuid(), v_company_a, '  ', 'x.pdf',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('title_empty_denied', false, NULL, 'expected check');
  EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.record_result('title_empty_denied', true, '23514', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('title_empty_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET title = 'Contratto aggiornato' WHERE id = v_doc;
    SELECT title INTO v_title FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result('owner_update_title', v_title = 'Contratto aggiornato', NULL, v_title);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_update_title', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET is_archived = TRUE WHERE id = v_doc;
    SELECT is_archived INTO v_archived FROM public.documents WHERE id = v_doc;
    UPDATE public.documents SET is_archived = FALSE WHERE id = v_doc;
    PERFORM pg_temp.record_result('owner_archive_reactivate', v_archived = TRUE, NULL, v_archived::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_archive_reactivate', false, v_sqlstate, v_err);
  END;

  BEGIN
    DELETE FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result('owner_delete_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('owner_delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_delete_denied', v_sqlstate = '42501', v_sqlstate, v_err);
  END;

  -- manager insert
  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc2, v_company_a, 'Ricevuta', 'ricevuta.jpg',
      v_company_a::text || '/' || v_doc2::text || '/' || gen_random_uuid()::text || '.jpg',
      'image/jpeg', 2048
    );
    PERFORM pg_temp.record_result('manager_insert_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_insert_ok', false, v_sqlstate, v_err);
  END;

  -- employee denied write, allowed read
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.documents WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('employee_select_ok', v_count >= 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_select_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      gen_random_uuid(), v_company_a, 'Emp', 'e.pdf',
      v_company_a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 10
    );
    PERFORM pg_temp.record_result('employee_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_insert_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'employee_insert_denied',
      v_sqlstate IN ('42501', '42501') OR v_err ILIKE '%row-level security%',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    UPDATE public.documents SET title = 'Hacked' WHERE company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_update_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_update_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_update_denied', false, v_sqlstate, v_err);
  END;

  -- other tenant cannot see
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.documents WHERE company_id = v_company_a;
    PERFORM pg_temp.record_result('other_tenant_select_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('other_tenant_select_denied', false, v_sqlstate, v_err);
  END;

  -- storage path helpers: malformed path returns false/null without throw
  RESET ROLE;
  BEGIN
    PERFORM pg_temp.record_result(
      'storage_path_malformed_safe',
      private.storage_company_documents_path_is_canonical('invalid/path') = FALSE
        AND private.storage_uuid_path_segment('invalid/path', 1) IS NULL,
      NULL,
      'ok'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('storage_path_malformed_safe', false, v_sqlstate, v_err);
  END;

  -- column privileges: authenticated cannot update uploaded_by
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    UPDATE public.documents SET uploaded_by = v_employee WHERE id = v_doc;
    PERFORM pg_temp.record_result('uploaded_by_update_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('uploaded_by_update_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('uploaded_by_update_denied', v_sqlstate = '42501', v_sqlstate, v_err);
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
