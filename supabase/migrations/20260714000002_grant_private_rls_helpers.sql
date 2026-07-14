-- =============================================================================
-- Project Atlas — Grant EXECUTE helper RLS a authenticated
-- =============================================================================
-- Le policy RLS invocano private.is_company_member / private.has_company_role.
-- Dopo REVOKE FROM PUBLIC, authenticated deve poterle eseguire (42501 altrimenti).

GRANT EXECUTE ON FUNCTION private.is_company_member(UUID, UUID)
  TO authenticated;

GRANT EXECUTE ON FUNCTION private.has_company_role(UUID, public.company_role[], UUID)
  TO authenticated;
