# LLM Analysis Rubric

## Purpose

This rubric defines how to evaluate and compare outputs from different LLM models analyzing security log data. Use this to ensure consistency, identify blind spots, and detect hallucinations across multiple models.

---

## Evaluation Dimensions

### 1. **Clarity & Communication**

Does the analysis communicate findings in a way a security engineer would understand and act upon?

- **Score 5**: Crystal clear; logical flow; professional tone; appropriate confidence caveats
- **Score 4**: Clear; minor ambiguities or redundancy
- **Score 3**: Generally understandable; some vague phrasing or organizational issues
- **Score 2**: Confusing; scattered reasoning; hard to extract action items
- **Score 1**: Unintelligible; incoherent reasoning

---

### 2. **Correctness**

Does the analysis accurately reflect the data in the provided JSON packet?

- **Score 5**: All claims verifiable against provided data; math/counts accurate; no errors
- **Score 4**: One minor factual error or miscount; otherwise correct
- **Score 3**: One-two errors; some claims need qualification
- **Score 2**: Multiple errors; significant misstatements; poor data accuracy
- **Score 1**: Fundamentally wrong; analysis contradicts the data

---

### 3. **Evidence & Citation**

Does the analysis cite specific fields, values, and fieldPaths from the packet? Can you trace claims back to the source data?

- **Score 5**: Every significant claim includes explicit `fieldPath` + `value` citations; easy to verify
- **Score 4**: Most claims cited; a few assertions lack specific evidence links
- **Score 3**: Some claims cited; notable gaps in evidence for key findings
- **Score 2**: Minimal citations; most assertions unsupported by fieldPath references
- **Score 1**: No citations; unsourced claims throughout

---

### 4. **Actionable Next Steps**

Does the analysis recommend concrete, security-relevant follow-up actions?

- **Score 5**: Multiple specific, prioritized recommendations; clear success metrics
- **Score 4**: Clear recommendations; could be more detailed or prioritized
- **Score 3**: Some recommendations offered; vague or generic in places
- **Score 2**: Weak or generic recommendations; unclear how to act on them
- **Score 1**: No recommendations, or only abstract ones

---

### 5. **Hallucination Risk**

Does the analysis invent or extrapolate data not present in the packet?

- **Score 5**: No invented claims; acknowledges data gaps; speculates clearly labeled as such
- **Score 4**: One speculative claim presented as fact; otherwise grounded
- **Score 3**: 2–3 minor inventions or unwarranted inferences
- **Score 2**: Multiple fabrications; assumptions stated as facts
- **Score 1**: Pervasive hallucinations; significant invented "findings"

---

### 6. **Completeness**

Does the analysis address the major patterns, risks, and anomalies visible in the data?

- **Score 5**: Covers all major themes; notes limitations; identifies secondary patterns
- **Score 4**: Addresses main findings; may miss one edge case or secondary pattern
- **Score 3**: Covers core issues; notable gaps in depth or breadth
- **Score 2**: Partial analysis; significant findings overlooked
- **Score 1**: Superficial; major patterns missed

---

## Hallucination Detection Checklist

Use this checklist to spot invented claims:

- [ ] **Field Existence**: Does every cited `fieldPath` actually exist in the input JSON? (e.g., `heuristics.sprayCandidates[0].ip` — does `heuristics` have a `sprayCandidates` key?)
- [ ] **Value Match**: If a claim references a specific value, does it appear in the data? (e.g., "failure reason was 'AADSTS50058'" — does this error code appear in the raw data?)
- [ ] **Count Accuracy**: Do referenced counts match the actual data? (e.g., "there were 47 failures" — count the failures in the input)
- [ ] **Logic Consistency**: Are inferences grounded in the data, or are they pure guesses? (e.g., "this pattern suggests credential stuffing" — is there evidence of credential stuffing in the packet?)
- [ ] **Constraint Acknowledgment**: If the input has data gaps, does the analysis acknowledge them? (e.g., "location data was missing for 15% of events")

---

## Scoring Aggregate

| Dimension             | Weight | Notes                                  |
|-----------------------|--------|----------------------------------------|
| Clarity               | 15%    | Communication quality for the audience |
| Correctness           | 25%    | Factual accuracy is paramount          |
| Evidence & Citation   | 25%    | Security analysis must be traceable    |
| Actionable Next Steps | 15%    | Practical value to the organization    |
| Hallucination Risk    | 15%    | Fabrications undermine trust           |
| Completeness          | 5%     | Secondary to other factors             |

Overall Score = Σ(Dimension Score × Weight / 100)

---

## Using This Rubric

1. **Before requesting analysis**: Share this rubric with the LLM so it knows what you're evaluating.
2. **After receiving output**: Score each dimension independently; note which specific claims drove your scores.
3. **In `compare-analysis.ps1`**: Output should include a summary of high-level scores and flagged hallucinations (failed evidence checks).
4. **Cross-model comparison**: Use the same rubric for multiple models so you can compare apples-to-apples.

---

## Example: Rubric in Action

**Input packet**: `analysis_input_20260202_1632Z.json` (30 sign-in events, 5 failures, top app = "Office 365")

**Model A's output**:

- "The highest-risk pattern is brute-force attacks on Office 365 from IP 203.0.113.5 (failure count: 8)."
- Evidence cited: `failures[].ipAddress = "203.0.113.5"`, `failures[].appDisplayName = "Office 365"`
- Verification: ✓ Both values appear in the data; ✓ Exactly 8 failures from that IP

**Score**: Clarity (5), Correctness (5), Evidence (5), Actionable (4), Hallucination (5), Completeness (4)

---

**Model B's output**:

- "The attack was targeted at the Finance department (estimated 80% of failures)."
- Evidence cited: *None provided*
- Verification: ✗ Input packet contains no department information; ✗ Invention of "Finance department" claim

**Score**: Clarity (3), Correctness (2), Evidence (1), Actionable (2), Hallucination (1), Completeness (2)

---

## References

- [MITRE ATT&CK Framework](https://attack.mitre.org/) — for framing hypotheses
- [OWASP Top 10](https://owasp.org/Top10/) — for common vulnerability context
- [CIS Controls](https://www.cisecurity.org/cis-controls/) — for remediation guidance
