-- =============================================================================
-- Project Atlas — Step 14C-2F Phase D
-- Webhook apply processor foundation (paddle/test).
--
-- Additive:
--   - company_billing.last_subscription_event_occurred_at (subscription-state watermark)
--   - ingest allowlist: subscription.activated
--   - private.apply_paddle_sandbox_webhook_event (id-only; reads inbox payload_json)
--   - public.apply_paddle_sandbox_webhook_event_server (service_role only)
--
-- NO generic mark-processed RPC.
-- NO Edge Function / processor invoker.
-- NO grace invent; past_due → blocked.
-- Simulator firewall unchanged in principle (apply refuses ntfsimevt_* mutation).
-- Lock order: inbox → company_subscriptions → company_billing → checkout session
--   (checkout session last; matches reserve which locks session after sub/billing).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Watermark column (authoritative subscription events only)
-- -----------------------------------------------------------------------------
ALTER TABLE private.company_billing
  ADD COLUMN IF NOT EXISTS last_subscription_event_occurred_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN private.company_billing.last_subscription_event_occurred_at IS
  'Last successfully applied AUTHORITATIVE subscription-state webhook '
  'occurred_at (inbox.provider_created_at). Advanced only by subscription.* '
  'events (created/updated/activated/canceled/past_due). Never by '
  'transaction.completed. Opaque provider_object_version(_at) remain separate.';

-- -----------------------------------------------------------------------------
-- Ingest: add subscription.activated to supported classification allowlist
-- (full function replace; historical migrations untouched)
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
    OR p_external_event_id !~ '^(?:evt|ntfsimevt)_[a-z0-9]{26}$' THEN
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
      'subscription.activated',
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
  '14C-2F Phase D: paddle/test inbox. Supports subscription.activated. '
  'Accepts evt_/ntfsimevt_ event ids. No billing writes.';

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

-- -----------------------------------------------------------------------------
-- private.apply_paddle_sandbox_webhook_event
-- Id-only apply. Derives all business values from locked inbox.payload_json.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.apply_paddle_sandbox_webhook_event(
  p_inbox_event_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  company_id UUID,
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
  v_payload JSONB;
  v_data JSONB;
  v_event_type TEXT;
  v_is_subscription BOOLEAN;
  v_is_transaction BOOLEAN;
  v_paddle_status TEXT;
  v_customer_id TEXT;
  v_subscription_id TEXT;
  v_transaction_id TEXT;
  v_price_id TEXT;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
  v_canceled_at TIMESTAMPTZ;
  v_cancel_at_period_end BOOLEAN := FALSE;
  v_custom JSONB;
  v_schema_version INTEGER;
  v_atlas_company_id UUID;
  v_atlas_session_id UUID;
  v_atlas_offer_code TEXT;
  v_company_id UUID;
  v_bill private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;
  v_sess private.billing_checkout_sessions%ROWTYPE;
  v_price private.billing_provider_prices%ROWTYPE;
  v_owner_by_sub UUID;
  v_owner_by_cus UUID;
  v_need_session_lock BOOLEAN := FALSE;
  v_target_sub_status TEXT;
  v_target_pay_status TEXT;
  v_target_access TEXT;
  v_target_access_ends TIMESTAMPTZ;
  v_target_grace_ends TIMESTAMPTZ := NULL;
  v_target_cancel_at_end BOOLEAN := FALSE;
  v_target_canceled_at TIMESTAMPTZ := NULL;
  v_target_period_start TIMESTAMPTZ := NULL;
  v_target_period_end TIMESTAMPTZ := NULL;
  v_cs_origin TEXT;
  v_cs_plan TEXT;
  v_cs_status TEXT;
  v_cs_trial_start TIMESTAMPTZ;
  v_cs_trial_end TIMESTAMPTZ;
  v_cs_trial_used TIMESTAMPTZ;
  v_equiv BOOLEAN;
  v_tmp TEXT;
  v_tmp_num NUMERIC;
BEGIN
  IF p_inbox_event_id IS NULL THEN
    outcome := 'not_found';
    inbox_event_id := NULL;
    processing_status := NULL;
    company_id := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- 1) Lock inbox
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
    company_id := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.verification_status IS DISTINCT FROM 'verified' THEN
    outcome := 'not_verified';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Simulator hard firewall — never mutate billing/subs
  IF v_row.external_event_id ~ '^ntfsimevt_[a-z0-9]{26}$' THEN
    IF v_row.processing_status = 'processed' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_SIMULATOR_PROCESSED_INVARIANT';
    END IF;
    IF v_row.processing_status IS DISTINCT FROM 'ignored' THEN
      UPDATE private.billing_provider_events e
      SET
        processing_status = 'ignored',
        processed_at = v_now,
        error_sanitized = 'simulator_event'
      WHERE e.id = v_row.id;
    END IF;
    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := 'ignored';
    company_id := NULL;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status = 'processed' THEN
    outcome := 'already_processed';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status = 'ignored' THEN
    outcome := 'ignored';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.processing_status IS DISTINCT FROM 'processing' THEN
    outcome := 'invalid_state';
    inbox_event_id := v_row.id;
    processing_status := v_row.processing_status;
    company_id := v_row.company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_row.payload_json IS NULL OR jsonb_typeof(v_row.payload_json) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING';
  END IF;

  IF v_row.external_event_id !~ '^evt_[a-z0-9]{26}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_INVALID_REQUEST';
  END IF;

  v_payload := v_row.payload_json;
  v_event_type := v_row.event_type;

  IF v_event_type IS NULL OR v_event_type NOT IN (
    'subscription.created',
    'subscription.updated',
    'subscription.activated',
    'subscription.canceled',
    'subscription.past_due',
    'transaction.completed'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED';
  END IF;

  v_is_subscription := v_event_type LIKE 'subscription.%';
  v_is_transaction := v_event_type = 'transaction.completed';

  v_data := v_payload -> 'data';
  IF v_data IS NULL OR jsonb_typeof(v_data) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  -- Root occurred_at must match inbox.provider_created_at when present
  IF v_payload ? 'occurred_at' THEN
    BEGIN
      IF (v_payload ->> 'occurred_at')::timestamptz IS DISTINCT FROM v_row.provider_created_at THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
      END IF;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  IF v_row.provider_created_at IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  -- Extract IDs / status
  v_paddle_status := lower(btrim(COALESCE(v_data ->> 'status', '')));
  IF v_paddle_status = '' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  v_customer_id := btrim(COALESCE(v_data ->> 'customer_id', ''));
  IF v_customer_id = '' OR v_customer_id !~ '^ctm_[a-z0-9]{26}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
  END IF;

  IF v_is_subscription THEN
    v_subscription_id := btrim(COALESCE(v_data ->> 'id', ''));
    IF v_subscription_id = '' OR v_subscription_id !~ '^sub_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
  ELSE
    v_transaction_id := btrim(COALESCE(v_data ->> 'id', ''));
    IF v_transaction_id = '' OR v_transaction_id !~ '^txn_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
    v_subscription_id := btrim(COALESCE(v_data ->> 'subscription_id', ''));
    IF v_subscription_id = '' OR v_subscription_id !~ '^sub_[a-z0-9]{26}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
  END IF;

  -- Price id from items[0].price.id
  v_price_id := NULL;
  IF jsonb_typeof(v_data -> 'items') = 'array'
    AND jsonb_array_length(v_data -> 'items') > 0 THEN
    v_tmp := btrim(COALESCE(v_data -> 'items' -> 0 -> 'price' ->> 'id', ''));
    IF v_tmp <> '' THEN
      IF v_tmp !~ '^pri_[a-z0-9]{26}$' THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
      END IF;
      v_price_id := v_tmp;
    END IF;
  END IF;

  -- Period bounds (subscription events)
  v_period_start := NULL;
  v_period_end := NULL;
  IF v_is_subscription
    AND jsonb_typeof(v_data -> 'current_billing_period') = 'object' THEN
    BEGIN
      IF (v_data -> 'current_billing_period') ? 'starts_at'
        AND nullif(btrim(v_data -> 'current_billing_period' ->> 'starts_at'), '') IS NOT NULL THEN
        v_period_start := (v_data -> 'current_billing_period' ->> 'starts_at')::timestamptz;
      END IF;
      IF (v_data -> 'current_billing_period') ? 'ends_at'
        AND nullif(btrim(v_data -> 'current_billing_period' ->> 'ends_at'), '') IS NOT NULL THEN
        v_period_end := (v_data -> 'current_billing_period' ->> 'ends_at')::timestamptz;
      END IF;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  v_canceled_at := NULL;
  IF v_is_subscription
    AND nullif(btrim(COALESCE(v_data ->> 'canceled_at', '')), '') IS NOT NULL THEN
    BEGIN
      v_canceled_at := (v_data ->> 'canceled_at')::timestamptz;
    EXCEPTION
      WHEN others THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  -- Scheduled cancellation while still active
  IF v_is_subscription
    AND jsonb_typeof(v_data -> 'scheduled_change') = 'object'
    AND lower(btrim(COALESCE(v_data -> 'scheduled_change' ->> 'action', ''))) = 'cancel'
  THEN
    v_cancel_at_period_end := TRUE;
  END IF;

  -- custom_data (optional unless first-link)
  v_custom := NULL;
  IF v_data ? 'custom_data' AND jsonb_typeof(v_data -> 'custom_data') = 'object' THEN
    v_custom := v_data -> 'custom_data';
  END IF;

  v_schema_version := NULL;
  v_atlas_company_id := NULL;
  v_atlas_session_id := NULL;
  v_atlas_offer_code := NULL;
  IF v_custom IS NOT NULL THEN
    BEGIN
      IF v_custom ? 'atlas_schema_version' THEN
        v_tmp_num := (v_custom ->> 'atlas_schema_version')::numeric;
        IF v_tmp_num <> trunc(v_tmp_num) THEN
          RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA';
        END IF;
        v_schema_version := v_tmp_num::integer;
        IF v_schema_version IS DISTINCT FROM 1 THEN
          RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA';
        END IF;
      END IF;
      IF v_custom ? 'atlas_company_id'
        AND nullif(btrim(v_custom ->> 'atlas_company_id'), '') IS NOT NULL THEN
        v_atlas_company_id := (v_custom ->> 'atlas_company_id')::uuid;
      END IF;
      IF v_custom ? 'atlas_checkout_session_id'
        AND nullif(btrim(v_custom ->> 'atlas_checkout_session_id'), '') IS NOT NULL THEN
        v_atlas_session_id := (v_custom ->> 'atlas_checkout_session_id')::uuid;
      END IF;
      IF v_custom ? 'atlas_offer_code' THEN
        v_atlas_offer_code := lower(btrim(COALESCE(v_custom ->> 'atlas_offer_code', '')));
        IF v_atlas_offer_code = '' THEN
          v_atlas_offer_code := NULL;
        END IF;
      END IF;
    EXCEPTION
      WHEN others THEN
        IF SQLERRM LIKE 'ATLAS_%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END;
  END IF;

  -- Resolve existing owners (read-only evidence before row locks)
  SELECT b.company_id
  INTO v_owner_by_sub
  FROM private.company_billing b
  WHERE b.provider_code = v_provider_code
    AND b.provider_environment = v_provider_environment
    AND b.external_subscription_id = v_subscription_id
  LIMIT 1;

  SELECT b.company_id
  INTO v_owner_by_cus
  FROM private.company_billing b
  WHERE b.provider_code = v_provider_code
    AND b.provider_environment = v_provider_environment
    AND b.external_customer_id = v_customer_id
  LIMIT 1;

  IF v_owner_by_sub IS NOT NULL AND v_owner_by_cus IS NOT NULL
    AND v_owner_by_sub IS DISTINCT FROM v_owner_by_cus THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF v_owner_by_sub IS NOT NULL THEN
    v_company_id := v_owner_by_sub;
  ELSIF v_owner_by_cus IS NOT NULL THEN
    v_company_id := v_owner_by_cus;
  ELSE
    -- P2 first-link: full checkout proof required
    IF v_atlas_company_id IS NULL
      OR v_atlas_session_id IS NULL
      OR v_atlas_offer_code IS NULL
      OR v_schema_version IS DISTINCT FROM 1
      OR v_price_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_UNLINKED';
    END IF;

    SELECT s.*
    INTO v_sess
    FROM private.billing_checkout_sessions s
    WHERE s.id = v_atlas_session_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_UNLINKED';
    END IF;

    -- Session must be an open, non-expired, provider-created checkout.
    -- Note: sessions do NOT store customer_id or subscription_id; those
    -- cannot be cross-checked against checkout rows with the current schema.
    IF v_sess.company_id IS DISTINCT FROM v_atlas_company_id
      OR v_sess.provider_code IS DISTINCT FROM v_provider_code
      OR v_sess.provider_environment IS DISTINCT FROM v_provider_environment
      OR v_sess.offer_code IS DISTINCT FROM v_atlas_offer_code
      OR v_atlas_offer_code IS DISTINCT FROM 'premium_monthly'
      OR v_sess.checkout_status NOT IN ('created', 'opened')
      OR v_sess.expires_at <= v_now
      OR v_sess.provider_create_status IS DISTINCT FROM 'created'
      OR v_sess.external_transaction_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;

    SELECT p.*
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.id = v_sess.billing_provider_price_id;

    IF NOT FOUND
      OR v_price.provider_code IS DISTINCT FROM v_provider_code
      OR v_price.provider_environment IS DISTINCT FROM v_provider_environment
      OR v_price.external_price_id IS DISTINCT FROM v_price_id
      OR v_price.is_active IS DISTINCT FROM TRUE
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PRICE_MISMATCH';
    END IF;

    -- Transaction id must match session when applying transaction.completed.
    -- subscription.* first-link cannot compare txn id from subscription payload;
    -- session.external_transaction_id presence was already required above.
    IF v_is_transaction
      AND v_sess.external_transaction_id IS DISTINCT FROM v_transaction_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;

    v_company_id := v_sess.company_id;
    v_need_session_lock := TRUE;
  END IF;

  -- Linked path: if custom_data company present it must match
  IF v_atlas_company_id IS NOT NULL
    AND v_atlas_company_id IS DISTINCT FROM v_company_id THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- Price required when establishing or changing price / entitled path
  IF v_price_id IS NOT NULL THEN
    SELECT p.*
    INTO v_price
    FROM private.billing_provider_prices p
    WHERE p.provider_code = v_provider_code
      AND p.provider_environment = v_provider_environment
      AND p.external_price_id = v_price_id
      AND p.is_active IS TRUE
    LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PRICE_MISMATCH';
    END IF;
  END IF;

  -- 3) Lock subscriptions then billing (global order)
  SELECT cs.*
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  IF v_sub.entitlement_origin = 'manual' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT';
  END IF;

  SELECT b.*
  INTO v_bill
  FROM private.company_billing b
  WHERE b.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_BILLING_NOT_FOUND';
  END IF;

  -- Refuse overwriting a different provider / environment link
  IF (
      v_bill.provider_code IS NOT NULL
      AND v_bill.provider_code IS DISTINCT FROM v_provider_code
    )
    OR (
      v_bill.provider_environment IS NOT NULL
      AND v_bill.provider_environment IS DISTINCT FROM v_provider_environment
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- Re-validate unique ownership under locks
  IF v_bill.external_subscription_id IS NOT NULL
    AND v_bill.external_subscription_id IS DISTINCT FROM v_subscription_id
    AND v_owner_by_sub IS NULL THEN
    -- company already has a different subscription
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.company_billing b
    WHERE b.provider_code = v_provider_code
      AND b.provider_environment = v_provider_environment
      AND b.external_subscription_id = v_subscription_id
      AND b.company_id IS DISTINCT FROM v_company_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM private.company_billing b
    WHERE b.provider_code = v_provider_code
      AND b.provider_environment = v_provider_environment
      AND b.external_customer_id = v_customer_id
      AND b.company_id IS DISTINCT FROM v_company_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END IF;

  -- 5) Checkout session lock last (first-link only)
  IF v_need_session_lock THEN
    SELECT s.*
    INTO v_sess
    FROM private.billing_checkout_sessions s
    WHERE s.id = v_atlas_session_id
    FOR UPDATE;

    IF NOT FOUND
      OR v_sess.company_id IS DISTINCT FROM v_company_id
      OR v_sess.offer_code IS DISTINCT FROM v_atlas_offer_code
      OR v_sess.checkout_status NOT IN ('created', 'opened')
      OR v_sess.expires_at <= v_now
      OR v_sess.provider_create_status IS DISTINCT FROM 'created'
      OR v_sess.external_transaction_id IS NULL
      OR (
        v_is_transaction
        AND v_sess.external_transaction_id IS DISTINCT FROM v_transaction_id
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END IF;
  END IF;

  -- Paddle trialing = configuration drift (no provider trial)
  IF v_is_subscription AND v_paddle_status = 'trialing' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED';
  END IF;

  -- Transaction.completed: linkage + payment assist only (non-authoritative)
  IF v_is_transaction THEN
    IF v_paddle_status IS DISTINCT FROM 'completed' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;
    IF v_price_id IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;

    BEGIN
      UPDATE private.company_billing b
      SET
        provider_code = v_provider_code,
        provider_environment = v_provider_environment,
        external_customer_id = v_customer_id,
        external_subscription_id = v_subscription_id,
        external_price_id = v_price_id,
        payment_status = CASE
          WHEN b.provider_access_status = 'entitled' THEN 'ok'
          WHEN b.payment_status = 'past_due' THEN b.payment_status
          ELSE 'ok'
        END,
        sync_status = 'idle',
        last_sync_result = 'succeeded',
        last_synced_at = v_now,
        last_sync_error_sanitized = NULL,
        updated_at = v_now
      WHERE b.company_id = v_company_id;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION USING
          ERRCODE = 'P0001',
          MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
    END;

    -- Do NOT mutate company_subscriptions entitlement from transaction alone.
    -- Do NOT advance last_subscription_event_occurred_at.

    UPDATE private.billing_provider_events e
    SET
      company_id = v_company_id,
      external_subscription_id = v_subscription_id,
      processing_status = 'processed',
      processed_at = v_now,
      error_sanitized = NULL
    WHERE e.id = v_row.id;

    outcome := 'applied';
    inbox_event_id := v_row.id;
    processing_status := 'processed';
    company_id := v_company_id;
    attempt_count := v_row.attempt_count;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Authoritative subscription-state ordering gate
  IF v_bill.last_subscription_event_occurred_at IS NOT NULL THEN
    IF v_row.provider_created_at < v_bill.last_subscription_event_occurred_at THEN
      UPDATE private.billing_provider_events e
      SET
        company_id = COALESCE(e.company_id, v_company_id),
        processing_status = 'ignored',
        processed_at = v_now,
        error_sanitized = 'stale_event'
      WHERE e.id = v_row.id;

      outcome := 'stale';
      inbox_event_id := v_row.id;
      processing_status := 'ignored';
      company_id := v_company_id;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  -- Map paddle status → atlas targets
  -- Period order: if both bounds present, must be ordered (all statuses).
  IF v_period_start IS NOT NULL
    AND v_period_end IS NOT NULL
    AND v_period_end <= v_period_start THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
  END IF;

  IF v_paddle_status = 'active' THEN
    IF v_period_start IS NULL OR v_period_end IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
    END IF;
    IF v_period_end <= v_now THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_PERIOD_INVALID';
    END IF;
    IF v_price_id IS NULL THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD';
    END IF;

    v_target_sub_status := 'active';
    v_target_pay_status := 'ok';
    v_target_access := 'entitled';
    v_target_access_ends := v_period_end;
    v_target_grace_ends := NULL;
    v_target_cancel_at_end := v_cancel_at_period_end;
    v_target_canceled_at := NULL;
    v_target_period_start := v_period_start;
    v_target_period_end := v_period_end;
    v_cs_origin := 'provider';
    v_cs_plan := 'premium';
    v_cs_status := 'active';
    v_cs_trial_used := v_sub.trial_used_at;
    v_cs_trial_start := NULL;
    v_cs_trial_end := NULL;

  ELSIF v_paddle_status = 'past_due' THEN
    v_target_sub_status := 'active';
    v_target_pay_status := 'past_due';
    v_target_access := 'blocked';
    v_target_access_ends := NULL;
    v_target_grace_ends := NULL;
    v_target_cancel_at_end := FALSE;
    v_target_canceled_at := NULL;
    v_target_period_start := v_period_start;
    v_target_period_end := v_period_end;
    v_cs_origin := 'provider';
    v_cs_plan := 'premium';
    v_cs_status := 'active';
    v_cs_trial_used := v_sub.trial_used_at;
    v_cs_trial_start := NULL;
    v_cs_trial_end := NULL;

  ELSIF v_paddle_status = 'paused' THEN
    v_target_sub_status := 'paused';
    -- Preserve existing payment_status; never invent payment success.
    v_target_pay_status := CASE
      WHEN v_bill.payment_status IN (
        'none', 'ok', 'pending', 'past_due', 'failed', 'refunded', 'unknown'
      ) THEN v_bill.payment_status
      ELSE 'unknown'
    END;
    v_target_access := 'blocked';
    v_target_access_ends := NULL;
    v_target_grace_ends := NULL;
    v_target_cancel_at_end := FALSE;
    v_target_canceled_at := NULL;
    v_target_period_start := v_period_start;
    v_target_period_end := v_period_end;
    v_cs_origin := 'provider';
    v_cs_plan := 'free';
    v_cs_status := 'free';
    v_cs_trial_used := v_sub.trial_used_at;
    v_cs_trial_start := NULL;
    v_cs_trial_end := NULL;

  ELSIF v_paddle_status = 'canceled' THEN
    v_target_sub_status := 'ended';
    v_target_pay_status := CASE
      WHEN v_bill.payment_status IN (
        'none', 'ok', 'past_due', 'failed', 'refunded', 'pending', 'unknown'
      ) THEN v_bill.payment_status
      ELSE 'unknown'
    END;
    v_target_access := 'ended';
    v_target_access_ends := NULL;
    v_target_grace_ends := NULL;
    v_target_cancel_at_end := FALSE;
    v_target_canceled_at := COALESCE(v_canceled_at, v_now);
    v_target_period_start := v_period_start;
    v_target_period_end := v_period_end;
    v_cs_origin := 'provider';
    v_cs_plan := 'free';
    v_cs_status := 'free';
    v_cs_trial_used := v_sub.trial_used_at;
    v_cs_trial_start := NULL;
    v_cs_trial_end := NULL;

  ELSIF v_paddle_status IN ('incomplete', 'pending') THEN
    v_target_sub_status := 'incomplete';
    v_target_pay_status := 'pending';
    v_target_access := 'blocked';
    v_target_access_ends := NULL;
    v_target_grace_ends := NULL;
    v_target_cancel_at_end := FALSE;
    v_target_canceled_at := NULL;
    v_target_period_start := v_period_start;
    v_target_period_end := v_period_end;
    -- Do not flip company_subscriptions to provider premium; keep prior or free
    v_cs_origin := CASE
      WHEN v_sub.entitlement_origin = 'provider' THEN 'provider'
      WHEN v_sub.entitlement_origin = 'internal_trial' THEN 'internal_trial'
      ELSE 'none'
    END;
    IF v_cs_origin = 'provider' THEN
      v_cs_plan := 'free';
      v_cs_status := 'free';
      v_cs_trial_used := v_sub.trial_used_at;
      v_cs_trial_start := NULL;
      v_cs_trial_end := NULL;
    ELSIF v_cs_origin = 'internal_trial' THEN
      v_cs_plan := v_sub.plan_code;
      v_cs_status := v_sub.status;
      v_cs_trial_used := v_sub.trial_used_at;
      v_cs_trial_start := v_sub.trial_started_at;
      v_cs_trial_end := v_sub.trial_ends_at;
    ELSE
      v_cs_plan := 'free';
      v_cs_status := 'free';
      v_cs_trial_used := v_sub.trial_used_at;
      v_cs_trial_start := NULL;
      v_cs_trial_end := NULL;
    END IF;

  ELSE
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_STATUS_UNSUPPORTED';
  END IF;

  -- Equal-timestamp ordering ambiguity gate
  IF v_bill.last_subscription_event_occurred_at IS NOT NULL
    AND v_row.provider_created_at = v_bill.last_subscription_event_occurred_at THEN
    v_equiv := (
      v_bill.provider_code IS NOT DISTINCT FROM v_provider_code
      AND v_bill.provider_environment IS NOT DISTINCT FROM v_provider_environment
      AND v_bill.external_customer_id IS NOT DISTINCT FROM v_customer_id
      AND v_bill.external_subscription_id IS NOT DISTINCT FROM v_subscription_id
      AND (v_price_id IS NULL OR v_bill.external_price_id IS NOT DISTINCT FROM v_price_id)
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_target_sub_status
      AND v_bill.payment_status IS NOT DISTINCT FROM v_target_pay_status
      AND v_bill.provider_access_status IS NOT DISTINCT FROM v_target_access
      AND v_bill.provider_access_ends_at IS NOT DISTINCT FROM v_target_access_ends
      AND v_bill.grace_ends_at IS NOT DISTINCT FROM v_target_grace_ends
      AND v_bill.cancel_at_period_end IS NOT DISTINCT FROM v_target_cancel_at_end
      AND v_bill.canceled_at IS NOT DISTINCT FROM v_target_canceled_at
      AND v_bill.current_period_start IS NOT DISTINCT FROM v_target_period_start
      AND v_bill.current_period_end IS NOT DISTINCT FROM v_target_period_end
      AND v_sub.entitlement_origin IS NOT DISTINCT FROM v_cs_origin
      AND v_sub.plan_code IS NOT DISTINCT FROM v_cs_plan
      AND v_sub.status IS NOT DISTINCT FROM v_cs_status
      AND v_sub.trial_started_at IS NOT DISTINCT FROM v_cs_trial_start
      AND v_sub.trial_ends_at IS NOT DISTINCT FROM v_cs_trial_end
      AND v_sub.trial_used_at IS NOT DISTINCT FROM v_cs_trial_used
    );
    IF v_equiv THEN
      UPDATE private.billing_provider_events e
      SET
        company_id = v_company_id,
        external_subscription_id = v_subscription_id,
        processing_status = 'processed',
        processed_at = v_now,
        error_sanitized = NULL
      WHERE e.id = v_row.id;

      outcome := 'applied';
      inbox_event_id := v_row.id;
      processing_status := 'processed';
      company_id := v_company_id;
      attempt_count := v_row.attempt_count;
      RETURN NEXT;
      RETURN;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS';
  END IF;

  -- Apply billing mutation
  BEGIN
    UPDATE private.company_billing b
    SET
      provider_code = v_provider_code,
      provider_environment = v_provider_environment,
      external_customer_id = v_customer_id,
      external_subscription_id = v_subscription_id,
      external_price_id = COALESCE(v_price_id, b.external_price_id),
      subscription_status = v_target_sub_status,
      payment_status = v_target_pay_status,
      cancel_at_period_end = v_target_cancel_at_end,
      current_period_start = v_target_period_start,
      current_period_end = v_target_period_end,
      canceled_at = v_target_canceled_at,
      provider_access_status = v_target_access,
      provider_access_ends_at = v_target_access_ends,
      grace_ends_at = v_target_grace_ends,
      sync_status = 'idle',
      last_sync_result = 'succeeded',
      last_synced_at = v_now,
      last_sync_error_sanitized = NULL,
      last_subscription_event_occurred_at = v_row.provider_created_at,
      updated_at = v_now
    WHERE b.company_id = v_company_id;
  EXCEPTION
    WHEN unique_violation THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'ATLAS_PROVIDER_LINK_CONFLICT';
  END;

  -- Apply company_subscriptions mutation when targets require change
  IF v_cs_origin = 'internal_trial' THEN
    -- leave trial row untouched for incomplete path
    NULL;
  ELSE
    UPDATE public.company_subscriptions cs
    SET
      entitlement_origin = v_cs_origin,
      plan_code = v_cs_plan,
      status = v_cs_status,
      trial_started_at = v_cs_trial_start,
      trial_ends_at = v_cs_trial_end,
      trial_used_at = v_cs_trial_used,
      updated_at = v_now
    WHERE cs.company_id = v_company_id;
  END IF;

  UPDATE private.billing_provider_events e
  SET
    company_id = v_company_id,
    external_subscription_id = v_subscription_id,
    processing_status = 'processed',
    processed_at = v_now,
    error_sanitized = NULL
  WHERE e.id = v_row.id;

  outcome := 'applied';
  inbox_event_id := v_row.id;
  processing_status := 'processed';
  company_id := v_company_id;
  attempt_count := v_row.attempt_count;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) IS
  '14C-2F Phase D: apply verified paddle/test inbox event from payload_json only. '
  'Lock order: inbox → subscriptions → billing → checkout session. '
  'No generic mark-processed. Stale subscription events → ignored/stale_event.';

ALTER FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) OWNER TO postgres;

REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM anon;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION private.apply_paddle_sandbox_webhook_event(UUID) FROM service_role;

-- -----------------------------------------------------------------------------
-- public service_role wrapper
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_paddle_sandbox_webhook_event_server(
  p_inbox_event_id UUID
)
RETURNS TABLE (
  outcome TEXT,
  inbox_event_id UUID,
  processing_status TEXT,
  company_id UUID,
  attempt_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM private.apply_paddle_sandbox_webhook_event(p_inbox_event_id);
END;
$$;

COMMENT ON FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID) IS
  '14C-2F Phase D: service_role wrapper for apply_paddle_sandbox_webhook_event.';

ALTER FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID) FROM anon;
REVOKE ALL ON FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paddle_sandbox_webhook_event_server(UUID)
  TO service_role;
