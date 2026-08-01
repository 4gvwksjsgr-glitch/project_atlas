-- =============================================================================
-- Project Atlas — Step 14A: create_company inserts Free subscription atomically
-- Recreates create_company via CREATE OR REPLACE; preserves signature and grants.
-- =============================================================================

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

  -- Free subscription in the same transaction. Fails atomically if plan missing.
  INSERT INTO public.company_subscriptions (
    company_id,
    plan_code,
    status,
    trial_started_at,
    trial_ends_at,
    trial_used_at
  )
  VALUES (
    v_company.id,
    'free',
    'free',
    NULL,
    NULL,
    NULL
  );

  RETURN v_company;
END;
$$;

COMMENT ON FUNCTION public.create_company(TEXT, TEXT) IS
  'Crea company + owner membership + subscription Free in una sola transazione.';

REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company(TEXT, TEXT) TO authenticated;
