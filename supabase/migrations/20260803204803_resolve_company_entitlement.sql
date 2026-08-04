-- =============================================================================
-- Project Atlas — Step 14C-1: resolve_company_entitlement + rewire quota/trial
-- Additive. SECURITY INVOKER resolver; client EXECUTE revoked.
-- =============================================================================

CREATE OR REPLACE FUNCTION private.resolve_company_entitlement(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  company_id UUID,
  entitlement_origin TEXT,
  atlas_plan_code TEXT,
  atlas_status TEXT,
  configured_plan_name TEXT,
  trial_started_at TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  trial_used_at TIMESTAMPTZ,
  effective_plan_code TEXT,
  effective_plan_name TEXT,
  document_monthly_limit INTEGER,
  is_manual_premium BOOLEAN,
  is_trial_active BOOLEAN,
  is_provider_premium BOOLEAN,
  is_provider_grace BOOLEAN,
  billing_linked BOOLEAN,
  billing_subscription_status TEXT,
  billing_payment_status TEXT,
  sync_status TEXT,
  last_sync_result TEXT,
  cancel_at_period_end BOOLEAN,
  billing_period_start TIMESTAMPTZ,
  billing_period_end TIMESTAMPTZ,
  provider_access_status TEXT,
  provider_access_ends_at TIMESTAMPTZ,
  grace_ends_at TIMESTAMPTZ,
  has_payment_issue BOOLEAN,
  billing_sync_pending BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_sub public.company_subscriptions%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_has_bill BOOLEAN := FALSE;
  v_origin TEXT;
  v_effective TEXT;
  v_eff_name TEXT;
  v_eff_limit INTEGER;
  v_cfg_name TEXT;
  v_trial_active BOOLEAN := FALSE;
  v_manual BOOLEAN := FALSE;
  v_prov_prem BOOLEAN := FALSE;
  v_prov_grace BOOLEAN := FALSE;
  v_linked BOOLEAN := FALSE;
  v_sub_status TEXT := 'none';
  v_pay_status TEXT := 'none';
  v_sync TEXT := 'idle';
  v_last_sync TEXT := 'none';
  v_cancel BOOLEAN := FALSE;
  v_bstart TIMESTAMPTZ := NULL;
  v_bend TIMESTAMPTZ := NULL;
  v_access TEXT := 'none';
  v_access_ends TIMESTAMPTZ := NULL;
  v_grace_ends TIMESTAMPTZ := NULL;
  v_pay_issue BOOLEAN := FALSE;
  v_sync_pending BOOLEAN := FALSE;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  v_has_bill := FOUND;

  IF v_has_bill THEN
    v_sub_status := v_bill.subscription_status;
    v_pay_status := v_bill.payment_status;
    v_sync := v_bill.sync_status;
    v_last_sync := v_bill.last_sync_result;
    v_cancel := v_bill.cancel_at_period_end;
    v_bstart := v_bill.current_period_start;
    v_bend := v_bill.current_period_end;
    v_access := v_bill.provider_access_status;
    v_access_ends := v_bill.provider_access_ends_at;
    v_grace_ends := v_bill.grace_ends_at;
    v_linked :=
      v_bill.external_customer_id IS NOT NULL
      OR v_bill.external_subscription_id IS NOT NULL;
    v_pay_issue := v_bill.payment_status IN ('failed', 'past_due');
    v_sync_pending := v_bill.sync_status IN (
      'pending', 'processing', 'reconcile_required'
    );
  END IF;

  SELECT p.name
  INTO v_cfg_name
  FROM public.plans p
  WHERE p.code = v_sub.plan_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PLAN_NOT_FOUND';
  END IF;

  v_origin := v_sub.entitlement_origin;

  IF v_origin = 'manual' THEN
    IF v_sub.plan_code = 'premium' AND v_sub.status = 'active' THEN
      v_effective := 'premium';
      v_manual := TRUE;
    ELSE
      v_effective := 'free';
    END IF;

  ELSIF v_origin = 'internal_trial' THEN
    IF v_sub.status = 'trialing'
      AND v_sub.trial_ends_at IS NOT NULL
      AND v_sub.trial_ends_at > p_now THEN
      v_effective := 'premium';
      v_trial_active := TRUE;
    ELSE
      v_effective := 'free';
    END IF;

  ELSIF v_origin = 'provider' THEN
    -- Fail-closed: ONLY provider_access_* (+ grace_ends_at) and p_now.
    IF v_access = 'entitled'
      AND v_access_ends IS NOT NULL
      AND v_access_ends > p_now THEN
      v_effective := 'premium';
      v_prov_prem := TRUE;
    ELSIF v_access = 'grace'
      AND v_grace_ends IS NOT NULL
      AND v_grace_ends > p_now THEN
      v_effective := 'premium';
      v_prov_prem := TRUE;
      v_prov_grace := TRUE;
    ELSE
      v_effective := 'free';
    END IF;

  ELSE
    -- none or unexpected → Free
    v_effective := 'free';
  END IF;

  SELECT p.name, p.document_monthly_limit
  INTO v_eff_name, v_eff_limit
  FROM public.plans p
  WHERE p.code = v_effective;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PLAN_NOT_FOUND';
  END IF;

  company_id := p_company_id;
  entitlement_origin := v_origin;
  atlas_plan_code := v_sub.plan_code;
  atlas_status := v_sub.status;
  configured_plan_name := v_cfg_name;
  trial_started_at := v_sub.trial_started_at;
  trial_ends_at := v_sub.trial_ends_at;
  trial_used_at := v_sub.trial_used_at;
  effective_plan_code := v_effective;
  effective_plan_name := v_eff_name;
  document_monthly_limit := v_eff_limit;
  is_manual_premium := v_manual;
  is_trial_active := v_trial_active;
  is_provider_premium := v_prov_prem;
  is_provider_grace := v_prov_grace;
  billing_linked := v_linked;
  billing_subscription_status := v_sub_status;
  billing_payment_status := v_pay_status;
  sync_status := v_sync;
  last_sync_result := v_last_sync;
  cancel_at_period_end := v_cancel;
  billing_period_start := v_bstart;
  billing_period_end := v_bend;
  provider_access_status := v_access;
  provider_access_ends_at := v_access_ends;
  grace_ends_at := v_grace_ends;
  has_payment_issue := v_pay_issue;
  billing_sync_pending := v_sync_pending;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.resolve_company_entitlement(UUID, TIMESTAMPTZ) IS
  'Step 14C-1: unica fonte piano effettivo. INVOKER; no EXECUTE client.';

ALTER FUNCTION private.resolve_company_entitlement(UUID, TIMESTAMPTZ)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.resolve_company_entitlement(UUID, TIMESTAMPTZ)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.resolve_company_entitlement(UUID, TIMESTAMPTZ)
  FROM anon;
REVOKE ALL ON FUNCTION private.resolve_company_entitlement(UUID, TIMESTAMPTZ)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- Rewire quota consume: lock order subscriptions → billing → usage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.consume_company_document_monthly_usage(
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_period_start TIMESTAMPTZ;
  v_limit INTEGER;
  v_used BIGINT;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  v_period_start :=
    date_trunc('month', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  -- Lock 1: subscription
  PERFORM 1
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  -- Lock 2: billing (may be absent → fail-safe via resolver)
  PERFORM 1
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  SELECT r.document_monthly_limit
  INTO v_limit
  FROM private.resolve_company_entitlement(p_company_id, v_now) r;

  INSERT INTO private.company_document_monthly_usage (
    company_id,
    period_start,
    documents_used
  )
  VALUES (p_company_id, v_period_start, 0)
  ON CONFLICT (company_id, period_start) DO NOTHING;

  -- Lock 3: usage row
  SELECT u.documents_used
  INTO v_used
  FROM private.company_document_monthly_usage u
  WHERE u.company_id = p_company_id
    AND u.period_start = v_period_start
  FOR UPDATE;

  IF v_limit IS NOT NULL AND v_used >= v_limit THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      DETAIL = format(
        'company=%s period_start=%s used=%s limit=%s',
        p_company_id,
        v_period_start,
        v_used,
        v_limit
      );
  END IF;

  UPDATE private.company_document_monthly_usage u
  SET
    documents_used = u.documents_used + 1,
    updated_at = v_now
  WHERE u.company_id = p_company_id
    AND u.period_start = v_period_start;
END;
$$;

COMMENT ON FUNCTION private.consume_company_document_monthly_usage(UUID) IS
  'Step 14C-1: quota via resolve_company_entitlement; lock sub→billing→usage.';

ALTER FUNCTION private.consume_company_document_monthly_usage(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM anon;
REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- Rewire activate_company_premium_trial
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.activate_company_premium_trial(
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
  v_bill private.company_billing%ROWTYPE;
  v_has_bill BOOLEAN := FALSE;
  v_effective TEXT;
  v_billing_linked BOOLEAN := FALSE;
  v_billing_sync_pending BOOLEAN := FALSE;
  v_premium_active BOOLEAN;
  v_linked BOOLEAN := FALSE;
  v_sync_pending BOOLEAN := FALSE;
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

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  v_has_bill := FOUND;

  IF v_has_bill THEN
    v_linked :=
      v_bill.external_customer_id IS NOT NULL
      OR v_bill.external_subscription_id IS NOT NULL;
    v_sync_pending := v_bill.sync_status IN (
      'pending', 'processing', 'reconcile_required'
    );
  END IF;

  SELECT r.effective_plan_code, r.billing_linked, r.billing_sync_pending
  INTO v_effective, v_billing_linked, v_billing_sync_pending
  FROM private.resolve_company_entitlement(p_company_id, v_now) r;

  -- Deterministic error precedence (Step 14C-1 final):
  -- 1 sync pending  2 billing linked  3 trial active
  -- 4 trial used  5 already premium  6 plan missing/unavailable
  IF v_sync_pending OR v_billing_sync_pending THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_SYNC_PENDING';
  END IF;

  IF v_sub.entitlement_origin = 'provider' OR v_linked OR v_billing_linked THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_LINKED';
  END IF;

  IF v_sub.entitlement_origin = 'internal_trial'
    AND v_sub.status = 'trialing'
    AND v_sub.trial_ends_at IS NOT NULL
    AND v_sub.trial_ends_at > v_now THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_TRIAL_ALREADY_ACTIVE';
  END IF;

  IF v_sub.trial_used_at IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_TRIAL_ALREADY_USED';
  END IF;

  IF v_effective = 'premium'
    OR v_sub.entitlement_origin = 'manual'
    OR v_sub.entitlement_origin IS DISTINCT FROM 'none'
    OR v_effective IS DISTINCT FROM 'free' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_ALREADY_PREMIUM';
  END IF;

  SELECT p.is_active
  INTO v_premium_active
  FROM public.plans p
  WHERE p.code = 'premium';

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PLAN_NOT_FOUND';
  END IF;

  IF v_premium_active IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PREMIUM_UNAVAILABLE';
  END IF;

  UPDATE public.company_subscriptions cs
  SET
    status = 'trialing',
    plan_code = 'premium',
    entitlement_origin = 'internal_trial',
    trial_started_at = v_now,
    trial_ends_at = v_now + interval '1 month',
    trial_used_at = v_now
  WHERE cs.company_id = p_company_id;
END;
$$;

COMMENT ON FUNCTION public.activate_company_premium_trial(UUID) IS
  'Step 14C-1: owner trial Atlas; fail-safe vs billing linked/sync/provider.';

ALTER FUNCTION public.activate_company_premium_trial(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.activate_company_premium_trial(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_company_premium_trial(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.activate_company_premium_trial(UUID)
  TO authenticated;
