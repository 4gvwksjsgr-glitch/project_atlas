-- =============================================================================
-- Project Atlas — Step 13A: Bucket privato company-documents + policy Storage
-- Migration additiva: non modifica migration già applicate.
-- =============================================================================

-- Helper: estrae un segmento path come UUID solo se valido; altrimenti NULL
-- (evita eccezioni da cast su path malformati nelle policy Storage).
CREATE FUNCTION private.storage_uuid_path_segment(
  p_object_name text,
  p_segment_index integer
)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_parts text[];
  v_seg text;
BEGIN
  IF p_object_name IS NULL
     OR p_segment_index IS NULL
     OR p_segment_index < 1 THEN
    RETURN NULL;
  END IF;

  v_parts := string_to_array(p_object_name, '/');
  IF cardinality(v_parts) IS NULL OR cardinality(v_parts) < p_segment_index THEN
    RETURN NULL;
  END IF;

  v_seg := lower(v_parts[p_segment_index]);
  IF v_seg IS NULL
     OR v_seg !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NULL;
  END IF;

  RETURN v_seg::uuid;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION private.storage_uuid_path_segment(text, integer)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.storage_uuid_path_segment(text, integer)
  FROM anon;
GRANT EXECUTE ON FUNCTION private.storage_uuid_path_segment(text, integer)
  TO authenticated;

-- Path canonico: company_id/document_id/object.ext (almeno 3 segmenti).
CREATE FUNCTION private.storage_company_documents_path_is_canonical(
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_parts text[];
  v_file text;
BEGIN
  IF p_object_name IS NULL OR position('/' in p_object_name) = 0 THEN
    RETURN FALSE;
  END IF;

  v_parts := string_to_array(p_object_name, '/');
  IF cardinality(v_parts) IS DISTINCT FROM 3 THEN
    RETURN FALSE;
  END IF;

  IF private.storage_uuid_path_segment(p_object_name, 1) IS NULL THEN
    RETURN FALSE;
  END IF;
  IF private.storage_uuid_path_segment(p_object_name, 2) IS NULL THEN
    RETURN FALSE;
  END IF;

  v_file := v_parts[3];
  IF v_file IS NULL
     OR v_file = ''
     OR position('/' in v_file) > 0
     OR v_file !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|png|webp)$' THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
EXCEPTION
  WHEN OTHERS THEN
    RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION private.storage_company_documents_path_is_canonical(text)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.storage_company_documents_path_is_canonical(text)
  FROM anon;
GRANT EXECUTE ON FUNCTION private.storage_company_documents_path_is_canonical(text)
  TO authenticated;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'company-documents',
  'company-documents',
  FALSE,
  6291456,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
);

CREATE POLICY "company_documents_select_member"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'company-documents'
    AND private.storage_company_documents_path_is_canonical(name)
    AND private.is_company_member(
      private.storage_uuid_path_segment(name, 1),
      auth.uid()
    )
  );

CREATE POLICY "company_documents_insert_owner_admin_manager"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'company-documents'
    AND private.storage_company_documents_path_is_canonical(name)
    AND private.has_company_role(
      private.storage_uuid_path_segment(name, 1),
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

-- DELETE solo per cleanup dopo fallimento metadata (e operazioni gestite).
CREATE POLICY "company_documents_delete_owner_admin_manager"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'company-documents'
    AND private.storage_company_documents_path_is_canonical(name)
    AND private.has_company_role(
      private.storage_uuid_path_segment(name, 1),
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

-- Nessuna policy UPDATE nello Step 13A.
