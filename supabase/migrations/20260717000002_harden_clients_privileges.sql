-- =============================================================================
-- Project Atlas — Step 7: Harden privileges on public.clients
-- Migration additiva: limita authenticated ai soli privilegi applicativi.
-- =============================================================================

REVOKE ALL ON TABLE public.clients FROM anon;

REVOKE ALL ON TABLE public.clients FROM authenticated;

GRANT SELECT, INSERT, UPDATE
ON TABLE public.clients
TO authenticated;
