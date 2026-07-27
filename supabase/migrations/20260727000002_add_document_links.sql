-- Step 13B: optional document links to client and transaction (same-tenant FKs).

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS client_id UUID NULL,
  ADD COLUMN IF NOT EXISTS transaction_id UUID NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'documents_company_client_fkey'
      AND conrelid = 'public.documents'::regclass
  ) THEN
    ALTER TABLE public.documents
      ADD CONSTRAINT documents_company_client_fkey
      FOREIGN KEY (company_id, client_id)
      REFERENCES public.clients (company_id, id)
      ON DELETE SET NULL (client_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'documents_company_transaction_fkey'
      AND conrelid = 'public.documents'::regclass
  ) THEN
    ALTER TABLE public.documents
      ADD CONSTRAINT documents_company_transaction_fkey
      FOREIGN KEY (company_id, transaction_id)
      REFERENCES public.transactions (company_id, id)
      ON DELETE SET NULL (transaction_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS documents_company_client_id_idx
  ON public.documents (company_id, client_id)
  WHERE client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS documents_company_transaction_id_idx
  ON public.documents (company_id, transaction_id)
  WHERE transaction_id IS NOT NULL;

COMMENT ON COLUMN public.documents.client_id IS
  'Optional same-tenant client link. NULL when unlinked. Cleared via ON DELETE SET NULL (client_id).';
COMMENT ON COLUMN public.documents.transaction_id IS
  'Optional same-tenant transaction link. NULL when unlinked. Cleared via ON DELETE SET NULL (transaction_id).';
