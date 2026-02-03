# Copilot Instructions (LLM-LogOps)

## Repository Structure

- **LLM-LogOps** (public): Code, scripts, docs, templates
- **LMM-LogOps-Data** (private): All collected logs and analysis outputs

All data is stored in the separate private repository to keep sensitive information out of the public repo.

## What This Repo Is

- Local-first PowerShell tooling to **collect + lightly normalize** security/platform logs, then emit **LLM-friendly JSON**.
- Current implemented collector: Entra ID sign-in logs via Microsoft Graph in [scripts/entra-signin-logs.ps1](../scripts/entra-signin-logs.ps1).
- **Data outputs go to LMM-LogOps-Data** — never stored in this public repo.

## How the Entra Sign-in Collector Works

- Loads secrets from a repo-root `.env` file (required): `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`.
- Uses OAuth2 client credentials to get a Graph token, then queries:
  - `GET https://graph.microsoft.com/v1.0/auditLogs/signIns?$filter=createdDateTime ge <start> and createdDateTime lt <end>`
  - Handles pagination via `@odata.nextLink`.
- Default time window is **last 60 minutes** (UTC).
- **Outputs to `../LMM-LogOps-Data/reports/entra-signins/`** (private data repo)

## Running Locally

- Use PowerShell 7+ (`pwsh`), especially on macOS/Linux.
- Ensure **LMM-LogOps-Data is cloned** as a sibling directory
- Run the collector:
  - `pwsh -File scripts/entra-signin-logs.ps1`
- Expected artifacts are written to **`../LMM-LogOps-Data/reports/entra-signins/`** (private data repo):
  - `raw_<yyyyMMdd_HHmmZ>.json` (full Graph records, minimal transforms)
  - `summary_<yyyyMMdd_HHmmZ>.json` (counts + window)
  - `analysis_input_<yyyyMMdd_HHmmZ>.json` (aggregations + heuristics + bounded samples)
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
