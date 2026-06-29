# Design: `cloud-architect-suite` Claude Code Plugin

**Date:** 2026-06-29
**Author:** Ramil Villon (ramilvillon)
**Status:** Approved design — pending implementation plan

## Goal

Package 5 AWS Well-Architected skills (currently living privately in
`width-infra/.claude/skills/`) as a **public Claude Code plugin** distributed via a
single-plugin marketplace repo. Users install with:

```
/plugin marketplace add ramilvillon/cloud-architect-suite
/plugin install cloud-architect-suite
```

## Scope

**In scope — 5 generic skills:**

| Skill | Purpose | Posture |
|-------|---------|---------|
| `cloud-architect` | Design AWS architecture → ADR (MADR) + Mermaid + parameterized Terraform; auto-runs the security + privacy auditors | Local FS writes only; never `terraform apply` / AWS writes |
| `security-auditor` | ISO 27001:2022 compliance audit (IaC + live) | Read-only on AWS |
| `privacy-auditor` | ISO 27701:2019 privacy/PII audit (IaC + live) | Read-only on AWS |
| `cost-auditor` | AWS cost audit + prioritized recommendations | Read-only on AWS |
| `ri-planner` | Reserved Instance coverage analysis | Read-only on AWS |

**Out of scope (left private in width-infra):** `iac-plan-verify`, `readiness-tracker`
— both tightly coupled to width-infra's repo layout, profiles, and service names.

**Out of scope (YAGNI):** hooks, MCP server, agents, CI. Can be added later if there's demand.

## Repo structure

Built in place at `/Users/ramil/projects/personal/cloud-skill` (git-initialized, empty).

```
cloud-architect-suite/            # repo root
├── .claude-plugin/
│   ├── plugin.json               # plugin manifest
│   └── marketplace.json          # single-plugin marketplace, source "./"
├── skills/
│   ├── cloud-architect/          # + patterns/ pillars/ templates/ evals/
│   ├── security-auditor/         # + domains/
│   ├── privacy-auditor/          # + domains/
│   ├── cost-auditor/
│   └── ri-planner/
├── commands/
│   ├── cloud-architect.md        # thin entry points → invoke each skill
│   ├── security-audit.md
│   ├── privacy-audit.md
│   ├── cost-audit.md
│   └── ri-plan.md
├── docs/superpowers/specs/       # this spec
├── README.md
└── LICENSE                       # MIT, "Ramil Villon"
```

## The real porting work: path references

A reference scan confirmed the 5 skills are **clean of width-infra specifics** — no
`width`, no private memory-file references (`feedback_*`, `project_*`), no hardcoded user
paths, no internal service names. (The only `memory`/`profile` matches are legitimate:
Lambda memory size, IAM login-profile.)

The genuine porting task is **path references**. The skills read their own bundled support
files and (for cloud-architect) the sibling auditors' files via **hardcoded
`.claude/skills/…` paths** — these resolve in width-infra but break once the plugin
installs to `~/.claude/plugins/…`.

Counts of `.claude/skills` references to rewrite:

| File | refs |
|------|------|
| `cloud-architect/SKILL.md` | 14 |
| `security-auditor/SKILL.md` | 20 |
| `privacy-auditor/SKILL.md` | 13 |
| `cost-auditor/SKILL.md` | 1 |
| `ri-planner/SKILL.md` | 1 |
| **total** | **49** |

**Fix:** rewrite `.claude/skills/` → `${CLAUDE_PLUGIN_ROOT}/skills/` (Claude Code's
documented plugin-root variable, expanded at runtime to the installed plugin directory).
This is a uniform, mechanical substitution. The implementation plan MUST first **verify
`${CLAUDE_PLUGIN_ROOT}` is the correct variable name and that it expands inside SKILL.md
instructions** (via claude-code-guide / docs) before applying the rewrite — if the
mechanism differs, adjust the substitution target accordingly.

## Cross-skill wiring

`cloud-architect` auto-invokes `security-auditor` + `privacy-auditor` as subagents. It does
so by (a) instructing a subagent to **read the auditor SKILL.md + domain files by path**,
and (b) pre-filling the interview answers. Because all three skills are co-located in the
plugin, this keeps working **once the path references (above) are rewritten** to
`${CLAUDE_PLUGIN_ROOT}`. No logic change needed — only the path rewrite.

## Slash commands

Five thin `commands/*.md` files. Each is frontmatter (`description`) + a one-line body
instructing Claude to invoke the corresponding skill. They add discoverable entry points
(`/cloud-architect`, `/security-audit`, `/privacy-audit`, `/cost-audit`, `/ri-plan`)
alongside the skills' own auto-trigger descriptions. Commands do not duplicate skill logic.

## Manifests

**`.claude-plugin/plugin.json`:**
- `name`: `cloud-architect-suite`
- `version`: `0.1.0`
- `description`: AWS Well-Architected design + read-only governance auditors (security, privacy, cost, RI)
- `author`: `{ "name": "Ramil Villon", "url": "https://github.com/ramilvillon" }`
- `license`: `MIT`
- `homepage` / `repository`: `https://github.com/ramilvillon/cloud-architect-suite`

**`.claude-plugin/marketplace.json`:** single-plugin marketplace listing this plugin at
`source: "./"`, with owner metadata. Exact field names to be confirmed against current
Claude Code marketplace schema during implementation.

## README + LICENSE

- **README.md:** what the suite does; the 5-skill table; the **read-only / no-AWS-writes /
  no-`terraform apply` safety posture** (a headline feature); install steps; per-skill
  usage examples; the cross-skill audit chain.
- **LICENSE:** MIT, copyright `Ramil Villon`, year 2026.

## Success criteria

1. Repo has valid `plugin.json` + `marketplace.json` that load without error.
2. All 5 skills present under `skills/`, with their support dirs intact.
3. Zero remaining `.claude/skills/` references; all rewritten to `${CLAUDE_PLUGIN_ROOT}/skills/`
   (or the verified-correct mechanism).
4. `cloud-architect`'s audit chain references resolve to the bundled auditor files.
5. Five working slash commands.
6. README + MIT LICENSE present.
7. (Stretch) Plugin installs locally from the marketplace and at least one skill triggers.

## Open questions / risks

- **`${CLAUDE_PLUGIN_ROOT}` semantics** — must be verified before the bulk rewrite. Primary risk.
- **marketplace.json schema** — confirm current required fields against live Claude Code docs.
- **evals/ inclusion** — `cloud-architect/evals/` ships as-is; harmless but optional. Keep unless it bloats.
