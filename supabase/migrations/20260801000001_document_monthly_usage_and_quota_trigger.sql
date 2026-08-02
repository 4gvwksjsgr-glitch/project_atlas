-- =============================================================================
-- Project Atlas — Step 14B: monthly document usage + quota enforcement
-- Additive. Does not modify historical migrations.
--
-- Quota measures committed metadata inserts per UTC calendar month, not live
-- document row counts. Archive/hard-delete never decrement usage.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- private.company_document_monthly_usage
-- -----------------------------------------------------------------------------
CREATE TABLE private.company_document_monthly_usage (
  company_id UUID NOT NULL
    REFERENCES public.companies (id) ON DELETE CASCADE,
  period_start TIMESTAMPTZ NOT NULL,
  documents_used BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT company_document_monthly_usage_pkey
    PRIMARY KEY (company_id, period_start),
  CONSTRAINT company_document_monthly_usage_documents_used_non_negative
    CHECK (documents_used >= 0)
);

COMMENT ON TABLE private.company_document_monthly_usage IS
  'Step 14B: contatore mensile documenti per company. Non esposto ai client.';
COMMENT ON COLUMN private.company_document_monthly_usage.period_start IS
  'Inizio mese solare UTC (date_trunc month).';
COMMENT ON COLUMN private.company_document_monthly_usage.documents_used IS
  'Upload con metadata commitati nel mese. Mai decrementato su archive/delete.';

CREATE TRIGGER set_company_document_monthly_usage_updated_at
  BEFORE UPDATE ON private.company_document_monthly_usage
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

REVOKE ALL ON TABLE private.company_document_monthly_usage FROM PUBLIC;
REVOKE ALL ON TABLE private.company_document_monthly_usage FROM anon;
REVOKE ALL ON TABLE private.company_document_monthly_usage FROM authenticated;

-- -----------------------------------------------------------------------------
-- Consume one monthly slot (or reject). SECURITY DEFINER; not client-callable.
-- Lock order (always): 1) company_subscriptions 2) usage row — avoids deadlocks.
-- -----------------------------------------------------------------------------
CREATE FUNCTION private.consume_company_document_monthly_usage(
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_period_start TIMESTAMPTZ;
  v_sub public.company_subscriptions%ROWTYPE;
  v_effective_code TEXT;
  v_limit INTEGER;
  v_used BIGINT;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_COMPANY_ID_REQUIRED';
  END IF;

  -- Period from server clock only; never NEW.created_at / client timestamps.
  v_period_start :=
    date_trunc('month', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  -- Lock 1: per-company subscription (serializes quota decisions for one tenant).
  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_SUBSCRIPTION_NOT_FOUND';
  END IF;

  -- Effective plan semantics identical to 14A overview.
  IF v_sub.status = 'trialing'
    AND v_sub.trial_ends_at IS NOT NULL
    AND v_sub.trial_ends_at > v_now THEN
    v_effective_code := 'premium';
  ELSIF v_sub.status = 'active' AND v_sub.plan_code = 'premium' THEN
    v_effective_code := 'premium';
  ELSE
    -- free, expired trial, or inconsistent states → effective Free
    v_effective_code := 'free';
  END IF;

  SELECT p.document_monthly_limit
  INTO v_limit
  FROM public.plans p
  WHERE p.code = v_effective_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_PLAN_NOT_FOUND';
  END IF;

  INSERT INTO private.company_document_monthly_usage (
    company_id,
    period_start,
    documents_used
  )
  VALUES (p_company_id, v_period_start, 0)
  ON CONFLICT (company_id, period_start) DO NOTHING;

  -- Lock 2: usage row for this company+month (after subscription lock).
  SELECT u.documents_used
  INTO v_used
  FROM private.company_document_monthly_usage u
  WHERE u.company_id = p_company_id
    AND u.period_start = v_period_start
  FOR UPDATE;

  -- Enforce only when limited; always increment (including Premium/trial).
  IF v_limit IS NOT NULL AND v_used >= v_limit THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'ATLAS_DOCUMENT_QUOTA_EXCEEDED',
      DETAIL = format(
        'company=%s period_start=%s used=%s limit=%s',
        p_company_id,
        v_period_start,
        v_used,
        v_limit
      );
  END IF;

  UPDATE private.company_document_monthly_usage u
  SET
    documents_used = u.documents_used + 1,
    updated_at = v_now
  WHERE u.company_id = p_company_id
    AND u.period_start = v_period_start;
END;
$$;

COMMENT ON FUNCTION private.consume_company_document_monthly_usage(UUID) IS
  'Step 14B: lock subscription then usage; enforce Free limit; always +1. '
  'Rollback of outer documents insert undoes the increment.';

ALTER FUNCTION private.consume_company_document_monthly_usage(UUID)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM anon;
REVOKE ALL ON FUNCTION private.consume_company_document_monthly_usage(UUID)
  FROM authenticated;

-- -----------------------------------------------------------------------------
-- BEFORE INSERT trigger on public.documents
-- -----------------------------------------------------------------------------
CREATE FUNCTION private.trg_documents_consume_monthly_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.consume_company_document_monthly_usage(NEW.company_id);
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION private.trg_documents_consume_monthly_usage() IS
  'Step 14B: BEFORE INSERT documents → consume monthly usage.';

ALTER FUNCTION private.trg_documents_consume_monthly_usage()
  OWNER TO postgres;

REVOKE ALL ON FUNCTION private.trg_documents_consume_monthly_usage()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.trg_documents_consume_monthly_usage()
  FROM anon;
REVOKE ALL ON FUNCTION private.trg_documents_consume_monthly_usage()
  FROM authenticated;

CREATE TRIGGER trg_documents_consume_monthly_usage
  BEFORE INSERT ON public.documents
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_documents_consume_monthly_usage();
