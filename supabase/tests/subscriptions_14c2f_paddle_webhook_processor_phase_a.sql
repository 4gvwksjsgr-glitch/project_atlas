-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2F Phase A
-- Webhook processor claim + simulator firewall + failure finalizer.
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

CREATE OR REPLACE FUNCTION pg_temp.usage_fp()
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT md5(COALESCE(string_agg(
    company_id::text || ':' || period_start::text || ':' || documents_used::text,
    '|' ORDER BY company_id::text || ':' || period_start::text
  ), ''))
  FROM private.company_document_monthly_usage;
$$;

CREATE OR REPLACE FUNCTION pg_temp.insert_inbox(
  p_external_event_id TEXT,
  p_processing_status TEXT,
  p_verification_status TEXT DEFAULT 'verified',
  p_attempt_count INTEGER DEFAULT 0,
  p_last_attempt_at TIMESTAMPTZ DEFAULT NULL,
  p_error_sanitized TEXT DEFAULT NULL,
  p_processed_at TIMESTAMPTZ DEFAULT NULL
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
    'paddle',
    'test',
    p_external_event_id,
    'transaction.completed',
    NULL,
    v_now,
    p_processing_status,
    p_verification_status,
    CASE
      WHEN p_verification_status = 'verified' THEN v_now
      ELSE NULL
    END,
    repeat('a', 64),
    jsonb_build_object('event_id', p_external_event_id),
    v_now + interval '30 days',
    v_now,
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
  v_claim_sig TEXT :=
    'public.claim_paddle_sandbox_webhook_event_for_processing_server(uuid)';
  v_fail_sig TEXT :=
    'public.fail_paddle_sandbox_webhook_event_processing_server(uuid,text)';
  v_claim_priv TEXT :=
    'private.claim_paddle_sandbox_webhook_event_for_processing(uuid)';
  v_fail_priv TEXT :=
    'private.fail_paddle_sandbox_webhook_event_processing(uuid,text)';
  v_billing_before BIGINT;
  v_subs_before BIGINT;
  v_usage_before BIGINT;
  v_billing_fp_before TEXT;
  v_subs_fp_before TEXT;
  v_usage_fp_before TEXT;
  v_billing_after BIGINT;
  v_subs_after BIGINT;
  v_usage_after BIGINT;
  v_billing_fp_after TEXT;
  v_subs_fp_after TEXT;
  v_usage_fp_after TEXT;
  v_checkout BOOLEAN;
  v_id UUID;
  v_id2 UUID;
  v_outcome TEXT;
  v_out_id UUID;
  v_status TEXT;
  v_attempts INTEGER;
  v_row private.billing_provider_events%ROWTYPE;
  v_seq INT := 0;
  v_evt TEXT;
  v_sim TEXT;
BEGIN
  -- -------------------------------------------------------------------------
  -- Privilege matrix
  -- -------------------------------------------------------------------------
  PERFORM pg_temp.record_result(
    'claim_wrapper_grants',
    has_function_privilege('service_role', v_claim_sig, 'EXECUTE')
    AND NOT has_function_privilege('anon', v_claim_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_claim_sig, 'EXECUTE')
  );

  PERFORM pg_temp.record_result(
    'fail_wrapper_grants',
    has_function_privilege('service_role', v_fail_sig, 'EXECUTE')
    AND NOT has_function_privilege('anon', v_fail_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_fail_sig, 'EXECUTE')
  );

  PERFORM pg_temp.record_result(
    'private_claim_not_client_executable',
    NOT has_function_privilege('anon', v_claim_priv, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_claim_priv, 'EXECUTE')
  );

  PERFORM pg_temp.record_result(
    'private_fail_not_client_executable',
    NOT has_function_privilege('anon', v_fail_priv, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_fail_priv, 'EXECUTE')
  );

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(
      gen_random_uuid()
    );
    PERFORM pg_temp.record_result(
      'authenticated_cannot_claim', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_claim', v_sqlstate = '42501', v_sqlstate, 'denied'
      );
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_claim', false, v_sqlstate, v_msg
      );
  END;
  RESET ROLE;

  BEGIN
    SET LOCAL ROLE anon;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      gen_random_uuid(), 'X'
    );
    PERFORM pg_temp.record_result(
      'anon_cannot_fail', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result(
        'anon_cannot_fail', v_sqlstate = '42501', v_sqlstate, 'denied'
      );
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'anon_cannot_fail', false, v_sqlstate, v_msg
      );
  END;
  RESET ROLE;

  -- No mark-processed RPC in Phase A
  PERFORM pg_temp.record_result(
    'no_mark_processed_rpc',
    NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname IN ('public', 'private')
        AND p.proname ILIKE '%mark%processed%'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname IN ('public', 'private')
        AND p.proname ILIKE '%complete%processing%'
    )
  );

  -- Business-data baseline
  SELECT count(*) INTO v_billing_before FROM private.company_billing;
  SELECT count(*) INTO v_subs_before FROM public.company_subscriptions;
  SELECT count(*) INTO v_usage_before FROM private.company_document_monthly_usage;
  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();
  v_usage_fp_before := pg_temp.usage_fp();

  SELECT coalesce(
    (
      SELECT checkout_enabled
      FROM private.billing_runtime_config
      WHERE provider_code = 'paddle'
        AND provider_environment = 'test'
        AND is_active IS TRUE
      LIMIT 1
    ),
    false
  ) INTO v_checkout;

  PERFORM pg_temp.record_result(
    'checkout_disabled_before',
    v_checkout IS FALSE
  );

  -- =========================================================================
  -- 4. Normal verified received -> claimed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'normal_received_claimed',
    v_outcome = 'claimed'
    AND v_out_id = v_id
    AND v_status = 'processing'
    AND v_attempts = 1
    AND v_row.processing_status = 'processing'
    AND v_row.attempt_count = 1
    AND v_row.last_attempt_at IS NOT NULL
    AND v_row.error_sanitized IS NULL
    AND v_row.company_id IS NULL
  );

  -- =========================================================================
  -- 5. Immediate second claim -> busy
  -- =========================================================================
  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'normal_processing_busy',
    v_outcome = 'busy'
    AND v_status = 'processing'
    AND v_attempts = 1
    AND v_row.attempt_count = 1
  );

  -- =========================================================================
  -- 6. Stale processing -> reclaimed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 3,
    clock_timestamp() - interval '11 minutes', 'PREV_ERR', NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'stale_processing_reclaimed',
    v_outcome = 'reclaimed'
    AND v_status = 'processing'
    AND v_attempts = 4
    AND v_row.attempt_count = 4
    AND v_row.last_attempt_at > clock_timestamp() - interval '1 minute'
    AND v_row.error_sanitized IS NULL
    AND v_row.processed_at IS NULL
  );

  -- =========================================================================
  -- 7. Processing with NULL last_attempt_at -> reclaimed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'processing', 'verified', 1, NULL);

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'null_last_attempt_reclaimed',
    v_outcome = 'reclaimed'
    AND v_attempts = 2
    AND v_row.last_attempt_at IS NOT NULL
  );

  -- =========================================================================
  -- 8. Failed normal event -> claim clears error
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'failed', 'verified', 2, clock_timestamp() - interval '1 hour',
    'OLD_FAIL', NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'failed_normal_reclaimed_as_claimed',
    v_outcome = 'claimed'
    AND v_attempts = 3
    AND v_row.processing_status = 'processing'
    AND v_row.error_sanitized IS NULL
  );

  -- =========================================================================
  -- 9. Processed normal -> terminal no-op
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processed', 'verified', 5, clock_timestamp() - interval '1 day',
    NULL, clock_timestamp() - interval '1 day'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'processed_normal_noop',
    v_outcome = 'processed'
    AND v_attempts = 5
    AND v_row.processing_status = 'processed'
    AND v_row.attempt_count = 5
  );

  -- =========================================================================
  -- 10. Ignored normal -> terminal no-op
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'ignored', 'verified', 1);

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'ignored_normal_noop',
    v_outcome = 'ignored'
    AND v_attempts = 1
    AND v_row.processing_status = 'ignored'
    AND v_row.attempt_count = 1
  );

  -- =========================================================================
  -- 11. Unverified / rejected cannot claim
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'unverified', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'unverified_cannot_claim',
    v_outcome = 'not_verified'
    AND v_attempts = 0
    AND v_row.processing_status = 'received'
    AND v_row.attempt_count = 0
  );

  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'rejected', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'rejected_cannot_claim',
    v_outcome = 'not_verified'
    AND v_row.processing_status = 'received'
    AND v_row.attempt_count = 0
  );

  -- =========================================================================
  -- 12. Simulator received -> ignored
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_sim, 'received', 'verified', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_received_ignored',
    v_outcome = 'ignored'
    AND v_status = 'ignored'
    AND v_attempts = 0
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
    AND v_row.company_id IS NULL
    AND v_row.attempt_count = 0
  );

  -- =========================================================================
  -- 13. Simulator failed -> ignored
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'failed', 'verified', 2, clock_timestamp(), 'X', NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_failed_ignored',
    v_outcome = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
  );

  -- =========================================================================
  -- 14. Simulator fresh processing -> ignored (overrides lease/busy)
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 4, clock_timestamp(), NULL, NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_fresh_processing_ignored',
    v_outcome = 'ignored'
    AND v_attempts = 4
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.attempt_count = 4
  );

  -- =========================================================================
  -- 15. Simulator already ignored -> noop
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'ignored', 'verified', 0, NULL, 'simulator_event', clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_already_ignored_noop',
    v_outcome = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.attempt_count = 0
  );

  -- =========================================================================
  -- 16. Simulator already processed -> fail-closed invariant
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processed', 'verified', 1, clock_timestamp(), NULL, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_processed_invariant',
    v_outcome = 'simulator_processed_invariant'
    AND v_status = 'processed'
    AND v_attempts = 1
    AND v_row.processing_status = 'processed'
    AND v_row.attempt_count = 1
  );

  -- =========================================================================
  -- 17. Normal failure finalizer: processing -> failed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 7, clock_timestamp(), NULL, NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROCESSOR_APPLY_FAILED'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_processing_to_failed',
    v_outcome = 'failed'
    AND v_status = 'failed'
    AND v_attempts = 7
    AND v_row.processing_status = 'failed'
    AND v_row.error_sanitized = 'ATLAS_PROCESSOR_APPLY_FAILED'
    AND v_row.attempt_count = 7
    AND v_row.processed_at IS NULL
    AND v_row.last_attempt_at IS NOT NULL
  );

  -- =========================================================================
  -- 18. Invalid failure error codes rejected
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 1, clock_timestamp()
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, 'lowercase'
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_rejects_lowercase', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_rejects_lowercase',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, 'HAS SPACE'
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_rejects_whitespace', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_rejects_whitespace',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, 'BAD' || chr(10) || 'CODE'
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_rejects_control', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_rejects_control',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, repeat('A', 129)
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_rejects_over_128', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_rejects_over_128',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_invalid_codes_no_mutation',
    v_row.processing_status = 'processing'
    AND v_row.error_sanitized IS NULL
  );

  -- =========================================================================
  -- 19. Failure on non-processing normal -> invalid_state
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(v_evt, 'received', 'verified', 0);

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_X'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_non_processing_invalid_state',
    v_outcome = 'invalid_state'
    AND v_status = 'received'
    AND v_row.processing_status = 'received'
    AND v_row.error_sanitized IS NULL
  );

  -- =========================================================================
  -- 20. Failure finalizer on simulator -> ignored, never failed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 2, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_SHOULD_NOT_APPLY'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_simulator_stays_ignored',
    v_outcome = 'ignored'
    AND v_status = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
  );

  -- =========================================================================
  -- Fix regressions: simulator firewall dominates before p_error_code validation
  -- =========================================================================
  -- A. simulator processing + invalid lowercase -> ignored (not ATLAS_INVALID_REQUEST)
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 3, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'lowercase'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_sim_processing_invalid_lowercase_ignored',
    v_outcome = 'ignored'
    AND v_status = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
    AND v_row.attempt_count = 3
  );

  -- B. simulator processing + NULL error -> ignored
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 1, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, NULL
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_sim_processing_null_error_ignored',
    v_outcome = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
  );

  -- C. simulator processing + >128-char error -> ignored
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 2, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, repeat('A', 129)
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_sim_processing_over128_ignored',
    v_outcome = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
  );

  -- D. simulator already ignored + invalid error -> noop
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'ignored', 'verified', 0, NULL, 'simulator_event', clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'bad code'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_sim_ignored_invalid_error_noop',
    v_outcome = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.attempt_count = 0
  );

  -- E. simulator processed + invalid error -> invariant, no rewrite
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processed', 'verified', 1, clock_timestamp(), NULL, clock_timestamp()
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'lowercase'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_sim_processed_invalid_error_invariant',
    v_outcome = 'simulator_processed_invariant'
    AND v_status = 'processed'
    AND v_row.processing_status = 'processed'
    AND v_row.attempt_count = 1
  );

  -- F. normal processing + invalid lowercase -> ATLAS_INVALID_REQUEST, stays processing
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 2, clock_timestamp()
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, 'lowercase'
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_normal_invalid_lowercase_rejected', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_normal_invalid_lowercase_rejected',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_normal_invalid_lowercase_no_mutation',
    v_row.processing_status = 'processing'
    AND v_row.error_sanitized IS NULL
  );

  -- G. normal processing + NULL error -> ATLAS_INVALID_REQUEST, stays processing
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'processing', 'verified', 1, clock_timestamp()
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
      v_id, NULL
    );
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'fail_normal_null_error_rejected', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'fail_normal_null_error_rejected',
        v_msg = 'ATLAS_INVALID_REQUEST',
        v_sqlstate,
        v_msg
      );
  END;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'fail_normal_null_error_no_mutation',
    v_row.processing_status = 'processing'
    AND v_row.error_sanitized IS NULL
  );

  -- H. simulator STALE processing -> claim ignored (never reclaimed)
  v_seq := v_seq + 1;
  v_sim := 'ntfsimevt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_sim, 'processing', 'verified', 5,
    clock_timestamp() - interval '11 minutes', NULL, NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'claim_simulator_stale_processing_ignored',
    v_outcome = 'ignored'
    AND v_status = 'ignored'
    AND v_attempts = 5
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND v_row.processed_at IS NOT NULL
    AND v_row.attempt_count = 5
  );

  -- =========================================================================
  -- 21. Reclaim after failed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := 'evt_' || lpad(v_seq::text, 26, '0');
  v_id := pg_temp.insert_inbox(
    v_evt, 'failed', 'verified', 4, clock_timestamp() - interval '30 minutes',
    'PREV', NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, attempt_count
  INTO v_outcome, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'claim_after_failed',
    v_outcome = 'claimed'
    AND v_attempts = 5
    AND v_row.processing_status = 'processing'
    AND v_row.error_sanitized IS NULL
  );

  -- =========================================================================
  -- 22. Nonexistent UUID -> not_found
  -- =========================================================================
  v_id2 := gen_random_uuid();
  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id, processing_status, attempt_count
  INTO v_outcome, v_out_id, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id2);
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'claim_not_found',
    v_outcome = 'not_found'
    AND v_out_id = v_id2
    AND v_status IS NULL
    AND v_attempts IS NULL
  );

  SET LOCAL ROLE service_role;
  SELECT outcome
  INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    gen_random_uuid(), 'ATLAS_X'
  );
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'fail_not_found',
    v_outcome = 'not_found'
  );

  -- =========================================================================
  -- Business-data non-mutation + checkout still disabled
  -- =========================================================================
  SELECT count(*) INTO v_billing_after FROM private.company_billing;
  SELECT count(*) INTO v_subs_after FROM public.company_subscriptions;
  SELECT count(*) INTO v_usage_after FROM private.company_document_monthly_usage;
  v_billing_fp_after := pg_temp.billing_fp();
  v_subs_fp_after := pg_temp.subs_fp();
  v_usage_fp_after := pg_temp.usage_fp();

  PERFORM pg_temp.record_result(
    'company_billing_unchanged',
    v_billing_after = v_billing_before
    AND v_billing_fp_after = v_billing_fp_before
  );

  PERFORM pg_temp.record_result(
    'company_subscriptions_unchanged',
    v_subs_after = v_subs_before
    AND v_subs_fp_after = v_subs_fp_before
  );

  PERFORM pg_temp.record_result(
    'usage_unchanged',
    v_usage_after = v_usage_before
    AND v_usage_fp_after = v_usage_fp_before
  );

  SELECT coalesce(
    (
      SELECT checkout_enabled
      FROM private.billing_runtime_config
      WHERE provider_code = 'paddle'
        AND provider_environment = 'test'
        AND is_active IS TRUE
      LIMIT 1
    ),
    false
  ) INTO v_checkout;

  PERFORM pg_temp.record_result(
    'checkout_disabled_after',
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
WHERE NOT passed
ORDER BY test_name;

ROLLBACK;
