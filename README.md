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
