-- =============================================================================
-- Project Atlas — Working Step 17: referral RPCs
-- SECURITY DEFINER, search_path='', auth.uid()-derived actor.
-- No entitlement / Paddle mutation. Reward ledger only (max 5).
-- =============================================================================

CREATE OR REPLACE FUNCTION private.generate_referral_code()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
  v_raw TEXT;
BEGIN
  v_raw := encode(extensions.gen_random_bytes(24), 'base64');
  v_raw := replace(replace(replace(v_raw, '+', '-'), '/', '_'), '=', '');
  RETURN v_raw;
END;
$$;

ALTER FUNCTION private.generate_referral_code() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.generate_referral_code() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.generate_referral_code() FROM anon;
REVOKE ALL ON FUNCTION private.generate_referral_code() FROM authenticated;

CREATE OR REPLACE FUNCTION private.assert_company_owner(p_company_id UUID)
RETURNS UUID
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
    ARRAY['owner']::public.company_role[],
    v_uid
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INSUFFICIENT_PRIVILEGES';
  END IF;
  RETURN v_uid;
END;
$$;

ALTER FUNCTION private.assert_company_owner(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.assert_company_owner(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.assert_company_owner(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.assert_company_owner(UUID) FROM authenticated;

-- ---------------------------------------------------------------------------
-- get_or_create_company_referral_link — owner only
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_or_create_company_referral_link(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  code TEXT,
  created_at TIMESTAMPTZ,
  rewarded_count INTEGER,
  max_rewards INTEGER
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID;
  v_code TEXT;
  v_created TIMESTAMPTZ;
  v_attempt INTEGER := 0;
BEGIN
  v_uid := private.assert_company_owner(p_company_id);

  SELECT c.code, c.created_at
  INTO v_code, v_created
  FROM public.company_referral_codes c
  WHERE c.company_id = p_company_id
    AND c.revoked_at IS NULL
  LIMIT 1;

  IF v_code IS NULL THEN
    LOOP
      v_attempt := v_attempt + 1;
      IF v_attempt > 8 THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_CODE_GENERATE_FAILED';
      END IF;
      v_code := private.generate_referral_code();
      BEGIN
        INSERT INTO public.company_referral_codes (
          company_id, created_by, code
        ) VALUES (
          p_company_id, v_uid, v_code
        )
        RETURNING company_referral_codes.created_at INTO v_created;
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        -- Active-company conflict: another concurrent create won — re-read.
        SELECT c.code, c.created_at
        INTO v_code, v_created
        FROM public.company_referral_codes c
        WHERE c.company_id = p_company_id
          AND c.revoked_at IS NULL
        LIMIT 1;
        IF v_code IS NOT NULL THEN
          EXIT;
        END IF;
        -- Else code collision — retry with new random.
        CONTINUE;
      END;
    END LOOP;
  END IF;

  RETURN QUERY
  SELECT
    p_company_id,
    v_code,
    v_created,
    private.referral_reward_count(p_company_id),
    5;
END;
$$;

ALTER FUNCTION public.get_or_create_company_referral_link(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_or_create_company_referral_link(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_or_create_company_referral_link(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_company_referral_link(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- regenerate_company_referral_link — owner only; revokes prior active code
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.regenerate_company_referral_link(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  code TEXT,
  created_at TIMESTAMPTZ,
  rewarded_count INTEGER,
  max_rewards INTEGER
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID;
  v_code TEXT;
  v_created TIMESTAMPTZ;
  v_attempt INTEGER := 0;
BEGIN
  v_uid := private.assert_company_owner(p_company_id);

  UPDATE public.company_referral_codes c
  SET revoked_at = now(), revoked_by = v_uid
  WHERE c.company_id = p_company_id
    AND c.revoked_at IS NULL;

  LOOP
    v_attempt := v_attempt + 1;
    IF v_attempt > 8 THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_CODE_GENERATE_FAILED';
    END IF;
    v_code := private.generate_referral_code();
    BEGIN
      INSERT INTO public.company_referral_codes (
        company_id, created_by, code
      ) VALUES (
        p_company_id, v_uid, v_code
      )
      RETURNING company_referral_codes.created_at INTO v_created;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      CONTINUE;
    END;
  END LOOP;

  RETURN QUERY
  SELECT
    p_company_id,
    v_code,
    v_created,
    private.referral_reward_count(p_company_id),
    5;
END;
$$;

ALTER FUNCTION public.regenerate_company_referral_link(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.regenerate_company_referral_link(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.regenerate_company_referral_link(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.regenerate_company_referral_link(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- claim_referral — authenticated; before first owned company
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_referral(
  p_code TEXT
)
RETURNS TABLE (
  referral_id UUID,
  referring_company_id UUID,
  status TEXT,
  claimed_at TIMESTAMPTZ,
  already_claimed BOOLEAN
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_code TEXT;
  v_code_id UUID;
  v_company_id UUID;
  v_existing public.referrals%ROWTYPE;
  v_owner_count INTEGER;
  v_is_member BOOLEAN;
  v_new_id UUID;
  v_claimed_at TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_AUTHENTICATED';
  END IF;

  v_code := nullif(btrim(p_code), '');
  IF v_code IS NULL OR v_code !~ '^[A-Za-z0-9_-]{16,64}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_CODE_INVALID';
  END IF;

  -- Idempotent: already claimed returns existing row.
  SELECT * INTO v_existing
  FROM public.referrals r
  WHERE r.referred_user_id = v_uid;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      v_existing.id,
      v_existing.referring_company_id,
      v_existing.status,
      v_existing.claimed_at,
      true;
    RETURN;
  END IF;

  -- Qualification window: no owned companies yet.
  SELECT count(*)::INTEGER INTO v_owner_count
  FROM public.company_members m
  WHERE m.user_id = v_uid
    AND m.role = 'owner'::public.company_role;

  IF v_owner_count > 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_CLAIM_WINDOW_CLOSED';
  END IF;

  SELECT c.id, c.company_id
  INTO v_code_id, v_company_id
  FROM public.company_referral_codes c
  WHERE c.code = v_code
    AND c.revoked_at IS NULL;

  IF v_code_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_CODE_INVALID';
  END IF;

  -- Self-referral: owner or any member of referring company.
  SELECT EXISTS (
    SELECT 1
    FROM public.company_members m
    WHERE m.company_id = v_company_id
      AND m.user_id = v_uid
  ) INTO v_is_member;

  IF v_is_member THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_REFERRAL_SELF_DENIED';
  END IF;

  INSERT INTO public.referrals (
    referral_code_id,
    referring_company_id,
    referred_user_id,
    status
  ) VALUES (
    v_code_id,
    v_company_id,
    v_uid,
    'claimed'
  )
  RETURNING id, referrals.claimed_at INTO v_new_id, v_claimed_at;

  RETURN QUERY
  SELECT v_new_id, v_company_id, 'claimed'::TEXT, v_claimed_at, false;
END;
$$;

ALTER FUNCTION public.claim_referral(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_referral(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_referral(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.claim_referral(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- private.qualify_referral_on_company_create — called from create_company
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.qualify_referral_on_company_create(
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
  v_ref public.referrals%ROWTYPE;
  v_rewarded INTEGER;
  v_reward_id UUID;
BEGIN
  IF p_company_id IS NULL OR p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Serialize reward minting per referring company when we hold a claim.
  SELECT * INTO v_ref
  FROM public.referrals r
  WHERE r.referred_user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Already processed.
  IF v_ref.status IS DISTINCT FROM 'claimed' THEN
    RETURN;
  END IF;

  -- Lock referring company reward lane.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_ref.referring_company_id::text || ':referral_reward', 0)
  );

  -- Re-read after lock.
  SELECT * INTO v_ref
  FROM public.referrals r
  WHERE r.id = v_ref.id
  FOR UPDATE;

  IF v_ref.status IS DISTINCT FROM 'claimed' THEN
    RETURN;
  END IF;

  v_rewarded := private.referral_reward_count(v_ref.referring_company_id);

  IF v_rewarded >= 5 THEN
    UPDATE public.referrals r
    SET
      status = 'not_rewarded_limit_reached',
      qualified_at = now(),
      referred_company_id = p_company_id
    WHERE r.id = v_ref.id;
    RETURN;
  END IF;

  UPDATE public.referrals r
  SET
    status = 'rewarded',
    qualified_at = now(),
    referred_company_id = p_company_id
  WHERE r.id = v_ref.id;

  BEGIN
    INSERT INTO public.referral_rewards (
      referral_id,
      referring_company_id,
      reward_slot,
      reward_months,
      redemption_status
    ) VALUES (
      v_ref.id,
      v_ref.referring_company_id,
      (v_rewarded + 1)::SMALLINT,
      1,
      'pending'
    )
    RETURNING id INTO v_reward_id;
  EXCEPTION
    WHEN unique_violation THEN
      -- Under advisory lock this is rare; re-count and retry once or demote.
      v_rewarded := private.referral_reward_count(v_ref.referring_company_id);
      IF v_rewarded >= 5 THEN
        UPDATE public.referrals r
        SET
          status = 'not_rewarded_limit_reached',
          qualified_at = now(),
          referred_company_id = p_company_id
        WHERE r.id = v_ref.id;
      ELSE
        INSERT INTO public.referral_rewards (
          referral_id,
          referring_company_id,
          reward_slot,
          reward_months,
          redemption_status
        ) VALUES (
          v_ref.id,
          v_ref.referring_company_id,
          (v_rewarded + 1)::SMALLINT,
          1,
          'pending'
        )
        RETURNING id INTO v_reward_id;
      END IF;
  END;
END;
$$;

ALTER FUNCTION private.qualify_referral_on_company_create(UUID, UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.qualify_referral_on_company_create(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.qualify_referral_on_company_create(UUID, UUID) FROM anon;
REVOKE ALL ON FUNCTION private.qualify_referral_on_company_create(UUID, UUID) FROM authenticated;

-- ---------------------------------------------------------------------------
-- get_referral_overview — owner: full; members: counts only (no PII)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_referral_overview(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  code TEXT,
  rewarded_count INTEGER,
  max_rewards INTEGER,
  pending_redemption_months INTEGER,
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
    v_is_owner,
    CASE WHEN v_is_owner THEN v_items ELSE '[]'::JSONB END;
END;
$$;

ALTER FUNCTION public.get_referral_overview(UUID) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_referral_overview(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_referral_overview(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_referral_overview(UUID) TO authenticated;

COMMENT ON FUNCTION public.get_or_create_company_referral_link(UUID) IS
  'Owner-only: returns or creates the active company referral code. No entitlement mutation.';
COMMENT ON FUNCTION public.claim_referral(TEXT) IS
  'Authenticated claim of a referral code before first owned company. Idempotent per user.';
COMMENT ON FUNCTION public.get_referral_overview(UUID) IS
  'Members see reward counts; owners also see code and privacy-safe history.';
