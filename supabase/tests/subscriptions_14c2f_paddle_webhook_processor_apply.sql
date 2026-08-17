-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2F Phase D
-- Webhook apply processor (migration 20260817160001_billing_webhook_processor_apply).
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

CREATE OR REPLACE FUNCTION pg_temp.set_auth(p_uid UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.set_auth(UUID) TO authenticated;

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
      coalesce(last_subscription_event_occurred_at::text, ''),
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

CREATE OR REPLACE FUNCTION pg_temp.paddle_id(p_prefix TEXT, p_seed TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_prefix || substr(md5(p_seed), 1, 26);
$$;

CREATE OR REPLACE FUNCTION pg_temp.insert_inbox(
  p_external_event_id TEXT,
  p_event_type TEXT,
  p_processing_status TEXT,
  p_payload_json JSONB,
  p_provider_created_at TIMESTAMPTZ,
  p_verification_status TEXT DEFAULT 'verified'
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
    p_event_type,
    NULL,
    p_provider_created_at,
    p_processing_status,
    p_verification_status,
    CASE
      WHEN p_verification_status = 'verified' THEN v_now
      ELSE NULL
    END,
    repeat('a', 64),
    p_payload_json,
    v_now + interval '30 days',
    v_now,
    CASE WHEN p_processing_status = 'processing' THEN 1 ELSE 0 END,
    CASE WHEN p_processing_status = 'processing' THEN v_now ELSE NULL END,
    NULL,
    NULL
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.custom_data(
  p_company_id UUID,
  p_session_id UUID,
  p_offer_code TEXT,
  p_schema_version INTEGER DEFAULT 1
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'atlas_schema_version', p_schema_version,
    'atlas_company_id', p_company_id,
    'atlas_checkout_session_id', p_session_id,
    'atlas_offer_code', p_offer_code
  ));
$$;

CREATE OR REPLACE FUNCTION pg_temp.sub_payload(
  p_event_id TEXT,
  p_occurred_at TIMESTAMPTZ,
  p_status TEXT,
  p_sub_id TEXT,
  p_customer_id TEXT,
  p_price_id TEXT,
  p_period_start TIMESTAMPTZ,
  p_period_end TIMESTAMPTZ,
  p_custom JSONB DEFAULT NULL,
  p_scheduled_cancel BOOLEAN DEFAULT FALSE,
  p_canceled_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_data JSONB;
  v_period JSONB := NULL;
BEGIN
  IF p_period_start IS NOT NULL OR p_period_end IS NOT NULL THEN
    v_period := jsonb_strip_nulls(jsonb_build_object(
      'starts_at', CASE WHEN p_period_start IS NULL THEN NULL
                        ELSE to_char(p_period_start AT TIME ZONE 'UTC',
                                     'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,
      'ends_at', CASE WHEN p_period_end IS NULL THEN NULL
                      ELSE to_char(p_period_end AT TIME ZONE 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END
    ));
  END IF;

  v_data := jsonb_strip_nulls(jsonb_build_object(
    'id', p_sub_id,
    'status', p_status,
    'customer_id', p_customer_id,
    'canceled_at', CASE WHEN p_canceled_at IS NULL THEN NULL
                        ELSE to_char(p_canceled_at AT TIME ZONE 'UTC',
                                     'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,
    'current_billing_period', v_period,
    'items', CASE
      WHEN p_price_id IS NULL THEN '[]'::jsonb
      ELSE jsonb_build_array(jsonb_build_object(
        'price', jsonb_build_object('id', p_price_id)
      ))
    END,
    'custom_data', p_custom,
    'scheduled_change', CASE
      WHEN p_scheduled_cancel THEN jsonb_build_object('action', 'cancel')
      ELSE NULL
    END
  ));

  RETURN jsonb_build_object(
    'event_id', p_event_id,
    'event_type', 'subscription.' || p_status,
    'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'data', v_data
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.txn_payload(
  p_event_id TEXT,
  p_occurred_at TIMESTAMPTZ,
  p_txn_id TEXT,
  p_sub_id TEXT,
  p_customer_id TEXT,
  p_price_id TEXT,
  p_custom JSONB DEFAULT NULL,
  p_status TEXT DEFAULT 'completed'
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'event_id', p_event_id,
    'event_type', 'transaction.completed',
    'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'data', jsonb_strip_nulls(jsonb_build_object(
      'id', p_txn_id,
      'status', p_status,
      'customer_id', p_customer_id,
      'subscription_id', p_sub_id,
      'items', jsonb_build_array(jsonb_build_object(
        'price', jsonb_build_object('id', p_price_id)
      )),
      'custom_data', p_custom
    ))
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.create_checkout_session(
  p_company_id UUID,
  p_owner_id UUID,
  p_price_row_id UUID,
  p_txn_id TEXT,
  p_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_id UUID := gen_random_uuid();
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  INSERT INTO private.billing_checkout_sessions (
    id, company_id, provider_code, provider_environment,
    billing_provider_price_id, atlas_plan_code, offer_code,
    initiated_by_user_id, checkout_status, provider_create_status,
    external_transaction_id, checkout_url,
    idempotency_key, return_token_hash, return_token_version,
    allowed_return_origin, checkout_path, return_path,
    expires_at, created_at, updated_at
  ) VALUES (
    v_id, p_company_id, 'paddle', 'test',
    p_price_row_id, 'premium', 'premium_monthly',
    p_owner_id, 'created', 'created',
    p_txn_id, 'https://checkout.paddle.test/' || p_txn_id,
    p_idempotency_key,
    encode(extensions.digest(convert_to(p_idempotency_key, 'UTF8'), 'sha256'), 'hex'),
    1,
    'https://atlas.example', '/billing/checkout', '/billing/return',
    v_now + interval '1 hour', v_now, v_now
  );
  RETURN v_id;
END;
$$;

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company public.companies%ROWTYPE;

  v_co_main UUID;
  v_co_b UUID;
  v_co_manual UUID;
  v_co_unlinked UUID;
  v_co_atom UUID;

  v_price_row_id UUID;
  v_seed_price TEXT := 'pri_01kze90z27wy6m0fpxpebaewjv';

  v_sess_main UUID;
  v_sess_b UUID;
  v_sess_manual UUID;
  v_sess_unlinked UUID;
  v_sess_atom UUID;

  v_sub_main TEXT := pg_temp.paddle_id('sub_', 'main-sub');
  v_ctm_main TEXT := pg_temp.paddle_id('ctm_', 'main-ctm');
  v_txn_main TEXT := pg_temp.paddle_id('txn_', 'main-txn');

  v_sub_b TEXT := pg_temp.paddle_id('sub_', 'b-sub');
  v_ctm_b TEXT := pg_temp.paddle_id('ctm_', 'b-ctm');
  v_txn_b TEXT := pg_temp.paddle_id('txn_', 'b-txn');

  v_sub_manual TEXT := pg_temp.paddle_id('sub_', 'manual-sub');
  v_ctm_manual TEXT := pg_temp.paddle_id('ctm_', 'manual-ctm');
  v_txn_manual TEXT := pg_temp.paddle_id('txn_', 'manual-txn');

  v_sub_atom TEXT := pg_temp.paddle_id('sub_', 'atom-sub');
  v_ctm_atom TEXT := pg_temp.paddle_id('ctm_', 'atom-ctm');
  v_txn_atom TEXT := pg_temp.paddle_id('txn_', 'atom-txn');

  v_sub_unlinked TEXT := pg_temp.paddle_id('sub_', 'unlinked-sub');
  v_ctm_unlinked TEXT := pg_temp.paddle_id('ctm_', 'unlinked-ctm');
  v_txn_unlinked TEXT := pg_temp.paddle_id('txn_', 'unlinked-txn');

  v_bad_price TEXT := pg_temp.paddle_id('pri_', 'not-seeded-price');

  v_t0 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:00:00+00';
  v_t1 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:05:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:10:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:15:00+00';
  v_t4 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:20:00+00';
  v_t5 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:25:00+00';
  v_t6 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:30:00+00';
  v_t7 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:35:00+00';
  v_t8 TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:40:00+00';
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-08-17 10:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-09-17 10:00:00+00';

  v_apply_sig TEXT :=
    'public.apply_paddle_sandbox_webhook_event_server(uuid)';
  v_apply_priv TEXT :=
    'private.apply_paddle_sandbox_webhook_event(uuid)';

  v_id UUID;
  v_evt TEXT;
  v_sim TEXT;
  v_outcome TEXT;
  v_status TEXT;
  v_company_id UUID;
  v_attempts INTEGER;
  v_msg TEXT;
  v_sqlstate TEXT;
  v_row private.billing_provider_events%ROWTYPE;
  v_bill private.company_billing%ROWTYPE;
  v_sub public.company_subscriptions%ROWTYPE;
  v_eff TEXT;
  v_bool BOOLEAN;
  v_bool2 BOOLEAN;
  v_watermark TIMESTAMPTZ;
  v_watermark_before TIMESTAMPTZ;
  v_trial_used TIMESTAMPTZ;
  v_billing_fp_before TEXT;
  v_subs_fp_before TEXT;
  v_payload JSONB;
  v_custom JSONB;
  v_seq INT := 0;
  v_ingest_outcome TEXT;
  v_ingest_id UUID;
BEGIN
  -- =========================================================================
  -- Privileges / shape
  -- =========================================================================
  PERFORM pg_temp.record_result(
    'private_apply_no_execute',
    NOT has_function_privilege('anon', v_apply_priv, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_apply_priv, 'EXECUTE')
    AND NOT has_function_privilege('service_role', v_apply_priv, 'EXECUTE')
  );

  PERFORM pg_temp.record_result(
    'public_apply_service_role_only',
    has_function_privilege('service_role', v_apply_sig, 'EXECUTE')
    AND NOT has_function_privilege('anon', v_apply_sig, 'EXECUTE')
    AND NOT has_function_privilege('authenticated', v_apply_sig, 'EXECUTE')
  );

  SELECT
    p.prosecdef
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg IN ('search_path=', 'search_path=""')
    )
  INTO v_bool
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'apply_paddle_sandbox_webhook_event_server';

  PERFORM pg_temp.record_result(
    'public_apply_security_definer_empty_path_postgres',
    COALESCE(v_bool, FALSE)
  );

  SELECT
    NOT p.prosecdef
    AND pg_get_userbyid(p.proowner) = 'postgres'
    AND EXISTS (
      SELECT 1
      FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg IN ('search_path=', 'search_path=""')
    )
  INTO v_bool
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'apply_paddle_sandbox_webhook_event';

  PERFORM pg_temp.record_result(
    'private_apply_invoker_empty_path_postgres',
    COALESCE(v_bool, FALSE)
  );

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(
      gen_random_uuid()
    );
    PERFORM pg_temp.record_result(
      'authenticated_cannot_apply', false, NULL, 'unexpected success'
    );
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_apply', v_sqlstate = '42501', v_sqlstate, 'denied'
      );
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      PERFORM pg_temp.record_result(
        'authenticated_cannot_apply', false, v_sqlstate, v_msg
      );
  END;
  RESET ROLE;

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

  PERFORM pg_temp.record_result(
    'column_last_subscription_event_occurred_at_exists',
    EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'private'
        AND table_name = 'company_billing'
        AND column_name = 'last_subscription_event_occurred_at'
    )
  );

  -- =========================================================================
  -- Seed users / companies / checkout sessions
  -- =========================================================================
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2f-apply@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  SELECT p.id
  INTO v_price_row_id
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.external_price_id = v_seed_price
    AND p.is_active IS TRUE
  LIMIT 1;

  IF v_price_row_id IS NULL THEN
    RAISE EXCEPTION 'seeded paddle/test price % missing', v_seed_price;
  END IF;

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2F Apply Main',
    'company-14c2f-apply-main-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_co_main := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2F Apply B',
    'company-14c2f-apply-b-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_co_b := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2F Apply Manual',
    'company-14c2f-apply-manual-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_co_manual := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2F Apply Unlinked',
    'company-14c2f-apply-unlinked-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_co_unlinked := v_company.id;

  SELECT * INTO v_company
  FROM public.create_company(
    'Company 14C2F Apply Atom',
    'company-14c2f-apply-atom-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_co_atom := v_company.id;

  RESET ROLE;

  v_sess_main := pg_temp.create_checkout_session(
    v_co_main, v_owner, v_price_row_id, v_txn_main, 'idem-apply-main'
  );
  v_sess_b := pg_temp.create_checkout_session(
    v_co_b, v_owner, v_price_row_id, v_txn_b, 'idem-apply-b'
  );
  v_sess_manual := pg_temp.create_checkout_session(
    v_co_manual, v_owner, v_price_row_id, v_txn_manual, 'idem-apply-manual'
  );
  v_sess_unlinked := pg_temp.create_checkout_session(
    v_co_unlinked, v_owner, v_price_row_id, v_txn_unlinked, 'idem-apply-unlinked'
  );
  v_sess_atom := pg_temp.create_checkout_session(
    v_co_atom, v_owner, v_price_row_id, v_txn_atom, 'idem-apply-atom'
  );

  UPDATE public.company_subscriptions
  SET plan_code = 'premium',
      status = 'active',
      entitlement_origin = 'manual'
  WHERE company_id = v_co_manual;

  -- =========================================================================
  -- 4. Simulator apply → ignored / simulator_event; billing+subs unchanged
  -- =========================================================================
  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();
  v_sim := 'ntfsimevt_' || substr(md5('sim-apply'), 1, 26);
  v_id := pg_temp.insert_inbox(
    v_sim,
    'subscription.updated',
    'processing',
    jsonb_build_object('event_id', v_sim),
    v_t0,
    'verified'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'simulator_apply_ignored',
    v_outcome = 'ignored'
    AND v_status = 'ignored'
    AND v_row.processing_status = 'ignored'
    AND v_row.error_sanitized = 'simulator_event'
    AND pg_temp.billing_fp() = v_billing_fp_before
    AND pg_temp.subs_fp() = v_subs_fp_before,
    NULL,
    format('outcome=%s status=%s err=%s', v_outcome, v_status, v_row.error_sanitized)
  );

  -- =========================================================================
  -- 5. wrong processing_status (received) → invalid_state
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'invalid-state-' || v_seq::text);
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received',
    jsonb_build_object('event_id', v_evt), v_t0, 'verified'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'apply_invalid_state_received',
    v_outcome = 'invalid_state' AND v_status = 'received',
    NULL,
    format('%s/%s', v_outcome, v_status)
  );

  -- =========================================================================
  -- 6. unverified → not_verified
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'not-verified-' || v_seq::text);
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing',
    jsonb_build_object('event_id', v_evt), v_t0, 'unverified'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'apply_not_verified',
    v_outcome = 'not_verified' AND v_status = 'processing',
    NULL,
    format('%s/%s', v_outcome, v_status)
  );

  -- =========================================================================
  -- 7. missing payload_json → ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING + fail
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'payload-missing-' || v_seq::text);
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing',
    jsonb_build_object('event_id', v_evt), v_t0, 'verified'
  );
  UPDATE private.billing_provider_events
  SET payload_json = NULL
  WHERE id = v_id;

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_payload_missing_exception', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_payload_missing_exception',
      v_msg = 'ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING',
      v_sqlstate,
      v_msg
    );
  END;

  SELECT processing_status INTO v_status
  FROM private.billing_provider_events WHERE id = v_id;

  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING'
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'apply_payload_missing_fail_finalizer',
    v_status = 'processing'
    AND v_outcome = 'failed'
    AND v_row.processing_status = 'failed'
    AND v_row.error_sanitized = 'ATLAS_PROVIDER_EVENT_PAYLOAD_MISSING',
    NULL,
    format('pre=%s fail=%s final=%s', v_status, v_outcome, v_row.processing_status)
  );

  -- =========================================================================
  -- 8. unsupported type → fail
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'unsupported-type-' || v_seq::text);
  v_id := pg_temp.insert_inbox(
    v_evt, 'customer.created', 'processing',
    jsonb_build_object('event_id', v_evt, 'data', jsonb_build_object('status', 'x')),
    v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_unsupported_type', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_unsupported_type',
      v_msg = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_UNSUPPORTED'
  );
  RESET ROLE;

  -- =========================================================================
  -- 9. malformed payload → fail
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'malformed-' || v_seq::text);
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'processing',
    jsonb_build_object(
      'event_id', v_evt,
      'occurred_at', to_char(v_t0 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object('id', 'not-a-sub', 'status', 'active')
    ),
    v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_malformed_payload', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_malformed_payload',
      v_msg = 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_INVALID_PAYLOAD'
  );
  RESET ROLE;

  -- =========================================================================
  -- 10. unsupported schema version
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'bad-schema-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_main, v_sess_main, 'premium_monthly', 99);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_main, v_sub_main, v_ctm_main, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_unsupported_schema', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_unsupported_schema',
      v_msg = 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_UNSUPPORTED_SCHEMA'
  );
  RESET ROLE;

  -- =========================================================================
  -- 11. company UUID alone insufficient → UNLINKED
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'company-only-' || v_seq::text);
  v_custom := jsonb_build_object(
    'atlas_schema_version', 1,
    'atlas_company_id', v_co_unlinked
  );
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_unlinked, v_sub_unlinked, v_ctm_unlinked,
    v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_company_alone_unlinked', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_company_alone_unlinked',
      v_msg = 'ATLAS_PROVIDER_EVENT_UNLINKED',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_UNLINKED'
  );
  RESET ROLE;

  -- =========================================================================
  -- 12. wrong checkout session / cross-tenant → LINK_CONFLICT
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'cross-tenant-' || v_seq::text);
  -- session belongs to co_b, custom claims co_main
  v_custom := pg_temp.custom_data(v_co_main, v_sess_b, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_b, pg_temp.paddle_id('sub_', 'cross-sub'),
    pg_temp.paddle_id('ctm_', 'cross-ctm'), v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_cross_tenant_link_conflict', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_cross_tenant_link_conflict',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_LINK_CONFLICT'
  );
  RESET ROLE;

  -- =========================================================================
  -- 13. wrong offer / wrong price → mismatch or conflict
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'wrong-offer-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_unlinked, v_sess_unlinked, 'premium_yearly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_unlinked, v_sub_unlinked, v_ctm_unlinked,
    v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_wrong_offer', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_wrong_offer',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_LINK_CONFLICT'
  );
  RESET ROLE;

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'wrong-price-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_unlinked, v_sess_unlinked, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_unlinked, v_sub_unlinked, v_ctm_unlinked,
    v_bad_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_wrong_price', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_wrong_price',
      v_msg = 'ATLAS_PROVIDER_PRICE_MISMATCH',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_PRICE_MISMATCH'
  );
  RESET ROLE;

  -- =========================================================================
  -- 14. stolen subscription / customer id → conflict
  --     (first establish main linkage, then attempt steal onto co_b)
  -- =========================================================================
  -- Establish main via transaction.completed first (also covers test 16 partially)
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'first-link-txn-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_main, v_sess_main, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_main, v_sub_main, v_ctm_main, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received', v_payload, v_t0, 'verified'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome, processing_status, company_id
  INTO v_outcome, v_status, v_company_id
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'first_link_transaction_completed',
    v_outcome = 'applied'
    AND v_status = 'processed'
    AND v_company_id = v_co_main
    AND v_bill.external_subscription_id = v_sub_main
    AND v_bill.external_customer_id = v_ctm_main
    AND v_bill.external_price_id = v_seed_price
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status IS DISTINCT FROM 'entitled'
    AND v_bill.last_subscription_event_occurred_at IS NULL
    AND v_sub.plan_code = 'free'
    AND v_sub.entitlement_origin = 'none'
    AND v_eff = 'free',
    NULL,
    format(
      'out=%s pay=%s access=%s plan=%s origin=%s eff=%s wm=%s',
      v_outcome, v_bill.payment_status, v_bill.provider_access_status,
      v_sub.plan_code, v_sub.entitlement_origin, v_eff,
      v_bill.last_subscription_event_occurred_at
    )
  );

  -- Stolen subscription id onto co_b session
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'stolen-sub-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_b, v_sess_b, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_b, v_sub_main, v_ctm_b, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_stolen_subscription_id', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_stolen_subscription_id',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_LINK_CONFLICT'
  );
  RESET ROLE;

  -- Stolen customer id
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'stolen-ctm-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_b, v_sess_b, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_b, v_sub_b, v_ctm_main, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_stolen_customer_id', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_stolen_customer_id',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_LINK_CONFLICT'
  );
  RESET ROLE;

  -- =========================================================================
  -- 15. manual entitlement overwrite rejected
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'manual-reject-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_manual, v_sess_manual, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_manual, v_sub_manual, v_ctm_manual, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'processing', v_payload, v_t0, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_manual_entitlement_conflict', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_manual_entitlement_conflict',
      v_msg = 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_MANUAL_ENTITLEMENT_CONFLICT'
  );
  RESET ROLE;

  -- =========================================================================
  -- 17. subscription.activated → entitled + premium + watermark advanced
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'activated-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t1, 'active', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  -- fix event_type in payload root is cosmetic; inbox.event_type is authoritative
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.activated', 'received', v_payload, v_t1, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome, processing_status, company_id
  INTO v_outcome, v_status, v_company_id
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'subscription_activated_entitled',
    v_outcome = 'applied'
    AND v_status = 'processed'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.subscription_status = 'active'
    AND v_bill.payment_status = 'ok'
    AND v_bill.last_subscription_event_occurred_at = v_t1
    AND v_sub.plan_code = 'premium'
    AND v_sub.status = 'active'
    AND v_sub.entitlement_origin = 'provider'
    AND v_eff = 'premium',
    NULL,
    format(
      'out=%s access=%s plan=%s origin=%s eff=%s wm=%s',
      v_outcome, v_bill.provider_access_status, v_sub.plan_code,
      v_sub.entitlement_origin, v_eff, v_bill.last_subscription_event_occurred_at
    )
  );

  -- =========================================================================
  -- 18. active missing/invalid period → fail
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'bad-period-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t2, 'active', v_sub_main, v_ctm_main, v_seed_price,
    NULL, NULL, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'processing', v_payload, v_t2, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_active_invalid_period', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_active_invalid_period',
      v_msg = 'ATLAS_PROVIDER_PERIOD_INVALID',
      v_sqlstate,
      v_msg
    );
  END;

  SELECT processing_status INTO v_status
  FROM private.billing_provider_events WHERE id = v_id;
  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_PERIOD_INVALID'
  );
  RESET ROLE;
  PERFORM pg_temp.record_result(
    'apply_active_invalid_period_not_processed',
    v_status = 'processing' AND v_outcome = 'failed',
    NULL,
    format('pre=%s fail=%s', v_status, v_outcome)
  );

  -- =========================================================================
  -- 19. past_due → payment past_due, access blocked, grace null, effective free
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'past-due-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t2, 'past_due', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.past_due', 'received', v_payload, v_t2, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT r.effective_plan_code, r.provider_access_status, r.grace_ends_at IS NULL
  INTO v_eff, v_status, v_bool
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'subscription_past_due_blocks_access',
    v_outcome = 'applied'
    AND v_bill.payment_status = 'past_due'
    AND v_bill.provider_access_status = 'blocked'
    AND v_bill.grace_ends_at IS NULL
    AND v_bill.last_subscription_event_occurred_at = v_t2
    AND v_eff = 'free'
    AND v_bool IS TRUE,
    NULL,
    format('pay=%s access=%s eff=%s', v_bill.payment_status,
           v_bill.provider_access_status, v_eff)
  );

  -- =========================================================================
  -- 20. paused → billing paused/blocked, subs free/free/provider, trial_used kept
  -- =========================================================================
  v_trial_used := TIMESTAMPTZ '2026-07-01 00:00:00+00';
  UPDATE public.company_subscriptions
  SET trial_used_at = v_trial_used
  WHERE company_id = v_co_main;

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'paused-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t3, 'paused', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'received', v_payload, v_t3, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'subscription_paused',
    v_outcome = 'applied'
    AND v_bill.subscription_status = 'paused'
    AND v_bill.provider_access_status = 'blocked'
    AND v_sub.plan_code = 'free'
    AND v_sub.status = 'free'
    AND v_sub.entitlement_origin = 'provider'
    AND v_sub.trial_used_at = v_trial_used
    AND v_eff = 'free',
    NULL,
    format(
      'sub_status=%s access=%s plan=%s origin=%s trial_used=%s eff=%s',
      v_bill.subscription_status, v_bill.provider_access_status,
      v_sub.plan_code, v_sub.entitlement_origin, v_sub.trial_used_at, v_eff
    )
  );

  -- =========================================================================
  -- 21. later active restores premium after paused
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'restore-active-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t4, 'active', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'received', v_payload, v_t4, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'subscription_active_restores_premium',
    v_outcome = 'applied'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.subscription_status = 'active'
    AND v_sub.plan_code = 'premium'
    AND v_sub.status = 'active'
    AND v_sub.entitlement_origin = 'provider'
    AND v_eff = 'premium'
    AND v_bill.last_subscription_event_occurred_at = v_t4,
    NULL,
    format('access=%s plan=%s eff=%s', v_bill.provider_access_status,
           v_sub.plan_code, v_eff)
  );

  -- =========================================================================
  -- 22. trialing → ATLAS_PROVIDER_TRIALING_UNSUPPORTED (no premium / no trial)
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'trialing-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t5, 'trialing', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'processing', v_payload, v_t5, 'verified'
  );

  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_trialing_unsupported', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'apply_trialing_unsupported',
      v_msg = 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED'
      AND pg_temp.billing_fp() = v_billing_fp_before
      AND pg_temp.subs_fp() = v_subs_fp_before,
      v_sqlstate,
      v_msg
    );
  END;

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_TRIALING_UNSUPPORTED'
  );
  RESET ROLE;

  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  PERFORM pg_temp.record_result(
    'trialing_does_not_set_internal_trial',
    v_sub.entitlement_origin = 'provider'
    AND v_sub.plan_code = 'premium'
    AND v_sub.trial_started_at IS NULL
    AND v_sub.trial_ends_at IS NULL,
    NULL,
    format('origin=%s plan=%s', v_sub.entitlement_origin, v_sub.plan_code)
  );

  -- =========================================================================
  -- 23. scheduled cancel while active → cancel_at_period_end, still entitled
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'sched-cancel-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t5, 'active', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, TRUE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'received', v_payload, v_t5, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'scheduled_cancel_still_entitled',
    v_outcome = 'applied'
    AND v_bill.cancel_at_period_end IS TRUE
    AND v_bill.provider_access_status = 'entitled'
    AND v_eff = 'premium',
    NULL,
    format('cancel_at_end=%s access=%s eff=%s',
           v_bill.cancel_at_period_end, v_bill.provider_access_status, v_eff)
  );

  -- =========================================================================
  -- 24. canceled → ended/ended, free/free, trials null, trial_used preserved
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'canceled-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t6, 'canceled', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, v_t6
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.canceled', 'received', v_payload, v_t6, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, now()) r;

  PERFORM pg_temp.record_result(
    'subscription_canceled',
    v_outcome = 'applied'
    AND v_bill.subscription_status = 'ended'
    AND v_bill.provider_access_status = 'ended'
    AND v_sub.plan_code = 'free'
    AND v_sub.status = 'free'
    AND v_sub.entitlement_origin = 'provider'
    AND v_sub.trial_started_at IS NULL
    AND v_sub.trial_ends_at IS NULL
    AND v_sub.trial_used_at = v_trial_used
    AND v_eff = 'free',
    NULL,
    format(
      'bill=%s/%s plan=%s/%s/%s trial_used=%s eff=%s',
      v_bill.subscription_status, v_bill.provider_access_status,
      v_sub.plan_code, v_sub.status, v_sub.entitlement_origin,
      v_sub.trial_used_at, v_eff
    )
  );

  -- =========================================================================
  -- Re-activate for ordering / watermark tests (t7)
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'reactivate-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t7, 'active', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'received', v_payload, v_t7, 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT last_subscription_event_occurred_at INTO v_watermark
  FROM private.company_billing WHERE company_id = v_co_main;

  -- =========================================================================
  -- 25. stale older occurred_at → stale / ignored / stale_event, no regression
  -- =========================================================================
  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'stale-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t4, 'canceled', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, v_t4
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.canceled', 'processing', v_payload, v_t4, 'verified'
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT * INTO v_sub FROM public.company_subscriptions WHERE company_id = v_co_main;

  PERFORM pg_temp.record_result(
    'stale_older_event_ignored',
    v_outcome = 'stale'
    AND v_status = 'ignored'
    AND v_row.error_sanitized = 'stale_event'
    AND v_bill.last_subscription_event_occurred_at = v_watermark
    AND v_bill.provider_access_status = 'entitled'
    AND v_sub.plan_code = 'premium'
    AND pg_temp.billing_fp() = v_billing_fp_before
    AND pg_temp.subs_fp() = v_subs_fp_before,
    NULL,
    format('out=%s err=%s access=%s', v_outcome, v_row.error_sanitized,
           v_bill.provider_access_status)
  );

  -- =========================================================================
  -- 26. transaction does NOT advance watermark
  -- =========================================================================
  v_watermark_before := v_watermark;
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'txn-no-wm-' || v_seq::text);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t8, pg_temp.paddle_id('txn_', 'later-txn'),
    v_sub_main, v_ctm_main, v_seed_price, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received', v_payload, v_t8, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome INTO v_outcome
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  SELECT last_subscription_event_occurred_at INTO v_watermark
  FROM private.company_billing WHERE company_id = v_co_main;

  PERFORM pg_temp.record_result(
    'transaction_does_not_advance_watermark',
    v_outcome = 'applied'
    AND v_watermark = v_watermark_before
    AND v_watermark_before = v_t7,
    NULL,
    format('out=%s wm_before=%s wm_after=%s', v_outcome,
           v_watermark_before, v_watermark)
  );

  -- =========================================================================
  -- 27. equal timestamp equivalent → safe no-op processed
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'equal-equiv-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t7, 'active', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'processing', v_payload, v_t7, 'verified'
  );

  v_billing_fp_before := pg_temp.billing_fp();
  v_subs_fp_before := pg_temp.subs_fp();

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status
  INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;

  PERFORM pg_temp.record_result(
    'equal_timestamp_equivalent_noop',
    v_outcome = 'applied'
    AND v_status = 'processed'
    AND pg_temp.billing_fp() = v_billing_fp_before
    AND pg_temp.subs_fp() = v_subs_fp_before,
    NULL,
    format('out=%s status=%s', v_outcome, v_status)
  );

  -- =========================================================================
  -- 28. equal timestamp conflicting → ORDER_AMBIGUOUS + fail finalizer
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'equal-conflict-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t7, 'past_due', v_sub_main, v_ctm_main, v_seed_price,
    v_period_start, v_period_end, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.past_due', 'processing', v_payload, v_t7, 'verified'
  );

  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'equal_timestamp_conflicting', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'equal_timestamp_conflicting',
      v_msg = 'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS',
      v_sqlstate,
      v_msg
    );
  END;

  SELECT processing_status INTO v_status
  FROM private.billing_provider_events WHERE id = v_id;
  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS'
  );
  RESET ROLE;
  PERFORM pg_temp.record_result(
    'equal_timestamp_conflicting_fail_finalizer',
    v_status = 'processing' AND v_outcome = 'failed',
    NULL,
    format('pre=%s fail=%s', v_status, v_outcome)
  );

  -- =========================================================================
  -- 29. atomicity on separate company (link + fail + reclaim)
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'atom-txn-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_atom, v_sess_atom, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_atom, v_sub_atom, v_ctm_atom, v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received', v_payload, v_t0, 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  SELECT outcome, processing_status INTO v_outcome, v_status
  FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;
  PERFORM pg_temp.record_result(
    'atomicity_successful_apply_processed',
    v_outcome = 'applied' AND v_status = 'processed',
    NULL,
    format('%s/%s', v_outcome, v_status)
  );

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'atom-bad-period-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t1, 'active', v_sub_atom, v_ctm_atom, v_seed_price,
    v_period_end, v_period_start, NULL, FALSE, NULL
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.activated', 'received', v_payload, v_t1, 'verified'
  );

  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  BEGIN
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'atomicity_forced_failure_raises', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'atomicity_forced_failure_raises',
      v_msg = 'ATLAS_PROVIDER_PERIOD_INVALID',
      v_sqlstate,
      v_msg
    );
  END;

  SELECT processing_status INTO v_status
  FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'atomicity_forced_failure_not_processed',
    v_status = 'processing',
    NULL,
    v_status
  );

  SET LOCAL ROLE service_role;
  SELECT outcome INTO v_outcome
  FROM public.fail_paddle_sandbox_webhook_event_processing_server(
    v_id, 'ATLAS_PROVIDER_PERIOD_INVALID'
  );
  RESET ROLE;
  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_id;
  PERFORM pg_temp.record_result(
    'atomicity_fail_finalizer_works',
    v_outcome = 'failed'
    AND v_row.processing_status = 'failed'
    AND v_row.error_sanitized = 'ATLAS_PROVIDER_PERIOD_INVALID',
    NULL,
    format('%s/%s/%s', v_outcome, v_row.processing_status, v_row.error_sanitized)
  );

  SET LOCAL ROLE service_role;
  SELECT outcome, processing_status, attempt_count
  INTO v_outcome, v_status, v_attempts
  FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  RESET ROLE;
  PERFORM pg_temp.record_result(
    'atomicity_reclaim_from_failed',
    v_outcome = 'claimed'
    AND v_status = 'processing'
    AND v_attempts >= 2,
    NULL,
    format('out=%s status=%s attempts=%s', v_outcome, v_status, v_attempts)
  );

  -- =========================================================================
  -- Phase E hardening: expired/abandoned session, scheduled_change, future
  -- canceled period, provider raw null
  -- =========================================================================
  -- Reuse unlinked company's session: force expired open session
  UPDATE private.billing_checkout_sessions
  SET
    created_at = clock_timestamp() - interval '2 hours',
    expires_at = clock_timestamp() - interval '30 seconds',
    updated_at = clock_timestamp()
  WHERE id = v_sess_unlinked;

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'expired-sess-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_unlinked, v_sess_unlinked, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_unlinked, v_sub_unlinked, v_ctm_unlinked,
    v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received', v_payload, v_t0, 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  BEGIN
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'first_link_expired_session_rejected', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'first_link_expired_session_rejected',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  UPDATE private.billing_checkout_sessions
  SET
    checkout_status = 'abandoned',
    expires_at = clock_timestamp() + interval '1 hour',
    updated_at = clock_timestamp()
  WHERE id = v_sess_unlinked;

  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'abandoned-sess-' || v_seq::text);
  v_custom := pg_temp.custom_data(v_co_unlinked, v_sess_unlinked, 'premium_monthly', 1);
  v_payload := pg_temp.txn_payload(
    v_evt, v_t0, v_txn_unlinked, v_sub_unlinked, v_ctm_unlinked,
    v_seed_price, v_custom
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'transaction.completed', 'received', v_payload, v_t0, 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  BEGIN
    PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'first_link_abandoned_session_rejected', false, NULL, 'unexpected success'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    RESET ROLE;
    PERFORM pg_temp.record_result(
      'first_link_abandoned_session_rejected',
      v_msg = 'ATLAS_PROVIDER_LINK_CONFLICT',
      v_sqlstate,
      v_msg
    );
  END;

  -- scheduled_change action != cancel must not set cancel_at_period_end
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'sched-pause-action-' || v_seq::text);
  v_payload := jsonb_build_object(
    'event_id', v_evt,
    'event_type', 'subscription.updated',
    'occurred_at', to_char((v_t7 + interval '5 minutes') AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'data', jsonb_build_object(
      'id', v_sub_main,
      'status', 'active',
      'customer_id', v_ctm_main,
      'items', jsonb_build_array(jsonb_build_object(
        'price', jsonb_build_object('id', v_seed_price)
      )),
      'current_billing_period', jsonb_build_object(
        'starts_at', to_char(v_period_start AT TIME ZONE 'UTC',
                             'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'ends_at', to_char(v_period_end AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      'scheduled_change', jsonb_build_object('action', 'pause')
    )
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.updated', 'received', v_payload,
    v_t7 + interval '5 minutes', 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  PERFORM pg_temp.record_result(
    'scheduled_change_non_cancel_no_flag',
    v_bill.cancel_at_period_end IS FALSE
    AND v_bill.provider_access_status = 'entitled',
    NULL,
    format('cancel_at_end=%s access=%s', v_bill.cancel_at_period_end,
           v_bill.provider_access_status)
  );

  -- canceled with future period_end still ends access
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'canceled-future-period-' || v_seq::text);
  v_payload := pg_temp.sub_payload(
    v_evt, v_t7 + interval '10 minutes', 'canceled', v_sub_main, v_ctm_main,
    v_seed_price, v_period_start, v_period_end, NULL, FALSE, clock_timestamp()
  );
  v_id := pg_temp.insert_inbox(
    v_evt, 'subscription.canceled', 'received', v_payload,
    v_t7 + interval '10 minutes', 'verified'
  );
  SET LOCAL ROLE service_role;
  PERFORM * FROM public.claim_paddle_sandbox_webhook_event_for_processing_server(v_id);
  PERFORM * FROM public.apply_paddle_sandbox_webhook_event_server(v_id);
  RESET ROLE;
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_co_main;
  SELECT r.effective_plan_code INTO v_eff
  FROM private.resolve_company_entitlement(v_co_main, clock_timestamp()) r;
  PERFORM pg_temp.record_result(
    'canceled_future_period_not_entitled',
    v_bill.subscription_status = 'ended'
    AND v_bill.provider_access_status = 'ended'
    AND v_eff = 'free',
    NULL,
    format('sub=%s access=%s eff=%s', v_bill.subscription_status,
           v_bill.provider_access_status, v_eff)
  );

  -- provider_*_raw remain null after apply path on atom company
  SELECT provider_subscription_raw IS NULL, provider_payment_raw IS NULL
  INTO v_bool, v_bool2
  FROM private.company_billing WHERE company_id = v_co_atom;
  PERFORM pg_temp.record_result(
    'provider_raw_fields_remain_null',
    v_bool IS TRUE AND v_bool2 IS TRUE,
    NULL,
    format('sub_null=%s pay_null=%s', v_bool, v_bool2)
  );

  -- =========================================================================
  -- 30. ingest accepts subscription.activated as supported
  -- =========================================================================
  v_seq := v_seq + 1;
  v_evt := pg_temp.paddle_id('evt_', 'ingest-activated-' || v_seq::text);
  SET LOCAL ROLE service_role;
  SELECT outcome, inbox_event_id
  INTO v_ingest_outcome, v_ingest_id
  FROM public.ingest_paddle_sandbox_webhook_event_server(
    v_evt,
    'subscription.activated',
    v_t0,
    repeat('c', 64),
    jsonb_build_object('event_id', v_evt),
    'supported',
    NULL
  );
  RESET ROLE;

  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_ingest_id;
  PERFORM pg_temp.record_result(
    'ingest_accepts_subscription_activated',
    v_ingest_outcome = 'inserted'
    AND v_row.event_type = 'subscription.activated'
    AND v_row.processing_status = 'received'
    AND v_row.verification_status = 'verified',
    NULL,
    format('out=%s type=%s status=%s', v_ingest_outcome, v_row.event_type,
           v_row.processing_status)
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

DO $$
DECLARE
  v_failed INTEGER;
BEGIN
  SELECT count(*)::integer INTO v_failed FROM test_results WHERE NOT passed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION '14C-2F Phase D apply tests failed: %', v_failed;
  END IF;
END;
$$;

ROLLBACK;
