-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2G Phase B
-- claim_next + processor_enabled foundation
-- (migration 20260820124032_billing_webhook_processor_invoker_foundation).
-- BEGIN … ROLLBACK: no local residue.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_results TO anon;

CREATE OR REPLACE FUNCTION pg_temp.record_result(
  p_name TEXT,
  p_passed BOOLEAN,
  p_sqlstate TEXT DEFAULT NULL,
  p_detail TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  INSERT INTO test_results(test_name, passed, sqlstate, detail)
  VALUES (p_name, p_passed, p_sqlstate, p_detail)
  ON CONFLICT (test_name) DO UPDATE
  SET passed = EXCLUDED.passed,
      sqlstate = EXCLUDED.sqlstate,
      detail = EXCLUDED.detail;
END;
$$;

REVOKE ALL ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.record_result(TEXT, BOOLEAN, TEXT, TEXT)
  TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION pg_temp.billing_fp()
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(COALESCE(string_agg(
    concat_ws(
      '|',
      company_id::text,
      coalesce(provider_code, ''),
      coalesce(provider_environment, ''),
      coalesce(external_customer_id, ''),
      coalesce(external_subscription_id, ''),
      coalesce(external_price_id, ''),
      subscription_status,
      payment_status,
      cancel_at_period_end::text,
      coalesce(current_period_start::text, ''),
      coalesce(current_period_end::text, ''),
      coalesce(canceled_at::text, ''),
      provider_access_status,
      coalesce(provider_access_ends_at::text, ''),
      coalesce(grace_ends_at::text, ''),
      sync_status,
      last_sync_result,
      coalesce(last_synced_at::text, ''),
      coalesce(last_sync_error_sanitized, ''),
      coalesce(provider_object_version, ''),
      coalesce(provider_object_version_at::text, ''),
      coalesce(provider_subscription_raw, ''),
      coalesce(provider_payment_raw, ''),
      created_at::text,
      updated_at::text
    ),
    E'\n' ORDER BY company_id
  ), ''))
  FROM private.company_billing;
$$;

CREATE OR REPLACE FUNCTION pg_temp.subs_fp()
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(COALESCE(string_agg(
    concat_ws(
      '|',
      company_id::text,
      plan_code,
      status,
      entitlement_origin,
      coalesce(trial_started_at::text, ''),
      coalesce(trial_ends_at::text, ''),
      coalesce(trial_used_at::text, ''),
      created_at::text,
      updated_at::text
    ),
    E'\n' ORDER BY company_id
  ), ''))
  FROM public.company_subscriptions;
$$;

CREATE OR REPLACE FUNCTION pg_temp.insert_inbox(
  p_external_event_id TEXT,
  p_processing_status TEXT,
  p_verification_status TEXT DEFAULT 'verified',
  p_attempt_count INTEGER DEFAULT 0,
  p_last_attempt_at TIMESTAMPTZ DEFAULT NULL,
  p_error_sanitized TEXT DEFAULT NULL,
  p_processed_at TIMESTAMPTZ DEFAULT NULL,
  p_provider_created_at TIMESTAMPTZ DEFAULT clock_timestamp(),
  p_received_at TIMESTAMPTZ DEFAULT clock_timestamp(),
  p_provider_code TEXT DEFAULT 'paddle',
  p_provider_environment TEXT DEFAULT 'test'
)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_id UUID;
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  INSERT INTO private.billing_provider_events (
    provider_code,
    provider_environment,
    external_event_id,
    event_type,
    company_id,
    provider_created_at,
    processing_status,
    verification_status,
    signature_verified_at,
    payload_hash,
    payload_json,
    retention_expires_at,
    received_at,
    attempt_count,
    last_attempt_at,
    error_sanitized,
    processed_at
  ) VALUES (
    p_provider_code,
    p_provider_environment,
    p_external_event_id,
    'transaction.completed',
    NULL,
    p_provider_created_at,
    p_processing_status,
    p_verification_status,
    CASE
      WHEN p_verification_status = 'verified' THEN v_now
      ELSE NULL
    END,
    repeat('a', 64),
    jsonb_build_object('event_id', p_external_event_id),
    v_now + interval '30 days',
    p_received_at,
    p_attempt_count,
    p_last_attempt_at,
    p_error_sanitized,
    p_processed_at
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

DO $$
DECLARE
  v_sqlstate TEXT;
  v_msg TEXT;
  v_priv_sig TEXT :=
    'private.claim_next_paddle_sandbox_webhook_event_for_processing()';
  v_pub_sig TEXT :=
    'public.claim_next_paddle_sandbox_webhook_event_for_processing_server()';
  v_priv_oid REGPROCEDURE :=
    'private.claim_next_paddle_sandbox_webhook_event_for_processing()'::regprocedure;
  v_pub_oid REGPROCEDURE :=
    'public.claim_next_paddle_sandbox_webhook_event_for_processing_server()'::regprocedure;
  v_def TEXT;
  v_col_exists BOOLEAN;
  v_col_notnull BOOLEAN;
  v_col_default TEXT;
  v_processor BOOLEAN;
  v_checkout BOOLEAN;
  v_checkout_before BOOLEAN;
  v_billing_before BIGINT;
  v_subs_before BIGINT;
  v_billing_fp_before TEXT;
  v_subs_fp_before TEXT;
  v_billing_after BIGINT;
  v_subs_after BIGINT;
  v_billing_fp_after TEXT;
  v_subs_fp_after TEXT;
  v_id UUID;
  v_id2 UUID;
  v_id3 UUID;
  v_id_null UUID;
  v_id_old UUID;
  v_id_new UUID;
  v_id_tie_a UUID;
  v_id_tie_b UUID;
  v_outcome TEXT;
  v_out_id UUID;
  v_status TEXT;
  v_attempts INTEGER;
  v_row private.billing_provider_events%ROWTYPE;
  v_row2 private.billing_provider_events%ROWTYPE;
  v_seq INT := 0;
  v_evt TEXT;
  v_sim TEXT;
  v_t0 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-20 12:00:00+00';
  v_before_attempt INT;
  v_before_last TIMESTAMPTZ;
  v_before_status TEXT;
  v_before_error TEXT;
  v_acl_public_priv BOOLEAN;
  v_acl_public_pub BOOLEAN;
  v_owner_priv NAME;
  v_owner_pub NAME;
  v_invoker BOOLEAN;
  v_definer BOOLEAN;
  v_search_priv TEXT;
  v_search_pub TEXT;
BEGIN
  -- =========================================================================
  -- Kill switch / schema
  -- =========================================================================
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'private'
      AND table_name = 'billing_runtime_config'
      AND column_name = 'processor_enabled'
  ) INTO v_col_exists;

  PERFORM pg_temp.record_result('processor_enabled_column_exists', v_col_exists);

  SELECT (a.attnotnull IS TRUE)
  INTO v_col_notnull
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'private'
    AND c.relname = 'billing_runtime_config'
    AND a.attname = 'processor_enabled'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  PERFORM pg_temp.record_result('processor_enabled_not_null', v_col_notnull);

  SELECT pg_get_expr(ad.adbin, ad.adrelid)
  INTO v_col_default
  FROM pg_attrdef ad
  JOIN pg_attribute a ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'private'
    AND c.relname = 'billing_runtime_config'
    AND a.attname = 'processor_enabled';

  PERFORM pg_temp.record_result(
    'processor_enabled_default_false',
    v_col_default IS NOT NULL
    AND v_col_default ILIKE '%false%'
  );

  SELECT c.processor_enabled, c.checkout_enabled
  INTO v_processor, v_checkout_before
  FROM private.billing_runtime_config c
  WHERE c.provider_code = 'paddle'
    AND c.provider_environment = 'test'
    AND c.is_active IS TRUE;

  PERFORM pg_temp.record_result(
    'runtime_processor_enabled_false',
    v_processor IS FALSE
  );

  PERFORM pg_temp.record_result(
    'checkout_enabled_independent_before',
    v_checkout_before IS FALSE
  );

  SELECT count(*) INTO v_billing_before FROM private.company_billing;
  SELECT count(*) INTO v_subs_before FROM public.company_subscriptions;
  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();

  -- Eligible received row while disabled (must not be claimed)
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 0);

  SELECT attempt_count, last_attempt_at, processing_status, error_sanitized
  INTO v_before_attempt, v_before_last, v_before_status, v_before_error
  FROM private.billing_provider_events WHERE id = v_id;

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'disabled_returns_disabled',
    v_outcome = 'disabled'
    AND v_out_id IS NULL
    AND v_status IS NULL
    AND v_attempts IS NULL
  );

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'disabled_no_inbox_mutation',
    v_row.processing_status = v_before_status
    AND v_row.attempt_count = v_before_attempt
    AND v_row.last_attempt_at IS NOT DISTINCT FROM v_before_last
    AND v_row.error_sanitized IS NOT DISTINCT FROM v_before_error
  );

  PERFORM pg_temp.record_result(
    'disabled_no_attempt_increment',
    v_row.attempt_count = 0
  );

  SELECT count(*) INTO v_billing_after FROM private.company_billing;
  SELECT count(*) INTO v_subs_after FROM public.company_subscriptions;
  v_billing_fp_after := pg_temp.billing_fp();
  v_subs_fp_after := pg_temp.subs_fp();

  PERFORM pg_temp.record_result(
    'disabled_no_billing_sub_mutation',
    v_billing_after = v_billing_before
    AND v_subs_after = v_subs_before
    AND v_billing_fp_after = v_billing_fp_before
    AND v_subs_fp_after = v_subs_fp_before
  );

  SELECT checkout_enabled INTO v_checkout
  FROM private.billing_runtime_config
  WHERE provider_code = 'paddle'
    AND provider_environment = 'test'
    AND is_active IS TRUE;

  PERFORM pg_temp.record_result(
    'checkout_unchanged_after_disabled_call',
    v_checkout IS FALSE
    AND v_checkout IS NOT DISTINCT FROM v_checkout_before
  );

  -- =========================================================================
  -- Enable processor inside this test transaction only
  -- =========================================================================
  UPDATE private.billing_runtime_config
  SET processor_enabled = TRUE
  WHERE provider_code = 'paddle'
    AND provider_environment = 'test'
    AND is_active IS TRUE;

  -- Empty queue (only the still-received row? wait - that row IS eligible now)
  -- Claim the pending received from disabled test first to clear, or delete it.
  DELETE FROM private.billing_provider_events WHERE id = v_id;

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'empty_when_no_candidate',
    v_outcome = 'empty'
    AND v_out_id IS NULL
    AND v_status IS NULL
    AND v_attempts IS NULL
  );

  -- =========================================================================
  -- Received → claimed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 0);

  SELECT count(*) INTO v_billing_before FROM private.company_billing;
  SELECT count(*) INTO v_subs_before FROM public.company_subscriptions;
  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;

  PERFORM pg_temp.record_result(
    'received_claimed',
    v_outcome = 'claimed'
    AND v_out_id = v_id
    AND v_status = 'processing'
    AND v_attempts = 1
    AND v_row.processing_status = 'processing'
    AND v_row.attempt_count = 1
    AND v_row.last_attempt_at IS NOT NULL
  );

  SELECT count(*) INTO v_billing_after FROM private.company_billing;
  SELECT count(*) INTO v_subs_after FROM public.company_subscriptions;
  PERFORM pg_temp.record_result(
    'received_claim_no_entitlement_mutation',
    v_billing_after = v_billing_before
    AND v_subs_after = v_subs_before
    AND pg_temp.billing_fp() = v_billing_fp_before
    AND pg_temp.subs_fp() = v_subs_fp_before
  );

  -- =========================================================================
  -- Stale processing → reclaimed; fresh processing not selected
  -- =========================================================================
  DELETE FROM private.billing_provider_events
  WHERE provider_code = 'paddle' AND provider_environment = 'test'
    AND external_event_id LIKE 'evt_%';

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 1,
    clock_timestamp() - interval '11 minutes'
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id2 := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 1,
    clock_timestamp() - interval '1 minute'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  SELECT * INTO v_row2 FROM private.billing_provider_events WHERE id = v_id2;

  PERFORM pg_temp.record_result(
    'stale_processing_reclaimed',
    v_outcome = 'reclaimed'
    AND v_out_id = v_id
    AND v_status = 'processing'
    AND v_attempts = 2
    AND v_row.processing_status = 'processing'
    AND v_row.attempt_count = 2
    AND v_row.last_attempt_at > clock_timestamp() - interval '1 minute'
  );

  PERFORM pg_temp.record_result(
    'fresh_processing_not_selected',
    v_row2.processing_status = 'processing'
    AND v_row2.attempt_count = 1
    AND v_row2.last_attempt_at < clock_timestamp() - interval '30 seconds'
  );

  -- NULL last_attempt_at on processing is reclaimable (mirrors UUID claim)
  DELETE FROM private.billing_provider_events WHERE id IN (v_id, v_id2);
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'processing', 'verified', 2, NULL);

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, attempt_count
  INTO v_outcome, v_out_id, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'null_last_attempt_processing_reclaimed',
    v_outcome = 'reclaimed'
    AND v_out_id = v_id
    AND v_attempts = 3
  );

  -- =========================================================================
  -- Failed must NOT auto-retry
  -- =========================================================================
  DELETE FROM private.billing_provider_events WHERE id = v_id;
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'failed', 'verified', 1, clock_timestamp(), 'ATLAS_PROVIDER_EVENT_UNLINKED'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_out_id
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'failed_not_auto_selected',
    v_outcome = 'empty'
    AND v_out_id IS NULL
    AND v_row.processing_status = 'failed'
    AND v_row.attempt_count = 1
    AND v_row.error_sanitized = 'ATLAS_PROVIDER_EVENT_UNLINKED'
  );

  -- =========================================================================
  -- Max attempt guard (attempt_count = 5 blocked; 4 allowed → 5)
  -- =========================================================================
  DELETE FROM private.billing_provider_events WHERE id = v_id;

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 5);

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id2 := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 5,
    clock_timestamp() - interval '11 minutes'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  SELECT * INTO v_row2 FROM private.billing_provider_events WHERE id = v_id2;

  PERFORM pg_temp.record_result(
    'attempt_5_received_not_selected',
    v_outcome = 'empty'
    AND v_row.processing_status = 'received'
    AND v_row.attempt_count = 5
  );

  PERFORM pg_temp.record_result(
    'attempt_5_stale_processing_not_selected',
    v_row2.processing_status = 'processing'
    AND v_row2.attempt_count = 5
  );

  DELETE FROM private.billing_provider_events WHERE id IN (v_id, v_id2);
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 4);

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, attempt_count
  INTO v_outcome, v_out_id, v_attempts
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'attempt_4_received_becomes_5',
    v_outcome = 'claimed'
    AND v_out_id = v_id
    AND v_attempts = 5
  );

  -- =========================================================================
  -- Filter safety
  -- =========================================================================
  DELETE FROM private.billing_provider_events WHERE id = v_id;

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'unverified', 0);

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id2 := pg_temp.insert_inbox(
    v_evt, 'ignored', 'verified', 0, NULL, 'simulator_event', clock_timestamp()
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id3 := pg_temp.insert_inbox(
    v_evt, 'processed', 'verified', 1, clock_timestamp(), NULL, clock_timestamp()
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  PERFORM pg_temp.insert_inbox(
    v_evt, 'failed', 'verified', 0, NULL, 'ATLAS_X'
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  PERFORM pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0,
    NULL, NULL, NULL, v_t0, v_t0, 'otherprovider', 'test'
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  PERFORM pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0,
    NULL, NULL, NULL, v_t0, v_t0, 'paddle', 'live'
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  PERFORM pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 1,
    clock_timestamp() - interval '1 minute'
  );

  v_sim := 'ntfsimevt_' || repeat('e', 26);
  PERFORM pg_temp.insert_inbox(v_sim, 'received', 'verified', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'filters_exclude_unsafe_candidates',
    v_outcome = 'empty'
  );

  SELECT processing_status, error_sanitized, attempt_count
  INTO v_before_status, v_before_error, v_before_attempt
  FROM private.billing_provider_events
  WHERE external_event_id = v_sim;

  PERFORM pg_temp.record_result(
    'simulator_unchanged_by_claim_next',
    v_before_status = 'received'
    AND v_before_attempt = 0
    AND v_before_error IS NULL
  );

  -- =========================================================================
  -- Ordering
  -- =========================================================================
  DELETE FROM private.billing_provider_events
  WHERE provider_code IN ('paddle', 'otherprovider');

  -- Older provider_created_at wins
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_new := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    v_t0 + interval '2 hours', v_t0
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_old := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    v_t0, v_t0 + interval '1 hour'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_out_id
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'ordering_older_provider_created_wins',
    v_outcome = 'claimed' AND v_out_id = v_id_old
  );

  DELETE FROM private.billing_provider_events WHERE id IN (v_id_old, v_id_new);

  -- NULL provider_created_at loses to non-NULL
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_null := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    NULL, v_t0
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    v_t0 + interval '1 day', v_t0 + interval '1 day'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_out_id
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'ordering_null_provider_created_last',
    v_outcome = 'claimed' AND v_out_id = v_id
  );

  DELETE FROM private.billing_provider_events WHERE id IN (v_id, v_id_null);

  -- Tie on provider_created_at: earlier received_at wins; then id
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_tie_b := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    v_t0, v_t0 + interval '2 minutes'
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_tie_a := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL,
    v_t0, v_t0 + interval '1 minute'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_out_id
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'ordering_received_at_tiebreak',
    v_outcome = 'claimed' AND v_out_id = v_id_tie_a
  );

  -- Equal provider_created_at + received_at: lower id wins
  DELETE FROM private.billing_provider_events WHERE id IN (v_id_tie_a, v_id_tie_b);
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_tie_a := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL, v_t0, v_t0
  );
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(to_hex(v_seq), 26, '0');
  v_id_tie_b := pg_temp.insert_inbox(
    v_evt, 'received', 'verified', 0, NULL, NULL, NULL, v_t0, v_t0
  );

  IF v_id_tie_a < v_id_tie_b THEN
    v_id := v_id_tie_a;
  ELSE
    v_id := v_id_tie_b;
  END IF;

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_out_id
  FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'ordering_id_tiebreak',
    v_outcome = 'claimed' AND v_out_id = v_id
  );

  -- =========================================================================
  -- SKIP LOCKED: static definition check (no multi-session harness)
  -- =========================================================================
  SELECT pg_get_functiondef(v_priv_oid) INTO v_def;
  PERFORM pg_temp.record_result(
    'definition_contains_for_update_skip_locked',
    v_def ILIKE '%FOR UPDATE SKIP LOCKED%'
  );

  -- =========================================================================
  -- Grants / security attributes
  -- =========================================================================
  SELECT EXISTS (
    SELECT 1
    FROM aclexplode(COALESCE(
      (SELECT p.proacl FROM pg_proc p WHERE p.oid = v_priv_oid::oid),
      acldefault('f', (SELECT p.proowner FROM pg_proc p WHERE p.oid = v_priv_oid::oid))
    )) x
    WHERE x.grantee = 0 AND x.privilege_type = 'EXECUTE'
  ) INTO v_acl_public_priv;

  SELECT EXISTS (
    SELECT 1
    FROM aclexplode(COALESCE(
      (SELECT p.proacl FROM pg_proc p WHERE p.oid = v_pub_oid::oid),
      acldefault('f', (SELECT p.proowner FROM pg_proc p WHERE p.oid = v_pub_oid::oid))
    )) x
    WHERE x.grantee = 0 AND x.privilege_type = 'EXECUTE'
  ) INTO v_acl_public_pub;

  PERFORM pg_temp.record_result(
    'private_grants',
    NOT v_acl_public_priv
    AND NOT has_function_privilege('anon', v_priv_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_priv_sig, 'EXECUTE')
    AND NOT has_function_privilege('service_role', v_priv_sig, 'EXECUTE')
  );

  PERFORM pg_temp.record_result(
    'public_wrapper_grants',
    NOT v_acl_public_pub
    AND NOT has_function_privilege('anon', v_pub_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_pub_sig, 'EXECUTE')
    AND has_function_privilege('service_role', v_pub_sig, 'EXECUTE')
  );

  SELECT pg_get_userbyid(p.proowner), (NOT p.prosecdef),
         coalesce(array_to_string(p.proconfig, ','), '')
  INTO v_owner_priv, v_invoker, v_search_priv
  FROM pg_proc p WHERE p.oid = v_priv_oid::oid;

  SELECT pg_get_userbyid(p.proowner), p.prosecdef,
         coalesce(array_to_string(p.proconfig, ','), '')
  INTO v_owner_pub, v_definer, v_search_pub
  FROM pg_proc p WHERE p.oid = v_pub_oid::oid;

  PERFORM pg_temp.record_result(
    'security_attributes',
    v_owner_priv = 'postgres'
    AND v_owner_pub = 'postgres'
    AND v_invoker IS TRUE
    AND v_definer IS TRUE
    AND v_search_priv LIKE '%search_path=%'
    AND v_search_pub LIKE '%search_path=%'
  );

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.claim_next_paddle_sandbox_webhook_event_for_processing_server();
    PERFORM pg_temp.record_result('authenticated_denied', false, NULL, 'unexpected success');
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result('authenticated_denied', v_sqlstate = '42501', v_sqlstate, 'denied');
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result('authenticated_denied', false, v_sqlstate, v_msg);
  END;
  RESET ROLE;

  -- Final: checkout still independent; processor was enabled only in-test
  SELECT checkout_enabled INTO v_checkout
  FROM private.billing_runtime_config
  WHERE provider_code = 'paddle'
    AND provider_environment = 'test'
    AND is_active IS TRUE;

  PERFORM pg_temp.record_result(
    'checkout_still_false_end',
    v_checkout IS FALSE
  );
END;
$$;

SELECT
  count(*)::int AS total,
  count(*) FILTER (WHERE passed)::int AS passed,
  count(*) FILTER (WHERE NOT passed)::int AS failed
FROM test_results;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

ROLLBACK;
