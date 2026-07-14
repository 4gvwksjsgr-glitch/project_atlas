-- Verifica post-migration: EXECUTE su helper RLS solo per authenticated.
-- Eseguire con: supabase db execute --linked -f supabase/tests/verify_private_function_grants.sql

SELECT
  routine_schema,
  routine_name,
  grantee,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'private'
  AND routine_name IN ('is_company_member', 'has_company_role')
  AND grantee IN ('authenticated', 'anon', 'PUBLIC')
ORDER BY routine_name, grantee;

-- Atteso: privilege_type = EXECUTE per grantee = authenticated su entrambe le funzioni.
-- Atteso: nessuna riga con grantee = anon.
