-- =============================================================================
-- Project Atlas — Step 14C-2B: private.billing_runtime_config
-- Additive. Zero active rows = checkout disabled (fail-closed).
-- No seed of active config without a real approved payment_page_origin.
-- =============================================================================

CREATE TABLE private.billing_runtime_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_code TEXT NOT NULL,
  provider_environment TEXT NOT NULL,
  checkout_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  payment_page_origin TEXT NOT NULL,
  checkout_path TEXT NOT NULL,
  return_path TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_runtime_config_provider_code_normalized
    CHECK (
      provider_code = lower(btrim(provider_code))
      AND char_length(provider_code) > 0
    ),
  CONSTRAINT billing_runtime_config_environment_allowed
    CHECK (provider_environment IN ('test', 'live')),
  CONSTRAINT billing_runtime_config_origin_shape
    CHECK (
      payment_page_origin = btrim(payment_page_origin)
      AND payment_page_origin ~ '^https?://[^/?#]+$'
      AND position('?' IN payment_page_origin) = 0
      AND position('#' IN payment_page_origin) = 0
    ),
  CONSTRAINT billing_runtime_config_checkout_path_allowed
    CHECK (checkout_path = '/billing/checkout'),
  CONSTRAINT billing_runtime_config_return_path_allowed
    CHECK (return_path = '/billing/return'),
  CONSTRAINT billing_runtime_config_paths_distinct
    CHECK (checkout_path IS DISTINCT FROM return_path)
);

COMMENT ON TABLE private.billing_runtime_config IS
  'Step 14C-2B: non-secret billing runtime. At most one is_active row; zero = checkout off.';

CREATE TRIGGER set_billing_runtime_config_updated_at
  BEFORE UPDATE ON private.billing_runtime_config
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- At most one active configuration (not exactly one).
CREATE UNIQUE INDEX billing_runtime_config_one_active_uidx
  ON private.billing_runtime_config ((TRUE))
  WHERE is_active;

ALTER TABLE private.billing_runtime_config OWNER TO postgres;

ALTER TABLE private.billing_runtime_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_runtime_config FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.billing_runtime_config FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_runtime_config FROM anon;
REVOKE ALL ON TABLE private.billing_runtime_config FROM authenticated;
