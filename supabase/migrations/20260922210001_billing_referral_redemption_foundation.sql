-- =============================================================================
-- Project Atlas — Step 18B: referral Premium-month redemption foundation
-- Additive. Kill switch DEFAULT FALSE. No remote enablement in this step.
-- Provider mechanism (locked Step 18A): PATCH next_billed_at + do_not_bill.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Runtime kill switch (fail-closed)
-- -----------------------------------------------------------------------------
ALTER TABLE private.billing_runtime_config
  ADD COLUMN IF NOT EXISTS referral_redemption_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN private.billing_runtime_config.referral_redemption_enabled IS
  '18B: referral reward → Paddle next_billed_at redemption kill switch. '
  'DEFAULT FALSE. Independent of checkout_enabled and processor_enabled. '
  'Outbound provider mutation is dormant unless TRUE on the active paddle/test row.';

UPDATE private.billing_runtime_config
SET referral_redemption_enabled = FALSE
WHERE referral_redemption_enabled IS DISTINCT FROM FALSE;

-- -----------------------------------------------------------------------------
-- Expand referral_rewards.redemption_status: pending | applying | redeemed | void
-- -----------------------------------------------------------------------------
ALTER TABLE public.referral_rewards
  DROP CONSTRAINT IF EXISTS referral_rewards_redemption_allowed;

ALTER TABLE public.referral_rewards
  ADD CONSTRAINT referral_rewards_redemption_allowed
  CHECK (redemption_status IN ('pending', 'applying', 'redeemed', 'void'));

COMMENT ON COLUMN public.referral_rewards.redemption_status IS
  'pending=earned; applying=owned by open redemption op; redeemed=provider-confirmed; void=admin/abuse only. '
  'Transient provider failure must never void an earned reward.';

-- -----------------------------------------------------------------------------
-- Redemption operations (private; no client access)
-- -----------------------------------------------------------------------------
CREATE TABLE private.billing_referral_redemption_operations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  -- claimed | previewing | ready_to_apply | provider_accepted | needs_reconcile
  -- | retryable_failed | confirmed | terminal_failed | blocked
  status TEXT NOT NULL,
  reward_count INTEGER NOT NULL,
  reward_ids UUID[] NOT NULL,
  expected_old_next_billed_at TIMESTAMPTZ,
  target_next_billed_at TIMESTAMPTZ,
  -- Snapshot of company_billing.external_subscription_id at claim/eligibility time.
  -- Used only to detect subscription replacement; authoritative link stays on company_billing.
  provider_subscription_id_snapshot TEXT,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  previewed_at TIMESTAMPTZ,
  provider_accepted_at TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  last_attempt_at TIMESTAMPTZ,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  -- Safe Atlas classification (no raw Paddle bodies).
  last_error_code TEXT,
  block_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_referral_redemption_ops_status_allowed
    CHECK (status IN (
      'claimed',
      'previewing',
      'ready_to_apply',
      'provider_accepted',
      'needs_reconcile',
      'retryable_failed',
      'confirmed',
      'terminal_failed',
      'blocked'
    )),
  CONSTRAINT billing_referral_redemption_ops_reward_count_positive
    CHECK (reward_count >= 1 AND reward_count <= 5),
  CONSTRAINT billing_referral_redemption_ops_reward_ids_len
    CHECK (cardinality(reward_ids) = reward_count),
  CONSTRAINT billing_referral_redemption_ops_attempt_nonneg
    CHECK (attempt_count >= 0)
);

COMMENT ON TABLE private.billing_referral_redemption_operations IS
  '18B: server-owned batch redemption of pending referral_rewards via Paddle next_billed_at extension. '
  'At most one open operation per company. Confirmation requires exact target match.';

CREATE UNIQUE INDEX billing_referral_redemption_ops_one_open_company_uidx
  ON private.billing_referral_redemption_operations (company_id)
  WHERE status NOT IN ('confirmed', 'terminal_failed');

CREATE INDEX billing_referral_redemption_ops_company_claimed_idx
  ON private.billing_referral_redemption_operations (company_id, claimed_at DESC);

CREATE INDEX billing_referral_redemption_ops_open_status_idx
  ON private.billing_referral_redemption_operations (status)
  WHERE status NOT IN ('confirmed', 'terminal_failed');

ALTER TABLE private.billing_referral_redemption_operations OWNER TO postgres;
ALTER TABLE private.billing_referral_redemption_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_referral_redemption_operations FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE private.billing_referral_redemption_operations FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_referral_redemption_operations FROM anon;
REVOKE ALL ON TABLE private.billing_referral_redemption_operations FROM authenticated;

-- -----------------------------------------------------------------------------
-- Link rewards → operation (nullable until claimed)
-- -----------------------------------------------------------------------------
ALTER TABLE public.referral_rewards
  ADD COLUMN IF NOT EXISTS redemption_operation_id UUID
    REFERENCES private.billing_referral_redemption_operations (id)
    ON DELETE SET NULL;

COMMENT ON COLUMN public.referral_rewards.redemption_operation_id IS
  '18B: open/confirmed redemption operation owning this reward while applying/redeemed. '
  'Client cannot set. A reward must never belong to two operations.';

CREATE INDEX referral_rewards_redemption_operation_id_idx
  ON public.referral_rewards (redemption_operation_id)
  WHERE redemption_operation_id IS NOT NULL;

-- redeemed_pair still: redeemed_at set iff status = redeemed
ALTER TABLE public.referral_rewards
  DROP CONSTRAINT IF EXISTS referral_rewards_redeemed_pair;

ALTER TABLE public.referral_rewards
  ADD CONSTRAINT referral_rewards_redeemed_pair
  CHECK (
    (redeemed_at IS NULL AND redemption_status IS DISTINCT FROM 'redeemed')
    OR (redeemed_at IS NOT NULL AND redemption_status = 'redeemed')
  );

-- applying rewards must reference an operation
ALTER TABLE public.referral_rewards
  DROP CONSTRAINT IF EXISTS referral_rewards_applying_has_op;

ALTER TABLE public.referral_rewards
  ADD CONSTRAINT referral_rewards_applying_has_op
  CHECK (
    redemption_status IS DISTINCT FROM 'applying'
    OR redemption_operation_id IS NOT NULL
  );
