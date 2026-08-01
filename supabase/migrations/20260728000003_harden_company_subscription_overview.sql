-- =============================================================================
-- Project Atlas — Step 14A correction: overview SECURITY DEFINER
-- Additive. Does not modify 20260728000001 / 20260728000002.
--
-- Why: SECURITY INVOKER + plans RLS (is_active = true only) made historical
-- subscriptions on inactive plans fail with "Plan not found".
-- is_active gates catalog visibility and new assignments, not historical reads.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_company_subscription_overview(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  configured_plan_code TEXT,
  configured_plan_name TEXT,
  subscription_status TEXT,
  effective_plan_code TEXT,
  effective_plan_name TEXT,
  document_monthly_limit INTEGER,
  trial_started_at TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  trial_used_at TIMESTAMPTZ,
  is_trial_active BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := now();
  v_sub public.company_subscriptions%ROWTYPE;
  v_configured public.plans%ROWTYPE;
  v_effective_code TEXT;
  v_effective_name TEXT;
  v_effective_limit INTEGER;
  v_trial_active BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required'
      USING ERRCODE = '22023';
  END IF;

  -- Membership check independent of RLS (private helper is SECURITY DEFINER).
  IF NOT private.is_company_member(p_company_id, v_uid) THEN
    RAISE EXCEPTION 'Not a company member'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- Read plan rows regardless of is_active (DEFINER + membership already gated).
  SELECT *
  INTO v_configured
  FROM public.plans p
  WHERE p.code = v_sub.plan_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plan not found'
      USING ERRCODE = 'P0002';
  END IF;

  v_trial_active := FALSE;

  IF v_sub.status = 'trialing'
    AND v_sub.trial_ends_at IS NOT NULL
    AND v_sub.trial_ends_at > v_now THEN
    v_effective_code := 'premium';
    v_trial_active := TRUE;
  ELSIF v_sub.status = 'active' AND v_sub.plan_code = 'premium' THEN
    v_effective_code := 'premium';
  ELSE
    -- free, trialing scaduto, o stati incoerenti: effective Free
    v_effective_code := 'free';
  END IF;

  SELECT p.name, p.document_monthly_limit
  INTO v_effective_name, v_effective_limit
  FROM public.plans p
  WHERE p.code = v_effective_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plan not found'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT
    v_sub.company_id,
    v_sub.plan_code,
    v_configured.name,
    v_sub.status,
    v_effective_code,
    v_effective_name,
    v_effective_limit,
    v_sub.trial_started_at,
    v_sub.trial_ends_at,
    v_sub.trial_used_at,
    v_trial_active;
END;
$$;

COMMENT ON FUNCTION public.get_company_subscription_overview(UUID) IS
  'Overview piano effettivo per member. SECURITY DEFINER; membership gate; '
  'legge plans anche se is_active = false. Read-only.';

-- Ensure server-side ownership (migration role / postgres), never client roles.
ALTER FUNCTION public.get_company_subscription_overview(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_company_subscription_overview(UUID)
  TO authenticated;
