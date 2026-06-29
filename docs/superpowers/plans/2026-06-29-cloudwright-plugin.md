# Cloudwright Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package 5 existing AWS Well-Architected skills as a public Claude Code plugin named `cloudwright`, distributed via a single-plugin marketplace repo.

**Architecture:** Copy the 5 skills verbatim from `width-infra/.claude/skills/`, rewrite their hardcoded `.claude/skills/...` file paths to the plugin-portable `${CLAUDE_SKILL_DIR}` variable, add `plugin.json` + `marketplace.json` manifests, add thin slash-command aliases, and ship README + MIT LICENSE. Skill *logic* is never altered — only file-path references change.

**Tech Stack:** Claude Code plugin format (`.claude-plugin/`), Markdown skills, JSON manifests, git. No build step, no runtime dependencies.

## Global Constraints

- Plugin name: `cloudwright`. Version: `0.1.0`. License: `MIT`. Author: `Ramil Villon`, url `https://github.com/ramilvillon`, email `ramilvillon@gmail.com`.
- Source skills live at `/Users/ramil/projects/work/width/repo/width-infra/.claude/skills/` — read-only source; copy, never move.
- Target repo root: `/Users/ramil/projects/personal/cloudwright` (git-initialized).
- All manifest path fields must be relative and start with `./`. Manifests live in `.claude-plugin/`; skills/commands live at repo root (NOT inside `.claude-plugin/`).
- Skills auto-discover from `skills/` (one subdir per skill, each with `SKILL.md` + support dirs). Commands auto-discover from `commands/` (flat `.md` files). Neither needs declaring in `plugin.json`.
- **Path rewrite rule:** `${CLAUDE_SKILL_DIR}` is the documented SKILL.md-prose variable for a skill referencing its OWN bundled files. `${CLAUDE_PLUGIN_ROOT}` does NOT reliably expand in SKILL.md prose — do not use it there.
  - Self-reference: `.claude/skills/<skill>/X` → `${CLAUDE_SKILL_DIR}/X`
  - Cross-reference (only in cloud-architect → auditors): `.claude/skills/<auditor>/X` → `${CLAUDE_SKILL_DIR}/../<auditor>/X`
- **Confirmed reference inventory** (all 49 refs are in SKILL.md files only; support dirs are clean): cloud-architect 14 (10 self + 4 cross), security-auditor 20 (all self), privacy-auditor 13 (all self), cost-auditor 1 (self), ri-planner 1 (self).
- Never alter the skills' read-only / no-AWS-writes / no-`terraform apply` posture or any audit logic. Only path strings change.
- Commit after every task.

---

### Task 1: Plugin + marketplace manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: a loadable plugin manifest (`name: cloudwright`) and a single-plugin marketplace pointing at `source: "./"`. All later tasks add files that these manifests auto-discover.

- [ ] **Step 1: Create the plugin manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "cloudwright",
  "displayName": "Cloudwright",
  "version": "0.1.0",
  "description": "AWS Well-Architected design plus read-only governance auditors: architecture generation (ADR + Terraform), ISO 27001 security, ISO 27701 privacy, cost optimization, and Reserved Instance planning. Writes local files only — never applies to AWS.",
  "author": {
    "name": "Ramil Villon",
    "email": "ramilvillon@gmail.com",
    "url": "https://github.com/ramilvillon"
  },
  "homepage": "https://github.com/ramilvillon/cloudwright",
  "repository": "https://github.com/ramilvillon/cloudwright",
  "license": "MIT",
  "keywords": ["aws", "terraform", "well-architected", "iso-27001", "iso-27701", "cost-optimization", "security-audit", "privacy", "reserved-instances", "iac"]
}
```

- [ ] **Step 2: Create the marketplace manifest**

Create `.claude-plugin/marketplace.json`. Note: the marketplace `name` is the `@handle` users reference at install (`<plugin>@<marketplace>`); we use `ramilvillon` so the install reads `cloudwright@ramilvillon`.

```json
{
  "name": "ramilvillon",
  "owner": {
    "name": "Ramil Villon",
    "email": "ramilvillon@gmail.com",
    "url": "https://github.com/ramilvillon"
  },
  "description": "Ramil Villon's Claude Code plugins.",
  "plugins": [
    {
      "name": "cloudwright",
      "source": "./",
      "description": "AWS Well-Architected design plus read-only governance auditors (security, privacy, cost, RI).",
      "version": "0.1.0",
      "license": "MIT",
      "keywords": ["aws", "terraform", "well-architected", "governance"]
    }
  ]
}
```

- [ ] **Step 3: Verify both manifests are valid JSON**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
jq -e . .claude-plugin/plugin.json >/dev/null && echo "plugin.json OK"
jq -e . .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json OK"
jq -e '.plugins[0].source == "./" and .name == "ramilvillon"' .claude-plugin/marketplace.json
jq -e '.name == "cloudwright"' .claude-plugin/plugin.json
```
Expected: `plugin.json OK`, `marketplace.json OK`, then two `true` lines.

- [ ] **Step 4: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add .claude-plugin/
git commit -m "Add cloudwright plugin and marketplace manifests"
```

---

### Task 2: Copy the 5 skills verbatim

**Files:**
- Create: `skills/cloud-architect/` (+ `patterns/ pillars/ templates/ evals/`)
- Create: `skills/security-auditor/` (+ `domains/`)
- Create: `skills/privacy-auditor/` (+ `domains/`)
- Create: `skills/cost-auditor/`
- Create: `skills/ri-planner/`

**Interfaces:**
- Consumes: nothing.
- Produces: `skills/<name>/SKILL.md` for all 5 skills with support dirs intact. Tasks 3–4 edit these SKILL.md files in place.

This task is a pure copy — no edits — to establish a clean baseline commit before any rewriting.

- [ ] **Step 1: Copy all 5 skill directories**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
mkdir -p skills
SRC=/Users/ramil/projects/work/width/repo/width-infra/.claude/skills
for s in cloud-architect security-auditor privacy-auditor cost-auditor ri-planner; do
  cp -R "$SRC/$s" "skills/$s"
done
```

- [ ] **Step 2: Verify the tree and that all 5 SKILL.md exist**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
ls skills
for s in cloud-architect security-auditor privacy-auditor cost-auditor ri-planner; do
  test -f "skills/$s/SKILL.md" && echo "$s/SKILL.md OK" || echo "MISSING $s/SKILL.md"
done
ls skills/security-auditor/domains | wc -l   # expect 7
ls skills/privacy-auditor/domains | wc -l    # expect 4
ls skills/cloud-architect/patterns | wc -l   # expect >= 10
```
Expected: 5 `... OK` lines, then `7`, `4`, and a number ≥ 10.

- [ ] **Step 3: Confirm the reference inventory baseline (49 refs, SKILL.md only)**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
grep -rno "\.claude/skills" skills | wc -l                       # expect 49
grep -rl "\.claude/skills" skills | grep -v "SKILL.md" || echo "only SKILL.md (good)"
```
Expected: `49`, then `only SKILL.md (good)` (no support-dir files contain refs).

- [ ] **Step 4: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add skills/
git commit -m "Add 5 AWS skills verbatim (pre-rewrite baseline)"
```

---

### Task 3: Rewrite self-references to `${CLAUDE_SKILL_DIR}`

**Files:**
- Modify: `skills/cloud-architect/SKILL.md` (10 self-refs; 4 cross-refs left for Task 4)
- Modify: `skills/security-auditor/SKILL.md` (20 self-refs)
- Modify: `skills/privacy-auditor/SKILL.md` (13 self-refs)
- Modify: `skills/cost-auditor/SKILL.md` (1 self-ref, also strips a `<project-root>/` prefix and fixes `skill.md`→`SKILL.md`)
- Modify: `skills/ri-planner/SKILL.md` (1 self-ref, strips `<project-root>/`)

**Interfaces:**
- Consumes: the verbatim SKILL.md files from Task 2.
- Produces: SKILL.md files whose own-file references resolve via `${CLAUDE_SKILL_DIR}`. After this task the ONLY remaining `.claude/skills` strings are the 4 cross-refs in `skills/cloud-architect/SKILL.md` (to `security-auditor` and `privacy-auditor`).

- [ ] **Step 1: Rewrite the three skills whose refs are 100% self-references**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
perl -pi -e 's{\.claude/skills/cloud-architect/}{\$\{CLAUDE_SKILL_DIR\}/}g'   skills/cloud-architect/SKILL.md
perl -pi -e 's{\.claude/skills/security-auditor/}{\$\{CLAUDE_SKILL_DIR\}/}g'  skills/security-auditor/SKILL.md
perl -pi -e 's{\.claude/skills/privacy-auditor/}{\$\{CLAUDE_SKILL_DIR\}/}g'   skills/privacy-auditor/SKILL.md
```

(The cloud-architect command rewrites only its 10 self-refs; its `security-auditor`/`privacy-auditor` cross-refs do not match `cloud-architect/` and are left for Task 4.)

- [ ] **Step 2: Rewrite cost-auditor and ri-planner (strip `<project-root>/`, normalize filename)**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
perl -pi -e 's{<project-root>/\.claude/skills/cost-auditor/skill\.md}{\$\{CLAUDE_SKILL_DIR\}/SKILL.md}g'  skills/cost-auditor/SKILL.md
perl -pi -e 's{<project-root>/\.claude/skills/ri-planner/SKILL\.md}{\$\{CLAUDE_SKILL_DIR\}/SKILL.md}g'    skills/ri-planner/SKILL.md
```

- [ ] **Step 3: Verify all self-refs are gone and only the 4 cross-refs remain**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
echo "--- self-ref skills (expect 0 each) ---"
grep -c "\.claude/skills/security-auditor" skills/security-auditor/SKILL.md
grep -c "\.claude/skills/privacy-auditor"  skills/privacy-auditor/SKILL.md
grep -c "\.claude/skills/cost-auditor"     skills/cost-auditor/SKILL.md
grep -c "\.claude/skills/ri-planner"       skills/ri-planner/SKILL.md
grep -c "\.claude/skills/cloud-architect"  skills/cloud-architect/SKILL.md
echo "--- remaining refs anywhere (expect exactly 4, all in cloud-architect) ---"
grep -rno "\.claude/skills" skills | wc -l
grep -rn "\.claude/skills" skills
echo "--- skill-dir var present (expect many) ---"
grep -rc "CLAUDE_SKILL_DIR" skills | grep -v ':0'
```
Expected: five `0` lines; total remaining `4`; the 4 printed lines are all `skills/cloud-architect/SKILL.md` referencing `security-auditor`/`privacy-auditor`; and several files report `${CLAUDE_SKILL_DIR}` occurrences.

- [ ] **Step 4: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add skills/
git commit -m "Rewrite skill self-references to \${CLAUDE_SKILL_DIR}"
```

---

### Task 4: Rewrite cloud-architect cross-skill auditor references

**Files:**
- Modify: `skills/cloud-architect/SKILL.md` (4 cross-refs: lines invoking the security + privacy auditors as subagents)

**Interfaces:**
- Consumes: `skills/cloud-architect/SKILL.md` from Task 3 (still holds 4 `.claude/skills/<auditor>/` strings).
- Produces: a SKILL.md where the audit-chain subagent prompts reference the sibling auditors via `${CLAUDE_SKILL_DIR}/../<auditor>/`. Because all skills sit under `skills/`, `${CLAUDE_SKILL_DIR}/../security-auditor/` resolves to the bundled auditor regardless of install location. After this task, zero `.claude/skills` strings remain anywhere.

- [ ] **Step 1: Rewrite the 4 sibling references**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
perl -pi -e 's{\.claude/skills/security-auditor/}{\$\{CLAUDE_SKILL_DIR\}/../security-auditor/}g; s{\.claude/skills/privacy-auditor/}{\$\{CLAUDE_SKILL_DIR\}/../privacy-auditor/}g' skills/cloud-architect/SKILL.md
```

- [ ] **Step 2: Verify zero `.claude/skills` strings remain in the whole plugin**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
grep -rn "\.claude/skills" skills && echo "STILL FOUND (bad)" || echo "0 remaining (good)"
echo "--- confirm the 4 sibling paths now point at ../ ---"
grep -n "CLAUDE_SKILL_DIR}/../security-auditor" skills/cloud-architect/SKILL.md
grep -n "CLAUDE_SKILL_DIR}/../privacy-auditor"  skills/cloud-architect/SKILL.md
```
Expected: `0 remaining (good)`, then 2 lines for security-auditor and 2 lines for privacy-auditor (4 total).

- [ ] **Step 3: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add skills/cloud-architect/SKILL.md
git commit -m "Rewrite cloud-architect audit-chain refs to sibling \${CLAUDE_SKILL_DIR}/../"
```

---

### Task 5: Slash-command aliases

**Files:**
- Create: `commands/architect.md`
- Create: `commands/security-audit.md`
- Create: `commands/privacy-audit.md`
- Create: `commands/cost-audit.md`
- Create: `commands/ri-plan.md`

**Interfaces:**
- Consumes: the 5 installed skills (invoked by fully-qualified `cloudwright:<skill>` name).
- Produces: 5 explicit user entry points (`/cloudwright:architect`, `/cloudwright:security-audit`, `/cloudwright:privacy-audit`, `/cloudwright:cost-audit`, `/cloudwright:ri-plan`). Command names deliberately differ from skill names to avoid the `/cloudwright:<name>` collision skills already create. `disable-model-invocation: true` keeps auto-triggering the job of the skills' own descriptions; commands are user-explicit shortcuts.

- [ ] **Step 1: Create `commands/architect.md`**

```markdown
---
description: Design an AWS Well-Architected architecture — generates an ADR (MADR), a Mermaid diagram, and a parameterized Terraform project, then runs the security + privacy auditors against the generated output. Writes local files only; never applies to AWS.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:cloud-architect` skill. If the user has not described a target workload or pointed to a requirements document, ask for it before proceeding.
```

- [ ] **Step 2: Create `commands/security-audit.md`**

```markdown
---
description: Run a read-only ISO 27001:2022 security compliance audit of Terraform/CloudFormation files or live AWS infrastructure. Produces a scorecard plus remediation artifacts. Never modifies AWS.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:security-auditor` skill. Let the skill run its normal interview (audit mode: IaC vs live; domain selection) unless the user has already specified those.
```

- [ ] **Step 3: Create `commands/privacy-audit.md`**

```markdown
---
description: Run a read-only ISO 27701:2019 privacy audit (PII residency, retention, discovery, sharing) of Terraform/CloudFormation files or live AWS infrastructure. Produces a privacy scorecard plus PII inventory. Never modifies AWS.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:privacy-auditor` skill. Let the skill run its normal interview (audit mode, domains, PII role/scope, allowed regions) unless the user has already specified those.
```

- [ ] **Step 4: Create `commands/cost-audit.md`**

```markdown
---
description: Run a read-only AWS cost audit across all major spend domains and produce prioritized, ready-to-apply recommendations. Never modifies AWS infrastructure.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:cost-auditor` skill.
```

- [ ] **Step 5: Create `commands/ri-plan.md`**

```markdown
---
description: Run a read-only Reserved Instance coverage analysis across EC2, RDS, ElastiCache, and OpenSearch, and produce a prioritized purchase plan for human review. Never purchases anything.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:ri-planner` skill.
```

- [ ] **Step 6: Verify all 5 command files exist with frontmatter**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
for c in architect security-audit privacy-audit cost-audit ri-plan; do
  f="commands/$c.md"
  test -f "$f" && head -1 "$f" | grep -q '^---$' && echo "$f OK" || echo "BAD $f"
done
```
Expected: 5 `... OK` lines.

- [ ] **Step 7: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add commands/
git commit -m "Add slash-command aliases for the 5 skills"
```

---

### Task 6: README and MIT LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: everything above (documents the install flow + skill/command names).
- Produces: public-facing docs and the open-source license. No code depends on these.

- [ ] **Step 1: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Ramil Villon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create `README.md`**

```markdown
# Cloudwright

Build AWS clouds, well — and verify them. Cloudwright is a [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin bundling one architecture-design skill and four read-only governance auditors, all centered on AWS and Terraform.

## Safety posture

Every skill is **read-only against AWS**. The plugin writes local files (Terraform, reports, ADRs) but **never** calls AWS write APIs and **never** runs `terraform apply` / `destroy`. Recommendations are emitted for a human to review and run. This is a hard constraint baked into each skill.

## Skills

| Skill | What it does |
|-------|--------------|
| `cloud-architect` | Turns a workload description into a Well-Architected AWS design: ADR (MADR) + Mermaid diagram + parameterized Terraform in a staging dir, then auto-runs the security + privacy auditors before you promote it. |
| `security-auditor` | ISO 27001:2022 compliance audit of Terraform/CloudFormation files or live AWS infra. Scorecard + remediation artifacts. |
| `privacy-auditor` | ISO 27701:2019 privacy audit — PII residency, retention, discovery, sharing. Scorecard + PII inventory. |
| `cost-auditor` | Structured read-only AWS cost audit across all major domains; prioritized, ready-to-apply recommendations. |
| `ri-planner` | Reserved Instance coverage analysis across EC2, RDS, ElastiCache, OpenSearch; prioritized purchase plan. |

The skills auto-trigger from natural requests (e.g. "audit this Terraform for ISO 27001", "where can I cut AWS cost?"). Each also has an explicit slash command.

## Slash commands

- `/cloudwright:architect` — design an AWS architecture
- `/cloudwright:security-audit` — ISO 27001 audit
- `/cloudwright:privacy-audit` — ISO 27701 audit
- `/cloudwright:cost-audit` — cost audit
- `/cloudwright:ri-plan` — Reserved Instance plan

## Install

```
/plugin marketplace add ramilvillon/cloudwright
/plugin install cloudwright@ramilvillon
```

Then invoke a skill by description or run one of the slash commands above.

## Requirements

- Claude Code with plugin support.
- For **live** audit / cost / RI modes: AWS credentials with read-only access (the skills use only `describe-*`, `list-*`, `get-*` calls). For **IaC** mode (scanning `.tf` / CloudFormation files): no AWS credentials needed.

## License

MIT © Ramil Villon
```

- [ ] **Step 3: Verify both files exist and are non-empty**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
test -s README.md && echo "README OK"
grep -q "MIT License" LICENSE && grep -q "Ramil Villon" LICENSE && echo "LICENSE OK"
```
Expected: `README OK`, `LICENSE OK`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ramil/projects/personal/cloudwright
git add README.md LICENSE
git commit -m "Add README and MIT license"
```

---

### Task 7: Live smoke test (human-in-the-loop acceptance)

**Files:** none (verification only).

**Interfaces:**
- Consumes: the fully assembled plugin.
- Produces: empirical confirmation that (a) the plugin installs, (b) all 5 skills + 5 commands register under the `cloudwright:` namespace, and (c) `${CLAUDE_SKILL_DIR}` actually resolves at runtime so skills can read their own support files and cloud-architect's audit chain reaches the sibling auditors.

> This task requires a live Claude Code session and cannot be fully scripted (plugin install + skill triggering are interactive). It is the real proof of the `${CLAUDE_SKILL_DIR}` mechanism assumed in Tasks 3–4.

- [ ] **Step 1: Pre-flight structure check (scriptable)**

Run:
```bash
cd /Users/ramil/projects/personal/cloudwright
jq -e . .claude-plugin/plugin.json >/dev/null && echo "plugin.json valid"
jq -e . .claude-plugin/marketplace.json >/dev/null && echo "marketplace.json valid"
ls skills | wc -l        # expect 5
ls commands | wc -l       # expect 5
grep -rn "\.claude/skills" skills && echo "LEFTOVER REFS (bad)" || echo "no leftover refs (good)"
git status --short        # expect clean
```
Expected: both `valid` lines, `5`, `5`, `no leftover refs (good)`, clean status.

- [ ] **Step 2: Install the plugin locally and confirm registration**

In a Claude Code session (in any test directory), run:
```
/plugin marketplace add /Users/ramil/projects/personal/cloudwright
/plugin install cloudwright@ramilvillon
```
Then confirm the 5 skills and 5 commands appear under the `cloudwright:` namespace (via `/help` or the plugin/skill listing). Expected: `cloudwright:cloud-architect`, `:security-auditor`, `:privacy-auditor`, `:cost-auditor`, `:ri-planner`, and commands `cloudwright:architect`, `:security-audit`, `:privacy-audit`, `:cost-audit`, `:ri-plan`.

- [ ] **Step 3: Confirm `${CLAUDE_SKILL_DIR}` resolves (self-reference)**

Trigger a skill that reads its own support files — e.g. run `/cloudwright:security-audit` and choose IaC mode against any sample `.tf` directory. Confirm the skill successfully reads its `domains/*.md` files (i.e. it produces a domain-grouped scorecard, not a "file not found" error). This proves self-reference resolution.

- [ ] **Step 4: Confirm cross-skill audit chain (sibling reference)**

Run `/cloudwright:architect` against a small sample workload through to the staging-output audit step. Confirm cloud-architect's audit chain successfully invokes the security + privacy auditors (i.e. it reads `${CLAUDE_SKILL_DIR}/../security-auditor/...`) and returns inline scorecards. This proves sibling-reference resolution.

- [ ] **Step 5: Record the result**

If Steps 3–4 pass, the `${CLAUDE_SKILL_DIR}` strategy is confirmed — the plugin is done. If either fails with a path-resolution error, apply the documented fallback below, then re-test.

**Fallback (only if `${CLAUDE_SKILL_DIR}` does not resolve in prose):** convert each skill's own-file reads to bare relative paths from the skill directory (e.g. `domains/iam.md`) and instruct the model in each SKILL.md to resolve them relative to the skill's own directory; for the cross-skill case, switch cloud-architect's audit chain from "subagent reads auditor files by path" to invoking the namespaced skills `cloudwright:security-auditor` / `cloudwright:privacy-auditor` directly with the pre-filled answers in the invocation prompt. Re-run Steps 3–4.

---

## Self-Review

**Spec coverage:**
- 5 generic skills packaged → Tasks 2–4. ✓
- plugin.json + marketplace.json → Task 1. ✓
- Path-reference porting (the spec's flagged core work) → Tasks 3–4, with the corrected `${CLAUDE_SKILL_DIR}` target (supersedes the spec's tentative `${CLAUDE_PLUGIN_ROOT}`). ✓
- Cross-skill audit chain preserved → Task 4 + Task 7 Step 4. ✓
- 5 slash commands → Task 5. ✓
- README + MIT LICENSE → Task 6. ✓
- Verify `${CLAUDE_PLUGIN_ROOT}`/plugin-root mechanism before bulk rewrite (spec's top risk) → resolved up front via claude-code-guide research; empirically confirmed in Task 7. ✓
- Success criteria 1–7 from the spec → covered by Task 1 (manifests), Task 2 (skills present), Tasks 3–4 (zero leftover refs), Task 4/7 (audit chain), Task 5 (commands), Task 6 (docs), Task 7 (install + trigger). ✓

**Placeholder scan:** No "TBD"/"TODO"/"handle edge cases" — every step has exact commands, exact file content, and expected output. The only deferred item is the documented, conditional fallback in Task 7, which is a real branch, not a placeholder. ✓

**Type/name consistency:** Plugin name `cloudwright`, marketplace name `ramilvillon`, install `cloudwright@ramilvillon`, skill names unchanged (`cloud-architect`, `security-auditor`, `privacy-auditor`, `cost-auditor`, `ri-planner`), command names distinct from skills (`architect`, `security-audit`, `privacy-audit`, `cost-audit`, `ri-plan`) — consistent across Tasks 1, 5, 6, 7. Rewrite variable `${CLAUDE_SKILL_DIR}` used identically in Tasks 3–4. ✓
