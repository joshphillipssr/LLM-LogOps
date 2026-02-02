# Copilot instructions (CFHDITA-Logging)

## What this repo is
- Local-first PowerShell tooling to **collect + lightly normalize** security/platform logs, then emit **LLM-friendly JSON**.
- Current implemented collector: Entra ID sign-in logs via Microsoft Graph in [scripts/entra-signin-logs.ps1](../scripts/entra-signin-logs.ps1).

## How the Entra sign-in collector works
- Loads secrets from a repo-root `.env` file (required): `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`.
- Uses OAuth2 client credentials to get a Graph token, then queries:
  - `GET https://graph.microsoft.com/v1.0/auditLogs/signIns?$filter=createdDateTime ge <start> and createdDateTime lt <end>`
  - Handles pagination via `@odata.nextLink`.
- Default time window is **last 60 minutes** (UTC).

## Running locally
- Use PowerShell 7+ (`pwsh`), especially on macOS/Linux.
- Run the collector:
  - `pwsh -File scripts/entra-signin-logs.ps1`
- Expected artifacts are written under [reports/entra-signins](../reports/entra-signins):
  - `raw_<yyyyMMdd_HHmmZ>.json` (full Graph records, minimal transforms)
  - `summary_<yyyyMMdd_HHmmZ>.json` (counts + window)
  - `analysis_input_<yyyyMMdd_HHmmZ>.json` (aggregations + heuristics + bounded samples)

## Conventions to follow when editing/adding collectors
- Keep scripts **explicit and minimally opinionated**: preserve original signal; avoid irreversible transformations.
- Maintain the “3 artifacts” pattern (raw + summary + analysis_input) and keep JSON output stable and well-labeled.
- Prefer `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` like the existing script.
- For aggregations, follow the existing helpers:
  - `Get-TopCounts` (group/sort/top-N output objects with `count`)
  - `Get-NullableString` (normalize empty strings to `null`)
- Heuristics are meant to be **LLM-safe hints**, not detections (e.g., `sprayCandidates`, `noisyUsers`).

## External integration points
- Microsoft identity platform token endpoint: `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token`
- Microsoft Graph API: `https://graph.microsoft.com/v1.0/auditLogs/signIns`

## Security/ops notes for agents
- Never print or serialize `.env` secrets into outputs.
- Don’t check in `.env`; keep it local.
- When changing time windows/filters, keep everything in UTC ISO8601 (`ToString('o')`) to match existing outputs.
