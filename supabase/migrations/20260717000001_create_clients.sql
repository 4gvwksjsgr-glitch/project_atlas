-- =============================================================================
-- Project Atlas — Step 7: Anagrafica clienti (clients)
-- Migration additiva: non modifica migration già applicate.
-- =============================================================================

CREATE TABLE public.clients (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name        TEXT        NOT NULL,
  email       TEXT,
  phone       TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT clients_name_not_empty CHECK (char_length(trim(name)) > 0)
);

COMMENT ON TABLE public.clients IS 'Clienti (anagrafica) scoped per azienda';

CREATE INDEX idx_clients_company_id
  ON public.clients (company_id);

CREATE INDEX idx_clients_company_name
  ON public.clients (company_id, name);

CREATE TRIGGER set_clients_updated_at
  BEFORE UPDATE ON public.clients
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients FORCE ROW LEVEL SECURITY;

-- SELECT: qualunque membro dell'azienda
CREATE POLICY "clients_select_member"
  ON public.clients
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

-- INSERT: owner, admin, manager
CREATE POLICY "clients_insert_owner_admin_manager"
  ON public.clients
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
CREATE POLICY "clients_update_owner_admin_manager"
  ON public.clients
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

GRANT SELECT, INSERT, UPDATE ON public.clients TO authenticated;

REVOKE ALL ON public.clients FROM anon;
REVOKE DELETE ON public.clients FROM authenticated;
