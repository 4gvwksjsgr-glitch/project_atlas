-- =============================================================================
-- Project Atlas — Step 10A: RPC importazione clienti (CSV/XLSX client-side)
-- Migration additiva: non modifica migration già applicate.
--
-- Deduplicazione email (trim + lowercase): best effort dello Step 10A.
-- Conserva la prima email nel payload; esclude successive e quelle già
-- presenti nello stesso tenant; righe senza email restano importabili;
-- nessun UPDATE. Non è garanzia database: non esiste indice univoco su
-- (company_id, email); il CRUD manuale non usa l'advisory lock; una
-- scrittura concorrente esterna alla RPC può creare un duplicato.
-- Un indice univoco sarà valutato nello Step 10B.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.import_customers(
  p_company_id UUID,
  p_rows JSONB
)
RETURNS TABLE (
  inserted_count BIGINT,
  skipped_duplicate_count BIGINT,
  skipped_source_rows INTEGER[]
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_row_count INTEGER;
  v_elem JSONB;
  v_key TEXT;
  v_source_row_raw TEXT;
  v_source_row_num NUMERIC;
  v_source_row INTEGER;
  v_name TEXT;
  v_email TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_inserted BIGINT := 0;
  v_skipped_rows INTEGER[] := ARRAY[]::INTEGER[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'rows must be a JSON array'
      USING ERRCODE = '22023';
  END IF;

  v_row_count := jsonb_array_length(p_rows);
  IF v_row_count < 1 OR v_row_count > 500 THEN
    RAISE EXCEPTION 'rows count must be between 1 and 500'
      USING ERRCODE = '22023';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner', 'admin', 'manager']::public.company_role[],
    auth.uid()
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions'
      USING ERRCODE = '42501';
  END IF;

  -- Lock transazionale limitato all'azienda (evita import concorrenti sullo stesso tenant).
  PERFORM pg_advisory_xact_lock(hashtextextended(p_company_id::text, 0));

  CREATE TEMP TABLE tmp_import_customers (
    source_row INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    email_norm TEXT
  ) ON COMMIT DROP;

  FOR v_elem IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    IF jsonb_typeof(v_elem) <> 'object' THEN
      RAISE EXCEPTION 'each row must be a JSON object'
        USING ERRCODE = '22023';
    END IF;

    IF v_elem ? 'company_id' THEN
      RAISE EXCEPTION 'company_id must not be present in row payload'
        USING ERRCODE = '22023';
    END IF;

    FOR v_key IN SELECT jsonb_object_keys(v_elem)
    LOOP
      IF v_key NOT IN ('source_row', 'name', 'email', 'phone', 'notes') THEN
        RAISE EXCEPTION 'unexpected field in row payload'
          USING ERRCODE = '22023';
      END IF;
    END LOOP;

    IF NOT (v_elem ? 'source_row') THEN
      RAISE EXCEPTION 'source_row is required'
        USING ERRCODE = '22023';
    END IF;

    IF NOT (v_elem ? 'name') THEN
      RAISE EXCEPTION 'name is required'
        USING ERRCODE = '22023';
    END IF;

    -- Validazione intera di source_row PRIMA di qualsiasi cast a INTEGER.
    -- Non affidarsi al cast PostgreSQL (troncherebbe 2.7 -> 2).
    IF jsonb_typeof(v_elem->'source_row') <> 'number' THEN
      RAISE EXCEPTION 'source_row must be a JSON number'
        USING ERRCODE = '22023';
    END IF;

    v_source_row_raw := v_elem->>'source_row';
    IF v_source_row_raw IS NULL OR v_source_row_raw = '' THEN
      RAISE EXCEPTION 'source_row is required'
        USING ERRCODE = '22023';
    END IF;

    -- Solo cifre intere non negative in forma decimale semplice (niente 2.7, 1e2, +2).
    IF v_source_row_raw !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'source_row must be a positive integer'
        USING ERRCODE = '22023';
    END IF;

    v_source_row_num := (v_elem->'source_row')::TEXT::NUMERIC;
    IF trunc(v_source_row_num) <> v_source_row_num THEN
      RAISE EXCEPTION 'source_row must be a positive integer'
        USING ERRCODE = '22023';
    END IF;

    IF v_source_row_num <= 0 OR v_source_row_num > 2147483647 THEN
      RAISE EXCEPTION 'source_row out of range'
        USING ERRCODE = '22023';
    END IF;

    v_source_row := v_source_row_num::INTEGER;

    IF EXISTS (
      SELECT 1
      FROM tmp_import_customers t
      WHERE t.source_row = v_source_row
    ) THEN
      RAISE EXCEPTION 'duplicate source_row in payload'
        USING ERRCODE = '22023';
    END IF;

    IF jsonb_typeof(v_elem->'name') <> 'string' THEN
      RAISE EXCEPTION 'name must be a string'
        USING ERRCODE = '22023';
    END IF;

    v_name := btrim(v_elem->>'name');
    IF v_name = '' OR char_length(v_name) > 200 THEN
      RAISE EXCEPTION 'invalid name'
        USING ERRCODE = '22023';
    END IF;

    IF v_elem ? 'email' AND jsonb_typeof(v_elem->'email') <> 'null' THEN
      IF jsonb_typeof(v_elem->'email') <> 'string' THEN
        RAISE EXCEPTION 'email must be a string or null'
          USING ERRCODE = '22023';
      END IF;
      v_email := nullif(btrim(v_elem->>'email'), '');
      IF v_email IS NOT NULL AND char_length(v_email) > 254 THEN
        RAISE EXCEPTION 'email too long'
          USING ERRCODE = '22023';
      END IF;
    ELSE
      v_email := NULL;
    END IF;

    IF v_elem ? 'phone' AND jsonb_typeof(v_elem->'phone') <> 'null' THEN
      IF jsonb_typeof(v_elem->'phone') <> 'string' THEN
        RAISE EXCEPTION 'phone must be a string or null'
          USING ERRCODE = '22023';
      END IF;
      v_phone := nullif(btrim(v_elem->>'phone'), '');
      IF v_phone IS NOT NULL AND char_length(v_phone) > 40 THEN
        RAISE EXCEPTION 'phone too long'
          USING ERRCODE = '22023';
      END IF;
    ELSE
      v_phone := NULL;
    END IF;

    IF v_elem ? 'notes' AND jsonb_typeof(v_elem->'notes') <> 'null' THEN
      IF jsonb_typeof(v_elem->'notes') <> 'string' THEN
        RAISE EXCEPTION 'notes must be a string or null'
          USING ERRCODE = '22023';
      END IF;
      v_notes := nullif(btrim(v_elem->>'notes'), '');
      IF v_notes IS NOT NULL AND char_length(v_notes) > 2000 THEN
        RAISE EXCEPTION 'notes too long'
          USING ERRCODE = '22023';
      END IF;
    ELSE
      v_notes := NULL;
    END IF;

    INSERT INTO tmp_import_customers (source_row, name, email, phone, notes, email_norm)
    VALUES (
      v_source_row,
      v_name,
      CASE WHEN v_email IS NULL THEN NULL ELSE lower(v_email) END,
      v_phone,
      v_notes,
      CASE WHEN v_email IS NULL THEN NULL ELSE lower(v_email) END
    );
  END LOOP;

  -- Deduplicazione best effort dello Step 10A (vedi commento in testa migration).
  -- Duplicati email nel payload: conserva la prima source_row, escludi le successive.
  WITH ranked AS (
    SELECT
      source_row,
      ROW_NUMBER() OVER (
        PARTITION BY email_norm
        ORDER BY source_row
      ) AS rn
    FROM tmp_import_customers
    WHERE email_norm IS NOT NULL
  ),
  removed AS (
    DELETE FROM tmp_import_customers t
    USING ranked r
    WHERE t.source_row = r.source_row
      AND r.rn > 1
    RETURNING t.source_row
  )
  SELECT coalesce(array_agg(source_row ORDER BY source_row), ARRAY[]::INTEGER[])
    INTO v_skipped_rows
  FROM removed;

  -- Duplicati email già presenti nel tenant (best effort; senza unique index).
  WITH existing AS (
    SELECT t.source_row
    FROM tmp_import_customers t
    WHERE t.email_norm IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.clients c
        WHERE c.company_id = p_company_id
          AND c.email IS NOT NULL
          AND lower(btrim(c.email)) = t.email_norm
      )
  ),
  removed AS (
    DELETE FROM tmp_import_customers t
    USING existing e
    WHERE t.source_row = e.source_row
    RETURNING t.source_row
  )
  SELECT
    coalesce(v_skipped_rows, ARRAY[]::INTEGER[])
      || coalesce(
        (SELECT array_agg(source_row ORDER BY source_row) FROM removed),
        ARRAY[]::INTEGER[]
      )
    INTO v_skipped_rows;

  -- Unico INSERT su public.clients: tutta la validazione termina prima.
  INSERT INTO public.clients (company_id, name, email, phone, notes)
  SELECT
    p_company_id,
    t.name,
    t.email,
    t.phone,
    t.notes
  FROM tmp_import_customers t
  ORDER BY t.source_row;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  inserted_count := v_inserted;
  skipped_duplicate_count := coalesce(cardinality(v_skipped_rows), 0)::BIGINT;
  skipped_source_rows := coalesce(v_skipped_rows, ARRAY[]::INTEGER[]);
  RETURN NEXT;
END;
$$;

REVOKE ALL
ON FUNCTION public.import_customers(UUID, JSONB)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.import_customers(UUID, JSONB)
FROM anon;

REVOKE ALL
ON FUNCTION public.import_customers(UUID, JSONB)
FROM authenticated;

GRANT EXECUTE
ON FUNCTION public.import_customers(UUID, JSONB)
TO authenticated;
