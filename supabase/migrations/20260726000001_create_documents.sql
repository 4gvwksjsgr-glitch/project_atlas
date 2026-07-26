-- =============================================================================
-- Project Atlas — Step 13A: Documenti operativi (public.documents)
-- Migration additiva: non modifica migration già applicate.
-- Nessun collegamento a clienti/movimenti; senza stato di upload; senza colonna bucket.
-- =============================================================================

CREATE TABLE public.documents (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID NOT NULL
    REFERENCES public.companies(id) ON DELETE CASCADE,
  uploaded_by         UUID DEFAULT auth.uid()
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  title               TEXT NOT NULL,
  original_file_name  TEXT NOT NULL,
  storage_path        TEXT NOT NULL,
  mime_type           TEXT NOT NULL,
  size_bytes          BIGINT NOT NULL,
  is_archived         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT documents_title_trimmed
    CHECK (title = btrim(title)),
  CONSTRAINT documents_title_not_empty
    CHECK (char_length(btrim(title)) > 0),
  CONSTRAINT documents_title_max_len
    CHECK (char_length(title) <= 160),
  CONSTRAINT documents_original_file_name_trimmed
    CHECK (original_file_name = btrim(original_file_name)),
  CONSTRAINT documents_original_file_name_not_empty
    CHECK (char_length(btrim(original_file_name)) > 0),
  CONSTRAINT documents_original_file_name_max_len
    CHECK (char_length(original_file_name) <= 255),
  CONSTRAINT documents_mime_type_allowed
    CHECK (mime_type IN (
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    )),
  CONSTRAINT documents_size_bytes_positive
    CHECK (size_bytes > 0),
  CONSTRAINT documents_size_bytes_max
    CHECK (size_bytes <= 6291456),
  -- Path canonico esatto: {company_id}/{document_id}/{object_uuid}.{pdf|jpg|png|webp}
  -- UUID lowercase (rappresentazione ::text di PostgreSQL); allineato alle policy Storage.
  CONSTRAINT documents_storage_path_matches_ids
    CHECK (
      storage_path ~
        (
          '^'
          || company_id::text
          || '/'
          || id::text
          || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
          || '\.(pdf|jpg|png|webp)$'
        )
    ),
  CONSTRAINT documents_storage_path_unique
    UNIQUE (storage_path)
);

COMMENT ON TABLE public.documents IS
  'Documenti operativi aziendali (non fiscali); file in bucket privato company-documents';

CREATE INDEX idx_documents_company_created_at
  ON public.documents (company_id, created_at DESC);

CREATE INDEX idx_documents_company_created_at_active
  ON public.documents (company_id, created_at DESC)
  WHERE is_archived = FALSE;

CREATE TRIGGER set_documents_updated_at
  BEFORE UPDATE ON public.documents
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Immutabilità company_id dopo creazione
-- -----------------------------------------------------------------------------
CREATE FUNCTION private.enforce_documents_company_id_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'company_id cannot be changed'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_documents_company_id_immutable()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.enforce_documents_company_id_immutable()
  FROM anon;
REVOKE ALL ON FUNCTION private.enforce_documents_company_id_immutable()
  FROM authenticated;

CREATE TRIGGER trg_documents_company_id_immutable
  BEFORE UPDATE ON public.documents
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_documents_company_id_immutable();

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents FORCE ROW LEVEL SECURITY;

CREATE POLICY "documents_select_member"
  ON public.documents
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

CREATE POLICY "documents_insert_owner_admin_manager"
  ON public.documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

CREATE POLICY "documents_update_owner_admin_manager"
  ON public.documents
  FOR UPDATE
  TO authenticated
  USING (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  )
  WITH CHECK (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

-- Nessuna policy DELETE in questo Step.

-- id deve essere inseribile dal client: Flow A genera documentId prima
-- dell'upload e il CHECK richiede path = company_id/id/...
GRANT SELECT ON TABLE public.documents TO authenticated;

GRANT INSERT (
  id,
  company_id,
  title,
  original_file_name,
  storage_path,
  mime_type,
  size_bytes
)
ON TABLE public.documents
TO authenticated;

GRANT UPDATE (
  title,
  is_archived
)
ON TABLE public.documents
TO authenticated;

REVOKE ALL ON TABLE public.documents FROM anon;
REVOKE DELETE ON TABLE public.documents FROM authenticated;
