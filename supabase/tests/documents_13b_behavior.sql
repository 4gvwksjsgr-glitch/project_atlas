-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 13B behavioral checks for public.documents links & delete
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
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_client_a UUID := gen_random_uuid();
  v_client_a2 UUID := gen_random_uuid();
  v_client_b UUID := gen_random_uuid();
  v_client_del UUID := gen_random_uuid();
  v_txn_a UUID := gen_random_uuid();
  v_txn_a2 UUID := gen_random_uuid();
  v_txn_b UUID := gen_random_uuid();
  v_txn_del UUID := gen_random_uuid();
  v_txn_with_client UUID := gen_random_uuid();
  v_doc UUID := gen_random_uuid();
  v_doc_null UUID := gen_random_uuid();
  v_doc_client_null UUID := gen_random_uuid();
  v_doc_txn_null UUID := gen_random_uuid();
  v_doc_both UUID := gen_random_uuid();
  v_doc_atomic UUID := gen_random_uuid();
  v_doc_del_owner UUID := gen_random_uuid();
  v_doc_del_admin UUID := gen_random_uuid();
  v_doc_del_manager UUID := gen_random_uuid();
  v_doc_del_employee UUID := gen_random_uuid();
  v_doc_del_outsider UUID := gen_random_uuid();
  v_doc_del_absent UUID := gen_random_uuid();
  v_sqlstate TEXT;
  v_err TEXT;
  v_count BIGINT;
  v_company_id UUID;
  v_client_id UUID;
  v_transaction_id UUID;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner13b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin13b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager13b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee13b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider13b@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Company A 13B', 'company-a-13b'),
    (v_company_b, 'Company B 13B', 'company-b-13b');

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner');

  INSERT INTO public.clients (id, company_id, name) VALUES
    (v_client_a, v_company_a, 'Cliente A'),
    (v_client_a2, v_company_a, 'Cliente A2'),
    (v_client_b, v_company_b, 'Cliente B'),
    (v_client_del, v_company_a, 'Cliente Delete Probe');

  INSERT INTO public.transactions (
    id, company_id, client_id, kind, amount, occurred_on, description
  ) VALUES
    (v_txn_a, v_company_a, v_client_a, 'expense', 10.00, CURRENT_DATE, 'txn-a'),
    (v_txn_a2, v_company_a, v_client_a2, 'income', 20.00, CURRENT_DATE, 'txn-a2'),
    (v_txn_b, v_company_b, v_client_b, 'expense', 5.00, CURRENT_DATE, 'txn-b'),
    (v_txn_del, v_company_a, NULL, 'expense', 7.00, CURRENT_DATE, 'txn-del-probe'),
    (v_txn_with_client, v_company_a, v_client_a2, 'expense', 8.00, CURRENT_DATE, 'txn-other-client');

  -- ---------------------------------------------------------------------------
  -- 1. Transactions UNIQUE (company_id, id)
  -- ---------------------------------------------------------------------------
  RESET ROLE;
  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname = 'transactions_company_id_id_unique'
      AND conrelid = 'public.transactions'::regclass;
    PERFORM pg_temp.record_result(
      'transactions_company_id_id_unique_present',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'transactions_company_id_id_unique_present', false, v_sqlstate, v_err
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    INSERT INTO public.transactions (
      company_id, kind, amount, occurred_on, description
    ) VALUES (
      v_company_a, 'expense', 9.00, CURRENT_DATE, 'owner-live-insert'
    );
    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname = 'transactions_company_id_id_unique'
      AND conrelid = 'public.transactions'::regclass;
    PERFORM pg_temp.record_result(
      'transactions_unique_existing_rows_valid',
      v_count = 1,
      NULL,
      'insert_ok'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'transactions_unique_existing_rows_valid', false, v_sqlstate, v_err
    );
  END;

  -- ---------------------------------------------------------------------------
  -- 2. Link columns nullable
  -- ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc_null, v_company_a, 'Senza link', 'nolink.pdf',
      v_company_a::text || '/' || v_doc_null::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
    SELECT client_id, transaction_id
    INTO v_client_id, v_transaction_id
    FROM public.documents
    WHERE id = v_doc_null;
    PERFORM pg_temp.record_result(
      'client_id_nullable',
      v_client_id IS NULL,
      NULL,
      COALESCE(v_client_id::text, 'null')
    );
    PERFORM pg_temp.record_result(
      'transaction_id_nullable',
      v_transaction_id IS NULL,
      NULL,
      COALESCE(v_transaction_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('client_id_nullable', false, v_sqlstate, v_err);
    PERFORM pg_temp.record_result('transaction_id_nullable', false, v_sqlstate, v_err);
  END;

  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc, v_company_a, 'Doc base', 'base.pdf',
      v_company_a::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('doc_base_insert', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 3–5. Client link accept / cross-tenant deny / unlink
  -- ---------------------------------------------------------------------------
  BEGIN
    UPDATE public.documents
    SET client_id = v_client_a
    WHERE id = v_doc AND company_id = v_company_a;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    SELECT client_id INTO v_client_id FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result(
      'same_tenant_client_link_ok',
      v_count = 1 AND v_client_id = v_client_a,
      NULL,
      COALESCE(v_client_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('same_tenant_client_link_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents
    SET client_id = v_client_b
    WHERE id = v_doc AND company_id = v_company_a;
    PERFORM pg_temp.record_result('cross_tenant_client_link_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('cross_tenant_client_link_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('cross_tenant_client_link_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET client_id = NULL WHERE id = v_doc;
    SELECT client_id INTO v_client_id FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result(
      'unlink_client_to_null',
      v_client_id IS NULL,
      NULL,
      COALESCE(v_client_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('unlink_client_to_null', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 6. ON DELETE SET NULL (client_id)
  -- ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc_client_null, v_company_a, 'Client SET NULL', 'cnull.pdf',
      v_company_a::text || '/' || v_doc_client_null::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
    UPDATE public.documents
    SET client_id = v_client_del, transaction_id = v_txn_del
    WHERE id = v_doc_client_null;

    RESET ROLE;
    DELETE FROM public.clients WHERE id = v_client_del;

    SELECT company_id, client_id, transaction_id
    INTO v_company_id, v_client_id, v_transaction_id
    FROM public.documents
    WHERE id = v_doc_client_null;

    IF NOT FOUND THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_client_id', false, NULL, 'document missing'
      );
    ELSIF v_client_id IS NOT NULL THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_client_id', false, NULL, 'client_id not null'
      );
    ELSIF v_company_id IS DISTINCT FROM v_company_a THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_client_id', false, NULL, 'company_id changed'
      );
    ELSIF v_transaction_id IS DISTINCT FROM v_txn_del THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_client_id', false, NULL, 'transaction_id changed'
      );
    ELSE
      PERFORM pg_temp.record_result(
        'on_delete_set_null_client_id', true, NULL, 'client_id null only'
      );
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    PERFORM set_config(
      'request.jwt.claims',
      json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
      true
    );
    EXECUTE 'SET LOCAL ROLE authenticated';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('on_delete_set_null_client_id', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 7–9. Transaction link accept / cross-tenant deny / unlink
  -- ---------------------------------------------------------------------------
  BEGIN
    UPDATE public.documents
    SET transaction_id = v_txn_a
    WHERE id = v_doc;
    SELECT transaction_id INTO v_transaction_id FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result(
      'same_tenant_transaction_link_ok',
      v_transaction_id = v_txn_a,
      NULL,
      COALESCE(v_transaction_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('same_tenant_transaction_link_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents
    SET transaction_id = v_txn_b
    WHERE id = v_doc;
    PERFORM pg_temp.record_result('cross_tenant_transaction_denied', false, NULL, 'expected fk');
  EXCEPTION WHEN foreign_key_violation THEN
    PERFORM pg_temp.record_result('cross_tenant_transaction_denied', true, '23503', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('cross_tenant_transaction_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET transaction_id = NULL WHERE id = v_doc;
    SELECT transaction_id INTO v_transaction_id FROM public.documents WHERE id = v_doc;
    PERFORM pg_temp.record_result(
      'unlink_transaction_to_null',
      v_transaction_id IS NULL,
      NULL,
      COALESCE(v_transaction_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('unlink_transaction_to_null', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 10. ON DELETE SET NULL (transaction_id)
  -- ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc_txn_null, v_company_a, 'Txn SET NULL', 'tnull.pdf',
      v_company_a::text || '/' || v_doc_txn_null::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
    UPDATE public.documents
    SET client_id = v_client_a, transaction_id = v_txn_del
    WHERE id = v_doc_txn_null;

    RESET ROLE;
    DELETE FROM public.transactions WHERE id = v_txn_del;

    SELECT company_id, client_id, transaction_id
    INTO v_company_id, v_client_id, v_transaction_id
    FROM public.documents
    WHERE id = v_doc_txn_null;

    IF NOT FOUND THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_transaction_id', false, NULL, 'document missing'
      );
    ELSIF v_transaction_id IS NOT NULL THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_transaction_id', false, NULL, 'transaction_id not null'
      );
    ELSIF v_company_id IS DISTINCT FROM v_company_a THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_transaction_id', false, NULL, 'company_id changed'
      );
    ELSIF v_client_id IS DISTINCT FROM v_client_a THEN
      PERFORM pg_temp.record_result(
        'on_delete_set_null_transaction_id', false, NULL, 'client_id changed'
      );
    ELSE
      PERFORM pg_temp.record_result(
        'on_delete_set_null_transaction_id', true, NULL, 'transaction_id null only'
      );
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    PERFORM set_config(
      'request.jwt.claims',
      json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
      true
    );
    EXECUTE 'SET LOCAL ROLE authenticated';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('on_delete_set_null_transaction_id', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 11. Both links with document client != transaction client
  -- ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc_both, v_company_a, 'Both links', 'both.pdf',
      v_company_a::text || '/' || v_doc_both::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
    UPDATE public.documents
    SET client_id = v_client_a, transaction_id = v_txn_with_client
    WHERE id = v_doc_both;
    SELECT client_id, transaction_id
    INTO v_client_id, v_transaction_id
    FROM public.documents
    WHERE id = v_doc_both;
    PERFORM pg_temp.record_result(
      'both_links_different_clients_ok',
      v_client_id = v_client_a AND v_transaction_id = v_txn_with_client,
      NULL,
      COALESCE(v_client_id::text, 'null') || ',' || COALESCE(v_transaction_id::text, 'null')
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('both_links_different_clients_ok', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 12. Atomic update of both links
  -- ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.documents (
      id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
    ) VALUES (
      v_doc_atomic, v_company_a, 'Atomic', 'atomic.pdf',
      v_company_a::text || '/' || v_doc_atomic::text || '/' || gen_random_uuid()::text || '.pdf',
      'application/pdf', 100
    );
    UPDATE public.documents
    SET client_id = v_client_a2, transaction_id = v_txn_a2
    WHERE id = v_doc_atomic;
    SELECT client_id, transaction_id
    INTO v_client_id, v_transaction_id
    FROM public.documents
    WHERE id = v_doc_atomic;
    PERFORM pg_temp.record_result(
      'atomic_update_both_links',
      v_client_id = v_client_a2 AND v_transaction_id = v_txn_a2,
      NULL,
      'ok'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('atomic_update_both_links', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 13. Privileges: manage roles UPDATE links; employee denied; column limits
  -- ---------------------------------------------------------------------------
  BEGIN
    UPDATE public.documents SET client_id = v_client_a WHERE id = v_doc;
    PERFORM pg_temp.record_result('owner_update_client_id_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_update_client_id_ok', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET transaction_id = v_txn_a WHERE id = v_doc;
    PERFORM pg_temp.record_result('owner_update_transaction_id_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_update_transaction_id_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    UPDATE public.documents SET client_id = v_client_a2 WHERE id = v_doc;
    PERFORM pg_temp.record_result('admin_update_client_id_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_update_client_id_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    UPDATE public.documents SET transaction_id = v_txn_a2 WHERE id = v_doc;
    PERFORM pg_temp.record_result('manager_update_transaction_id_ok', true, NULL, 'ok');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_update_transaction_id_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    UPDATE public.documents SET client_id = v_client_a WHERE id = v_doc;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_update_client_id_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_update_client_id_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_update_client_id_denied', false, v_sqlstate, v_err);
  END;

  BEGIN
    UPDATE public.documents SET transaction_id = v_txn_a WHERE id = v_doc;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result('employee_update_transaction_id_denied', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_update_transaction_id_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_update_transaction_id_denied', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    UPDATE public.documents SET company_id = v_company_b WHERE id = v_doc;
    PERFORM pg_temp.record_result('authenticated_update_company_id_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('authenticated_update_company_id_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_update_company_id_denied',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  BEGIN
    UPDATE public.documents
    SET storage_path = v_company_b::text || '/' || v_doc::text || '/' || gen_random_uuid()::text || '.pdf'
    WHERE id = v_doc;
    PERFORM pg_temp.record_result('authenticated_update_storage_path_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('authenticated_update_storage_path_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'authenticated_update_storage_path_denied',
      v_sqlstate = '42501',
      v_sqlstate,
      v_err
    );
  END;

  -- ---------------------------------------------------------------------------
  -- 14. DELETE metadata privileges
  -- ---------------------------------------------------------------------------
  INSERT INTO public.documents (
    id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
  ) VALUES
    (v_doc_del_owner, v_company_a, 'Del owner', 'o.pdf',
     v_company_a::text || '/' || v_doc_del_owner::text || '/' || gen_random_uuid()::text || '.pdf',
     'application/pdf', 100),
    (v_doc_del_admin, v_company_a, 'Del admin', 'a.pdf',
     v_company_a::text || '/' || v_doc_del_admin::text || '/' || gen_random_uuid()::text || '.pdf',
     'application/pdf', 100),
    (v_doc_del_manager, v_company_a, 'Del manager', 'm.pdf',
     v_company_a::text || '/' || v_doc_del_manager::text || '/' || gen_random_uuid()::text || '.pdf',
     'application/pdf', 100),
    (v_doc_del_employee, v_company_a, 'Del employee', 'e.pdf',
     v_company_a::text || '/' || v_doc_del_employee::text || '/' || gen_random_uuid()::text || '.pdf',
     'application/pdf', 100),
    (v_doc_del_outsider, v_company_a, 'Del outsider', 'x.pdf',
     v_company_a::text || '/' || v_doc_del_outsider::text || '/' || gen_random_uuid()::text || '.pdf',
     'application/pdf', 100);

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_owner;
    SELECT count(*) INTO v_count FROM public.documents WHERE id = v_doc_del_owner;
    PERFORM pg_temp.record_result('owner_delete_ok', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('owner_delete_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_admin;
    SELECT count(*) INTO v_count FROM public.documents WHERE id = v_doc_del_admin;
    PERFORM pg_temp.record_result('admin_delete_ok', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('admin_delete_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_manager;
    SELECT count(*) INTO v_count FROM public.documents WHERE id = v_doc_del_manager;
    PERFORM pg_temp.record_result('manager_delete_ok', v_count = 0, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('manager_delete_ok', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_employee;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count > 0 THEN
      PERFORM pg_temp.record_result('employee_delete_denied', false, NULL, 'deleted unexpectedly');
    ELSE
      SELECT count(*) INTO v_count FROM public.documents WHERE id = v_doc_del_employee;
      PERFORM pg_temp.record_result('employee_delete_denied', v_count = 1, NULL, v_count::text);
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('employee_delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('employee_delete_denied', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_outsider;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count > 0 THEN
      PERFORM pg_temp.record_result('other_tenant_delete_denied', false, NULL, 'deleted unexpectedly');
    ELSE
      -- Verifica esistenza senza RLS (outsider non vede company A in SELECT).
      RESET ROLE;
      SELECT count(*) INTO v_count FROM public.documents WHERE id = v_doc_del_outsider;
      PERFORM pg_temp.record_result(
        'other_tenant_delete_denied',
        v_count = 1,
        NULL,
        v_count::text
      );
      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
      PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
        true
      );
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('other_tenant_delete_denied', true, '42501', 'rejected');
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('other_tenant_delete_denied', false, v_sqlstate, v_err);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    DELETE FROM public.documents WHERE id = v_doc_del_absent;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM pg_temp.record_result(
      'delete_absent_returns_zero_rows',
      v_count = 0,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('delete_absent_returns_zero_rows', false, v_sqlstate, v_err);
  END;

  -- ---------------------------------------------------------------------------
  -- 15–19. Schema metadata checks (indexes, FK names, privileges, policy)
  -- ---------------------------------------------------------------------------
  RESET ROLE;
  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'documents'
      AND indexname = 'documents_company_client_id_idx'
      AND indexdef ILIKE '%WHERE (client_id IS NOT NULL)%';
    PERFORM pg_temp.record_result(
      'partial_index_documents_company_client_id_idx',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'partial_index_documents_company_client_id_idx', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'documents'
      AND indexname = 'documents_company_transaction_id_idx'
      AND indexdef ILIKE '%WHERE (transaction_id IS NOT NULL)%';
    PERFORM pg_temp.record_result(
      'partial_index_documents_company_transaction_id_idx',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'partial_index_documents_company_transaction_id_idx', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname = 'documents_company_client_fkey'
      AND conrelid = 'public.documents'::regclass;
    PERFORM pg_temp.record_result(
      'fk_documents_company_client_fkey',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('fk_documents_company_client_fkey', false, v_sqlstate, v_err);
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname = 'documents_company_transaction_fkey'
      AND conrelid = 'public.documents'::regclass;
    PERFORM pg_temp.record_result(
      'fk_documents_company_transaction_fkey',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('fk_documents_company_transaction_fkey', false, v_sqlstate, v_err);
  END;

  BEGIN
    PERFORM pg_temp.record_result(
      'update_privilege_title',
      has_column_privilege('authenticated', 'public.documents', 'title', 'UPDATE'),
      NULL,
      'title'
    );
    PERFORM pg_temp.record_result(
      'update_privilege_is_archived',
      has_column_privilege('authenticated', 'public.documents', 'is_archived', 'UPDATE'),
      NULL,
      'is_archived'
    );
    PERFORM pg_temp.record_result(
      'update_privilege_client_id',
      has_column_privilege('authenticated', 'public.documents', 'client_id', 'UPDATE'),
      NULL,
      'client_id'
    );
    PERFORM pg_temp.record_result(
      'update_privilege_transaction_id',
      has_column_privilege('authenticated', 'public.documents', 'transaction_id', 'UPDATE'),
      NULL,
      'transaction_id'
    );
    PERFORM pg_temp.record_result(
      'update_privilege_company_id_denied',
      NOT has_column_privilege('authenticated', 'public.documents', 'company_id', 'UPDATE'),
      NULL,
      'company_id'
    );
    PERFORM pg_temp.record_result(
      'update_privilege_storage_path_denied',
      NOT has_column_privilege('authenticated', 'public.documents', 'storage_path', 'UPDATE'),
      NULL,
      'storage_path'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result('update_privilege_title', false, v_sqlstate, v_err);
  END;

  BEGIN
    PERFORM pg_temp.record_result(
      'delete_privilege_authenticated_granted',
      has_table_privilege('authenticated', 'public.documents', 'DELETE'),
      NULL,
      'DELETE'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'delete_privilege_authenticated_granted', false, v_sqlstate, v_err
    );
  END;

  BEGIN
    SELECT count(*) INTO v_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'documents'
      AND policyname = 'documents_delete_manage';
    PERFORM pg_temp.record_result(
      'delete_policy_documents_delete_manage_exists',
      v_count = 1,
      NULL,
      v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_err = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'delete_policy_documents_delete_manage_exists', false, v_sqlstate, v_err
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
