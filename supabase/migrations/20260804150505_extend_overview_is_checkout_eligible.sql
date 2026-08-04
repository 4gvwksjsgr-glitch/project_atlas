-- =============================================================================
-- Project Atlas — Step 14C-2B: overview append is_checkout_eligible (col 33)
-- Additive DROP+CREATE. Preserve columns 1–32; portal remains FALSE.
-- =============================================================================

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
  can_activate_trial BOOLEAN,
  entitlement_origin TEXT,
  billing_subscription_status TEXT,
  billing_payment_status TEXT,
  sync_status TEXT,
  last_sync_result TEXT,
  cancel_at_period_end BOOLEAN,
  billing_period_start TIMESTAMPTZ,
  billing_period_end TIMESTAMPTZ,
  provider_access_status TEXT,
  provider_access_ends_at TIMESTAMPTZ,
  is_provider_grace BOOLEAN,
  grace_ends_at TIMESTAMPTZ,
  has_payment_issue BOOLEAN,
  billing_linked BOOLEAN,
  can_open_billing_portal BOOLEAN,
  billing_sync_pending BOOLEAN,
  is_checkout_eligible BOOLEAN
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
  v_used BIGINT;
  v_is_owner BOOLEAN;
  v_premium_ok BOOLEAN;
  v_can_trial BOOLEAN;
  v_can_checkout BOOLEAN;
  v_client_status TEXT;
  v_ent_origin TEXT;
  v_atlas_plan TEXT;
  v_cfg_name TEXT;
  v_eff_code TEXT;
  v_eff_name TEXT;
  v_eff_limit INTEGER;
  v_trial_started TIMESTAMPTZ;
  v_trial_ends TIMESTAMPTZ;
  v_trial_used TIMESTAMPTZ;
  v_trial_active BOOLEAN;
  v_prov_grace BOOLEAN;
  v_bill_sub TEXT;
  v_bill_pay TEXT;
  v_sync TEXT;
  v_last_sync TEXT;
  v_cancel BOOLEAN;
  v_bstart TIMESTAMPTZ;
  v_bend TIMESTAMPTZ;
  v_access TEXT;
  v_access_ends TIMESTAMPTZ;
  v_grace_ends TIMESTAMPTZ;
  v_pay_issue BOOLEAN;
  v_linked BOOLEAN;
  v_sync_pending BOOLEAN;
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

  SELECT
    r.entitlement_origin,
    r.atlas_plan_code,
    r.configured_plan_name,
    r.effective_plan_code,
    r.effective_plan_name,
    r.document_monthly_limit,
    r.trial_started_at,
    r.trial_ends_at,
    r.trial_used_at,
    r.is_trial_active,
    r.is_provider_grace,
    r.billing_subscription_status,
    r.billing_payment_status,
    r.sync_status,
    r.last_sync_result,
    r.cancel_at_period_end,
    r.billing_period_start,
    r.billing_period_end,
    r.provider_access_status,
    r.provider_access_ends_at,
    r.grace_ends_at,
    r.has_payment_issue,
    r.billing_linked,
    r.billing_sync_pending
  INTO
    v_ent_origin,
    v_atlas_plan,
    v_cfg_name,
    v_eff_code,
    v_eff_name,
    v_eff_limit,
    v_trial_started,
    v_trial_ends,
    v_trial_used,
    v_trial_active,
    v_prov_grace,
    v_bill_sub,
    v_bill_pay,
    v_sync,
    v_last_sync,
    v_cancel,
    v_bstart,
    v_bend,
    v_access,
    v_access_ends,
    v_grace_ends,
    v_pay_issue,
    v_linked,
    v_sync_pending
  FROM private.resolve_company_entitlement(p_company_id, v_now) r;

  IF v_trial_active THEN
    v_client_status := 'trialing';
  ELSIF v_eff_code = 'premium' THEN
    v_client_status := 'active';
  ELSE
    v_client_status := 'free';
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
    AND v_trial_used IS NULL
    AND v_eff_code = 'free'
    AND v_ent_origin = 'none'
    AND NOT v_linked
    AND NOT v_sync_pending
    AND v_premium_ok;

  v_can_checkout := private.is_company_checkout_eligible(
    p_company_id,
    v_uid,
    v_now
  );

  RETURN QUERY
  SELECT
    p_company_id,
    v_atlas_plan,
    v_cfg_name,
    v_client_status,
    v_eff_code,
    v_eff_name,
    v_eff_limit,
    v_trial_started,
    v_trial_ends,
    v_trial_used,
    v_trial_active,
    v_used,
    v_period_start,
    v_period_end,
    (v_eff_limit IS NULL),
    v_can_trial,
    v_ent_origin,
    v_bill_sub,
    v_bill_pay,
    v_sync,
    v_last_sync,
    v_cancel,
    v_bstart,
    v_bend,
    v_access,
    v_access_ends,
    v_prov_grace,
    v_grace_ends,
    v_pay_issue,
    v_linked,
    FALSE, -- can_open_billing_portal remains false in 14C-2
    v_sync_pending,
    v_can_checkout;
END;
$$;

COMMENT ON FUNCTION public.get_company_subscription_overview(UUID) IS
  'Step 14C-2B: overview 1–32 preserved; col 33 is_checkout_eligible; portal always false.';

ALTER FUNCTION public.get_company_subscription_overview(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_company_subscription_overview(UUID)
  TO authenticated;
