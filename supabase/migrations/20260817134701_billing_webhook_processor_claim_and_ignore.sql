-- =============================================================================
-- Project Atlas — Step 14C-2F Phase A
-- Webhook processor claim + simulator firewall + failure finalizer foundation.
--
-- Phase A only:
--   - claim inbox rows for processing (paddle/test hard-coded)
--   - simulator ntfsimevt_* events are terminal ignored (never normal claim)
--   - separate fail finalizer so failure state can persist after apply TX rollback
--
-- NO billing / subscription / entitlement mutations.
-- NO generic mark-processed RPC (deferred to apply phase).
-- NO table structure changes.
-- Processing lease: hard-coded 10 minutes (not caller-controlled).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.claim_paddle_sandbox_webhook_event_for_processing
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(
  p_inbox_event_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_provider_code TEXT := 'paddle';
  v_provider_environment TEXT := 'test';
  v_lease INTERVAL := interval '10 minutes';
  v_now TIMESTAMPTZ := clock_timestamp();
  v_row private.billing_provider_events%ROWTYPE;
  v_is_simulator BOOLEAN;
BEGIN
  IF p_inbox_event_id IS NULL THEN
    outcome := 'not_found';
    inbox_event_id := NULL;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT e.*
  INTO v_row
  FROM private.billing_provider_events e
  WHERE e.id = p_inbox_event_id
    AND e.provider_code = v_provider_code
    AND e.provider_environment = v_provider_environment
  FOR UPDATE;

  IF NOT FOUND THEN
    outcome := 'not_found';
    inbox_event_id := p_inbox_event_id;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.verification_status IS DISTINCT FROM 'verified' THEN
    outcome := 'not_verified';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  v_is_simulator := (
    v_row.external_event_id ~ '^ntfsimevt_[a-z0-9]{26}$'
  );

  -- -------------------------------------------------------------------------
  -- HARD SIMULATOR FIREWALL — runs before any normal claim / lease logic
  -- -------------------------------------------------------------------------
  IF v_is_simulator THEN
    IF v_row.processing_status = 'processed' THEN
      -- Fail-closed: simulator must never have been normally processed.
      outcome := 'simulator_processed_invariant';
      inbox_event_id := v_row.id;
      processing_status := v_row.processing_status;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    IF v_row.processing_status = 'ignored' THEN
      outcome := 'ignored';
      inbox_event_id := v_row.id;
      processing_status := v_row.processing_status;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    -- received / failed / processing (including fresh lease) -> ignored
    UPDATE private.billing_provider_events e
    SET
      processing_status = 'ignored',
      processed_at = v_now,
      error_sanitized = 'simulator_event'
    WHERE e.id = v_row.id;

    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := 'ignored';
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- -------------------------------------------------------------------------
  -- Normal (non-simulator) terminal no-ops
  -- -------------------------------------------------------------------------
  IF v_row.processing_status = 'processed' THEN
    outcome := 'processed';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status = 'ignored' THEN
    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- -------------------------------------------------------------------------
  -- Fresh processing lease -> busy (no attempt increment)
  -- -------------------------------------------------------------------------
  IF v_row.processing_status = 'processing'
    AND v_row.last_attempt_at IS NOT NULL
    AND v_row.last_attempt_at > v_now - v_lease THEN
    outcome := 'busy';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- -------------------------------------------------------------------------
  -- Claim / reclaim: received, failed, or stuck processing
  -- -------------------------------------------------------------------------
  IF v_row.processing_status = 'processing'
    AND (
      v_row.last_attempt_at IS NULL
      OR v_row.last_attempt_at <= v_now - v_lease
    ) THEN
    UPDATE private.billing_provider_events e
    SET
      processing_status = 'processing',
      attempt_count = e.attempt_count + 1,
      last_attempt_at = v_now,
      error_sanitized = NULL,
      processed_at = NULL
    WHERE e.id = v_row.id
    RETURNING e.attempt_count INTO attempt_count;

    outcome := 'reclaimed';
    inbox_event_id := v_row.id;
    processing_status := 'processing';
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status IN ('received', 'failed') THEN
    UPDATE private.billing_provider_events e
    SET
      processing_status = 'processing',
      attempt_count = e.attempt_count + 1,
      last_attempt_at = v_now,
      error_sanitized = NULL,
      processed_at = NULL
    WHERE e.id = v_row.id
    RETURNING e.attempt_count INTO attempt_count;

    outcome := 'claimed';
    inbox_event_id := v_row.id;
    processing_status := 'processing';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Unexpected status: non-mutating fail-closed
  outcome := 'invalid_state';
  inbox_event_id := v_row.id;
  processing_status := v_row.processing_status;
  attempt_count := v_row.attempt_count;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(UUID) IS
  '14C-2F Phase A: claim paddle/test inbox for processing. '
  'Simulator ntfsimevt_* -> terminal ignored before normal claim. '
  'Hard-coded 10-minute processing lease. '
  'No billing/subscription/entitlement mutations. No mark-processed.';

ALTER FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(UUID)
  FROM anon;
REVOKE ALL ON FUNCTION private.claim_paddle_sandbox_webhook_event_for_processing(UUID)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.claim_paddle_sandbox_webhook_event_for_processing_server
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(
  p_inbox_event_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.claim_paddle_sandbox_webhook_event_for_processing(
    p_inbox_event_id
  );
END;
$$;

COMMENT ON FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID) IS
  '14C-2F Phase A: service_role-only claim wrapper. '
  'Simulator firewall + 10-minute lease. No billing mutations. '
  'No generic mark-processed RPC in Phase A.';

ALTER FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID)
  FROM anon;
REVOKE ALL ON FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_paddle_sandbox_webhook_event_for_processing_server(UUID)
  TO service_role;

-- -----------------------------------------------------------------------------
-- private.fail_paddle_sandbox_webhook_event_processing
-- Separate TX from apply mutations so failure state can persist after rollback.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fail_paddle_sandbox_webhook_event_processing(
  p_inbox_event_id UUID,
  p_error_code TEXT
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_provider_code TEXT := 'paddle';
  v_provider_environment TEXT := 'test';
  v_now TIMESTAMPTZ := clock_timestamp();
  v_row private.billing_provider_events%ROWTYPE;
  v_is_simulator BOOLEAN;
BEGIN
  -- Order: lock -> not_found -> verification -> simulator firewall ->
  -- normal terminal/invalid_state -> ONLY THEN validate p_error_code -> failed.
  IF p_inbox_event_id IS NULL THEN
    outcome := 'not_found';
    inbox_event_id := NULL;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT e.*
  INTO v_row
  FROM private.billing_provider_events e
  WHERE e.id = p_inbox_event_id
    AND e.provider_code = v_provider_code
    AND e.provider_environment = v_provider_environment
  FOR UPDATE;

  IF NOT FOUND THEN
    outcome := 'not_found';
    inbox_event_id := p_inbox_event_id;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.verification_status IS DISTINCT FROM 'verified' THEN
    outcome := 'not_verified';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  v_is_simulator := (
    v_row.external_event_id ~ '^ntfsimevt_[a-z0-9]{26}$'
  );

  -- HARD SIMULATOR FIREWALL — before p_error_code validation.
  -- Invalid/NULL error codes must not prevent simulator neutralization.
  IF v_is_simulator THEN
    IF v_row.processing_status = 'processed' THEN
      outcome := 'simulator_processed_invariant';
      inbox_event_id := v_row.id;
      processing_status := v_row.processing_status;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    IF v_row.processing_status = 'ignored' THEN
      outcome := 'ignored';
      inbox_event_id := v_row.id;
      processing_status := v_row.processing_status;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    -- received / failed / processing -> ignored (p_error_code ignored)
    UPDATE private.billing_provider_events e
    SET
      processing_status = 'ignored',
      processed_at = v_now,
      error_sanitized = 'simulator_event'
    WHERE e.id = v_row.id;

    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := 'ignored';
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Non-simulator terminal no-ops: no p_error_code validation needed.
  IF v_row.processing_status IN ('processed', 'ignored') THEN
    outcome := v_row.processing_status;
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status IS DISTINCT FROM 'processing' THEN
    outcome := 'invalid_state';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Eligible normal processing -> failed: validate sanitized machine code now.
  IF p_error_code IS NULL
    OR p_error_code !~ '^[A-Z0-9_]{1,128}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  UPDATE private.billing_provider_events e
  SET
    processing_status = 'failed',
    error_sanitized = p_error_code,
    processed_at = NULL
  WHERE e.id = v_row.id;

  outcome := 'failed';
  inbox_event_id := v_row.id;
  processing_status := 'failed';
  attempt_count := v_row.attempt_count;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.fail_paddle_sandbox_webhook_event_processing(UUID, TEXT) IS
  '14C-2F Phase A: separate failure finalizer for paddle/test inbox. '
  'Order: lock, verify, simulator firewall, then p_error_code only for normal processing->failed. '
  'Call after a failed apply transaction so failed state persists. '
  'Simulator events forced/kept ignored (never failed); invalid error codes cannot block firewall. '
  'No billing/subscription/entitlement mutations. No attempt_count increment.';

ALTER FUNCTION private.fail_paddle_sandbox_webhook_event_processing(UUID, TEXT)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.fail_paddle_sandbox_webhook_event_processing(UUID, TEXT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.fail_paddle_sandbox_webhook_event_processing(UUID, TEXT)
  FROM anon;
REVOKE ALL ON FUNCTION private.fail_paddle_sandbox_webhook_event_processing(UUID, TEXT)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.fail_paddle_sandbox_webhook_event_processing_server
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(
  p_inbox_event_id UUID,
  p_error_code TEXT
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.fail_paddle_sandbox_webhook_event_processing(
    p_inbox_event_id,
    p_error_code
  );
END;
$$;

COMMENT ON FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT) IS
  '14C-2F Phase A: service_role-only failure finalizer wrapper. '
  'Separate from apply TX so failure persists after rollback. '
  'No billing mutations. Sanitized machine error codes only.';

ALTER FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT)
  FROM anon;
REVOKE ALL ON FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT)
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fail_paddle_sandbox_webhook_event_processing_server(UUID, TEXT)
  TO service_role;
