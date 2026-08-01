-- =============================================================================
-- Project Atlas — Step 14A: plans + company_subscriptions foundation
-- Additive migration. No historical migrations are modified.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- public.plans
-- -----------------------------------------------------------------------------
CREATE TABLE public.plans (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  document_monthly_limit INTEGER NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT plans_code_trimmed
    CHECK (code = btrim(code)),
  CONSTRAINT plans_code_not_empty
    CHECK (char_length(btrim(code)) > 0),
  CONSTRAINT plans_code_lowercase
    CHECK (code = lower(code)),
  CONSTRAINT plans_name_trimmed
    CHECK (name = btrim(name)),
  CONSTRAINT plans_name_not_empty
    CHECK (char_length(btrim(name)) > 0),
  CONSTRAINT plans_document_monthly_limit_non_negative
    CHECK (
      document_monthly_limit IS NULL
      OR document_monthly_limit >= 0
    )
);

COMMENT ON TABLE public.plans IS
  'Catalogo piani abbonamento. document_monthly_limit NULL = illimitato.';
COMMENT ON COLUMN public.plans.document_monthly_limit IS
  'Limite documenti mensili. NULL = illimitato (Premium).';

CREATE TRIGGER set_plans_updated_at
  BEFORE UPDATE ON public.plans
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.plans (code, name, document_monthly_limit, is_active)
VALUES
  ('free', 'Free', 30, TRUE),
  ('premium', 'Premium', NULL, TRUE)
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- public.company_subscriptions
-- -----------------------------------------------------------------------------
CREATE TABLE public.company_subscriptions (
  company_id UUID PRIMARY KEY
    REFERENCES public.companies (id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL
    REFERENCES public.plans (code) ON DELETE RESTRICT,
  status TEXT NOT NULL,
  trial_started_at TIMESTAMPTZ NULL,
  trial_ends_at TIMESTAMPTZ NULL,
  trial_used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT company_subscriptions_status_allowed
    CHECK (status IN ('free', 'trialing', 'active')),
  CONSTRAINT company_subscriptions_status_shape
    CHECK (
      (
        status = 'free'
        AND plan_code = 'free'
        AND trial_started_at IS NULL
        AND trial_ends_at IS NULL
      )
      OR (
        status = 'trialing'
        AND plan_code = 'premium'
        AND trial_started_at IS NOT NULL
        AND trial_ends_at IS NOT NULL
        AND trial_used_at IS NOT NULL
        AND trial_ends_at > trial_started_at
      )
      OR (
        status = 'active'
        AND plan_code = 'premium'
      )
    )
);

COMMENT ON TABLE public.company_subscriptions IS
  'Abbonamento per company (1:1). Mutazioni solo via RPC server-side.';
COMMENT ON COLUMN public.company_subscriptions.trial_used_at IS
  'Valorizzato dopo attivazione trial; può restare su status free post-scadenza.';

CREATE TRIGGER set_company_subscriptions_updated_at
  BEFORE UPDATE ON public.company_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_company_subscriptions_plan_code
  ON public.company_subscriptions (plan_code);

CREATE INDEX idx_company_subscriptions_status
  ON public.company_subscriptions (status);

-- Backfill Free for existing companies (idempotent).
INSERT INTO public.company_subscriptions (
  company_id,
  plan_code,
  status,
  trial_started_at,
  trial_ends_at,
  trial_used_at
)
SELECT
  c.id,
  'free',
  'free',
  NULL,
  NULL,
  NULL
FROM public.companies c
ON CONFLICT (company_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans FORCE ROW LEVEL SECURITY;

ALTER TABLE public.company_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_subscriptions FORCE ROW LEVEL SECURITY;

CREATE POLICY plans_select_active_authenticated
  ON public.plans
  FOR SELECT
  TO authenticated
  USING (is_active = TRUE);

CREATE POLICY company_subscriptions_select_member
  ON public.company_subscriptions
  FOR SELECT
  TO authenticated
  USING (
    private.is_company_member(company_id, auth.uid())
  );

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.plans FROM PUBLIC;
REVOKE ALL ON TABLE public.plans FROM anon;
REVOKE ALL ON TABLE public.plans FROM authenticated;
GRANT SELECT ON TABLE public.plans TO authenticated;

REVOKE ALL ON TABLE public.company_subscriptions FROM PUBLIC;
REVOKE ALL ON TABLE public.company_subscriptions FROM anon;
REVOKE ALL ON TABLE public.company_subscriptions FROM authenticated;
GRANT SELECT ON TABLE public.company_subscriptions TO authenticated;

-- -----------------------------------------------------------------------------
-- Effective plan overview (SECURITY INVOKER + membership check, like cash summary)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_company_subscription_overview(
  p_company_id UUID
)
RETURNS TABLE (
  company_id UUID,
  configured_plan_code TEXT,
  configured_plan_name TEXT,
  subscription_status TEXT,
  effective_plan_code TEXT,
  effective_plan_name TEXT,
  document_monthly_limit INTEGER,
  trial_started_at TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  trial_used_at TIMESTAMPTZ,
  is_trial_active BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_sub public.company_subscriptions%ROWTYPE;
  v_configured public.plans%ROWTYPE;
  v_effective_code TEXT;
  v_effective_name TEXT;
  v_effective_limit INTEGER;
  v_trial_active BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'company_id is required'
      USING ERRCODE = '22023';
  END IF;

  IF NOT private.is_company_member(p_company_id, auth.uid()) THEN
    RAISE EXCEPTION 'Not a company member'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_sub
  FROM public.company_subscriptions cs
  WHERE cs.company_id = p_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Subscription not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO v_configured
  FROM public.plans p
  WHERE p.code = v_sub.plan_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plan not found'
      USING ERRCODE = 'P0002';
  END IF;

  v_trial_active := FALSE;

  IF v_sub.status = 'trialing'
    AND v_sub.trial_ends_at IS NOT NULL
    AND v_sub.trial_ends_at > v_now THEN
    v_effective_code := 'premium';
    v_trial_active := TRUE;
  ELSIF v_sub.status = 'active' AND v_sub.plan_code = 'premium' THEN
    v_effective_code := 'premium';
  ELSE
    -- free, trialing scaduto, o stati incoerenti: effective Free
    v_effective_code := 'free';
  END IF;

  SELECT p.name, p.document_monthly_limit
  INTO v_effective_name, v_effective_limit
  FROM public.plans p
  WHERE p.code = v_effective_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plan not found'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT
    v_sub.company_id,
    v_sub.plan_code,
    v_configured.name,
    v_sub.status,
    v_effective_code,
    v_effective_name,
    v_effective_limit,
    v_sub.trial_started_at,
    v_sub.trial_ends_at,
    v_sub.trial_used_at,
    v_trial_active;
END;
$$;

COMMENT ON FUNCTION public.get_company_subscription_overview(UUID) IS
  'Overview piano effettivo per member. Read-only; timestamp server-side.';

REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_company_subscription_overview(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_company_subscription_overview(UUID)
  TO authenticated;
