-- Step 13B: allow authenticated UPDATE of document link columns.

REVOKE UPDATE ON TABLE public.documents FROM authenticated;
GRANT UPDATE (title, is_archived, client_id, transaction_id)
  ON TABLE public.documents TO authenticated;
