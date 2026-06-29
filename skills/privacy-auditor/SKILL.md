---
name: privacy-auditor
description: Use when working in an AWS project and asked to audit, verify, or check ISO 27701 privacy compliance (PII residency, retention, discovery, or sharing) of Terraform/CloudFormation files or live AWS infrastructure.
---

# AWS ISO 27701 Privacy Auditor

## Overview

Audit AWS infrastructure for ISO 27701:2019 (Privacy Information Management System) compliance. Supports two modes:
- **IaC mode:** scan Terraform (.tf) or CloudFormation (.yaml/.json) files in the repo — no AWS credentials required
- **Live infra mode:** read-only checks against a running AWS account

Output: a structured privacy scorecard + PII inventory + self-contained remediation artifacts.

**Scope:** infra-checkable subset of 27701 — residency, retention, PII discovery, cross-party sharing. Does not cover encryption-at-rest, access logging, or IAM; those belong to the sibling `security-auditor` (ISO 27001) skill. Every report footer points readers there.

## HARD CONSTRAINT: READ-ONLY AUDIT ONLY

**Live infra mode MUST NOT apply, execute, or deploy any changes to AWS infrastructure — ever.**

All AWS CLI calls must be read-only. The only permitted command verbs are: `describe-*`, `list-*`, `get-*`

If the user asks to apply a fix directly, respond: _"This skill is read-only. I can generate the exact commands/code for you to review and apply yourself."_

---

## Step 1 — Ask Audit Mode

Ask the user:
> "What would you like to audit?
> **A) IaC files** — scan Terraform (.tf) or CloudFormation (.yaml/.json) files in this repo (no AWS credentials needed)
> **B) Live AWS infrastructure** — run read-only checks against your running AWS account (requires configured AWS credentials)"

Wait for the user's response before continuing.

---

## Step 2 — Ask Domain Selection

Ask the user:
> "Which privacy domain would you like to check?
> **1) Data Residency** (A.7.5 / B.8.5)
> **2) Retention & Deletion** (A.7.4.7–8 / B.8.4)
> **3) PII Discovery & Inventory** (A.7.2.1, A.7.4.1 / B.8.4)
> **4) Transfer & Sharing** (A.7.5.3–4 / B.8.5.3–8)
> **5) All domains**"

Wait for the user's response before continuing.

---

## Step 3 — Ask PII Role

Ask the user:
> "What is this workload's role under ISO 27701?
> **A) Controller** — you determine the purposes and means of processing PII
> **B) Processor** — you process PII on behalf of another party
> **C) Both**"

Role answer maps to clause citations in the final report:
- Controller → cite only A.7.x clauses
- Processor → cite only B.8.x clauses
- Both → cite both

Wait for the user's response before continuing.

---

## Step 4 — Ask PII Scope

Ask the user:
> "How should PII-bearing resources be identified?
> **A) By tag** (enter tag key and value, e.g., `DataClass=PII`)
> **B) Audit all data stores** (S3, RDS, DynamoDB, EBS, EFS, Redshift)"

If A: ask for the tag key and value, store as `PII_TAG_KEY` and `PII_TAG_VALUE`.
If B: store scope as `ALL_STORES`.

The scope filter is passed to every domain subagent.

Wait for the user's response before continuing.

---

## Step 5 — Ask Allowed Regions (domain 1 or 5 only)

If the user selected domain 1 (Data Residency) or 5 (All domains), ask:
> "Which AWS regions is PII allowed to reside in? Comma-separated (e.g., `eu-west-1,eu-central-1`), or type `skip` to report regions without PASS/FAIL."

Store as `ALLOWED_REGIONS` (list) or `SKIP_REGION_CHECK=true`.

If `skip`, all residency checks that would otherwise compare against the allowlist downgrade to REPORT-ONLY.

If the user selected domain 2, 3, or 4, skip this step.

Wait for the user's response before continuing.

---

## Step 6 — Execute Audit

### IaC Mode (any domain selection)

Announce: _"Starting IaC privacy scan. Scanning Terraform and CloudFormation files for ISO 27701 gaps. No AWS credentials required. No files will be modified."_

Domain file map (use path(s) matching user's domain selection):
- 1 → `.claude/skills/privacy-auditor/domains/data-residency.md`
- 2 → `.claude/skills/privacy-auditor/domains/retention.md`
- 3 → `.claude/skills/privacy-auditor/domains/pii-discovery.md`
- 4 → `.claude/skills/privacy-auditor/domains/transfer-sharing.md`
- 5 → all 4 files above

Launch a **single subagent**:

```
Agent({
  description: "ISO 27701 IaC privacy scan — [domain(s)]",
  subagent_type: "general-purpose",
  prompt: `
You are an ISO 27701 IaC privacy scanner. Your job is read-only file analysis. Never modify any files.

CONTEXT (from interview):
- PII role: [Controller / Processor / Both]
- PII scope: [tag KEY=VALUE / ALL_STORES]
- Allowed regions: [comma-list or "skip"]

STEP 1 — Read the domain file(s) for your assigned domain(s):
[Main agent: substitute this with the actual file paths from the domain file map above, based on the user's selection.]

STEP 2 — Find IaC files in the repo using the Glob tool:
  Patterns: **/*.tf, **/*.yaml, **/*.yml, **/*.json
  Exclude: node_modules/, .git/, .terraform/, vendor/, package*.json, package-lock.json

STEP 3 — Run every IaC check defined in the domain file(s) against the found files.
Apply the scope filter: if tag-based, only consider resources carrying PII_TAG_KEY=PII_TAG_VALUE; if ALL_STORES, treat every data store as in-scope.
Determine PASS / FAIL / PARTIAL / REPORT per the criteria in each domain file.
Filter clause citations by role: Controller → A.7.x only, Processor → B.8.x only, Both → cite both.

STEP 4 — Build the privacy report using the Output Format defined in:
  .claude/skills/privacy-auditor/SKILL.md

STEP 5 — Save report to docs/privacy-report-YYYY-MM-DD.md (use today's date).

Return a brief summary: X/Y PASS/FAIL controls passing, Z REPORT items surfaced, top 3 critical gaps.
  `
})
```

Main agent: relay the subagent's summary to the user and point to the saved report file.

---

### Live Infra Mode — Single Domain

Announce: _"Starting AWS privacy audit (read-only) for [domain name]. No changes will be made."_

**Prerequisite — verify credentials:**
```bash
aws sts get-caller-identity
```
If this fails: stop and ask the user to configure AWS credentials (`aws configure` or set `AWS_PROFILE`).

Launch a **single subagent**:

```
Agent({
  description: "ISO 27701 live infra privacy audit — [domain name]",
  subagent_type: "general-purpose",
  prompt: `
You are an ISO 27701 live AWS privacy auditor.
HARD CONSTRAINT: read-only only. Never modify, delete, or create any AWS resource.
Only use describe-*, list-*, get-* AWS CLI commands.

CONTEXT (from interview):
- PII role: [Controller / Processor / Both]
- PII scope: [tag KEY=VALUE / ALL_STORES]
- Allowed regions: [comma-list or "skip"]

STEP 1 — Read the domain file for your assigned domain:
[domain file path from .claude/skills/privacy-auditor/domains/]

STEP 2 — Build the PII-scoped resource list first.
If scope is tag-based: list resources carrying PII_TAG_KEY=PII_TAG_VALUE using the Resource Groups Tagging API.
If scope is ALL_STORES: list all S3 buckets, RDS instances, DynamoDB tables, EBS volumes, EFS file systems, Redshift clusters in the account.
Store this list as the PII inventory — every subsequent check filters to these resources only.

STEP 3 — Run all live infra checks defined in the domain file against the PII-scoped resources.
Apply rate limiting: sleep 0.2 between sequential API calls.
Filter clause citations by role.

STEP 4 — Build the privacy report using the Output Format defined in:
  .claude/skills/privacy-auditor/SKILL.md

STEP 5 — Save report to docs/privacy-report-YYYY-MM-DD.md (use today's date).

Return a brief summary: X/Y PASS/FAIL controls passing, Z REPORT items surfaced, top 3 critical gaps.
  `
})
```

Main agent: relay the subagent's summary to the user and point to the saved report file.

---

### Live Infra Mode — All Domains

Announce: _"Starting full AWS ISO 27701 privacy audit (read-only). Checking all 4 domains in parallel. No changes will be made."_

**Prerequisite — verify credentials:**
```bash
aws sts get-caller-identity
```
If this fails: stop and ask the user to configure AWS credentials.

Launch an **orchestrator subagent**:

```
Agent({
  description: "ISO 27701 full privacy audit — orchestrator",
  subagent_type: "general-purpose",
  prompt: `
You are the ISO 27701 privacy audit orchestrator.
HARD CONSTRAINT: read-only only. Never modify, delete, or create any AWS resource.

CONTEXT (from interview):
- PII role: [Controller / Processor / Both]
- PII scope: [tag KEY=VALUE / ALL_STORES]
- Allowed regions: [comma-list or "skip"]

STEP 1 — Setup:
  mkdir -p docs/tmp

STEP 2 — Read the SKILL.md output format before starting:
  .claude/skills/privacy-auditor/SKILL.md

STEP 3 — Launch all 4 domain agents IN PARALLEL (single Agent tool message with all 4 calls):

  Agent 1 — Data Residency (no delay):
    "HARD CONSTRAINT: read-only, never modify AWS.
     CONTEXT: role=[...], scope=[...], regions=[...]
     Read .claude/skills/privacy-auditor/domains/data-residency.md
     Build PII-scoped resource list first (see SKILL.md STEP 2).
     Run all live infra checks. sleep 0.2 between sequential API calls.
     Write findings (raw CLI output + PASS/FAIL/REPORT per check) to docs/tmp/privacy-residency.md"

  Agent 2 — Retention (sleep 5):
    "HARD CONSTRAINT: read-only, never modify AWS.
     CONTEXT: role=[...], scope=[...]
     sleep 5
     Read .claude/skills/privacy-auditor/domains/retention.md
     Build PII-scoped resource list first.
     Run all live infra checks. sleep 0.2 between sequential API calls.
     Write findings to docs/tmp/privacy-retention.md"

  Agent 3 — PII Discovery (sleep 10):
    "HARD CONSTRAINT: read-only, never modify AWS.
     CONTEXT: role=[...], scope=[...]
     sleep 10
     Read .claude/skills/privacy-auditor/domains/pii-discovery.md
     Build PII-scoped resource list first.
     Run all live infra checks. sleep 0.2 between sequential API calls.
     Write findings to docs/tmp/privacy-pii.md"

  Agent 4 — Transfer & Sharing (sleep 15):
    "HARD CONSTRAINT: read-only, never modify AWS.
     CONTEXT: role=[...], scope=[...]
     sleep 15
     Read .claude/skills/privacy-auditor/domains/transfer-sharing.md
     Build PII-scoped resource list first.
     Run all live infra checks. sleep 0.2 between sequential API calls.
     Write findings to docs/tmp/privacy-transfer.md"

STEP 4 — Wait for all 4 agents to complete. If any agent failed or did not create its output file, stop and report which domain(s) failed before proceeding.

STEP 5 — Read all 4 temp files:
  docs/tmp/privacy-residency.md
  docs/tmp/privacy-retention.md
  docs/tmp/privacy-pii.md
  docs/tmp/privacy-transfer.md

STEP 6 — Merge all findings into the final report using the Output Format in SKILL.md.
Filter clause citations by role before merging.

STEP 7 — Save to docs/privacy-report-YYYY-MM-DD.md (use today's date).

STEP 8 — Clean up: rm -rf docs/tmp/

Return brief summary: X/Y PASS/FAIL controls passing across all domains, Z REPORT items surfaced, top 5 critical gaps.
  `
})
```

**Main agent rule:** relay only the orchestrator's summary to the user. Point to the report file. Do not run any `aws` CLI commands in the main context.

---

## Output Format

Every report — IaC or live infra — is saved to `docs/privacy-report-YYYY-MM-DD.md` using this exact structure:

### Part 1 — Header + PII Inventory

```markdown
# ISO 27701 Privacy Report — YYYY-MM-DD

> **READ-ONLY AUDIT.** No changes were made to infrastructure.
> All findings are recommendations. A human must review and apply them.

**Audit mode:** [IaC scan / Live AWS]
**Account:** [account-id] or N/A (IaC scan)
**PII role:** [Controller / Processor / Both]
**PII scope:** [tag `KEY=VALUE` / all data stores]
**Allowed regions:** [list] or "not specified"
**Domain(s) audited:** [selected domain(s)]
**Generated by:** privacy-auditor

## PII Inventory

| Resource type | Count | Regions in use              |
|---------------|-------|-----------------------------|
| S3 buckets    | N     | region-a, region-b          |
| RDS instances | N     | region-a                    |
| DynamoDB      | N     | region-a (X), region-b global (Y) |
| EBS volumes   | N     | region-a                    |
| EFS           | N     | region-a                    |
| Redshift      | N     | region-a                    |
```

If scope returns zero resources, show an empty inventory with the note: _"No PII-scoped resources found. Verify your scope selection (Step 4) is correct."_

For tag-based scope, include one row per distinct resource type returned by the Resource Groups Tagging API (the template rows above are for ALL_STORES scope — add or remove rows as needed to match the actual inventory).

### Part 2 — Scorecard

```markdown
## Compliance Scorecard

| Clause   | Name                           | Status       | Severity |
|----------|--------------------------------|--------------|----------|
| A.7.5.1  | Identify basis for transfer    | ❌ FAIL      | Critical |
| A.7.4.8  | PII erasure                    | ⚠️ PARTIAL   | High     |
| A.7.4.7  | PII retention                  | 📋 REPORT    | —        |
| A.7.2.1  | Identify and document purpose  | ✅ PASS      | —        |

**Overall: X/Y PASS/FAIL clauses passing (XX%) — Z REPORT items surfaced for human review**
```

Status values:
- `✅ PASS` — all checks for this clause pass
- `❌ FAIL` — one or more checks definitively fail
- `⚠️ PARTIAL` — some checks pass, some fail; use only when control is partially implemented. If the primary resource is entirely absent, use FAIL.
- `📋 REPORT` — facts surfaced; no verdict applied

REPORT items do not count against the overall percentage.

### Part 3 — Findings with Remediation Artifacts

Each FAIL or PARTIAL clause gets one self-contained block:

```markdown
---
## [CRITICAL] A.7.5.1 — Identify Basis for PII Transfer

**Gap:** Bucket `user-uploads` replicates to account `123456789012` in `us-east-1`; US is outside the declared allowlist of `eu-west-1, eu-central-1`.
**Evidence required:** S3 replication configuration showing destination; DPA confirming transfer basis (SCCs / adequacy decision).

**Remediation (Terraform):**
```hcl
resource "aws_s3_bucket_replication_configuration" "user_uploads" {
  bucket = aws_s3_bucket.user_uploads.id
  role   = aws_iam_role.replication.arn
  rule {
    id     = "compliance-eu-only"
    status = "Enabled"
    destination {
      bucket        = "arn:aws:s3:::user-uploads-replica-eu"
      storage_class = "STANDARD_IA"
    }
  }
}
```

**Closes:** A.7.5.1
```

Each REPORT clause gets a lighter block (no remediation; the fact is the deliverable):

Use `[REPORT]` as the bracket label — REPORT findings have no severity.

```markdown
---
## [REPORT] A.7.5.3 — PII Disclosure to Third Parties

**Finding:** Bucket `user-uploads` replicates to account `123456789012` (us-east-1).
**Clause:** A.7.5.3 — records of PII disclosures to third parties.
**Human review required:** Confirm this destination account is authorized in your ROPA/DPA. If not authorized, update the bucket replication config to remove the destination.
```

### Report Footer

Every report ends with:

> _This privacy audit does not cover encryption-at-rest, access logging, or IAM. For those controls, run `security-auditor` (ISO 27001)._

---

## Subagent invocation (pre-filled interview contract)

Dispatching skills (e.g., `cloud-architect`) may invoke this auditor as a subagent with every interview answer pre-filled in the dispatch prompt. When invoked this way, the auditor **skips Steps 1–5 and executes Step 6 directly** using the supplied answers.

**Contract:** a dispatching subagent prompt is considered complete if it specifies:
- **Audit Mode** (A = IaC, B = Live infra)
- **Domain selection** (1–4 for a single domain, or 5 for all domains)
- **PII Role** (A = Controller, B = Processor, C = Both)
- **PII Scope** — either (A) tag filter with `PII_TAG_KEY` and `PII_TAG_VALUE`, or (B) `ALL_STORES`
- **Allowed Regions** — comma-separated AWS region list (used by Data Residency domain)
- **Target path** (for IaC mode) or **AWS profile** (for Live mode)
- **Return mode:** one of
  - `file` — write report to `docs/privacy-report-YYYY-MM-DD.md` as usual (standalone behaviour)
  - `inline` — return the full scorecard + PII inventory in the subagent's result and **do not** write to `docs/` (caller will embed findings)

When return mode is `inline`, the subagent returns the same structured content it would write to the report file: scorecard header (PASS / PARTIAL / REPORT / FAIL counts) + PII inventory + findings list grouped by domain.

Example dispatch prompt:
> "You are running the `privacy-auditor` skill. Pre-filled answers: Mode A (IaC), Domain 5 (all domains), PII Role C (Both), PII Scope B (ALL_STORES), Allowed Regions `ap-southeast-1`, Target path `./infra.staging/`, Return mode `inline`. Skip Steps 1–5. Read `.claude/skills/privacy-auditor/SKILL.md` and all four domain files. Execute Step 6. Return the scorecard + PII inventory as the subagent result."

If any required answer is missing from the dispatch prompt, the subagent should fall back to the normal interactive interview (ask the user).

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running write commands in live infra mode | Forbidden — only describe-*, list-*, get-* |
| Skipping one of the 5 interview steps | Always ask all applicable steps before any dispatch |
| Skipping credential check in live infra mode | Always run `aws sts get-caller-identity` first |
| Using orchestrator for a single domain | Only use orchestrator for option 5 (all domains) |
| Writing a FAIL/PARTIAL finding without a complete remediation snippet | Every FAIL/PARTIAL block must have a complete code block |
| Writing a REPORT finding with a remediation snippet | REPORT blocks have NO remediation — the fact is the deliverable |
| Marking PARTIAL when a required resource is entirely absent | No resource = FAIL, not PARTIAL |
| Applying PASS/FAIL to residency when user said `skip` | Residency checks downgrade to REPORT when allowlist is skipped |
| Citing both A.7.x and B.8.x for a Controller-only role | Filter clause citations by role before writing findings |
| Missing the report footer | Every report ends with the sibling-skill pointer |
