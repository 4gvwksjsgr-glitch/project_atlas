-- =============================================================================
-- Project Atlas — Step 14C-2B: checkout sessions + server-only RPCs
-- Additive. No Edge Functions / Paddle API / company_billing writes.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- -----------------------------------------------------------------------------
-- private.billing_checkout_sessions
-- -----------------------------------------------------------------------------
CREATE TABLE private.billing_checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL
    REFERENCES public.companies (id) ON DELETE CASCADE,
  provider_code TEXT NOT NULL,
  provider_environment TEXT NOT NULL,
  billing_provider_price_id UUID NOT NULL
    REFERENCES private.billing_provider_prices (id),
  atlas_plan_code TEXT NOT NULL,
  offer_code TEXT NOT NULL,
  initiated_by_user_id UUID NOT NULL
    REFERENCES auth.users (id),
  checkout_status TEXT NOT NULL,
  provider_create_status TEXT NOT NULL,
  browser_signal TEXT NOT NULL DEFAULT 'none',
  external_transaction_id TEXT NULL,
  checkout_url TEXT NULL,
  idempotency_key TEXT NOT NULL,
  return_token_hash TEXT NOT NULL,
  return_token_version INTEGER NOT NULL DEFAULT 1,
  return_token_consumed_at TIMESTAMPTZ NULL,
  allowed_return_origin TEXT NOT NULL,
  checkout_path TEXT NOT NULL,
  return_path TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  opened_at TIMESTAMPTZ NULL,
  returned_at TIMESTAMPTZ NULL,
  provider_last_error_sanitized TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT billing_checkout_sessions_environment_allowed
    CHECK (provider_environment IN ('test', 'live')),
  CONSTRAINT billing_checkout_sessions_checkout_status_allowed
    CHECK (
      checkout_status IN (
        'created', 'opened', 'expired', 'abandoned', 'failed'
      )
    ),
  CONSTRAINT billing_checkout_sessions_provider_create_status_allowed
    CHECK (
      provider_create_status IN (
        'not_started',
        'processing',
        'created',
        'outcome_unknown',
        'failed'
      )
    ),
  CONSTRAINT billing_checkout_sessions_browser_signal_allowed
    CHECK (
      browser_signal IN (
        'none', 'completion_signaled', 'checkout_closed'
      )
    ),
  CONSTRAINT billing_checkout_sessions_token_version_positive
    CHECK (return_token_version > 0),
  CONSTRAINT billing_checkout_sessions_expires_after_created
    CHECK (expires_at > created_at),
  CONSTRAINT billing_checkout_sessions_created_shape
    CHECK (
      (
        provider_create_status = 'created'
        AND external_transaction_id IS NOT NULL
        AND checkout_url IS NOT NULL
      )
      OR (
        provider_create_status IS DISTINCT FROM 'created'
      )
    ),
  CONSTRAINT billing_checkout_sessions_pre_create_no_txn
    CHECK (
      (
        provider_create_status IN ('not_started', 'processing')
        AND external_transaction_id IS NULL
      )
      OR (
        provider_create_status IS DISTINCT FROM 'not_started'
        AND provider_create_status IS DISTINCT FROM 'processing'
      )
    ),
  CONSTRAINT billing_checkout_sessions_failed_pairs_status
    CHECK (
      (
        provider_create_status = 'failed'
        AND checkout_status = 'failed'
      )
      OR provider_create_status IS DISTINCT FROM 'failed'
    ),
  CONSTRAINT billing_checkout_sessions_outcome_unknown_open
    CHECK (
      (
        provider_create_status = 'outcome_unknown'
        AND checkout_status IN ('created', 'opened')
      )
      OR provider_create_status IS DISTINCT FROM 'outcome_unknown'
    ),
  CONSTRAINT billing_checkout_sessions_idempotency_uidx
    UNIQUE (
      company_id,
      provider_code,
      provider_environment,
      idempotency_key
    )
);

COMMENT ON TABLE private.billing_checkout_sessions IS
  'Step 14C-2B: Atlas checkout sessions. No Premium; no company_billing writes.';

CREATE TRIGGER set_billing_checkout_sessions_updated_at
  BEFORE UPDATE ON private.billing_checkout_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE UNIQUE INDEX billing_checkout_sessions_one_open_uidx
  ON private.billing_checkout_sessions (
    company_id,
    provider_code,
    provider_environment
  )
  WHERE checkout_status IN ('created', 'opened');

CREATE UNIQUE INDEX billing_checkout_sessions_external_txn_uidx
  ON private.billing_checkout_sessions (
    provider_code,
    provider_environment,
    external_transaction_id
  )
  WHERE external_transaction_id IS NOT NULL;

ALTER TABLE private.billing_checkout_sessions OWNER TO postgres;
ALTER TABLE private.billing_checkout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.billing_checkout_sessions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.billing_checkout_sessions FROM PUBLIC;
REVOKE ALL ON TABLE private.billing_checkout_sessions FROM anon;
REVOKE ALL ON TABLE private.billing_checkout_sessions FROM authenticated;

-- -----------------------------------------------------------------------------
-- Token helpers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.billing_new_return_token_plain()
RETURNS TEXT
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT encode(extensions.gen_random_bytes(32), 'hex');
$$;

CREATE OR REPLACE FUNCTION private.billing_hash_return_token(p_plain TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT encode(
    extensions.digest(pg_catalog.convert_to(p_plain, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

ALTER FUNCTION private.billing_new_return_token_plain() OWNER TO postgres;
ALTER FUNCTION private.billing_hash_return_token(TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.billing_new_return_token_plain() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_new_return_token_plain() FROM anon;
REVOKE ALL ON FUNCTION private.billing_new_return_token_plain() FROM authenticated;
REVOKE ALL ON FUNCTION private.billing_hash_return_token(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.billing_hash_return_token(TEXT) FROM anon;
REVOKE ALL ON FUNCTION private.billing_hash_return_token(TEXT) FROM authenticated;

-- -----------------------------------------------------------------------------
-- Eligibility helper (shared by overview + reserve)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_company_checkout_eligible(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_cfg private.billing_runtime_config%ROWTYPE;
  v_offer private.billing_offers%ROWTYPE;
  v_price_id UUID;
  v_ent RECORD;
  v_open_count INTEGER;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF NOT private.is_company_member(p_company_id, p_actor_user_id) THEN
    RETURN FALSE;
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RETURN FALSE;
  END IF;

  SELECT *
  INTO v_cfg
  FROM private.billing_runtime_config c
  WHERE c.is_active
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_cfg.checkout_enabled IS DISTINCT FROM TRUE THEN
    RETURN FALSE;
  END IF;

  SELECT *
  INTO v_offer
  FROM private.billing_offers o
  WHERE o.offer_code = 'premium_monthly'
    AND o.is_active
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  SELECT p.id
  INTO v_price_id
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer.id
    AND p.provider_code = v_cfg.provider_code
    AND p.provider_environment = v_cfg.provider_environment
    AND p.is_active
    AND p.valid_to IS NULL
    AND p.valid_from <= p_now
  LIMIT 1;

  IF v_price_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT
    r.is_provider_grace,
    r.provider_access_status,
    r.billing_subscription_status
  INTO v_ent
  FROM private.resolve_company_entitlement(p_company_id, p_now) r;

  IF v_ent.provider_access_status IN ('entitled', 'grace')
    OR v_ent.is_provider_grace IS TRUE
  THEN
    RETURN FALSE;
  END IF;

  -- Active provider subscription blocks repurchase; ended does not.
  IF v_ent.billing_subscription_status = 'active' THEN
    RETURN FALSE;
  END IF;

  -- Open sessions block eligibility only while still within TTL.
  -- Do not UPDATE rows here; reserve materializes expired status later.
  SELECT count(*)::integer
  INTO v_open_count
  FROM private.billing_checkout_sessions s
  WHERE s.company_id = p_company_id
    AND s.provider_code = v_cfg.provider_code
    AND s.provider_environment = v_cfg.provider_environment
    AND s.checkout_status IN ('created', 'opened')
    AND s.expires_at > p_now;

  IF v_open_count > 0 THEN
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ) IS
  'Step 14C-2B: DB eligibility only (no runtime secrets).';

ALTER FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM anon;
REVOKE ALL ON FUNCTION private.is_company_checkout_eligible(UUID, UUID, TIMESTAMPTZ)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.reserve_billing_checkout_session
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.reserve_billing_checkout_session(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_offer_code TEXT,
  p_idempotency_key TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  session_id UUID,
  reuse BOOLEAN,
  provider_environment TEXT,
  billing_provider_price_id UUID,
  external_price_id TEXT,
  atlas_plan_code TEXT,
  offer_code TEXT,
  checkout_status TEXT,
  provider_create_status TEXT,
  return_token_plain TEXT,
  return_token_version INTEGER,
  expires_at TIMESTAMPTZ,
  existing_checkout_url TEXT,
  existing_external_transaction_id TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_cfg private.billing_runtime_config%ROWTYPE;
  v_offer private.billing_offers%ROWTYPE;
  v_price private.billing_provider_prices%ROWTYPE;
  v_existing private.billing_checkout_sessions%ROWTYPE;
  v_plain TEXT;
  v_hash TEXT;
  v_new_id UUID;
  v_expires TIMESTAMPTZ;
  v_ent RECORD;
  v_open_exists BOOLEAN;
BEGIN
  IF p_company_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_offer_code IS NULL OR btrim(p_offer_code) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_OFFER_CODE_REQUIRED';
  END IF;

  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  -- Lock order: subscription → billing
  PERFORM 1
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  PERFORM 1
  FROM private.company_billing b
  WHERE b.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  -- Expire open sessions past TTL
  UPDATE private.billing_checkout_sessions s
  SET
    checkout_status = 'expired',
    updated_at = p_now
  WHERE s.company_id = p_company_id
    AND s.checkout_status IN ('created', 'opened')
    AND s.expires_at <= p_now;

  IF NOT private.is_company_member(p_company_id, p_actor_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    p_company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  SELECT *
  INTO v_cfg
  FROM private.billing_runtime_config c
  WHERE c.is_active
  FOR UPDATE;

  IF NOT FOUND OR v_cfg.checkout_enabled IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_UNAVAILABLE';
  END IF;

  SELECT *
  INTO v_offer
  FROM private.billing_offers o
  WHERE o.offer_code = lower(btrim(p_offer_code))
    AND o.is_active
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_OFFER_NOT_FOUND';
  END IF;

  SELECT
    r.provider_access_status,
    r.is_provider_grace,
    r.billing_subscription_status
  INTO v_ent
  FROM private.resolve_company_entitlement(p_company_id, p_now) r;

  IF v_ent.provider_access_status IN ('entitled', 'grace')
    OR v_ent.is_provider_grace IS TRUE
    OR v_ent.billing_subscription_status = 'active'
  THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_NOT_ELIGIBLE';
  END IF;

  -- Idempotent reuse: snapshot from session FK, not current catalog price.
  SELECT *
  INTO v_existing
  FROM private.billing_checkout_sessions s
  WHERE s.company_id = p_company_id
    AND s.provider_code = v_cfg.provider_code
    AND s.provider_environment = v_cfg.provider_environment
    AND s.idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing.checkout_status NOT IN ('created', 'opened')
      OR v_existing.expires_at <= p_now
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_CHECKOUT_IDEMPOTENCY_CONFLICT';
    END IF;

    SELECT *
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.id = v_existing.billing_provider_price_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PRICE_UNAVAILABLE';
    END IF;

    v_plain := private.billing_new_return_token_plain();
    v_hash := private.billing_hash_return_token(v_plain);

    UPDATE private.billing_checkout_sessions s
    SET
      return_token_hash = v_hash,
      return_token_version = s.return_token_version + 1,
      return_token_consumed_at = NULL,
      updated_at = p_now
    WHERE s.id = v_existing.id
    RETURNING * INTO v_existing;

    session_id := v_existing.id;
    reuse := TRUE;
    provider_environment := v_existing.provider_environment;
    billing_provider_price_id := v_existing.billing_provider_price_id;
    external_price_id := v_price.external_price_id;
    atlas_plan_code := v_existing.atlas_plan_code;
    offer_code := v_existing.offer_code;
    checkout_status := v_existing.checkout_status;
    provider_create_status := v_existing.provider_create_status;
    return_token_plain := v_plain;
    return_token_version := v_existing.return_token_version;
    expires_at := v_existing.expires_at;
    existing_checkout_url := v_existing.checkout_url;
    existing_external_transaction_id := v_existing.external_transaction_id;
    RETURN NEXT;
    RETURN;
  END IF;

  -- New session: resolve current active catalog price.
  SELECT *
  INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.offer_id = v_offer.id
    AND p.provider_code = v_cfg.provider_code
    AND p.provider_environment = v_cfg.provider_environment
    AND p.is_active
    AND p.valid_to IS NULL
    AND p.valid_from <= p_now
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_PRICE_UNAVAILABLE';
  END IF;

  -- Another open non-expired session?
  SELECT EXISTS (
    SELECT 1
    FROM private.billing_checkout_sessions s
    WHERE s.company_id = p_company_id
      AND s.provider_code = v_cfg.provider_code
      AND s.provider_environment = v_cfg.provider_environment
      AND s.checkout_status IN ('created', 'opened')
      AND s.expires_at > p_now
  )
  INTO v_open_exists;

  IF v_open_exists THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_CHECKOUT_ALREADY_OPEN';
  END IF;

  v_plain := private.billing_new_return_token_plain();
  v_hash := private.billing_hash_return_token(v_plain);
  v_expires := p_now + interval '45 minutes';
  v_new_id := gen_random_uuid();

  INSERT INTO private.billing_checkout_sessions (
    id,
    company_id,
    provider_code,
    provider_environment,
    billing_provider_price_id,
    atlas_plan_code,
    offer_code,
    initiated_by_user_id,
    checkout_status,
    provider_create_status,
    browser_signal,
    idempotency_key,
    return_token_hash,
    return_token_version,
    allowed_return_origin,
    checkout_path,
    return_path,
    expires_at,
    created_at,
    updated_at
  ) VALUES (
    v_new_id,
    p_company_id,
    v_cfg.provider_code,
    v_cfg.provider_environment,
    v_price.id,
    v_offer.atlas_plan_code,
    v_offer.offer_code,
    p_actor_user_id,
    'created',
    'not_started',
    'none',
    p_idempotency_key,
    v_hash,
    1,
    v_cfg.payment_page_origin,
    v_cfg.checkout_path,
    v_cfg.return_path,
    v_expires,
    p_now,
    p_now
  );

  session_id := v_new_id;
  reuse := FALSE;
  provider_environment := v_cfg.provider_environment;
  billing_provider_price_id := v_price.id;
  external_price_id := v_price.external_price_id;
  atlas_plan_code := v_offer.atlas_plan_code;
  offer_code := v_offer.offer_code;
  checkout_status := 'created';
  provider_create_status := 'not_started';
  return_token_plain := v_plain;
  return_token_version := 1;
  expires_at := v_expires;
  existing_checkout_url := NULL;
  existing_external_transaction_id := NULL;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.reserve_billing_checkout_session(UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM anon;
REVOKE ALL ON FUNCTION private.reserve_billing_checkout_session(UUID, UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.attach_billing_checkout_provider_result (14C-2 matrix only)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.attach_billing_checkout_provider_result(
  p_session_id UUID,
  p_actor_user_id UUID,
  p_expected_from TEXT,
  p_to_status TEXT,
  p_external_transaction_id TEXT DEFAULT NULL,
  p_checkout_url TEXT DEFAULT NULL,
  p_error_sanitized TEXT DEFAULT NULL,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  applied BOOLEAN,
  session_id UUID,
  provider_create_status TEXT,
  checkout_status TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_sess private.billing_checkout_sessions%ROWTYPE;
  v_new_checkout_status TEXT;
BEGIN
  IF p_session_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  SELECT *
  INTO v_sess
  FROM private.billing_checkout_sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_SESSION_NOT_FOUND';
  END IF;

  IF NOT private.is_company_member(v_sess.company_id, p_actor_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    v_sess.company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  IF v_sess.checkout_status NOT IN ('created', 'opened')
    OR v_sess.expires_at <= p_now
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE';
  END IF;

  -- Rigid 14C-2 matrix
  IF NOT (
    (p_expected_from = 'not_started' AND p_to_status = 'processing')
    OR (
      p_expected_from = 'processing'
      AND p_to_status IN ('created', 'failed', 'outcome_unknown')
    )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_PROVIDER_CREATE_TRANSITION';
  END IF;

  IF p_to_status = 'created' THEN
    IF p_external_transaction_id IS NULL
      OR btrim(p_external_transaction_id) = ''
      OR p_checkout_url IS NULL
      OR btrim(p_checkout_url) = ''
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_CHECKOUT_PROVIDER_RESULT_INCOMPLETE';
    END IF;
  END IF;

  v_new_checkout_status := v_sess.checkout_status;
  IF p_to_status = 'failed' THEN
    v_new_checkout_status := 'failed';
  END IF;

  UPDATE private.billing_checkout_sessions s
  SET
    provider_create_status = p_to_status,
    checkout_status = v_new_checkout_status,
    external_transaction_id = CASE
      WHEN p_to_status = 'created' THEN btrim(p_external_transaction_id)
      ELSE s.external_transaction_id
    END,
    checkout_url = CASE
      WHEN p_to_status = 'created' THEN btrim(p_checkout_url)
      ELSE s.checkout_url
    END,
    provider_last_error_sanitized = CASE
      WHEN p_to_status IN ('failed', 'outcome_unknown') THEN p_error_sanitized
      ELSE s.provider_last_error_sanitized
    END,
    updated_at = p_now
  WHERE s.id = p_session_id
    AND s.provider_create_status = p_expected_from
  RETURNING * INTO v_sess;

  IF NOT FOUND THEN
    applied := FALSE;
    session_id := p_session_id;
    provider_create_status := NULL;
    checkout_status := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  applied := TRUE;
  session_id := v_sess.id;
  provider_create_status := v_sess.provider_create_status;
  checkout_status := v_sess.checkout_status;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.attach_billing_checkout_provider_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.attach_billing_checkout_provider_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.attach_billing_checkout_provider_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.attach_billing_checkout_provider_result(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;

-- -----------------------------------------------------------------------------
-- private.confirm_billing_checkout_browser_signal
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.confirm_billing_checkout_browser_signal(
  p_session_id UUID,
  p_actor_user_id UUID,
  p_return_token_plain TEXT,
  p_browser_signal TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  ok BOOLEAN,
  checkout_status TEXT,
  provider_create_status TEXT,
  browser_signal TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_sess private.billing_checkout_sessions%ROWTYPE;
  v_hash TEXT;
  v_new_checkout TEXT;
BEGIN
  IF p_session_id IS NULL OR p_actor_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  IF p_browser_signal IS NULL
    OR p_browser_signal NOT IN ('completion_signaled', 'checkout_closed')
  THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_INVALID_BROWSER_SIGNAL';
  END IF;

  IF p_return_token_plain IS NULL OR btrim(p_return_token_plain) = '' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_RETURN_TOKEN_REQUIRED';
  END IF;

  SELECT *
  INTO v_sess
  FROM private.billing_checkout_sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_CHECKOUT_SESSION_NOT_FOUND';
  END IF;

  IF NOT private.is_company_member(v_sess.company_id, p_actor_user_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_MEMBER';
  END IF;

  IF NOT private.has_company_role(
    v_sess.company_id,
    ARRAY['owner']::public.company_role[],
    p_actor_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_NOT_COMPANY_OWNER';
  END IF;

  IF v_sess.checkout_status NOT IN ('created', 'opened')
    OR v_sess.expires_at <= p_now
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_CHECKOUT_SESSION_NOT_CONFIRMABLE';
  END IF;

  IF v_sess.return_token_consumed_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_RETURN_TOKEN_CONSUMED';
  END IF;

  v_hash := private.billing_hash_return_token(p_return_token_plain);
  IF v_hash IS DISTINCT FROM v_sess.return_token_hash THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_RETURN_TOKEN_INVALID';
  END IF;

  v_new_checkout := v_sess.checkout_status;
  IF v_sess.checkout_status = 'created' THEN
    v_new_checkout := 'opened';
  END IF;

  UPDATE private.billing_checkout_sessions s
  SET
    browser_signal = p_browser_signal,
    returned_at = p_now,
    return_token_consumed_at = p_now,
    checkout_status = v_new_checkout,
    opened_at = coalesce(s.opened_at, p_now),
    updated_at = p_now
  WHERE s.id = p_session_id
  RETURNING * INTO v_sess;

  ok := TRUE;
  checkout_status := v_sess.checkout_status;
  provider_create_status := v_sess.provider_create_status;
  browser_signal := v_sess.browser_signal;
  RETURN NEXT;
END;
$$;

ALTER FUNCTION private.confirm_billing_checkout_browser_signal(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.confirm_billing_checkout_browser_signal(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.confirm_billing_checkout_browser_signal(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION private.confirm_billing_checkout_browser_signal(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.*_server wrappers (SECURITY DEFINER, service_role only)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reserve_billing_checkout_session_server(
  p_company_id UUID,
  p_actor_user_id UUID,
  p_offer_code TEXT,
  p_idempotency_key TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  session_id UUID,
  reuse BOOLEAN,
  provider_environment TEXT,
  billing_provider_price_id UUID,
  external_price_id TEXT,
  atlas_plan_code TEXT,
  offer_code TEXT,
  checkout_status TEXT,
  provider_create_status TEXT,
  return_token_plain TEXT,
  return_token_version INTEGER,
  expires_at TIMESTAMPTZ,
  existing_checkout_url TEXT,
  existing_external_transaction_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.reserve_billing_checkout_session(
    p_company_id,
    p_actor_user_id,
    p_offer_code,
    p_idempotency_key,
    p_now
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.attach_billing_checkout_provider_result_server(
  p_session_id UUID,
  p_actor_user_id UUID,
  p_expected_from TEXT,
  p_to_status TEXT,
  p_external_transaction_id TEXT DEFAULT NULL,
  p_checkout_url TEXT DEFAULT NULL,
  p_error_sanitized TEXT DEFAULT NULL,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  applied BOOLEAN,
  session_id UUID,
  provider_create_status TEXT,
  checkout_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.attach_billing_checkout_provider_result(
    p_session_id,
    p_actor_user_id,
    p_expected_from,
    p_to_status,
    p_external_transaction_id,
    p_checkout_url,
    p_error_sanitized,
    p_now
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_billing_checkout_browser_signal_server(
  p_session_id UUID,
  p_actor_user_id UUID,
  p_return_token_plain TEXT,
  p_browser_signal TEXT,
  p_now TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  ok BOOLEAN,
  checkout_status TEXT,
  provider_create_status TEXT,
  browser_signal TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.confirm_billing_checkout_browser_signal(
    p_session_id,
    p_actor_user_id,
    p_return_token_plain,
    p_browser_signal,
    p_now
  );
END;
$$;

ALTER FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
ALTER FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;
ALTER FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) TO service_role;

REVOKE ALL ON FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) TO service_role;

REVOKE ALL ON FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM anon;
REVOKE ALL ON FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) TO service_role;

COMMENT ON FUNCTION public.reserve_billing_checkout_session_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2B: service_role only. EF verifies JWT then passes jwt.sub as actor.';
COMMENT ON FUNCTION public.attach_billing_checkout_provider_result_server(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2B: service_role only. Rigid provider_create_status matrix.';
COMMENT ON FUNCTION public.confirm_billing_checkout_browser_signal_server(
  UUID, UUID, TEXT, TEXT, TIMESTAMPTZ
) IS
  'Step 14C-2B: service_role only. Consumes return token + browser_signal.';
