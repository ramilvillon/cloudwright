---
name: ri-planner
description: Use when working in an AWS project and asked to plan, analyze, or optimize Reserved Instance purchases across EC2, RDS, ElastiCache, and OpenSearch.
---

# AWS Reserved Instance Planner

## Overview

Run a structured, read-only analysis of RI coverage gaps across all RI-eligible AWS services, then produce a prioritized report with comparison tables (1yr vs 3yr × No/Partial/All Upfront) and ready-to-run purchase commands for human review.

**No RI purchases are ever made by this skill.**

## HARD CONSTRAINT: READ-ONLY ANALYSIS ONLY

**You MUST NOT purchase, create, modify, or delete any AWS resource — ever.**

All AWS CLI calls must be read-only. The only permitted command verbs are:
`describe-*`, `list-*`, `get-*`

**Explicitly forbidden commands:**
- `aws ec2 purchase-reserved-instances-offering`
- `aws rds purchase-reserved-db-instances-offering`
- `aws elasticache purchase-reserved-cache-nodes-offering`
- `aws opensearch purchase-reserved-instance-offering`
- Any AWS CLI call containing the verbs: `purchase`, `create`, `modify`, `delete`, `update`, `apply`, `deploy` — in any service or subcommand position

**The output of this skill is recommendations only.** A human must review and deliberately run any purchase commands.

If the user asks you to purchase RIs directly, respond: _"This skill is read-only. I can generate the exact purchase commands for you to review and run yourself."_

Every generated purchase command must be:
1. **Commented out** with `#` prefix on the purchase line
2. **Labeled** with `## REVIEW BEFORE RUNNING` above the block

---

## When to Use

- User is about to purchase Reserved Instances and wants a data-driven recommendation
- User received a budget alert and wants to understand their RI coverage exposure
- User wants to know what uncovered instances are costing them at on-demand rates
- User asks "should I buy RIs?" or "what RIs do we need?"

**When NOT to use:**
- AWS credentials are not configured (verify with `aws sts get-caller-identity` first)
- User only wants to see existing RI utilization (use focused Cost Explorer queries instead)

---

## Prerequisites

> Check before starting: `command -v jq` — install with `brew install jq` (macOS) or `sudo apt install jq` (Linux).
> Verify credentials: `aws sts get-caller-identity`

Announce at the start: _"Starting AWS RI coverage analysis (read-only). Collecting inventory and Cost Explorer recommendations across EC2, RDS, ElastiCache, and OpenSearch. No changes will be made."_

---

## Execution Mode: Orchestrator + Parallel Domain Agents

Use a 2-phase architecture. Phase 1 collects data in parallel across all 4 services; Phase 2 analyzes and writes the report sequentially.

```
Main Agent
└── Orchestrator (general-purpose subagent)
    ├── Phase 1 — launches 4 domain agents IN PARALLEL (single Agent tool message)
    │   ├── [A] EC2         → running instances, active RIs, CE recs  (no delay)
    │   ├── [B] RDS         → DB instances, reserved DBs, CE recs      (sleep 5)
    │   ├── [C] ElastiCache → cache clusters, reserved nodes, CE recs  (sleep 10)
    │   └── [D] OpenSearch  → domains, reserved instances, CE recs     (sleep 15)
    │       ↓ each writes findings to docs/tmp/ri-<domain>.md
    ├── Phase 2–4 — reads all 4 temp files, analyzes + builds tables (inline)
    └── Phase 5  — writes final report, cleans up docs/tmp/
```

The startup delays stagger each agent's initial API burst to avoid thundering-herd throttling on Cost Explorer (hard limit: 1 req/s shared across all callers).

### Orchestrator Instructions

When this skill is invoked, the **main agent** immediately calls the `Agent` tool to create an Orchestrator subagent:

```
Agent({
  description: "AWS RI planner — orchestrator",
  subagent_type: "general-purpose",
  prompt: `
You are the AWS RI planner orchestrator. Follow these steps exactly.

HARD CONSTRAINT: Read-only analysis only. Never purchase, modify, or create any AWS resource.

Step 1 — Setup:
  mkdir -p docs/tmp
  aws sts get-caller-identity  # confirm credentials are valid

Step 2 — Read the full skill file to get all Phase 1 commands and Phase 2–5 instructions:
  ${CLAUDE_SKILL_DIR}/SKILL.md

Step 3 — Launch all 4 domain agents IN PARALLEL (send a single Agent tool message with all 4 calls):

  Agent A — EC2 domain:
    "Run all commands in the 'Domain A — EC2' section of the skill file.
     Apply rate limiting: sleep 1 after every aws ce call.
     No startup delay.
     Write all collected data to docs/tmp/ri-ec2.md."

  Agent B — RDS domain:
    "Run all commands in the 'Domain B — RDS' section of the skill file.
     Apply rate limiting: sleep 1 after every aws ce call.
     Startup delay: sleep 5 before issuing any AWS CLI calls.
     Write all collected data to docs/tmp/ri-rds.md."

  Agent C — ElastiCache domain:
    "Run all commands in the 'Domain C — ElastiCache' section of the skill file.
     Apply rate limiting: sleep 1 after every aws ce call.
     Startup delay: sleep 10 before issuing any AWS CLI calls.
     Write all collected data to docs/tmp/ri-elasticache.md."

  Agent D — OpenSearch domain:
    "Run all commands in the 'Domain D — OpenSearch' section of the skill file.
     Apply rate limiting: sleep 1 after every aws ce call.
     Startup delay: sleep 15 before issuing any AWS CLI calls.
     Write all collected data to docs/tmp/ri-opensearch.md."

Step 4 — Wait for all 4 agents to complete.

Step 5 — Read all 4 temp files:
  docs/tmp/ri-ec2.md
  docs/tmp/ri-rds.md
  docs/tmp/ri-elasticache.md
  docs/tmp/ri-opensearch.md

Step 6 — Run Phases 2–5 inline per the skill file instructions.

Step 7 — Clean up: rm -rf docs/tmp/

Return a brief terminal summary (total monthly exposure + top 3 recommendations).
  `
})
```

**Main agent rule:** relay only the orchestrator's summary to the user. Point to `docs/ri-plan-YYYY-MM-DD.md` for the full report. Do not run any `aws` CLI commands in the main context.

---

## Phase 1 — Data Collection

Phase 1 is split into 4 independent domain groups. Each runs as a separate subagent and writes its output to `docs/tmp/ri-<domain>.md`.

---

### Domain A — EC2
*Covers: running EC2 instances, active EC2 Reserved Instances, Cost Explorer purchase recommendations*
*Startup delay: none — start immediately*
*Rate limit: `sleep 1` after every `aws ce` call*

**Running EC2 instances**
```bash
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone,Placement.Tenancy,Tags]' \
  --output json | jq -r '
    .[] |
    (.[-1] // [] | map(select(.Key == "Name")) | .[0].Value // "(no name)") as $name |
    [.[0], .[1], .[2], .[3], $name] | @tsv'
```

**Active EC2 Reserved Instances**
```bash
aws ec2 describe-reserved-instances \
  --filters Name=state,Values=active \
  --query 'ReservedInstances[].[ReservedInstancesId,InstanceType,InstanceCount,End,OfferingType,Scope]' \
  --output table
```

Note the `Scope` field — `Region` scope covers any AZ, `Availability Zone` scope is AZ-specific. Regional scope is more flexible.

**Cost Explorer EC2 purchase recommendations**
```bash
aws ce get-reservation-purchase-recommendation \
  --service AmazonEC2 \
  --output json | jq -r '
    .Recommendations[] |
    "Term: \(.TermInYears)yr  Payment: \(.PaymentOption)",
    (.RecommendationDetails[] |
      [.InstanceDetails.EC2InstanceDetails.InstanceType,
       .InstanceDetails.EC2InstanceDetails.Region,
       (.RecommendedNumberOfInstancesToPurchase | tostring) + "x",
       ("$" + .EstimatedMonthlySavingsAmount + "/mo savings"),
       ("\(.EstimatedBreakEvenInMonths) month breakeven")]
      | @tsv)'
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

### Domain B — RDS
*Covers: running DB instances, active reserved DB instances, Cost Explorer recommendations*
*Startup delay: `sleep 5` before issuing any AWS CLI calls*
*Rate limit: `sleep 1` after every `aws ce` call*

**Running RDS DB instances**
```bash
aws rds describe-db-instances \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,MultiAZ,Engine,DBInstanceStatus,AvailabilityZone]' \
  --output table
```

**Active RDS Reserved DB instances**
```bash
aws rds describe-reserved-db-instances \
  --query 'ReservedDBInstances[].[ReservedDBInstanceId,DBInstanceClass,MultiAZ,OfferingType,State,StartTime,Duration]' \
  --output table
```

Note the `Duration` field — `31536000` = 1 year, `94608000` = 3 years. Check `StartTime` to calculate expiry: `StartTime + Duration`.

**Cost Explorer RDS purchase recommendations**
```bash
aws ce get-reservation-purchase-recommendation \
  --service AmazonRDS \
  --output json | jq -r '
    .Recommendations[] |
    "Term: \(.TermInYears)yr  Payment: \(.PaymentOption)",
    (.RecommendationDetails[] |
      [.InstanceDetails.RDSInstanceDetails.DBInstanceClass,
       .InstanceDetails.RDSInstanceDetails.DatabaseEngine,
       (.InstanceDetails.RDSInstanceDetails.MultiAZCapable | tostring),
       (.RecommendedNumberOfInstancesToPurchase | tostring) + "x",
       ("$" + .EstimatedMonthlySavingsAmount + "/mo savings")]
      | @tsv)'
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

### Domain C — ElastiCache
*Covers: running cache clusters/nodes, active reserved cache nodes, Cost Explorer recommendations*
*Startup delay: `sleep 10` before issuing any AWS CLI calls*
*Rate limit: `sleep 1` after every `aws ce` call*

**Running ElastiCache clusters**
```bash
aws elasticache describe-cache-clusters \
  --query 'CacheClusters[].[CacheClusterId,CacheNodeType,NumCacheNodes,Engine,CacheClusterStatus,PreferredAvailabilityZone]' \
  --output table
```

**Active ElastiCache reserved cache nodes**
```bash
aws elasticache describe-reserved-cache-nodes \
  --query 'ReservedCacheNodes[].[ReservedCacheNodeId,CacheNodeType,Duration,OfferingType,State,StartTime,CacheNodeCount]' \
  --output table
```

**Cost Explorer ElastiCache purchase recommendations**
```bash
aws ce get-reservation-purchase-recommendation \
  --service AmazonElastiCache \
  --output json | jq -r '
    .Recommendations[] |
    "Term: \(.TermInYears)yr  Payment: \(.PaymentOption)",
    (.RecommendationDetails[] |
      [.InstanceDetails.ElastiCacheInstanceDetails.NodeType,
       .InstanceDetails.ElastiCacheInstanceDetails.ProductDescription,
       (.RecommendedNumberOfInstancesToPurchase | tostring) + "x",
       ("$" + .EstimatedMonthlySavingsAmount + "/mo savings")]
      | @tsv)'
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

### Domain D — OpenSearch
*Covers: running OpenSearch domains, active reserved instances, Cost Explorer recommendations*
*Startup delay: `sleep 15` before issuing any AWS CLI calls*
*Rate limit: `sleep 1` after every `aws ce` call*

**Running OpenSearch domains**
```bash
DOMAINS=$(aws opensearch list-domain-names --output json | jq -r '.DomainNames[].DomainName' | tr '\n' ' ')
echo "OpenSearch domains: $(aws opensearch list-domain-names --output json | jq '.DomainNames | length')"
[ -n "$DOMAINS" ] && aws opensearch describe-domains --domain-names $DOMAINS --output json \
  | jq -r '.DomainStatusList[] | [
      .DomainName,
      .ClusterConfig.InstanceType,
      (.ClusterConfig.InstanceCount | tostring) + "x data",
      ("DedicatedMaster:" + (.ClusterConfig.DedicatedMasterEnabled | tostring)),
      ("ZoneAware:" + (.ClusterConfig.ZoneAwarenessEnabled | tostring))
    ] | @tsv'
```

Note: `ZoneAwarenessEnabled=true` means the actual node count is 2× or 3× the `InstanceCount` value — account for this in gap analysis.

**Active OpenSearch reserved instances**
```bash
aws opensearch describe-reserved-instances --output json 2>/dev/null | jq -r '
  "OpenSearch reservations: \(.ReservedInstances | length)",
  (.ReservedInstances[] |
    [.ReservedInstanceId,
     .InstanceType,
     (.InstanceCount | tostring) + "x",
     .PaymentOption,
     .State,
     .StartTime]
    | @tsv)' || echo "No OpenSearch reservations or insufficient permissions"
```

**Cost Explorer OpenSearch purchase recommendations**
```bash
# Note: Cost Explorer uses the legacy "AmazonES" service name for OpenSearch even after the rebrand.
# The response still returns ESInstanceDetails (not OpenSearchInstanceDetails).
aws ce get-reservation-purchase-recommendation \
  --service AmazonES \
  --output json | jq -r '
    .Recommendations[] |
    "Term: \(.TermInYears)yr  Payment: \(.PaymentOption)",
    (.RecommendationDetails[] |
      [.InstanceDetails.ESInstanceDetails.InstanceType,
       .InstanceDetails.ESInstanceDetails.Region,
       (.RecommendedNumberOfInstancesToPurchase | tostring) + "x",
       ("$" + .EstimatedMonthlySavingsAmount + "/mo savings")]
      | @tsv)'
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

## Phase 2 — Coverage Gap Analysis

Read all 4 temp files (`docs/tmp/ri-ec2.md`, `docs/tmp/ri-rds.md`, `docs/tmp/ri-elasticache.md`, `docs/tmp/ri-opensearch.md`) and compute coverage gaps inline.

### Gap Calculation Logic

For each service:

1. **Count running instances** by type (e.g., 4× db.r7g.large)
2. **Count active RI coverage** by type (e.g., 2× db.r7g.large reserved)
3. **Gap** = running − covered (floor at 0)
4. **Monthly exposure** = gap × on-demand hourly rate × 730 hours

For **EC2 specifically**, normalize by instance size using NFU (Normalized Factor Units) before comparing — a single `m5.2xlarge` RI (NFU=16) covers two `m5.xlarge` (NFU=8 each) within the same family and region scope. Only apply NFU normalization for Regional-scope RIs.

NFU reference (relative to m5.large = NFU 4):
| Size | NFU |
|------|-----|
| nano | 0.25 |
| micro | 0.5 |
| small | 1 |
| medium | 2 |
| large | 4 |
| xlarge | 8 |
| 2xlarge | 16 |
| 4xlarge | 32 |
| 8xlarge | 64 |
| 16xlarge | 128 |

### Cross-reference Cost Explorer recommendations

For each gap found, check if Cost Explorer also recommends purchasing that type. If CE recommends it too, flag as **High Confidence**. If gap exists but CE has no recommendation, flag as **Manual Review** (may indicate the workload is too new for CE's 14-day lookback).

### Gap Analysis Output Format

Present one table per service:

| Instance Type | Running | RI Covered | Gap | Est. On-Demand/mo | CE Confidence |
|---|---|---|---|---|---|
| db.r7g.large | 4 | 2 | 2 | ~$350 | High |
| cache.m7g.xlarge | 2 | 0 | 2 | ~$580 | High |

**Savings Plans note:** Before finalizing EC2 gaps, check if uncovered EC2 instances are already covered by a Compute Savings Plan. Savings Plans and RIs can overlap — buying RIs for SP-covered instances wastes money. Use CE coverage data if available:

```bash
aws ce get-reservation-coverage \
  --time-period Start=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --output json
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

## Phase 3 — Term/Payment Comparison Tables

For each gap identified in Phase 2, fetch live RI offering prices and build a comparison table. Do this inline in the orchestrator.

### Fetching Offering Prices

**EC2:**
```bash
aws ec2 describe-reserved-instances-offerings \
  --instance-type <type> \
  --product-description "Linux/UNIX" \
  --instance-tenancy default \
  --offering-class standard \
  --filters Name=duration,Values=31536000 \
  --output json | jq -r '
    .ReservedInstancesOfferings[] |
    [.OfferingType,
     ("$" + (.FixedPrice | tostring) + " upfront"),
     ("$" + ((.RecurringCharges[0].RecurringChargeAmount // 0) * 730 | . * 100 | round / 100 | tostring) + "/mo")]
    | @tsv'
# Repeat with --filters Name=duration,Values=94608000 for 3yr
```

**RDS:**
```bash
aws rds describe-reserved-db-instances-offerings \
  --db-instance-class <class> \
  --product-description "postgresql" \
  --output json | jq -r '
    .ReservedDBInstancesOfferings[] |
    [.OfferingType,
     ((.Duration / 31536000) | tostring) + "yr",
     ("$" + (.FixedPrice | tostring) + " upfront"),
     ("$" + ((.RecurringCharges[0].RecurringChargeAmount // 0) * 730 | . * 100 | round / 100 | tostring) + "/mo")]
    | @tsv'
```

**ElastiCache:**
```bash
aws elasticache describe-reserved-cache-nodes-offerings \
  --cache-node-type <type> \
  --output json | jq -r '
    .ReservedCacheNodesOfferings[] |
    [.OfferingType,
     ((.Duration / 31536000) | tostring) + "yr",
     ("$" + (.FixedPrice | tostring) + " upfront"),
     ("$" + ((.RecurringCharges[0].RecurringChargeAmount // 0) * 730 | . * 100 | round / 100 | tostring) + "/mo")]
    | @tsv'
```

**OpenSearch:**
```bash
aws opensearch describe-reserved-instance-offerings \
  --output json | jq -r '
    .ReservedInstanceOfferings[] | select(.InstanceType == "<type>") |
    [.PaymentOption,
     ((.Duration / 31536000) | tostring) + "yr",
     ("$" + (.FixedPrice | tostring) + " upfront"),
     ("$" + ((.RecurringCharges[0].RecurringChargeAmount // 0) * 730 | . * 100 | round / 100 | tostring) + "/mo")]
    | @tsv'
```

### Comparison Table Format

Build one table per gap. Include a breakeven calculation for upfront options:

```
## RDS: db.r7g.large × 2 (PostgreSQL)
On-demand cost: ~$350/month (2 instances × $0.24/hr × 730)

| Term | Payment     | Upfront | Monthly | Total Cost | vs On-Demand | Breakeven |
|------|------------|---------|---------|-----------|-------------|-----------|
| 1yr  | No Upfront | $0      | $180    | $2,160    | 38%         | —         |
| 1yr  | Partial    | $900    | $90     | $1,980    | 43%         | 4.2 months|
| 1yr  | All Upfront| $1,800  | $0      | $1,800    | 49%         | 3.6 months|
| 3yr  | No Upfront | $0      | $120    | $4,320    | 59%         | —         |
| 3yr  | All Upfront| $3,200  | $0      | $3,200    | 69%         | 5.1 months|
```

**Breakeven formula (vs No Upfront of same term):**
`breakeven_months = upfront_cost / (no_upfront_monthly - this_option_monthly)`

**Recommendation line** below each table:
- If workload is < 3 months old: recommend 1yr only (insufficient history for 3yr commitment)
- If workload is stable > 6 months: flag 3yr All Upfront as best long-term value
- Default safe recommendation: 1yr Partial Upfront (balances savings vs cash flow)

---

## Phase 4 — Buy Commands

For each recommendation, generate a two-step purchase block. Step 1 finds the offering ID (read-only). Step 2 is the actual purchase — **always commented out**.

### EC2 Buy Command Template

```bash
## REVIEW BEFORE RUNNING — EC2 <type> × <count>, <term> <payment>
## Estimated savings: ~$X/month vs on-demand

# Step 1: Find and confirm the offering ID
aws ec2 describe-reserved-instances-offerings \
  --instance-type <type> \
  --product-description "Linux/UNIX" \
  --instance-tenancy default \
  --offering-class standard \
  --filters Name=duration,Values=<31536000_or_94608000> \
  --query 'ReservedInstancesOfferings[?OfferingType==`<payment_type>`].[ReservedInstancesOfferingId,OfferingType,FixedPrice,RecurringCharges]' \
  --output table

# Step 2: Purchase (uncomment and run after confirming offering ID above)
# aws ec2 purchase-reserved-instances-offering \
#   --reserved-instances-offering-id <offering-id-from-step-1> \
#   --instance-count <count>
```

### RDS Buy Command Template

```bash
## REVIEW BEFORE RUNNING — RDS <class> × <count>, <term> <payment>
## Estimated savings: ~$X/month vs on-demand

# Step 1: Find and confirm the offering ID
aws rds describe-reserved-db-instances-offerings \
  --db-instance-class <class> \
  --product-description "<postgresql|mysql|aurora-postgresql|aurora-mysql>" \
  --offering-type "<No Upfront|Partial Upfront|All Upfront>" \
  --duration <31536000_or_94608000> \
  --output table

# Step 2: Purchase (uncomment and run after confirming offering ID above)
# aws rds purchase-reserved-db-instances-offering \
#   --reserved-db-instances-offering-id <offering-id-from-step-1> \
#   --db-instance-count <count>
```

### ElastiCache Buy Command Template

```bash
## REVIEW BEFORE RUNNING — ElastiCache <type> × <count>, <term> <payment>
## Estimated savings: ~$X/month vs on-demand

# Step 1: Find and confirm the offering ID
aws elasticache describe-reserved-cache-nodes-offerings \
  --cache-node-type <type> \
  --offering-type "<No Upfront|Partial Upfront|All Upfront>" \
  --duration <31536000_or_94608000> \
  --output table

# Step 2: Purchase (uncomment and run after confirming offering ID above)
# aws elasticache purchase-reserved-cache-nodes-offering \
#   --reserved-cache-nodes-offering-id <offering-id-from-step-1> \
#   --cache-node-count <count>
```

### OpenSearch Buy Command Template

```bash
## REVIEW BEFORE RUNNING — OpenSearch <type> × <count>, <term> <payment>
## Estimated savings: ~$X/month vs on-demand

# Step 1: Find and confirm the offering ID
aws opensearch describe-reserved-instance-offerings \
  --output json | jq -r '
    .ReservedInstanceOfferings[] |
    select(.InstanceType == "<type>" and .PaymentOption == "<NO_UPFRONT|PARTIAL_UPFRONT|ALL_UPFRONT>") |
    [.ReservedInstanceOfferingId, .InstanceType, .PaymentOption, .FixedPrice] | @tsv'

# Step 2: Purchase (uncomment and run after confirming offering ID above)
# aws opensearch purchase-reserved-instance-offering \
#   --reserved-instance-offering-id <offering-id-from-step-1> \
#   --reservation-name "<descriptive-name>" \
#   --instance-count <count>
```

---

## Phase 5 — Report

Save the full report to `docs/ri-plan-YYYY-MM-DD.md` using this structure:

```markdown
# AWS Reserved Instance Plan — YYYY-MM-DD

> **READ-ONLY ANALYSIS.** No changes were made to AWS infrastructure.
> All purchase commands below are commented out. A human must review and run them.

## Executive Summary

**Account:** [account-id] ([region]) · Analysis date: YYYY-MM-DD

| | Amount |
|--|--------|
| Total uncovered monthly exposure | **$X/month** |
| Savings if all recommendations applied | **$X/month (X%)** |
| Recommended immediate actions | [count] purchases |

## Current RI Inventory

[Per-service table: type, count, expiry, offering type — flag any expiring within 90 days with ***]

## Coverage Gap Analysis

[Per-service gap table from Phase 2]

## Purchase Recommendations

[Ranked by savings opportunity — largest gap first]

### Recommendation #1: [Service] [Type] × [Count]

[Comparison table from Phase 3]

**Recommendation:** [1yr Partial Upfront / 3yr All Upfront / etc.] — [one sentence rationale]

[Buy commands block from Phase 4]

---

[Repeat for each recommendation]

## IAM Permissions

Most permissions are covered by `iam/aws-cost-optimizer-policy.json`. Verify your policy also includes these RI-specific actions (not in the base cost auditor policy):

- `ce:GetReservationPurchaseRecommendation`
- `ec2:DescribeReservedInstancesOfferings`
- `rds:DescribeReservedDBInstances`, `rds:DescribeReservedDBInstancesOfferings`
- `elasticache:DescribeReservedCacheNodes`, `elasticache:DescribeReservedCacheNodesOfferings`
- `es:DescribeReservedElasticsearchInstances`, `es:DescribeReservedElasticsearchInstanceOfferings`
```

Also output a brief terminal summary after saving the file:
- Total monthly exposure
- Top 3 recommendations with estimated savings
- Path to the full report

---

## Common Mistakes to Avoid

| Mistake | Fix |
|---------|-----|
| Generating uncommented purchase commands | Always comment out the purchase step; label every block `## REVIEW BEFORE RUNNING` |
| Recommending EC2 RIs for SP-covered instances | Check Savings Plans coverage first — SPs and RIs overlap; double-covering wastes money |
| Forgetting NFU normalization for EC2 | A Regional r7g.large RI covers 2× r7g.medium — count by NFU, not raw instance count |
| Fetching RDS offerings without engine filter | Offerings are engine-specific; always pass `--product-description` |
| Recommending 3yr for workloads < 3 months old | Flag insufficient history — recommend 1yr only until 6+ months of data exists |
| Missing `sleep 1` after Cost Explorer calls | Hard limit — causes `ThrottlingException`; one call per second across all domains |
| Not accounting for ZoneAwareness in OpenSearch | `ZoneAwarenessEnabled=true` means actual node count = `InstanceCount × 2 or 3` |
| Using `sesv2`, `apigatewayv2`, or `opensearch` as IAM namespace prefixes | OpenSearch IAM still uses `es:*`; API Gateway v2 uses `apigateway:`; SES v2 uses `ses:` |
| Using `AmazonOpenSearchService` as the CE service name | Cost Explorer retained the legacy `AmazonES` name after the rebrand — use `--service AmazonES` |
| Not filtering RDS offerings by MultiAZ | `describe-reserved-db-instances-offerings` returns both Single-AZ and Multi-AZ rows — match the `MultiAZ` value from the running instance to avoid recommending the wrong SKU |
