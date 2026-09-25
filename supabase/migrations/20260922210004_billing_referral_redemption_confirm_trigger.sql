-- =============================================================================
-- Project Atlas — Step 18B: confirm open redemption after billing period updates
-- Trigger-based hook avoids rewriting the large shared applicator body.
-- Confirmation uses exact target match only (never live >= target).
-- transaction.completed does not update current_period_end → cannot confirm.
-- =============================================================================

CREATE OR REPLACE FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.current_period_end IS DISTINCT FROM OLD.current_period_end THEN
    PERFORM private.maybe_confirm_referral_redemption_after_billing_apply(NEW.company_id);
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption()
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS company_billing_maybe_confirm_referral_redemption
  ON private.company_billing;

CREATE TRIGGER company_billing_maybe_confirm_referral_redemption
  AFTER UPDATE OF current_period_end ON private.company_billing
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_company_billing_maybe_confirm_referral_redemption();

COMMENT ON TRIGGER company_billing_maybe_confirm_referral_redemption
  ON private.company_billing IS
  '18B: after authoritative period-end update, attempt exact-target referral redemption confirm.';
