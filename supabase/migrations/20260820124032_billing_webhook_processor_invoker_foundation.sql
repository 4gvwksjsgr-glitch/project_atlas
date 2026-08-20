-- =============================================================================
-- Project Atlas — Step 14C-2G Phase B
-- Automatic webhook processor foundation (Paddle sandbox).
--
-- Phase B only:
--   - processor_enabled kill switch on private.billing_runtime_config (DEFAULT FALSE)
--   - atomic claim_next dequeue for paddle/test verified inbox events
--   - service_role public wrapper
--
-- Reuses private.claim_paddle_sandbox_webhook_event_for_processing(UUID) for
-- state transitions while holding the selected row lock (FOR UPDATE SKIP LOCKED).
--
-- NO Edge Function / scheduler / cron.
-- NO apply / fail / ingest changes.
-- NO checkout mutation.
-- Automatic path does NOT select failed events (unlike UUID claim).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Kill switch: processor_enabled (independent of checkout_enabled)
-- -----------------------------------------------------------------------------
ALTER TABLE private.billing_runtime_config
  ADD COLUMN IF NOT EXISTS processor_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN private.billing_runtime_config.processor_enabled IS
  '14C-2G: automatic inbox processor kill switch. DEFAULT FALSE. '
  'Independent of checkout_enabled. claim_next is dormant unless TRUE on the '
  'active paddle/test runtime row.';

-- Fail-closed: never leave any existing row enabled by this migration.
UPDATE private.billing_runtime_config
SET processor_enabled = FALSE
WHERE processor_enabled IS DISTINCT FROM FALSE;

-- -----------------------------------------------------------------------------
-- private.claim_next_paddle_sandbox_webhook_event_for_processing
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
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
  v_processor_enabled BOOLEAN;
  v_candidate_id UUID;
BEGIN
  -- Kill switch: active paddle/test runtime must exist and be enabled.
  SELECT c.processor_enabled
  INTO v_processor_enabled
  FROM private.billing_runtime_config c
  WHERE c.provider_code = v_provider_code
    AND c.provider_environment = v_provider_environment
    AND c.is_active IS TRUE;

  IF NOT FOUND OR v_processor_enabled IS DISTINCT FROM TRUE THEN
    outcome := 'disabled';
    inbox_event_id := NULL;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Atomic select of at most one eligible candidate.
  -- Eligibility intentionally narrower than UUID claim (no automatic failed retry).
  SELECT e.id
  INTO v_candidate_id
  FROM private.billing_provider_events e
  WHERE e.provider_code = v_provider_code
    AND e.provider_environment = v_provider_environment
    AND e.verification_status = 'verified'
    AND e.attempt_count < 5
    AND e.external_event_id !~ '^ntfsimevt_[a-z0-9]{26}$'
    AND (
      e.processing_status = 'received'
      OR (
        e.processing_status = 'processing'
        AND (
          e.last_attempt_at IS NULL
          OR e.last_attempt_at <= v_now - v_lease
        )
      )
    )
  ORDER BY
    e.provider_created_at ASC NULLS LAST,
    e.received_at ASC,
    e.id ASC
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF v_candidate_id IS NULL THEN
    outcome := 'empty';
    inbox_event_id := NULL;
    processing_status := NULL;
    attempt_count := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Reuse authoritative UUID claim transition while row lock is held.
  RETURN QUERY
  SELECT *
  FROM private.claim_paddle_sandbox_webhook_event_for_processing(v_candidate_id);
END;
$$;

COMMENT ON FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing() IS
  '14C-2G Phase B: atomic claim-next for paddle/test verified inbox. '
  'Requires active runtime processor_enabled=true. '
  'Selects received or stale processing (10-minute lease) with attempt_count < 5; '
  'excludes failed/processed/ignored/fresh processing/simulator. '
  'FOR UPDATE SKIP LOCKED; reuses UUID claim for state transition. '
  'No billing/subscription/entitlement mutations. Independent of checkout_enabled.';

ALTER FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
  FROM anon;
REVOKE ALL ON FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
  FROM authenticated;
REVOKE ALL ON FUNCTION private.claim_next_paddle_sandbox_webhook_event_for_processing()
  FROM service_role;

-- -----------------------------------------------------------------------------
-- public.claim_next_paddle_sandbox_webhook_event_for_processing_server
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
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
  FROM private.claim_next_paddle_sandbox_webhook_event_for_processing();
END;
$$;

COMMENT ON FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server() IS
  '14C-2G Phase B: service_role-only wrapper for claim_next. '
  'No extra business logic. Kill switch + eligibility enforced privately.';

ALTER FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
  FROM anon;
REVOKE ALL ON FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
  FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_paddle_sandbox_webhook_event_for_processing_server()
  TO service_role;
