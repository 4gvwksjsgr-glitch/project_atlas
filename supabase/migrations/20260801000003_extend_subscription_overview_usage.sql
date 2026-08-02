-- =============================================================================
-- Project Atlas — Step 14B: extend subscription overview with usage + trial flag
-- Additive. RETURNS TABLE change requires DROP + CREATE (not CREATE OR REPLACE).
-- =============================================================================

-- Refuse DROP if a view/rule depends on the RPC (no CASCADE).
DO $$
DECLARE
  v_deps TEXT;
BEGIN
  SELECT string_agg(dep.obj_name, ', ' ORDER BY dep.obj_name)
  INTO v_deps
  FROM (
    SELECT DISTINCT n.nspname || '.' || c.relname AS obj_name
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class c ON c.oid = r.ev_class
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = d.refobjid
    JOIN pg_namespace pn ON pn.oid = p.pronamespace
    WHERE pn.nspname = 'public'
      AND p.proname = 'get_company_subscription_overview'
      AND pg_get_function_identity_arguments(p.oid) = 'p_company_id uuid'
  ) dep;

  IF v_deps IS NOT NULL THEN
    RAISE EXCEPTION
      'Refusing DROP get_company_subscription_overview(uuid): view deps: %',
      v_deps;
  END IF;
END $$;

DROP FUNCTION public.get_company_subscription_overview(UUID);

CREATE FUNCTION public.get_company_subscription_overview(
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
  is_trial_active BOOLEAN,
  documents_used BIGINT,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  is_unlimited BOOLEAN,
  can_activate_trial BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := now();
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
  v_sub public.company_subscriptions%ROWTYPE;
  v_configured public.plans%ROWTYPE;
  v_effective_code TEXT;
  v_effective_name TEXT;
  v_effective_limit INTEGER;
  v_trial_active BOOLEAN;
  v_used BIGINT;
  v_is_owner BOOLEAN;
  v_premium_ok BOOLEAN;
  v_can_trial BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required'
      USING ERRCODE = '22023';
  END IF;

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

  v_period_start :=
    date_trunc('month', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_period_end := v_period_start + interval '1 month';

  SELECT u.documents_used
  INTO v_used
  FROM private.company_document_monthly_usage u
  WHERE u.company_id = p_company_id
    AND u.period_start = v_period_start;

  IF NOT FOUND THEN
    v_used := 0;
  END IF;

  v_is_owner := private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    v_uid
  );

  SELECT EXISTS (
    SELECT 1
    FROM public.plans p
    WHERE p.code = 'premium'
      AND p.is_active = TRUE
  )
  INTO v_premium_ok;

  v_can_trial :=
    v_is_owner
    AND v_sub.trial_used_at IS NULL
    AND v_effective_code = 'free'
    AND v_premium_ok;

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
    v_trial_active,
    v_used,
    v_period_start,
    v_period_end,
    (v_effective_limit IS NULL),
    v_can_trial;
END;
$$;

COMMENT ON FUNCTION public.get_company_subscription_overview(UUID) IS
  'Step 14B: overview 14A + documents_used/period/is_unlimited/can_activate_trial.';

ALTER FUNCTION public.get_company_subscription_overview(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_company_subscription_overview(UUID)
  TO authenticated;
