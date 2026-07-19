-- Project Atlas — Step 9 fix:
-- consente alle RPC SECURITY INVOKER di risolvere gli helper autorizzativi
-- nello schema private, senza concedere CREATE o privilegi sugli oggetti.

REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;

GRANT USAGE ON SCHEMA private TO authenticated;
