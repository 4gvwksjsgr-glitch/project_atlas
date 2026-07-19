-- =============================================================================
-- Project Atlas — Step 9: RPC riepilogo cassa Dashboard
-- Migration additiva: non modifica migration già applicate.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_company_cash_summary(
  p_company_id UUID,
  p_month_start DATE,
  p_next_month_start DATE
)
RETURNS TABLE (
  total_income TEXT,
  total_expense TEXT,
  movement_count BIGINT,
  month_income TEXT,
  month_expense TEXT,
  month_movement_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_month_start IS NULL OR p_next_month_start IS NULL THEN
    RAISE EXCEPTION 'month bounds are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_month_start >= p_next_month_start THEN
    RAISE EXCEPTION 'month_start must be before next_month_start'
      USING ERRCODE = '22023';
  END IF;

  IF NOT private.is_company_member(p_company_id, auth.uid()) THEN
    RAISE EXCEPTION 'Not a company member'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(
      SUM(t.amount) FILTER (
        WHERE t.kind = 'income'::public.transaction_kind
      ),
      0
    )::TEXT,
    COALESCE(
      SUM(t.amount) FILTER (
        WHERE t.kind = 'expense'::public.transaction_kind
      ),
      0
    )::TEXT,
    COUNT(*)::BIGINT,
    COALESCE(
      SUM(t.amount) FILTER (
        WHERE t.kind = 'income'::public.transaction_kind
          AND t.occurred_on >= p_month_start
          AND t.occurred_on < p_next_month_start
      ),
      0
    )::TEXT,
    COALESCE(
      SUM(t.amount) FILTER (
        WHERE t.kind = 'expense'::public.transaction_kind
          AND t.occurred_on >= p_month_start
          AND t.occurred_on < p_next_month_start
      ),
      0
    )::TEXT,
    COUNT(*) FILTER (
      WHERE t.occurred_on >= p_month_start
        AND t.occurred_on < p_next_month_start
    )::BIGINT
  FROM public.transactions AS t
  WHERE t.company_id = p_company_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)
FROM anon;

REVOKE ALL
ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)
FROM authenticated;

GRANT EXECUTE
ON FUNCTION public.get_company_cash_summary(UUID, DATE, DATE)
TO authenticated;
