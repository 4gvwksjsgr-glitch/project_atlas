-- =============================================================================
-- Project Atlas — Step 13A: Harden privileges on public.documents
-- Migration additiva: privilegi minimi espliciti (least privilege).
-- INSERT: id + campi metadata (id richiesto dal Flow A / path CHECK).
-- UPDATE: solo title, is_archived.
-- =============================================================================

REVOKE ALL ON TABLE public.documents FROM PUBLIC;
REVOKE ALL ON TABLE public.documents FROM anon;
REVOKE ALL ON TABLE public.documents FROM authenticated;

REVOKE ALL (
  id,
  company_id,
  uploaded_by,
  title,
  original_file_name,
  storage_path,
  mime_type,
  size_bytes,
  is_archived,
  created_at,
  updated_at
) ON TABLE public.documents FROM PUBLIC;

REVOKE ALL (
  id,
  company_id,
  uploaded_by,
  title,
  original_file_name,
  storage_path,
  mime_type,
  size_bytes,
  is_archived,
  created_at,
  updated_at
) ON TABLE public.documents FROM anon;

REVOKE ALL (
  id,
  company_id,
  uploaded_by,
  title,
  original_file_name,
  storage_path,
  mime_type,
  size_bytes,
  is_archived,
  created_at,
  updated_at
) ON TABLE public.documents FROM authenticated;

GRANT SELECT
ON TABLE public.documents
TO authenticated;

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
