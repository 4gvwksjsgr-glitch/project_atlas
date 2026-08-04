-- =============================================================================
-- Project Atlas — Step 14C-2B: versioned billing catalog (offers + provider prices)
-- Additive. Seeds logical premium_monthly only. No fabricated Paddle IDs.
-- =============================================================================

CREATE TABLE private.billing_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_code TEXT NOT NULL,
  atlas_plan_code TEXT NOT NULL
    REFERENCES public.plans (code),
  billing_interval TEXT NOT NULL,
  interval_count INTEGER NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_offers_offer_code_normalized
    CHECK (
      offer_code = lower(btrim(offer_code))
      AND char_length(offer_code) > 0
    ),
  CONSTRAINT billing_offers_offer_code_unique UNIQUE (offer_code),
  CONSTRAINT billing_offers_interval_allowed
    CHECK (billing_interval = 'month'),
  CONSTRAINT billing_offers_interval_count_allowed
    CHECK (interval_count = 1),
  CONSTRAINT billing_offers_atlas_plan_premium
    CHECK (atlas_plan_code = 'premium')
);

COMMENT ON TABLE private.billing_offers IS
  'Step 14C-2B: logical Atlas commercial offers (no external provider IDs).';

CREATE TRIGGER set_billing_offers_updated_at
  BEFORE UPDATE ON private.billing_offers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

INSERT INTO private.billing_offers (
  offer_code,
  atlas_plan_code,
  billing_interval,
  interval_count,
  is_active
)
SELECT
  'premium_monthly',
  'premium',
  'month',
  1,
  TRUE
WHERE EXISTS (SELECT 1 FROM public.plans p WHERE p.code = 'premium')
ON CONFLICT (offer_code) DO NOTHING;

ALTER TABLE private.billing_offers OWNER TO postgres;
ALTER TABLE private.billing_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_offers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.billing_offers FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_offers FROM anon;
REVOKE ALL ON TABLE private.billing_offers FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.billing_provider_prices (append-only historical fields)
-- -----------------------------------------------------------------------------
CREATE TABLE private.billing_provider_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID NOT NULL
    REFERENCES private.billing_offers (id),
  provider_code TEXT NOT NULL,
  provider_environment TEXT NOT NULL,
  external_product_id TEXT NOT NULL,
  external_price_id TEXT NOT NULL,
  base_amount NUMERIC(12, 2) NOT NULL,
  currency TEXT NOT NULL,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_to TIMESTAMPTZ NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_provider_prices_provider_code_normalized
    CHECK (
      provider_code = lower(btrim(provider_code))
      AND char_length(provider_code) > 0
    ),
  CONSTRAINT billing_provider_prices_environment_allowed
    CHECK (provider_environment IN ('test', 'live')),
  CONSTRAINT billing_provider_prices_external_ids_not_empty
    CHECK (
      char_length(btrim(external_product_id)) > 0
      AND char_length(btrim(external_price_id)) > 0
    ),
  CONSTRAINT billing_provider_prices_base_amount_positive
    CHECK (base_amount > 0),
  CONSTRAINT billing_provider_prices_currency_iso
    CHECK (currency ~ '^[A-Z]{3}$'),
  CONSTRAINT billing_provider_prices_valid_range
    CHECK (valid_to IS NULL OR valid_to > valid_from),
  CONSTRAINT billing_provider_prices_external_price_uidx
    UNIQUE (provider_code, provider_environment, external_price_id)
);

COMMENT ON TABLE private.billing_provider_prices IS
  'Step 14C-2B: versioned provider price rows. Historical fields immutable after insert.';

CREATE TRIGGER set_billing_provider_prices_updated_at
  BEFORE UPDATE ON private.billing_provider_prices
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- At most one current active price per offer+provider+environment.
CREATE UNIQUE INDEX billing_provider_prices_current_active_uidx
  ON private.billing_provider_prices (
    offer_id,
    provider_code,
    provider_environment
  )
  WHERE is_active AND valid_to IS NULL;

CREATE OR REPLACE FUNCTION private.billing_provider_prices_immutable_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.offer_id IS DISTINCT FROM OLD.offer_id
    OR NEW.provider_code IS DISTINCT FROM OLD.provider_code
    OR NEW.provider_environment IS DISTINCT FROM OLD.provider_environment
    OR NEW.external_product_id IS DISTINCT FROM OLD.external_product_id
    OR NEW.external_price_id IS DISTINCT FROM OLD.external_price_id
    OR NEW.base_amount IS DISTINCT FROM OLD.base_amount
    OR NEW.currency IS DISTINCT FROM OLD.currency
    OR NEW.valid_from IS DISTINCT FROM OLD.valid_from
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_PRICE_IMMUTABLE';
  END IF;

  -- No reactivation.
  IF OLD.is_active IS DISTINCT FROM TRUE AND NEW.is_active IS TRUE THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_PRICE_REACTIVATE_FORBIDDEN';
  END IF;

  -- valid_to: only NULL → timestamp; never clear or change once set.
  IF OLD.valid_to IS NOT NULL AND NEW.valid_to IS DISTINCT FROM OLD.valid_to THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_PRICE_VALID_TO_LOCKED';
  END IF;

  IF OLD.valid_to IS NULL
    AND NEW.valid_to IS NOT NULL
    AND NEW.valid_to <= OLD.valid_from
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_PRICE_VALID_TO_INVALID';
  END IF;

  RETURN NEW;
END;
$$;

ALTER FUNCTION private.billing_provider_prices_immutable_guard() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_provider_prices_immutable_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_provider_prices_immutable_guard() FROM anon;
REVOKE ALL ON FUNCTION private.billing_provider_prices_immutable_guard() FROM authenticated;

CREATE TRIGGER billing_provider_prices_immutable_guard
  BEFORE UPDATE ON private.billing_provider_prices
  FOR EACH ROW
  EXECUTE FUNCTION private.billing_provider_prices_immutable_guard();

ALTER TABLE private.billing_provider_prices OWNER TO postgres;
ALTER TABLE private.billing_provider_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_provider_prices FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.billing_provider_prices FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_provider_prices FROM anon;
REVOKE ALL ON TABLE private.billing_provider_prices FROM authenticated;
