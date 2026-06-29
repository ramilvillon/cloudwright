---
name: security-auditor
description: Use when working in an AWS project and asked to audit, verify, or check ISO 27001 compliance of Terraform/CloudFormation files or live AWS infrastructure.
---

# AWS ISO 27001 Security Auditor

## Overview

Audit AWS infrastructure for ISO 27001:2022 compliance (Annex A, Theme 4 — Technological Controls). Supports two modes:
- **IaC mode:** scan Terraform (.tf) or CloudFormation (.yaml/.json) files in the repo — no AWS credentials required
- **Live infra mode:** read-only checks against a running AWS account

Output: a structured compliance scorecard + self-contained remediation artifacts designed for both human review and downstream AI agents.

> **Bundled file paths.** Paths like `domains/iam.md` in this skill are relative to **this skill's own directory**, which your runtime announces when the skill activates. Read them with your normal file-reading tool. **When you pass such a path into a subagent, first resolve it to an absolute path** (prefix it with this skill's directory) — a subagent does not share this skill's directory context.

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
> "Which compliance domain would you like to check?
> **1) IAM & Access Control** (A.8.2, A.8.5)
> **2) Logging & Audit Trail** (A.8.15, A.8.16)
> **3) Threat Detection** (A.8.7, A.8.16)
> **4) Vulnerability Management** (A.8.8)
> **5) Network Security** (A.8.20–A.8.22)
> **6) Encryption** (A.8.24)
> **7) Data Protection** (A.8.11, A.8.12)
> **8) All domains**"

Wait for the user's response before continuing.

---

## Step 3 — Execute Audit

### IaC Mode (any domain selection)

Announce: _"Starting IaC compliance scan. Scanning Terraform and CloudFormation files for ISO 27001 gaps. No AWS credentials required. No files will be modified."_

Domain file map (use path(s) matching user's domain selection):
- 1 → `domains/iam.md`
- 2 → `domains/logging.md`
- 3 → `domains/threat-detection.md`
- 4 → `domains/vulnerability.md`
- 5 → `domains/network.md`
- 6 → `domains/encryption.md`
- 7 → `domains/data-protection.md`
- 8 → all 7 files above

Dispatch a subagent (general-purpose). Description: "ISO 27001 IaC compliance scan — [domain(s)]". Give it this prompt:

> You are an ISO 27001 IaC compliance scanner. Your job is read-only file analysis. Never modify any files.
>
> STEP 1 — Read the domain file(s) for your assigned domain(s):
> [Main agent: substitute the **absolute** path to the domain file(s) based on the user's selection (this skill's directory + /domains/<name>.md)]
>
> STEP 2 — Find IaC files in the repo using the Glob tool:
>   Patterns: **/*.tf, **/*.yaml, **/*.yml, **/*.json
>   Exclude: node_modules/, .git/, .terraform/, vendor/, package*.json, package-lock.json
>
> STEP 3 — Run every IaC check defined in the domain file(s) against the found files.
> Read relevant files with the Read tool. Grep for patterns with the Grep tool.
> Determine PASS, FAIL, or PARTIAL per the criteria in each domain file.
>
> STEP 4 — Build the compliance report using the Output Format defined in SKILL.md
> (absolute path: this skill's directory + /SKILL.md — main agent: substitute the actual absolute path in this prompt).
>
> STEP 5 — Save report to docs/security-report-YYYY-MM-DD.md (use today's date).
>
> Return a brief summary: X/Y controls passing, top 3 critical gaps.

Main agent: relay the subagent's summary to the user and point to the saved report file.

---

### Live Infra Mode — Single Domain

Announce: _"Starting AWS compliance audit (read-only) for [domain name]. No changes will be made."_

**Prerequisite — verify credentials:**
```bash
aws sts get-caller-identity
```
If this fails: stop and ask the user to configure AWS credentials (`aws configure` or set `AWS_PROFILE`).

Dispatch a subagent (general-purpose). Description: "ISO 27001 live infra audit — [domain name]". Give it this prompt:

> You are an ISO 27001 live AWS compliance auditor.
> HARD CONSTRAINT: read-only only. Never modify, delete, or create any AWS resource.
> Only use describe-*, list-*, get-* AWS CLI commands.
>
> STEP 1 — Read the domain file for your assigned domain:
> [Main agent: substitute the **absolute** path to the domain file (this skill's directory + /domains/<name>.md)]
>
> STEP 2 — Run all live infra checks defined in the domain file.
> Apply rate limiting: sleep 0.2 between sequential API calls.
>
> STEP 3 — Build the compliance report using the Output Format defined in SKILL.md
> (absolute path: this skill's directory + /SKILL.md — main agent: substitute the actual absolute path in this prompt).
>
> STEP 4 — Save report to docs/security-report-YYYY-MM-DD.md (use today's date).
>
> Return a brief summary: X/Y controls passing, top 3 critical gaps.

Main agent: relay the subagent's summary to the user and point to the saved report file.

---

### Live Infra Mode — All Domains

Announce: _"Starting full AWS ISO 27001 compliance audit (read-only). Checking all 7 domains in parallel. No changes will be made."_

**Prerequisite — verify credentials:**
```bash
aws sts get-caller-identity
```
If this fails: stop and ask the user to configure AWS credentials.

Dispatch a subagent (general-purpose). Description: "ISO 27001 full compliance audit — orchestrator". Give it this prompt:

> You are the ISO 27001 compliance audit orchestrator.
> HARD CONSTRAINT: read-only only. Never modify, delete, or create any AWS resource.
>
> STEP 1 — Setup:
>   mkdir -p docs/tmp
>
> STEP 2 — Read the SKILL.md output format before starting:
>   [absolute path: this skill's directory + /SKILL.md — caller: substitute the actual absolute path when dispatching this orchestrator]
>
> STEP 3 — Dispatch all 7 domain subagents in parallel (one per domain) in a single batch:
>
>   Agent 1 — IAM (no delay):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      Read [absolute path: this skill's directory + /domains/iam.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings (raw CLI output + PASS/FAIL per check) to docs/tmp/security-iam.md"
>
>   Agent 2 — Logging (sleep 5):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 5
>      Read [absolute path: this skill's directory + /domains/logging.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-logging.md"
>
>   Agent 3 — Threat Detection (sleep 10):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 10
>      Read [absolute path: this skill's directory + /domains/threat-detection.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-threat.md"
>
>   Agent 4 — Vulnerability (sleep 15):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 15
>      Read [absolute path: this skill's directory + /domains/vulnerability.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-vuln.md"
>
>   Agent 5 — Network (sleep 20):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 20
>      Read [absolute path: this skill's directory + /domains/network.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-network.md"
>
>   Agent 6 — Encryption (sleep 25):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 25
>      Read [absolute path: this skill's directory + /domains/encryption.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-encryption.md"
>
>   Agent 7 — Data Protection (sleep 30):
>     "HARD CONSTRAINT: read-only, never modify AWS.
>      sleep 30
>      Read [absolute path: this skill's directory + /domains/data-protection.md — orchestrator: substitute the actual absolute path]
>      Run all live infra checks. sleep 0.2 between sequential API calls.
>      Write findings to docs/tmp/security-data.md"
>
> STEP 4 — Wait for all 7 agents to complete. If any agent failed or did not create its output file, stop and report which domain(s) failed before proceeding.
>
> STEP 5 — Read all 7 temp files:
>   docs/tmp/security-iam.md
>   docs/tmp/security-logging.md
>   docs/tmp/security-threat.md
>   docs/tmp/security-vuln.md
>   docs/tmp/security-network.md
>   docs/tmp/security-encryption.md
>   docs/tmp/security-data.md
>
> STEP 6 — Merge all findings into the final report using the Output Format in SKILL.md.
>
> STEP 7 — Save to docs/security-report-YYYY-MM-DD.md (use today's date).
>
> STEP 8 — Clean up: rm -rf docs/tmp/
>
> Return brief summary: X/Y controls passing across all domains, top 5 critical gaps.

**Main agent rule:** relay only the orchestrator's summary to the user. Point to the report file. Do not run any `aws` CLI commands in the main context.

---

## Output Format

Every report — IaC or live infra — is saved to `docs/security-report-YYYY-MM-DD.md` using this exact structure:

### Part 1 — Compliance Scorecard

```markdown
# ISO 27001 Compliance Report — YYYY-MM-DD

> **READ-ONLY AUDIT.** No changes were made to infrastructure.
> All findings are recommendations. A human must review and apply them.

**Audit mode:** [IaC scan / Live AWS]
**Account:** [account-id] or N/A (IaC scan)
**Region:** [region] or N/A (IaC scan)
**Domain(s) audited:** [selected domain(s)]
**Generated by:** security-auditor

## Compliance Scorecard

| Control ID | Control Name              | Status      | Severity |
|------------|---------------------------|-------------|----------|
| A.8.2      | Privileged Access Rights  | ❌ FAIL     | Critical |
| A.8.5      | Secure Authentication     | ✅ PASS     | —        |
| A.8.15     | Logging                   | ⚠️ PARTIAL  | High     |

**Overall: X/Y controls passing (XX%)**
```

Status values:
- `✅ PASS` — all checks for this control pass
- `❌ FAIL` — one or more checks definitively fail
- `⚠️ PARTIAL` — some checks pass, some fail (e.g., CloudTrail enabled but integrity validation off). Use PARTIAL only when the control is partially implemented — if the primary resource is entirely absent, use FAIL.

### Part 2 — Findings with Remediation Artifacts

Each FAIL or PARTIAL control gets one self-contained block. Every block includes control ID + gap description + complete remediation — no cross-referencing between blocks.

Live infra finding format:
```markdown
---
## [CRITICAL] A.8.2 — Privileged Access Rights

**Gap:** Root account has 2 active access keys.
**Evidence required:** IAM credential report showing root access key status = inactive/none.

**Remediation:**
```bash
aws iam list-access-keys --user-name root
aws iam delete-access-key --access-key-id <AccessKeyId> --user-name root
```

**Closes:** A.8.2
```

IaC finding format:
```markdown
---
## [HIGH] A.8.24 — Use of Cryptography

**Gap:** `aws_s3_bucket.uploads` has no server-side encryption configured.
**File:** `infra/s3.tf:12`
**Evidence required:** S3 bucket configuration showing SSE-KMS or SSE-S3 enabled.

**Remediation (Terraform):**
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
```

**Closes:** A.8.24
```

---

## Subagent invocation (pre-filled interview contract)

Dispatching skills (e.g., `cloud-architect`) may invoke this auditor as a subagent with every interview answer pre-filled in the dispatch prompt. When invoked this way, the auditor **skips Steps 1–2 and executes Step 3 directly** using the supplied answers.

**Contract:** a dispatching subagent prompt is considered complete if it specifies:
- **Audit Mode** (A = IaC, B = Live infra)
- **Domain selection** (1–7 for a single domain, or 8 for all domains)
- **Target path** (for IaC mode) or **AWS profile** (for Live mode)
- **Return mode:** one of
  - `file` — write report to `docs/security-report-YYYY-MM-DD.md` as usual (standalone behaviour)
  - `inline` — return the full scorecard in the subagent's result and **do not** write to `docs/` (caller will embed findings)

When return mode is `inline`, the subagent returns the scorecard in the same structure it would write to the report file: header summary (PASS / PARTIAL / FAIL counts) followed by the findings list grouped by domain.

Example dispatch prompt (what a parent agent would send):
> "Invoke the `security-auditor` skill with these pre-filled answers: Mode A (IaC), Domain 8 (all), Target path `./infra.staging/`, Return mode `inline`. Skip Steps 1–2. The skill reads its own domain files. Execute Step 3 and return the scorecard."

If any required answer is missing from the dispatch prompt, the subagent should fall back to the normal interactive interview (ask the user).

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running write commands in live infra mode | Forbidden — only describe-*, list-*, get-* |
| Not waiting for both user answers before starting | Always ask mode AND domain before any action |
| Skipping credential check in live infra mode | Always run `aws sts get-caller-identity` first |
| Using orchestrator for a single domain | Only use orchestrator for option 8 (all domains) |
| Writing a finding without a complete remediation snippet | Every FAIL/PARTIAL block must have a complete code block |
| Marking PARTIAL when a required resource is entirely absent in IaC | No resource = FAIL, not PARTIAL |
