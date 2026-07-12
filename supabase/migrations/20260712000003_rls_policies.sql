-- =============================================================================
-- Project Atlas — Step 1: RLS
-- Nessun INSERT client su companies / company_members
-- =============================================================================

ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles        FORCE ROW LEVEL SECURITY;
ALTER TABLE public.companies       FORCE ROW LEVEL SECURITY;
ALTER TABLE public.company_members FORCE ROW LEVEL SECURITY;

-- =============================================================================
-- PROFILES
-- =============================================================================

CREATE POLICY "profiles_select_own"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "profiles_update_own"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- =============================================================================
-- COMPANIES
-- =============================================================================

CREATE POLICY "companies_select_member"
  ON public.companies
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(id, auth.uid()));

CREATE POLICY "companies_update_owner_admin"
  ON public.companies
  FOR UPDATE
  TO authenticated
  USING (
    private.has_company_role(
      id,
      ARRAY['owner', 'admin']::public.company_role[],
      auth.uid()
    )
  )
  WITH CHECK (
    private.has_company_role(
      id,
      ARRAY['owner', 'admin']::public.company_role[],
      auth.uid()
    )
  );

CREATE POLICY "companies_delete_owner"
  ON public.companies
  FOR DELETE
  TO authenticated
  USING (
    private.has_company_role(
      id,
      ARRAY['owner']::public.company_role[],
      auth.uid()
    )
  );

-- =============================================================================
-- COMPANY_MEMBERS
-- =============================================================================

CREATE POLICY "company_members_select_same_company"
  ON public.company_members
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

CREATE POLICY "company_members_update_owner_admin"
  ON public.company_members
  FOR UPDATE
  TO authenticated
  USING (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin']::public.company_role[],
      auth.uid()
    )
  )
  WITH CHECK (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin']::public.company_role[],
      auth.uid()
    )
  );

CREATE POLICY "company_members_delete_owner_admin_or_self"
  ON public.company_members
  FOR DELETE
  TO authenticated
  USING (
    (
      user_id = auth.uid()
      AND role IS DISTINCT FROM 'owner'::public.company_role
    )
    OR private.has_company_role(
      company_id,
      ARRAY['owner', 'admin']::public.company_role[],
      auth.uid()
    )
  );
