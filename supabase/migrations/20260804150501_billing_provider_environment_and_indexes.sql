-- =============================================================================
-- Project Atlas — Step 14C-2B: provider_environment + ambient unique indexes
-- Additive. Does not modify historical migrations.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.company_billing.provider_environment
-- Nullable only while fully unlinked.
-- -----------------------------------------------------------------------------
ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS provider_environment TEXT;

ALTER TABLE private.company_billing
  DROP CONSTRAINT IF EXISTS company_billing_provider_environment_shape;

ALTER TABLE private.company_billing
  ADD CONSTRAINT company_billing_provider_environment_shape
  CHECK (
    (
      provider_code IS NULL
      AND provider_environment IS NULL
      AND external_customer_id IS NULL
      AND external_subscription_id IS NULL
      AND external_price_id IS NULL
    )
    OR (
      provider_code IS NOT NULL
      AND provider_environment IS NOT NULL
      AND provider_environment IN ('test', 'live')
    )
  );

COMMENT ON COLUMN private.company_billing.provider_environment IS
  'Step 14C-2B: test|live when linked; NULL only when fully unlinked.';

-- Existing 14C-1 rows remain unlinked → provider_environment stays NULL.

-- Drop legacy UNIQUE indexes (created as indexes, not table constraints).
DROP INDEX IF EXISTS private.company_billing_provider_subscription_uidx;
DROP INDEX IF EXISTS private.company_billing_provider_customer_uidx;

CREATE UNIQUE INDEX company_billing_provider_subscription_uidx
  ON private.company_billing (
    provider_code,
    provider_environment,
    external_subscription_id
  )
  WHERE provider_code IS NOT NULL
    AND provider_environment IS NOT NULL
    AND external_subscription_id IS NOT NULL;

CREATE UNIQUE INDEX company_billing_provider_customer_uidx
  ON private.company_billing (
    provider_code,
    provider_environment,
    external_customer_id
  )
  WHERE provider_code IS NOT NULL
    AND provider_environment IS NOT NULL
    AND external_customer_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- private.billing_provider_events.provider_environment (NOT NULL)
-- -----------------------------------------------------------------------------
ALTER TABLE private.billing_provider_events
  ADD COLUMN IF NOT EXISTS provider_environment TEXT;

-- Structurally safe if unexpected rows exist: backfill then enforce NOT NULL.
UPDATE private.billing_provider_events
SET provider_environment = 'test'
WHERE provider_environment IS NULL;

ALTER TABLE private.billing_provider_events
  ALTER COLUMN provider_environment SET NOT NULL;

ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_environment_allowed;

ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_environment_allowed
  CHECK (provider_environment IN ('test', 'live'));

COMMENT ON COLUMN private.billing_provider_events.provider_environment IS
  'Step 14C-2B: test|live. Part of provider event uniqueness.';

-- Legacy UNIQUE was a table constraint.
ALTER TABLE private.billing_provider_events
  DROP CONSTRAINT IF EXISTS billing_provider_events_provider_event_uidx;

ALTER TABLE private.billing_provider_events
  ADD CONSTRAINT billing_provider_events_provider_event_uidx
    UNIQUE (provider_code, provider_environment, external_event_id);
