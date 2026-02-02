# Compare Analysis Outputs
# Diffs two or more LLM analysis JSON files and detects hallucinations/inconsistencies

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$AnalysisPaths
)

if ($AnalysisPaths.Count -lt 2) {
  Write-Host "Usage: compare-analysis.ps1 <path1.json> <path2.json> [path3.json ...]" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Compares multiple LLM analysis outputs and flags discrepancies and hallucinations."
  exit 1
}

Write-Host "Comparing $($AnalysisPaths.Count) analysis files..." -ForegroundColor Cyan
Write-Host ""

# Load all analyses
$analyses = @()
$fileInfo = @()

foreach ($path in $AnalysisPaths) {
  if (-not (Test-Path $path)) {
    Write-Host "File not found: $path" -ForegroundColor Red
    continue
  }

  $content = Get-Content -Path $path -Raw
  try {
    $json = $content | ConvertFrom-Json
    $analyses += $json
    $fileInfo += @{
      path = $path
      name = (Split-Path $path -Leaf)
      index = $analyses.Count - 1
    }
    Write-Host "✓ Loaded: $(Split-Path $path -Leaf)" -ForegroundColor Green
  }
  catch {
    Write-Host "✗ Failed to parse: $path" -ForegroundColor Red
    throw
  }
}

if ($analyses.Count -lt 2) {
  Write-Host "Need at least 2 valid analysis files to compare." -ForegroundColor Red
  exit 1
}

Write-Host ""

# --- Helper functions ---

function Get-AllJsonKeys {
  param([object]$obj, [string]$prefix = '')

  $keys = @()

  if ($null -eq $obj) {
    return $keys
  }

  if ($obj -is [array]) {
    for ($i = 0; $i -lt $obj.Count; $i++) {
      $keys += Get-AllJsonKeys -obj $obj[$i] -prefix "$prefix`[$i`]"
    }
  }
  elseif ($obj -is [pscustomobject]) {
    foreach ($prop in $obj.PSObject.Properties) {
      $newPrefix = if ($prefix) { "$prefix.$($prop.Name)" } else { $prop.Name }
      $keys += $newPrefix
      $keys += Get-AllJsonKeys -obj $prop.Value -prefix $newPrefix
    }
  }
  else {
    # Leaf node, already added via parent
  }

  return $keys
}

function Get-ValueAtPath {
  param([object]$obj, [string]$path)

  $parts = $path -split '\.' | ForEach-Object {
    if ($_ -match '^(\w+)\[(\d+)\]$') {
      @($matches[1], [int]$matches[2])
    }
    else {
      $_
    }
  }

  $current = $obj

  foreach ($part in $parts) {
    if ($null -eq $current) { return $null }

    if ($current -is [array] -and $part -is [int]) {
      if ($part -lt $current.Count) {
        $current = $current[$part]
      }
      else {
        return $null
      }
    }
    elseif ($current -is [pscustomobject]) {
      $prop = $current.PSObject.Properties[$part]
      $current = $prop.Value
    }
    else {
      return $null
    }
  }

  return $current
}

# --- Extract all keys from all analyses ---
Write-Host "=== KEY COMPARISON ===" -ForegroundColor Cyan

$allKeys = @{}
foreach ($i in 0..($analyses.Count - 1)) {
  $keys = Get-AllJsonKeys -obj $analyses[$i]
  $allKeys[$i] = @($keys)
}

$allUniqueKeys = $allKeys.Values | ForEach-Object { $_ } | Select-Object -Unique | Sort-Object

# Find missing keys per analysis
$missingByAnalysis = @{}
for ($i = 0; $i -lt $analyses.Count; $i++) {
  $missing = @()
  foreach ($key in $allUniqueKeys) {
    if ($allKeys[$i] -notcontains $key) {
      $missing += $key
    }
  }
  if ($missing.Count -gt 0) {
    $missingByAnalysis[$i] = $missing
  }
}

if ($missingByAnalysis.Count -gt 0) {
  Write-Host "Missing keys per analysis:" -ForegroundColor Yellow
  foreach ($idx in $missingByAnalysis.Keys | Sort-Object) {
    $info = $fileInfo[$idx]
    Write-Host "  [$($info.name)]: $(($missingByAnalysis[$idx]).Count) missing" -ForegroundColor Yellow
    foreach ($key in $missingByAnalysis[$idx] | Select-Object -First 5) {
      Write-Host "    - $key"
    }
    if ($missingByAnalysis[$idx].Count -gt 5) {
      Write-Host "    ... and $($missingByAnalysis[$idx].Count - 5) more"
    }
  }
}
else {
  Write-Host "All analyses have the same top-level keys ✓" -ForegroundColor Green
}

Write-Host ""

# --- Check for hallucinations (fieldPath evidence validation) ---
Write-Host "=== HALLUCINATION DETECTION ===" -ForegroundColor Cyan

$hallucinations = @()

foreach ($i in 0..($analyses.Count - 1)) {
  $analysis = $analyses[$i]
  $fileInfo_i = $fileInfo[$i]

  # Check evidence array if it exists
  if ($analysis.evidence -and $analysis.evidence -is [array]) {
    foreach ($evidence in $analysis.evidence) {
      if ($evidence.fieldPath) {
        # Try to resolve the fieldPath in the input data
        # Note: We don't have the original input here, so we check against other analyses' evidence
        $resolvedInOthers = $false
        foreach ($j in 0..($analyses.Count - 1)) {
          if ($i -eq $j) { continue }
          $otherAnalysis = $analyses[$j]
          if ($otherAnalysis.evidence -and $otherAnalysis.evidence -is [array]) {
            foreach ($otherEv in $otherAnalysis.evidence) {
              if ($otherEv.fieldPath -eq $evidence.fieldPath) {
                $resolvedInOthers = $true
                break
              }
            }
          }
          if ($resolvedInOthers) { break }
        }

        if (-not $resolvedInOthers) {
          $hallucinations += @{
            file      = $fileInfo_i.name
            fieldPath = $evidence.fieldPath
            value     = $evidence.value
            severity  = 'medium'
          }
        }
      }
    }
  }

  # Check anomalies for evidence
  if ($analysis.anomalies -and $analysis.anomalies -is [array]) {
    foreach ($anomaly in $analysis.anomalies) {
      if ($anomaly.evidence -and $anomaly.evidence -is [array]) {
        foreach ($evidence in $anomaly.evidence) {
          if ($evidence.fieldPath) {
            # Check if this fieldPath is cited in other analyses
            $found = $false
            foreach ($j in 0..($analyses.Count - 1)) {
              if ($i -eq $j) { continue }
              $otherAnalysis = $analyses[$j]
              if ($otherAnalysis.evidence) {
                $otherEvidence = $otherAnalysis.evidence | Where-Object { $_.fieldPath -eq $evidence.fieldPath }
                if ($otherEvidence) {
                  $found = $true
                  break
                }
              }
              if ($found) { break }
            }

            if (-not $found) {
              $hallucinations += @{
                file      = $fileInfo_i.name
                fieldPath = $evidence.fieldPath
                context   = "Anomaly: $($anomaly.anomaly)"
                severity  = 'high'
              }
            }
          }
        }
      }
    }
  }
}

if ($hallucinations.Count -gt 0) {
  Write-Host "⚠️  Potential hallucinations detected ($($hallucinations.Count)):" -ForegroundColor Red
  foreach ($hal in $hallucinations) {
    Write-Host "  [$($hal.file)] fieldPath: $($hal.fieldPath)" -ForegroundColor Red
    if ($hal.context) { Write-Host "    Context: $($hal.context)" }
    Write-Host "    Severity: $($hal.severity)"
  }
}
else {
  Write-Host "No obvious hallucinations detected across analyses ✓" -ForegroundColor Green
}

Write-Host ""

# --- High-level summary comparison ---
Write-Host "=== SUMMARY COMPARISON ===" -ForegroundColor Cyan

foreach ($i in 0..($analyses.Count - 1)) {
  $analysis = $analyses[$i]
  $fileInfo_i = $fileInfo[$i]

  Write-Host ""
  Write-Host "[$($fileInfo_i.name)]" -ForegroundColor Magenta
  if ($analysis.summary) {
    Write-Host "Summary: $($analysis.summary)"
  }

  if ($analysis.confidence) {
    Write-Host "Confidence: $($analysis.confidence * 100)%"
  }

  if ($analysis.notablePatterns -and $analysis.notablePatterns.Count -gt 0) {
    Write-Host "Patterns: $($analysis.notablePatterns.Count)" -ForegroundColor Cyan
    foreach ($pattern in $analysis.notablePatterns | Select-Object -First 3) {
      Write-Host "  • $($pattern.pattern)"
    }
    if ($analysis.notablePatterns.Count -gt 3) {
      Write-Host "  ... and $($analysis.notablePatterns.Count - 3) more"
    }
  }

  if ($analysis.anomalies -and $analysis.anomalies.Count -gt 0) {
    Write-Host "Anomalies: $($analysis.anomalies.Count)" -ForegroundColor Yellow
    foreach ($anom in $analysis.anomalies | Select-Object -First 2) {
      Write-Host "  • [$($anom.severity.ToUpper())] $($anom.anomaly)"
    }
    if ($analysis.anomalies.Count -gt 2) {
      Write-Host "  ... and $($analysis.anomalies.Count - 2) more"
    }
  }

  if ($analysis.recommendedFollowUps -and $analysis.recommendedFollowUps.Count -gt 0) {
    Write-Host "Follow-ups: $($analysis.recommendedFollowUps.Count)" -ForegroundColor Cyan
    foreach ($followUp in $analysis.recommendedFollowUps | Select-Object -First 2) {
      Write-Host "  • [$($followUp.priority.ToUpper())] $($followUp.action)"
    }
    if ($analysis.recommendedFollowUps.Count -gt 2) {
      Write-Host "  ... and $($analysis.recommendedFollowUps.Count - 2) more"
    }
  }

  if ($analysis.caveats -and $analysis.caveats.Count -gt 0) {
    Write-Host "Caveats: $($analysis.caveats.Count)" -ForegroundColor DarkYellow
    foreach ($caveat in $analysis.caveats | Select-Object -First 2) {
      Write-Host "  ⚠ $caveat"
    }
    if ($analysis.caveats.Count -gt 2) {
      Write-Host "  ... and $($analysis.caveats.Count - 2) more"
    }
  }
}

Write-Host ""
Write-Host "=== COMPARISON COMPLETE ===" -ForegroundColor Green
