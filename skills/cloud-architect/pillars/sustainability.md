# WAF Pillar: Sustainability

## Purpose

Apply Sustainability design-time defaults. Primary levers: efficient compute (Graviton, shared with Performance pillar), right-sized storage with lifecycle rules, and scale-to-zero for non-prod.

## Defaults

### Compute
- **Graviton default** (same as Performance pillar — single source of truth for ARM64 selection)
- ECS services in **dev** environments: tag with `scheduled-stop = "19:00"` and `scheduled-start = "07:00"` (UTC); add a TODO comment in the ADR noting the scheduler is not wired in v1 — user adds EventBridge Scheduler rules post-deploy
- Lambda: no always-on provisioned concurrency in non-prod

### Storage
- S3 lifecycle rules (same as Performance pillar):
  - Logs / audit buckets: `INTELLIGENT_TIERING` at 30d → `GLACIER_IR` at 90d → `DEEP_ARCHIVE` at 365d
  - Versioned application buckets: expire noncurrent versions at 90d
- EBS snapshots: lifecycle policy retaining 7 daily, 4 weekly, 12 monthly

### Managed services over self-hosted

- Use Aurora Serverless v2 as an alternative to provisioned RDS when `traffic = low` AND `environments` excludes prod — captures ~60% cost savings for idle workloads. Apply only when the pattern annotation allows.
- Favour Fargate over EC2 for stateless compute — no idle instances.
- Favour DynamoDB on-demand over RDS for simple key-value access.

### Networking

- Single NAT Gateway in dev environments (shared across AZs) instead of per-AZ — smaller carbon footprint and cost. Documented trade-off: reduced AZ isolation for dev only.
- VPC endpoints for S3 and DynamoDB in any VPC that talks to them — reduces NAT Gateway traffic.

## Generation-time checks

1. Every log / audit bucket has a lifecycle rule with at least one tier transition.
2. No EC2 Auto Scaling Group in patterns where Fargate would work (i.e., user must opt in explicitly to EC2).
3. VPC endpoints for S3 + DynamoDB when those services are used from inside a private subnet.

## ADR decisions narrative

1–2 sentences: Graviton use, storage tiering, scale-to-zero / scheduling plans, managed-service choices that reduce idle.

Example:
> Graviton for all compute. S3 lifecycle tiers logs to INTELLIGENT_TIERING → GLACIER_IR → DEEP_ARCHIVE. Dev environments flagged for scheduled stop/start (user wires post-deploy). Single NAT Gateway in dev; per-AZ in prod.
