# Ollama JSON Analysis Script
# Submits analysis_input JSON to Ollama and captures structured LLM output

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [Parameter(Mandatory = $false)]
  [string]$OllamaBaseUrl = "http://localhost:11434",

  [Parameter(Mandatory = $false)]
  [string]$Model = "gpt-oss:20b",

  [Parameter(Mandatory = $false)]
  [string]$OutDir = "reports/analysis"
)

# Resolve paths
$InputPath = Resolve-Path -Path $InputPath -ErrorAction Stop
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$OutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }

# Ensure output directory exists
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "Input: $InputPath" -ForegroundColor Cyan
Write-Host "Ollama: $OllamaBaseUrl" -ForegroundColor Cyan
Write-Host "Model: $Model" -ForegroundColor Cyan
Write-Host "OutDir: $OutDir" -ForegroundColor Cyan

# --- Load prompt template ---
$promptTemplatePath = Join-Path $repoRoot 'docs/prompts/log-analysis.prompt.md'
if (-not (Test-Path $promptTemplatePath)) {
  throw "Prompt template not found at $promptTemplatePath"
}

$promptTemplate = Get-Content -Path $promptTemplatePath -Raw

# Extract system and user portions from the template
# System: everything up to "## User Prompt"
# User: everything from "## User Prompt" onward
$systemMatch = $promptTemplate -match '(?s)^.*?(?=## User Prompt)'
$systemPrompt = if ($systemMatch) { $promptTemplate.Substring(0, $promptTemplate.IndexOf('## User Prompt')).Trim() } else { 'You are a security analyst.' }

# Remove the header line "## User Prompt" from the user portion
$userPromptSection = $promptTemplate -replace '(?s)^.*?## User Prompt\s*', ''

# Load the JSON input packet
$jsonPacket = Get-Content -Path $InputPath -Raw
$jsonInput = $jsonPacket | ConvertFrom-Json
if (-not $jsonInput) {
  throw "Failed to parse JSON from $InputPath"
}

Write-Host "Loaded analysis packet with $(($jsonInput.totals.total ?? 0)) total events" -ForegroundColor Green

# Compute input hash for reproducibility tracking
$inputHasher = [System.Security.Cryptography.SHA256]::Create()
$inputHashBytes = $inputHasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($jsonPacket))
$inputHash = [System.BitConverter]::ToString($inputHashBytes).Replace('-', '').Substring(0, 16)

Write-Host "Input hash: $inputHash" -ForegroundColor Magenta

# --- Build Ollama chat request ---
$userMessage = "$userPromptSection`n`n$jsonPacket"

$chatRequest = @{
  model       = $Model
  messages    = @(
    @{ role = 'system'; content = $systemPrompt },
    @{ role = 'user'; content = $userMessage }
  )
  stream      = $false
  temperature = 0.2
  top_p       = 0.9
  top_k       = 40
} | ConvertTo-Json -Depth 10

Write-Host "Submitting request to Ollama..." -ForegroundColor Cyan
$startTime = Get-Date

try {
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "$OllamaBaseUrl/api/chat" `
    -ContentType 'application/json' `
    -Body $chatRequest `
    -TimeoutSec 300

  $endTime = Get-Date
  $duration = ($endTime - $startTime).TotalSeconds

  Write-Host "Response received in $([math]::Round($duration, 2))s" -ForegroundColor Green

  if (-not $response.message.content) {
    throw 'No response content from Ollama'
  }

  $modelOutput = $response.message.content

  # --- Parse JSON response ---
  $analysisJson = $null
  try {
    # Try to extract JSON if it's embedded in markdown or other text
    $jsonMatch = $modelOutput | Select-String -Pattern '(?s)\{.*\}' -AllMatches
    if ($jsonMatch.Matches.Count -gt 0) {
      $jsonStr = $jsonMatch.Matches[0].Value
      $analysisJson = $jsonStr | ConvertFrom-Json
    } else {
      $analysisJson = $modelOutput | ConvertFrom-Json
    }
  }
  catch {
    Write-Warning "Failed to parse response as JSON; saving raw output instead."
    $analysisJson = @{ rawResponse = $modelOutput } | ConvertTo-Json -Depth 10
  }

  # --- Write analysis output ---
  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmZ'
  $modelSafe = $Model -replace '[^a-zA-Z0-9_]', '_'
  $analysisOutputPath = Join-Path $OutDir "${timestamp}_${modelSafe}_ollama.json"

  $analysisJson | ConvertTo-Json -Depth 10 | Out-File -Path $analysisOutputPath -Encoding UTF8

  Write-Host "Analysis output: $analysisOutputPath" -ForegroundColor Green

  # --- Write metadata ---
  $metadata = @{
    model             = $Model
    baseUrl           = $OllamaBaseUrl
    inputPath         = $InputPath
    inputHash         = $inputHash
    timestamp         = (Get-Date -AsUTC).ToString('o')
    durationSeconds   = $duration
    outputPath        = $analysisOutputPath
    temperature       = 0.2
    top_p             = 0.9
    top_k             = 40
    inputTotals       = @{
      events           = $jsonInput.totals.total
      successCount     = $jsonInput.totals.success
      failureCount     = $jsonInput.totals.failure
      window           = $jsonInput.window
    }
  }

  # Add token info if available from response
  if ($response.eval_count -and $response.prompt_eval_count) {
    $metadata.tokens = @{
      promptTokens = $response.prompt_eval_count
      responseTokens = $response.eval_count
      totalTokens = ($response.prompt_eval_count + $response.eval_count)
    }
  }

  $metadataOutputPath = Join-Path $OutDir "${timestamp}_${modelSafe}_metadata.json"
  $metadata | ConvertTo-Json -Depth 10 | Out-File -Path $metadataOutputPath -Encoding UTF8

  Write-Host "Metadata: $metadataOutputPath" -ForegroundColor Green
  Write-Host "`nAnalysis complete." -ForegroundColor Cyan
}
catch {
  Write-Host "Error during Ollama request: $_" -ForegroundColor Red
  throw
}
