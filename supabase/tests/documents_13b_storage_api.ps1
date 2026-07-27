#!/usr/bin/env powershell
# LOCAL ONLY — Storage + metadata delete integration (Step 13B).
# Uses local Supabase Auth + Storage + PostgREST. Does not touch the remote project.
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

function Remove-StorageObjects([string[]]$paths) {
  if ($paths.Count -eq 0) { return @{ StatusCode = 204; Content = '' } }
  return Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
    apikey = $ServiceKey
    Authorization = "Bearer $ServiceKey"
  } -Body ((To-PrefixesJson $paths))
}

function Remove-DocumentMetadata([string]$token, [string]$docId) {
  return Invoke-Http -Method DELETE -Url "$ApiUrl/rest/v1/documents?id=eq.$docId" -Headers @{
    apikey = $AnonKey
    Authorization = "Bearer $token"
    Prefer = 'return=minimal'
  }
}

function New-DocumentPair {
  param(
    [string]$CompanyId,
    [string]$OwnerToken,
    [string]$Title
  )
  $docId = [guid]::NewGuid().ToString()
  $objId = [guid]::NewGuid().ToString()
  $path = "$CompanyId/$docId/$objId.pdf"
  Sql @"
insert into public.documents (
  id, company_id, title, original_file_name, storage_path, mime_type, size_bytes
) values (
  '$docId', '$CompanyId', '$Title', 'test.pdf', '$path', 'application/pdf', 100
);
"@ | Out-Null
  $pdfBytes = [byte[]](0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34) + ([byte[]]::new(32))
  $upload = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/company-documents/$path" -Headers @{
    apikey = $AnonKey
    Authorization = "Bearer $OwnerToken"
    'x-upsert' = 'false'
  } -Bytes $pdfBytes -ContentType 'application/pdf'
  return @{
    DocId = $docId
    Path = $path
    UploadStatus = $upload.StatusCode
  }
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$ownerEmail = "owner13b_$suffix@example.test"
$managerEmail = "manager13b_$suffix@example.test"
$employeeEmail = "employee13b_$suffix@example.test"
$outsiderEmail = "outsider13b_$suffix@example.test"
$password = 'Password123!'

$orphanNames = (Sql "select name from storage.objects where bucket_id = 'company-documents';").Trim()
if ($orphanNames) {
  $orphanPaths = @($orphanNames -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $null = Remove-StorageObjects $orphanPaths
}

$ownerToken = New-UserToken $ownerEmail $password
$managerToken = New-UserToken $managerEmail $password
$employeeToken = New-UserToken $employeeEmail $password
$outsiderToken = New-UserToken $outsiderEmail $password

$ownerId = (Sql "select id from auth.users where email = '$ownerEmail';").Trim()
$managerId = (Sql "select id from auth.users where email = '$managerEmail';").Trim()
$employeeId = (Sql "select id from auth.users where email = '$employeeEmail';").Trim()
$outsiderId = (Sql "select id from auth.users where email = '$outsiderEmail';").Trim()

$companyA = [guid]::NewGuid().ToString()
$companyB = [guid]::NewGuid().ToString()
$pdfBytes = [byte[]](0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34) + ([byte[]]::new(32))

Sql @"
insert into public.companies (id, name, slug) values
  ('$companyA', 'Docs 13B A $suffix', 'docs-13b-a-$suffix'),
  ('$companyB', 'Docs 13B B $suffix', 'docs-13b-b-$suffix');
insert into public.company_members (company_id, user_id, role) values
  ('$companyA', '$ownerId', 'owner'),
  ('$companyA', '$managerId', 'manager'),
  ('$companyA', '$employeeId', 'employee'),
  ('$companyB', '$outsiderId', 'owner');
"@ | Out-Null

function Interpret-ClientStorageDelete([int]$Status, [string]$Body, [string]$StillCount) {
  # Specifica del client corretto post-fix:
  # 200/[] + oggetto presente = no-op (NON successo)
  # 200 con oggetto eliminato nella body + still=0 = deleted
  # 200/[] + still=0 = alreadyAbsent (idempotente)
  $trimmed = if ($null -eq $Body) { '' } else { $Body.Trim() }
  $emptyList = ($trimmed -eq '[]') -or ($trimmed -eq '')
  $hasDeletedObject = $trimmed -match '"name"'
  if ($StillCount -eq '1') {
    if ($emptyList) { return 'noop_denied' }
    return 'unexpected_still_present'
  }
  if ($StillCount -eq '0') {
    if ($hasDeletedObject) { return 'deleted' }
    if ($emptyList) { return 'already_absent' }
    return 'absent_unknown_body'
  }
  return 'unknown'
}

# 1. Manage role can delete storage object
$pairManage = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Manage delete'
$mgrDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $managerToken"
} -Body ((To-PrefixesJson @($pairManage.Path)))
$stillManage = (Sql "select count(*) from storage.objects where name = '$($pairManage.Path)';").Trim()
$mgrInterp = Interpret-ClientStorageDelete $mgrDel.StatusCode "$($mgrDel.Content)" $stillManage
Record 'api_manage_delete_storage_ok' (
  ($mgrDel.StatusCode -in 200, 204) -and ($stillManage -eq '0') -and ($mgrInterp -eq 'deleted')
) "$($mgrDel.StatusCode) still=$stillManage interp=$mgrInterp bodyLen=$($mgrDel.Content.Length)"

# 2. Employee denied storage delete (200/[] non è successo client)
$pairEmp = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Employee deny'
$empDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $employeeToken"
} -Body ((To-PrefixesJson @($pairEmp.Path)))
$stillEmp = (Sql "select count(*) from storage.objects where name = '$($pairEmp.Path)';").Trim()
$empInterp = Interpret-ClientStorageDelete $empDel.StatusCode "$($empDel.Content)" $stillEmp
Record 'api_employee_delete_storage_denied' (($stillEmp -eq '1') -and ($empInterp -eq 'noop_denied')) "$($empDel.StatusCode) still=$stillEmp interp=$empInterp"
Record 'api_employee_noop_not_client_success' ($empInterp -ne 'deleted' -and $empInterp -ne 'already_absent') "interp=$empInterp"

# 3. Other tenant denied storage delete
$pairOut = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Outsider deny'
$outDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $outsiderToken"
} -Body ((To-PrefixesJson @($pairOut.Path)))
$stillOut = (Sql "select count(*) from storage.objects where name = '$($pairOut.Path)';").Trim()
$outInterp = Interpret-ClientStorageDelete $outDel.StatusCode "$($outDel.Content)" $stillOut
Record 'api_other_tenant_delete_storage_denied' (($stillOut -eq '1') -and ($outInterp -eq 'noop_denied')) "$($outDel.StatusCode) still=$stillOut interp=$outInterp"
Record 'api_outsider_noop_not_client_success' ($outInterp -ne 'deleted' -and $outInterp -ne 'already_absent') "interp=$outInterp"

# 4. Storage already absent handled idempotently
$ghostPath = "$companyA/$([guid]::NewGuid())/$([guid]::NewGuid()).pdf"
$ghostDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($ghostPath)))
$ghostStill = (Sql "select count(*) from storage.objects where name = '$ghostPath';").Trim()
$ghostInterp = Interpret-ClientStorageDelete $ghostDel.StatusCode "$($ghostDel.Content)" $ghostStill
Record 'api_storage_delete_idempotent_absent' (
  ($ghostDel.StatusCode -in 200, 204) -and ($ghostStill -eq '0') -and ($ghostInterp -eq 'already_absent')
) "$($ghostDel.StatusCode) still=$ghostStill interp=$ghostInterp"

# 5. Storage delete fails → metadata remains
$pairPreserve = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Preserve metadata'
$badDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $employeeToken"
} -Body ((To-PrefixesJson @($pairPreserve.Path)))
$metaStill = (Sql "select count(*) from public.documents where id = '$($pairPreserve.DocId)';").Trim()
$storStill = (Sql "select count(*) from storage.objects where name = '$($pairPreserve.Path)';").Trim()
# Employee non può eliminare Storage: metadata e oggetto restano (HTTP può essere 200 no-op).
Record 'api_storage_fail_metadata_preserved' (($metaStill -eq '1') -and ($storStill -eq '1')) "meta=$metaStill stor=$storStill status=$($badDel.StatusCode)"

# 6. Full delete: storage then metadata
$pairFull = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Full delete'
$fullStorDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($pairFull.Path)))
$fullMetaDel = Remove-DocumentMetadata -token $ownerToken -docId $pairFull.DocId
$fullMetaLeft = (Sql "select count(*) from public.documents where id = '$($pairFull.DocId)';").Trim()
$fullStorLeft = (Sql "select count(*) from storage.objects where name = '$($pairFull.Path)';").Trim()
Record 'api_full_delete_storage_then_metadata' (
  ($fullStorDel.StatusCode -in 200, 204) -and
  ($fullMetaDel.StatusCode -in 200, 204) -and
  ($fullMetaLeft -eq '0') -and
  ($fullStorLeft -eq '0')
) "stor=$($fullStorDel.StatusCode) meta=$($fullMetaDel.StatusCode) left=$fullMetaLeft/$fullStorLeft"

# 7. Metadata delete fails after storage → retry completes
$pairRetry = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Retry metadata'
$retryStorDel = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($pairRetry.Path)))
$retryFail = Remove-DocumentMetadata -token $employeeToken -docId $pairRetry.DocId
$retryMetaLeft = (Sql "select count(*) from public.documents where id = '$($pairRetry.DocId)';").Trim()
$retryOk = Remove-DocumentMetadata -token $ownerToken -docId $pairRetry.DocId
$retryMetaLeft2 = (Sql "select count(*) from public.documents where id = '$($pairRetry.DocId)';").Trim()
Record 'api_metadata_delete_retry_after_storage' (
  ($retryStorDel.StatusCode -in 200, 204) -and
  ($retryFail.StatusCode -ge 400 -or $retryMetaLeft -eq '1') -and
  ($retryOk.StatusCode -in 200, 204) -and
  ($retryMetaLeft2 -eq '0')
) "fail=$($retryFail.StatusCode) retry=$($retryOk.StatusCode) left=$retryMetaLeft2"

# 8. Double delete leaves no errors/orphans
$pairDouble = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Double delete'
$doubleStor1 = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($pairDouble.Path)))
$doubleMeta1 = Remove-DocumentMetadata -token $ownerToken -docId $pairDouble.DocId
$doubleStor2 = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($pairDouble.Path)))
$doubleMeta2 = Remove-DocumentMetadata -token $ownerToken -docId $pairDouble.DocId
$doubleMetaLeft = (Sql "select count(*) from public.documents where id = '$($pairDouble.DocId)';").Trim()
$doubleStorLeft = (Sql "select count(*) from storage.objects where name = '$($pairDouble.Path)';").Trim()
Record 'api_double_delete_idempotent' (
  ($doubleStor1.StatusCode -in 200, 204) -and
  ($doubleMeta1.StatusCode -in 200, 204) -and
  ($doubleStor2.StatusCode -in 200, 204) -and
  ($doubleMeta2.StatusCode -in 200, 204) -and
  ($doubleMetaLeft -eq '0') -and
  ($doubleStorLeft -eq '0')
) "meta=$doubleMetaLeft stor=$doubleStorLeft"

# 9. Signed URL after delete not obtainable
$pairSign = New-DocumentPair -CompanyId $companyA -OwnerToken $ownerToken -Title 'Signed after delete'
$signedBefore = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$($pairSign.Path)" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
$null = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body ((To-PrefixesJson @($pairSign.Path)))
$null = Remove-DocumentMetadata -token $ownerToken -docId $pairSign.DocId
$signedAfter = Invoke-Http -Method POST -Url "$ApiUrl/storage/v1/object/sign/company-documents/$($pairSign.Path)" -Headers @{
  apikey = $AnonKey
  Authorization = "Bearer $ownerToken"
} -Body (@{ expiresIn = 300 } | ConvertTo-Json)
Record 'api_signed_url_after_delete_denied' (
  ($signedBefore.StatusCode -eq 200) -and ($signedAfter.StatusCode -ge 400)
) "before=$($signedBefore.StatusCode) after=$($signedAfter.StatusCode)"

# Cleanup remaining test artifacts (service role Storage API + SQL fallback)
$leftPaths = (Sql "select name from storage.objects where name like '$companyA/%' or name like '$companyB/%';").Trim()
if ($leftPaths) {
  $paths = @($leftPaths -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($paths.Count -gt 0) {
    $null = Remove-StorageObjects ([string[]]$paths)
    foreach ($p in $paths) {
      $null = Invoke-Http -Method DELETE -Url "$ApiUrl/storage/v1/object/company-documents" -Headers @{
        apikey = $ServiceKey
        Authorization = "Bearer $ServiceKey"
      } -Body ((To-PrefixesJson @($p)))
    }
  }
}

Sql @"
SET session_replication_role = replica;
delete from storage.objects where name like '$companyA/%' or name like '$companyB/%';
delete from public.documents where company_id in ('$companyA','$companyB');
delete from public.company_members where company_id in ('$companyA','$companyB');
delete from public.companies where id in ('$companyA','$companyB');
delete from auth.users where id in ('$ownerId','$managerId','$employeeId','$outsiderId');
SET session_replication_role = origin;
"@ | Out-Null

$residDocs = (Sql "select count(*) from public.documents where company_id in ('$companyA','$companyB');").Trim()
$residObj = (Sql "select count(*) from storage.objects where name like '$companyA/%' or name like '$companyB/%';").Trim()
$residUsers = (Sql "select count(*) from auth.users where email in ('$ownerEmail','$managerEmail','$employeeEmail','$outsiderEmail');").Trim()
Record 'api_no_orphans_at_end' (($residDocs -eq '0') -and ($residObj -eq '0') -and ($residUsers -eq '0')) "docs=$residDocs obj=$residObj users=$residUsers"

Write-Host ""
Write-Host "Storage API 13B results: passed=$passed failed=$failed total=$($passed+$failed)"
if ($failed -gt 0) { exit 1 }
exit 0
