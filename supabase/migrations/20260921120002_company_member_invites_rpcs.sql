-- =============================================================================
-- Project Atlas — Working Step 15: company member invites RPCs
-- Additive. Invite lifecycle only; email delivery out of scope.
-- =============================================================================

CREATE OR REPLACE FUNCTION private.normalize_invite_email(p_email TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT nullif(lower(btrim(p_email)), '');
$$;

ALTER FUNCTION private.normalize_invite_email(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.normalize_invite_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.normalize_invite_email(TEXT) FROM anon;
REVOKE ALL ON FUNCTION private.normalize_invite_email(TEXT) FROM authenticated;

CREATE OR REPLACE FUNCTION private.hash_invite_token(p_token TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT encode(
    extensions.digest(pg_catalog.convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

ALTER FUNCTION private.hash_invite_token(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.hash_invite_token(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.hash_invite_token(TEXT) FROM anon;
REVOKE ALL ON FUNCTION private.hash_invite_token(TEXT) FROM authenticated;

CREATE OR REPLACE FUNCTION private.generate_invite_token()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
  v_raw TEXT;
BEGIN
  v_raw := encode(extensions.gen_random_bytes(32), 'base64');
  v_raw := replace(replace(replace(v_raw, '+', '-'), '/', '_'), '=', '');
  RETURN v_raw;
END;
$$;

ALTER FUNCTION private.generate_invite_token() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.generate_invite_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.generate_invite_token() FROM anon;
REVOKE ALL ON FUNCTION private.generate_invite_token() FROM authenticated;

CREATE OR REPLACE FUNCTION private.assert_can_manage_company_members(p_company_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;
  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner', 'admin']::public.company_role[],
    v_uid
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INSUFFICIENT_PRIVILEGES';
  END IF;
END;
$$;

ALTER FUNCTION private.assert_can_manage_company_members(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.assert_can_manage_company_members(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.assert_can_manage_company_members(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.assert_can_manage_company_members(UUID) FROM authenticated;

-- ---------------------------------------------------------------------------
-- list_company_members
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_company_members(
  p_company_id UUID
)
RETURNS TABLE (
  membership_id UUID,
  user_id UUID,
  email TEXT,
  full_name TEXT,
  role public.company_role,
  joined_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;
  IF NOT private.is_company_member(p_company_id, v_uid) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    m.user_id,
    p.email,
    p.full_name,
    m.role,
    m.joined_at
  FROM public.company_members m
  JOIN public.profiles p ON p.id = m.user_id
  WHERE m.company_id = p_company_id
  ORDER BY
    CASE m.role
      WHEN 'owner'::public.company_role THEN 0
      WHEN 'admin'::public.company_role THEN 1
      WHEN 'manager'::public.company_role THEN 2
      ELSE 3
    END,
    p.email ASC,
    m.joined_at ASC;
END;
$$;

ALTER FUNCTION public.list_company_members(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.list_company_members(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_company_members(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_company_members(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- list_company_invites (never returns token or token_hash)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_company_invites(
  p_company_id UUID
)
RETURNS TABLE (
  invite_id UUID,
  email_normalized TEXT,
  role public.company_role,
  invited_by UUID,
  created_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  status TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.assert_can_manage_company_members(p_company_id);

  RETURN QUERY
  SELECT
    i.id,
    i.email_normalized,
    i.role,
    i.invited_by,
    i.created_at,
    i.expires_at,
    i.accepted_at,
    i.revoked_at,
    CASE
      WHEN i.accepted_at IS NOT NULL THEN 'accepted'
      WHEN i.revoked_at IS NOT NULL THEN 'revoked'
      WHEN i.expires_at <= now() THEN 'expired'
      ELSE 'pending'
    END
  FROM public.company_invites i
  WHERE i.company_id = p_company_id
  ORDER BY i.created_at DESC;
END;
$$;

ALTER FUNCTION public.list_company_invites(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.list_company_invites(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_company_invites(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.list_company_invites(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- create_company_invite
-- Returns raw invite_token ONCE. Caller must treat it as a secret.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_company_invite(
  p_company_id UUID,
  p_email TEXT,
  p_role public.company_role,
  p_expires_in_hours INTEGER DEFAULT 168
)
RETURNS TABLE (
  invite_id UUID,
  email_normalized TEXT,
  role public.company_role,
  expires_at TIMESTAMPTZ,
  invite_token TEXT
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_email TEXT;
  v_token TEXT;
  v_hash TEXT;
  v_expires TIMESTAMPTZ;
  v_actor_is_owner BOOLEAN;
  v_id UUID;
BEGIN
  PERFORM private.assert_can_manage_company_members(p_company_id);

  v_email := private.normalize_invite_email(p_email);
  IF v_email IS NULL OR char_length(v_email) > 254 OR position('@' IN v_email) < 2 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_EMAIL_INVALID';
  END IF;

  IF p_role IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ROLE_REQUIRED';
  END IF;

  IF p_role = 'owner'::public.company_role THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ROLE_OWNER_FORBIDDEN';
  END IF;

  IF p_expires_in_hours IS NULL OR p_expires_in_hours < 1 OR p_expires_in_hours > 720 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_EXPIRY_INVALID';
  END IF;

  v_actor_is_owner := private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    v_uid
  );

  IF p_role = 'admin'::public.company_role AND NOT v_actor_is_owner THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ADMIN_ROLE_OWNER_ONLY';
  END IF;

  -- Existing member with same normalized email cannot be re-invited.
  IF EXISTS (
    SELECT 1
    FROM public.company_members m
    JOIN public.profiles p ON p.id = m.user_id
    WHERE m.company_id = p_company_id
      AND private.normalize_invite_email(p.email) = v_email
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ALREADY_MEMBER';
  END IF;

  -- Replace expired pending invite for same email; reject active pending.
  IF EXISTS (
    SELECT 1
    FROM public.company_invites i
    WHERE i.company_id = p_company_id
      AND i.email_normalized = v_email
      AND i.accepted_at IS NULL
      AND i.revoked_at IS NULL
      AND i.expires_at > now()
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ALREADY_PENDING';
  END IF;

  UPDATE public.company_invites i
  SET
    revoked_at = now(),
    revoked_by = v_uid
  WHERE i.company_id = p_company_id
    AND i.email_normalized = v_email
    AND i.accepted_at IS NULL
    AND i.revoked_at IS NULL
    AND i.expires_at <= now();

  v_token := private.generate_invite_token();
  v_hash := private.hash_invite_token(v_token);
  v_expires := now() + make_interval(hours => p_expires_in_hours);

  INSERT INTO public.company_invites (
    company_id,
    email_normalized,
    role,
    invited_by,
    token_hash,
    expires_at
  ) VALUES (
    p_company_id,
    v_email,
    p_role,
    v_uid,
    v_hash,
    v_expires
  )
  RETURNING id INTO v_id;

  RETURN QUERY
  SELECT v_id, v_email, p_role, v_expires, v_token;
END;
$$;

ALTER FUNCTION public.create_company_invite(UUID, TEXT, public.company_role, INTEGER) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_company_invite(UUID, TEXT, public.company_role, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_company_invite(UUID, TEXT, public.company_role, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company_invite(UUID, TEXT, public.company_role, INTEGER) TO authenticated;

-- ---------------------------------------------------------------------------
-- revoke_company_invite
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_company_invite(
  p_invite_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_invite public.company_invites%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_invite_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ID_REQUIRED';
  END IF;

  SELECT * INTO v_invite
  FROM public.company_invites i
  WHERE i.id = p_invite_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_NOT_FOUND';
  END IF;

  PERFORM private.assert_can_manage_company_members(v_invite.company_id);

  IF v_invite.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ALREADY_ACCEPTED';
  END IF;

  IF v_invite.revoked_at IS NOT NULL THEN
    RETURN; -- idempotent
  END IF;

  UPDATE public.company_invites
  SET revoked_at = now(), revoked_by = v_uid
  WHERE id = p_invite_id;
END;
$$;

ALTER FUNCTION public.revoke_company_invite(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.revoke_company_invite(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_company_invite(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.revoke_company_invite(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- accept_company_invite
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_company_invite(
  p_invite_token TEXT
)
RETURNS TABLE (
  company_id UUID,
  membership_id UUID,
  role public.company_role
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_token TEXT;
  v_hash TEXT;
  v_invite public.company_invites%ROWTYPE;
  v_auth_email TEXT;
  v_membership_id UUID;
  v_existing_role public.company_role;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;

  v_token := nullif(btrim(p_invite_token), '');
  IF v_token IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_TOKEN_REQUIRED';
  END IF;

  SELECT u.email
  INTO v_auth_email
  FROM auth.users u
  WHERE u.id = v_uid
    AND u.email_confirmed_at IS NOT NULL;

  IF v_auth_email IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_EMAIL_UNVERIFIED';
  END IF;

  v_hash := private.hash_invite_token(v_token);

  SELECT * INTO v_invite
  FROM public.company_invites i
  WHERE i.token_hash = v_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_NOT_FOUND';
  END IF;

  -- Idempotent: same user already accepted this invite.
  IF v_invite.accepted_at IS NOT NULL THEN
    IF v_invite.accepted_by IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ALREADY_ACCEPTED';
    END IF;
    SELECT m.id, m.role
    INTO v_membership_id, v_existing_role
    FROM public.company_members m
    WHERE m.company_id = v_invite.company_id
      AND m.user_id = v_uid;
    IF v_membership_id IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_ACCEPTANCE_INCONSISTENT';
    END IF;
    RETURN QUERY SELECT v_invite.company_id, v_membership_id, v_existing_role;
    RETURN;
  END IF;

  IF v_invite.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_REVOKED';
  END IF;

  IF v_invite.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_EXPIRED';
  END IF;

  IF private.normalize_invite_email(v_auth_email) IS DISTINCT FROM v_invite.email_normalized THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVITE_EMAIL_MISMATCH';
  END IF;

  SELECT m.id, m.role
  INTO v_membership_id, v_existing_role
  FROM public.company_members m
  WHERE m.company_id = v_invite.company_id
    AND m.user_id = v_uid;

  IF v_membership_id IS NOT NULL THEN
    -- Already a member: mark invite accepted idempotently without duplicate insert.
    UPDATE public.company_invites
    SET accepted_at = now(), accepted_by = v_uid
    WHERE id = v_invite.id;
    RETURN QUERY SELECT v_invite.company_id, v_membership_id, v_existing_role;
    RETURN;
  END IF;

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_invite.company_id, v_uid, v_invite.role)
  RETURNING id INTO v_membership_id;

  UPDATE public.company_invites
  SET accepted_at = now(), accepted_by = v_uid
  WHERE id = v_invite.id;

  RETURN QUERY SELECT v_invite.company_id, v_membership_id, v_invite.role;
END;
$$;

ALTER FUNCTION public.accept_company_invite(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.accept_company_invite(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_company_invite(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.accept_company_invite(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- change_company_member_role
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.change_company_member_role(
  p_company_id UUID,
  p_user_id UUID,
  p_role public.company_role
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_actor_is_owner BOOLEAN;
  v_target public.company_members%ROWTYPE;
BEGIN
  PERFORM private.assert_can_manage_company_members(p_company_id);

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_MEMBER_USER_ID_REQUIRED';
  END IF;
  IF p_role IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_MEMBER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_target
  FROM public.company_members m
  WHERE m.company_id = p_company_id
    AND m.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_MEMBER_NOT_FOUND';
  END IF;

  IF v_target.role IS NOT DISTINCT FROM p_role THEN
    RETURN;
  END IF;

  v_actor_is_owner := private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    v_uid
  );

  IF p_role = 'owner'::public.company_role AND NOT v_actor_is_owner THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_ONLY_OWNER_CAN_ASSIGN_OWNER';
  END IF;

  IF p_role = 'admin'::public.company_role AND NOT v_actor_is_owner THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_ONLY_OWNER_CAN_ASSIGN_ADMIN';
  END IF;

  -- Self-promotion / last-owner rules are enforced by integrity trigger.
  UPDATE public.company_members
  SET role = p_role
  WHERE company_id = p_company_id
    AND user_id = p_user_id;
END;
$$;

ALTER FUNCTION public.change_company_member_role(UUID, UUID, public.company_role) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.change_company_member_role(UUID, UUID, public.company_role) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.change_company_member_role(UUID, UUID, public.company_role) FROM anon;
GRANT EXECUTE ON FUNCTION public.change_company_member_role(UUID, UUID, public.company_role) TO authenticated;

-- ---------------------------------------------------------------------------
-- remove_company_member
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.remove_company_member(
  p_company_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_target public.company_members%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_MEMBER_USER_ID_REQUIRED';
  END IF;

  SELECT * INTO v_target
  FROM public.company_members m
  WHERE m.company_id = p_company_id
    AND m.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_MEMBER_NOT_FOUND';
  END IF;

  IF p_user_id = v_uid THEN
    IF v_target.role = 'owner'::public.company_role
       AND private.count_company_owners(p_company_id) <= 1 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CANNOT_REMOVE_LAST_OWNER';
    END IF;
  ELSE
    PERFORM private.assert_can_manage_company_members(p_company_id);
  END IF;

  DELETE FROM public.company_members
  WHERE company_id = p_company_id
    AND user_id = p_user_id;
END;
$$;

ALTER FUNCTION public.remove_company_member(UUID, UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.remove_company_member(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_company_member(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_company_member(UUID, UUID) TO authenticated;
