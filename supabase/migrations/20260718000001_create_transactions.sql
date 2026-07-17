-- =============================================================================
-- Project Atlas — Step 8: Movimenti di cassa (transactions)
-- Migration additiva: non modifica migration già applicate.
-- PostgreSQL remoto verificato: 17.6 → ON DELETE SET NULL (client_id) supportato.
-- =============================================================================

CREATE TYPE public.transaction_kind AS ENUM ('income', 'expense');

ALTER TABLE public.clients
  ADD CONSTRAINT clients_company_id_id_unique
  UNIQUE (company_id, id);

CREATE TABLE public.transactions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID NOT NULL
    REFERENCES public.companies(id) ON DELETE CASCADE,
  client_id     UUID,
  kind          public.transaction_kind NOT NULL,
  amount        NUMERIC(14, 2) NOT NULL,
  occurred_on   DATE NOT NULL,
  description   TEXT NOT NULL,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT transactions_amount_positive
    CHECK (amount > 0),
  CONSTRAINT transactions_description_not_empty
    CHECK (char_length(trim(description)) > 0),
  CONSTRAINT transactions_client_same_company
    FOREIGN KEY (company_id, client_id)
    REFERENCES public.clients (company_id, id)
    ON DELETE SET NULL (client_id)
);

COMMENT ON TABLE public.transactions IS
  'Movimenti di cassa (entrate/uscite) scoped per azienda';

CREATE INDEX idx_transactions_company_id
  ON public.transactions (company_id);

CREATE INDEX idx_transactions_company_occurred_on
  ON public.transactions (company_id, occurred_on DESC, created_at DESC);

CREATE INDEX idx_transactions_company_client
  ON public.transactions (company_id, client_id)
  WHERE client_id IS NOT NULL;

CREATE TRIGGER set_transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Immutabilità company_id dopo creazione
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.enforce_transactions_company_id_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'company_id cannot be changed'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()
  FROM anon;
REVOKE ALL ON FUNCTION private.enforce_transactions_company_id_immutable()
  FROM authenticated;

CREATE TRIGGER trg_transactions_company_id_immutable
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_transactions_company_id_immutable();

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions FORCE ROW LEVEL SECURITY;

-- SELECT: qualunque membro dell'azienda
CREATE POLICY "transactions_select_member"
  ON public.transactions
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

-- INSERT: owner, admin, manager
CREATE POLICY "transactions_insert_owner_admin_manager"
  ON public.transactions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

-- UPDATE: owner, admin, manager
CREATE POLICY "transactions_update_owner_admin_manager"
  ON public.transactions
  FOR UPDATE
  TO authenticated
  USING (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  )
  WITH CHECK (
    private.has_company_role(
      company_id,
      ARRAY['owner', 'admin', 'manager']::public.company_role[],
      auth.uid()
    )
  );

-- Nessuna policy DELETE in questo Step.

GRANT SELECT, INSERT, UPDATE ON public.transactions TO authenticated;

REVOKE ALL ON public.transactions FROM anon;
REVOKE DELETE ON public.transactions FROM authenticated;
