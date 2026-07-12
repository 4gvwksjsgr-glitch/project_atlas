-- =============================================================================
-- Project Atlas — Step 1: Privilegi
-- =============================================================================

REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company(TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION private.is_company_member(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.has_company_role(UUID, public.company_role[], UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.count_company_owners(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.enforce_company_members_integrity() FROM PUBLIC;

GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, UPDATE, DELETE ON public.companies TO authenticated;
GRANT SELECT, UPDATE, DELETE ON public.company_members TO authenticated;

REVOKE INSERT ON public.companies FROM authenticated;
REVOKE INSERT ON public.company_members FROM authenticated;

REVOKE ALL ON public.profiles FROM anon;
REVOKE ALL ON public.companies FROM anon;
REVOKE ALL ON public.company_members FROM anon;
