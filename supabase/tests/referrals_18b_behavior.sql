-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 18B referral redemption behavior
-- =============================================================================

BEGIN;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  error_code TEXT,
  error_message TEXT
);

CREATE OR REPLACE FUNCTION pg_temp.record_result(
  p_name TEXT,
  p_passed BOOLEAN,
  p_code TEXT DEFAULT NULL,
  p_msg TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO test_results(test_name, passed, error_code, error_message)
  VALUES (p_name, p_passed, p_code, p_msg)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      error_code = EXCLUDED.error_code,
      error_message = EXCLUDED.error_message;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO anon;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO anon;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_company UUID := gen_random_uuid();
  v_code_id UUID := gen_random_uuid();
  v_friend UUID;
  v_ref_id UUID;
  v_claim RECORD;
  v_confirm RECORD;
  v_op_id UUID;
  v_n INT;
  v_open_count INT;
  v_status TEXT;
  v_i INT;
BEGIN
  PERFORM pg_temp.record_result(
    'cal_jan31_to_feb28',
    private.add_calendar_months('2026-01-31 10:00:00+00'::timestamptz, 1)
      = '2026-02-28 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_jan31_leap_to_feb29',
    private.add_calendar_months('2028-01-31 10:00:00+00'::timestamptz, 1)
      = '2028-02-29 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_mar31_to_apr30',
    private.add_calendar_months('2026-03-31 10:00:00+00'::timestamptz, 1)
      = '2026-04-30 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_aug31_to_sep30',
    private.add_calendar_months('2026-08-31 10:00:00+00'::timestamptz, 1)
      = '2026-09-30 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_dec31_year_cross',
    private.add_calendar_months('2026-12-31 10:00:00+00'::timestamptz, 1)
      = '2027-01-31 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_jan31_plus_2_single_step',
    private.add_calendar_months('2026-01-31 10:00:00+00'::timestamptz, 2)
      = '2026-03-31 10:00:00+00'::timestamptz, NULL, NULL
  );
  PERFORM pg_temp.record_result(
    'cal_oct15_plus_3',
    private.add_calendar_months('2026-10-15 10:00:00+00'::timestamptz, 3)
      = '2027-01-15 10:00:00+00'::timestamptz, NULL, NULL
  );

  PERFORM pg_temp.record_result(
    'kill_switch_default_false',
    private.is_referral_redemption_enabled() IS FALSE, NULL, NULL
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner18@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin18@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, email, full_name) VALUES
    (v_owner, 'owner18@example.invalid', 'Owner 18'),
    (v_admin, 'admin18@example.invalid', 'Admin 18')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  INSERT INTO public.companies (id, name, slug)
  VALUES (v_company, 'Redeem Co 18', 'redeem-co-18');
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company, v_owner, 'owner'),
    (v_company, v_admin, 'admin');
  INSERT INTO public.company_subscriptions (
    company_id, plan_code, status, entitlement_origin
  ) VALUES (v_company, 'free', 'free', 'none');
  INSERT INTO private.company_billing (company_id) VALUES (v_company);

  INSERT INTO public.company_referral_codes (id, company_id, created_by, code)
  VALUES (v_code_id, v_company, v_owner, 'TestCode18Baaaaaaaaaaaa');

  FOR v_i IN 1..3 LOOP
    v_friend := gen_random_uuid();
    v_ref_id := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_friend, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'friend18_' || v_i || '@example.invalid', crypt('x', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (v_friend, 'friend18_' || v_i || '@example.invalid', 'Friend ' || v_i)
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    INSERT INTO public.referrals (
      id, referral_code_id, referring_company_id, referred_user_id,
      referred_company_id, status, claimed_at, qualified_at
    ) VALUES (
      v_ref_id, v_code_id, v_company, v_friend, v_company,
      'rewarded', now(), now()
    );
    INSERT INTO public.referral_rewards (
      referral_id, referring_company_id, reward_slot, reward_months, redemption_status
    ) VALUES (v_ref_id, v_company, v_i::smallint, 1, 'pending');
  END LOOP;

  SELECT * INTO v_claim FROM private.claim_referral_redemption_operation(v_company, now());
  PERFORM pg_temp.record_result(
    'disabled_blocks_claim',
    v_claim.outcome = 'blocked'
      AND v_claim.error_code = 'ATLAS_REFERRAL_REDEMPTION_DISABLED',
    v_claim.error_code, v_claim.outcome
  );
  SELECT count(*) INTO v_n FROM public.referral_rewards
  WHERE referring_company_id = v_company AND redemption_status = 'pending';
  PERFORM pg_temp.record_result('disabled_keeps_pending', v_n = 3, NULL, v_n::text);

  UPDATE private.billing_runtime_config
  SET referral_redemption_enabled = TRUE
  WHERE provider_code = 'paddle' AND provider_environment = 'test' AND is_active;

  SELECT * INTO v_claim FROM private.claim_referral_redemption_operation(v_company, now());
  PERFORM pg_temp.record_result(
    'unlinked_blocks_claim',
    v_claim.outcome = 'blocked'
      AND v_claim.error_code = 'ATLAS_REFERRAL_PROVIDER_UNLINKED',
    v_claim.error_code, v_claim.outcome
  );

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_subscription_id = 'sub_01habcdefghijklmnopqrstuvw',
    external_customer_id = 'ctm_01habcdefghijklmnopqrstuvw',
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = '2026-10-15 10:00:00+00',
    current_period_start = '2026-09-15 10:00:00+00',
    current_period_end = '2026-10-15 10:00:00+00',
    cancel_at_period_end = FALSE
  WHERE company_id = v_company;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  SELECT * INTO v_claim FROM private.claim_referral_redemption_operation(v_company, now());
  v_op_id := v_claim.operation_id;
  PERFORM pg_temp.record_result(
    'claim_three_batch',
    v_claim.outcome = 'claimed'
      AND v_claim.reward_count = 3
      AND v_claim.target_next_billed_at = '2027-01-15 10:00:00+00'::timestamptz,
    v_claim.error_code, coalesce(v_claim.reward_count::text, 'null')
  );

  SELECT count(*) INTO v_n FROM public.referral_rewards
  WHERE referring_company_id = v_company AND redemption_status = 'applying';
  PERFORM pg_temp.record_result('rewards_applying', v_n = 3, NULL, v_n::text);

  SELECT * INTO v_claim FROM private.claim_referral_redemption_operation(v_company, now());
  PERFORM pg_temp.record_result(
    'second_claim_existing_open',
    v_claim.outcome = 'existing_open' AND v_claim.operation_id = v_op_id,
    NULL, v_claim.outcome
  );

  SELECT count(*) INTO v_open_count
  FROM private.billing_referral_redemption_operations
  WHERE company_id = v_company AND status NOT IN ('confirmed', 'terminal_failed');
  PERFORM pg_temp.record_result('one_open_op', v_open_count = 1, NULL, v_open_count::text);

  -- Spoof: period_end alone without provider fence must NOT confirm.
  UPDATE private.company_billing
  SET current_period_end = '2027-01-15 10:00:00+00'
  WHERE company_id = v_company;
  SELECT o.status INTO v_status
  FROM private.billing_referral_redemption_operations o WHERE o.id = v_op_id;
  SELECT count(*) INTO v_n FROM public.referral_rewards
  WHERE referring_company_id = v_company AND redemption_status = 'redeemed';
  PERFORM pg_temp.record_result(
    'confirm_spoof_period_end_alone',
    v_status IS DISTINCT FROM 'confirmed' AND v_n = 0,
    NULL, coalesce(v_status, 'null') || '/' || v_n::text
  );

  -- Reset period_end so the authoritative UPDATE changes it (trigger distinctness).
  UPDATE private.company_billing
  SET current_period_end = '2026-10-15 10:00:00+00'
  WHERE company_id = v_company;

  -- Authoritative path: period_end + provider fence movement → exact confirm.
  UPDATE private.company_billing
  SET
    current_period_end = '2027-01-15 10:00:00+00',
    provider_access_ends_at = '2027-01-15 10:00:00+00',
    last_provider_subscription_updated_at = '2026-09-22 12:00:00+00',
    last_provider_subscription_state_fingerprint = 'fp_redeem_confirm_1'
  WHERE company_id = v_company;

  SELECT o.status INTO v_status
  FROM private.billing_referral_redemption_operations o WHERE o.id = v_op_id;
  SELECT count(*) INTO v_n FROM public.referral_rewards
  WHERE referring_company_id = v_company AND redemption_status = 'redeemed';
  PERFORM pg_temp.record_result(
    'confirm_exact_target',
    v_status = 'confirmed' AND v_n = 3,
    NULL, coalesce(v_status, 'null') || '/' || v_n::text
  );
  PERFORM pg_temp.record_result(
    'provider_access_aligned_to_period_end',
    EXISTS (
      SELECT 1 FROM private.company_billing b
      WHERE b.company_id = v_company
        AND b.current_period_end = '2027-01-15 10:00:00+00'::timestamptz
        AND b.provider_access_ends_at = b.current_period_end
        AND b.provider_access_status = 'entitled'
    ), NULL, NULL
  );

  SELECT * INTO v_confirm FROM private.confirm_referral_redemption_operation(
    v_company, '2027-01-15 10:00:00+00'::timestamptz, 'sub_01habcdefghijklmnopqrstuvw'
  );
  PERFORM pg_temp.record_result(
    'confirm_idempotent',
    v_confirm.outcome IN ('no_open_operation', 'already_confirmed'),
    NULL, v_confirm.outcome
  );

  PERFORM pg_temp.record_result(
    'reward_months_fixed',
    NOT EXISTS (
      SELECT 1 FROM public.referral_rewards r
      WHERE r.referring_company_id = v_company AND r.reward_months IS DISTINCT FROM 1
    ), NULL, NULL
  );

  -- Old value does not confirm (new op scenario skipped — already confirmed)
  PERFORM pg_temp.record_result(
    'max5_slot_index_intact',
    EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE indexname = 'referral_rewards_company_slot_uidx'
    ), NULL, NULL
  );

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.retry_referral_redemption(v_company);
    PERFORM pg_temp.record_result('nonowner_retry_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'nonowner_retry_denied',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%',
      SQLSTATE, SQLERRM
    );
  END;
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.referral_rewards (
      referral_id, referring_company_id, reward_slot, reward_months
    ) VALUES (gen_random_uuid(), v_company, 4, 1);
    PERFORM pg_temp.record_result('direct_reward_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.record_result('direct_reward_insert_denied', true, NULL, NULL);
  WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'direct_reward_insert_denied', SQLSTATE = '42501', SQLSTATE, SQLERRM
    );
  END;
  RESET ROLE;

  -- -------------------------------------------------------------------------
  -- Closure: eligibility matrix, near-renewal boundaries, confirm branches,
  -- auto-evaluate, provider replacement, kill-switch evaluate.
  -- -------------------------------------------------------------------------
  DECLARE
    v_c2 UUID := gen_random_uuid();
    v_owner2 UUID := gen_random_uuid();
    v_code2 UUID := gen_random_uuid();
    v_friend2 UUID;
    v_ref2 UUID;
    v_elig RECORD;
    v_eval RECORD;
    v_claim2 RECORD;
    v_confirm2 RECORD;
    v_op2 UUID;
    v_now TIMESTAMPTZ := '2026-09-22 12:00:00+00'::timestamptz;
    v_period TIMESTAMPTZ := '2026-10-15 10:00:00+00'::timestamptz;
    v_target2 TIMESTAMPTZ;
  BEGIN
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_owner2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'owner18b2@example.invalid', crypt('x', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (v_owner2, 'owner18b2@example.invalid', 'Owner 18B2')
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    INSERT INTO public.companies (id, name, slug)
    VALUES (v_c2, 'Redeem Co 18B2', 'redeem-co-18b2');
    INSERT INTO public.company_members (company_id, user_id, role)
    VALUES (v_c2, v_owner2, 'owner');
    INSERT INTO public.company_subscriptions (
      company_id, plan_code, status, entitlement_origin
    ) VALUES (v_c2, 'free', 'free', 'none');
    INSERT INTO private.company_billing (company_id) VALUES (v_c2);
    INSERT INTO public.company_referral_codes (id, company_id, created_by, code)
    VALUES (v_code2, v_c2, v_owner2, 'TestCode18B2bbbbbbbbbbbb');

    v_friend2 := gen_random_uuid();
    v_ref2 := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_friend2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'friend18b2@example.invalid', crypt('x', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (v_friend2, 'friend18b2@example.invalid', 'Friend 18B2')
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    INSERT INTO public.referrals (
      id, referral_code_id, referring_company_id, referred_user_id,
      referred_company_id, status, claimed_at, qualified_at
    ) VALUES (
      v_ref2, v_code2, v_c2, v_friend2, v_c2, 'rewarded', now(), now()
    );
    INSERT INTO public.referral_rewards (
      referral_id, referring_company_id, reward_slot, reward_months, redemption_status
    ) VALUES (v_ref2, v_c2, 1, 1, 'pending');

    -- Kill switch evaluate: pending remains, zero outbound signal.
    UPDATE private.billing_runtime_config
    SET referral_redemption_enabled = FALSE
    WHERE provider_code = 'paddle' AND provider_environment = 'test' AND is_active;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_kill_switch_false',
      v_eval.should_invoke_outbound IS FALSE
        AND v_eval.reason = 'ATLAS_REFERRAL_REDEMPTION_DISABLED'
        AND v_eval.pending_reward_count = 1,
      NULL, v_eval.reason
    );

    UPDATE private.billing_runtime_config
    SET referral_redemption_enabled = TRUE
    WHERE provider_code = 'paddle' AND provider_environment = 'test' AND is_active;

    -- Free / unlinked: stay pending; evaluate no invoke.
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'elig_free_unlinked',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_PROVIDER_UNLINKED',
      NULL, v_elig.block_reason
    );
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_free_no_invoke',
      v_eval.should_invoke_outbound IS FALSE
        AND v_eval.pending_reward_count = 1,
      NULL, v_eval.reason
    );

    -- Link active: free→active auto-eligible.
    UPDATE private.company_billing
    SET
      provider_code = 'paddle',
      provider_environment = 'test',
      external_subscription_id = 'sub_01habcdefghijklmnopqrstuvx',
      external_customer_id = 'ctm_01habcdefghijklmnopqrstuvx',
      subscription_status = 'active',
      payment_status = 'ok',
      provider_access_status = 'entitled',
      provider_access_ends_at = v_period,
      current_period_start = '2026-09-15 10:00:00+00',
      current_period_end = v_period,
      cancel_at_period_end = FALSE,
      canceled_at = NULL
    WHERE company_id = v_c2;
    UPDATE public.company_subscriptions
    SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
    WHERE company_id = v_c2;

    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'auto_eligible_after_paid_link',
      v_eval.should_invoke_outbound IS TRUE
        AND v_eval.reason = 'eligible_pending'
        AND v_eval.pending_reward_count = 1,
      NULL, v_eval.reason
    );

    -- past_due blocks
    UPDATE private.company_billing
    SET payment_status = 'past_due'
    WHERE company_id = v_c2;
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'elig_past_due',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_PROVIDER_PAST_DUE',
      NULL, v_elig.block_reason
    );
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_past_due_no_invoke',
      v_eval.should_invoke_outbound IS FALSE, NULL, v_eval.reason
    );

    -- past_due → active recovery
    UPDATE private.company_billing SET payment_status = 'ok' WHERE company_id = v_c2;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'auto_eligible_after_past_due_recovery',
      v_eval.should_invoke_outbound IS TRUE
        AND v_eval.reason = 'eligible_pending',
      NULL, v_eval.reason
    );

    -- scheduled cancel blocks
    UPDATE private.company_billing
    SET cancel_at_period_end = TRUE
    WHERE company_id = v_c2;
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'elig_scheduled_cancel',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_SCHEDULED_CANCEL',
      NULL, v_elig.block_reason
    );

    -- scheduled_cancel cleared → active
    UPDATE private.company_billing
    SET cancel_at_period_end = FALSE
    WHERE company_id = v_c2;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'auto_eligible_after_scheduled_cancel_clear',
      v_eval.should_invoke_outbound IS TRUE, NULL, v_eval.reason
    );

    -- canceled blocks (do not silently reactivate)
    UPDATE private.company_billing
    SET
      subscription_status = 'ended',
      canceled_at = v_now,
      provider_access_status = 'ended',
      provider_access_ends_at = NULL
    WHERE company_id = v_c2;
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'elig_canceled',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_PROVIDER_CANCELED',
      NULL, v_elig.block_reason
    );

    -- New active lifecycle after cancel (new sub id)
    UPDATE private.company_billing
    SET
      external_subscription_id = 'sub_01newlifecycleabcdefghijklmnopqrst',
      subscription_status = 'active',
      payment_status = 'ok',
      provider_access_status = 'entitled',
      provider_access_ends_at = v_period,
      current_period_end = v_period,
      cancel_at_period_end = FALSE,
      canceled_at = NULL
    WHERE company_id = v_c2;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'auto_eligible_new_lifecycle_after_cancel',
      v_eval.should_invoke_outbound IS TRUE
        AND v_eval.reason = 'eligible_pending',
      NULL, v_eval.reason
    );

    -- Near-renewal inclusive 30m boundaries (server-derived).
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(
      v_c2, v_period - interval '29 minutes 59 seconds'
    );
    PERFORM pg_temp.record_result(
      'near_renewal_29m59s_blocked',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_NEAR_RENEWAL',
      NULL, v_elig.block_reason
    );
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(
      v_c2, v_period - interval '30 minutes'
    );
    PERFORM pg_temp.record_result(
      'near_renewal_30m00s_blocked',
      v_elig.eligible IS FALSE
        AND v_elig.block_reason = 'ATLAS_REFERRAL_NEAR_RENEWAL',
      NULL, v_elig.block_reason
    );
    SELECT * INTO v_elig FROM private.referral_redemption_eligibility(
      v_c2, v_period - interval '30 minutes 1 second'
    );
    PERFORM pg_temp.record_result(
      'near_renewal_30m01s_eligible',
      v_elig.eligible IS TRUE, NULL, v_elig.block_reason
    );

    -- Claim + confirm branches: old / third / replacement.
    SELECT * INTO v_claim2 FROM private.claim_referral_redemption_operation(v_c2, v_now);
    v_op2 := v_claim2.operation_id;
    v_target2 := v_claim2.target_next_billed_at;
    PERFORM pg_temp.record_result(
      'claim_after_auto_eligible',
      v_claim2.outcome = 'claimed' AND v_claim2.reward_count = 1,
      v_claim2.error_code, v_claim2.outcome
    );
    PERFORM pg_temp.record_result(
      'target_immutable_from_claim',
      v_target2 = private.add_calendar_months(v_period, 1),
      NULL, v_target2::text
    );

    SELECT * INTO v_confirm2 FROM private.confirm_referral_redemption_operation(
      v_c2, v_period, 'sub_01newlifecycleabcdefghijklmnopqrst'
    );
    PERFORM pg_temp.record_result(
      'confirm_old_value_retryable',
      v_confirm2.outcome = 'still_old'
        AND v_confirm2.error_code = 'ATLAS_REFERRAL_PROVIDER_NOT_APPLIED',
      NULL, v_confirm2.outcome
    );

    SELECT * INTO v_confirm2 FROM private.confirm_referral_redemption_operation(
      v_c2, '2026-11-01 10:00:00+00'::timestamptz, 'sub_01newlifecycleabcdefghijklmnopqrst'
    );
    PERFORM pg_temp.record_result(
      'confirm_third_date_conflict',
      v_confirm2.outcome = 'conflict_third_date'
        AND v_confirm2.error_code = 'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT',
      NULL, v_confirm2.outcome
    );

    -- Heal path: open op => evaluate invokes (no duplicate claim).
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_open_op_heal',
      v_eval.should_invoke_outbound IS TRUE
        AND v_eval.reason = 'open_operation'
        AND v_eval.open_operation_id = v_op2,
      NULL, v_eval.reason
    );
    SELECT * INTO v_claim2 FROM private.claim_referral_redemption_operation(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'no_duplicate_open_op',
      v_claim2.outcome = 'existing_open' AND v_claim2.operation_id = v_op2,
      NULL, v_claim2.outcome
    );

    -- Provider replacement on open op.
    SELECT * INTO v_confirm2 FROM private.confirm_referral_redemption_operation(
      v_c2, v_target2, 'sub_01REPLACEDabcdefghijklmnopqrstuv'
    );
    PERFORM pg_temp.record_result(
      'confirm_provider_replacement_conflict',
      v_confirm2.outcome = 'provider_subscription_changed'
        AND v_confirm2.error_code = 'ATLAS_REFERRAL_PROVIDER_SUBSCRIPTION_CHANGED',
      NULL, v_confirm2.outcome
    );

    -- Recursion safety: after exact confirm, no pending => no invoke.
    -- Reset op to applying-like state is hard after conflict; claim a fresh reward path:
    -- Abort/conflict left op closed-ish (needs_reconcile still open). Force terminal.
    UPDATE private.billing_referral_redemption_operations
    SET status = 'terminal_failed', updated_at = now()
    WHERE id = v_op2;
    UPDATE public.referral_rewards
    SET redemption_status = 'pending', redemption_operation_id = NULL, redeemed_at = NULL
    WHERE referring_company_id = v_c2;

    SELECT * INTO v_claim2 FROM private.claim_referral_redemption_operation(v_c2, v_now);
    v_op2 := v_claim2.operation_id;
    v_target2 := v_claim2.target_next_billed_at;
    UPDATE private.company_billing
    SET
      current_period_end = v_target2,
      provider_access_ends_at = v_target2,
      last_provider_subscription_updated_at = v_now + interval '1 second',
      last_provider_subscription_state_fingerprint = 'fp_redeem_confirm_2'
    WHERE company_id = v_c2;
    SELECT o.status INTO v_status
    FROM private.billing_referral_redemption_operations o WHERE o.id = v_op2;
    PERFORM pg_temp.record_result(
      'confirm_exact_after_heal',
      v_status = 'confirmed', NULL, v_status
    );
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_no_pending_after_confirm',
      v_eval.should_invoke_outbound IS FALSE
        AND v_eval.reason = 'no_pending'
        AND v_eval.pending_reward_count = 0,
      NULL, v_eval.reason
    );

    -- Unlink → re-link active: pending reward (new) becomes eligible.
    v_friend2 := gen_random_uuid();
    v_ref2 := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_friend2, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'friend18b2b@example.invalid', crypt('x', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (v_friend2, 'friend18b2b@example.invalid', 'Friend 18B2b')
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    INSERT INTO public.referrals (
      id, referral_code_id, referring_company_id, referred_user_id,
      referred_company_id, status, claimed_at, qualified_at
    ) VALUES (
      v_ref2, v_code2, v_c2, v_friend2, v_c2, 'rewarded', now(), now()
    );
    INSERT INTO public.referral_rewards (
      referral_id, referring_company_id, reward_slot, reward_months, redemption_status
    ) VALUES (v_ref2, v_c2, 2, 1, 'pending');

    UPDATE private.company_billing
    SET
      external_subscription_id = NULL,
      external_customer_id = NULL,
      external_price_id = NULL,
      subscription_status = 'none',
      payment_status = 'none',
      provider_access_status = 'none',
      provider_access_ends_at = NULL,
      current_period_start = NULL,
      current_period_end = NULL,
      cancel_at_period_end = FALSE,
      canceled_at = NULL
    WHERE company_id = v_c2;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'eval_unlinked_blocks',
      v_eval.should_invoke_outbound IS FALSE, NULL, v_eval.reason
    );
    UPDATE private.company_billing
    SET
      external_subscription_id = 'sub_01relinkedabcdefghijklmnopqrstuv',
      external_customer_id = 'ctm_01relinkedabcdefghijklmnopqrstuv',
      subscription_status = 'active',
      payment_status = 'ok',
      provider_access_status = 'entitled',
      provider_access_ends_at = v_period,
      current_period_end = v_period,
      cancel_at_period_end = FALSE,
      canceled_at = NULL
    WHERE company_id = v_c2;
    SELECT * INTO v_eval FROM private.evaluate_referral_auto_redemption(v_c2, v_now);
    PERFORM pg_temp.record_result(
      'auto_eligible_after_relink',
      v_eval.should_invoke_outbound IS TRUE
        AND v_eval.reason = 'eligible_pending',
      NULL, v_eval.reason
    );

    -- Public cannot touch private ops table / claim RPC.
    PERFORM set_config('request.jwt.claim.sub', v_owner2::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
      INSERT INTO private.billing_referral_redemption_operations (
        company_id, status, reward_count, reward_ids,
        expected_old_next_billed_at, target_next_billed_at,
        provider_subscription_id_snapshot
      ) VALUES (
        v_c2, 'claimed', 1, ARRAY[gen_random_uuid()],
        v_period, private.add_calendar_months(v_period, 1),
        'sub_x'
      );
      PERFORM pg_temp.record_result('public_ops_insert_denied', false, NULL, 'expected deny');
    EXCEPTION WHEN insufficient_privilege THEN
      PERFORM pg_temp.record_result('public_ops_insert_denied', true, NULL, NULL);
    WHEN OTHERS THEN
      PERFORM pg_temp.record_result(
        'public_ops_insert_denied', SQLSTATE = '42501', SQLSTATE, SQLERRM
      );
    END;
    BEGIN
      PERFORM private.claim_referral_redemption_operation(v_c2, v_now);
      PERFORM pg_temp.record_result('public_claim_rpc_denied', false, NULL, 'expected deny');
    EXCEPTION WHEN insufficient_privilege THEN
      PERFORM pg_temp.record_result('public_claim_rpc_denied', true, NULL, NULL);
    WHEN OTHERS THEN
      PERFORM pg_temp.record_result(
        'public_claim_rpc_denied',
        SQLSTATE = '42501' OR SQLERRM ILIKE '%permission%',
        SQLSTATE, SQLERRM
      );
    END;
    RESET ROLE;
  END;

EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.record_result('suite_exception', false, SQLSTATE, SQLERRM);
END;
$$;

SELECT test_name, passed, error_code, error_message
FROM test_results ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed,
  count(*) FILTER (WHERE NOT passed) AS failed,
  count(*) AS total
FROM test_results;

ROLLBACK;
