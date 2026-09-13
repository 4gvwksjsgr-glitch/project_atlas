# LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
# Step 14C-2J D1: real two-session NOWAIT busy harness for reconciliation apply/finalizer.
# Pattern mirrors subscriptions_14b_quota_concurrency.ps1 (Docker + Start-Job + psql).
# Requires Docker container supabase_db_project_atlas.
# Requires D1 migration applied locally. Do NOT use dblink.
# FIX2: prove busy with before/after audit snapshot equality (no fake result enums).

$ErrorActionPreference = 'Continue'
$DbContainer = 'supabase_db_project_atlas'

function Invoke-PsqlFile([string]$Sql, [switch]$StopOnError) {
  $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14c2jd1-' + [guid]::NewGuid().ToString('N') + '.sql'))
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tmp, $Sql, $utf8)
  try {
    $stopFlag = if ($StopOnError) { '1' } else { '0' }
    $out = cmd /c "type `"$tmp`" | docker exec -i $DbContainer psql -U postgres -d postgres -v ON_ERROR_STOP=$stopFlag 2>&1"
    return ($out | Out-String)
  } finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}

# Strict psql runner: always ON_ERROR_STOP=1; returns ExitCode + Output (never swallows failure).
function Invoke-PsqlStrict([string]$Sql) {
  $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14c2jd1-strict-' + [guid]::NewGuid().ToString('N') + '.sql'))
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tmp, $Sql, $utf8)
  try {
    $out = cmd /c "type `"$tmp`" | docker exec -i $DbContainer psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>&1"
    return @{
      ExitCode = [int]$LASTEXITCODE
      Output   = ($out | Out-String)
    }
  } finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Start-PsqlJob([string]$Sql) {
  return Start-Job -ScriptBlock {
    param($Container, $SqlText)
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14c2jd1-job-' + [guid]::NewGuid().ToString('N') + '.sql'))
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $SqlText, $utf8)
    try {
      $out = cmd /c "type `"$tmp`" | docker exec -i $Container psql -U postgres -d postgres -v ON_ERROR_STOP=0 2>&1"
      return ($out | Out-String)
    } finally {
      Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    }
  } -ArgumentList $DbContainer, $Sql
}

function Get-Harness([string]$Key) {
  $sql = "SELECT v FROM private._conc_d1_harness WHERE k = '$Key';"
  $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14c2jd1-h-' + [guid]::NewGuid().ToString('N') + '.sql'))
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tmp, $sql, $utf8)
  try {
    $out = cmd /c "type `"$tmp`" | docker exec -i $DbContainer psql -U postgres -d postgres -t -A -v ON_ERROR_STOP=1 2>&1"
    return (($out | Out-String) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -First 1)
  } finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}

Write-Host '=== 14C-2J D1 reconciliation NOWAIT concurrency harness (FIX2) ==='

$companyId = $null
$ownerId = $null
$conc01Result = 'PENDING'
$conc02Result = 'PENDING'
$conc03Result = 'PENDING'
$cleanupResult = 'PENDING'
$cleanupExitCode = -1
$fixtureResidue = 'UNKNOWN'
$triggerState = 'UNKNOWN'
$conc01AuditUnchanged = $false
$conc02AuditUnchanged = $false
$conc03AuditUnchanged = $false
$conc03Recorded = $null

try {
  $setupCommitted = @'
CREATE TABLE IF NOT EXISTS private._conc_d1_harness (
  k text PRIMARY KEY,
  v text NOT NULL
);
REVOKE ALL ON TABLE private._conc_d1_harness FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_company uuid := gen_random_uuid();
  v_price text;
  v_cust text := 'ctm_' || substr(md5('d1-conc-customer'), 1, 26);
  v_subid text := 'sub_' || substr(md5('d1-conc-subscription'), 1, 26);
  v_period_start timestamptz := timestamptz '2026-09-01 00:00:00+00';
  v_period_end timestamptz := timestamptz '2026-10-01 00:00:00+00';
  v_wm timestamptz := timestamptz '2026-09-13 08:00:00+00';
  v_t2 timestamptz := timestamptz '2026-09-13 10:00:00+00';
  v_fp_link text;
  v_fp_active text;
BEGIN
  SELECT p.external_price_id INTO v_price
  FROM private.billing_provider_prices p
  WHERE p.provider_code = 'paddle'
    AND p.provider_environment = 'test'
    AND p.is_active
  ORDER BY p.valid_from DESC
  LIMIT 1;
  IF v_price IS NULL THEN
    RAISE EXCEPTION 'D1 concurrency requires seeded paddle/test active price';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'conc14c2jd1-' || substr(v_owner::text,1,8) || '@example.test', crypt('x', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
  );

  INSERT INTO public.companies (id, name, slug) VALUES (
    v_company,
    'Company 14C2J D1 Conc',
    'company-14c2j-d1-conc-' || substr(v_company::text, 1, 8)
  );

  INSERT INTO public.company_members (company_id, user_id, role)
  VALUES (v_company, v_owner, 'owner');

  INSERT INTO public.company_subscriptions (
    company_id, plan_code, status, entitlement_origin
  ) VALUES (
    v_company, 'premium', 'active', 'provider'
  );

  -- Audit fields left at NULL defaults; busy must leave them unchanged.
  INSERT INTO private.company_billing (
    company_id,
    provider_code,
    provider_environment,
    external_customer_id,
    external_subscription_id,
    external_price_id,
    subscription_status,
    payment_status,
    provider_access_status,
    provider_access_ends_at,
    current_period_start,
    current_period_end,
    cancel_at_period_end,
    sync_status,
    last_sync_result,
    last_subscription_event_occurred_at,
    last_provider_subscription_updated_at,
    last_provider_subscription_state_fingerprint
  ) VALUES (
    v_company,
    'paddle',
    'test',
    v_cust,
    v_subid,
    v_price,
    'active',
    'ok',
    'entitled',
    v_period_end,
    v_period_start,
    v_period_end,
    false,
    'idle',
    'succeeded',
    v_wm,
    v_t2,
    private.billing_paddle_subscription_snapshot_fingerprint(
      v_subid, v_cust, v_price, 'active',
      v_period_start, v_period_end, false, NULL
    )
  );

  v_fp_link := private.billing_reconciliation_linkage_fingerprint(
    'paddle', 'test', v_cust, v_subid, v_price
  );
  v_fp_active := private.billing_paddle_subscription_snapshot_fingerprint(
    v_subid, v_cust, v_price, 'active',
    v_period_start, v_period_end, false, NULL
  );

  INSERT INTO private._conc_d1_harness(k,v) VALUES
    ('company', v_company::text),
    ('owner', v_owner::text),
    ('price', v_price),
    ('cust', v_cust),
    ('subid', v_subid),
    ('fp_link', v_fp_link),
    ('fp_active', v_fp_active),
    ('period_start', v_period_start::text),
    ('period_end', v_period_end::text),
    ('t2', v_t2::text),
    ('t3', (timestamptz '2026-09-13 11:00:00+00')::text),
    ('wm', v_wm::text)
  ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
END $$;

SELECT k || '=' || v FROM private._conc_d1_harness
WHERE k IN ('company','owner','price','cust','subid','fp_link','period_start','period_end','t3')
ORDER BY k;
'@

  $metaOut = Invoke-PsqlFile $setupCommitted -StopOnError
  Write-Host $metaOut
  $meta = @{}
  foreach ($line in ($metaOut -split "`r?`n")) {
    $t = $line.Trim()
    if ($t -match '^(company|owner|price|cust|subid|fp_link|period_start|period_end|t3)=(.*)$') {
      $meta[$Matches[1]] = $Matches[2]
    }
  }
  if (-not $meta.ContainsKey('company')) { throw "Setup failed: $metaOut" }

  $companyId = $meta['company']
  $ownerId = $meta['owner']
  $price = $meta['price']
  $cust = $meta['cust']
  $subid = $meta['subid']
  $fpLink = $meta['fp_link']
  $periodStart = $meta['period_start']
  $periodEnd = $meta['period_end']
  $t3 = $meta['t3']

  function Clear-ConcKeys {
    Invoke-PsqlFile "DELETE FROM private._conc_d1_harness WHERE k LIKE 'conc%';" -StopOnError | Out-Null
  }

  function Capture-AuditBaseline([string]$Phase) {
    # Store NULL-safe text tokens: empty string means SQL NULL.
    Invoke-PsqlFile @"
DO `$`$
DECLARE
  v_bill private.company_billing%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_bill
  FROM private.company_billing WHERE company_id = '$companyId'::uuid;
  INSERT INTO private._conc_d1_harness(k,v) VALUES
    ('${Phase}_last_reconciled_at', COALESCE(v_bill.last_reconciled_at::text, '')),
    ('${Phase}_last_reconciliation_result', COALESCE(v_bill.last_reconciliation_result, '')),
    ('${Phase}_last_reconciliation_error_sanitized', COALESCE(v_bill.last_reconciliation_error_sanitized, '')),
    ('${Phase}_last_reconciliation_provider_updated_at', COALESCE(v_bill.last_reconciliation_provider_updated_at::text, '')),
    ('${Phase}_updated_at', COALESCE(v_bill.updated_at::text, ''))
  ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
END;
`$`$;
"@ -StopOnError | Out-Null
  }

  function Test-AuditUnchanged([string]$Label) {
    $fields = @(
      'last_reconciled_at',
      'last_reconciliation_result',
      'last_reconciliation_error_sanitized',
      'last_reconciliation_provider_updated_at',
      'updated_at'
    )
    foreach ($f in $fields) {
      $before = Get-Harness "${Label}_before_$f"
      $after = Get-Harness "${Label}_after_$f"
      if ($before -ne $after) {
        Write-Host "AUDIT_DRIFT ${Label}.$f before=[$before] after=[$after]"
        return $false
      }
    }
    return $true
  }

  function New-ApplyBusySql([string]$Label) {
    return @"
BEGIN;
DO `$`$
DECLARE
  v_out record;
  v_bill private.company_billing%ROWTYPE;
BEGIN
  SELECT * INTO v_out
  FROM public.apply_company_billing_reconciliation_server(
    '$companyId'::uuid,
    '$ownerId'::uuid,
    '$subid',
    '$cust',
    '$fpLink',
    '$price',
    'active',
    '$periodStart'::timestamptz,
    '$periodEnd'::timestamptz,
    false,
    NULL,
    '$t3'::timestamptz
  );
  SELECT * INTO STRICT v_bill FROM private.company_billing WHERE company_id = '$companyId'::uuid;
  INSERT INTO private._conc_d1_harness(k,v) VALUES
    ('${Label}_result', COALESCE(v_out.result, '')),
    ('${Label}_after_last_reconciled_at', COALESCE(v_bill.last_reconciled_at::text, '')),
    ('${Label}_after_last_reconciliation_result', COALESCE(v_bill.last_reconciliation_result, '')),
    ('${Label}_after_last_reconciliation_error_sanitized', COALESCE(v_bill.last_reconciliation_error_sanitized, '')),
    ('${Label}_after_last_reconciliation_provider_updated_at', COALESCE(v_bill.last_reconciliation_provider_updated_at::text, '')),
    ('${Label}_after_updated_at', COALESCE(v_bill.updated_at::text, ''))
  ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
  RAISE NOTICE '${Label}_RESULT=%', v_out.result;
END;
`$`$;
COMMIT;
"@
  }

  function New-FinalizerBusySql([string]$Label) {
    return @"
BEGIN;
DO `$`$
DECLARE
  v_out record;
  v_bill private.company_billing%ROWTYPE;
BEGIN
  SELECT * INTO v_out
  FROM public.record_company_billing_reconciliation_result_server(
    '$companyId'::uuid,
    '$ownerId'::uuid,
    '$subid',
    '$cust',
    '$fpLink',
    'provider_error',
    'x',
    NULL
  );
  SELECT * INTO STRICT v_bill FROM private.company_billing WHERE company_id = '$companyId'::uuid;
  INSERT INTO private._conc_d1_harness(k,v) VALUES
    ('${Label}_result', COALESCE(v_out.result, '')),
    ('${Label}_recorded', COALESCE(v_out.recorded::text, '')),
    ('${Label}_after_last_reconciled_at', COALESCE(v_bill.last_reconciled_at::text, '')),
    ('${Label}_after_last_reconciliation_result', COALESCE(v_bill.last_reconciliation_result, '')),
    ('${Label}_after_last_reconciliation_error_sanitized', COALESCE(v_bill.last_reconciliation_error_sanitized, '')),
    ('${Label}_after_last_reconciliation_provider_updated_at', COALESCE(v_bill.last_reconciliation_provider_updated_at::text, '')),
    ('${Label}_after_updated_at', COALESCE(v_bill.updated_at::text, ''))
  ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
  RAISE NOTICE '${Label}_RESULT=% recorded=%', v_out.result, v_out.recorded;
END;
`$`$;
COMMIT;
"@
  }

  $barrierSub = @"
BEGIN;
SELECT company_id FROM public.company_subscriptions
WHERE company_id = '$companyId'::uuid FOR UPDATE;
SELECT pg_sleep(3);
COMMIT;
"@

  $barrierBill = @"
BEGIN;
SELECT company_id FROM private.company_billing
WHERE company_id = '$companyId'::uuid FOR UPDATE;
SELECT pg_sleep(3);
COMMIT;
"@

  # -------------------------------------------------------------------------
  # CONC-01: hold company_subscriptions; apply expects busy; audit unchanged
  # -------------------------------------------------------------------------
  Clear-ConcKeys
  Capture-AuditBaseline 'conc01_before'
  $jobBarrier = Start-PsqlJob $barrierSub
  Start-Sleep -Milliseconds 400
  $jobApply = Start-PsqlJob (New-ApplyBusySql 'conc01')
  $outBarrier = Receive-Job $jobBarrier -Wait
  $outApply = Receive-Job $jobApply -Wait
  Remove-Job $jobBarrier, $jobApply -Force -ErrorAction SilentlyContinue
  Write-Host '--- CONC-01 barrier ---'
  Write-Host $outBarrier
  Write-Host '--- CONC-01 apply ---'
  Write-Host $outApply
  $r1 = Get-Harness 'conc01_result'
  $conc01AuditUnchanged = Test-AuditUnchanged 'conc01'
  Write-Host "CONC01 result=$r1 audit_unchanged=$conc01AuditUnchanged"
  if ($r1 -ne 'busy' -or -not $conc01AuditUnchanged) {
    Write-Error "CONC-01 FAIL: result=$r1 audit_unchanged=$conc01AuditUnchanged"
    $conc01Result = 'FAIL'
  } else {
    Write-Host 'CONC-01 PASS'
    $conc01Result = 'PASS'
  }

  # -------------------------------------------------------------------------
  # CONC-02: hold company_billing; apply expects busy; audit unchanged
  # -------------------------------------------------------------------------
  Clear-ConcKeys
  Capture-AuditBaseline 'conc02_before'
  $jobBarrier = Start-PsqlJob $barrierBill
  Start-Sleep -Milliseconds 400
  $jobApply = Start-PsqlJob (New-ApplyBusySql 'conc02')
  $outBarrier = Receive-Job $jobBarrier -Wait
  $outApply = Receive-Job $jobApply -Wait
  Remove-Job $jobBarrier, $jobApply -Force -ErrorAction SilentlyContinue
  Write-Host '--- CONC-02 barrier ---'
  Write-Host $outBarrier
  Write-Host '--- CONC-02 apply ---'
  Write-Host $outApply
  $r2 = Get-Harness 'conc02_result'
  $conc02AuditUnchanged = Test-AuditUnchanged 'conc02'
  Write-Host "CONC02 result=$r2 audit_unchanged=$conc02AuditUnchanged"
  if ($r2 -ne 'busy' -or -not $conc02AuditUnchanged) {
    Write-Error "CONC-02 FAIL: result=$r2 audit_unchanged=$conc02AuditUnchanged"
    $conc02Result = 'FAIL'
  } else {
    Write-Host 'CONC-02 PASS'
    $conc02Result = 'PASS'
  }

  # -------------------------------------------------------------------------
  # CONC-03: hold subscriptions; finalizer busy + recorded=false; audit unchanged
  # -------------------------------------------------------------------------
  Clear-ConcKeys
  Capture-AuditBaseline 'conc03_before'
  $jobBarrier = Start-PsqlJob $barrierSub
  Start-Sleep -Milliseconds 400
  $jobFin = Start-PsqlJob (New-FinalizerBusySql 'conc03')
  $outBarrier = Receive-Job $jobBarrier -Wait
  $outFin = Receive-Job $jobFin -Wait
  Remove-Job $jobBarrier, $jobFin -Force -ErrorAction SilentlyContinue
  Write-Host '--- CONC-03 barrier ---'
  Write-Host $outBarrier
  Write-Host '--- CONC-03 finalizer ---'
  Write-Host $outFin
  $r3 = Get-Harness 'conc03_result'
  $conc03Recorded = Get-Harness 'conc03_recorded'
  $conc03AuditUnchanged = Test-AuditUnchanged 'conc03'
  Write-Host "CONC03 result=$r3 recorded=$conc03Recorded audit_unchanged=$conc03AuditUnchanged"
  if ($r3 -ne 'busy' -or $conc03Recorded -ne 'false' -or -not $conc03AuditUnchanged) {
    Write-Error "CONC-03 FAIL: result=$r3 recorded=$conc03Recorded audit_unchanged=$conc03AuditUnchanged"
    $conc03Result = 'FAIL'
  } else {
    Write-Host 'CONC-03 PASS'
    $conc03Result = 'PASS'
  }
}
finally {
  # Fail-closed LOCAL cleanup: exact fixture IDs, transactional trigger disable/enable,
  # hard post-assertions. Exit code must propagate (never Out-Null).
  if ($companyId -and $ownerId -and
      $companyId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and
      $ownerId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    $cleanupSql = @"
BEGIN;

-- A. Verify only expected fixture rows are targeted (exact IDs + fixture markers).
DO `$`$
DECLARE
  v_company uuid := '$companyId'::uuid;
  v_owner uuid := '$ownerId'::uuid;
  v_slug text;
  v_email text;
  v_member_count int;
BEGIN
  SELECT c.slug INTO v_slug
  FROM public.companies c
  WHERE c.id = v_company
    AND c.name = 'Company 14C2J D1 Conc'
    AND c.slug = 'company-14c2j-d1-conc-' || substr(c.id::text, 1, 8);
  IF v_slug IS NULL THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: company fixture mismatch or missing (%)', v_company;
  END IF;

  SELECT u.email INTO v_email
  FROM auth.users u
  WHERE u.id = v_owner
    AND u.email = 'conc14c2jd1-' || substr(u.id::text, 1, 8) || '@example.test';
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: user fixture mismatch or missing (%)', v_owner;
  END IF;

  SELECT count(*) INTO v_member_count
  FROM public.company_members m
  WHERE m.company_id = v_company;
  IF v_member_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: unexpected member count % for company %', v_member_count, v_company;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.company_members m
    WHERE m.company_id = v_company AND m.user_id = v_owner AND m.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: expected owner membership missing';
  END IF;
END;
`$`$;

-- B. Temporarily disable ONLY trg_company_members_integrity (transactional).
ALTER TABLE public.company_members DISABLE TRIGGER trg_company_members_integrity;

-- C/D. Delete exact fixture rows (no wildcards).
DELETE FROM private.company_billing
WHERE company_id = '$companyId'::uuid;

DELETE FROM public.company_subscriptions
WHERE company_id = '$companyId'::uuid;

DELETE FROM public.company_members
WHERE company_id = '$companyId'::uuid
  AND user_id = '$ownerId'::uuid;

DELETE FROM public.companies
WHERE id = '$companyId'::uuid;

DELETE FROM public.profiles
WHERE id = '$ownerId'::uuid;

DELETE FROM auth.users
WHERE id = '$ownerId'::uuid;

-- E. Drop expected harness table only.
DO `$`$
DECLARE
  v_cols int;
BEGIN
  IF to_regclass('private._conc_d1_harness') IS NOT NULL THEN
    SELECT count(*) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'private'
      AND table_name = '_conc_d1_harness';
    IF v_cols IS DISTINCT FROM 2 THEN
      RAISE EXCEPTION 'D1_CONC_CLEANUP: unexpected harness shape (cols=%)', v_cols;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'private' AND table_name = '_conc_d1_harness'
        AND column_name = 'k' AND data_type = 'text'
    ) OR NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'private' AND table_name = '_conc_d1_harness'
        AND column_name = 'v' AND data_type = 'text'
    ) THEN
      RAISE EXCEPTION 'D1_CONC_CLEANUP: harness columns are not (k text, v text)';
    END IF;
    DROP TABLE private._conc_d1_harness;
  END IF;
END;
`$`$;

-- F. Re-enable trigger inside the same transaction.
ALTER TABLE public.company_members ENABLE TRIGGER trg_company_members_integrity;

-- G/H. Hard-assert zero fixture residue + trigger O before COMMIT.
DO `$`$
DECLARE
  v_users int;
  v_companies int;
  v_members int;
  v_profiles int;
  v_subs int;
  v_billing int;
  v_tg char;
BEGIN
  SELECT count(*) INTO v_users
  FROM auth.users u
  WHERE u.email LIKE 'conc14c2jd1-%@example.test'
     OR u.id = '$ownerId'::uuid;

  SELECT count(*) INTO v_companies
  FROM public.companies c
  WHERE c.id = '$companyId'::uuid
     OR c.name = 'Company 14C2J D1 Conc'
     OR c.slug LIKE 'company-14c2j-d1-conc-%';

  SELECT count(*) INTO v_members
  FROM public.company_members m
  WHERE m.company_id = '$companyId'::uuid
     OR m.user_id = '$ownerId'::uuid;

  SELECT count(*) INTO v_profiles
  FROM public.profiles p
  WHERE p.id = '$ownerId'::uuid;

  SELECT count(*) INTO v_subs
  FROM public.company_subscriptions s
  WHERE s.company_id = '$companyId'::uuid;

  SELECT count(*) INTO v_billing
  FROM private.company_billing b
  WHERE b.company_id = '$companyId'::uuid;

  IF v_users <> 0 OR v_companies <> 0 OR v_members <> 0 OR v_profiles <> 0
     OR v_subs <> 0 OR v_billing <> 0 THEN
    RAISE EXCEPTION
      'D1_CONC_CLEANUP: fixture residue users=% companies=% members=% profiles=% subs=% billing=%',
      v_users, v_companies, v_members, v_profiles, v_subs, v_billing;
  END IF;

  IF to_regclass('private._conc_d1_harness') IS NOT NULL THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: private._conc_d1_harness still present';
  END IF;

  SELECT t.tgenabled INTO v_tg
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE t.tgname = 'trg_company_members_integrity'
    AND n.nspname = 'public'
    AND c.relname = 'company_members';
  IF v_tg IS DISTINCT FROM 'O' THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: trigger state=% expected O', v_tg;
  END IF;

  RAISE NOTICE 'D1_CONC_CLEANUP_OK residue=0 trigger=%', v_tg;
END;
`$`$;

COMMIT;
"@
    Write-Host '--- CLEANUP (transactional) ---'
    $cleanupRun = Invoke-PsqlStrict $cleanupSql
    $cleanupExitCode = $cleanupRun.ExitCode
    Write-Host $cleanupRun.Output
    if ($cleanupExitCode -eq 0) {
      $cleanupResult = 'PASS'
      $fixtureResidue = '0'
      $triggerState = 'O'
    } else {
      $cleanupResult = 'FAIL'
      Write-Error "D1_CONC_CLEANUP_FAIL exit=$cleanupExitCode"
    }
  } else {
    # Setup never yielded valid IDs: still attempt harness drop fail-closed.
    Write-Host '--- CLEANUP (harness-only; no fixture IDs) ---'
    $cleanupRun = Invoke-PsqlStrict @"
BEGIN;
DO `$`$
DECLARE
  v_cols int;
  v_tg char;
BEGIN
  IF to_regclass('private._conc_d1_harness') IS NOT NULL THEN
    SELECT count(*) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'private' AND table_name = '_conc_d1_harness';
    IF v_cols IS DISTINCT FROM 2 THEN
      RAISE EXCEPTION 'D1_CONC_CLEANUP: unexpected harness shape (cols=%)', v_cols;
    END IF;
    DROP TABLE private._conc_d1_harness;
  END IF;

  SELECT t.tgenabled INTO v_tg
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE t.tgname = 'trg_company_members_integrity'
    AND n.nspname = 'public'
    AND c.relname = 'company_members';
  IF v_tg IS DISTINCT FROM 'O' THEN
    RAISE EXCEPTION 'D1_CONC_CLEANUP: trigger state=% expected O', v_tg;
  END IF;
END;
`$`$;
COMMIT;
"@
    $cleanupExitCode = $cleanupRun.ExitCode
    Write-Host $cleanupRun.Output
    if ($cleanupExitCode -eq 0) {
      $cleanupResult = 'PASS'
      $fixtureResidue = '0'
      $triggerState = 'O'
    } else {
      $cleanupResult = 'FAIL'
      Write-Error "D1_CONC_CLEANUP_FAIL exit=$cleanupExitCode"
    }
  }
}

$testsPassed = (
  $conc01Result -eq 'PASS' -and
  $conc02Result -eq 'PASS' -and
  $conc03Result -eq 'PASS'
)
$overallPass = ($testsPassed -and $cleanupResult -eq 'PASS')

Write-Host "CONC01_RESULT=$conc01Result"
Write-Host "CONC02_RESULT=$conc02Result"
Write-Host "CONC03_RESULT=$conc03Result"
Write-Host "CLEANUP_RESULT=$cleanupResult"
Write-Host "CLEANUP_EXIT_CODE=$cleanupExitCode"
Write-Host "FIXTURE_RESIDUE=$fixtureResidue"
Write-Host "TRIGGER_STATE=$triggerState"

if ($overallPass) {
  Write-Host 'CONCURRENCY_TEST_RESULT=PASS'
  Write-Host 'D1_CONCURRENCY_PASS'
  exit 0
}

Write-Host 'CONCURRENCY_TEST_RESULT=FAIL'
if (-not $testsPassed) {
  Write-Error "D1_CONCURRENCY_TEST_FAIL CONC01=$conc01Result CONC02=$conc02Result CONC03=$conc03Result"
}
if ($cleanupResult -ne 'PASS') {
  Write-Error "D1_CONCURRENCY_CLEANUP_FAIL CLEANUP=$cleanupResult EXIT=$cleanupExitCode"
}
Write-Error 'D1_CONCURRENCY_FAIL'
exit 1
