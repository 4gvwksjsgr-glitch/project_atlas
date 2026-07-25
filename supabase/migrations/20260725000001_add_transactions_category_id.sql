-- =============================================================================
-- Project Atlas — Step 12B: Assegnazione categoria operativa ai movimenti
-- Migration additiva: non modifica migration già applicate.
-- Nessuna modifica a RLS o privilegi di public.transactions
-- (INSERT/UPDATE a livello tabella già coprono category_id).
-- =============================================================================

ALTER TABLE public.transactions
  ADD COLUMN category_id UUID NULL;

COMMENT ON COLUMN public.transactions.category_id IS
  'Categoria operativa opzionale; NULL = nessuna categoria';

ALTER TABLE public.transactions
  ADD CONSTRAINT transactions_category_same_company_kind
  FOREIGN KEY (company_id, category_id, kind)
  REFERENCES public.transaction_categories (company_id, id, kind)
  ON DELETE SET NULL (category_id);

CREATE INDEX idx_transactions_company_category
  ON public.transactions (company_id, category_id)
  WHERE category_id IS NOT NULL;
