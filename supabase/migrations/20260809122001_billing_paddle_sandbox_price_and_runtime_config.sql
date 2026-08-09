-- =============================================================================
-- Project Atlas — Step 14C-2E-C-B
-- Paddle Sandbox provider price + fail-closed active runtime config.
--
-- Seeds public catalog/config metadata only.
-- checkout_enabled remains FALSE (checkout unusable).
-- Does NOT enable checkout, grant Premium, create sessions, or store secrets.
-- =============================================================================

DO $$
DECLARE
  v_offer_id UUID;
  v_offer_count INTEGER;
  v_price_count INTEGER;
  v_cfg_count INTEGER;
  v_ext_price_count INTEGER;
  v_current_active_count INTEGER;
BEGIN
  -- -------------------------------------------------------------------------
  -- Pre-insert guards: logical offer
  -- -------------------------------------------------------------------------
  SELECT count(*)::integer
  INTO v_offer_count
  FROM private.billing_offers o
  WHERE o.offer_code = 'premium_monthly'
    AND o.atlas_plan_code = 'premium'
    AND o.billing_interval = 'month'
    AND o.interval_count = 1
    AND o.is_active IS TRUE;

  IF v_offer_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: expected exactly one active premium_monthly offer, found %',
      v_offer_count;
  END IF;

  SELECT o.id
  INTO v_offer_id
  FROM private.billing_offers o
  WHERE o.offer_code = 'premium_monthly'
    AND o.atlas_plan_code = 'premium'
    AND o.billing_interval = 'month'
    AND o.interval_count = 1
    AND o.is_active IS TRUE;

  IF v_offer_id IS NULL THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: premium_monthly offer id unresolved';
  END IF;

  -- -------------------------------------------------------------------------
  -- Pre-insert guards: provider prices must be empty for this seed scope
  -- -------------------------------------------------------------------------
  SELECT count(*)::integer
  INTO v_ext_price_count
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.external_price_id = 'pri_01kze90z27wy6m0fpxpebaewjv';

  IF v_ext_price_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: paddle/test external_price_id already present';
  END IF;

  SELECT count(*)::integer
  INTO v_current_active_count
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer_id
    AND p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active IS TRUE
    AND p.valid_to IS NULL;

  IF v_current_active_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: current active premium_monthly paddle/test price already present';
  END IF;

  -- -------------------------------------------------------------------------
  -- Pre-insert guards: runtime config must be empty
  -- -------------------------------------------------------------------------
  SELECT count(*)::integer
  INTO v_cfg_count
  FROM private.billing_runtime_config;

  IF v_cfg_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: billing_runtime_config must be empty before seed, found %',
      v_cfg_count;
  END IF;

  -- -------------------------------------------------------------------------
  -- Inserts (no ON CONFLICT)
  -- -------------------------------------------------------------------------
  INSERT INTO private.billing_provider_prices (
    offer_id,
    provider_code,
    provider_environment,
    external_product_id,
    external_price_id,
    base_amount,
    currency,
    valid_from,
    valid_to,
    is_active
  ) VALUES (
    v_offer_id,
    'paddle',
    'test',
    'pro_01kze8m55z7c6vdp4pe66bkrch',
    'pri_01kze90z27wy6m0fpxpebaewjv',
    11.99,
    'EUR',
    TIMESTAMPTZ '2026-08-09 00:00:00+00',
    NULL,
    TRUE
  );

  INSERT INTO private.billing_runtime_config (
    provider_code,
    provider_environment,
    checkout_enabled,
    payment_page_origin,
    checkout_path,
    return_path,
    is_active
  ) VALUES (
    'paddle',
    'test',
    FALSE,
    'https://project-atlas-bxh.pages.dev',
    '/billing/checkout',
    '/billing/return',
    TRUE
  );

  -- -------------------------------------------------------------------------
  -- Post-insert assertions
  -- -------------------------------------------------------------------------
  SELECT count(*)::integer
  INTO v_price_count
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer_id
    AND p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.external_product_id = 'pro_01kze8m55z7c6vdp4pe66bkrch'
    AND p.external_price_id = 'pri_01kze90z27wy6m0fpxpebaewjv'
    AND p.base_amount = 11.99
    AND p.currency = 'EUR'
    AND p.valid_from = TIMESTAMPTZ '2026-08-09 00:00:00+00'
    AND p.valid_to IS NULL
    AND p.is_active IS TRUE;

  IF v_price_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: post-insert provider price mismatch, found %',
      v_price_count;
  END IF;

  SELECT count(*)::integer
  INTO v_cfg_count
  FROM private.billing_runtime_config c
  WHERE c.provider_code = 'paddle'
    AND c.provider_environment = 'test'
    AND c.payment_page_origin = 'https://project-atlas-bxh.pages.dev'
    AND c.checkout_path = '/billing/checkout'
    AND c.return_path = '/billing/return'
    AND c.is_active IS TRUE
    AND c.checkout_enabled IS FALSE;

  IF v_cfg_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: post-insert runtime config mismatch, found %',
      v_cfg_count;
  END IF;

  SELECT count(*)::integer INTO v_cfg_count FROM private.billing_runtime_config;
  IF v_cfg_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'ATLAS_BILLING_SEED_ABORT: expected exactly one runtime config row, found %',
      v_cfg_count;
  END IF;
END;
$$;
