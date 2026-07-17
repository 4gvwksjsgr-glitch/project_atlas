-- =============================================================================
-- Project Atlas — Step 8: Harden privileges on public.transactions
-- Migration additiva: limita authenticated ai soli privilegi applicativi.
-- =============================================================================

REVOKE ALL ON TABLE public.transactions FROM anon;

REVOKE ALL ON TABLE public.transactions FROM authenticated;

GRANT SELECT, INSERT, UPDATE
ON TABLE public.transactions
TO authenticated;
