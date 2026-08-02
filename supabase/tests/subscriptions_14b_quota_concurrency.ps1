# LOCAL DATABASE ONLY — NEVER RUN ON REMOTE
# Step 14B: real two-session concurrency for Free quota at 29/30.
# Requires Docker container supabase_db_project_atlas.

$ErrorActionPreference = 'Continue'
$DbContainer = 'supabase_db_project_atlas'

function Invoke-PsqlFile([string]$Sql, [switch]$StopOnError) {
  $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14b-' + [guid]::NewGuid().ToString('N') + '.sql'))
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tmp, $Sql, $utf8)
  try {
    $stopFlag = if ($StopOnError) { '1' } else { '0' }
    # NativeCommandError from docker NOTICE must not abort the harness.
    $out = cmd /c "type `"$tmp`" | docker exec -i $DbContainer psql -U postgres -d postgres -v ON_ERROR_STOP=$stopFlag 2>&1"
    return ($out | Out-String)
  } finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Start-PsqlJob([string]$Sql) {
  return Start-Job -ScriptBlock {
    param($Container, $SqlText)
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14b-job-' + [guid]::NewGuid().ToString('N') + '.sql'))
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

Write-Host '=== 14B quota concurrency harness ==='

$setupCommitted = @'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS private._conc_14b_harness (
  k text PRIMARY KEY,
  v text NOT NULL
);
REVOKE ALL ON TABLE private._conc_14b_harness FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_company uuid := gen_random_uuid();
  v_owner uuid := gen_random_uuid();
  v_company_b uuid := gen_random_uuid();
  v_owner_b uuid := gen_random_uuid();
  v_period timestamptz := date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (v_owner, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'conc14b-a-' || substr(v_owner::text,1,8) || '@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_owner_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'conc14b-b-' || substr(v_owner_b::text,1,8) || '@example.test', crypt('x', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  INSERT INTO public.companies (id, name, slug) VALUES
    (v_company, 'Conc14B A', 'conc14b-a-' || substr(v_company::text,1,8)),
    (v_company_b, 'Conc14B B', 'conc14b-b-' || substr(v_company_b::text,1,8));

  INSERT INTO public.company_members (company_id, user_id, role) VALUES
    (v_company, v_owner, 'owner'),
    (v_company_b, v_owner_b, 'owner');

  INSERT INTO public.company_subscriptions (company_id, plan_code, status) VALUES
    (v_company, 'free', 'free'),
    (v_company_b, 'free', 'free');

  INSERT INTO private.company_document_monthly_usage (company_id, period_start, documents_used)
  VALUES (v_company, v_period, 29), (v_company_b, v_period, 0)
  ON CONFLICT (company_id, period_start) DO UPDATE SET documents_used = EXCLUDED.documents_used;

  INSERT INTO private._conc_14b_harness(k,v) VALUES
    ('company_a', v_company::text),
    ('owner_a', v_owner::text),
    ('company_b', v_company_b::text),
    ('owner_b', v_owner_b::text),
    ('period', v_period::text)
  ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
END $$;

SELECT k || '=' || v FROM private._conc_14b_harness ORDER BY k;
'@

$metaOut = Invoke-PsqlFile $setupCommitted -StopOnError
Write-Host $metaOut
$meta = @{}
foreach ($line in ($metaOut -split "`r?`n")) {
  $t = $line.Trim()
  if ($t -match '^(company_a|owner_a|company_b|owner_b|period)=(.*)$') {
    $meta[$Matches[1]] = $Matches[2]
  }
}
if (-not $meta.ContainsKey('company_a')) { throw "Setup failed: $metaOut" }

$companyA = $meta['company_a']
$ownerA = $meta['owner_a']
$companyB = $meta['company_b']
$ownerB = $meta['owner_b']
$period = $meta['period']

function New-InsertSql([string]$CompanyId, [string]$OwnerId, [string]$Label) {
  return @"
BEGIN;
SELECT set_config('request.jwt.claim.sub', '$OwnerId', true);
SELECT set_config('request.jwt.claims', json_build_object('sub', '$OwnerId', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
DO `$`$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.documents (
    id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
  ) VALUES (
    v_id, '$CompanyId'::uuid, 'Conc $Label', 'c.pdf',
    '$CompanyId/' || v_id::text || '/' || gen_random_uuid()::text || '.pdf',
    'application/pdf', 1024
  );
  RAISE NOTICE 'SUCCESS_$Label';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'FAIL_$Label`:`%`:`%', SQLSTATE, SQLERRM;
END;
`$`$;
COMMIT;
"@
}

# Hold subscription lock so both insert sessions queue behind the same row lock.
$barrier = @"
BEGIN;
SELECT company_id FROM public.company_subscriptions WHERE company_id = '$companyA'::uuid FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;
"@

$jobBarrier = Start-PsqlJob $barrier
Start-Sleep -Milliseconds 400

$job1 = Start-PsqlJob (New-InsertSql $companyA $ownerA 'T1')
Start-Sleep -Milliseconds 200
$job2 = Start-PsqlJob (New-InsertSql $companyA $ownerA 'T2')

$outBarrier = Receive-Job $jobBarrier -Wait
$out1 = Receive-Job $job1 -Wait
$out2 = Receive-Job $job2 -Wait
Remove-Job $jobBarrier, $job1, $job2 -Force

Write-Host '--- barrier ---'
Write-Host $outBarrier
Write-Host '--- T1 ---'
Write-Host $out1
Write-Host '--- T2 ---'
Write-Host $out2

$success = 0
$failQuota = 0
foreach ($o in @($out1, $out2)) {
  if ($o -match 'SUCCESS_') { $success++ }
  if ($o -match 'ATLAS_DOCUMENT_QUOTA_EXCEEDED') { $failQuota++ }
}

$usageSql = "SELECT documents_used::text FROM private.company_document_monthly_usage WHERE company_id = '$companyA'::uuid AND period_start = '$period'::timestamptz;"
$usageTmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('atlas14b-usage-' + [guid]::NewGuid().ToString('N') + '.sql'))
[System.IO.File]::WriteAllText($usageTmp, $usageSql, (New-Object System.Text.UTF8Encoding $false))
$usageOut = cmd /c "type `"$usageTmp`" | docker exec -i $DbContainer psql -U postgres -d postgres -t -A -v ON_ERROR_STOP=1 2>&1"
Remove-Item -Force $usageTmp -ErrorAction SilentlyContinue
$usage = (($usageOut | Out-String) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
Write-Host "usage_final=$usage success=$success failQuota=$failQuota"

# Different companies should both succeed (no shared application lock)
$jobB1 = Start-PsqlJob (New-InsertSql $companyB $ownerB 'B1')
$jobB2 = Start-PsqlJob (New-InsertSql $companyB $ownerB 'B2')
$outB1 = Receive-Job $jobB1 -Wait
$outB2 = Receive-Job $jobB2 -Wait
Remove-Job $jobB1, $jobB2 -Force
$bSuccess = 0
foreach ($o in @($outB1, $outB2)) { if ($o -match 'SUCCESS_') { $bSuccess++ } }
Write-Host "company_b_parallel_success=$bSuccess"
Write-Host $outB1
Write-Host $outB2

Invoke-PsqlFile @"
DELETE FROM public.documents WHERE company_id IN ('$companyA'::uuid, '$companyB'::uuid);
DELETE FROM private.company_document_monthly_usage WHERE company_id IN ('$companyA'::uuid, '$companyB'::uuid);
DELETE FROM public.company_subscriptions WHERE company_id IN ('$companyA'::uuid, '$companyB'::uuid);
DELETE FROM public.company_members WHERE company_id IN ('$companyA'::uuid, '$companyB'::uuid);
DELETE FROM public.companies WHERE id IN ('$companyA'::uuid, '$companyB'::uuid);
DELETE FROM auth.users WHERE id IN ('$ownerA'::uuid, '$ownerB'::uuid);
DROP TABLE IF EXISTS private._conc_14b_harness;
"@ -StopOnError | Out-Null

if ($success -ne 1 -or $failQuota -ne 1 -or $usage -ne '30') {
  Write-Error "CONCURRENCY FAIL: success=$success failQuota=$failQuota usage=$usage"
  exit 1
}
if ($bSuccess -ne 2) {
  Write-Error "CROSS-COMPANY FAIL: bSuccess=$bSuccess"
  exit 1
}

Write-Host 'CONCURRENCY_PASS'
exit 0
