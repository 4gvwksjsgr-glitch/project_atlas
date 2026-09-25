-- =============================================================================
-- Project Atlas — Step 18B closure: confirm trigger harden + auto-redeem evaluate
-- Additive. Kill switch remains DEFAULT FALSE. No remote enablement.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Harden confirm trigger: require provider-authoritative fence movement.
-- Clients cannot UPDATE private.company_billing (REVOKE ALL + FORCE RLS).
-- Spoofing current_period_end alone must NOT confirm rewards.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.current_period_end IS DISTINCT FROM OLD.current_period_end
     AND NEW.provider_code IS NOT DISTINCT FROM 'paddle'
     AND NEW.last_provider_subscription_updated_at IS NOT NULL
     AND (
       NEW.last_provider_subscription_updated_at
         IS DISTINCT FROM OLD.last_provider_subscription_updated_at
       OR NEW.last_provider_subscription_state_fingerprint
         IS DISTINCT FROM OLD.last_provider_subscription_state_fingerprint
     )
  THEN
    PERFORM private.maybe_confirm_referral_redemption_after_billing_apply(NEW.company_id);
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption() IS
  '18B closure: confirm only when period_end changes together with provider fence '
  '(updated_at and/or state fingerprint). Exact-target confirm remains mandatory.';

-- -----------------------------------------------------------------------------
-- Near-renewal policy (documented): inclusive 30-minute window.
-- next_billed_at <= now() + 30 minutes => ATLAS_REFERRAL_NEAR_RENEWAL (no PATCH).
-- next_billed_at > now() + 30 minutes => eligible (subject to other gates).
-- -----------------------------------------------------------------------------
COMMENT ON FUNCTION private.referral_redemption_eligibility(UUID, TIMESTAMPTZ) IS
  '18B: Atlas-known eligibility. Near-renewal uses inclusive 30-minute Paddle restriction: '
  'period_end <= now+30m blocks; > now+30m may proceed. Server-derived only.';

-- -----------------------------------------------------------------------------
-- Evaluate whether processor/reconcile should invoke outbound redeem Edge.
-- Does NOT call Paddle. Does NOT create operations (Edge claim does).
-- Recursion-safe: after exact-target confirm, pending=0 => should_invoke=false.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.evaluate_referral_auto_redemption(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  should_invoke_outbound BOOLEAN,
  reason TEXT,
  open_operation_id UUID,
  open_operation_status TEXT,
  pending_reward_count INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_open private.billing_referral_redemption_operations%ROWTYPE;
  v_pending INTEGER;
  v_elig RECORD;
BEGIN
  IF p_company_id IS NULL THEN
    should_invoke_outbound := FALSE;
    reason := 'ATLAS_COMPANY_ID_REQUIRED';
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT private.is_referral_redemption_enabled() THEN
    should_invoke_outbound := FALSE;
    reason := 'ATLAS_REFERRAL_REDEMPTION_DISABLED';
    SELECT count(*)::INTEGER INTO v_pending
    FROM public.referral_rewards r
    WHERE r.referring_company_id = p_company_id
      AND r.redemption_status = 'pending';
    pending_reward_count := coalesce(v_pending, 0);
    RETURN NEXT;
    RETURN;
  END IF;

  v_open := private.get_open_referral_redemption_operation(p_company_id);

  SELECT count(*)::INTEGER INTO v_pending
  FROM public.referral_rewards r
  WHERE r.referring_company_id = p_company_id
    AND r.redemption_status = 'pending';

  pending_reward_count := coalesce(v_pending, 0);

  IF v_open.id IS NOT NULL THEN
    -- Heal/retry/confirm path for open op; never create a duplicate.
    should_invoke_outbound := TRUE;
    reason := 'open_operation';
    open_operation_id := v_open.id;
    open_operation_status := v_open.status;
    RETURN NEXT;
    RETURN;
  END IF;

  IF coalesce(v_pending, 0) = 0 THEN
    should_invoke_outbound := FALSE;
    reason := 'no_pending';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT * INTO v_elig
  FROM private.referral_redemption_eligibility(p_company_id, p_now);

  IF v_elig.eligible THEN
    should_invoke_outbound := TRUE;
    reason := 'eligible_pending';
    RETURN NEXT;
    RETURN;
  END IF;

  should_invoke_outbound := FALSE;
  reason := coalesce(v_elig.block_reason, 'blocked');
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.evaluate_referral_auto_redemption(UUID, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.evaluate_referral_auto_redemption(UUID, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.evaluate_referral_auto_redemption_server(
  p_company_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  should_invoke_outbound BOOLEAN,
  reason TEXT,
  open_operation_id UUID,
  open_operation_status TEXT,
  pending_reward_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM private.evaluate_referral_auto_redemption(p_company_id, p_now);
END;
$$;

ALTER FUNCTION public.evaluate_referral_auto_redemption_server(UUID, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.evaluate_referral_auto_redemption_server(UUID, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_referral_auto_redemption_server(UUID, TIMESTAMPTZ)
  TO service_role;
