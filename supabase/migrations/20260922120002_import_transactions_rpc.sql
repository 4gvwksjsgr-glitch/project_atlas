-- =============================================================================
-- Project Atlas — Working Step 16: import_transactions SECURITY DEFINER RPC
-- Atomic batch + transactions + provenance. auth.uid() is the only actor.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.import_transactions(
  p_company_id UUID,
  p_source_file_name TEXT,
  p_source_file_sha256 TEXT,
  p_source_format TEXT,
  p_rows JSONB
)
RETURNS TABLE (
  batch_id UUID,
  imported_count BIGINT,
  skipped_invalid_count BIGINT,
  skipped_duplicate_count BIGINT,
  transaction_ids UUID[]
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_file_name TEXT;
  v_sha TEXT;
  v_format TEXT;
  v_row_count INTEGER;
  v_elem JSONB;
  v_key TEXT;
  v_source_row_raw TEXT;
  v_source_row_num NUMERIC;
  v_source_row INTEGER;
  v_occurred_on DATE;
  v_kind public.transaction_kind;
  v_amount NUMERIC(14, 2);
  v_description TEXT;
  v_notes TEXT;
  v_reference TEXT;
  v_row_fp TEXT;
  v_batch_id UUID;
  v_tx_id UUID;
  v_imported BIGINT := 0;
  v_skipped_invalid INTEGER := 0;
  v_skipped_duplicate INTEGER := 0;
  v_tx_ids UUID[] := ARRAY[]::UUID[];
  v_rec RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  v_file_name := nullif(btrim(p_source_file_name), '');
  IF v_file_name IS NULL OR char_length(v_file_name) > 255 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_FILE_NAME_INVALID';
  END IF;

  v_sha := lower(nullif(btrim(p_source_file_sha256), ''));
  IF v_sha IS NULL OR v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_FILE_HASH_INVALID';
  END IF;

  v_format := lower(nullif(btrim(p_source_format), ''));
  IF v_format IS NULL OR v_format NOT IN ('csv', 'xlsx') THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_FORMAT_INVALID';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
  END IF;

  v_row_count := jsonb_array_length(p_rows);
  IF v_row_count < 1 OR v_row_count > 500 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_TOO_MANY_ROWS';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner', 'admin', 'manager']::public.company_role[],
    v_uid
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INSUFFICIENT_PRIVILEGES';
  END IF;

  -- Serialize imports per company; also gates same-file reimport check.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_company_id::text || ':txn_import', 0));

  IF EXISTS (
    SELECT 1
    FROM public.transaction_import_batches b
    WHERE b.company_id = p_company_id
      AND b.source_file_sha256 = v_sha
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_IMPORT_FILE_ALREADY_IMPORTED';
  END IF;

  -- Temp table may already exist if this call shares an outer transaction
  -- with a prior import attempt in the same session (e.g. SQL test harness).
  DROP TABLE IF EXISTS tmp_import_transactions;

  CREATE TEMP TABLE tmp_import_transactions (
    source_row INTEGER PRIMARY KEY,
    occurred_on DATE NOT NULL,
    kind public.transaction_kind NOT NULL,
    amount NUMERIC(14, 2) NOT NULL,
    description TEXT NOT NULL,
    notes TEXT,
    reference_text TEXT,
    row_fingerprint TEXT NOT NULL
  ) ON COMMIT DROP;

  -- Fingerprint is provenance/metadata only: identical bank rows may share it.
  -- Distinct identity within a payload/batch is source_row (PRIMARY KEY).
  CREATE INDEX tmp_import_transactions_row_fp_idx
    ON tmp_import_transactions (row_fingerprint);

  FOR v_elem IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    IF jsonb_typeof(v_elem) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;

    IF v_elem ? 'company_id' OR v_elem ? 'id' OR v_elem ? 'transaction_id' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(v_elem)
    LOOP
      IF v_key NOT IN (
        'source_row',
        'occurred_on',
        'kind',
        'amount',
        'description',
        'notes',
        'reference',
        'row_fingerprint'
      ) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
      END IF;
    END LOOP;

    IF NOT (v_elem ? 'source_row')
       OR NOT (v_elem ? 'occurred_on')
       OR NOT (v_elem ? 'kind')
       OR NOT (v_elem ? 'amount')
       OR NOT (v_elem ? 'description')
       OR NOT (v_elem ? 'row_fingerprint') THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;

    IF jsonb_typeof(v_elem->'source_row') <> 'number' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;

    v_source_row_raw := v_elem->>'source_row';
    IF v_source_row_raw IS NULL OR v_source_row_raw !~ '^[0-9]+$' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;

    v_source_row_num := (v_elem->'source_row')::TEXT::NUMERIC;
    IF trunc(v_source_row_num) <> v_source_row_num
       OR v_source_row_num <= 0
       OR v_source_row_num > 2147483647 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_PAYLOAD_INVALID';
    END IF;
    v_source_row := v_source_row_num::INTEGER;

    BEGIN
      v_occurred_on := (v_elem->>'occurred_on')::DATE;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_DATE_INVALID';
    END;

    IF (v_elem->>'occurred_on') IS DISTINCT FROM to_char(v_occurred_on, 'YYYY-MM-DD') THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_DATE_INVALID';
    END IF;

    BEGIN
      v_kind := (v_elem->>'kind')::public.transaction_kind;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_KIND_INVALID';
    END;

    BEGIN
      v_amount := (v_elem->>'amount')::NUMERIC(14, 2);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_AMOUNT_INVALID';
    END;

    IF v_amount IS NULL OR v_amount <= 0 OR v_amount <> trunc(v_amount, 2) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_AMOUNT_INVALID';
    END IF;

    v_description := nullif(btrim(v_elem->>'description'), '');
    IF v_description IS NULL OR char_length(v_description) > 500 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_DESCRIPTION_INVALID';
    END IF;

    v_notes := nullif(btrim(v_elem->>'notes'), '');
    IF v_notes IS NOT NULL AND char_length(v_notes) > 2000 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_NOTES_INVALID';
    END IF;

    v_reference := nullif(btrim(v_elem->>'reference'), '');
    IF v_reference IS NOT NULL AND char_length(v_reference) > 200 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_REFERENCE_INVALID';
    END IF;

    v_row_fp := lower(nullif(btrim(v_elem->>'row_fingerprint'), ''));
    IF v_row_fp IS NULL OR v_row_fp !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IMPORT_ROW_FINGERPRINT_INVALID';
    END IF;

    BEGIN
      INSERT INTO tmp_import_transactions (
        source_row,
        occurred_on,
        kind,
        amount,
        description,
        notes,
        reference_text,
        row_fingerprint
      ) VALUES (
        v_source_row,
        v_occurred_on,
        v_kind,
        v_amount,
        v_description,
        v_notes,
        v_reference,
        v_row_fp
      );
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_IMPORT_DUPLICATE_SOURCE_ROW';
    END;
  END LOOP;

  INSERT INTO public.transaction_import_batches (
    company_id,
    created_by,
    source_file_name,
    source_file_sha256,
    source_format,
    total_rows,
    imported_rows,
    skipped_invalid_rows,
    skipped_duplicate_rows
  ) VALUES (
    p_company_id,
    v_uid,
    v_file_name,
    v_sha,
    v_format,
    v_row_count,
    0,
    v_skipped_invalid,
    v_skipped_duplicate
  )
  RETURNING id INTO v_batch_id;

  FOR v_rec IN
    SELECT *
    FROM tmp_import_transactions t
    ORDER BY t.source_row
  LOOP
    INSERT INTO public.transactions (
      company_id,
      client_id,
      category_id,
      kind,
      amount,
      occurred_on,
      description,
      notes
    ) VALUES (
      p_company_id,
      NULL,
      NULL,
      v_rec.kind,
      v_rec.amount,
      v_rec.occurred_on,
      v_rec.description,
      v_rec.notes
    )
    RETURNING id INTO v_tx_id;

    INSERT INTO public.transaction_import_items (
      batch_id,
      company_id,
      transaction_id,
      source_row,
      row_fingerprint,
      reference_text
    ) VALUES (
      v_batch_id,
      p_company_id,
      v_tx_id,
      v_rec.source_row,
      v_rec.row_fingerprint,
      v_rec.reference_text
    );

    v_imported := v_imported + 1;
    v_tx_ids := array_append(v_tx_ids, v_tx_id);
  END LOOP;

  UPDATE public.transaction_import_batches b
  SET imported_rows = v_imported::INTEGER
  WHERE b.id = v_batch_id;

  RETURN QUERY
  SELECT
    v_batch_id,
    v_imported,
    v_skipped_invalid::BIGINT,
    v_skipped_duplicate::BIGINT,
    v_tx_ids;
END;
$$;

ALTER FUNCTION public.import_transactions(UUID, TEXT, TEXT, TEXT, JSONB) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.import_transactions(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.import_transactions(UUID, TEXT, TEXT, TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.import_transactions(UUID, TEXT, TEXT, TEXT, JSONB) TO authenticated;
