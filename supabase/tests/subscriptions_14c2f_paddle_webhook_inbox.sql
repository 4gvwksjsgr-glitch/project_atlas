-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2F-B
-- Paddle Sandbox webhook inbox foundation (migration 20260810120001).
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

DO $$
DECLARE
  v_sqlstate TEXT;
  v_msg TEXT;
  v_hash_a TEXT := repeat('a', 64);
  v_hash_b TEXT := repeat('b', 64);
  v_evt TEXT := 'evt_' || repeat('a', 26);
  v_evt2 TEXT := 'evt_' || repeat('b', 26);
  v_evt3 TEXT := 'evt_' || repeat('c', 26);
  v_sub TEXT := 'sub_' || repeat('d', 26);
  v_now TIMESTAMPTZ := TIMESTAMPTZ '2026-08-10 12:00:00+00';
  v_outcome TEXT;
  v_id UUID;
  v_id2 UUID;
  v_cnt INT;
  v_row private.billing_provider_events%ROWTYPE;
  v_billing_before BIGINT;
  v_billing_after BIGINT;
  v_subs_before BIGINT;
  v_subs_after BIGINT;
  v_billing_fp_before TEXT;
  v_billing_fp_after TEXT;
  v_subs_fp_before TEXT;
  v_subs_fp_after TEXT;
  v_fn_sig TEXT :=
    'public.ingest_paddle_sandbox_webhook_event_server(text,text,timestamptz,text,jsonb,text,text)';
BEGIN
  -- Grants on wrapper (7-arg signature; no p_now)
  PERFORM pg_temp.record_result(
    'server_rpc_execute_grants',
    NOT has_function_privilege('authenticated', v_fn_sig, 'EXECUTE')
    AND NOT has_function_privilege('anon', v_fn_sig, 'EXECUTE')
    AND has_function_privilege('service_role', v_fn_sig, 'EXECUTE')
  );

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.ingest_paddle_sandbox_webhook_event_server(
      v_evt, 'subscription.created', v_now, v_hash_a,
      '{"event_id":"x"}'::jsonb, 'supported', NULL
    );
    PERFORM pg_temp.record_result(
      'authenticated_cannot_execute',
      false,
      NULL,
      'unexpected success'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_execute',
        v_sqlstate = '42501',
        v_sqlstate,
        'denied'
      );
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_execute',
        false,
        v_sqlstate,
        v_msg
      );
  END;
  RESET ROLE;

  BEGIN
    SET LOCAL ROLE anon;
    PERFORM * FROM public.ingest_paddle_sandbox_webhook_event_server(
      v_evt, 'subscription.created', v_now, v_hash_a,
      '{"event_id":"x"}'::jsonb, 'supported', NULL
    );
    PERFORM pg_temp.record_result(
      'anon_cannot_execute',
      false,
      NULL,
      'unexpected success'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result(
        'anon_cannot_execute',
        v_sqlstate = '42501',
        v_sqlstate,
        'denied'
      );
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'anon_cannot_execute',
        false,
        v_sqlstate,
        v_msg
      );
  END;
  RESET ROLE;

  -- service_role must not have arbitrary direct SELECT on private events
  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM 1 FROM private.billing_provider_events LIMIT 1;
    PERFORM pg_temp.record_result(
      'service_role_no_direct_private_select',
      false,
      NULL,
      'unexpected success'
    );
  EXCEPTION WHEN insufficient_privilege OR OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
    PERFORM pg_temp.record_result(
      'service_role_no_direct_private_select',
      true,
      v_sqlstate,
      'denied'
    );
  END;
  RESET ROLE;

  SELECT count(*) INTO v_billing_before FROM private.company_billing;
  SELECT count(*) INTO v_subs_before FROM public.company_subscriptions;

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
  INTO v_billing_fp_before
  FROM private.company_billing;

  SELECT md5(COALESCE(string_agg(
    concat_ws(
      '|',
      company_id::text,
      plan_code,
      status,
      coalesce(trial_started_at::text, ''),
      coalesce(trial_ends_at::text, ''),
      coalesce(trial_used_at::text, ''),
      created_at::text,
      updated_at::text
    ),
    E'\n' ORDER BY company_id
  ), ''))
  INTO v_subs_fp_before
  FROM public.company_subscriptions;

  -- First supported insert (RPC as service_role)
  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_id
  FROM public.ingest_paddle_sandbox_webhook_event_server(
    v_evt,
    'subscription.created',
    v_now,
    v_hash_a,
    jsonb_build_object(
      'event_id', v_evt,
      'event_type', 'subscription.created',
      'occurred_at', v_now
    ),
    'supported',
    v_sub
  );
  RESET ROLE;

  PERFORM pg_temp.record_result('first_insert_outcome', v_outcome = 'inserted', NULL, v_outcome);

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'first_insert_shape',
    v_row.provider_code = 'paddle'
      AND v_row.provider_environment = 'test'
      AND v_row.verification_status = 'verified'
      AND v_row.processing_status = 'received'
      AND v_row.signature_verified_at IS NOT NULL
      AND v_row.company_id IS NULL
      AND v_row.payload_hash = v_hash_a
      AND v_row.external_subscription_id = v_sub
      AND v_row.retention_expires_at = v_row.signature_verified_at + interval '30 days'
      AND v_row.received_at IS NOT DISTINCT FROM v_row.signature_verified_at,
    NULL,
    NULL
  );

  SELECT count(*) INTO v_cnt
  FROM private.billing_provider_events
  WHERE provider_code = 'paddle'
    AND provider_environment = 'test'
    AND external_event_id = v_evt;
  PERFORM pg_temp.record_result('first_insert_one_row', v_cnt = 1, NULL, v_cnt::text);

  -- Exact duplicate (RPC as service_role)
  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_id2
  FROM public.ingest_paddle_sandbox_webhook_event_server(
    v_evt,
    'subscription.created',
    v_now,
    v_hash_a,
    jsonb_build_object(
      'event_id', v_evt,
      'event_type', 'subscription.created',
      'occurred_at', v_now
    ),
    'supported',
    v_sub
  );
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'exact_duplicate',
    v_outcome = 'duplicate' AND v_id2 = v_id,
    NULL,
    v_outcome
  );
  SELECT count(*) INTO v_cnt
  FROM private.billing_provider_events
  WHERE provider_code = 'paddle'
    AND provider_environment = 'test'
    AND external_event_id = v_evt;
  PERFORM pg_temp.record_result('exact_duplicate_one_row', v_cnt = 1, NULL, v_cnt::text);

  -- Hash conflict (RPC as service_role)
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM * FROM public.ingest_paddle_sandbox_webhook_event_server(
      v_evt,
      'subscription.created',
      v_now,
      v_hash_b,
      jsonb_build_object('event_id', v_evt, 'event_type', 'subscription.created'),
      'supported',
      NULL
    );
    PERFORM pg_temp.record_result('hash_conflict_fail_closed', false, NULL, 'unexpected success');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'hash_conflict_fail_closed',
      v_msg = 'ATLAS_PROVIDER_EVENT_PAYLOAD_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;
  RESET ROLE;

  -- Unsupported ignored (RPC as service_role)
  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_outcome, v_id
  FROM public.ingest_paddle_sandbox_webhook_event_server(
    v_evt2,
    'transaction.payment_failed',
    v_now,
    v_hash_a,
    jsonb_build_object(
      'event_id', v_evt2,
      'event_type', 'transaction.payment_failed',
      'occurred_at', v_now
    ),
    'ignored',
    NULL
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'unsupported_ignored',
    v_outcome = 'inserted'
      AND v_row.processing_status = 'ignored'
      AND v_row.verification_status = 'verified'
      AND v_row.company_id IS NULL,
    NULL,
    v_row.processing_status
  );

  -- Invalid payload_hash format (RPC as service_role)
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM * FROM public.ingest_paddle_sandbox_webhook_event_server(
      v_evt3,
      'transaction.completed',
      v_now,
      'not-a-hash',
      jsonb_build_object('event_id', v_evt3),
      'supported',
      NULL
    );
    PERFORM pg_temp.record_result('payload_hash_format', false, NULL, 'unexpected success');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.record_result(
      'payload_hash_format',
      v_msg = 'ATLAS_INVALID_REQUEST',
      v_sqlstate,
      v_msg
    );
  END;
  RESET ROLE;

  SELECT count(*) INTO v_billing_after FROM private.company_billing;
  SELECT count(*) INTO v_subs_after FROM public.company_subscriptions;

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
  INTO v_billing_fp_after
  FROM private.company_billing;

  SELECT md5(COALESCE(string_agg(
    concat_ws(
      '|',
      company_id::text,
      plan_code,
      status,
      coalesce(trial_started_at::text, ''),
      coalesce(trial_ends_at::text, ''),
      coalesce(trial_used_at::text, ''),
      created_at::text,
      updated_at::text
    ),
    E'\n' ORDER BY company_id
  ), ''))
  INTO v_subs_fp_after
  FROM public.company_subscriptions;

  PERFORM pg_temp.record_result(
    'no_company_billing_count_change',
    v_billing_before = v_billing_after,
    NULL,
    format('%s->%s', v_billing_before, v_billing_after)
  );
  PERFORM pg_temp.record_result(
    'no_company_billing_fingerprint_change',
    v_billing_fp_before = v_billing_fp_after,
    NULL,
    NULL
  );
  PERFORM pg_temp.record_result(
    'no_company_subscriptions_count_change',
    v_subs_before = v_subs_after,
    NULL,
    format('%s->%s', v_subs_before, v_subs_after)
  );
  PERFORM pg_temp.record_result(
    'no_company_subscriptions_fingerprint_change',
    v_subs_fp_before = v_subs_fp_after,
    NULL,
    NULL
  );

  -- RLS / FORCE preserved
  PERFORM pg_temp.record_result(
    'events_rls_force',
    (SELECT c.relrowsecurity AND c.relforcerowsecurity
     FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'private' AND c.relname = 'billing_provider_events'),
    NULL,
    NULL
  );

  PERFORM pg_temp.record_result(
    'events_no_anon_auth_table_privs',
    NOT has_table_privilege('anon', 'private.billing_provider_events', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'private.billing_provider_events', 'SELECT')
      AND NOT has_table_privilege('anon', 'private.billing_provider_events', 'INSERT')
      AND NOT has_table_privilege('authenticated', 'private.billing_provider_events', 'INSERT'),
    NULL,
    NULL
  );

  -- checkout still disabled in seed config
  PERFORM pg_temp.record_result(
    'checkout_still_disabled',
    NOT EXISTS (
      SELECT 1 FROM private.billing_runtime_config
      WHERE checkout_enabled IS TRUE
    ),
    NULL,
    NULL
  );
END;
$$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY 1;

SELECT count(*) FILTER (WHERE NOT passed) AS failed
FROM test_results;

ROLLBACK;
