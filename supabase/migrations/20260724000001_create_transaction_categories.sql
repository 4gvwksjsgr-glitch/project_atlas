-- =============================================================================
-- Project Atlas — Step 12A: Categorie operative (transaction_categories)
-- Migration additiva: non modifica migration già applicate.
-- Nessun collegamento a public.transactions in questo Step.
-- =============================================================================

CREATE TABLE public.transaction_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL
    REFERENCES public.companies(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  kind        public.transaction_kind NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT transaction_categories_name_not_empty
    CHECK (char_length(btrim(name)) > 0),
  CONSTRAINT transaction_categories_name_trimmed
    CHECK (name = btrim(name)),
  CONSTRAINT transaction_categories_name_max_len
    CHECK (char_length(name) <= 80),
  -- Preparazione FK composita futura (company_id, category_id, kind).
  CONSTRAINT transaction_categories_company_id_id_kind_unique
    UNIQUE (company_id, id, kind)
);

COMMENT ON TABLE public.transaction_categories IS
  'Categorie operative entrate/uscite scoped per azienda (non fiscali)';

-- Unicità case-insensitive: stesso nome (ignorando case) per azienda+kind.
CREATE UNIQUE INDEX transaction_categories_company_kind_lower_name_unique
  ON public.transaction_categories (company_id, kind, lower(name));

CREATE INDEX idx_transaction_categories_company_kind_active
  ON public.transaction_categories (company_id, kind, is_active);

CREATE TRIGGER set_transaction_categories_updated_at
  BEFORE UPDATE ON public.transaction_categories
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Immutabilità company_id e kind dopo creazione
-- -----------------------------------------------------------------------------
CREATE FUNCTION private.enforce_transaction_categories_immutable_keys()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'company_id cannot be changed'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.kind IS DISTINCT FROM OLD.kind THEN
    RAISE EXCEPTION 'kind cannot be changed'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_transaction_categories_immutable_keys()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.enforce_transaction_categories_immutable_keys()
  FROM anon;
REVOKE ALL ON FUNCTION private.enforce_transaction_categories_immutable_keys()
  FROM authenticated;

CREATE TRIGGER trg_transaction_categories_immutable_keys
  BEFORE UPDATE ON public.transaction_categories
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_transaction_categories_immutable_keys();

ALTER TABLE public.transaction_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_categories FORCE ROW LEVEL SECURITY;

-- SELECT: qualunque membro dell'azienda
CREATE POLICY "transaction_categories_select_member"
  ON public.transaction_categories
  FOR SELECT
  TO authenticated
  USING (private.is_company_member(company_id, auth.uid()));

-- INSERT: owner, admin, manager
CREATE POLICY "transaction_categories_insert_owner_admin_manager"
  ON public.transaction_categories
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
CREATE POLICY "transaction_categories_update_owner_admin_manager"
  ON public.transaction_categories
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

GRANT SELECT
ON TABLE public.transaction_categories
TO authenticated;

GRANT INSERT (
  company_id,
  name,
  kind,
  is_active
)
ON TABLE public.transaction_categories
TO authenticated;

GRANT UPDATE (name, is_active)
ON TABLE public.transaction_categories
TO authenticated;

REVOKE ALL ON public.transaction_categories FROM anon;
REVOKE DELETE ON public.transaction_categories FROM authenticated;
