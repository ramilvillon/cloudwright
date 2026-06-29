# WAF Pillar: Performance Efficiency

## Purpose

Apply Performance Efficiency design-time defaults. Favour modern compute (Graviton), right-sized storage, and appropriate caching where `traffic` tier justifies it.

## Defaults

### Compute selection
- **Default to Graviton (ARM64)** for Fargate, Lambda, RDS (r6g / m6g / t4g class), ElastiCache (r6g / m6g)
- Fargate task CPU/memory selection:
  - `traffic = low` → 0.25 vCPU / 512 MiB
  - `traffic = medium` → 0.5 vCPU / 1024 MiB
  - `traffic = high` → 1 vCPU / 2048 MiB (horizontally scaled)
- Lambda memory:
  - Default 512 MB unless pattern dictates otherwise
  - Increase to 1024 MB for any function handling >1 MB payloads
- RDS instance class:
  - `traffic = low` → `db.t4g.small` (non-prod) / `db.m6g.large` (prod)
  - `traffic = medium` → `db.m6g.large` (non-prod) / `db.r6g.large` (prod)
  - `traffic = high` → `db.r6g.xlarge` (non-prod) / `db.r6g.2xlarge` (prod)

### Caching
- Add ElastiCache Redis to the `three-tier-containerized` pattern when `traffic` ∈ {medium, high}
- CloudFront in front of any static S3 content — always. `PriceClass_100` (NA + EU) for low, `PriceClass_200` for medium, `PriceClass_All` for high
- API Gateway caching enabled (TTL 60s) for `serverless-rest-api` when `traffic = high`

### Storage class selection
- S3 application data: `STANDARD`
- S3 logs + audit artifacts: lifecycle → `INTELLIGENT_TIERING` at 30 days → `GLACIER_IR` at 90 days
- S3 infrequent backup artifacts: `STANDARD_IA` immediately
- EBS: `gp3` always (never `gp2`); `io2` only if IOPS > 16k

## Generation-time checks

1. No `gp2` EBS volumes anywhere in generated HCL.
2. Every compute resource uses Graviton unless pattern annotation documents why (e.g., the workload image is x86-only).
3. CloudFront present for any S3-backed static content.
4. API Gateway throttling limits set (default: burst 5000, rate 10000) — even if not exceeded, prevents runaway cost.

## ADR decisions narrative

1–2 sentences: CPU architecture (ARM64/x86), compute sizing tied to traffic tier, caching decisions.

Example:
> Graviton (ARM64) for Fargate tasks and RDS (r6g.large in prod). ElastiCache Redis fronts the RDS for session + hot-query caching. CloudFront PriceClass_200 for static assets.
