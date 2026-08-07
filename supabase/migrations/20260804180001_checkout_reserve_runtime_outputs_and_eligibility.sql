-- =============================================================================
-- Project Atlas — Step 14C-2C: checkout reserve runtime outputs + eligibility
-- Additive. Extends service-role reserve wrapper; tightens eligibility gates.
-- Does not seed runtime config or provider prices.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.is_company_checkout_eligible — tighter fail-closed gates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_company_checkout_eligible(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_cfg private.billing_runtime_config%ROWTYPE;
  v_offer private.billing_offers%ROWTYPE;
  v_price_id UUID;
  v_ent RECORD;
  v_bill private.company_billing%ROWTYPE;
  v_origin TEXT;
  v_open_count INTEGER;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF NOT private.is_company_member(p_company_id, p_actor_user_id) THEN
    RETURN FALSE;
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RETURN FALSE;
  END IF;

  SELECT *
  INTO v_cfg
  FROM private.billing_runtime_config c
  WHERE c.is_active
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_cfg.checkout_enabled IS DISTINCT FROM TRUE THEN
    RETURN FALSE;
  END IF;

  SELECT *
  INTO v_offer
  FROM private.billing_offers o
  WHERE o.offer_code = 'premium_monthly'
    AND o.is_active
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  SELECT p.id
  INTO v_price_id
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer.id
    AND p.provider_code = v_cfg.provider_code
    AND p.provider_environment = v_cfg.provider_environment
    AND p.is_active
    AND p.valid_to IS NULL
    AND p.valid_from <= p_now
  LIMIT 1;

  IF v_price_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT s.entitlement_origin
  INTO v_origin
  FROM public.company_subscriptions s
  WHERE s.company_id = p_company_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Atlas manual Premium / manual origin never starts provider checkout here.
  IF v_origin = 'manual' THEN
    RETURN FALSE;
  END IF;

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_bill.sync_status IS DISTINCT FROM 'idle' THEN
    RETURN FALSE;
  END IF;

  -- Any provider/customer/subscription/price linkage blocks first checkout.
  IF v_bill.provider_code IS NOT NULL
    OR v_bill.external_customer_id IS NOT NULL
    OR v_bill.external_subscription_id IS NOT NULL
    OR v_bill.external_price_id IS NOT NULL
  THEN
    RETURN FALSE;
  END IF;

  SELECT
    r.is_provider_grace,
    r.provider_access_status,
    r.billing_subscription_status
  INTO v_ent
  FROM private.resolve_company_entitlement(p_company_id, p_now) r;

  IF v_ent.provider_access_status IN ('entitled', 'grace')
    OR v_ent.is_provider_grace IS TRUE
  THEN
    RETURN FALSE;
  END IF;

  IF v_ent.billing_subscription_status = 'active' THEN
    RETURN FALSE;
  END IF;

  SELECT count(*)::integer
  INTO v_open_count
  FROM private.billing_checkout_sessions s
  WHERE s.company_id = p_company_id
    AND s.provider_code = v_cfg.provider_code
    AND s.provider_environment = v_cfg.provider_environment
    AND s.checkout_status IN ('created', 'opened')
    AND s.expires_at > p_now;

  IF v_open_count > 0 THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ) IS
  'Step 14C-2C: fail-closed checkout eligibility (owner, idle sync, unlinked, non-manual).';

ALTER FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM anon;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.reserve_billing_checkout_session — mirror eligibility gates
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.reserve_billing_checkout_session(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_offer_code TEXT,
  p_idempotency_key TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  session_id UUID,
  reuse BOOLEAN,
  provider_environment TEXT,
  billing_provider_price_id UUID,
  external_price_id TEXT,
  atlas_plan_code TEXT,
  offer_code TEXT,
  checkout_status TEXT,
  provider_create_status TEXT,
  return_token_plain TEXT,
  return_token_version INTEGER,
  expires_at TIMESTAMPTZ,
  existing_checkout_url TEXT,
  existing_external_transaction_id TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_cfg private.billing_runtime_config%ROWTYPE;
  v_offer private.billing_offers%ROWTYPE;
  v_price private.billing_provider_prices%ROWTYPE;
  v_existing private.billing_checkout_sessions%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_origin TEXT;
  v_plain TEXT;
  v_hash TEXT;
  v_new_id UUID;
  v_expires TIMESTAMPTZ;
  v_ent RECORD;
  v_open_exists BOOLEAN;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_offer_code IS NULL OR btrim(p_offer_code) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_OFFER_CODE_REQUIRED';
  END IF;

  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  PERFORM 1
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  SELECT s.entitlement_origin
  INTO v_origin
  FROM public.company_subscriptions s
  WHERE s.company_id = p_company_id;

  PERFORM 1
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  SELECT *
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  UPDATE private.billing_checkout_sessions s
  SET
    checkout_status = 'expired',
    updated_at = p_now
  WHERE s.company_id = p_company_id
    AND s.checkout_status IN ('created', 'opened')
    AND s.expires_at <= p_now;

  IF NOT private.is_company_member(p_company_id, p_actor_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  IF v_origin = 'manual' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  END IF;

  IF v_bill.sync_status IS DISTINCT FROM 'idle' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  END IF;

  IF v_bill.provider_code IS NOT NULL
    OR v_bill.external_customer_id IS NOT NULL
    OR v_bill.external_subscription_id IS NOT NULL
    OR v_bill.external_price_id IS NOT NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  END IF;

  SELECT *
  INTO v_cfg
  FROM private.billing_runtime_config c
  WHERE c.is_active
  FOR UPDATE;

  IF NOT FOUND OR v_cfg.checkout_enabled IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  SELECT *
  INTO v_offer
  FROM private.billing_offers o
  WHERE o.offer_code = lower(btrim(p_offer_code))
    AND o.is_active
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_OFFER_NOT_FOUND';
  END IF;

  SELECT
    r.provider_access_status,
    r.is_provider_grace,
    r.billing_subscription_status
  INTO v_ent
  FROM private.resolve_company_entitlement(p_company_id, p_now) r;

  IF v_ent.provider_access_status IN ('entitled', 'grace')
    OR v_ent.is_provider_grace IS TRUE
    OR v_ent.billing_subscription_status = 'active'
  THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  END IF;

  SELECT *
  INTO v_existing
  FROM private.billing_checkout_sessions s
  WHERE s.company_id = p_company_id
    AND s.provider_code = v_cfg.provider_code
    AND s.provider_environment = v_cfg.provider_environment
    AND s.idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing.checkout_status NOT IN ('created', 'opened')
      OR v_existing.expires_at <= p_now
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT';
    END IF;

    SELECT *
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.id = v_existing.billing_provider_price_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PRICE_UNAVAILABLE';
    END IF;

    v_plain := private.billing_new_return_token_plain();
    v_hash := private.billing_hash_return_token(v_plain);

    UPDATE private.billing_checkout_sessions s
    SET
      return_token_hash = v_hash,
      return_token_version = s.return_token_version + 1,
      return_token_consumed_at = NULL,
      updated_at = p_now
    WHERE s.id = v_existing.id
    RETURNING * INTO v_existing;

    session_id := v_existing.id;
    reuse := TRUE;
    provider_environment := v_existing.provider_environment;
    billing_provider_price_id := v_existing.billing_provider_price_id;
    external_price_id := v_price.external_price_id;
    atlas_plan_code := v_existing.atlas_plan_code;
    offer_code := v_existing.offer_code;
    checkout_status := v_existing.checkout_status;
    provider_create_status := v_existing.provider_create_status;
    return_token_plain := v_plain;
    return_token_version := v_existing.return_token_version;
    expires_at := v_existing.expires_at;
    existing_checkout_url := v_existing.checkout_url;
    existing_external_transaction_id := v_existing.external_transaction_id;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT *
  INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer.id
    AND p.provider_code = v_cfg.provider_code
    AND p.provider_environment = v_cfg.provider_environment
    AND p.is_active
    AND p.valid_to IS NULL
    AND p.valid_from <= p_now
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_PRICE_UNAVAILABLE';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM private.billing_checkout_sessions s
    WHERE s.company_id = p_company_id
      AND s.provider_code = v_cfg.provider_code
      AND s.provider_environment = v_cfg.provider_environment
      AND s.checkout_status IN ('created', 'opened')
      AND s.expires_at > p_now
  )
  INTO v_open_exists;

  IF v_open_exists THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_CHECKOUT_ALREADY_OPEN';
  END IF;

  v_plain := private.billing_new_return_token_plain();
  v_hash := private.billing_hash_return_token(v_plain);
  v_expires := p_now + interval '45 minutes';
  v_new_id := gen_random_uuid();

  INSERT INTO private.billing_checkout_sessions (
    id,
    company_id,
    provider_code,
    provider_environment,
    billing_provider_price_id,
    atlas_plan_code,
    offer_code,
    initiated_by_user_id,
    checkout_status,
    provider_create_status,
    browser_signal,
    idempotency_key,
    return_token_hash,
    return_token_version,
    allowed_return_origin,
    checkout_path,
    return_path,
    expires_at,
    created_at,
    updated_at
  ) VALUES (
    v_new_id,
    p_company_id,
    v_cfg.provider_code,
    v_cfg.provider_environment,
    v_price.id,
    v_offer.atlas_plan_code,
    v_offer.offer_code,
    p_actor_user_id,
    'created',
    'not_started',
    'none',
    p_idempotency_key,
    v_hash,
    1,
    v_cfg.payment_page_origin,
    v_cfg.checkout_path,
    v_cfg.return_path,
    v_expires,
    p_now,
    p_now
  );

  session_id := v_new_id;
  reuse := FALSE;
  provider_environment := v_cfg.provider_environment;
  billing_provider_price_id := v_price.id;
  external_price_id := v_price.external_price_id;
  atlas_plan_code := v_offer.atlas_plan_code;
  offer_code := v_offer.offer_code;
  checkout_status := 'created';
  provider_create_status := 'not_started';
  return_token_plain := v_plain;
  return_token_version := 1;
  expires_at := v_expires;
  existing_checkout_url := NULL;
  existing_external_transaction_id := NULL;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.reserve_billing_checkout_session(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.reserve_billing_checkout_session_server — append runtime outputs
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
);

CREATE FUNCTION public.reserve_billing_checkout_session_server(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_offer_code TEXT,
  p_idempotency_key TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  session_id UUID,
  reuse BOOLEAN,
  provider_environment TEXT,
  billing_provider_price_id UUID,
  external_price_id TEXT,
  atlas_plan_code TEXT,
  offer_code TEXT,
  checkout_status TEXT,
  provider_create_status TEXT,
  return_token_plain TEXT,
  return_token_version INTEGER,
  expires_at TIMESTAMPTZ,
  existing_checkout_url TEXT,
  existing_external_transaction_id TEXT,
  provider_code TEXT,
  payment_page_origin TEXT,
  checkout_path TEXT,
  return_path TEXT,
  checkout_page_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_reserved RECORD;
  v_cfg private.billing_runtime_config%ROWTYPE;
  v_cfg_count INTEGER;
  v_session_provider TEXT;
BEGIN
  SELECT *
  INTO v_reserved
  FROM private.reserve_billing_checkout_session(
    p_company_id,
    p_actor_user_id,
    p_offer_code,
    p_idempotency_key,
    p_now
  );

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  SELECT count(*)::integer
  INTO v_cfg_count
  FROM private.billing_runtime_config c
  WHERE c.is_active
    AND c.provider_environment = v_reserved.provider_environment;

  IF v_cfg_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  SELECT *
  INTO v_cfg
  FROM private.billing_runtime_config c
  WHERE c.is_active
    AND c.provider_environment = v_reserved.provider_environment;

  IF NOT FOUND
    OR v_cfg.checkout_enabled IS DISTINCT FROM TRUE
    OR v_cfg.payment_page_origin IS NULL
    OR btrim(v_cfg.payment_page_origin) = ''
    OR v_cfg.checkout_path IS DISTINCT FROM '/billing/checkout'
    OR v_cfg.return_path IS DISTINCT FROM '/billing/return'
  THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  SELECT s.provider_code
  INTO v_session_provider
  FROM private.billing_checkout_sessions s
  WHERE s.id = v_reserved.session_id;

  IF v_session_provider IS DISTINCT FROM v_cfg.provider_code THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  session_id := v_reserved.session_id;
  reuse := v_reserved.reuse;
  provider_environment := v_reserved.provider_environment;
  billing_provider_price_id := v_reserved.billing_provider_price_id;
  external_price_id := v_reserved.external_price_id;
  atlas_plan_code := v_reserved.atlas_plan_code;
  offer_code := v_reserved.offer_code;
  checkout_status := v_reserved.checkout_status;
  provider_create_status := v_reserved.provider_create_status;
  return_token_plain := v_reserved.return_token_plain;
  return_token_version := v_reserved.return_token_version;
  expires_at := v_reserved.expires_at;
  existing_checkout_url := v_reserved.existing_checkout_url;
  existing_external_transaction_id := v_reserved.existing_external_transaction_id;
  provider_code := v_cfg.provider_code;
  payment_page_origin := v_cfg.payment_page_origin;
  checkout_path := v_cfg.checkout_path;
  return_path := v_cfg.return_path;
  checkout_page_url := v_cfg.payment_page_origin || v_cfg.checkout_path;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2C: service_role reserve wrapper with runtime page URL outputs.';

ALTER FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) TO service_role;
