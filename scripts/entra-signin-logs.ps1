

# Entra ID Sign-in Log Analyzer (POC)
# Phase 0/1: App-only auth, no LLM yet

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load .env file safely ---
$envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if (-not (Test-Path $envPath)) {
  throw "Missing .env file at $envPath"
}

Get-Content $envPath | ForEach-Object {
  if ($_ -match '^\s*#') { return }
  if ($_ -match '^\s*$') { return }
  $k, $v = $_ -split '=', 2
  if (-not $k -or -not $v) { return }
  $k = $k.Trim()
  $v = $v.Trim().Trim('"')
  [Environment]::SetEnvironmentVariable($k, $v)
}

$TenantId = $env:AZURE_TENANT_ID
$ClientId = $env:AZURE_CLIENT_ID
$ClientSecret = $env:AZURE_CLIENT_SECRET

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
  throw 'Required AZURE_* variables not found after loading .env'
}

# --- Get Graph access token (client credentials) ---
$tokenBody = @{
  client_id     = $ClientId
  client_secret = $ClientSecret
  scope         = 'https://graph.microsoft.com/.default'
  grant_type    = 'client_credentials'
}


$tokenParams = @{
  Method      = 'Post'
  Uri         = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
  ContentType = 'application/x-www-form-urlencoded'
  Body        = $tokenBody
}

$tokenResponse = Invoke-RestMethod @tokenParams

$AccessToken = $tokenResponse.access_token
if (-not $AccessToken) {
  throw 'Failed to obtain access token'
}

Write-Host "Token acquired successfully" -ForegroundColor Green

# --- Time window: last 60 minutes ---
$EndTime = (Get-Date).ToUniversalTime()
$StartTime = $EndTime.AddMinutes(-60)

$StartIso = $StartTime.ToString('o')
$EndIso   = $EndTime.ToString('o')

# --- Query sign-in logs ---
$filter = "createdDateTime ge $StartIso and createdDateTime lt $EndIso"
$encodedFilter = [uri]::EscapeDataString($filter)

$uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$encodedFilter"

$headers = @{ Authorization = "Bearer $AccessToken" }

$results = @()

while ($uri) {
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers

  if ($response.value) {
    $results += $response.value
  }

  $nextLinkProp = $response.PSObject.Properties['@odata.nextLink']
  $uri = if ($null -ne $nextLinkProp) { [string]$nextLinkProp.Value } else { $null }
}

# Normalize results to an array (PowerShell can treat single objects differently)
$results = @($results)

Write-Host "Retrieved $($results.Count) sign-in records" -ForegroundColor Cyan

# --- Basic preprocessing summary ---
$summary = [ordered]@{
  window = @{ start = $StartIso; end = $EndIso; timezone = 'UTC' }
  totals = @{ total = ($results | Measure-Object).Count }
  success = (($results | Where-Object { $_.status.errorCode -eq 0 } | Measure-Object).Count)
  failure = (($results | Where-Object { $_.status.errorCode -ne 0 } | Measure-Object).Count)
}

# --- Aggregations + heuristics (LLM-safe input for later phases) ---

function Get-TopCounts {
  param(
    [Parameter(Mandatory)] [object[]]$Events,
    [Parameter(Mandatory)] [scriptblock]$KeySelector,
    [int]$Top = 10,
    [string]$KeyName = 'key'
  )

  $Events |
    Group-Object $KeySelector |
    Sort-Object Count -Descending |
    Select-Object -First $Top |
    ForEach-Object {
      [pscustomobject]@{
        $KeyName = [string]$_.Name
        count    = [int]$_.Count
      }
    }
}

function Get-NullableString([object]$v) {
  if ($null -eq $v) { return $null }
  $s = [string]$v
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  return $s
}

$allCount = ($results | Measure-Object).Count
$successCount = (($results | Where-Object { $_.status.errorCode -eq 0 } | Measure-Object).Count)
$failureCount = (($results | Where-Object { $_.status.errorCode -ne 0 } | Measure-Object).Count)

# Common dimensions
$topUsers = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.userPrincipalName } -Top 20 -KeyName 'upn'
$topIps   = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.ipAddress } -Top 20 -KeyName 'ip'
$topApps  = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.appDisplayName } -Top 15 -KeyName 'app'
$topClientApps = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.clientAppUsed } -Top 10 -KeyName 'clientApp'
$topCountries  = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.location.countryOrRegion } -Top 10 -KeyName 'country'

# Failure-focused dimensions
$failureEvents = @($results | Where-Object { $_.status.errorCode -ne 0 })
$topErrorCodes = Get-TopCounts -Events $failureEvents -KeySelector { [string]$_.status.errorCode } -Top 10 -KeyName 'errorCode'
$topFailureReasons = Get-TopCounts -Events $failureEvents -KeySelector { Get-NullableString $_.status.failureReason } -Top 10 -KeyName 'failureReason'

# Conditional access + risk
$topConditionalAccess = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.conditionalAccessStatus } -Top 10 -KeyName 'status'
$topRiskLevel = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.riskLevelAggregated } -Top 10 -KeyName 'riskLevel'
$topRiskState = Get-TopCounts -Events $results -KeySelector { Get-NullableString $_.riskState } -Top 10 -KeyName 'riskState'

# --- Heuristics ---

# Spray candidate: failed sign-ins from the same IP across many distinct users
$sprayCandidates = $failureEvents |
  Where-Object { $_.ipAddress } |
  Group-Object { $_.ipAddress } |
  ForEach-Object {
    $distinctUsers = @($_.Group.userPrincipalName | Where-Object { $_ } | Select-Object -Unique)
    [pscustomobject]@{
      ip          = [string]$_.Name
      failures    = [int]$_.Count
      uniqueUsers = [int]$distinctUsers.Count
    }
  } |
  Sort-Object uniqueUsers -Descending |
  Select-Object -First 10

# Noisy users: repeated failures
$noisyUsers = $failureEvents |
  Where-Object { $_.userPrincipalName } |
  Group-Object { $_.userPrincipalName } |
  Sort-Object Count -Descending |
  Select-Object -First 10 |
  ForEach-Object {
    [pscustomobject]@{ upn = [string]$_.Name; failures = [int]$_.Count }
  }

# --- Samples (bounded) ---

# Representative samples from the top error codes (or top apps if no failures)
$samples = @()

if (($failureEvents | Measure-Object).Count -gt 0) {
  $topErr = $failureEvents | Group-Object { $_.status.errorCode } | Sort-Object Count -Descending | Select-Object -First 5
  foreach ($g in $topErr) {
    foreach ($e in ($g.Group | Select-Object -First 2)) {
      $samples += [pscustomobject]@{
        createdDateTime = $e.createdDateTime
        userPrincipalName = $e.userPrincipalName
        appDisplayName = $e.appDisplayName
        ipAddress = $e.ipAddress
        clientAppUsed = $e.clientAppUsed
        country = $e.location.countryOrRegion
        conditionalAccessStatus = $e.conditionalAccessStatus
        riskLevelAggregated = $e.riskLevelAggregated
        riskState = $e.riskState
        errorCode = $e.status.errorCode
        failureReason = $e.status.failureReason
      }
    }
  }
} else {
  $topAppGroups = $results | Group-Object { $_.appDisplayName } | Sort-Object Count -Descending | Select-Object -First 5
  foreach ($g in $topAppGroups) {
    foreach ($e in ($g.Group | Select-Object -First 2)) {
      $samples += [pscustomobject]@{
        createdDateTime = $e.createdDateTime
        userPrincipalName = $e.userPrincipalName
        appDisplayName = $e.appDisplayName
        ipAddress = $e.ipAddress
        clientAppUsed = $e.clientAppUsed
        country = $e.location.countryOrRegion
        conditionalAccessStatus = $e.conditionalAccessStatus
        riskLevelAggregated = $e.riskLevelAggregated
        riskState = $e.riskState
        errorCode = $e.status.errorCode
        failureReason = $e.status.failureReason
      }
    }
  }
}

$samples = @($samples | Select-Object -First 30)

$analysisInput = [ordered]@{
  window = @{ start = $StartIso; end = $EndIso; timezone = 'UTC' }
  totals = @{ total = $allCount; success = $successCount; failure = $failureCount }
  top = [ordered]@{
    users = $topUsers
    ips = $topIps
    apps = $topApps
    clientApps = $topClientApps
    countries = $topCountries
    errorCodes = $topErrorCodes
    failureReasons = $topFailureReasons
    conditionalAccess = $topConditionalAccess
    riskLevelAggregated = $topRiskLevel
    riskState = $topRiskState
  }
  heuristics = [ordered]@{
    sprayCandidates = $sprayCandidates
    noisyUsers = $noisyUsers
  }
  samples = $samples
}

# --- Output raw + summary (POC) ---
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'reports/entra-signins'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$ts = Get-Date -Format 'yyyyMMdd_HHmmZ'

$results | ConvertTo-Json -Depth 10 | Out-File (Join-Path $outDir "raw_$ts.json")
$summary | ConvertTo-Json -Depth 5  | Out-File (Join-Path $outDir "summary_$ts.json")
$analysisInput | ConvertTo-Json -Depth 10 | Out-File (Join-Path $outDir "analysis_input_$ts.json")

Write-Host "POC artifacts written to $outDir" -ForegroundColor Green