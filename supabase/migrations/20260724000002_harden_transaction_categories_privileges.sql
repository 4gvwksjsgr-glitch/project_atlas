-- =============================================================================
-- Project Atlas — Step 12A: Harden privileges on public.transaction_categories
-- Migration additiva: privilegi minimi espliciti (least privilege).
-- INSERT solo company_id/name/kind/is_active; UPDATE solo name/is_active.
-- =============================================================================

REVOKE ALL ON TABLE public.transaction_categories FROM PUBLIC;
REVOKE ALL ON TABLE public.transaction_categories FROM anon;
REVOKE ALL ON TABLE public.transaction_categories FROM authenticated;

REVOKE ALL (
  id,
  company_id,
  name,
  kind,
  is_active,
  created_at,
  updated_at
) ON TABLE public.transaction_categories FROM PUBLIC;

REVOKE ALL (
  id,
  company_id,
  name,
  kind,
  is_active,
  created_at,
  updated_at
) ON TABLE public.transaction_categories FROM anon;

REVOKE ALL (
  id,
  company_id,
  name,
  kind,
  is_active,
  created_at,
  updated_at
) ON TABLE public.transaction_categories FROM authenticated;

GRANT SELECT
ON TABLE public.transaction_categories
TO authenticated;

GRANT INSERT (
  company_id,
  name,
  kind,
  is_active
)
ON TABLE public.transaction_categories
TO authenticated;

GRANT UPDATE (
  name,
  is_active
)
ON TABLE public.transaction_categories
TO authenticated;
