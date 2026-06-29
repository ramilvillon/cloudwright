# MADR Template (used by cloud-architect)

The generation subagent produces `<path>.staging/ADR.md` by substituting every `{{placeholder}}` below with content derived from the interview answers, pattern file, and pillar files. Placeholders inside code fences are literal and must not be substituted.

---

## Template

`````markdown
# ADR-001: {{workload_name}} Architecture

## Status

Proposed — {{date}}

## Context

{{workload_description}}

**Environments:** {{environments}}
**Primary region:** {{region}}
**Traffic:** {{traffic_tier}} ({{traffic_description}})
**Data sensitivity:** {{data_sensitivity}}
**Auth:** {{auth}}

**Assumptions used (user did not specify):**
{{assumptions_bullets}}

## Scope boundary

{{scope_boundary}}

## Decision

Use the **{{primary_pattern}}** pattern{{composed_pattern_clause}}.

### Architecture

````mermaid
{{mermaid_diagram}}
````

## Alternatives Considered

{{alternatives_bullets}}

## WAF Pillar Justification

- **Reliability:** {{reliability_decisions}}
- **Performance Efficiency:** {{performance_decisions}}
- **Cost Optimization:** {{cost_decisions}}
- **Operational Excellence:** {{ops_decisions}}
- **Sustainability:** {{sustainability_decisions}}
- **Security:** Deferred to `security-auditor` (findings in appendix).
- **Privacy:** Deferred to `privacy-auditor` (findings in appendix).

## Consequences

{{consequences_bullets}}

---

## Cost estimate (design-time)

{{cost_estimate_note}}

{{cost_estimate_table}}

_Post-deploy reality check: run `cost-auditor` against real usage once the workload has traffic._

---

## Audit Findings (auto-generated)

### ISO 27001 — `security-auditor`

{{security_scorecard_summary}}

{{security_findings_detail}}

### ISO 27701 — `privacy-auditor`

{{privacy_scorecard_summary}}

{{privacy_findings_detail}}
`````

---

## Placeholder contract

| Placeholder | Source | Format |
|---|---|---|
| `{{workload_name}}` | Interview Step 2 — derived slug | Title Case |
| `{{date}}` | Current date | YYYY-MM-DD |
| `{{workload_description}}` | Interview Step 2 | 1–3 sentences |
| `{{environments}}` | Interview Step 3 | comma-separated list |
| `{{region}}` | Interview Step 4 | AWS region code |
| `{{traffic_tier}}` | Interview Step 5 | `low` / `medium` / `high` |
| `{{traffic_description}}` | Derived from tier | e.g., "10–100 RPS" |
| `{{data_sensitivity}}` | Interview Step 6 | `none` / `internal` / `PII` / `regulated-PII` |
| `{{auth}}` | Interview Step 7 | `none` / `API keys` / `Cognito` / `existing IdP` |
| `{{assumptions_bullets}}` | Defaults the skill picked | markdown bullets, or `None` |
| `{{scope_boundary}}` | Pattern file's `## Scope boundary` section, verbatim | the paragraph + bullet list the workload pattern declares. For `account-baseline` itself, substitute: `_This pattern IS the account baseline — no deferred controls._` |
| `{{primary_pattern}}` | Pattern selection | human-readable name |
| `{{composed_pattern_clause}}` | Pattern selection | empty, or `", composed with the **<sibling>** pattern"` |
| `{{mermaid_diagram}}` | Pattern file's Mermaid snippet, parameterised | valid Mermaid |
| `{{alternatives_bullets}}` | Rejected patterns | markdown bullets with reasoning |
| `{{<pillar>_decisions}}` | Pillar-specific decisions from pattern annotations | 1–3 sentences per pillar. `<pillar>` expands to exactly these five keys: `reliability`, `performance`, `cost`, `ops` (from the "Ops Excellence" annotation), `sustainability`. Security and Privacy are hardcoded in the template (deferred to sibling auditor skills) — no placeholders for them. |
| `{{consequences_bullets}}` | Accepted trade-offs | markdown bullets |
| `{{security_scorecard_summary}}` | Audit subagent result | `✅ PASS (N) \| ⚠️ PARTIAL (N) \| ❌ FAIL (N)` |
| `{{security_findings_detail}}` | Audit subagent result | findings grouped by domain |
| `{{privacy_scorecard_summary}}` | Audit subagent result | `✅ PASS (N) \| 📋 REPORT (N) \| ⚠️ PARTIAL (N) \| ❌ FAIL (N)` |
| `{{privacy_findings_detail}}` | Audit subagent result | findings grouped by domain |
| `{{cost_estimate_note}}` | Infracost run status | italic one-liner: either "_Estimated via infracost v0.10.x (cloud pricing API)._" / "_Estimated via infracost v0.10.x (bundled pricing — set `INFRACOST_API_KEY` for live pricing)._" / "_Skipped — `infracost` not installed. Run `asdf plugin add infracost && asdf install infracost latest` and re-generate for estimates._" |
| `{{cost_estimate_table}}` | Infracost breakdown per env | markdown table: columns `Environment`, `Monthly cost (USD)`, `Top cost drivers`. One row per entry in `{{environments}}`. If skipped, replace with `_No estimate available._` |

**No placeholder may appear in the final ADR.** If any value is genuinely unknown (e.g., user declined to specify and no sensible default exists), write `TBD — requires workload owner confirmation` and add a bullet in the Assumptions section noting it.

## EXPERIMENTAL banner

If the skill could not match the workload to any catalog pattern and the user opted to proceed with freeform generation, prepend this banner to the ADR before `# ADR-001:`:

```markdown
> ⚠️ **EXPERIMENTAL** — this design was generated freeform (no catalog pattern matched). Review carefully before applying.
```
