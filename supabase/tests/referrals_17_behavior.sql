-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 17 referral foundation behavioral checks
-- BEGIN … ROLLBACK. No persistent fixtures.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.record_result(
  p_name TEXT,
  p_passed BOOLEAN,
  p_sqlstate TEXT DEFAULT NULL,
  p_detail TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO test_results (test_name, passed, sqlstate, detail)
  VALUES (p_name, p_passed, p_sqlstate, p_detail)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      sqlstate = EXCLUDED.sqlstate,
      detail = EXCLUDED.detail;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO anon;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO anon;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_employee UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_friend UUID;
  v_friend_n UUID;
  v_company_a UUID;
  v_company_b UUID;
  v_code TEXT;
  v_code2 TEXT;
  v_ref_id UUID;
  v_status TEXT;
  v_count INTEGER;
  v_rewarded INTEGER;
  v_already BOOLEAN;
  v_sub_origin TEXT;
  v_i INTEGER;
  v_slug TEXT;
BEGIN
  -- Seed auth users + profiles
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  )
  SELECT
    u.id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    u.email,
    crypt('x', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  FROM (VALUES
    (v_owner, 'owner17@example.invalid'),
    (v_admin, 'admin17@example.invalid'),
    (v_manager, 'manager17@example.invalid'),
    (v_employee, 'employee17@example.invalid'),
    (v_outsider, 'outsider17@example.invalid')
  ) AS u(id, email);

  INSERT INTO public.profiles (id, email, full_name)
  SELECT u.id, u.email, split_part(u.email, '@', 1)
  FROM auth.users u
  WHERE u.id IN (v_owner, v_admin, v_manager, v_employee, v_outsider)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  -- Owner creates company A
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;

  SELECT c.id INTO v_company_a
  FROM public.create_company('Ref Co A', 'ref-co-a-17') c;

  RESET ROLE;
  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_a, v_employee, 'employee');

  -- Outsider owns company B (for multi-referrer tests)
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  SELECT c.id INTO v_company_b
  FROM public.create_company('Ref Co B', 'ref-co-b-17') c;

  -- Owner gets referral link
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.code INTO v_code
    FROM public.get_or_create_company_referral_link(v_company_a) r;
    PERFORM pg_temp.record_result(
      'owner_gets_referral_link',
      v_code IS NOT NULL AND length(v_code) >= 16,
      NULL,
      left(coalesce(v_code, ''), 8)
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_gets_referral_link', false, SQLSTATE, SQLERRM);
  END;

  -- Idempotent get returns same code
  BEGIN
    SELECT r.code INTO v_code2
    FROM public.get_or_create_company_referral_link(v_company_a) r;
    PERFORM pg_temp.record_result(
      'owner_link_stable',
      v_code2 = v_code, NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_link_stable', false, SQLSTATE, SQLERRM);
  END;

  -- Admin cannot get/create
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.get_or_create_company_referral_link(v_company_a);
    PERFORM pg_temp.record_result('admin_cannot_manage_link', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'admin_cannot_manage_link',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Manager cannot
  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.regenerate_company_referral_link(v_company_a);
    PERFORM pg_temp.record_result('manager_cannot_regenerate', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'manager_cannot_regenerate',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Employee cannot
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.get_or_create_company_referral_link(v_company_a);
    PERFORM pg_temp.record_result('employee_cannot_manage_link', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'employee_cannot_manage_link',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Outsider cannot manage company A link
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.get_or_create_company_referral_link(v_company_a);
    PERFORM pg_temp.record_result('outsider_cannot_manage_link', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'outsider_cannot_manage_link',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Self-referral denied (employee is member of referring company, no owned company)
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.claim_referral(v_code);
    PERFORM pg_temp.record_result('self_referral_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'self_referral_denied',
      SQLERRM LIKE '%ATLAS_REFERRAL_SELF_DENIED%',
      SQLSTATE, SQLERRM
    );
  END;

  -- Valid new-user claim
  RESET ROLE;
  v_friend := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend, 'friend17@example.invalid', 'friend17')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  PERFORM set_config('request.jwt.claim.sub', v_friend::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    SELECT r.referral_id, r.status, r.already_claimed
    INTO v_ref_id, v_status, v_already
    FROM public.claim_referral(v_code) r;
    PERFORM pg_temp.record_result(
      'valid_new_user_claim',
      v_status = 'claimed' AND v_already = false AND v_ref_id IS NOT NULL,
      NULL, v_status
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('valid_new_user_claim', false, SQLSTATE, SQLERRM);
  END;

  -- Duplicate claim idempotent
  BEGIN
    SELECT r.referral_id, r.status, r.already_claimed
    INTO v_ref_id, v_status, v_already
    FROM public.claim_referral(v_code) r;
    PERFORM pg_temp.record_result(
      'duplicate_claim_idempotent',
      v_already = true AND v_status = 'claimed',
      NULL, v_status
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('duplicate_claim_idempotent', false, SQLSTATE, SQLERRM);
  END;

  -- Same user cannot claim other company code (already has referral)
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  SELECT r.code INTO v_code2
  FROM public.get_or_create_company_referral_link(v_company_b) r;

  PERFORM set_config('request.jwt.claim.sub', v_friend::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.already_claimed INTO v_already
    FROM public.claim_referral(v_code2) r;
    RESET ROLE;
    -- Idempotent return of original A referral, not switch to B
    PERFORM pg_temp.record_result(
      'multi_referrer_blocked',
      v_already = true AND (
        SELECT referring_company_id FROM public.referrals WHERE referred_user_id = v_friend
      ) = v_company_a,
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('multi_referrer_blocked', false, SQLSTATE, SQLERRM);
  END;

  -- Qualify via create_company → 1 reward
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.referral_rewards
  WHERE referring_company_id = v_company_a;
  PERFORM set_config('request.jwt.claim.sub', v_friend::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_company('Friend Co', 'friend-co-17');
    RESET ROLE;
    SELECT count(*) INTO v_rewarded FROM public.referral_rewards
    WHERE referring_company_id = v_company_a;
    SELECT r.status INTO v_status FROM public.referrals r WHERE r.referred_user_id = v_friend;
    PERFORM pg_temp.record_result(
      'qualification_mints_one_reward',
      v_rewarded = v_count + 1 AND v_status = 'rewarded',
      NULL,
      v_rewarded::text || '/' || v_status
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('qualification_mints_one_reward', false, SQLSTATE, SQLERRM);
  END;

  -- Repeated qualification does not mint second (create another company as same user)
  BEGIN
    PERFORM public.create_company('Friend Co 2', 'friend-co-17-b');
    RESET ROLE;
    SELECT count(*) INTO v_rewarded FROM public.referral_rewards
    WHERE referring_company_id = v_company_a;
    PERFORM pg_temp.record_result(
      'repeat_qualify_no_second_reward',
      v_rewarded = 1, NULL, v_rewarded::text
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('repeat_qualify_no_second_reward', false, SQLSTATE, SQLERRM);
  END;

  -- Billing state unchanged for referring company (still free/none)
  RESET ROLE;
  SELECT cs.entitlement_origin INTO v_sub_origin
  FROM public.company_subscriptions cs
  WHERE cs.company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'no_entitlement_mutation_on_reward',
    v_sub_origin = 'none', NULL, v_sub_origin
  );

  -- First five rewards: add 4 more friends (already 1)
  FOR v_i IN 2..5 LOOP
    RESET ROLE;
    v_friend_n := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) VALUES (
      v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      'friend17_' || v_i::text || '@example.invalid', crypt('x', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
      v_friend_n,
      'friend17_' || v_i::text || '@example.invalid',
      'friend17_' || v_i::text
    )
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

    PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
    PERFORM set_config(
      'request.jwt.claims',
      json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
      true
    );
    SET LOCAL ROLE authenticated;
    PERFORM public.claim_referral(v_code);
    v_slug := 'friend-co-17-' || v_i::text;
    PERFORM public.create_company('Friend Co ' || v_i::text, v_slug);
  END LOOP;

  RESET ROLE;
  SELECT count(*) INTO v_rewarded FROM public.referral_rewards
  WHERE referring_company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'first_five_rewards_succeed',
    v_rewarded = 5, NULL, v_rewarded::text
  );

  -- Sixth: qualifies but no reward #6
  RESET ROLE;
  v_friend_n := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17_6@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend_n, 'friend17_6@example.invalid', 'friend17_6')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.claim_referral(v_code);
  PERFORM public.create_company('Friend Co 6', 'friend-co-17-6');
  RESET ROLE;
  SELECT count(*) INTO v_rewarded FROM public.referral_rewards
  WHERE referring_company_id = v_company_a;
  SELECT r.status INTO v_status FROM public.referrals r WHERE r.referred_user_id = v_friend_n;
  PERFORM pg_temp.record_result(
    'sixth_no_reward',
    v_rewarded = 5 AND v_status = 'not_rewarded_limit_reached',
    NULL,
    v_rewarded::text || '/' || v_status
  );

  -- Direct writes denied for authenticated
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.referral_rewards (
      referral_id, referring_company_id, reward_months
    ) VALUES (gen_random_uuid(), v_company_a, 1);
    PERFORM pg_temp.record_result('direct_reward_insert_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'direct_reward_insert_denied',
      SQLSTATE IN ('42501', 'P0001'), SQLSTATE, SQLERRM
    );
  END;

  -- Cross-tenant overview denied
  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.get_referral_overview(v_company_a);
    PERFORM pg_temp.record_result('cross_tenant_overview_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'cross_tenant_overview_denied',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  -- Member overview: counts, no code
  PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_employee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT r.code IS NULL AND r.rewarded_count = 5 AND r.is_owner = false
    INTO v_already
    FROM public.get_referral_overview(v_company_a) r;
    PERFORM pg_temp.record_result('member_overview_counts_only', v_already, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('member_overview_counts_only', false, SQLSTATE, SQLERRM);
  END;

  -- Anon execute denied
  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.claim_referral(v_code);
    PERFORM pg_temp.record_result('anon_claim_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'anon_claim_denied',
      SQLSTATE IN ('42501', 'P0001', '28000'), SQLSTATE, SQLERRM
    );
  END;

  RESET ROLE;

  -- SECURITY DEFINER search_path
  SELECT (p.proconfig::text LIKE '%search_path%')
  INTO v_already
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'claim_referral';
  PERFORM pg_temp.record_result('security_definer_search_path', v_already, NULL, NULL);

  -- Invalid code
  RESET ROLE;
  v_friend_n := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17_bad@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend_n, 'friend17_bad@example.invalid', 'bad')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.claim_referral('not-a-valid-code!!');
    PERFORM pg_temp.record_result('invalid_code_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'invalid_code_denied',
      SQLERRM LIKE '%ATLAS_REFERRAL_CODE_INVALID%', SQLSTATE, SQLERRM
    );
  END;

  -- Late claim after first owned company denied
  RESET ROLE;
  v_friend_n := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17_late@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend_n, 'friend17_late@example.invalid', 'late')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.create_company('Late Co', 'late-co-17');
  BEGIN
    PERFORM public.claim_referral(v_code);
    PERFORM pg_temp.record_result('late_claim_after_owned_company_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'late_claim_after_owned_company_denied',
      SQLERRM LIKE '%ATLAS_REFERRAL_CLAIM_WINDOW_CLOSED%', SQLSTATE, SQLERRM
    );
  END;

  -- Code regeneration: old invalid, claims/rewards survive
  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT r.code INTO v_code2
  FROM public.regenerate_company_referral_link(v_company_a) r;
  BEGIN
    PERFORM pg_temp.record_result(
      'code_rotation_new_code_differs',
      v_code2 IS NOT NULL AND v_code2 IS DISTINCT FROM v_code,
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('code_rotation_new_code_differs', false, SQLSTATE, SQLERRM);
  END;

  RESET ROLE;
  v_friend_n := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17_oldcode@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend_n, 'friend17_oldcode@example.invalid', 'oldcode')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.claim_referral(v_code);
    PERFORM pg_temp.record_result('old_code_invalid_after_rotation', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'old_code_invalid_after_rotation',
      SQLERRM LIKE '%ATLAS_REFERRAL_CODE_INVALID%', SQLSTATE, SQLERRM
    );
  END;

  RESET ROLE;
  SELECT count(*) INTO v_rewarded FROM public.referral_rewards
  WHERE referring_company_id = v_company_a;
  PERFORM pg_temp.record_result(
    'existing_rewards_survive_rotation',
    v_rewarded = 5, NULL, v_rewarded::text
  );

  -- Structural max-five: active slots unique 1..5
  SELECT count(*) INTO v_count
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'referral_rewards_company_slot_uidx';
  PERFORM pg_temp.record_result(
    'max5_slot_unique_index_present',
    v_count = 1, NULL, v_count::text
  );

  -- create_company without referral succeeds
  RESET ROLE;
  v_friend_n := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_friend_n, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'friend17_noref@example.invalid', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (v_friend_n, 'friend17_noref@example.invalid', 'noref')
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  PERFORM set_config('request.jwt.claim.sub', v_friend_n::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_friend_n::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_company('No Ref Co', 'no-ref-co-17');
    PERFORM pg_temp.record_result('create_company_without_referral_ok', true, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('create_company_without_referral_ok', false, SQLSTATE, SQLERRM);
  END;

END $$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

ROLLBACK;
