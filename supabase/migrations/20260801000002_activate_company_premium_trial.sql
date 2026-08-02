-- =============================================================================
-- Project Atlas — Step 14B: owner-only Premium trial activation
-- Additive. Does not modify historical migrations.
-- =============================================================================

CREATE FUNCTION public.activate_company_premium_trial(
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := now();
  v_sub public.company_subscriptions%ROWTYPE;
  v_premium_active BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF NOT private.is_company_member(p_company_id, v_uid) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    v_uid
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  -- Deterministic check order after lock:
  -- 1) active trial
  IF v_sub.status = 'trialing'
    AND v_sub.trial_ends_at IS NOT NULL
    AND v_sub.trial_ends_at > v_now THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_TRIAL_ALREADY_ACTIVE';
  END IF;

  -- 2) already Premium
  IF v_sub.status = 'active' AND v_sub.plan_code = 'premium' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_ALREADY_PREMIUM';
  END IF;

  -- 3) trial already used (includes expired trial rows)
  IF v_sub.trial_used_at IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_TRIAL_ALREADY_USED';
  END IF;

  -- 4) premium catalog available
  SELECT p.is_active
  INTO v_premium_active
  FROM public.plans p
  WHERE p.code = 'premium';

  IF NOT FOUND OR v_premium_active IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PREMIUM_UNAVAILABLE';
  END IF;

  UPDATE public.company_subscriptions cs
  SET
    status = 'trialing',
    plan_code = 'premium',
    trial_started_at = v_now,
    trial_ends_at = v_now + interval '1 month',
    trial_used_at = v_now
    -- updated_at via set_company_subscriptions_updated_at trigger
  WHERE cs.company_id = p_company_id;
END;
$$;

COMMENT ON FUNCTION public.activate_company_premium_trial(UUID) IS
  'Step 14B: owner-only one-shot Premium trial. MESSAGE = ATLAS_* codes.';

ALTER FUNCTION public.activate_company_premium_trial(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.activate_company_premium_trial(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_company_premium_trial(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.activate_company_premium_trial(UUID)
  TO authenticated;
