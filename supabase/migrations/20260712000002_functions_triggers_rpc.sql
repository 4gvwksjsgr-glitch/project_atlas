-- =============================================================================
-- Project Atlas — Step 1: Funzioni, trigger, RPC
-- =============================================================================

-- -----------------------------------------------------------------------------
-- updated_at generico
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_companies_updated_at
  BEFORE UPDATE ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Profilo automatico su signup
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Helper RLS — schema private
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_company_member(
  p_company_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_members
    WHERE company_id = p_company_id
      AND user_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION private.has_company_role(
  p_company_id UUID,
  p_roles public.company_role[],
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.company_members
    WHERE company_id = p_company_id
      AND user_id = p_user_id
      AND role = ANY (p_roles)
  );
$$;

CREATE OR REPLACE FUNCTION private.count_company_owners(
  p_company_id UUID
)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.company_members
  WHERE company_id = p_company_id
    AND role = 'owner'::public.company_role;
$$;

-- -----------------------------------------------------------------------------
-- Integrità membership
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.enforce_company_members_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_owner_count INTEGER;
  v_actor_is_owner BOOLEAN;
  v_actor_is_admin BOOLEAN;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
      RAISE EXCEPTION 'company_id cannot be changed';
    END IF;

    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      RAISE EXCEPTION 'user_id cannot be changed';
    END IF;

    IF NEW.user_id = auth.uid() AND NEW.role IS DISTINCT FROM OLD.role THEN
      IF (
        (OLD.role = 'employee'::public.company_role AND NEW.role IN ('manager'::public.company_role, 'admin'::public.company_role, 'owner'::public.company_role))
        OR (OLD.role = 'manager'::public.company_role AND NEW.role IN ('admin'::public.company_role, 'owner'::public.company_role))
        OR (OLD.role = 'admin'::public.company_role AND NEW.role = 'owner'::public.company_role)
      ) THEN
        RAISE EXCEPTION 'Self-promotion is not allowed';
      END IF;

      IF OLD.role = 'owner'::public.company_role
         AND NEW.role IS DISTINCT FROM OLD.role THEN
        v_owner_count := private.count_company_owners(OLD.company_id);
        IF v_owner_count <= 1 THEN
          RAISE EXCEPTION 'Cannot demote the last owner';
        END IF;
      END IF;
    END IF;

    v_actor_is_owner := private.has_company_role(
      OLD.company_id,
      ARRAY['owner']::public.company_role[],
      auth.uid()
    );

    v_actor_is_admin := private.has_company_role(
      OLD.company_id,
      ARRAY['admin']::public.company_role[],
      auth.uid()
    );

    IF NEW.role = 'owner'::public.company_role
       AND OLD.role IS DISTINCT FROM NEW.role THEN
      IF NOT v_actor_is_owner THEN
        RAISE EXCEPTION 'Only owners can assign the owner role';
      END IF;
    END IF;

    IF NEW.role = 'admin'::public.company_role
       AND OLD.role IS DISTINCT FROM NEW.role
       AND NEW.user_id IS DISTINCT FROM auth.uid() THEN
      IF v_actor_is_admin AND NOT v_actor_is_owner THEN
        RAISE EXCEPTION 'Admins cannot assign the admin role';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.role = 'owner'::public.company_role THEN
      v_owner_count := private.count_company_owners(OLD.company_id);
      IF v_owner_count <= 1 THEN
        RAISE EXCEPTION 'Cannot remove the last owner';
      END IF;
    END IF;

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_company_members_integrity
  BEFORE UPDATE OR DELETE ON public.company_members
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_company_members_integrity();

-- -----------------------------------------------------------------------------
-- RPC: creazione atomica company + owner
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_company(
  p_name TEXT,
  p_slug TEXT
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_slug TEXT;
  v_company public.companies;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  v_name := trim(p_name);
  v_slug := lower(trim(p_slug));

  IF v_name IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Company name is required'
      USING ERRCODE = '22023';
  END IF;

  IF v_slug IS NULL OR v_slug = '' THEN
    RAISE EXCEPTION 'Company slug is required'
      USING ERRCODE = '22023';
  END IF;

  IF v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'Invalid slug format'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.companies (name, slug)
  VALUES (v_name, v_slug)
  RETURNING * INTO v_company;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (
    v_company.id,
    v_user_id,
    'owner'::public.company_role
  );

  RETURN v_company;
END;
$$;
