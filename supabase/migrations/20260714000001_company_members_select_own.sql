-- =============================================================================
-- Project Atlas — Fix RLS ricorsione su company_members SELECT
-- =============================================================================
-- La policy company_members_select_same_company invoca private.is_company_member,
-- che a sua volta legge company_members e può causare:
--   infinite recursion detected in policy for relation "company_members" (42P17)
-- Questa policy consente la lettura diretta delle proprie membership.

CREATE POLICY "company_members_select_own"
  ON public.company_members
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());
