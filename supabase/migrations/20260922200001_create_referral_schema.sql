-- =============================================================================
-- Project Atlas — Working Step 17: referral program foundation (schema)
-- Additive. Attribution + reward ledger only. No Paddle / entitlement mutation.
-- Referral codes are shareable attribution tokens (not auth secrets).
-- =============================================================================

CREATE TABLE public.company_referral_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES public.profiles (id),
  -- URL-safe cryptographically random token returned to the owner for sharing.
  code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES public.profiles (id),
  CONSTRAINT company_referral_codes_code_shape
    CHECK (code ~ '^[A-Za-z0-9_-]{16,64}$'),
  CONSTRAINT company_referral_codes_revoked_pair
    CHECK (
      (revoked_at IS NULL AND revoked_by IS NULL)
      OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    )
);

COMMENT ON TABLE public.company_referral_codes IS
  'Per-company referral codes. One active code per company. Codes are attribution tokens, not credentials.';

CREATE UNIQUE INDEX company_referral_codes_code_uidx
  ON public.company_referral_codes (code);

-- At most one active (non-revoked) code per company.
CREATE UNIQUE INDEX company_referral_codes_active_company_uidx
  ON public.company_referral_codes (company_id)
  WHERE revoked_at IS NULL;

CREATE INDEX company_referral_codes_company_idx
  ON public.company_referral_codes (company_id);

CREATE TABLE public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_code_id UUID NOT NULL
    REFERENCES public.company_referral_codes (id) ON DELETE RESTRICT,
  referring_company_id UUID NOT NULL
    REFERENCES public.companies (id) ON DELETE CASCADE,
  referred_user_id UUID NOT NULL
    REFERENCES public.profiles (id),
  referred_company_id UUID
    REFERENCES public.companies (id) ON DELETE SET NULL,
  -- claimed | qualified | rewarded | not_rewarded_limit_reached | rejected
  status TEXT NOT NULL,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  qualified_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  reject_reason TEXT,
  CONSTRAINT referrals_status_allowed
    CHECK (status IN (
      'claimed',
      'qualified',
      'rewarded',
      'not_rewarded_limit_reached',
      'rejected'
    )),
  CONSTRAINT referrals_qualified_pair
    CHECK (
      (qualified_at IS NULL AND referred_company_id IS NULL
        AND status IN ('claimed', 'rejected'))
      OR (qualified_at IS NOT NULL AND referred_company_id IS NOT NULL
        AND status IN (
          'qualified',
          'rewarded',
          'not_rewarded_limit_reached'
        ))
      OR (status = 'rejected')
    ),
  CONSTRAINT referrals_reject_reason_length
    CHECK (reject_reason IS NULL OR char_length(reject_reason) <= 120)
);

COMMENT ON TABLE public.referrals IS
  'Referral attribution. One referred user may reward at most one referring company.';

-- One referred user → at most one referral row (no multi-referrer).
CREATE UNIQUE INDEX referrals_referred_user_uidx
  ON public.referrals (referred_user_id);

CREATE INDEX referrals_referring_company_idx
  ON public.referrals (referring_company_id, claimed_at DESC);

CREATE INDEX referrals_code_idx
  ON public.referrals (referral_code_id);

CREATE TABLE public.referral_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_id UUID NOT NULL UNIQUE
    REFERENCES public.referrals (id) ON DELETE RESTRICT,
  referring_company_id UUID NOT NULL
    REFERENCES public.companies (id) ON DELETE CASCADE,
  -- Deterministic 1..5 slot per company: structural max-five even under races.
  reward_slot SMALLINT NOT NULL,
  -- Always exactly 1 Premium month credit per rewarded referral.
  reward_months INTEGER NOT NULL,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- pending = earned, awaiting provider-safe redemption (Step 17 does not redeem).
  redemption_status TEXT NOT NULL DEFAULT 'pending',
  redeemed_at TIMESTAMPTZ,
  CONSTRAINT referral_rewards_months_one
    CHECK (reward_months = 1),
  CONSTRAINT referral_rewards_slot_range
    CHECK (reward_slot >= 1 AND reward_slot <= 5),
  CONSTRAINT referral_rewards_redemption_allowed
    CHECK (redemption_status IN ('pending', 'redeemed', 'void')),
  CONSTRAINT referral_rewards_redeemed_pair
    CHECK (
      (redeemed_at IS NULL AND redemption_status IS DISTINCT FROM 'redeemed')
      OR (redeemed_at IS NOT NULL AND redemption_status = 'redeemed')
    )
);

COMMENT ON TABLE public.referral_rewards IS
  'Immutable ledger of earned Premium-month credits. Redemption is deferred when provider billing would diverge.';

-- At most one non-void reward per slot per company => never more than 5 live rewards.
CREATE UNIQUE INDEX referral_rewards_company_slot_uidx
  ON public.referral_rewards (referring_company_id, reward_slot)
  WHERE redemption_status IS DISTINCT FROM 'void';

CREATE INDEX referral_rewards_company_earned_idx
  ON public.referral_rewards (referring_company_id, earned_at DESC);

-- Cap of 5 rewarded months per referring company (excluding void).
CREATE OR REPLACE FUNCTION private.referral_reward_count(p_company_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT count(*)::INTEGER
  FROM public.referral_rewards r
  WHERE r.referring_company_id = p_company_id
    AND r.redemption_status IS DISTINCT FROM 'void';
$$;

ALTER FUNCTION private.referral_reward_count(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.referral_reward_count(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.referral_reward_count(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.referral_reward_count(UUID) FROM authenticated;

ALTER TABLE public.company_referral_codes OWNER TO postgres;
ALTER TABLE public.referrals OWNER TO postgres;
ALTER TABLE public.referral_rewards OWNER TO postgres;

ALTER TABLE public.company_referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_referral_codes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals FORCE ROW LEVEL SECURITY;
ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_rewards FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.company_referral_codes FROM PUBLIC;
REVOKE ALL ON TABLE public.company_referral_codes FROM anon;
REVOKE ALL ON TABLE public.company_referral_codes FROM authenticated;

REVOKE ALL ON TABLE public.referrals FROM PUBLIC;
REVOKE ALL ON TABLE public.referrals FROM anon;
REVOKE ALL ON TABLE public.referrals FROM authenticated;

REVOKE ALL ON TABLE public.referral_rewards FROM PUBLIC;
REVOKE ALL ON TABLE public.referral_rewards FROM anon;
REVOKE ALL ON TABLE public.referral_rewards FROM authenticated;

-- No client policies: all access via SECURITY DEFINER RPCs (invite pattern).
