# WAF Pillar: Reliability

## Purpose

Apply Reliability design-time defaults to every generated pattern. Check the result against this rubric before handing off to the audit chain.

## Defaults (apply unless pattern annotation overrides)

### Compute
- ECS services: minimum 2 tasks across 2 AZs; enable service autoscaling (target 60% CPU) when `traffic` ∈ {medium, high}
- Lambda: reserved concurrency set for any user-facing function (20 for low, 100 for medium, 500 for high); set `maximum_retry_attempts` on async invocations to 2
- EC2 (if used): Auto Scaling Group across ≥2 AZs, health check grace period 300s

### Data
- RDS: Multi-AZ = `true` whenever `environments` includes `prod` or `staging`; automated backups = 7 days for non-prod, 30 days for prod; `deletion_protection = true` for prod
- DynamoDB: on-demand billing mode by default; point-in-time recovery enabled
- S3: versioning enabled on any bucket holding application state (not logs); cross-region replication NOT applied in v1 (multi-region out of scope)

### Networking
- ALB / NLB: cross-zone load balancing enabled; target group health check with 2-out-of-3 failure threshold
- NAT Gateway: per-AZ in prod (2 NATs); single NAT in dev acceptable; document the cost/reliability trade-off in the Consequences section

### Messaging
- SQS: DLQ configured with `maxReceiveCount = 5`; message retention = 4 days (default) or 14 days if downstream processing may be delayed
- Kinesis: on-demand mode unless `traffic` = high (provisioned with 2+ shards); retention = 24h default, 7 days if replay needed

## Generation-time checks (subagent MUST verify before writing)

1. Every stateful resource has a backup/retention mechanism (RDS automated backups, DynamoDB PITR, S3 versioning) — NOT disabled via variable.
2. Every user-facing compute has ≥2 AZ spread OR an explicit note in Consequences explaining why single-AZ is acceptable (e.g., dev-only).
3. Every async queue has a DLQ or an explicit exemption in pattern annotation.
4. No hardcoded AZ references (e.g., `"us-east-1a"`) in generated HCL — always derived from `data.aws_availability_zones.available`.

## ADR decisions narrative (what to write in `{{reliability_decisions}}`)

Summarise in 1–3 sentences: the AZ spread (single / multi-AZ), the backup/retention approach, any explicit trade-offs accepted (e.g., single NAT in dev). Reference the pattern's annotation, don't restate rubric defaults verbatim.

Example:
> Multi-AZ across 2 AZs for ECS and RDS (Multi-AZ failover). RDS automated backups 30 days in prod, 7 days elsewhere; deletion protection on prod. Single NAT Gateway in dev accepted to reduce cost; prod uses per-AZ NATs.
