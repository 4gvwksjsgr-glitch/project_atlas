-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Working Step 16: transaction import behavior
-- BEGIN … ROLLBACK: no persistent residue.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.record_result(
  p_name TEXT,
  p_passed BOOLEAN,
  p_sqlstate TEXT DEFAULT NULL,
  p_detail TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO test_results (test_name, passed, sqlstate, detail)
  VALUES (p_name, p_passed, p_sqlstate, p_detail)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      sqlstate = EXCLUDED.sqlstate,
      detail = EXCLUDED.detail;
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO anon;

DO $body$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_batch UUID;
  v_imported BIGINT;
  v_tx_ids UUID[];
  v_count INTEGER;
  v_client_null INTEGER;
  v_cat_null INTEGER;
  v_sha TEXT := repeat('a', 64);
  v_sha2 TEXT := repeat('b', 64);
  v_fp1 TEXT := repeat('c', 64);
  v_fp2 TEXT := repeat('d', 64);
  v_fp3 TEXT := repeat('e', 64);
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner16@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin16@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager16@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee16@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider16@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, email, full_name)
  SELECT u.id, u.email, 'Step16'
  FROM auth.users u
  WHERE u.id IN (v_owner, v_admin, v_manager, v_employee, v_outsider)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Step16 Co A', 'step16-co-a-' || substr(replace(v_company_a::text, '-', ''), 1, 8)),
    (v_company_b, 'Step16 Co B', 'step16-co-b-' || substr(replace(v_company_b::text, '-', ''), 1, 8));

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_outsider, 'owner');

  -- Unauthenticated
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'a.csv', v_sha, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-01-15',
        'kind', 'income',
        'amount', '10.00',
        'description', 'X',
        'row_fingerprint', v_fp1
      ))
    );
    PERFORM pg_temp.record_result('unauthenticated_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'unauthenticated_denied',
      SQLERRM LIKE '%ATLAS_NOT_AUTHENTICATED%', SQLSTATE, SQLERRM
    );
  END;

  -- Employee denied
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'a.csv', v_sha, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-01-15',
        'kind', 'income',
        'amount', '10.00',
        'description', 'X',
        'row_fingerprint', v_fp1
      ))
    );
    PERFORM pg_temp.record_result('employee_cannot_import', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'employee_cannot_import',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Cross-tenant denied
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'a.csv', v_sha, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-01-15',
        'kind', 'income',
        'amount', '10.00',
        'description', 'X',
        'row_fingerprint', v_fp1
      ))
    );
    PERFORM pg_temp.record_result('cross_tenant_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'cross_tenant_denied',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Owner valid income + expense
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.batch_id, r.imported_count, r.transaction_ids
    INTO v_batch, v_imported, v_tx_ids
    FROM public.import_transactions(
      v_company_a, 'stmt.csv', v_sha, 'csv',
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'occurred_on', '2026-01-15',
          'kind', 'income',
          'amount', '12.34',
          'description', 'Accredito stipendio',
          'row_fingerprint', v_fp1
        ),
        jsonb_build_object(
          'source_row', 3,
          'occurred_on', '2026-01-16',
          'kind', 'expense',
          'amount', '5.00',
          'description', 'Pagamento utenza',
          'notes', 'luce',
          'reference', 'REF-1',
          'row_fingerprint', v_fp2
        )
      )
    ) r;

    SELECT count(*) INTO v_count FROM public.transactions WHERE company_id = v_company_a;
    SELECT count(*) INTO v_client_null FROM public.transactions
    WHERE company_id = v_company_a AND client_id IS NULL;
    SELECT count(*) INTO v_cat_null FROM public.transactions
    WHERE company_id = v_company_a AND category_id IS NULL;

    PERFORM pg_temp.record_result(
      'owner_import_income_expense',
      v_imported = 2 AND v_count = 2 AND v_client_null = 2 AND v_cat_null = 2
        AND cardinality(v_tx_ids) = 2,
      NULL, v_imported::text
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_import_income_expense', false, SQLSTATE, SQLERRM);
  END;

  -- Same file reimport blocked
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'stmt-again.csv', v_sha, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-02-01',
        'kind', 'income',
        'amount', '1.00',
        'description', 'Y',
        'row_fingerprint', v_fp3
      ))
    );
    PERFORM pg_temp.record_result('same_file_reimport_blocked', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'same_file_reimport_blocked',
      SQLERRM LIKE '%ATLAS_IMPORT_FILE_ALREADY_IMPORTED%', SQLSTATE, SQLERRM
    );
  END;

  -- Admin can import different file
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.imported_count INTO v_imported
    FROM public.import_transactions(
      v_company_a, 'admin.csv', v_sha2, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-02-02',
        'kind', 'expense',
        'amount', '3.50',
        'description', 'Admin row',
        'row_fingerprint', v_fp3
      ))
    ) r;
    PERFORM pg_temp.record_result('admin_can_import', v_imported = 1, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('admin_can_import', false, SQLSTATE, SQLERRM);
  END;

  -- Manager can import
  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.imported_count INTO v_imported
    FROM public.import_transactions(
      v_company_a, 'mgr.csv', repeat('f', 64), 'xlsx',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-02-03',
        'kind', 'income',
        'amount', '9.99',
        'description', 'Manager row',
        'row_fingerprint', repeat('1', 64)
      ))
    ) r;
    PERFORM pg_temp.record_result('manager_can_import', v_imported = 1, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('manager_can_import', false, SQLSTATE, SQLERRM);
  END;

  -- Zero amount rejected (atomic: no partial)
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT count(*) INTO v_count FROM public.transactions WHERE company_id = v_company_a;
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'bad.csv', repeat('2', 64), 'csv',
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'occurred_on', '2026-03-01',
          'kind', 'income',
          'amount', '1.00',
          'description', 'ok',
          'row_fingerprint', repeat('3', 64)
        ),
        jsonb_build_object(
          'source_row', 3,
          'occurred_on', '2026-03-02',
          'kind', 'income',
          'amount', '0.00',
          'description', 'zero',
          'row_fingerprint', repeat('4', 64)
        )
      )
    );
    PERFORM pg_temp.record_result('zero_amount_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'zero_amount_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_AMOUNT_INVALID%', SQLSTATE, SQLERRM
    );
  END;
  SELECT count(*) INTO v_client_null FROM public.transactions WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'atomic_no_partial_on_invalid',
    v_client_null = v_count, NULL, v_client_null::text || '/' || v_count::text
  );

  -- Empty description rejected
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'empty-desc.csv', repeat('5', 64), 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-03-03',
        'kind', 'income',
        'amount', '1.00',
        'description', '   ',
        'row_fingerprint', repeat('6', 64)
      ))
    );
    PERFORM pg_temp.record_result('empty_description_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'empty_description_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_DESCRIPTION_INVALID%', SQLSTATE, SQLERRM
    );
  END;

  -- Invalid date rejected
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'baddate.csv', repeat('7', 64), 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-13-40',
        'kind', 'income',
        'amount', '1.00',
        'description', 'x',
        'row_fingerprint', repeat('8', 64)
      ))
    );
    PERFORM pg_temp.record_result('invalid_date_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'invalid_date_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_DATE_INVALID%', SQLSTATE, SQLERRM
    );
  END;

  -- Too many rows rejected
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'big.csv', repeat('9', 64), 'csv',
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'source_row', g,
            'occurred_on', '2026-04-01',
            'kind', 'income',
            'amount', '1.00',
            'description', 'r' || g::text,
            'row_fingerprint', md5(g::text || 'pad') || md5(g::text || 'pad2')
          )
        )
        FROM generate_series(1, 501) g
      )
    );
    PERFORM pg_temp.record_result('too_many_rows_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'too_many_rows_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_TOO_MANY_ROWS%', SQLSTATE, SQLERRM
    );
  END;

  -- Duplicate source_row in payload rejected (identity is source_row, not fingerprint)
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'dup.csv', repeat('0', 64), 'csv',
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'occurred_on', '2026-05-01',
          'kind', 'income',
          'amount', '1.00',
          'description', 'A',
          'row_fingerprint', repeat('ab', 32)
        ),
        jsonb_build_object(
          'source_row', 2,
          'occurred_on', '2026-05-02',
          'kind', 'expense',
          'amount', '2.00',
          'description', 'B',
          'row_fingerprint', repeat('cd', 32)
        )
      )
    );
    PERFORM pg_temp.record_result('duplicate_source_row_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'duplicate_source_row_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_DUPLICATE_SOURCE_ROW%', SQLSTATE, SQLERRM
    );
  END;

  -- Two legitimate identical-content rows (same fingerprint, distinct source_row) allowed
  BEGIN
    SELECT r.imported_count INTO v_imported
    FROM public.import_transactions(
      v_company_a, 'twins.csv', repeat('ef', 32), 'csv',
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'occurred_on', '2026-06-01',
          'kind', 'expense',
          'amount', '7.00',
          'description', 'Stesso caffe',
          'row_fingerprint', repeat('aa', 32)
        ),
        jsonb_build_object(
          'source_row', 3,
          'occurred_on', '2026-06-01',
          'kind', 'expense',
          'amount', '7.00',
          'description', 'Stesso caffe',
          'row_fingerprint', repeat('aa', 32)
        )
      )
    ) r;
    PERFORM pg_temp.record_result(
      'legitimate_identical_rows_allowed',
      v_imported = 2, NULL, v_imported::text
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'legitimate_identical_rows_allowed', false, SQLSTATE, SQLERRM
    );
  END;

  -- Same file SHA in a different company is allowed (company-scoped)
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.imported_count INTO v_imported
    FROM public.import_transactions(
      v_company_b, 'stmt.csv', v_sha, 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-06-10',
        'kind', 'income',
        'amount', '4.00',
        'description', 'Other company',
        'row_fingerprint', repeat('bb', 32)
      ))
    ) r;
    PERFORM pg_temp.record_result(
      'same_file_sha_different_company_allowed',
      v_imported = 1, NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'same_file_sha_different_company_allowed', false, SQLSTATE, SQLERRM
    );
  END;

  -- Provenance linked (as company A member — not outsider from prior check)
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT count(*) INTO v_count
  FROM public.transaction_import_items i
  JOIN public.transaction_import_batches b ON b.id = i.batch_id
  WHERE b.company_id = v_company_a;
  PERFORM pg_temp.record_result('provenance_items_linked', v_count >= 2, NULL, v_count::text);

  -- Isolation: outsider cannot see company A batches via RLS
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  SELECT count(*) INTO v_count
  FROM public.transaction_import_batches WHERE company_id = v_company_a;
  PERFORM pg_temp.record_result('batch_rls_cross_tenant', v_count = 0, NULL, v_count::text);

  -- Direct grants: authenticated has SELECT only (no insert)
  RESET ROLE;
  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'transaction_import_batches'
    AND grantee = 'authenticated'
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
  PERFORM pg_temp.record_result('batch_no_write_grants', v_count = 0, NULL, v_count::text);

  SELECT count(*) INTO v_count
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'transaction_import_batches'
    AND grantee IN ('anon', 'PUBLIC');
  PERFORM pg_temp.record_result('batch_no_anon_grants', v_count = 0, NULL, v_count::text);

  -- Malformed payload with company_id rejected
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.import_transactions(
      v_company_a, 'spoof.csv', repeat('cd', 32), 'csv',
      jsonb_build_array(jsonb_build_object(
        'source_row', 2,
        'occurred_on', '2026-07-01',
        'kind', 'income',
        'amount', '1.00',
        'description', 'x',
        'company_id', v_company_b::text,
        'row_fingerprint', repeat('33', 32)
      ))
    );
    PERFORM pg_temp.record_result('company_id_spoof_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'company_id_spoof_rejected',
      SQLERRM LIKE '%ATLAS_IMPORT_PAYLOAD_INVALID%', SQLSTATE, SQLERRM
    );
  END;

  RESET ROLE;
END;
$body$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

ROLLBACK;
