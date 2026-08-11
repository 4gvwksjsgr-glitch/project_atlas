-- =============================================================================
-- Project Atlas — Step 14C-2F-B: Paddle Sandbox webhook inbox foundation
-- Additive. Inbox only — no company_billing / entitlement mutation.
-- Hard-coded provider_code=paddle, provider_environment=test.
-- Server time/retention: clock_timestamp() only (caller cannot supply p_now).
-- =============================================================================

DROP FUNCTION IF EXISTS public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT, TIMESTAMPTZ
);
DROP FUNCTION IF EXISTS private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT, TIMESTAMPTZ
);

-- -----------------------------------------------------------------------------
-- private.ingest_paddle_sandbox_webhook_event
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.ingest_paddle_sandbox_webhook_event(
  p_external_event_id TEXT,
  p_event_type TEXT,
  p_provider_created_at TIMESTAMPTZ,
  p_payload_hash TEXT,
  p_payload_json JSONB,
  p_classification TEXT,
  p_external_subscription_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_provider_code TEXT := 'paddle';
  v_provider_environment TEXT := 'test';
  v_processing_status TEXT;
  v_existing_id UUID;
  v_existing_hash TEXT;
  v_new_id UUID;
  v_sub TEXT;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF p_external_event_id IS NULL
    OR p_external_event_id !~ '^evt_[a-z0-9]{26}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_event_type IS NULL OR btrim(p_event_type) = '' OR char_length(p_event_type) > 128 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_provider_created_at IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_payload_hash IS NULL OR p_payload_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_payload_json IS NULL OR jsonb_typeof(p_payload_json) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_classification IS NULL
    OR p_classification NOT IN ('supported', 'ignored') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_classification = 'supported'
    AND p_event_type NOT IN (
      'subscription.created',
      'subscription.updated',
      'subscription.canceled',
      'subscription.past_due',
      'transaction.completed'
    ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  IF p_classification = 'supported' THEN
    v_processing_status := 'received';
  ELSE
    v_processing_status := 'ignored';
  END IF;

  v_sub := NULL;
  IF p_external_subscription_id IS NOT NULL
    AND btrim(p_external_subscription_id) <> '' THEN
    IF p_external_subscription_id !~ '^sub_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_INVALID_REQUEST';
    END IF;
    v_sub := p_external_subscription_id;
  END IF;

  SELECT e.id, e.payload_hash
  INTO v_existing_id, v_existing_hash
  FROM private.billing_provider_events e
  WHERE e.provider_code = v_provider_code
    AND e.provider_environment = v_provider_environment
    AND e.external_event_id = p_external_event_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing_hash IS DISTINCT FROM p_payload_hash THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_PAYLOAD_CONFLICT';
    END IF;
    outcome := 'duplicate';
    inbox_event_id := v_existing_id;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO private.billing_provider_events (
      provider_code,
      provider_environment,
      external_event_id,
      event_type,
      company_id,
      external_subscription_id,
      provider_created_at,
      processing_status,
      verification_status,
      signature_verified_at,
      payload_hash,
      payload_json,
      retention_expires_at,
      received_at
    ) VALUES (
      v_provider_code,
      v_provider_environment,
      p_external_event_id,
      p_event_type,
      NULL,
      v_sub,
      p_provider_created_at,
      v_processing_status,
      'verified',
      v_now,
      p_payload_hash,
      p_payload_json,
      v_now + interval '30 days',
      v_now
    )
    RETURNING id INTO v_new_id;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT e.id, e.payload_hash
      INTO v_existing_id, v_existing_hash
      FROM private.billing_provider_events e
      WHERE e.provider_code = v_provider_code
        AND e.provider_environment = v_provider_environment
        AND e.external_event_id = p_external_event_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_INTERNAL_ERROR';
      END IF;

      IF v_existing_hash IS DISTINCT FROM p_payload_hash THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_PAYLOAD_CONFLICT';
      END IF;

      outcome := 'duplicate';
      inbox_event_id := v_existing_id;
      RETURN NEXT;
      RETURN;
  END;

  outcome := 'inserted';
  inbox_event_id := v_new_id;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) IS
  '14C-2F-B: paddle/test webhook inbox insert. No billing/entitlement writes.';

ALTER FUNCTION private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) OWNER TO postgres;

REVOKE ALL ON FUNCTION private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM anon;
REVOKE ALL ON FUNCTION private.ingest_paddle_sandbox_webhook_event(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM authenticated;

-- -----------------------------------------------------------------------------
-- public.ingest_paddle_sandbox_webhook_event_server (service_role only)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  p_external_event_id TEXT,
  p_event_type TEXT,
  p_provider_created_at TIMESTAMPTZ,
  p_payload_hash TEXT,
  p_payload_json JSONB,
  p_classification TEXT,
  p_external_subscription_id TEXT DEFAULT NULL
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.ingest_paddle_sandbox_webhook_event(
    p_external_event_id,
    p_event_type,
    p_provider_created_at,
    p_payload_hash,
    p_payload_json,
    p_classification,
    p_external_subscription_id
  );
END;
$$;

COMMENT ON FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) IS
  '14C-2F-B: service_role only. EF verifies Paddle signature then ingests inbox.';

ALTER FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM anon;
REVOKE ALL ON FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_paddle_sandbox_webhook_event_server(
  TEXT, TEXT, TIMESTAMPTZ, TEXT, JSONB, TEXT, TEXT
) TO service_role;
