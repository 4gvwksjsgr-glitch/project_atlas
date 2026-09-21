-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Working Step 15: company member invites behavior
-- BEGIN … ROLLBACK: no persistent residue.
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
SECURITY DEFINER
SET search_path = ''
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

GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) TO anon;

DO $body$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_admin UUID := gen_random_uuid();
  v_manager UUID := gen_random_uuid();
  v_outsider UUID := gen_random_uuid();
  v_invitee UUID := gen_random_uuid();
  v_newperson UUID := gen_random_uuid();
  v_expired_user UUID := gen_random_uuid();
  v_company_a UUID := gen_random_uuid();
  v_company_b UUID := gen_random_uuid();
  v_invite_id UUID;
  v_token TEXT;
  v_token2 TEXT;
  v_count INTEGER;
  v_role public.company_role;
  v_membership UUID;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'owner15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'admin15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'manager15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_outsider, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'outsider15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_invitee, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'invitee15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_newperson, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'newperson15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_expired_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'expired15@example.invalid', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.profiles (id, email, full_name)
  SELECT u.id, u.email, 'Step15'
  FROM auth.users u
  WHERE u.id IN (v_owner, v_admin, v_manager, v_outsider, v_invitee, v_newperson, v_expired_user)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company_a, 'Step15 Co A', 'step15-co-a-' || substr(replace(v_company_a::text, '-', ''), 1, 8)),
    (v_company_b, 'Step15 Co B', 'step15-co-b-' || substr(replace(v_company_b::text, '-', ''), 1, 8));

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company_a, v_owner, 'owner'),
    (v_company_a, v_admin, 'admin'),
    (v_company_a, v_manager, 'manager'),
    (v_company_b, v_outsider, 'owner');

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SET LOCAL ROLE authenticated;

  BEGIN
    SELECT c.invite_id, c.invite_token INTO v_invite_id, v_token
    FROM public.create_company_invite(
      v_company_a, '  Invitee15@Example.Invalid ', 'employee'::public.company_role, 24
    ) c;
    PERFORM pg_temp.record_result(
      'owner_creates_invite',
      v_invite_id IS NOT NULL AND v_token IS NOT NULL AND char_length(v_token) >= 32,
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_creates_invite', false, SQLSTATE, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.create_company_invite(
      v_company_a, 'x@example.invalid', 'employee'::public.company_role, 24
    );
    PERFORM pg_temp.record_result('manager_cannot_create_invite', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'manager_cannot_create_invite',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.create_company_invite(
      v_company_a, 'y@example.invalid', 'employee'::public.company_role, 24
    );
    PERFORM pg_temp.record_result('cross_tenant_cannot_create', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'cross_tenant_cannot_create',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.create_company_invite(
      v_company_a, 'invitee15@example.invalid', 'employee'::public.company_role, 24
    );
    PERFORM pg_temp.record_result('duplicate_pending_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'duplicate_pending_rejected',
      SQLERRM LIKE '%ATLAS_INVITE_ALREADY_PENDING%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.accept_company_invite(v_token);
    PERFORM pg_temp.record_result('wrong_email_cannot_accept', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'wrong_email_cannot_accept',
      SQLERRM LIKE '%ATLAS_INVITE_EMAIL_MISMATCH%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_invitee::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_invitee::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT a.membership_id, a.role INTO v_membership, v_role
    FROM public.accept_company_invite(v_token) a;
    PERFORM pg_temp.record_result(
      'correct_email_accepts',
      v_membership IS NOT NULL AND v_role = 'employee'::public.company_role,
      NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('correct_email_accepts', false, SQLSTATE, SQLERRM);
  END;

  BEGIN
    SELECT a.membership_id INTO v_membership FROM public.accept_company_invite(v_token) a;
    SELECT count(*) INTO v_count FROM public.company_members
    WHERE company_id = v_company_a AND user_id = v_invitee;
    PERFORM pg_temp.record_result(
      'accept_idempotent_same_user',
      v_count = 1 AND v_membership IS NOT NULL, NULL, v_count::text
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('accept_idempotent_same_user', false, SQLSTATE, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.create_company_invite(
      v_company_a, 'invitee15@example.invalid', 'manager'::public.company_role, 24
    );
    PERFORM pg_temp.record_result('invite_already_member_rejected', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'invite_already_member_rejected',
      SQLERRM LIKE '%ATLAS_INVITE_ALREADY_MEMBER%', SQLSTATE, SQLERRM
    );
  END;

  SELECT c.invite_id, c.invite_token INTO v_invite_id, v_token2
  FROM public.create_company_invite(
    v_company_a, 'newperson15@example.invalid', 'manager'::public.company_role, 24
  ) c;
  PERFORM public.revoke_company_invite(v_invite_id);

  PERFORM set_config('request.jwt.claim.sub', v_newperson::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_newperson::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.accept_company_invite(v_token2);
    PERFORM pg_temp.record_result('revoked_invite_cannot_accept', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'revoked_invite_cannot_accept',
      SQLERRM LIKE '%ATLAS_INVITE_REVOKED%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  SELECT c.invite_id, c.invite_token INTO v_invite_id, v_token2
  FROM public.create_company_invite(
    v_company_a, 'expired15@example.invalid', 'employee'::public.company_role, 1
  ) c;

  -- Fixture-only: expire invite as postgres (clients have no table grants).
  -- Backdate created_at so expires_after_created check remains satisfied.
  RESET ROLE;
  UPDATE public.company_invites
  SET created_at = now() - interval '2 hours',
      expires_at = now() - interval '1 minute'
  WHERE id = v_invite_id;
  SET LOCAL ROLE authenticated;

  PERFORM set_config('request.jwt.claim.sub', v_expired_user::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_expired_user::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.accept_company_invite(v_token2);
    PERFORM pg_temp.record_result('expired_invite_cannot_accept', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'expired_invite_cannot_accept',
      SQLERRM LIKE '%ATLAS_INVITE_EXPIRED%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.change_company_member_role(
      v_company_a, v_invitee, 'manager'::public.company_role
    );
    SELECT role INTO v_role FROM public.company_members
    WHERE company_id = v_company_a AND user_id = v_invitee;
    PERFORM pg_temp.record_result(
      'owner_role_change_succeeds',
      v_role = 'manager'::public.company_role, NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_role_change_succeeds', false, SQLSTATE, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_manager::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.change_company_member_role(
      v_company_a, v_invitee, 'employee'::public.company_role
    );
    PERFORM pg_temp.record_result('manager_cannot_change_role', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'manager_cannot_change_role',
      SQLERRM LIKE '%ATLAS_INSUFFICIENT_PRIVILEGES%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.change_company_member_role(
      v_company_a, v_invitee, 'admin'::public.company_role
    );
    PERFORM pg_temp.record_result('admin_cannot_assign_admin', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'admin_cannot_assign_admin',
      SQLERRM LIKE '%ATLAS_ONLY_OWNER_CAN_ASSIGN_ADMIN%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.remove_company_member(v_company_a, v_invitee);
    SELECT count(*) INTO v_count FROM public.company_members
    WHERE company_id = v_company_a AND user_id = v_invitee;
    PERFORM pg_temp.record_result('owner_remove_member', v_count = 0, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('owner_remove_member', false, SQLSTATE, SQLERRM);
  END;

  BEGIN
    PERFORM public.remove_company_member(v_company_a, v_owner);
    PERFORM pg_temp.record_result('last_owner_invariant', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'last_owner_invariant',
      SQLERRM LIKE '%last owner%' OR SQLERRM LIKE '%ATLAS_CANNOT_REMOVE_LAST_OWNER%',
      SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_outsider::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_outsider::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    PERFORM public.list_company_members(v_company_a);
    PERFORM pg_temp.record_result('list_members_cross_tenant_denied', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'list_members_cross_tenant_denied',
      SQLERRM LIKE '%ATLAS_NOT_COMPANY_MEMBER%', SQLSTATE, SQLERRM
    );
  END;

  PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_owner::text, 'role', 'authenticated')::text,
    true
  );
  BEGIN
    SELECT count(*) INTO v_count FROM public.list_company_invites(v_company_a);
    PERFORM pg_temp.record_result('list_invites_owner_ok', v_count >= 1, NULL, v_count::text);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result('list_invites_owner_ok', false, SQLSTATE, SQLERRM);
  END;

  BEGIN
    PERFORM public.create_company_invite(
      v_company_a, 'ownerrole15@example.invalid', 'owner'::public.company_role, 24
    );
    PERFORM pg_temp.record_result('invite_owner_role_forbidden', false, NULL, 'expected deny');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.record_result(
      'invite_owner_role_forbidden',
      SQLERRM LIKE '%ATLAS_INVITE_ROLE_OWNER_FORBIDDEN%', SQLSTATE, SQLERRM
    );
  END;

  RESET ROLE;
END;
$body$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

ROLLBACK;
