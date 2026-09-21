-- =============================================================================
-- Project Atlas — Working Step 15: company member invites (schema)
-- Additive. Working roadmap number; not a formal repo roadmap assignment.
-- Invite lifecycle only; email delivery is out of scope.
-- =============================================================================

CREATE TABLE public.company_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE CASCADE,
  email_normalized TEXT NOT NULL,
  role public.company_role NOT NULL,
  invited_by UUID NOT NULL REFERENCES public.profiles (id),
  token_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ,
  accepted_by UUID REFERENCES public.profiles (id),
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES public.profiles (id),

  CONSTRAINT company_invites_email_normalized_not_empty
    CHECK (char_length(email_normalized) > 0),
  CONSTRAINT company_invites_email_normalized_format
    CHECK (email_normalized = lower(btrim(email_normalized))),
  CONSTRAINT company_invites_email_normalized_length
    CHECK (char_length(email_normalized) <= 254),
  CONSTRAINT company_invites_role_not_owner
    CHECK (role IS DISTINCT FROM 'owner'::public.company_role),
  CONSTRAINT company_invites_expires_after_created
    CHECK (expires_at > created_at),
  CONSTRAINT company_invites_token_hash_not_empty
    CHECK (char_length(token_hash) > 0),
  CONSTRAINT company_invites_accepted_pair
    CHECK (
      (accepted_at IS NULL AND accepted_by IS NULL)
      OR (accepted_at IS NOT NULL AND accepted_by IS NOT NULL)
    ),
  CONSTRAINT company_invites_revoked_pair
    CHECK (
      (revoked_at IS NULL AND revoked_by IS NULL)
      OR (revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    ),
  CONSTRAINT company_invites_not_accepted_and_revoked
    CHECK (NOT (accepted_at IS NOT NULL AND revoked_at IS NOT NULL))
);

COMMENT ON TABLE public.company_invites IS
  'Company member invitations. Raw invite tokens are never stored; only sha256 hex hashes.';

CREATE UNIQUE INDEX company_invites_token_hash_uidx
  ON public.company_invites (token_hash);

-- At most one non-terminal pending invite per company + email.
CREATE UNIQUE INDEX company_invites_pending_company_email_uidx
  ON public.company_invites (company_id, email_normalized)
  WHERE accepted_at IS NULL AND revoked_at IS NULL;

CREATE INDEX company_invites_company_id_idx
  ON public.company_invites (company_id);

CREATE INDEX company_invites_company_pending_idx
  ON public.company_invites (company_id, created_at DESC)
  WHERE accepted_at IS NULL AND revoked_at IS NULL;

ALTER TABLE public.company_invites OWNER TO postgres;
ALTER TABLE public.company_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_invites FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.company_invites FROM PUBLIC;
REVOKE ALL ON TABLE public.company_invites FROM anon;
REVOKE ALL ON TABLE public.company_invites FROM authenticated;
-- No client policies: access only via SECURITY DEFINER RPCs.
