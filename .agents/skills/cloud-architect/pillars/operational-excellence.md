# WAF Pillar: Operational Excellence

## Purpose

Apply Operational Excellence design-time defaults. Covers tagging, observability, deployment hygiene, and IaC structure.

## Defaults

### Tagging (applied via `default_tags` in AWS provider block)

Every pattern's root `main.tf` MUST include:

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Workload    = var.workload
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
      Repository  = var.repository
    }
  }
}
```

Variables `environment`, `workload`, `owner`, `cost_center`, `repository` MUST be declared in `variables.tf` with no defaults (forcing the user to set them per-environment).

### Observability

- CloudWatch Log Groups: every Lambda, ECS service, API Gateway stage, and RDS instance → `retention_in_days = 30` (non-prod) / `365` (prod)
- CloudWatch Alarms (minimum set per pattern):
  - ALB: 5xx rate > 1% for 5 minutes
  - ECS service: CPU utilization > 80% for 10 minutes
  - Lambda: error rate > 1% for 5 minutes; duration p99 > 80% of configured timeout
  - RDS: CPU > 80% for 15 minutes; free storage < 20%
- SNS topic for alarm notifications — **no subscriptions** in generated Terraform (user adds email/Slack post-deploy)
- Container Insights enabled on every ECS cluster

### Deployment hygiene

- `versions.tf` pinning: `terraform >= 1.7`, `hashicorp/aws ~> 5.0`
- Remote state backend stub (S3 + DynamoDB lock) in `backend.tf` — commented out with instructions to enable
- `.gitignore` at the root of the generated project covering `*.tfstate*`, `.terraform/`, `terraform.tfvars` (NEVER commit tfvars with secrets)
- Never commit `terraform.tfvars`; always provide `terraform.tfvars.example` with placeholder values

### IaC structure

- Use `terraform.tfvars` per environment (not Terraform workspaces unless pattern requires it)
- Module structure per pattern file's annotation
- `locals.tf` for derived values (avoid duplicated ternaries across resources)

## Generation-time checks

1. `default_tags` block present and includes all six required tags.
2. `.gitignore` file present.
3. Every log group has an explicit retention — no `retention_in_days = 0` (= never expire).
4. Alarm SNS topic exists; alarms reference it.

## ADR decisions narrative

1 sentence: tagging scheme, log retention policy, alarm coverage.

Example:
> Consistent tagging (Environment, Workload, Owner, CostCenter, ManagedBy, Repository) via default_tags. CloudWatch log retention 30d non-prod / 365d prod. Baseline alarms for ALB 5xx, ECS CPU, Lambda errors, RDS CPU + free storage, wired to an unsubscribed SNS topic.
