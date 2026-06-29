---
name: cloud-architect
description: Use when working in an AWS project and asked to design, generate, or scaffold a cloud architecture following the AWS Well-Architected Framework. Produces an ADR (MADR), a Mermaid diagram, and a parameterized Terraform project, then auto-runs the security-auditor and privacy-auditor skills to verify the design before promoting files.
---

# AWS Cloud Architect

## Overview

Turn a workload description or a requirements doc into a Well-Architected AWS design. The skill picks a reference pattern from its 10-pattern catalog (composing two or more when needed), generates Terraform into a staging directory, runs the sibling security + privacy auditors against the staged output, and presents findings before the user promotes the staging directory to its final location.

Outputs (in `<path>.staging/`, promoted to `<path>/` on user confirmation):
- `ADR.md` — MADR-format Architecture Decision Record with Mermaid diagram + inline audit findings
- `README.md` — how to use the generated Terraform
- Terraform project (layout depends on selected pattern)

## HARD CONSTRAINT: NO AWS WRITES, NO `terraform apply`

This skill writes to the **local filesystem only**. It:
- Creates `<path>.staging/` during generation
- Moves `<path>.staging/` → `<path>/` on promote (user-confirmed)
- Never executes AWS write calls
- Never runs `terraform apply`, `terraform destroy`, or any state-mutating command

If the user asks the skill to apply the Terraform directly, respond:
> _"This skill writes local Terraform files only. Review the generated code in `<path>/`, then run `terraform init && terraform plan` yourself to apply."_

---

## Step 1 — Ask Input Mode

Ask the user:
> "What would you like to do?
> **A) Greenfield design** — describe a workload and I'll design + generate it
> **B) Design from requirements doc** — point me at a markdown/text file"

Wait for the response.

---

## Step 2 — Requirements Intake

- **If Mode A:** ask _"Describe the workload in 1–3 sentences."_ and store the response as `WORKLOAD_DESCRIPTION`.
- **If Mode B:** ask _"Path to the requirements doc?"_, read the file with the Read tool, and extract `WORKLOAD_DESCRIPTION`, `ENVIRONMENTS`, `REGION`, `TRAFFIC`, `DATA_SENSITIVITY`, `AUTH` where the doc provides them. Record which inputs are present; move to Step 3 for each missing one.

---

## Step 3 — Environments

Ask (skip if Mode B supplied this):
> "Which environments? **A) dev only**, **B) dev + staging + prod**, or **C) custom** (type a comma-separated list)"

Store as `ENVIRONMENTS` (list).

---

## Step 3b — VPC-layer environment mapping

Skip this step if the user already specified VPC topology in `WORKLOAD_DESCRIPTION` (e.g., "2 VPCs — one shared by dev+staging, one for prod") — in that case, parse their mapping directly.

Otherwise ask (skip if `ENVIRONMENTS` has only one entry):
> "How should environments map to VPCs?
> **A) One VPC per environment** (full network isolation — default)
> **B) Shared nonprod VPC** (dev+staging share one VPC, prod isolated — common cost/isolation trade-off)
> **C) Custom** (describe which envs share)"

Compute two variables from the answer:

- `VPC_LAYER_ENVS`: the deduplicated list of **VPC-layer environments**. Not the same as `ENVIRONMENTS`.
  - Option A → `VPC_LAYER_ENVS = ENVIRONMENTS` (e.g., `[dev, staging, prod]`)
  - Option B → `VPC_LAYER_ENVS = [nonprod, prod]` (dev + staging collapse to `nonprod`)
  - Option C → parse the user's mapping (e.g., "dev+qa share, staging+prod separate" → `[shared, staging, prod]`)
- `ENV_TO_VPC`: a mapping from each workload env → its VPC-layer env. Used for tagging and README documentation. E.g., `{dev: nonprod, staging: nonprod, prod: prod}`.

**Why this matters.** Several patterns (`vpc-foundation`, `three-tier-containerized`, anything with RDS/ECS/EC2) emit per-VPC-layer `.tfvars` files. Without this mapping, the generation subagent defaults to one VPC per workload env — which produces too many VPCs when the user actually wants envs to share (wasted NAT + endpoint cost, confusing README). The account-baseline + vpc-foundation eval run surfaced exactly this defect.

If the selected pattern (decided in Step 9) turns out to have no VPC resources, `VPC_LAYER_ENVS` is ignored — no harm done.

---

## Step 4 — Primary Region

Ask (skip if Mode B supplied this):
> "Primary AWS region? (e.g., `ap-southeast-1`, `us-east-1`)"

Store as `REGION`.

**If the user declines to pick:** ask once more with an explicit list of common regions. If they still decline, default to `us-east-1` and record the assumption.

---

## Step 5 — Traffic / Scale

Ask (skip if Mode B supplied this):
> "Traffic tier?
> **A) low** (<10 RPS)
> **B) medium** (10–100 RPS)
> **C) high** (100+ RPS)"

Store as `TRAFFIC`.

---

## Step 6 — Data Sensitivity

Ask (skip if Mode B supplied this):
> "Data sensitivity?
> **A) none** — public data
> **B) internal** — internal-only data, no PII
> **C) PII** — personally identifiable information
> **D) regulated-PII** — HIPAA, PCI, or equivalent regulated data"

Store as `DATA_SENSITIVITY`.

---

## Step 7 — Auth

Ask (skip if Mode B supplied this):
> "Application-end-user authentication? (How users of the workload sign in — NOT how humans access the AWS console, which is assumed to be IAM.)
> **A) none** — no end-user auth (static site, internal service, etc.)
> **B) API keys** — shared keys per caller
> **C) Cognito** — user pool + hosted UI
> **D) existing IdP** (SAML/OIDC)"

Store as `AUTH`.

**Disambiguation.** If the user mentions "IAM users", "root account", "AWS SSO", or "Identity Center", those are AWS-console/programmatic-access concerns — not application auth. Record them under `WORKLOAD_DESCRIPTION` assumptions (they inform account-baseline pattern selection) and ask the auth question again scoped to end-users. The eval run for account-baseline surfaced this conflation; the disambiguation prevents `AUTH = none` from being set when the user meant "AWS console is IAM, no app-layer auth needed yet."

---

## Step 8 — Output Path

Ask:
> "Where should I write? (default: `./iac/`) I'll write to `<path>.staging/` first and promote after audit."

Store as `OUTPUT_PATH`. If user doesn't answer, default to `./iac`. Derive `STAGING_PATH = "${OUTPUT_PATH}.staging"`.

---

## Step 9 — Pattern Selection and Confirmation

Read only the `## When to use` and `## Not when` headers of each pattern file in `${CLAUDE_SKILL_DIR}/patterns/`. Based on `WORKLOAD_DESCRIPTION`, `TRAFFIC`, `AUTH`, and `DATA_SENSITIVITY`, select:
- **Primary pattern** (required)
- Up to **2 composed patterns** (optional — e.g., `three-tier-containerized` + `event-driven-async` for a web app with a background queue)

If no pattern fits, ask:
> "No catalog pattern matches this workload cleanly. Options:
> **A) Describe a custom design** — I'll generate freeform with an ⚠️ EXPERIMENTAL banner on the ADR
> **B) Pick the closest catalog pattern and document deviations**
> **C) Cancel**"

Summarise the selection and confirm with the user:
> "I'll use the **{{primary}}** pattern{{, composed with {{composed}}}} to write Terraform + ADR to `{{STAGING_PATH}}`. Audit chain (security-auditor + privacy-auditor) will run against the staged output before you promote. Proceed? (yes/no)"

Wait for confirmation before dispatching subagents.

---

## Step 10 — Generation Subagent

Dispatch **one** subagent:

```
Agent({
  description: "Generate WAF-aligned Terraform + ADR for {{workload}}",
  subagent_type: "general-purpose",
  prompt: `
You are the cloud-architect generation subagent. Write local files only — no AWS writes.

INPUT:
- WORKLOAD_DESCRIPTION: {{WORKLOAD_DESCRIPTION}}
- ENVIRONMENTS: {{ENVIRONMENTS}}  # workload-level envs, e.g., [dev, staging, prod]
- VPC_LAYER_ENVS: {{VPC_LAYER_ENVS}}  # deduplicated VPC-layer envs, e.g., [nonprod, prod] when dev+staging share
- ENV_TO_VPC: {{ENV_TO_VPC}}  # mapping, e.g., {dev: nonprod, staging: nonprod, prod: prod}
- REGION: {{REGION}}
- TRAFFIC: {{TRAFFIC}}
- DATA_SENSITIVITY: {{DATA_SENSITIVITY}}
- AUTH: {{AUTH}}
- STAGING_PATH: {{STAGING_PATH}}
- PRIMARY_PATTERN: {{PRIMARY_PATTERN}}
- COMPOSED_PATTERNS: {{COMPOSED_PATTERNS}}
- ASSUMPTIONS: {{ASSUMPTIONS_BULLETS}}
- EXPERIMENTAL: {{true|false}}  # true only if no pattern matched

STEP 1 — Read these files:
- ${CLAUDE_SKILL_DIR}/patterns/{{PRIMARY_PATTERN}}.md
- ${CLAUDE_SKILL_DIR}/patterns/{{each composed pattern}}.md
- ${CLAUDE_SKILL_DIR}/patterns/vpc-foundation.md (if the primary pattern's layout uses modules/networking/)
- ${CLAUDE_SKILL_DIR}/pillars/reliability.md
- ${CLAUDE_SKILL_DIR}/pillars/performance.md
- ${CLAUDE_SKILL_DIR}/pillars/operational-excellence.md
- ${CLAUDE_SKILL_DIR}/pillars/sustainability.md
- ${CLAUDE_SKILL_DIR}/templates/adr.md
- ${CLAUDE_SKILL_DIR}/templates/mermaid-conventions.md

STEP 2 — Create the staging directory:
  mkdir -p {{STAGING_PATH}}
  If {{STAGING_PATH}} already exists, abort and return error: "Staging path already exists — move or delete it first."

STEP 3 — Generate Terraform files per the primary pattern's "Terraform layout" section, substituting variables with values derived from the interview answers. If composing multiple patterns, merge their HCL while:
  - de-duplicating provider, variable, and output blocks
  - preserving module boundaries
  - ensuring all cross-module wiring (module outputs → module inputs) is explicit

STEP 4 — Apply ALL 4 pillar rubrics (reliability, performance, operational-excellence, sustainability) to the generated HCL. This means:
  - default_tags block in the provider (from ops-excellence)
  - Graviton architectures where applicable (from performance + sustainability)
  - Multi-AZ defaults (from reliability)
  - Log retention + alarms (from ops-excellence)
  - Lifecycle rules on S3 buckets (from sustainability)

STEP 5 — Write ADR.md using templates/adr.md as the scaffold. Fill EVERY placeholder:
  - {{scope_boundary}} — copy the pattern file's `## Scope boundary` section body verbatim (paragraph + bullet list). If the primary pattern is `account-baseline`, substitute the literal string: `_This pattern IS the account baseline — no deferred controls._`
  - {{mermaid_diagram}} derived from the pattern's Mermaid snippet, parameterised (e.g., RDS → "RDS Multi-AZ" for prod, "RDS" for dev-only), following templates/mermaid-conventions.md
  - {{<pillar>_decisions}} taken from the pattern's WAF pillar annotations for that pillar
  - {{alternatives_bullets}} — explicitly list the 1–2 closest patterns you rejected and why
  - {{consequences_bullets}} — trade-offs accepted (e.g., single NAT in dev, no read replica, Fargate Spot in non-prod)
  - {{security_scorecard_summary}} / {{security_findings_detail}} / {{privacy_*}} — leave as placeholder "_pending audit — main agent will fill in_"
  - If EXPERIMENTAL: prepend the experimental banner from the template file

STEP 6 — Write README.md at the root of the staging path:
  - "How to use" section: per-env workflow — `terraform init`, then `terraform plan -var-file=<env>.tfvars`, then `terraform apply -var-file=<env>.tfvars`. Recommend separate state backends / workspaces per env.
  - Required env vars / AWS profile
  - List of generated `<env>.tfvars` files and which variables each one sets (link to `terraform.tfvars.example` for the full variable catalog)
  - If `<env>-usage.yml` files were emitted, add a short "Usage estimates" paragraph explaining they're inputs for `infracost breakdown --usage-file` and the user can edit them to re-estimate cost without re-generating
  - Pointer to ADR.md
  - Note that the `AUDIT.md` findings are currently embedded in ADR.md (do not create separate AUDIT.md unless findings are too large — in which case create it and link from ADR.md)

STEP 7 — Write per-env `.tfvars` files. The iteration target depends on what the patterns emit:
  - **If the selected pattern(s) emit ONLY VPC-layer resources** (e.g., `vpc-foundation`, `account-baseline` composed with `vpc-foundation`): iterate over `{{VPC_LAYER_ENVS}}`. Filenames use the VPC-layer env names: e.g., `nonprod.tfvars`, `prod.tfvars` — NOT `dev.tfvars`/`staging.tfvars`/`prod.tfvars` when dev+staging share the nonprod VPC. Writing per-workload-env tfvars in this case would produce duplicate VPCs and confuse the README.
  - **If the pattern emits workload-level resources that vary per workload env** (e.g., `three-tier-containerized` with per-env ECS services): iterate over `{{ENVIRONMENTS}}`. Filenames use the workload env names: `dev.tfvars`, `staging.tfvars`, `prod.tfvars`.
  - **If composing both** (VPC foundation + workload pattern): emit BOTH sets in their respective subdirectories — the VPC subproject gets `nonprod.tfvars`/`prod.tfvars`, the workload subproject gets `dev.tfvars`/`staging.tfvars`/`prod.tfvars`. The README explains the handoff and the `ENV_TO_VPC` mapping.

  Each file sets:
  - The appropriate env variable (`environment = "<vpc-env>"` or `environment = "<workload-env>"`) plus `region = "{{REGION}}"` and any pattern-specific variables.
  - Per-env defaults pulled from the pillar rubrics:
    - **prod:** Multi-AZ on, larger instance classes, longer log/backup retention, no Spot, reserved-capacity candidates noted
    - **staging:** prod-like topology, smaller instances, Fargate Spot allowed
    - **dev / nonprod:** single-AZ, smallest viable instances, 7-day log retention, Fargate Spot
  - Omit any secrets; set them via `TF_VAR_` env vars or separate Secrets Manager references.

  Also write `terraform.tfvars.example` (per subproject if the layout is multi-project) as a commented reference showing every available variable. Never write `terraform.tfvars`.

STEP 7b — Write one `<env>-usage.yml` file per entry in the **same iteration target** used in Step 7 (`{{VPC_LAYER_ENVS}}` or `{{ENVIRONMENTS}}`) IF the primary pattern file has a `## Usage drivers` section. These files drive infracost's estimation of usage-dependent resources (CloudFront data transfer, S3 requests, Lambda invocations, etc.) in Step 11.5.
  - Read the pattern's `## Usage drivers` section — it contains a YAML template with per-traffic-tier numbers (low / medium / high).
  - For each target env, scale the usage numbers to reflect that env's expected traffic. Mapping: non-prod envs use the tier BELOW the interview's {{TRAFFIC}} (or the low tier floor); prod uses the interview's tier directly. Rationale: pre-prod envs typically see 10x lower traffic than prod.
  - If the pattern has no `## Usage drivers` section, SKIP this step — do not emit usage files. Step 11.5 will run infracost without a usage file (fixed-cost-only estimate).
  - Filename convention: alongside the corresponding `<env>.tfvars` (e.g., `nonprod-usage.yml` / `prod-usage.yml`, or `dev-usage.yml` / `staging-usage.yml` / `prod-usage.yml`).

STEP 8 — Run optional syntax check:
  If terraform is available on PATH, run:
    cd {{STAGING_PATH}} && terraform init -backend=false && terraform validate
  Capture the output. Do NOT fail if terraform isn't installed; just note it in your result.

STEP 9 — Return a structured result:
  - Files written (list of paths)
  - Terraform validate output (or "skipped — terraform not installed")
  - Any assumptions made + what default was used
`
})
```

Wait for the subagent to return before proceeding.

---

## Step 11 — Audit Chain (Parallel Subagents)

Dispatch **two subagents in parallel** (single message with two Agent tool calls):

### Security audit subagent

```
Agent({
  description: "ISO 27001 IaC audit on {{STAGING_PATH}}",
  subagent_type: "general-purpose",
  prompt: `
You are running the security-auditor skill as a subagent. Skip the normal interview — every answer is pre-filled here.

PRE-FILLED ANSWERS:
- Step 1 (Audit Mode): A (IaC)
- Step 2 (Domain Selection): 8 (all domains)
- Target path: {{STAGING_PATH}}
- Return mode: inline

STEPS:
1. Read ${CLAUDE_SKILL_DIR}/../security-auditor/SKILL.md (specifically the "Subagent invocation" section).
2. Read all 7 domain files under ${CLAUDE_SKILL_DIR}/../security-auditor/domains/.
3. Execute Step 3 of that skill's flow (IaC compliance scan) against {{STAGING_PATH}}.
4. Return the full scorecard INLINE (do NOT write docs/security-report-*.md). Format matches what SKILL.md would normally write:
   - Header summary: PASS/PARTIAL/FAIL counts
   - Findings list grouped by domain
`
})
```

### Privacy audit subagent

```
Agent({
  description: "ISO 27701 IaC audit on {{STAGING_PATH}}",
  subagent_type: "general-purpose",
  prompt: `
You are running the privacy-auditor skill as a subagent. Skip the normal interview — every answer is pre-filled here.

PRE-FILLED ANSWERS:
- Step 1 (Audit Mode): A (IaC)
- Step 2 (Domain Selection): 5 (all domains)
- Step 3 (PII Role): C (Both)
- Step 4 (PII Scope): B (ALL_STORES)
- Step 5 (Allowed Regions): {{REGION}}
- Target path: {{STAGING_PATH}}
- Return mode: inline

STEPS:
1. Read ${CLAUDE_SKILL_DIR}/../privacy-auditor/SKILL.md (specifically the "Subagent invocation" section).
2. Read all 4 domain files under ${CLAUDE_SKILL_DIR}/../privacy-auditor/domains/.
3. Execute Step 6 of that skill's flow against {{STAGING_PATH}}.
4. Return the full scorecard + PII inventory INLINE (do NOT write docs/privacy-report-*.md).
`
})
```

Wait for BOTH subagents to return.

**Failure handling:** if either audit subagent returns an error (e.g., the staging path had malformed HCL that couldn't be parsed), surface the error verbatim, mark audit as `failed` in the ADR's Audit Findings section, and still offer the user the promote/regenerate/keep-staging choice below.

---

## Step 11.5 — Design-Time Cost Estimate (infracost)

In the main agent (NOT a subagent), run `infracost` once per tfvars file the generation subagent emitted in Step 7. The iteration target is the same one used in Step 7: `{{VPC_LAYER_ENVS}}` for VPC-only patterns, `{{ENVIRONMENTS}}` for workload patterns, or both for composed patterns. This produces the design-time cost numbers that land in the ADR's "Cost estimate (design-time)" section.

**Binary check.** Run `command -v infracost` to detect whether infracost is installed. If it's not:
- Set `COST_NOTE = "_Skipped — `+"`infracost`"+` not installed. Run `+"`asdf plugin add infracost && asdf install infracost latest`"+` and re-generate for estimates._"`
- Set `COST_TABLE = "_No estimate available._"`
- Skip to Step 12.

**API key check.** infracost v0.10+ **hard-requires** an API key — there is no bundled-pricing fallback. Check both sources in order:
- `INFRACOST_API_KEY` environment variable, OR
- `~/.config/infracost/credentials.yml` (written by `infracost configure set api_key <key>`)

If neither is present:
- Set `COST_NOTE = "_Skipped — infracost requires an API key. Get a free key at https://dashboard.infracost.io, then run `+"`infracost configure set api_key <key>`"+` (or export `+"`INFRACOST_API_KEY=<key>`"+`) and re-generate._"`
- Set `COST_TABLE = "_No estimate available._"`
- Skip the per-env breakdown; continue to Step 12.

If either source has a key, pricing comes from the Infracost Cloud Pricing API (the only path in v0.10+).

**Per-env breakdown.** List the `.tfvars` files that actually exist under `{{STAGING_PATH}}` (recursively — multi-project layouts have them in subdirectories). For each one, first check whether a matching `<env>-usage.yml` file exists alongside it. If it does, pass `--usage-file <env>-usage.yml` for a traffic-aware estimate. If not, run without the flag (fixed-cost-only).

```bash
# Base command
infracost breakdown \
  --path {{STAGING_PATH}} \
  --terraform-var-file <env>.tfvars \
  --format json \
  --out-file /tmp/infracost-<env>.json 2>/dev/null

# If {{STAGING_PATH}}/<env>-usage.yml exists, add the flag:
#   --usage-file <env>-usage.yml
```

Parse `totalMonthlyCost` and the top 3 line-items by `monthlyCost` from each JSON file. If `infracost breakdown` exits non-zero for a specific env (e.g., Terraform references a resource type infracost doesn't price), record the env as `error` in the table but continue with the remaining envs.

**Table format.** Build `COST_TABLE` as:

```markdown
| Environment | Monthly cost (USD) | Top cost drivers |
|---|---|---|
| dev     | $XXX | `<top driver 1>`, `<top driver 2>`, `<top driver 3>` |
| staging | $XXX | ... |
| prod    | $XXX | ... |
```

**Note format.** Build `COST_NOTE` as one of:
- With API key + at least one env succeeded: `_Estimated via infracost (cloud pricing API) on {{date}}._`
- With API key but all envs had unpriced usage-dependent resources: `_Estimated via infracost (cloud pricing API) on {{date}}. **Fixed costs only** — usage-dependent resources reported as null; see Step 10's `+"`<env>-usage.yml`"+` to model expected traffic._`
- Skipped (no binary): see Binary check.
- Skipped (no API key): see API key check.

**Cleanup.** After parsing, remove `/tmp/infracost-*.json`.

**Do not block on errors.** infracost failing is a soft failure — the ADR still renders, the audit chain still ran, the user can still promote. Cost numbers are advisory.

---

## Step 12 — Integrate Findings Into ADR

In the main agent, read `{{STAGING_PATH}}/ADR.md`. Replace the six placeholder sections with content from the audit subagents and the Step 11.5 cost estimate:
- `{{security_scorecard_summary}}` → `✅ PASS (N) | ⚠️ PARTIAL (N) | ❌ FAIL (N)` from security subagent
- `{{security_findings_detail}}` → findings list (truncate to first 20 findings if more; link to full subagent output in a note)
- `{{privacy_scorecard_summary}}` → `✅ PASS (N) | 📋 REPORT (N) | ⚠️ PARTIAL (N) | ❌ FAIL (N)` from privacy subagent
- `{{privacy_findings_detail}}` → findings list + PII inventory
- `{{cost_estimate_note}}` → `COST_NOTE` from Step 11.5
- `{{cost_estimate_table}}` → `COST_TABLE` from Step 11.5

Summarise to the user:
> "Audit complete. Security: N PASS / N PARTIAL / **N FAIL**. Privacy: N PASS / N REPORT / N PARTIAL / **N FAIL**. Cost estimate: dev $X / staging $Y / prod $Z per month (design-time, advisory). Staging dir: `{{STAGING_PATH}}`. ADR with findings: `{{STAGING_PATH}}/ADR.md`."

If **any FAIL exists**, additionally print:
> "⚠️ Audit reported N FAIL findings. Review before promoting."

---

## Step 13 — Promote Decision

Ask:
> "What next?
> **A) promote** — move `{{STAGING_PATH}}` → `{{OUTPUT_PATH}}`
> **B) regenerate** — re-run generation with audit findings as additional input (single retry, no loop)
> **C) keep staging** — leave both dirs for manual editing"

### If A (promote):

Verify `{{OUTPUT_PATH}}` does not already exist. If it does:
> "Output path `{{OUTPUT_PATH}}` already exists. Options: (1) pick a new path, (2) back up the existing dir first, (3) cancel."

Then run:
```bash
mv {{STAGING_PATH}} {{OUTPUT_PATH}}
```

Confirm:
> "Promoted to `{{OUTPUT_PATH}}/`. Next steps: `cd {{OUTPUT_PATH}} && terraform init && terraform plan` to review before applying."

### If B (regenerate):

Re-dispatch the generation subagent from Step 10 with an additional instruction:
> "PREVIOUS AUDIT FINDINGS (address these during regeneration): <paste security + privacy findings that were FAIL or PARTIAL>. Regenerate to fix these; keep the same pattern selection."

Then re-run Step 11 (audit chain) and Step 12 (findings integration). This is a **single retry** — after regenerate, present Step 13 again WITHOUT the regenerate option (just promote / keep staging). This prevents infinite loops.

### If C (keep staging):

Confirm:
> "Left staging at `{{STAGING_PATH}}/` alongside existing `{{OUTPUT_PATH}}/` (if present). Edit manually, then run `mv {{STAGING_PATH}} {{OUTPUT_PATH}}` yourself when ready."

---

## Conflict Resolution

If interview answers conflict (e.g., `DATA_SENSITIVITY = regulated-PII` AND user later asks for "lowest cost possible"), pick the compliance-preserving default (Multi-AZ, CMK, Flow Logs, no Fargate Spot for prod) and note the trade-off explicitly in the ADR's Consequences section.

## Assumption Handling

Any interview answer the user declined to provide becomes an assumption. Record every assumption in the ADR's Context section under "Assumptions used (user did not specify):". Use sensible defaults:
- Peak traffic not specified → tier-based estimate (low = 50 RPS peak, medium = 500 RPS peak, high = 5000 RPS peak)
- Retention not specified → 7 days for logs, 30 days for backups
- Budget not specified → no budget cap; use pillar-optimal sizing

## Sibling Skills

- **`security-auditor`** — invoked by this skill's audit chain; also runnable standalone for ISO 27001 reports on non-generated infra
- **`privacy-auditor`** — invoked by this skill's audit chain; also runnable standalone for ISO 27701 reports
- **`cost-auditor`** — not invoked by this skill; run against generated output after deploy for live cost analysis
- **`ri-planner`** — not invoked by this skill; run after workload has real usage data

---

## Report Output Format

The skill's primary output is the generated directory tree:

```
{{OUTPUT_PATH}}/
├── ADR.md                     ← single source of truth: design + audit + cost
├── README.md                  ← operator guide (per-env workflow)
├── versions.tf                ← Terraform + provider version pins
├── main.tf                    ← provider + module wiring (or root resources for flat patterns)
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example   ← commented reference of every variable
├── dev.tfvars                 ← per-env values (one file per entry in ENVIRONMENTS)
├── staging.tfvars
├── prod.tfvars
├── dev-usage.yml              ← per-env infracost usage (only if pattern has Usage drivers)
├── staging-usage.yml
├── prod-usage.yml
├── modules/                   ← only if pattern uses modular layout
│   ├── networking/
│   ├── compute/
│   └── data/
└── lambdas/                   ← Lambda handler stubs if pattern uses Lambda
```

The ADR is the authoritative design document; terraform files are its implementation.
