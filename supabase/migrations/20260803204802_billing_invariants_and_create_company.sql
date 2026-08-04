-- =============================================================================
-- Project Atlas — Step 14C-1: billing invariants + create_company billing row
-- Additive. Applies definitive CHECKs after backfill/validation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Validate entitlement_origin backfill (must be zero rows)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_bad INTEGER;
BEGIN
  SELECT count(*)::integer
  INTO v_bad
  FROM public.company_subscriptions cs
  WHERE NOT (
    (cs.entitlement_origin = 'none'
      AND cs.plan_code = 'free'
      AND cs.status = 'free')
    OR (cs.entitlement_origin = 'internal_trial'
      AND cs.plan_code = 'premium'
      AND cs.status = 'trialing'
      AND cs.trial_started_at IS NOT NULL
      AND cs.trial_ends_at IS NOT NULL
      AND cs.trial_used_at IS NOT NULL
      AND cs.trial_ends_at > cs.trial_started_at)
    OR (cs.entitlement_origin = 'manual'
      AND cs.plan_code = 'premium'
      AND cs.status = 'active')
    OR (cs.entitlement_origin = 'provider'
      AND cs.status IN ('free', 'active')
      AND cs.plan_code IN ('free', 'premium')
      AND cs.status IS DISTINCT FROM 'trialing')
  );

  IF v_bad > 0 THEN
    RAISE EXCEPTION
      'Step 14C-1: % company_subscriptions rows violate entitlement_origin shape before CHECK',
      v_bad;
  END IF;
END $$;

ALTER TABLE public.company_subscriptions
  DROP CONSTRAINT IF EXISTS company_subscriptions_entitlement_origin_shape;

ALTER TABLE public.company_subscriptions
  ADD CONSTRAINT company_subscriptions_entitlement_origin_shape
  CHECK (
    (
      entitlement_origin = 'none'
      AND plan_code = 'free'
      AND status = 'free'
    )
    OR (
      entitlement_origin = 'internal_trial'
      AND plan_code = 'premium'
      AND status = 'trialing'
      AND trial_started_at IS NOT NULL
      AND trial_ends_at IS NOT NULL
      AND trial_used_at IS NOT NULL
      AND trial_ends_at > trial_started_at
    )
    OR (
      entitlement_origin = 'manual'
      AND plan_code = 'premium'
      AND status = 'active'
    )
    OR (
      entitlement_origin = 'provider'
      AND status IN ('free', 'active')
      AND plan_code IN ('free', 'premium')
    )
  );

-- -----------------------------------------------------------------------------
-- company_billing definitive CHECKs
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_bad INTEGER;
BEGIN
  SELECT count(*)::integer
  INTO v_bad
  FROM private.company_billing b
  WHERE NOT (
    b.subscription_status IN (
      'none', 'incomplete', 'active', 'paused', 'ended', 'revoked', 'unknown'
    )
    AND b.payment_status IN (
      'none', 'ok', 'pending', 'failed', 'past_due', 'refunded', 'unknown'
    )
    AND b.provider_access_status IN (
      'none', 'entitled', 'grace', 'blocked', 'ended', 'unknown'
    )
    AND b.sync_status IN (
      'idle', 'pending', 'processing', 'reconcile_required'
    )
    AND b.last_sync_result IN ('none', 'succeeded', 'failed')
    AND (
      (b.external_customer_id IS NULL AND b.external_subscription_id IS NULL
        AND b.external_price_id IS NULL)
      OR b.provider_code IS NOT NULL
    )
    AND (
      b.cancel_at_period_end = FALSE
      OR b.subscription_status = 'active'
    )
    AND (
      b.current_period_start IS NULL
      OR b.current_period_end IS NULL
      OR b.current_period_end > b.current_period_start
    )
    AND (
      b.provider_access_status IS DISTINCT FROM 'entitled'
      OR b.provider_access_ends_at IS NOT NULL
    )
    AND (
      b.provider_access_status IS DISTINCT FROM 'grace'
      OR b.grace_ends_at IS NOT NULL
    )
  );

  IF v_bad > 0 THEN
    RAISE EXCEPTION
      'Step 14C-1: % company_billing rows violate invariants before CHECK',
      v_bad;
  END IF;
END $$;

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_subscription_status_allowed;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_subscription_status_allowed
  CHECK (
    subscription_status IN (
      'none', 'incomplete', 'active', 'paused', 'ended', 'revoked', 'unknown'
    )
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_payment_status_allowed;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_payment_status_allowed
  CHECK (
    payment_status IN (
      'none', 'ok', 'pending', 'failed', 'past_due', 'refunded', 'unknown'
    )
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_provider_access_status_allowed;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_provider_access_status_allowed
  CHECK (
    provider_access_status IN (
      'none', 'entitled', 'grace', 'blocked', 'ended', 'unknown'
    )
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_sync_status_allowed;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_sync_status_allowed
  CHECK (
    sync_status IN (
      'idle', 'pending', 'processing', 'reconcile_required'
    )
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_last_sync_result_allowed;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_last_sync_result_allowed
  CHECK (last_sync_result IN ('none', 'succeeded', 'failed'));

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_external_ids_require_provider;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_external_ids_require_provider
  CHECK (
    (external_customer_id IS NULL
      AND external_subscription_id IS NULL
      AND external_price_id IS NULL)
    OR provider_code IS NOT NULL
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_cancel_requires_active;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_cancel_requires_active
  CHECK (
    cancel_at_period_end = FALSE
    OR subscription_status = 'active'
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_period_order;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_period_order
  CHECK (
    current_period_start IS NULL
    OR current_period_end IS NULL
    OR current_period_end > current_period_start
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_entitled_requires_ends_at;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_entitled_requires_ends_at
  CHECK (
    provider_access_status IS DISTINCT FROM 'entitled'
    OR provider_access_ends_at IS NOT NULL
  );

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_grace_requires_ends_at;
ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_grace_requires_ends_at
  CHECK (
    provider_access_status IS DISTINCT FROM 'grace'
    OR grace_ends_at IS NOT NULL
  );

-- -----------------------------------------------------------------------------
-- billing_provider_events definitive CHECKs
-- -----------------------------------------------------------------------------
ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_processing_status_allowed;
ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_processing_status_allowed
  CHECK (
    processing_status IN (
      'received', 'processing', 'processed', 'ignored', 'failed'
    )
  );

ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_verification_status_allowed;
ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_verification_status_allowed
  CHECK (
    verification_status IN ('unverified', 'verified', 'rejected')
  );

ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_verified_requires_timestamp;
ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_verified_requires_timestamp
  CHECK (
    verification_status IS DISTINCT FROM 'verified'
    OR signature_verified_at IS NOT NULL
  );

ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_processed_requires_verified;
ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_processed_requires_verified
  CHECK (
    processing_status IS DISTINCT FROM 'processed'
    OR verification_status = 'verified'
  );

-- -----------------------------------------------------------------------------
-- create_company: Free subscription + billing row (atomic)
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

  INSERT INTO public.company_subscriptions (
    company_id,
    plan_code,
    status,
    trial_started_at,
    trial_ends_at,
    trial_used_at,
    entitlement_origin
  )
  VALUES (
    v_company.id,
    'free',
    'free',
    NULL,
    NULL,
    NULL,
    'none'
  );

  INSERT INTO private.company_billing (company_id)
  VALUES (v_company.id);

  RETURN v_company;
END;
$$;

COMMENT ON FUNCTION public.create_company(TEXT, TEXT) IS
  'Crea company + owner + subscription Free + billing none/idle in una transazione.';

ALTER FUNCTION public.create_company(TEXT, TEXT) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_company(TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company(TEXT, TEXT) TO authenticated;
