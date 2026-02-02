# CFHDITA Logging

CFHIDTA-Logging is a focused, local-first repository for **collecting, normalizing, and analyzing security and platform logs** using a combination of PowerShell tooling and local or self‑hosted LLMs.

The goal is **not** to hard‑code every analytic rule up front, but to:

- Produce *clean, structured, and minimally ambiguous* log output
- Hand that output to an LLM for higher‑order reasoning, correlation, and narrative analysis
- Iterate toward heuristics and automation only where they clearly add value

This repo is intentionally separated from application or infrastructure code to keep logging logic, experiments, and analysis workflows isolated and reusable.

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

## LLM Usage

This repo is designed to pair well with:

- **Continue.dev**
- **VS Code Copilot (agent mode)**
- Custom local VS Code agents

Typical workflow:

1. Run collector script
2. Review / spot‑check JSON output
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
