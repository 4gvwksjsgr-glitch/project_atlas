-- =============================================================================
-- Project Atlas — Step 1: Schema iniziale
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;

CREATE TYPE public.company_role AS ENUM (
  'owner',
  'admin',
  'manager',
  'employee'
);

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT        NOT NULL,
  full_name   TEXT,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT profiles_email_not_empty CHECK (char_length(trim(email)) > 0)
);

COMMENT ON TABLE public.profiles IS 'Profilo applicativo esteso da auth.users';

-- -----------------------------------------------------------------------------
-- companies
-- -----------------------------------------------------------------------------
CREATE TABLE public.companies (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  slug        TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT companies_name_not_empty CHECK (char_length(trim(name)) > 0),
  CONSTRAINT companies_slug_unique UNIQUE (slug),
  CONSTRAINT companies_slug_format CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

COMMENT ON TABLE public.companies IS 'Aziende (tenant) — inserimento solo via RPC create_company';

-- -----------------------------------------------------------------------------
-- company_members
-- -----------------------------------------------------------------------------
CREATE TABLE public.company_members (
  id          UUID                PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID                NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id     UUID                NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role        public.company_role NOT NULL DEFAULT 'employee',
  joined_at   TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

  CONSTRAINT company_members_unique_membership UNIQUE (company_id, user_id)
);

COMMENT ON TABLE public.company_members IS 'Membership — inserimento solo via RPC o funzioni server-side';

-- -----------------------------------------------------------------------------
-- Indici
-- -----------------------------------------------------------------------------
CREATE INDEX idx_companies_slug
  ON public.companies (slug);

CREATE INDEX idx_company_members_company_id
  ON public.company_members (company_id);

CREATE INDEX idx_company_members_user_id
  ON public.company_members (user_id);
