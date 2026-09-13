-- =============================================================================
-- LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
-- Project Atlas — Step 14C-2J Phase B2/C (+ FIX1 + FIX8)
-- Shared applicator + provider fence + equal-event-timestamp fence rules.
-- migration: 20260912140001_billing_shared_paddle_subscription_applicator.sql
--
-- AUTHORED FOR REVIEW — DO NOT EXECUTE until explicit local validation.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TEMP TABLE test_results (
  test_name TEXT PRIMARY KEY,
  passed BOOLEAN NOT NULL,
  sqlstate TEXT,
  detail TEXT
) ON COMMIT DROP;

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

CREATE OR REPLACE FUNCTION pg_temp.expect_atlas_error(
  p_name TEXT,
  p_expected TEXT,
  p_sqlstate TEXT,
  p_msg TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_temp, pg_catalog
AS $$
BEGIN
  PERFORM pg_temp.record_result(
    p_name,
    p_sqlstate = 'P0001' AND p_msg = p_expected,
    p_sqlstate,
    p_msg
  );
END;
$$;

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

-- ---------------------------------------------------------------------------
-- EQ-01..EQ-08 equal-event-timestamp provider-fence matrix (FIX1)
-- Webhook contract mapping under test:
--   shared stale_provider_state -> webhook outcome `stale`
--   shared already_applied|repaired_same_version|applied -> webhook `applied`
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID;
  v_company_row public.companies%ROWTYPE;
  v_price TEXT;
  v_cust TEXT := 'ctm_' || substr(md5('b2c-eq-customer-01'), 1, 26);
  v_subid TEXT := 'sub_' || substr(md5('b2c-eq-subscription-01'), 1, 26);
  v_wm TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t1 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 09:00:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 11:00:00+00';
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_fp TEXT;
  v_fp2 TEXT;
  v_evt_id UUID;
  v_payload JSONB;
  v_out RECORD;
  v_bill private.company_billing%ROWTYPE;
  v_bill_before private.company_billing%ROWTYPE;
  v_row private.billing_provider_events%ROWTYPE;
  v_msg TEXT;
  v_sqlstate TEXT;
  v_def TEXT;
  v_seq INT := 0;
BEGIN
  -- Resolve seeded paddle/test price
  SELECT p.external_price_id INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'B2C EQ tests require seeded paddle/test price';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2ceq@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C EQ',
    'company-14c2j-b2c-eq-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  -- Linked premium company with fence T2 + watermark = v_wm
  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  v_fp := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = v_wm,
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp
  WHERE company_id = v_company;

  -- Helper: build subscription payload with updated_at
  -- (inline jsonb for each case)

  -- =========================================================================
  -- EQ-08: source/function must not contain local-equivalence bypass
  -- =========================================================================
  SELECT pg_get_functiondef(p.oid)
  INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'apply_paddle_sandbox_webhook_event';

  PERFORM pg_temp.record_result(
    'EQ-08_no_local_equiv_bypass_before_fence',
    v_def IS NOT NULL
    AND v_def NOT LIKE '%v_equiv :=%'
    AND v_def LIKE '%billing_paddle_subscription_snapshot_fingerprint%'
    AND v_def LIKE '%ATLAS_PROVIDER_STATE_FENCE_UNINITIALIZED%'
    AND v_def LIKE '%ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS%'
  );

  -- =========================================================================
  -- EQ-01: equal event ts + older provider version => stale / ignored
  -- =========================================================================
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq01' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq01' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t1 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('a', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_evt_id;

  PERFORM pg_temp.record_result(
    'EQ-01_equal_ts_older_provider_stale',
    v_out.outcome = 'stale'
    AND v_out.processing_status = 'ignored'
    AND v_row.error_sanitized = 'stale_provider_state'
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
  );

  -- =========================================================================
  -- EQ-02: equal event ts + newer provider version => EVENT_ORDER_AMBIGUOUS
  -- =========================================================================
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq02' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq02' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t3 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('b', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  BEGIN
    PERFORM 1 FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
    PERFORM pg_temp.record_result('EQ-02_equal_ts_newer_provider_ambiguous', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'EQ-02_equal_ts_newer_provider_ambiguous',
      'ATLAS_PROVIDER_EVENT_ORDER_AMBIGUOUS',
      v_sqlstate,
      v_msg
    );
  END;

  -- =========================================================================
  -- EQ-03: equal ts + same version + different snapshot fp
  -- =========================================================================
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq03' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq03' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'past_due', -- different snapshot vs stored active
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('c', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  BEGIN
    PERFORM 1 FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
    PERFORM pg_temp.record_result('EQ-03_equal_ts_same_version_diff_fp', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'EQ-03_equal_ts_same_version_diff_fp',
      'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS',
      v_sqlstate,
      v_msg
    );
  END;

  -- =========================================================================
  -- EQ-04: equal ts + same version + same fp + local match => applied
  -- =========================================================================
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq04' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq04' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('d', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'EQ-04_equal_ts_same_fp_idempotent',
    v_out.outcome = 'applied'
    AND v_out.processing_status = 'processed'
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_fp
  );

  -- =========================================================================
  -- EQ-05: equal ts + same fp + local drift => repair, watermark unchanged
  -- =========================================================================
  UPDATE private.company_billing
  SET payment_status = 'past_due',
      provider_access_status = 'blocked',
      provider_access_ends_at = NULL
  WHERE company_id = v_company;
  -- Keep fence pair intact (same version/fp)
  UPDATE private.company_billing
  SET last_provider_subscription_updated_at = v_t2,
      last_provider_subscription_state_fingerprint = v_fp,
      last_subscription_event_occurred_at = v_wm
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq05' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq05' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('e', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'EQ-05_equal_ts_same_fp_repair',
    v_out.outcome = 'applied'
    AND v_out.processing_status = 'processed'
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_wm
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_fp
  );

  -- =========================================================================
  -- EQ-06: equal ts + NULL fence + non-NULL watermark => UNINITIALIZED
  -- =========================================================================
  UPDATE private.company_billing
  SET last_provider_subscription_updated_at = NULL,
      last_provider_subscription_state_fingerprint = NULL,
      last_subscription_event_occurred_at = v_wm,
      payment_status = 'ok',
      provider_access_status = 'entitled',
      provider_access_ends_at = v_period_end
  WHERE company_id = v_company;

  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq06' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq06' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('f', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  BEGIN
    PERFORM 1 FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
    PERFORM pg_temp.record_result('EQ-06_equal_ts_uninitialized_fence', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'EQ-06_equal_ts_uninitialized_fence',
      'ATLAS_PROVIDER_STATE_FENCE_UNINITIALIZED',
      v_sqlstate,
      v_msg
    );
  END;

  -- =========================================================================
  -- EQ-07: half-initialized fence => INTEGRITY
  -- =========================================================================
  UPDATE private.company_billing
  SET last_provider_subscription_updated_at = v_t2,
      last_provider_subscription_state_fingerprint = NULL,
      last_subscription_event_occurred_at = v_wm
  WHERE company_id = v_company;

  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('eq07' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm, 'verified', 'processing', v_wm,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('eq07' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('g', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  BEGIN
    PERFORM 1 FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
    PERFORM pg_temp.record_result('EQ-07_equal_ts_fence_integrity', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    PERFORM pg_temp.expect_atlas_error(
      'EQ-07_equal_ts_fence_integrity',
      'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY',
      v_sqlstate,
      v_msg
    );
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- PF-01..PF-14 provider snapshot fingerprint + shared applicator matrix
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_owner_pf07 UUID := gen_random_uuid();
  v_owner_pf08 UUID := gen_random_uuid();
  v_owner_pf09 UUID := gen_random_uuid();
  v_company UUID;
  v_company_pf07 UUID;
  v_company_pf08 UUID;
  v_company_pf09 UUID;
  v_company_row public.companies%ROWTYPE;
  v_price TEXT;
  -- Main PF company (PF-06 bootstrap + PF-10..PF-14): distinct from PF-07/08/09
  v_cust TEXT := 'ctm_' || substr(md5('b2c-pf06-customer'), 1, 26);
  v_subid TEXT := 'sub_' || substr(md5('b2c-pf06-subscription'), 1, 26);
  v_cust_pf07 TEXT := 'ctm_' || substr(md5('b2c-pf07-customer'), 1, 26);
  v_subid_pf07 TEXT := 'sub_' || substr(md5('b2c-pf07-subscription'), 1, 26);
  v_cust_pf08 TEXT := 'ctm_' || substr(md5('b2c-pf08-customer'), 1, 26);
  v_subid_pf08 TEXT := 'sub_' || substr(md5('b2c-pf08-subscription'), 1, 26);
  v_cust_pf09 TEXT := 'ctm_' || substr(md5('b2c-pf09-customer'), 1, 26);
  v_subid_pf09 TEXT := 'sub_' || substr(md5('b2c-pf09-subscription'), 1, 26);
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_t1 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 09:00:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 11:00:00+00';
  v_fp TEXT;
  v_fp2 TEXT;
  v_fp_active TEXT;
  v_fp_past_due TEXT;
  v_fp_pf09 TEXT;
  v_bill private.company_billing%ROWTYPE;
  v_bill_before private.company_billing%ROWTYPE;
  v_apply_out TEXT;
  v_msg TEXT;
  v_sqlstate TEXT;
  v_tz_before TEXT;
BEGIN
  SELECT p.external_price_id INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'B2C PF tests require seeded paddle/test price';
  END IF;

  v_fp_active := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_past_due := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'past_due',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_pf09 := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid_pf09, v_cust_pf09, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );

  -- PF-01: same normalized snapshot twice => same fingerprint
  v_fp := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  v_fp2 := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  PERFORM pg_temp.record_result(
    'PF-01_snapshot_fingerprint_deterministic',
    v_fp = v_fp2
  );

  -- PF-02: nullable TEXT NULL vs '' => distinct fingerprints
  PERFORM pg_temp.record_result(
    'PF-02_null_vs_empty_text_distinct',
    private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, NULL, 'active',
      v_period_start, v_period_end, false, NULL
    ) IS DISTINCT FROM private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, '', 'active',
      v_period_start, v_period_end, false, NULL
    )
  );

  -- PF-03: delimiter-safe jsonb array (would collide under raw "|" concat)
  PERFORM pg_temp.record_result(
    'PF-03_delimiter_safe_distinct',
    private.billing_paddle_subscription_snapshot_fingerprint(
      'sub|id', v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    ) IS DISTINCT FROM private.billing_paddle_subscription_snapshot_fingerprint(
      'sub', 'id|' || v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    )
  );

  -- PF-04: BOOLEAN NULL vs FALSE => distinct fingerprints
  PERFORM pg_temp.record_result(
    'PF-04_boolean_null_vs_false_distinct',
    private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, v_price, 'active',
      v_period_start, v_period_end, NULL, NULL
    ) IS DISTINCT FROM private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    )
  );

  -- PF-05: timezone invariant for TIMESTAMPTZ tokens
  BEGIN
    v_tz_before := current_setting('TimeZone');
    PERFORM set_config('TimeZone', 'UTC', true);
    v_fp := private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    );
    PERFORM set_config('TimeZone', 'America/New_York', true);
    v_fp2 := private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    );
    PERFORM set_config('TimeZone', v_tz_before, true);
    PERFORM pg_temp.record_result(
      'PF-05_timestamp_timezone_invariant',
      v_fp = v_fp2
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    BEGIN
      PERFORM set_config('TimeZone', v_tz_before, true);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM pg_temp.record_result(
      'PF-05_timestamp_timezone_invariant', false, v_sqlstate, v_msg
    );
  END;

  -- Shared company fixture for PF-06..PF-14
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2cpf@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C PF',
    'company-14c2j-b2c-pf-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  -- PF-06: NULL/NULL fence + bootstrap permitted => applied
  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = NULL,
    external_subscription_id = NULL,
    external_price_id = NULL,
    subscription_status = 'none',
    payment_status = 'ok',
    provider_access_status = 'none',
    provider_access_ends_at = NULL,
    current_period_start = NULL,
    current_period_end = NULL,
    cancel_at_period_end = false,
    sync_status = 'idle',
    last_subscription_event_occurred_at = NULL,
    last_provider_subscription_updated_at = NULL,
    last_provider_subscription_state_fingerprint = NULL
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, TRUE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'PF-06_null_fence_bootstrap_allowed',
    v_apply_out = 'applied'
    AND v_bill.subscription_status = 'active'
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.external_subscription_id IS NOT DISTINCT FROM v_subid
    AND v_bill.external_customer_id IS NOT DISTINCT FROM v_cust
  );

  -- PF-07: NULL/NULL fence + bootstrap forbidden => UNINITIALIZED, no mutation
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner_pf07, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2cpf07@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner_pf07);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C PF07',
    'company-14c2j-b2c-pf07-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company_pf07 := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company_pf07;

  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = NULL,
    last_provider_subscription_state_fingerprint = NULL,
    subscription_status = 'none',
    payment_status = 'ok',
    provider_access_status = 'none'
  WHERE company_id = v_company_pf07;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company_pf07;

  BEGIN
    PERFORM 1 FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company_pf07, v_subid_pf07, v_cust_pf07, v_price, 'active',
      v_period_start, v_period_end, false, NULL,
      v_t2, FALSE
    ) a;
    PERFORM pg_temp.record_result('PF-07_null_fence_bootstrap_forbidden', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company_pf07;
    PERFORM pg_temp.record_result(
      'PF-07_null_fence_bootstrap_forbidden',
      v_sqlstate = 'P0001'
      AND v_msg = 'ATLAS_PROVIDER_STATE_FENCE_UNINITIALIZED'
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
      AND v_bill.last_provider_subscription_updated_at
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
      AND v_bill.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint,
      v_sqlstate,
      v_msg
    );
  END;

  -- PF-08: version set / fp NULL => INTEGRITY, no mutation
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner_pf08, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2cpf08@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner_pf08);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C PF08',
    'company-14c2j-b2c-pf08-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company_pf08 := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company_pf08;

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust_pf08,
    external_subscription_id = v_subid_pf08,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    last_provider_subscription_updated_at = v_t1,
    last_provider_subscription_state_fingerprint = NULL
  WHERE company_id = v_company_pf08;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company_pf08;

  BEGIN
    PERFORM 1 FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company_pf08, v_subid_pf08, v_cust_pf08, v_price, 'active',
      v_period_start, v_period_end, false, NULL,
      v_t2, FALSE
    ) a;
    PERFORM pg_temp.record_result('PF-08_version_set_fp_null_integrity', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company_pf08;
    PERFORM pg_temp.record_result(
      'PF-08_version_set_fp_null_integrity',
      v_sqlstate = 'P0001'
      AND v_msg = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY'
      AND v_bill.last_provider_subscription_updated_at
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
      AND v_bill.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status,
      v_sqlstate,
      v_msg
    );
  END;

  -- PF-09: version NULL / fp set => INTEGRITY, no mutation
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner_pf09, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2cpf09@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner_pf09);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C PF09',
    'company-14c2j-b2c-pf09-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company_pf09 := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company_pf09;

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust_pf09,
    external_subscription_id = v_subid_pf09,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    last_provider_subscription_updated_at = NULL,
    last_provider_subscription_state_fingerprint = v_fp_pf09
  WHERE company_id = v_company_pf09;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company_pf09;

  BEGIN
    PERFORM 1 FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company_pf09, v_subid_pf09, v_cust_pf09, v_price, 'active',
      v_period_start, v_period_end, false, NULL,
      v_t2, FALSE
    ) a;
    PERFORM pg_temp.record_result('PF-09_version_null_fp_set_integrity', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company_pf09;
    PERFORM pg_temp.record_result(
      'PF-09_version_null_fp_set_integrity',
      v_sqlstate = 'P0001'
      AND v_msg = 'ATLAS_PROVIDER_STATE_FENCE_INTEGRITY'
      AND v_bill.last_provider_subscription_updated_at
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
      AND v_bill.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status,
      v_sqlstate,
      v_msg
    );
  END;

  -- Reset PF main company to initialized fence T1 for PF-10..PF-14
  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = NULL,
    last_provider_subscription_updated_at = v_t1,
    last_provider_subscription_state_fingerprint = v_fp_active
  WHERE company_id = v_company;

  -- PF-10: incoming newer version T2 => applied atomically
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'PF-10_incoming_newer_version_applied',
    v_apply_out = 'applied'
    AND v_bill.subscription_status = 'active'
    AND v_bill.payment_status = 'ok'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
  );

  -- PF-11: incoming older version T1 vs stored T2 => stale_provider_state, no mutation
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t1, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'PF-11_incoming_older_version_stale',
    v_apply_out = 'stale_provider_state'
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill.payment_status IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill.last_provider_subscription_updated_at
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
    AND v_bill.last_provider_subscription_state_fingerprint
      IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
  );

  -- PF-12: equal version + same fp + local match => already_applied
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'PF-12_equal_version_same_fp_already_applied',
    v_apply_out = 'already_applied'
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill.payment_status IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
  );

  -- PF-13: equal version + same fp + local drift => repaired_same_version
  UPDATE private.company_billing
  SET payment_status = 'past_due',
      provider_access_status = 'blocked',
      provider_access_ends_at = NULL
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'PF-13_equal_version_same_fp_repair',
    v_apply_out = 'repaired_same_version'
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
  );

  -- PF-14: equal version + different fp => STATE_ORDER_AMBIGUOUS, no mutation
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  BEGIN
    PERFORM 1 FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company, v_subid, v_cust, v_price, 'past_due',
      v_period_start, v_period_end, false, NULL,
      v_t2, FALSE
    ) a;
    PERFORM pg_temp.record_result('PF-14_equal_version_diff_fp_ambiguous', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
    PERFORM pg_temp.record_result(
      'PF-14_equal_version_diff_fp_ambiguous',
      v_sqlstate = 'P0001'
      AND v_msg = 'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS'
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
      AND v_bill.payment_status IS NOT DISTINCT FROM v_bill_before.payment_status
      AND v_bill.last_provider_subscription_updated_at
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
      AND v_bill.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint,
      v_sqlstate,
      v_msg
    );
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- RV1..RV7 race-proof webhook vs reconciliation fence matrix
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID;
  v_company_row public.companies%ROWTYPE;
  v_price TEXT;
  v_cust TEXT := 'ctm_' || substr(md5('b2c-rv-customer-01'), 1, 26);
  v_subid TEXT := 'sub_' || substr(md5('b2c-rv-subscription-01'), 1, 26);
  v_wm TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_wm_new TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:30:00+00';
  v_t1 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 09:00:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 11:00:00+00';
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_fp_active TEXT;
  v_fp_past_due TEXT;
  v_evt_id UUID;
  v_out RECORD;
  v_bill private.company_billing%ROWTYPE;
  v_bill_before private.company_billing%ROWTYPE;
  v_row private.billing_provider_events%ROWTYPE;
  v_apply_out TEXT;
  v_apply_out_first TEXT;
  v_apply_out_repair TEXT;
  v_msg TEXT;
  v_sqlstate TEXT;
  v_seq INT := 0;
BEGIN
  SELECT p.external_price_id INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'B2C RV tests require seeded paddle/test price';
  END IF;

  v_fp_active := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_past_due := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'past_due',
    v_period_start, v_period_end, false, NULL
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2crv@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C RV',
    'company-14c2j-b2c-rv-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = NULL,
    last_provider_subscription_updated_at = v_t1,
    last_provider_subscription_state_fingerprint = v_fp_active
  WHERE company_id = v_company;

  -- RV1: fence T1, webhook subscription snapshot T2 => applied, fence T2
  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('rv01' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm_new, 'verified', 'processing', v_wm_new,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('rv01' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm_new AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('r', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'RV1_webhook_advances_fence_to_t2',
    v_out.outcome = 'applied'
    AND v_out.processing_status = 'processed'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.subscription_status = 'active'
    AND v_bill.last_subscription_event_occurred_at IS NOT DISTINCT FROM v_wm_new
  );

  -- RV2: reconciliation at T3, stale webhook (newer event ts, older provider T2)
  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t3, FALSE
  ) a;

  UPDATE private.company_billing
  SET last_subscription_event_occurred_at = v_wm
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('rv02' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm_new, 'verified', 'processing', v_wm_new,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('rv02' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm_new AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('s', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_evt_id;

  PERFORM pg_temp.record_result(
    'RV2_stale_webhook_after_reconciliation_t3',
    v_apply_out = 'applied'
    AND v_out.outcome = 'stale'
    AND v_out.processing_status = 'ignored'
    AND v_row.error_sanitized = 'stale_provider_state'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
    AND v_bill.subscription_status = 'active'
  );

  -- RV3: webhook wins T3 first, shared applicator T2 => stale_provider_state
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t1,
    last_provider_subscription_state_fingerprint = v_fp_active,
    last_subscription_event_occurred_at = NULL,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled'
  WHERE company_id = v_company;

  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('rv03a' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm_new, 'verified', 'processing', v_wm_new,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('rv03a' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm_new AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t3 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('t', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'RV3_shared_applicator_stale_after_webhook_t3',
    v_out.outcome = 'applied'
    AND v_apply_out = 'stale_provider_state'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
  );

  -- RV4: T3 + same fp + local match => already_applied; drift => repaired_same_version
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out_first
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t3, FALSE
  ) a;

  UPDATE private.company_billing
  SET payment_status = 'past_due',
      provider_access_status = 'blocked',
      provider_access_ends_at = NULL
  WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out_repair
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t3, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'RV4_same_version_idempotent_and_repair',
    v_apply_out_first = 'already_applied'
    AND v_apply_out_repair = 'repaired_same_version'
    AND v_bill.payment_status = 'ok'
    AND v_bill.provider_access_status = 'entitled'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
  );

  -- RV5: stored T3 + incoming T3 different snapshot => STATE_ORDER_AMBIGUOUS
  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  BEGIN
    PERFORM 1 FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company, v_subid, v_cust, v_price, 'past_due',
      v_period_start, v_period_end, false, NULL,
      v_t3, FALSE
    ) a;
    PERFORM pg_temp.record_result('RV5_equal_version_diff_snapshot_ambiguous', false);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
    PERFORM pg_temp.record_result(
      'RV5_equal_version_diff_snapshot_ambiguous',
      v_sqlstate = 'P0001'
      AND v_msg = 'ATLAS_PROVIDER_STATE_ORDER_AMBIGUOUS'
      AND v_bill.last_provider_subscription_updated_at
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_updated_at
      AND v_bill.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_bill_before.last_provider_subscription_state_fingerprint
      AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status,
      v_sqlstate,
      v_msg
    );
  END;

  -- RV6: shared applicator must NOT write webhook watermark
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t1,
    last_provider_subscription_state_fingerprint = v_fp_active,
    last_subscription_event_occurred_at = v_wm,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled'
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL,
    v_t2, FALSE
  ) a;

  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;

  PERFORM pg_temp.record_result(
    'RV6_shared_applicator_no_watermark_write',
    v_apply_out = 'applied'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t2
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_bill_before.last_subscription_event_occurred_at
  );

  -- RV7: watermark W1 + fence T3 + stale provider event => stale wrapper, no regression
  UPDATE private.company_billing
  SET
    last_provider_subscription_updated_at = v_t3,
    last_provider_subscription_state_fingerprint = v_fp_active,
    last_subscription_event_occurred_at = v_wm,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end
  WHERE company_id = v_company;

  SELECT * INTO v_bill_before FROM private.company_billing WHERE company_id = v_company;

  v_seq := v_seq + 1;
  INSERT INTO private.billing_provider_events (
    provider_code, provider_environment, external_event_id, event_type,
    provider_created_at, verification_status, processing_status,
    signature_verified_at, payload_json, payload_hash, retention_expires_at,
    attempt_count, company_id
  ) VALUES (
    'paddle', 'test',
    'evt_' || substr(md5('rv07' || v_seq::text), 1, 26),
    'subscription.updated',
    v_wm_new, 'verified', 'processing', v_wm_new,
    jsonb_build_object(
      'event_id', 'evt_' || substr(md5('rv07' || v_seq::text), 1, 26),
      'event_type', 'subscription.updated',
      'occurred_at', to_char(v_wm_new AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'data', jsonb_build_object(
        'id', v_subid,
        'status', 'active',
        'customer_id', v_cust,
        'updated_at', to_char(v_t2 AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'current_billing_period', jsonb_build_object(
          'starts_at', to_char(v_period_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'ends_at', to_char(v_period_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        ),
        'items', jsonb_build_array(jsonb_build_object('price', jsonb_build_object('id', v_price)))
      )
    ),
    repeat('u', 64), now() + interval '30 days', 1, v_company
  ) RETURNING id INTO v_evt_id;

  SELECT * INTO v_out
  FROM public.apply_paddle_sandbox_webhook_event_server(v_evt_id);
  SELECT * INTO v_bill FROM private.company_billing WHERE company_id = v_company;
  SELECT * INTO v_row FROM private.billing_provider_events WHERE id = v_evt_id;

  PERFORM pg_temp.record_result(
    'RV7_webhook_stale_provider_no_regression',
    v_out.outcome = 'stale'
    AND v_out.processing_status = 'ignored'
    AND v_row.error_sanitized = 'stale_provider_state'
    AND v_bill.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
    AND v_bill.last_provider_subscription_state_fingerprint IS NOT DISTINCT FROM v_fp_active
    AND v_bill.last_subscription_event_occurred_at
      IS NOT DISTINCT FROM v_wm
    AND v_bill.subscription_status IS NOT DISTINCT FROM v_bill_before.subscription_status
    AND v_bill.payment_status IS NOT DISTINCT FROM v_bill_before.payment_status
    AND v_bill.provider_access_status IS NOT DISTINCT FROM v_bill_before.provider_access_status
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- CN-01..CN-02 canceled mapping determinism (FIX8)
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_owner UUID := gen_random_uuid();
  v_company UUID;
  v_company_row public.companies%ROWTYPE;
  v_price TEXT;
  v_cust TEXT := 'ctm_' || substr(md5('b2c-cn-customer'), 1, 26);
  v_subid TEXT := 'sub_' || substr(md5('b2c-cn-subscription'), 1, 26);
  v_period_start TIMESTAMPTZ := TIMESTAMPTZ '2026-09-01 00:00:00+00';
  v_period_end TIMESTAMPTZ := TIMESTAMPTZ '2026-10-01 00:00:00+00';
  v_t2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:00:00+00';
  v_t3 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 11:00:00+00';
  v_n1 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 12:00:00+00';
  v_n2 TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 13:00:00+00';
  v_explicit_canceled_at TIMESTAMPTZ := TIMESTAMPTZ '2026-09-13 10:30:00+00';
  v_fp_active TEXT;
  v_fp_canceled_null TEXT;
  v_fp_canceled_explicit TEXT;
  v_bill private.company_billing%ROWTYPE;
  v_bill_after1 private.company_billing%ROWTYPE;
  v_bill_after2 private.company_billing%ROWTYPE;
  v_apply_out TEXT;
  v_canceled_at_1 TIMESTAMPTZ;
BEGIN
  SELECT p.external_price_id INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'B2C CN tests require seeded paddle/test price';
  END IF;

  v_fp_active := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_canceled_null := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'canceled',
    v_period_start, v_period_end, false, NULL
  );
  v_fp_canceled_explicit := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'canceled',
    v_period_start, v_period_end, false, v_explicit_canceled_at
  );

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'owner14c2jb2ccn@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  PERFORM pg_temp.set_auth(v_owner);
  SET LOCAL ROLE authenticated;
  SELECT * INTO v_company_row
  FROM public.create_company(
    'Company 14C2J B2C CN',
    'company-14c2j-b2c-cn-' || substr(gen_random_uuid()::text, 1, 8)
  );
  v_company := v_company_row.id;
  RESET ROLE;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  -- Valid fence before canceled transition (active @ T2)
  UPDATE private.company_billing
  SET
    provider_code = 'paddle',
    provider_environment = 'test',
    external_customer_id = v_cust,
    external_subscription_id = v_subid,
    external_price_id = v_price,
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    current_period_start = v_period_start,
    current_period_end = v_period_end,
    cancel_at_period_end = false,
    canceled_at = NULL,
    sync_status = 'idle',
    last_sync_result = 'succeeded',
    last_subscription_event_occurred_at = v_t2,
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active
  WHERE company_id = v_company;

  -- CN-01: canceled_at=NULL; fallback must be provider_updated_at (T3), not p_now
  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'canceled',
    v_period_start, v_period_end, false, NULL,
    v_t3, FALSE, v_n1
  ) a;

  SELECT * INTO v_bill_after1 FROM private.company_billing WHERE company_id = v_company;
  v_canceled_at_1 := v_bill_after1.canceled_at;

  IF v_apply_out IS DISTINCT FROM 'applied'
    OR v_canceled_at_1 IS DISTINCT FROM v_t3
  THEN
    PERFORM pg_temp.record_result(
      'CN-01_canceled_null_idempotent_across_p_now',
      false,
      NULL,
      format('first_apply=%s canceled_at=%s', v_apply_out, v_canceled_at_1)
    );
  ELSE
    SELECT a.outcome INTO v_apply_out
    FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company, v_subid, v_cust, v_price, 'canceled',
      v_period_start, v_period_end, false, NULL,
      v_t3, FALSE, v_n2
    ) a;

    SELECT * INTO v_bill_after2 FROM private.company_billing WHERE company_id = v_company;

    PERFORM pg_temp.record_result(
      'CN-01_canceled_null_idempotent_across_p_now',
      v_apply_out = 'already_applied'
      AND v_bill_after2.canceled_at IS NOT DISTINCT FROM v_canceled_at_1
      AND v_bill_after2.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
      AND v_bill_after2.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_fp_canceled_null
      AND v_bill_after2.subscription_status IS NOT DISTINCT FROM v_bill_after1.subscription_status
      AND v_bill_after2.payment_status IS NOT DISTINCT FROM v_bill_after1.payment_status
      AND v_bill_after2.provider_access_status IS NOT DISTINCT FROM v_bill_after1.provider_access_status
      AND v_bill_after2.last_subscription_event_occurred_at
        IS NOT DISTINCT FROM v_bill_after1.last_subscription_event_occurred_at
      AND v_bill_after1.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_fp_canceled_null
    );
  END IF;

  -- Reset to active fence for CN-02
  UPDATE private.company_billing
  SET
    subscription_status = 'active',
    payment_status = 'ok',
    provider_access_status = 'entitled',
    provider_access_ends_at = v_period_end,
    cancel_at_period_end = false,
    canceled_at = NULL,
    last_provider_subscription_updated_at = v_t2,
    last_provider_subscription_state_fingerprint = v_fp_active
  WHERE company_id = v_company;

  UPDATE public.company_subscriptions
  SET plan_code = 'premium', status = 'active', entitlement_origin = 'provider'
  WHERE company_id = v_company;

  -- CN-02: explicit provider canceled_at remains authoritative across replay
  SELECT a.outcome INTO v_apply_out
  FROM private.apply_normalized_paddle_sandbox_subscription_state(
    v_company, v_subid, v_cust, v_price, 'canceled',
    v_period_start, v_period_end, false, v_explicit_canceled_at,
    v_t3, FALSE, v_n1
  ) a;

  SELECT * INTO v_bill_after1 FROM private.company_billing WHERE company_id = v_company;
  v_canceled_at_1 := v_bill_after1.canceled_at;

  IF v_apply_out IS DISTINCT FROM 'applied'
    OR v_canceled_at_1 IS DISTINCT FROM v_explicit_canceled_at
  THEN
    PERFORM pg_temp.record_result(
      'CN-02_explicit_canceled_at_authoritative',
      false,
      NULL,
      format('first_apply=%s canceled_at=%s', v_apply_out, v_canceled_at_1)
    );
  ELSE
    SELECT a.outcome INTO v_apply_out
    FROM private.apply_normalized_paddle_sandbox_subscription_state(
      v_company, v_subid, v_cust, v_price, 'canceled',
      v_period_start, v_period_end, false, v_explicit_canceled_at,
      v_t3, FALSE, v_n2
    ) a;

    SELECT * INTO v_bill_after2 FROM private.company_billing WHERE company_id = v_company;

    PERFORM pg_temp.record_result(
      'CN-02_explicit_canceled_at_authoritative',
      v_apply_out = 'already_applied'
      AND v_bill_after2.canceled_at IS NOT DISTINCT FROM v_explicit_canceled_at
      AND v_bill_after2.last_provider_subscription_updated_at IS NOT DISTINCT FROM v_t3
      AND v_bill_after2.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_fp_canceled_explicit
      AND v_bill_after1.last_provider_subscription_state_fingerprint
        IS NOT DISTINCT FROM v_fp_canceled_explicit
    );
  END IF;
END;
$$;

SELECT test_name, passed, sqlstate, detail
FROM test_results
ORDER BY test_name;

SELECT
  count(*) FILTER (WHERE passed) AS passed_count,
  count(*) FILTER (WHERE NOT passed) AS failed_count,
  count(*) AS total_count
FROM test_results;

ROLLBACK;
