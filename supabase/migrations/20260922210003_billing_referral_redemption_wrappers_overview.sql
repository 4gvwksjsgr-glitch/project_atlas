-- =============================================================================
-- Project Atlas — Step 18B: redemption public wrappers, overview, confirm hook
-- =============================================================================

-- -----------------------------------------------------------------------------
-- service_role wrappers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_referral_redemption_operation_server(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  outcome TEXT,
  operation_id UUID,
  reward_count INTEGER,
  reward_ids UUID[],
  expected_old_next_billed_at TIMESTAMPTZ,
  target_next_billed_at TIMESTAMPTZ,
  provider_subscription_id TEXT,
  operation_status TEXT,
  error_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM private.claim_referral_redemption_operation(p_company_id, p_now);
END;
$$;

ALTER FUNCTION public.claim_referral_redemption_operation_server(UUID, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_referral_redemption_operation_server(UUID, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_referral_redemption_operation_server(UUID, TIMESTAMPTZ)
  TO service_role;

CREATE OR REPLACE FUNCTION public.update_referral_redemption_operation_status_server(
  p_operation_id UUID,
  p_status TEXT,
  p_error_code TEXT DEFAULT NULL,
  p_set_previewed BOOLEAN DEFAULT FALSE,
  p_set_provider_accepted BOOLEAN DEFAULT FALSE,
  p_bump_attempt BOOLEAN DEFAULT FALSE,
  p_expected_old TIMESTAMPTZ DEFAULT NULL,
  p_target TIMESTAMPTZ DEFAULT NULL,
  p_subscription_snapshot TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN private.update_referral_redemption_operation_status(
    p_operation_id, p_status, p_error_code, p_set_previewed, p_set_provider_accepted,
    p_bump_attempt, p_expected_old, p_target, p_subscription_snapshot
  );
END;
$$;

ALTER FUNCTION public.update_referral_redemption_operation_status_server(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_referral_redemption_operation_status_server(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_referral_redemption_operation_status_server(
  UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.confirm_referral_redemption_operation_server(
  p_company_id UUID,
  p_observed_next_billed_at TIMESTAMPTZ DEFAULT NULL,
  p_provider_subscription_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  outcome TEXT,
  operation_id UUID,
  rewards_redeemed INTEGER,
  error_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM private.confirm_referral_redemption_operation(
    p_company_id, p_observed_next_billed_at, p_provider_subscription_id
  );
END;
$$;

ALTER FUNCTION public.confirm_referral_redemption_operation_server(UUID, TIMESTAMPTZ, TEXT)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.confirm_referral_redemption_operation_server(UUID, TIMESTAMPTZ, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_referral_redemption_operation_server(UUID, TIMESTAMPTZ, TEXT)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_referral_redemption_operation_server(
  p_operation_id UUID,
  p_error_code TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN private.abort_referral_redemption_operation(p_operation_id, p_error_code);
END;
$$;

ALTER FUNCTION public.abort_referral_redemption_operation_server(UUID, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.abort_referral_redemption_operation_server(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.abort_referral_redemption_operation_server(UUID, TEXT)
  TO service_role;

CREATE OR REPLACE FUNCTION public.get_open_referral_redemption_operation_server(
  p_company_id UUID
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  status TEXT,
  reward_count INTEGER,
  reward_ids UUID[],
  expected_old_next_billed_at TIMESTAMPTZ,
  target_next_billed_at TIMESTAMPTZ,
  provider_subscription_id_snapshot TEXT,
  last_error_code TEXT,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_op private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  v_op := private.get_open_referral_redemption_operation(p_company_id);
  IF v_op.id IS NULL THEN
    RETURN;
  END IF;
  id := v_op.id;
  company_id := v_op.company_id;
  status := v_op.status;
  reward_count := v_op.reward_count;
  reward_ids := v_op.reward_ids;
  expected_old_next_billed_at := v_op.expected_old_next_billed_at;
  target_next_billed_at := v_op.target_next_billed_at;
  provider_subscription_id_snapshot := v_op.provider_subscription_id_snapshot;
  last_error_code := v_op.last_error_code;
  attempt_count := v_op.attempt_count;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION public.get_open_referral_redemption_operation_server(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_open_referral_redemption_operation_server(UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_open_referral_redemption_operation_server(UUID)
  TO service_role;

-- -----------------------------------------------------------------------------
-- Owner retry facade: heal/return open op; never chooses N or target
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retry_referral_redemption(
  p_company_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  operation_id UUID,
  operation_status TEXT,
  error_code TEXT,
  pending_months INTEGER,
  applying_months INTEGER,
  redeemed_months INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_claim RECORD;
  v_open private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  PERFORM private.assert_company_owner(p_company_id);

  IF NOT private.is_referral_redemption_enabled() THEN
    outcome := 'disabled';
    error_code := 'ATLAS_REFERRAL_REDEMPTION_DISABLED';
    RETURN NEXT;
    RETURN;
  END IF;

  v_open := private.get_open_referral_redemption_operation(p_company_id);
  IF v_open.id IS NOT NULL THEN
    outcome := 'existing_open';
    operation_id := v_open.id;
    operation_status := v_open.status;
    error_code := v_open.last_error_code;
  ELSE
    SELECT * INTO v_claim
    FROM private.claim_referral_redemption_operation(p_company_id, now());
    outcome := v_claim.outcome;
    operation_id := v_claim.operation_id;
    operation_status := v_claim.operation_status;
    error_code := v_claim.error_code;
  END IF;

  SELECT
    count(*) FILTER (WHERE r.redemption_status = 'pending'),
    count(*) FILTER (WHERE r.redemption_status = 'applying'),
    count(*) FILTER (WHERE r.redemption_status = 'redeemed')
  INTO pending_months, applying_months, redeemed_months
  FROM public.referral_rewards r
  WHERE r.referring_company_id = p_company_id;

  RETURN NEXT;
END;
$$;

ALTER FUNCTION public.retry_referral_redemption(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.retry_referral_redemption(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retry_referral_redemption(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- Extend get_referral_overview with redemption aggregates (privacy-safe)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_referral_overview(UUID);

CREATE OR REPLACE FUNCTION public.get_referral_overview(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  code TEXT,
  rewarded_count INTEGER,
  max_rewards INTEGER,
  pending_redemption_months INTEGER,
  applying_redemption_months INTEGER,
  redeemed_redemption_months INTEGER,
  redemption_block_reason TEXT,
  open_operation_status TEXT,
  is_owner BOOLEAN,
  items JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_is_owner BOOLEAN;
  v_is_member BOOLEAN;
  v_code TEXT;
  v_items JSONB := '[]'::JSONB;
  v_elig RECORD;
  v_open private.billing_referral_redemption_operations%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  v_is_member := private.is_company_member(p_company_id, v_uid);
  IF NOT v_is_member THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INSUFFICIENT_PRIVILEGES';
  END IF;

  v_is_owner := private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    v_uid
  );

  IF v_is_owner THEN
    SELECT c.code INTO v_code
    FROM public.company_referral_codes c
    WHERE c.company_id = p_company_id
      AND c.revoked_at IS NULL
    LIMIT 1;

    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'referral_id', r.id,
        'status', r.status,
        'claimed_at', r.claimed_at,
        'qualified_at', r.qualified_at,
        'label', 'friend'
      )
      ORDER BY r.claimed_at DESC
    ), '[]'::JSONB)
    INTO v_items
    FROM public.referrals r
    WHERE r.referring_company_id = p_company_id;
  END IF;

  v_open := private.get_open_referral_redemption_operation(p_company_id);
  SELECT * INTO v_elig
  FROM private.referral_redemption_eligibility(p_company_id, now());

  RETURN QUERY
  SELECT
    p_company_id,
    CASE WHEN v_is_owner THEN v_code ELSE NULL END,
    private.referral_reward_count(p_company_id),
    5,
    (
      SELECT count(*)::INTEGER
      FROM public.referral_rewards rw
      WHERE rw.referring_company_id = p_company_id
        AND rw.redemption_status = 'pending'
    ),
    (
      SELECT count(*)::INTEGER
      FROM public.referral_rewards rw
      WHERE rw.referring_company_id = p_company_id
        AND rw.redemption_status = 'applying'
    ),
    (
      SELECT count(*)::INTEGER
      FROM public.referral_rewards rw
      WHERE rw.referring_company_id = p_company_id
        AND rw.redemption_status = 'redeemed'
    ),
    CASE
      WHEN v_is_owner AND v_open.id IS NOT NULL THEN v_open.last_error_code
      WHEN v_is_owner AND NOT v_elig.eligible THEN v_elig.block_reason
      ELSE NULL
    END,
    CASE WHEN v_is_owner THEN v_open.status ELSE NULL END,
    v_is_owner,
    CASE WHEN v_is_owner THEN v_items ELSE '[]'::JSONB END;
END;
$$;

COMMENT ON FUNCTION public.get_referral_overview(UUID) IS
  '18B: owner sees code/history + redemption aggregates/block reason; members see counts only.';

ALTER FUNCTION public.get_referral_overview(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_referral_overview(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_referral_overview(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- Confirm hook after authoritative subscription apply
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.maybe_confirm_referral_redemption_after_billing_apply(
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_bill private.company_billing%ROWTYPE;
BEGIN
  IF p_company_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = p_company_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Exact target confirmation uses Atlas entitlement source field current_period_end
  -- (Paddle current_billing_period.ends_at), which must move with next_billed_at.
  PERFORM private.confirm_referral_redemption_operation(
    p_company_id,
    v_bill.current_period_end,
    v_bill.external_subscription_id
  );
END;
$$;

ALTER FUNCTION private.maybe_confirm_referral_redemption_after_billing_apply(UUID)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.maybe_confirm_referral_redemption_after_billing_apply(UUID)
  FROM PUBLIC, anon, authenticated;
