# LLM LogOps

LLM LogOps is a focused, local-first repository for **collecting, normalizing, and analyzing security and platform logs** using a combination of PowerShell tooling and local or self‑hosted LLMs.

The goal is **not** to hard‑code every analytic rule up front, but to:

- Produce *clean, structured, and minimally ambiguous* log output
- Hand that output to an LLM for higher‑order reasoning, correlation, and narrative analysis
- Iterate toward heuristics and automation only where they clearly add value

This repo is intentionally separated from application or infrastructure code to keep logging logic, experiments, and analysis workflows isolated and reusable.

---

## ⚠️ Security Notice

This repository works with **real production security logs** containing sensitive data. Before contributing or running scripts:

- Read [SECURITY.md](SECURITY.md) for data protection guidelines
- Never commit `.env` files or report outputs (`reports/**/*.json`)
- Use `.env.example` as a template; obtain credentials from Azure Portal

---

## Design Philosophy

### 1. LLM‑Assisted Analysis First

Rather than building a large rules engine immediately, this project assumes:

- Raw logs are often too noisy or ambiguous for reliable reasoning
- Light aggregation + normalization dramatically improves LLM performance
- The LLM should do the *thinking*, pattern recognition, and explanation

Scripts should therefore:

- Be explicit but not overly opinionated
- Preserve original signal wherever possible
- Emit structured, well‑labeled output (JSON preferred)

---

### 2. Local‑First, Portable, Auditable

- All tooling is designed to run locally (macOS, Linux, Windows)
- Ollama is the default LLM runtime, but not a hard dependency
- Outputs are inspectable, reproducible, and version‑controlled
- No hidden prompts or opaque cloud processing

---

### 3. Incremental Tightening

We start broad and tighten only when needed:

1. **Collection** – pull logs reliably
2. **Normalization** – consistent fields, timestamps, identities
3. **Aggregation** – group by time, user, app, IP, outcome, etc.
4. **Heuristics (optional)** – only where ambiguity remains high
5. **LLM Analysis** – summarize, correlate, explain, flag anomalies

---

## Current Focus Areas

### Entra ID / Azure AD

- Sign‑in logs via Microsoft Graph
- Application, user, IP, and conditional access context
- Export to structured JSON for downstream analysis

### Future Targets

- MDE / Defender logs
- M365 Unified Audit Log
- Windows Event Logs
- VPN / Network device logs
- Cross‑source correlation

---

## Repository Structure (Initial)

```text
CFHIDTA-Logging/
│
├─ scripts/
│   ├─ entra-signin-logs.ps1     # Entra ID sign-in log extraction
│   └─ (future collectors)
│
├─ schemas/
│   └─ (optional JSON schemas)
│
├─ samples/
│   └─ example-output.json
│
├─ docs/
│   └─ analysis-notes.md
│
└─ README.md
```

This structure is expected to evolve as analysis workflows solidify.

---

## Output Expectations

Scripts in this repo should generally:

- Output **JSON**
- Include:
  - Metadata block (tenant, time range, script version)
  - Raw records (minimally transformed)
  - Optional summary / aggregation blocks
- Avoid irreversible transformations

Example (high‑level):

```json
{
  "metadata": {
    "source": "entra-signin-logs",
    "generatedAt": "2026-02-02T15:40:00Z",
    "timeRange": "PT1H"
  },
  "records": [ ... ],
  "summary": {
    "totalEvents": 123,
    "byResult": { "success": 110, "failure": 13 }
  }
}
```

---

## 📦 Data Storage Architecture

**This repo is code + documentation only.** All collected log data is stored in a separate **private repository**: [LMM-LogOps-Data](https://github.com/joshphillipssr/LMM-LogOps-Data)

```
LLM-LogOps (public)         →  Scripts, docs, analysis tools
                            ↓
                       Outputs data to
                            ↓
LMM-LogOps-Data (private)   →  reports/, analysis files
```

### Why Separate Repos?

1. **Security** — Real logs never appear in public code
2. **Clarity** — Clear separation of code vs. data
3. **Flexibility** — Data repo can be rotated/archived independently
4. **Access control** — Different teams for code vs. sensitive data

### Expected Directory Structure

```
# In LMM-LogOps-Data:
reports/
├─ entra-signins/
│  ├─ raw_<yyyyMMdd_HHmmZ>.json          # Full Graph API response
│  ├─ summary_<yyyyMMdd_HHmmZ>.json      # Metadata + counts
│  └─ analysis_input_<yyyyMMdd_HHmmZ>.json # LLM-ready aggregations
├─ analysis/
│  ├─ <timestamp>_<model>_ollama.json
│  └─ <timestamp>_<model>_metadata.json
└─ comparisons/
   └─ <timestamp>_compare_*.json
```

**See [LMM-LogOps-Data README](https://github.com/joshphillipssr/LMM-LogOps-Data) for detailed structure and security guidelines.**

---

### Overview

This repo includes a complete workflow for **comparing analysis outputs from multiple LLM models**:

1. **Collect logs** → artifacts in `LMM-LogOps-Data/reports/entra-signins/`
2. **Run through Ollama** → analysis output in `LMM-LogOps-Data/reports/analysis/`
3. **Compare outputs** → detect differences, hallucinations, blind spots
4. **Evaluate with rubric** → score clarity, correctness, evidence, hallucination risk

### Step 1: Run Log Collector

Generate the analysis input packet (outputs to private data repo):

```bash
cd /Users/josh/Projects/LLM-LogOps
pwsh -File scripts/entra-signin-logs.ps1
# Outputs to: ../LMM-LogOps-Data/reports/entra-signins/
#   - raw_<timestamp>.json (12 KB)
#   - summary_<timestamp>.json (< 1 KB)
#   - analysis_input_<timestamp>.json (50-100 KB)
```

### Step 2: Analyze with Ollama

Submit the analysis input to a local Ollama instance:

```bash
pwsh -File scripts/analyze-json-ollama.ps1 `
  -InputPath ../LMM-LogOps-Data/reports/entra-signins/analysis_input_<timestamp>.json `
  -OllamaBaseUrl 'http://localhost:11434' `
  -Model 'gpt-oss:20b' `
  -OutDir ../LMM-LogOps-Data/reports/analysis
# Outputs to: ../LMM-LogOps-Data/reports/analysis/
#   - <timestamp>_gpt-oss_20b_ollama.json (analysis results)
#   - <timestamp>_gpt-oss_20b_metadata.json (metadata + timing)
```

**Supported Ollama models:**

- `gpt-oss:20b` (default)
- `neural-chat:latest`
- `mistral:latest`
- Any other model installed in your Ollama instance

**Parameters:**

- `-InputPath`: Path to `analysis_input_*.json` in data repo (required)
- `-OllamaBaseUrl`: Ollama HTTP endpoint (default: `http://localhost:11434`)
- `-Model`: Model name in Ollama (default: `gpt-oss:20b`)
- `-OutDir`: Output directory in data repo (default: `../LMM-LogOps-Data/reports/analysis`)

### Step 3 (Optional): Run Analysis with Continue/Copilot

Manually ask VS Code Copilot or Continue.dev to analyze the same packet:

1. Open `../LMM-LogOps-Data/reports/entra-signins/analysis_input_<timestamp>.json`
2. Tell Copilot/Continue: "Analyze this Entra ID sign-in log packet and return JSON matching this schema: [paste schema from docs/prompts/log-analysis.prompt.md]"
3. Save output to `../LMM-LogOps-Data/reports/analysis/<timestamp>_<model-name>.json`

### Step 4: Compare Analysis Outputs

Run the comparison script against 2+ analysis files:

```bash
pwsh -File scripts/compare-analysis.ps1 `
  ../LMM-LogOps-Data/reports/analysis/20260202_1632Z_gpt-oss_ollama.json `
  ../LMM-LogOps-Data/reports/analysis/20260202_1635Z_copilot_response.json
# Output: Side-by-side comparison, hallucination detection, summary diffs
```

**What it checks:**

- Missing keys across analyses
- Inconsistent structures
- Potentially hallucinated fieldPaths (evidence pointing to non-existent data)
- Summary, anomalies, and follow-up recommendations

### Evaluation & Scoring

Use the **rubric** in [docs/analysis-rubric.md](docs/analysis-rubric.md) to score each model on:

| Dimension             | Weight | What to Look For                           |
|-----------------------|--------|--------------------------------------------|
| Clarity               | 15%    | Professional, actionable communication     |
| Correctness           | 25%    | Facts match the input data                 |
| Evidence & Citation   | 25%    | fieldPath references are traceable         |
| Actionable Next Steps | 15%    | Concrete security recommendations          |
| Hallucination Risk    | 15%    | No fabricated data or patterns             |
| Completeness          | 5%     | Coverage of major signals                  |

See [docs/analysis-rubric.md](docs/analysis-rubric.md) for detailed scoring guidance and a hallucination detection checklist.

### Prompt Design

The analysis prompt is defined in [docs/prompts/log-analysis.prompt.md](docs/prompts/log-analysis.prompt.md). It enforces:

- **Only use provided JSON data** (no external knowledge assumed)
- **Return strict JSON output** with keys: `summary`, `notablePatterns`, `anomalies`, `hypotheses`, `recommendedFollowUps`, `confidence`, `evidence`, `caveats`
- **Evidence must be traceable** — every claim should cite a fieldPath and value
- **Explicit uncertainty** — if unsure, the model should say so; no fabrication

The script automatically injects this prompt as the system message and passes the JSON packet as the user message.

### Example Workflow

```bash
# 1. Collect logs (last 60 minutes of Entra sign-ins)
pwsh -File scripts/entra-signin-logs.ps1
# → reports/entra-signins/analysis_input_20260202_1632Z.json

# 2. Analyze with Ollama
pwsh -File scripts/analyze-json-ollama.ps1 `
  -InputPath ../LMM-LogOps-Data/reports/entra-signins/analysis_input_20260202_1632Z.json `
  -OllamaBaseUrl 'http://localhost:11434' `
  -Model 'gpt-oss:20b'
# → ../LMM-LogOps-Data/reports/analysis/20260202_1632Z_gpt-oss_ollama.json
# → ../LMM-LogOps-Data/reports/analysis/20260202_1632Z_gpt-oss_metadata.json

# 3. (Optionally) Get Copilot analysis via Continue
# ... paste JSON + schema into Continue sidebar, save output ...
# → ../LMM-LogOps-Data/reports/analysis/20260202_1635Z_copilot_response.json

# 4. Compare the two
pwsh -File scripts/compare-analysis.ps1 `
  ../LMM-LogOps-Data/reports/analysis/20260202_1632Z_gpt-oss_ollama.json `
  ../LMM-LogOps-Data/reports/analysis/20260202_1635Z_copilot_response.json

# 5. Score using the rubric
# Open docs/analysis-rubric.md and manually score each model on the 6 dimensions
```

---

## Repository Organization

### LLM-LogOps (Public - This Repo)

Contains:
- PowerShell scripts for log collection and analysis
- LLM prompt templates and analysis rubric
- Documentation and guides
- Security policies and best practices

**No data files** — all logs stored in private data repo

### LMM-LogOps-Data (Private)

Contains:
- Raw Entra ID sign-in logs (`raw_*.json`)
- Aggregated analysis inputs (`analysis_input_*.json`)
- LLM analysis outputs (`*_ollama.json`, `*_copilot.json`, etc.)
- Comparison outputs and metadata

See [LMM-LogOps-Data README](https://github.com/joshphillipssr/LMM-LogOps-Data) for full details.

---

## LLM Usage (Manual)

This repo is designed to pair well with:

- **Continue.dev**
- **VS Code Copilot (agent mode)**
- Custom local VS Code agents

For manual ad-hoc analysis:

1. Run collector script (outputs to data repo)
2. Review / spot-check JSON output

3. Feed output + context to an LLM
4. Ask for:
   - Behavioral summaries
   - Anomaly detection
   - Narrative explanations
   - Hypothesis generation

---

## Non‑Goals (For Now)

- Real‑time alerting
- Full SIEM replacement
- Hard‑coded detection rules at scale
- Automated enforcement actions

Those may come later — but only if justified.

---

## Status

🚧 **Early / Experimental**

This repo is actively evolving as tooling, models, and workflows are tested.

Expect:

- Frequent refactors
- Schema changes
- Documentation updates alongside scripts

---

## License

Internal / restricted use unless otherwise specified.
