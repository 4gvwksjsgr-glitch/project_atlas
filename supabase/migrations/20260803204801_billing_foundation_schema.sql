-- =============================================================================
-- Project Atlas — Step 14C-1: billing foundation schema (provider-neutral)
-- Additive. Does not modify historical migrations.
-- CHECK definitivi e create_company: migration successiva.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- public.company_subscriptions.entitlement_origin
-- -----------------------------------------------------------------------------
ALTER TABLE public.company_subscriptions
  ADD COLUMN IF NOT EXISTS entitlement_origin TEXT NOT NULL DEFAULT 'none';

COMMENT ON COLUMN public.company_subscriptions.entitlement_origin IS
  'Step 14C-1: none | manual | internal_trial | provider. Fonte autorevole per ramo entitlement.';

UPDATE public.company_subscriptions cs
SET entitlement_origin = CASE
  WHEN cs.status = 'active' AND cs.plan_code = 'premium' THEN 'manual'
  WHEN cs.status = 'trialing' THEN 'internal_trial'
  ELSE 'none'
END
WHERE cs.entitlement_origin = 'none'
  AND (
    (cs.status = 'active' AND cs.plan_code = 'premium')
    OR cs.status = 'trialing'
  );

-- Soft enum (definitive CHECK in next migration after validation)
ALTER TABLE public.company_subscriptions
  DROP CONSTRAINT IF EXISTS company_subscriptions_entitlement_origin_allowed;

ALTER TABLE public.company_subscriptions
  ADD CONSTRAINT company_subscriptions_entitlement_origin_allowed
  CHECK (
    entitlement_origin IN ('none', 'manual', 'internal_trial', 'provider')
  )
  NOT VALID;

ALTER TABLE public.company_subscriptions
  VALIDATE CONSTRAINT company_subscriptions_entitlement_origin_allowed;

-- -----------------------------------------------------------------------------
-- private.company_billing (1:1 operational)
-- -----------------------------------------------------------------------------
CREATE TABLE private.company_billing (
  company_id UUID PRIMARY KEY
    REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_code TEXT NULL,
  external_customer_id TEXT NULL,
  external_subscription_id TEXT NULL,
  external_price_id TEXT NULL,
  subscription_status TEXT NOT NULL DEFAULT 'none',
  payment_status TEXT NOT NULL DEFAULT 'none',
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
  current_period_start TIMESTAMPTZ NULL,
  current_period_end TIMESTAMPTZ NULL,
  canceled_at TIMESTAMPTZ NULL,
  provider_access_status TEXT NOT NULL DEFAULT 'none',
  provider_access_ends_at TIMESTAMPTZ NULL,
  grace_ends_at TIMESTAMPTZ NULL,
  sync_status TEXT NOT NULL DEFAULT 'idle',
  last_sync_result TEXT NOT NULL DEFAULT 'none',
  last_synced_at TIMESTAMPTZ NULL,
  last_sync_error_sanitized TEXT NULL,
  provider_object_version TEXT NULL,
  provider_object_version_at TIMESTAMPTZ NULL,
  provider_subscription_raw TEXT NULL,
  provider_payment_raw TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE private.company_billing IS
  'Step 14C-1: sync billing provider-neutral 1:1. Non esposto ai client.';
COMMENT ON COLUMN private.company_billing.provider_object_version IS
  'Opaca: interpretata solo dall''adapter. Non ordinare lessicograficamente nel DB.';
COMMENT ON COLUMN private.company_billing.provider_access_status IS
  'Accesso applicativo normalizzato dall''adapter: none|entitled|grace|blocked|ended|unknown.';

CREATE TRIGGER set_company_billing_updated_at
  BEFORE UPDATE ON private.company_billing
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX company_billing_provider_subscription_uidx
  ON private.company_billing (provider_code, external_subscription_id)
  WHERE provider_code IS NOT NULL
    AND external_subscription_id IS NOT NULL;

CREATE UNIQUE INDEX company_billing_provider_customer_uidx
  ON private.company_billing (provider_code, external_customer_id)
  WHERE provider_code IS NOT NULL
    AND external_customer_id IS NOT NULL;

-- Seed idempotent for existing companies
INSERT INTO private.company_billing (company_id)
SELECT c.id
FROM public.companies c
ON CONFLICT (company_id) DO NOTHING;

ALTER TABLE private.company_billing OWNER TO postgres;

ALTER TABLE private.company_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.company_billing FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.company_billing FROM PUBLIC;
REVOKE ALL ON TABLE private.company_billing FROM anon;
REVOKE ALL ON TABLE private.company_billing FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.billing_provider_events (idempotent inbox; no handler in 14C-1)
-- -----------------------------------------------------------------------------
CREATE TABLE private.billing_provider_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_code TEXT NOT NULL,
  external_event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  company_id UUID NULL
    REFERENCES public.companies (id) ON DELETE SET NULL,
  external_subscription_id TEXT NULL,
  provider_created_at TIMESTAMPTZ NULL,
  provider_object_version TEXT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ NULL,
  processing_status TEXT NOT NULL DEFAULT 'received',
  verification_status TEXT NOT NULL DEFAULT 'unverified',
  signature_verified_at TIMESTAMPTZ NULL,
  payload_hash TEXT NOT NULL,
  payload_json JSONB NULL,
  retention_expires_at TIMESTAMPTZ NOT NULL,
  error_sanitized TEXT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at TIMESTAMPTZ NULL,
  CONSTRAINT billing_provider_events_provider_event_uidx
    UNIQUE (provider_code, external_event_id)
);

COMMENT ON TABLE private.billing_provider_events IS
  'Step 14C-1: inbox eventi provider. Tombstone dopo retention: payload_json NULL, riga e UNIQUE restano.';
COMMENT ON COLUMN private.billing_provider_events.payload_hash IS
  'Hash del raw body. Resta NOT NULL anche dopo purge del JSON.';
COMMENT ON COLUMN private.billing_provider_events.provider_object_version IS
  'Opaca; interpretata dall''adapter.';

ALTER TABLE private.billing_provider_events OWNER TO postgres;

ALTER TABLE private.billing_provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_provider_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.billing_provider_events FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_provider_events FROM anon;
REVOKE ALL ON TABLE private.billing_provider_events FROM authenticated;
