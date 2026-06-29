# Cloudwright

Cloudwright is a set of AWS Well-Architected skills for AI coding agents: one architecture-design
skill and four read-only governance auditors. The skills follow the [Agent Skills](https://agentskills.io)
open standard and live in `.agents/skills/` — your runtime discovers them there (or in `~/.agents/skills/`
when installed globally).

## Skills

- **cloud-architect** — design an AWS architecture (ADR + Mermaid + parameterized Terraform), then run the security + privacy auditors against the generated output.
- **security-auditor** — ISO 27001:2022 compliance audit of Terraform/CloudFormation or live AWS.
- **privacy-auditor** — ISO 27701:2019 privacy audit (PII residency, retention, discovery, sharing).
- **cost-auditor** — read-only AWS cost audit with prioritized recommendations.
- **ri-planner** — Reserved Instance coverage analysis.

Each skill auto-triggers from its `description` when relevant; you can also invoke one by name.

## Safety posture

Every skill is **read-only against AWS**: it writes local files (Terraform, reports, ADRs) but never
calls AWS write APIs and never runs `terraform apply`/`destroy`. Recommendations are emitted for a
human to review and run.
