-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 10A behavioral checks for public.import_customers
--
-- Utilizzo previsto: Supabase locale isolato dopo `supabase db reset`.
-- Non eseguire su database remoto / di sviluppo condiviso.
-- Deduplicazione: best effort dello Step 10A (non garanzia database).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_inserted BIGINT;
  v_skipped BIGINT;
  v_rows INTEGER[];
  v_count_before BIGINT;
  v_count_after BIGINT;
  v_err TEXT;
  v_sqlstate TEXT;
BEGIN
  -- Seed auth.users (minimal) and memberships as needed by local schema.
  -- If auth.users insert shape differs, this script fails loudly on local reset.

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  )
  VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner10a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin10a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager10a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_employee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'employee10a@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug)
  VALUES
    (v_company_a, 'Company A 10A', 'company-a-10a'),
    (v_company_b, 'Company B 10A', 'company-b-10a');

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee'),
    (v_company_b, v_owner, 'owner');

  -- ---------- helpers ----------
  -- not_authenticated
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"X"}]'::jsonb
    );
    RAISE EXCEPTION 'expected not_authenticated';
  EXCEPTION WHEN SQLSTATE '28000' THEN
    NULL;
  END;

  -- company_id_null
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM public.import_customers(NULL, '[{"source_row":2,"name":"X"}]'::jsonb);
    RAISE EXCEPTION 'expected company_id_null';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- payload_null
  BEGIN
    PERFORM public.import_customers(v_company_a, NULL);
    RAISE EXCEPTION 'expected payload_null';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- payload_not_array
  BEGIN
    PERFORM public.import_customers(v_company_a, '{"a":1}'::jsonb);
    RAISE EXCEPTION 'expected payload_not_array';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- empty_array
  BEGIN
    PERFORM public.import_customers(v_company_a, '[]'::jsonb);
    RAISE EXCEPTION 'expected empty_array';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- more_than_500
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      (
        SELECT jsonb_agg(
          jsonb_build_object('source_row', g + 1, 'name', 'N' || g)
        )
        FROM generate_series(1, 501) g
      )
    );
    RAISE EXCEPTION 'expected more_than_500';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- employee_rejected
  BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"Emp"}]'::jsonb
    );
    RAISE EXCEPTION 'expected employee_rejected';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  -- owner_authorized / admin_authorized / manager_authorized
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  SELECT inserted_count, skipped_duplicate_count, skipped_source_rows
    INTO v_inserted, v_skipped, v_rows
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"Owner Row"}]'::jsonb
  );
  IF v_inserted <> 1 THEN
    RAISE EXCEPTION 'owner_authorized failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  SELECT inserted_count INTO v_inserted
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"Admin Row"}]'::jsonb
  );
  IF v_inserted <> 1 THEN
    RAISE EXCEPTION 'admin_authorized failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  SELECT inserted_count INTO v_inserted
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"Manager Row"}]'::jsonb
  );
  IF v_inserted <> 1 THEN
    RAISE EXCEPTION 'manager_authorized failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);

  -- element_not_object
  BEGIN
    PERFORM public.import_customers(v_company_a, '[1]'::jsonb);
    RAISE EXCEPTION 'expected element_not_object';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- source_row_missing
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"name":"NoRow"}]'::jsonb
    );
    RAISE EXCEPTION 'expected source_row_missing';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- source_row_string
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":"2","name":"S"}]'::jsonb
    );
    RAISE EXCEPTION 'expected source_row_string';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- source_row_decimal (must NOT truncate 2.7 -> 2)
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2.7,"name":"Dec"}]'::jsonb
    );
    RAISE EXCEPTION 'expected source_row_decimal';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- source_row_non_positive
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":0,"name":"Z"}]'::jsonb
    );
    RAISE EXCEPTION 'expected source_row_non_positive';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- source_row_duplicate (explicit RAISE before temp PK)
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"A"},{"source_row":2,"name":"B"}]'::jsonb
    );
    RAISE EXCEPTION 'expected source_row_duplicate';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF position('duplicate source_row' in v_err) = 0 THEN
      RAISE EXCEPTION 'source_row_duplicate message missing';
    END IF;
  END;

  -- name_missing
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2}]'::jsonb
    );
    RAISE EXCEPTION 'expected name_missing';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- name_blank
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"   "}]'::jsonb
    );
    RAISE EXCEPTION 'expected name_blank';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- email_wrong_type / phone_wrong_type / notes_wrong_type
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"T","email":1}]'::jsonb
    );
    RAISE EXCEPTION 'expected email_wrong_type';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"T","phone":true}]'::jsonb
    );
    RAISE EXCEPTION 'expected phone_wrong_type';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"T","notes":[]}]'::jsonb
    );
    RAISE EXCEPTION 'expected notes_wrong_type';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- length_limits
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'name', repeat('n', 201)
        )
      )
    );
    RAISE EXCEPTION 'expected length_limits';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- company_id_in_payload
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      jsonb_build_array(
        jsonb_build_object(
          'source_row', 2,
          'name', 'X',
          'company_id', v_company_b
        )
      )
    );
    RAISE EXCEPTION 'expected company_id_in_payload';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- unknown_key
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"X","vat":"1"}]'::jsonb
    );
    RAISE EXCEPTION 'expected unknown_key';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- atomic_failure: no partial inserts
  SELECT count(*) INTO v_count_before FROM public.clients WHERE company_id = v_company_a;
  BEGIN
    PERFORM public.import_customers(
      v_company_a,
      '[{"source_row":2,"name":"Ok"},{"source_row":3,"name":""}]'::jsonb
    );
    RAISE EXCEPTION 'expected atomic_failure';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    SELECT count(*) INTO v_count_after FROM public.clients WHERE company_id = v_company_a;
    IF v_count_after <> v_count_before THEN
      RAISE EXCEPTION 'atomic_failure leaked rows';
    END IF;
  END;

  -- company_id_from_param + tenant_isolation + email_other_tenant_ok
  PERFORM public.import_customers(
    v_company_b,
    '[{"source_row":2,"name":"B Only","email":"shared@example.test"}]'::jsonb
  );

  SELECT inserted_count, skipped_duplicate_count INTO v_inserted, v_skipped
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"A Shared","email":"shared@example.test"}]'::jsonb
  );
  IF v_inserted <> 1 OR v_skipped <> 0 THEN
    RAISE EXCEPTION 'email_other_tenant_ok failed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.clients
    WHERE company_id = v_company_a AND name = 'B Only'
  ) THEN
    RAISE EXCEPTION 'tenant_isolation / company_id_from_param failed';
  END IF;

  -- duplicate_email_payload (best effort dello Step 10A)
  SELECT inserted_count, skipped_duplicate_count, skipped_source_rows
    INTO v_inserted, v_skipped, v_rows
  FROM public.import_customers(
    v_company_a,
    '[
      {"source_row":2,"name":"First","email":"Dup@Example.TEST"},
      {"source_row":3,"name":"Second","email":"dup@example.test"}
    ]'::jsonb
  );
  IF v_inserted <> 1 OR v_skipped <> 1 OR v_rows <> ARRAY[3] THEN
    RAISE EXCEPTION 'duplicate_email_payload failed';
  END IF;

  -- duplicate_email_tenant
  SELECT inserted_count, skipped_duplicate_count, skipped_source_rows
    INTO v_inserted, v_skipped, v_rows
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"Again","email":"dup@example.test"}]'::jsonb
  );
  IF v_inserted <> 0 OR v_skipped <> 1 OR v_rows <> ARRAY[2] THEN
    RAISE EXCEPTION 'duplicate_email_tenant failed';
  END IF;

  -- rows_without_email
  SELECT inserted_count INTO v_inserted
  FROM public.import_customers(
    v_company_a,
    '[
      {"source_row":2,"name":"NoMail1"},
      {"source_row":3,"name":"NoMail2"}
    ]'::jsonb
  );
  IF v_inserted <> 2 THEN
    RAISE EXCEPTION 'rows_without_email failed';
  END IF;

  -- result_no_pii / counts_coherent
  SELECT inserted_count, skipped_duplicate_count, skipped_source_rows
    INTO v_inserted, v_skipped, v_rows
  FROM public.import_customers(
    v_company_a,
    '[{"source_row":2,"name":"CountMe","email":"countme@example.test"}]'::jsonb
  );
  IF v_inserted <> 1 OR v_skipped <> 0 THEN
    RAISE EXCEPTION 'counts_coherent failed';
  END IF;
  -- result columns are only counts + source_row ids (no name/email/phone/notes)
  IF to_jsonb(v_rows)::text ILIKE '%countme%' THEN
    RAISE EXCEPTION 'result_no_pii failed';
  END IF;

  -- advisory_lock present in function body (runtime lock held for xact)
  IF position('pg_advisory_xact_lock' in pg_get_functiondef('public.import_customers(uuid,jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'advisory_lock missing';
  END IF;

  RAISE NOTICE 'IMPORT_CUSTOMERS_BEHAVIOR_OK';
END $$;
