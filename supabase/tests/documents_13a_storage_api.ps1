#!/usr/bin/env powershell
# LOCAL ONLY — Storage API behavioral checks for company-documents (Step 13A).
# Uses local Supabase Auth + Storage REST. Does not touch the remote project.
$ErrorActionPreference = 'Stop'

$ApiUrl = 'http://127.0.0.1:54321'
$AnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
$ServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU'

$passed = 0
$failed = 0

function Record([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:passed++ } else { $script:failed++ }
  Write-Host ("{0}: {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail)
}

function Invoke-Http {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$Body = $null,
    [byte[]]$Bytes = $null,
    [string]$ContentType = 'application/json'
  )
  $hdr = @{}
  foreach ($k in $Headers.Keys) { $hdr[$k] = $Headers[$k] }
  try {
    if ($null -ne $Bytes) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $hdr -Body $Bytes -ContentType $ContentType -UseBasicParsing
    } elseif ($null -ne $Body) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $hdr -Body $Body -ContentType $ContentType -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $hdr -UseBasicParsing
    }
    return @{ StatusCode = [int]$resp.StatusCode; Content = $resp.Content }
  } catch {
    $ex = $_.Exception
    $status = 0
    $content = ''
    if ($ex.Response) {
      $status = [int]$ex.Response.StatusCode.value__
      try {
        $reader = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
        $content = $reader.ReadToEnd()
        $reader.Close()
      } catch {}
    } else {
      $content = $_.ToString()
    }
    return @{ StatusCode = $status; Content = $content }
  }
}

function New-UserToken([string]$email, [string]$password) {
  $body = @{ email = $email; password = $password } | ConvertTo-Json
  $resp = Invoke-Http -Method POST -Url "$ApiUrl/auth/v1/signup" -Headers @{
    apikey = $AnonKey
    Authorization = "Bearer $AnonKey"
  } -Body $body
  $json = $null
  try { $json = $resp.Content | ConvertFrom-Json } catch {}
  if ($json -and $json.access_token) { return $json.access_token }
  $login = Invoke-Http -Method POST -Url "$ApiUrl/auth/v1/token?grant_type=password" -Headers @{
    apikey = $AnonKey
    Authorization = "Bearer $AnonKey"
  } -Body $body
  $json = $login.Content | ConvertFrom-Json
  return $json.access_token
}

function To-PrefixesJson([string[]]$paths) {
  $escaped = @($paths | ForEach-Object {
    '"' + ($_ -replace '\\', '\\' -replace '"', '\"') + '"'
  })
  return '{"prefixes":[' + ($escaped -join ',') + ']}'
}

function Sql([string]$query) {
  $tmp = [System.IO.Path]::GetTempFileName()
  Set-Content -Path $tmp -Value $query -Encoding UTF8
  $out = Get-Content $tmp -Raw | docker exec -i supabase_db_project_atlas psql -U postgres -v ON_ERROR_STOP=1 -t -A 2>$null
  Remove-Item $tmp -Force
  if ($null -eq $out) { return '' }
  return "$out"
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$ownerEmail = "owner13a_$suffix@example.test"
$employeeEmail = "employee13a_$suffix@example.test"
$outsiderEmail = "outsider13a_$suffix@example.test"
$password = 'Password123!'

# Prefly locale: rimuove eventuali oggetti orfani di run interrotte (solo bucket company-documents).
$orphanNames = (Sql "select name from storage.objects where bucket_id = 'company-documents';").Trim()
if ($orphanNames) {
  $orphanPaths = @($orphanNames -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($orphanPath in $orphanPaths) {
    $null = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
      apikey = $ServiceKey
      Authorization = "Bearer $ServiceKey"
    } -Body ((To-PrefixesJson @($orphanPath)))
  }
}

$ownerToken = New-UserToken $ownerEmail $password
$employeeToken = New-UserToken $employeeEmail $password
$outsiderToken = New-UserToken $outsiderEmail $password

$ownerId = (Sql "select id from auth.users where email = '$ownerEmail';").Trim()
$employeeId = (Sql "select id from auth.users where email = '$employeeEmail';").Trim()
$outsiderId = (Sql "select id from auth.users where email = '$outsiderEmail';").Trim()
$companyA = [guid]::NewGuid().ToString()
$companyB = [guid]::NewGuid().ToString()
$docId = [guid]::NewGuid().ToString()
$objId = [guid]::NewGuid().ToString()
$path = "$companyA/$docId/$objId.pdf"
$pdfBytes = [byte[]](0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34) + ([byte[]]::new(32))

Sql @"
insert into public.companies (id, name, slug) values
  ('$companyA', 'Docs API A $suffix', 'docs-api-a-$suffix'),
  ('$companyB', 'Docs API B $suffix', 'docs-api-b-$suffix');
insert into public.company_members (company_id, user_id, role) values
  ('$companyA', '$ownerId', 'owner'),
  ('$companyA', '$employeeId', 'employee'),
  ('$companyB', '$outsiderId', 'owner');
"@ | Out-Null

$bucket = Invoke-Http -Method GET -Url "$ApiUrl/storage/v1/bucket/company-documents" -Headers @{
  apikey = $ServiceKey
  Authorization = "Bearer $ServiceKey"
}
if ($bucket.StatusCode -eq 0) {
  $limitRow = (Sql "select public, file_size_limit from storage.buckets where id = 'company-documents';").Trim()
  Record 'api_bucket_private' ($limitRow -match 'f\|6291456' -or $limitRow -match 'false\|6291456' -or $limitRow -eq 'f|6291456') $limitRow
} else {
  $bucketJson = $null
  try { $bucketJson = $bucket.Content | ConvertFrom-Json } catch {}
  Record 'api_bucket_private' (($bucket.StatusCode -eq 200) -and ($bucketJson.public -eq $false)) "$($bucket.StatusCode)"
}

$upload = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$path" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
  'x-upsert' = 'false'
} -Bytes $pdfBytes -ContentType 'application/pdf'
Record 'api_owner_upload_ok' ($upload.StatusCode -in 200, 201) "$($upload.StatusCode)"

$badMimePath = "$companyA/$([guid]::NewGuid())/$([guid]::NewGuid()).pdf"
$badMime = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$badMimePath" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Bytes $pdfBytes -ContentType 'application/zip'
Record 'api_mime_denied' ($badMime.StatusCode -ge 400) "$($badMime.StatusCode)"

$limit = (Sql "select file_size_limit from storage.buckets where id = 'company-documents';").Trim()
Record 'api_size_limit_configured' ($limit -eq '6291456') $limit

# Download via signed URL (member)
$signedForRead = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$path" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
$signedOk = $signedForRead.StatusCode -eq 200
Record 'api_member_read_ok' $signedOk "$($signedForRead.StatusCode)"

$signedOutEarly = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$path" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $outsiderToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
Record 'api_other_tenant_read_denied' ($signedOutEarly.StatusCode -ge 400) "$($signedOutEarly.StatusCode)"

$empPath = "$companyA/$([guid]::NewGuid())/$([guid]::NewGuid()).pdf"
$empUpload = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$empPath" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $employeeToken"
} -Bytes $pdfBytes -ContentType 'application/pdf'
Record 'api_employee_upload_denied' ($empUpload.StatusCode -ge 400) "$($empUpload.StatusCode)"

$otherPath = "$companyB/$([guid]::NewGuid())/$([guid]::NewGuid()).pdf"
$otherUpload = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$otherPath" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Bytes $pdfBytes -ContentType 'application/pdf'
Record 'api_other_company_path_denied' ($otherUpload.StatusCode -ge 400) "$($otherUpload.StatusCode)"

$malUpload = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/invalid/path" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Bytes $pdfBytes -ContentType 'application/pdf'
Record 'api_malformed_path_denied' ($malUpload.StatusCode -ge 400) "$($malUpload.StatusCode)"

$wrongBucket = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/avatars/$path" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Bytes $pdfBytes -ContentType 'application/pdf'
Record 'api_wrong_bucket_denied' ($wrongBucket.StatusCode -ge 400) "$($wrongBucket.StatusCode)"

$empDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $employeeToken"
} -Body ((To-PrefixesJson @($path)))
$empDelDenied = ($empDel.StatusCode -ge 400) -or ($empDel.Content -match '\[\s*\]')
Record 'api_employee_delete_denied' $empDelDenied "$($empDel.StatusCode) $($empDel.Content)"

$ownerDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($path)))
$stillThere = (Sql "select count(*) from storage.objects where name = '$path';").Trim()
$ownerDelOk = (($ownerDel.StatusCode -in 200, 204) -and ($stillThere -eq '0')) -or ($stillThere -eq '0')
Record 'api_owner_cleanup_delete_ok' $ownerDelOk "$($ownerDel.StatusCode) still=$stillThere $($ownerDel.Content)"

$docId2 = [guid]::NewGuid().ToString()
$objId2 = [guid]::NewGuid().ToString()
$path2 = "$companyA/$docId2/$objId2.pdf"
$null = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$path2" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Bytes $pdfBytes -ContentType 'application/pdf'

$signed = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$path2" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
Record 'api_signed_url_member_ok' ($signed.StatusCode -eq 200) "$($signed.StatusCode)"

$signedOut = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$path2" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $outsiderToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
Record 'api_signed_url_other_tenant_denied' ($signedOut.StatusCode -ge 400) "$($signedOut.StatusCode)"

$null = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $ServiceKey
  Authorization = "Bearer $ServiceKey"
} -Body ((To-PrefixesJson @($path2, "$companyA/", "$companyB/")))

# Cleanup eventuali oggetti residui del test via Storage API (service role).
$left = (Sql "select name from storage.objects where name like '$companyA/%' or name like '$companyB/%';").Trim()
if ($left) {
  $paths = @($left -split "`n" | Where-Object { $_ -and $_.Trim() })
  if ($paths.Count -gt 0) {
    $null = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
      apikey = $ServiceKey
      Authorization = "Bearer $ServiceKey"
    } -Body ((To-PrefixesJson ([string[]]$paths)))
  }
}

# Cleanup DB: disabilita temporaneamente i trigger anti last-owner, poi elimina.
Sql @"
SET session_replication_role = replica;
delete from public.documents where company_id in ('$companyA','$companyB');
delete from public.company_members where company_id in ('$companyA','$companyB');
delete from public.companies where id in ('$companyA','$companyB');
delete from auth.users where id in ('$ownerId','$employeeId','$outsiderId');
SET session_replication_role = origin;
"@ | Out-Null

$residDocs = (Sql "select count(*) from public.documents where company_id in ('$companyA','$companyB');").Trim()
$residObj = (Sql "select count(*) from storage.objects where name like '$companyA/%' or name like '$companyB/%';").Trim()
$residUsers = (Sql "select count(*) from auth.users where email in ('$ownerEmail','$employeeEmail','$outsiderEmail');").Trim()
Record 'api_no_residues' (($residDocs -eq '0') -and ($residObj -eq '0') -and ($residUsers -eq '0')) "docs=$residDocs obj=$residObj users=$residUsers"

Write-Host ""
Write-Host "Storage API results: passed=$passed failed=$failed total=$($passed+$failed)"
if ($failed -gt 0) { exit 1 }
exit 0
