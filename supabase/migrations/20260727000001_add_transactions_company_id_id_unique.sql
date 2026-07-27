-- Step 13B: UNIQUE (company_id, id) on transactions for composite document FKs.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'transactions_company_id_id_unique'
      AND conrelid = 'public.transactions'::regclass
  ) THEN
    RAISE NOTICE 'transactions_company_id_id_unique already present';
  ELSIF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.transactions'::regclass
      AND contype = 'u'
      AND pg_get_constraintdef(oid) ILIKE '%(company_id, id)%'
  ) THEN
    RAISE NOTICE 'equivalent UNIQUE (company_id, id) already present on transactions';
  ELSE
    ALTER TABLE public.transactions
      ADD CONSTRAINT transactions_company_id_id_unique
      UNIQUE (company_id, id);
  END IF;
END $$;

COMMENT ON CONSTRAINT transactions_company_id_id_unique ON public.transactions IS
  'Enables composite FK from documents (company_id, transaction_id).';
