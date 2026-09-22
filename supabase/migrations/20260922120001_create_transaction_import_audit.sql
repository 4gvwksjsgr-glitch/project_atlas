-- =============================================================================
-- Project Atlas — Working Step 16: transaction import audit/provenance schema
-- Additive. No raw file bytes. No bank credentials.
-- =============================================================================

CREATE TABLE public.transaction_import_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES public.profiles (id),
  source_file_name TEXT NOT NULL,
  source_file_sha256 TEXT NOT NULL,
  source_format TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  total_rows INTEGER NOT NULL,
  imported_rows INTEGER NOT NULL,
  skipped_invalid_rows INTEGER NOT NULL DEFAULT 0,
  skipped_duplicate_rows INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT transaction_import_batches_file_name_not_empty
    CHECK (char_length(btrim(source_file_name)) > 0),
  CONSTRAINT transaction_import_batches_file_name_length
    CHECK (char_length(source_file_name) <= 255),
  CONSTRAINT transaction_import_batches_sha256_shape
    CHECK (source_file_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT transaction_import_batches_format_allowed
    CHECK (source_format IN ('csv', 'xlsx')),
  CONSTRAINT transaction_import_batches_counts_nonnegative
    CHECK (
      total_rows >= 0
      AND imported_rows >= 0
      AND skipped_invalid_rows >= 0
      AND skipped_duplicate_rows >= 0
    ),
  CONSTRAINT transaction_import_batches_imported_lte_total
    CHECK (imported_rows <= total_rows)
);

COMMENT ON TABLE public.transaction_import_batches IS
  'Audit batches for manual CSV/XLSX transaction imports. Stores file SHA-256 fingerprint only — never raw bytes.';

CREATE UNIQUE INDEX transaction_import_batches_company_file_sha_uidx
  ON public.transaction_import_batches (company_id, source_file_sha256);

CREATE INDEX transaction_import_batches_company_created_idx
  ON public.transaction_import_batches (company_id, created_at DESC);

CREATE TABLE public.transaction_import_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id UUID NOT NULL
    REFERENCES public.transaction_import_batches (id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  transaction_id UUID NOT NULL,
  source_row INTEGER NOT NULL,
  row_fingerprint TEXT NOT NULL,
  reference_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT transaction_import_items_source_row_positive
    CHECK (source_row > 0),
  CONSTRAINT transaction_import_items_fingerprint_shape
    CHECK (row_fingerprint ~ '^[0-9a-f]{64}$'),
  CONSTRAINT transaction_import_items_reference_length
    CHECK (reference_text IS NULL OR char_length(reference_text) <= 200),
  CONSTRAINT transaction_import_items_transaction_fk
    FOREIGN KEY (company_id, transaction_id)
    REFERENCES public.transactions (company_id, id)
    ON DELETE CASCADE
);

COMMENT ON TABLE public.transaction_import_items IS
  'Per-row provenance linking an imported transaction to its import batch.';

CREATE UNIQUE INDEX transaction_import_items_batch_source_row_uidx
  ON public.transaction_import_items (batch_id, source_row);

-- Fingerprint is non-unique metadata: two legitimate identical-content rows
-- in the same batch may share the same fingerprint (distinct source_row).
CREATE INDEX transaction_import_items_batch_row_fp_idx
  ON public.transaction_import_items (batch_id, row_fingerprint);

CREATE INDEX transaction_import_items_company_idx
  ON public.transaction_import_items (company_id);

CREATE INDEX transaction_import_items_transaction_idx
  ON public.transaction_import_items (company_id, transaction_id);

ALTER TABLE public.transaction_import_batches OWNER TO postgres;
ALTER TABLE public.transaction_import_items OWNER TO postgres;

ALTER TABLE public.transaction_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_import_batches FORCE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_import_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_import_items FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.transaction_import_batches FROM PUBLIC;
REVOKE ALL ON TABLE public.transaction_import_batches FROM anon;
REVOKE ALL ON TABLE public.transaction_import_batches FROM authenticated;

REVOKE ALL ON TABLE public.transaction_import_items FROM PUBLIC;
REVOKE ALL ON TABLE public.transaction_import_items FROM anon;
REVOKE ALL ON TABLE public.transaction_import_items FROM authenticated;

-- Members may read their company's import audit history (no write policies:
-- inserts happen only via SECURITY DEFINER RPC).
CREATE POLICY transaction_import_batches_select_member
  ON public.transaction_import_batches
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

CREATE POLICY transaction_import_items_select_member
  ON public.transaction_import_items
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

GRANT SELECT ON TABLE public.transaction_import_batches TO authenticated;
GRANT SELECT ON TABLE public.transaction_import_items TO authenticated;
