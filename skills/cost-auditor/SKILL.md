---
name: cost-auditor
description: Use when working in an AWS project and asked to analyze, reduce, or audit AWS costs.
---

# AWS Cost Optimizer

## Overview

Run a structured, read-only audit of AWS spend across all major domains, then produce prioritized recommendations and ready-to-apply implementation artifacts. No changes are ever made to AWS infrastructure.

> **Bundled file paths.** Paths like `SKILL.md` in this skill are relative to **this skill's own directory**, which your runtime announces when the skill activates. Read them with your normal file-reading tool. **When you pass such a path into a subagent, first resolve it to an absolute path** (prefix it with this skill's directory) — a subagent does not share this skill's directory context.

## HARD CONSTRAINT: READ-ONLY AUDIT ONLY

**You MUST NOT apply, execute, or deploy any changes to AWS infrastructure — ever.**

All AWS CLI calls must be read-only. The only permitted command verbs are:
`describe-*`, `list-*`, `get-*`

**Explicitly forbidden commands (non-exhaustive):**

*Compute*
- `aws ec2 terminate-instances` / `stop-instances` / `modify-instance-*`
- `aws ec2 delete-volume` / `delete-snapshot` / `modify-volume`
- `aws ec2 release-address` / `delete-nat-gateway` / `delete-vpc-endpoints`
- `aws cloudformation delete-stack` / `update-stack` / `deploy`
- `aws ecs update-service` / `delete-service` / `delete-cluster`
- `aws eks update-cluster-config` / `delete-cluster` / `delete-nodegroup`
- `aws lambda delete-function` / `update-function-*` / `put-function-*`

*Storage & Database*
- `aws s3 rm` / `s3api delete-*` / `s3api put-lifecycle-*`
- `aws rds delete-db-instance` / `modify-db-instance` / `delete-db-cluster`
- `aws dynamodb delete-table` / `update-table` / `delete-item`
- `aws redshift delete-cluster` / `modify-cluster` / `delete-cluster-snapshot`

*Managed Services*
- `aws elasticache delete-cache-cluster` / `modify-cache-cluster` / `delete-replication-group`
- `aws mq delete-broker` / `update-broker`
- `aws kafka delete-cluster` / `update-cluster-configuration`
- `aws kinesis delete-stream` / `merge-shards` / `split-shard`
- `aws firehose delete-delivery-stream` / `update-destination`
- `aws es delete-elasticsearch-domain` / `update-elasticsearch-domain-config`
- `aws transfer delete-server` / `delete-user` / `update-server`

*Security & Networking*
- `aws wafv2 delete-web-acl` / `update-web-acl`
- `aws cloudtrail delete-trail` / `update-trail` / `stop-logging`
- `aws guardduty delete-detector` / `disable-organization-admin-account`
- `aws config delete-configuration-recorder` / `delete-delivery-channel`
- `aws secretsmanager delete-secret` / `put-secret-value` / `update-secret`
- `aws ecr delete-repository` / `delete-lifecycle-policy` / `batch-delete-image`

*Identity & Messaging*
- `aws cognito-idp delete-user-pool` / `update-user-pool` / `admin-delete-user`
- `aws cognito-identity delete-identity-pool` / `update-identity-pool`
- `aws ses delete-identity` / `update-*` / `put-*`

*CDN & API*
- `aws cloudfront delete-distribution` / `update-distribution`
- `aws apigateway delete-rest-api` / `update-rest-api` / `delete-stage`
- `aws elasticloadbalancing delete-load-balancer` / `delete-listener` / `delete-target-group`

*General rule — any subcommand containing:*
`apply`, `deploy`, `create`, `delete`, `modify`, `update`, `put`, `attach`, `detach`, `terminate`, `release`, `disable`, `stop`, `remove`, `batch-delete`, `purge`

**The output of this skill is recommendations only.** A human must review and deliberately apply them.

If the user asks you to apply a fix directly, respond: _"This skill is read-only. I can generate the exact commands/code for you to review and apply yourself."_

---

## Execution Mode: Orchestrator + Parallel Domain Agents

An AWS cost audit generates 30–100K+ tokens of raw CLI output and many sequential API calls. Use a 3-tier agent architecture that collects all domains in parallel, then analyzes sequentially.

```
Main Agent
└── Orchestrator (general-purpose subagent)
    ├── Phase 1 — Dispatch all 5 domain subagents in parallel (one per domain) in a single batch
    │   ├── [A] Compute      → EC2, RDS, Lambda, ECS, EKS, ElastiCache, MQ  (no delay)
    │   ├── [B] Storage      → S3, EBS, DynamoDB, Redshift, ECR              (sleep 5)
    │   ├── [C] Networking   → NAT, ELB, CloudFront, WAF, CloudTrail, GuardDuty, Config (sleep 10)
    │   ├── [D] Identity     → Cognito, SES, API GW, Kinesis, MSK, Transfer, Secrets, Logs (sleep 15)
    │   └── [E] Cost & RI    → Cost Explorer, Savings Plans, Reserved Instances (sleep 20)
    │       ↓ each writes findings to docs/tmp/phase1-<domain>.md
    ├── Phase 2–3 — reads all 5 temp files, analyzes + scores (inline)
    ├── Phase 4  — generates implementation artifacts (inline)
    └── Phase 5  — writes final report, cleans up docs/tmp/
```

The startup delays (sleep 5/10/15/20) stagger each agent's initial API burst to avoid thundering-herd throttling on shared services like CloudWatch.

### Orchestrator Instructions

When this skill is invoked, the **main agent** dispatches an Orchestrator subagent.

Dispatch a subagent (general-purpose). Description: "AWS cost audit — orchestrator". Give it this prompt:

> You are the AWS cost audit orchestrator. Follow these steps exactly.
>
> HARD CONSTRAINT: Read-only audit only. Never modify, delete, or create any AWS resource.
>
> Step 1 — Setup:
>   mkdir -p docs/tmp
>
> Step 2 — Read the full skill file to get all Phase 1 commands and Phase 2–5 instructions:
>   [Main agent: substitute the absolute path to SKILL.md in this skill's directory]
>
> Step 3 — Dispatch all 5 domain subagents in parallel (one per domain) in a single batch:
>
>   Agent A — Compute domain:
>     "Run all commands in the 'Domain A — Compute' section of the skill file.
>      Apply rate limiting: sleep 0.2 between loop iterations, sleep 0.5 after each
>      CloudWatch get-metric-data call. No startup delay.
>      Write all collected data to docs/tmp/phase1-compute.md."
>
>   Agent B — Storage & Data domain:
>     "Run all commands in the 'Domain B — Storage & Data' section of the skill file.
>      Apply rate limiting: sleep 0.2 between loop iterations.
>      Startup delay: sleep 5 before issuing any AWS CLI calls.
>      Write all collected data to docs/tmp/phase1-storage.md."
>
>   Agent C — Networking & Security domain:
>     "Run all commands in the 'Domain C — Networking & Security' section of the skill file.
>      Apply rate limiting: sleep 0.2 between loop iterations, sleep 0.5 after each
>      CloudWatch call.
>      Startup delay: sleep 10 before issuing any AWS CLI calls.
>      Write all collected data to docs/tmp/phase1-networking.md."
>
>   Agent D — Identity, Messaging & Data domain:
>     "Run all commands in the 'Domain D — Identity, Messaging & Data' section of the skill file.
>      Apply rate limiting: sleep 0.2 between loop iterations, sleep 0.5 after each
>      CloudWatch call.
>      Startup delay: sleep 15 before issuing any AWS CLI calls.
>      Write all collected data to docs/tmp/phase1-identity.md."
>
>   Agent E — Cost & RI domain:
>     "Run all commands in the 'Domain E — Cost & RI' section of the skill file.
>      Apply rate limiting: sleep 1 after EVERY aws ce call (Cost Explorer hard limit: 1 req/s).
>      Startup delay: sleep 20 before issuing any AWS CLI calls.
>      Write all collected data to docs/tmp/phase1-cost.md."
>
> Step 4 — Wait for all 5 agents to complete (they run in parallel; you are notified when each finishes).
>
> Step 5 — Read all 5 temp files:
>   docs/tmp/phase1-compute.md
>   docs/tmp/phase1-storage.md
>   docs/tmp/phase1-networking.md
>   docs/tmp/phase1-identity.md
>   docs/tmp/phase1-cost.md
>
> Step 6 — Run Phases 2–5 inline (Analyze, Prioritize, Artifacts, Report) per the skill file instructions.
>
> Step 7 — Clean up: rm -rf docs/tmp/
>
> Return a brief terminal summary (top 5 findings + total monthly savings).

**Main agent rule:** relay only the orchestrator's summary to the user. Point to `docs/cost-report-YYYY-MM-DD.md` for the full report. Do not run any `aws` CLI commands in the main context.

### Focused / Anomaly Mode

For focused or anomaly mode (single domain), skip the parallel architecture and run a single subagent directly (no orchestrator needed — the scope is small enough to stay in one context).

---

## When to Use

- Asked to "optimize AWS costs", "reduce our AWS bill", "audit spend", or "find waste"
- Notified of a budget alert or unexpected cost spike
- Pre-planning a cost review before a business review

**When NOT to use:**
- AWS credentials are not configured (verify with `aws sts get-caller-identity` first)
- Scope is already known — use the focused mode at the bottom instead

---

## Linear Audit Workflow

Announce at the start: _"Starting AWS cost audit (read-only). This will collect data across compute, storage, networking, managed services, and tooling. No changes will be made."_

### Phase 1 — Discover

> **Prerequisite:** `jq` is required for Phase 1 data collection.
> Check: `command -v jq` — install with `brew install jq` (macOS) or `sudo apt install jq` (Linux).

Phase 1 is split into 5 independent domain groups. In parallel mode, each runs as a separate subagent and writes its output to `docs/tmp/phase1-<domain>.md`. In focused mode, run only the relevant domain.

---

#### Domain A — Compute
*Covers: EC2, RDS, Lambda, ECS, EKS, ElastiCache, Amazon MQ, Reserved Instances, Compute Optimizer*
*Startup delay: none — start immediately*

**EC2 & Spot**
```bash
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags]' --output table
aws ec2 describe-spot-instance-requests --query 'SpotInstanceRequests[].[InstanceId,State,SpotPrice]' --output table
```

**Reserved Instances (EC2 & RDS — required for Phase 2 rightsizing timing)**
```bash
# EC2 Reserved Instances — note InstanceType, InstanceCount, and End date
aws ec2 describe-reserved-instances \
  --filters Name=state,Values=active \
  --query 'ReservedInstances[].[ReservedInstancesId,InstanceType,InstanceCount,End,OfferingType]' \
  --output table

# RDS Reserved DB Instances — note DBInstanceClass and expiry
aws rds describe-reserved-db-instances \
  --query 'ReservedDBInstances[].[ReservedDBInstanceId,DBInstanceClass,MultiAZ,OfferingType,StartTime,Duration,State]' \
  --output table
```
Store RI expiry dates — required in Phase 4 to determine safe downsize timing for every rightsizing recommendation.

**Compute Optimizer Rightsizing (primary source)**

Compute Optimizer analyzes 14 days of CloudWatch data automatically. Always try this first before manual CloudWatch queries.

```bash
# Check enrollment status first
aws compute-optimizer get-enrollment-status --output json

# EC2 rightsizing recommendations
# NOTE: --filters raises InvalidParameterValueException for EC2; filter with jq instead
aws compute-optimizer get-ec2-instance-recommendations --output json \
  | jq -r '
      .instanceRecommendations | map(select(.finding == "OVER_PROVISIONED")) as $r |
      "Overprovisioned EC2 instances: \($r | length)",
      ($r | sort_by(-.recommendationOptions[0].estimatedMonthlySavings.value)[] |
        [(.instanceArn | split("/")[-1]),
         .currentInstanceType,
         (.recommendationOptions[0].instanceType // "?"),
         ("$" + ((.recommendationOptions[0].estimatedMonthlySavings.value // 0) | tostring) + "/mo")]
        | @tsv),
      "Total savings: $\([$r[].recommendationOptions[0].estimatedMonthlySavings.value // 0] | add // 0)/mo"'

# Lambda rightsizing recommendations
aws compute-optimizer get-lambda-function-recommendations \
  --filters name=finding,values=Overprovisioned \
  --output json \
  | jq -r '
      "Overprovisioned Lambda functions: \(.lambdaFunctionRecommendations | length)",
      (.lambdaFunctionRecommendations[0:20][] |
        [(.functionArn | split(":")[-1] | .[0:50]),
         ((.memorySizeRecommendationOptions[0].memorySize // "?") | tostring) + "MB",
         ("$" + ((.memorySizeRecommendationOptions[0].estimatedMonthlySavings.value // 0) | tostring) + "/mo")]
        | @tsv)'
```

**EC2 CloudWatch Fallback** (only if Compute Optimizer is not enrolled or has no data)

```bash
# Fallback: query CPU for specific large instances via Python
python3 << 'PYEOF'
import subprocess, json, time
from datetime import datetime, timezone, timedelta
end = datetime.now(timezone.utc)
start = end - timedelta(days=14)
S = start.strftime("%Y-%m-%dT%H:%M:%SZ"); E = end.strftime("%Y-%m-%dT%H:%M:%SZ")

# Get running instances larger than t3.medium/t3a.medium
r = subprocess.run(["aws","ec2","describe-instances","--output","json"], capture_output=True, text=True)
data = json.loads(r.stdout)
large_types = {'t3.large','t3.xlarge','t3.2xlarge','t3a.large','t3a.xlarge','m5.large','m5.xlarge','r5.large','r5.xlarge','c5.large','c5.xlarge','c7g.large','m6g.xlarge'}
targets = []
for res in data['Reservations']:
    for i in res['Instances']:
        if i['State']['Name'] == 'running' and i['InstanceType'] in large_types:
            name = next((t['Value'] for t in i.get('Tags',[]) if t['Key']=='Name'), '(no name)')
            # Skip ECS ASG nodes — they auto-scale and are expected to be busy
            if 'ECSCluster' in name or 'ASG' in name: continue
            targets.append((i['InstanceId'], i['InstanceType'], name))

print(f"Querying {len(targets)} non-ASG large instances...")
for iid, itype, name in targets:
    q = [{"Id":"cpu","MetricStat":{"Metric":{"Namespace":"AWS/EC2","MetricName":"CPUUtilization","Dimensions":[{"Name":"InstanceId","Value":iid}]},"Period":1209600,"Stat":"Average"}}]
    res = subprocess.run(["aws","cloudwatch","get-metric-data","--start-time",S,"--end-time",E,"--metric-data-queries",json.dumps(q),"--output","json"],capture_output=True,text=True)
    time.sleep(0.5)  # Rate limit: CloudWatch get-metric-data
    vals = json.loads(res.stdout).get("MetricDataResults",[{}])[0].get("Values",[])
    avg = vals[0] if vals else None
    flag = "*** LOW (<10%)" if avg and avg < 10 else ("** MED (<20%)" if avg and avg < 20 else "OK")
    cpu_s = f"{avg:.1f}%" if avg else "no data"
    print(f"{iid:<25}{itype:<14}{name:<30}{cpu_s:>10}  {flag}")
PYEOF
```

**RDS**
```bash
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,MultiAZ,Engine,DBInstanceStatus]' --output table
```

**Utilization — RDS**

> **API constraint:** CloudWatch Metrics Insights allows only **1** `SELECT ... EXPRESSION` per `get-metric-data` call. Make one call per metric and merge results in Python.

```bash
python3 << 'PYEOF'
import subprocess, json, time
from datetime import datetime, timezone, timedelta

end = datetime.now(timezone.utc)
start = end - timedelta(days=14)
S = start.strftime("%Y-%m-%dT%H:%M:%SZ")
E = end.strftime("%Y-%m-%dT%H:%M:%SZ")

def insights_query(expression):
    """One expression per call — CloudWatch Metrics Insights limit."""
    q = json.dumps([{"Id": "m", "Expression": expression, "Period": 1209600}])
    r = subprocess.run(["aws","cloudwatch","get-metric-data",
                        "--start-time",S,"--end-time",E,
                        "--metric-data-queries",q,"--output","json"],
                       capture_output=True, text=True)
    time.sleep(0.5)  # Rate limit: CloudWatch get-metric-data
    out = {}
    for item in json.loads(r.stdout).get("MetricDataResults", []):
        label = item.get("Label", "")
        parts = label.split()
        key = parts[-1] if parts else label
        vals = item.get("Values", [])
        out[key] = vals[0] if vals else None
    return out

cpu_data  = insights_query('SELECT AVG(CPUUtilization) FROM SCHEMA("AWS/RDS",DBInstanceIdentifier) GROUP BY DBInstanceIdentifier')
conn_data = insights_query('SELECT AVG(DatabaseConnections) FROM SCHEMA("AWS/RDS",DBInstanceIdentifier) GROUP BY DBInstanceIdentifier')
mem_data  = insights_query('SELECT AVG(FreeableMemory) FROM SCHEMA("AWS/RDS",DBInstanceIdentifier) GROUP BY DBInstanceIdentifier')

all_keys = sorted(set(list(cpu_data) + list(conn_data) + list(mem_data)))
print(f'{"Instance":<45} {"Avg CPU%":>10} {"Avg Conns":>10} {"Free Mem GB":>12}')
print('-'*80)
for inst in all_keys:
    cpu  = cpu_data.get(inst)
    conn = conn_data.get(inst)
    mem  = mem_data.get(inst)
    flag = ' ***' if cpu and cpu < 10 else ''
    cpu_s  = f'{cpu:.1f}%'            if cpu  else 'n/a'
    conn_s = f'{conn:.0f}'            if conn else 'n/a'
    mem_s  = f'{mem/1024/1024/1024:.1f}' if mem else 'n/a'
    print(f'{inst:<45} {cpu_s:>10} {conn_s:>10} {mem_s:>12}{flag}')
PYEOF
```

**Lambda**
```bash
aws lambda list-functions --query 'Functions[].[FunctionName,MemorySize,Timeout,Runtime]' --output table
```

**Utilization — Lambda (memory & duration efficiency)**
```bash
START=$(date -u -v-14d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Focus on 1024MB+ functions — most likely over-provisioned
aws lambda list-functions \
  --query 'Functions[?MemorySize>=`1024`].[FunctionName,MemorySize,Timeout]' \
  --output json | python3 -c "
import json,sys,subprocess,time
fns=json.load(sys.stdin)
print(f'{\"Function\":<55} {\"Alloc MB\":>8} {\"Avg Dur ms\":>10} {\"Max Dur ms\":>10} {\"Util%\":>7}')
print('-'*95)
for fn in fns:
    name,mem,timeout=fn
    q=json.dumps([
      {\"Id\":\"avg\",\"MetricStat\":{\"Metric\":{\"Namespace\":\"AWS/Lambda\",\"MetricName\":\"Duration\",\"Dimensions\":[{\"Name\":\"FunctionName\",\"Value\":name}]},\"Period\":1209600,\"Stat\":\"Average\"}},
      {\"Id\":\"max\",\"MetricStat\":{\"Metric\":{\"Namespace\":\"AWS/Lambda\",\"MetricName\":\"Duration\",\"Dimensions\":[{\"Name\":\"FunctionName\",\"Value\":name}]},\"Period\":1209600,\"Stat\":\"Maximum\"}}
    ])
    result=subprocess.run(['aws','cloudwatch','get-metric-data','--start-time','$START','--end-time','$END','--metric-data-queries',q,'--output','json'],capture_output=True,text=True)
    time.sleep(0.5)  # Rate limit: CloudWatch get-metric-data
    try:
        data=json.loads(result.stdout)
        avg_dur=None; max_dur=None
        for r in data.get('MetricDataResults',[]):
            if r['Id']=='avg' and r['Values']: avg_dur=r['Values'][0]
            if r['Id']=='max' and r['Values']: max_dur=r['Values'][0]
        util=f'{avg_dur/(timeout*1000)*100:.0f}%' if avg_dur else 'n/a'
        avg_s=f'{avg_dur:.0f}' if avg_dur else 'n/a'
        max_s=f'{max_dur:.0f}' if max_dur else 'n/a'
        flag=' ***' if avg_dur and avg_dur<(timeout*1000*0.1) else ''
        print(f'{name:<55} {mem:>8} {avg_s:>10} {max_s:>10} {util:>7}{flag}')
    except: print(f'{name:<55} {mem:>8} {\"err\":>10}')
"
```

**ECS**
```bash
aws ecs list-clusters --output table
```

**EKS**
```bash
aws eks list-clusters --output json | python3 -c "
import json, sys, subprocess, time
data = json.load(sys.stdin)
clusters = data.get('clusters', [])
print(f'EKS clusters: {len(clusters)}')
for name in clusters:
    r = subprocess.run(['aws','eks','describe-cluster','--name',name,'--output','json'], capture_output=True, text=True)
    time.sleep(0.2)  # Rate limit: sequential describe calls
    c = json.loads(r.stdout).get('cluster', {})
    version = c.get('version', '?')
    status = c.get('status', '?')
    print(f'  {name:<50} k8s:{version}  {status}')
    # List node groups
    ng_r = subprocess.run(['aws','eks','list-nodegroups','--cluster-name',name,'--output','json'], capture_output=True, text=True)
    time.sleep(0.2)
    ngs = json.loads(ng_r.stdout).get('nodegroups', [])
    for ng in ngs:
        ngd_r = subprocess.run(['aws','eks','describe-nodegroup','--cluster-name',name,'--nodegroup-name',ng,'--output','json'], capture_output=True, text=True)
        time.sleep(0.2)
        ngd = json.loads(ngd_r.stdout).get('nodegroup', {})
        scaling = ngd.get('scalingConfig', {})
        itype = ngd.get('instanceTypes', ['?'])[0]
        print(f'    NodeGroup: {ng:<40} {itype:<14} min:{scaling.get(\"minSize\",\"?\")} desired:{scaling.get(\"desiredSize\",\"?\")} max:{scaling.get(\"maxSize\",\"?\")}')
"
```

Waste signals: node groups where `desiredSize` == `minSize` for extended periods (no autoscaling happening) with low CPU → cluster may be oversized; control plane costs $0.10/hr (~$73/month) per cluster regardless of usage — dev clusters left running 24/7.

**ElastiCache**
```bash
aws elasticache describe-cache-clusters --query 'CacheClusters[].[CacheClusterId,CacheNodeType,NumCacheNodes,CacheClusterStatus]' --output table
```

**Utilization — ElastiCache**

> **API constraint:** Same 1-expression-per-call limit applies — use separate calls per metric.

```bash
python3 << 'PYEOF'
import subprocess, json, time
from datetime import datetime, timezone, timedelta

end = datetime.now(timezone.utc)
start = end - timedelta(days=14)
S = start.strftime("%Y-%m-%dT%H:%M:%SZ")
E = end.strftime("%Y-%m-%dT%H:%M:%SZ")

def insights_query(expression):
    q = json.dumps([{"Id": "m", "Expression": expression, "Period": 1209600}])
    r = subprocess.run(["aws","cloudwatch","get-metric-data",
                        "--start-time",S,"--end-time",E,
                        "--metric-data-queries",q,"--output","json"],
                       capture_output=True, text=True)
    time.sleep(0.5)  # Rate limit: CloudWatch get-metric-data
    out = {}
    for item in json.loads(r.stdout).get("MetricDataResults", []):
        label = item.get("Label", "")
        parts = label.split()
        key = parts[-1] if parts else label
        vals = item.get("Values", [])
        out[key] = vals[0] if vals else None
    return out

cpu_data   = insights_query('SELECT AVG(CPUUtilization) FROM SCHEMA("AWS/ElastiCache",CacheClusterId) GROUP BY CacheClusterId')
hits_data  = insights_query('SELECT SUM(CacheHits) FROM SCHEMA("AWS/ElastiCache",CacheClusterId) GROUP BY CacheClusterId')
miss_data  = insights_query('SELECT SUM(CacheMisses) FROM SCHEMA("AWS/ElastiCache",CacheClusterId) GROUP BY CacheClusterId')

all_keys = sorted(set(list(cpu_data) + list(hits_data) + list(miss_data)))
print(f'{"ClusterId":<30} {"Avg CPU%":>10} {"Hit Rate%":>10}')
print('-'*55)
for cid in all_keys:
    cpu   = cpu_data.get(cid)
    hits  = hits_data.get(cid) or 0
    miss  = miss_data.get(cid) or 0
    total = hits + miss
    hit_rate = (hits / total * 100) if total > 0 else None
    cpu_s = f'{cpu:.1f}%'      if cpu      else 'n/a'
    hr_s  = f'{hit_rate:.1f}%' if hit_rate is not None else 'n/a'
    flag  = ' *** LOW CPU (<20%)' if cpu and cpu < 20 else ''
    print(f'{cid:<30} {cpu_s:>10} {hr_s:>10}{flag}')
PYEOF
```

**Amazon MQ**
```bash
# MQ can be a significant cost — always include in discovery
aws mq list-brokers --output json \
  | jq -r '
      "Amazon MQ Brokers: \(.BrokerSummaries | length)",
      (.BrokerSummaries[] |
        [.BrokerName, .BrokerState, .DeploymentMode, .EngineType] | @tsv)'
# For each broker, get the host instance type:
# aws mq describe-broker --broker-id <broker-id>
# Check: dev/staging brokers should not use the same instance type as production
```

Requires `mq:ListBrokers` and `mq:DescribeBroker` permissions.

---

#### Domain B — Storage & Data
*Covers: S3, EBS/Snapshots, DynamoDB, Redshift, ECR*
*Startup delay: `sleep 5` before issuing any AWS CLI calls*

**S3 & EBS**
```bash
aws s3api list-buckets --query 'Buckets[].Name' --output table
# For each bucket, check lifecycle:
aws s3api get-bucket-lifecycle-configuration --bucket <bucket-name>
aws ec2 describe-volumes --query 'Volumes[?State==`available`].[VolumeId,Size,VolumeType,CreateTime]' --output table
aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime,Description]' --output table
```

**DynamoDB**
```bash
aws dynamodb list-tables --output json | jq -r '"DynamoDB tables: \(.TableNames | length)", .TableNames[]' | {
  read -r header; echo "$header"
  while IFS= read -r table; do
    aws dynamodb describe-table --table-name "$table" --output json | jq -r --arg t "$table" '
      .Table |
      (.BillingModeSummary.BillingMode // "PROVISIONED") as $billing |
      (.TableSizeBytes // 0 / 1073741824 | . * 100 | round / 100) as $gb |
      (.ProvisionedThroughput.ReadCapacityUnits // 0) as $rcu |
      (.ProvisionedThroughput.WriteCapacityUnits // 0) as $wcu |
      "  \($t)  \($billing)  RCU:\($rcu) WCU:\($wcu)  \($gb)GB\(if $billing == "PROVISIONED" and ($rcu > 0 or $wcu > 0) then "  *** CHECK UTILIZATION" else "" end)"'
    sleep 0.2  # Rate limit: sequential describe-table calls
  done
}
```

Waste signals: tables in PROVISIONED mode where actual consumed RCU/WCU (check CloudWatch `ConsumedReadCapacityUnits` / `ConsumedWriteCapacityUnits`) is consistently less than 20% of provisioned — switch to PAY_PER_REQUEST (on-demand) billing mode. Small/dev tables are almost always cheaper on-demand.

**Redshift**
```bash
aws redshift describe-clusters --output json | jq -r '
  "Redshift clusters: \(.Clusters | length)",
  (.Clusters[] | [
    .ClusterIdentifier,
    .NodeType,
    ((.NumberOfNodes | tostring) + " nodes"),
    .ClusterStatus,
    (if .ClusterAvailabilityStatus == "Paused" then "PAUSED"
     elif .NumberOfNodes == 1 then "*** SINGLE NODE"
     else "" end)
  ] | @tsv)'
```

Waste signals: Redshift clusters not using pause/resume scheduling (significant cost if queries only run during business hours); single-node clusters on large instance types (consider downsizing); clusters with no recent queries (check `QueriesCompletedPerSecond` CloudWatch metric).

**ECR (Elastic Container Registry)**
```bash
aws ecr describe-repositories --output json | jq -r '
  "ECR repositories: \(.repositories | length)",
  .repositories[].repositoryName' | {
  read -r header; echo "$header"
  while IFS= read -r repo; do
    aws ecr describe-images --repository-name "$repo" --output json 2>/dev/null | jq -r --arg repo "$repo" '
      .imageDetails as $imgs |
      ([$imgs[].imageSizeInBytes // 0] | add // 0) as $bytes |
      ([$imgs[] | select((.imageTags // []) | length == 0)] | length) as $untagged |
      "  \($repo)  images:\($imgs | length)  \($bytes / 1073741824 | . * 100 | round / 100)GB  untagged:\($untagged)\(if $untagged > 0 then " ***" else "" end)"'
    sleep 0.2  # Rate limit: sequential describe-images calls
  done
}
echo "ECR storage cost: \$0.10/GB/month"
```

Waste signals: untagged images are orphaned build artifacts — safe to delete; old tagged images (> 90 days) with no active ECS/EKS deployment reference; total storage > 50 GB warrants a lifecycle policy.

---

#### Domain C — Networking & Security
*Covers: NAT, EIP, VPC Endpoints, ELB, CloudFront, WAF, CloudTrail, GuardDuty, AWS Config*
*Startup delay: `sleep 10` before issuing any AWS CLI calls*

**Networking (NAT, EIPs, VPC Endpoints)**
```bash
aws ec2 describe-nat-gateways --query 'NatGateways[].[NatGatewayId,State,VpcId,CreateTime]' --output table
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,InstanceId,AllocationId]' --output table
aws ec2 describe-vpc-endpoints --output table 2>/dev/null || true
```

**Elastic Load Balancing**
```bash
python3 << 'PYEOF'
import subprocess, json, time

# List all ALBs/NLBs
r = subprocess.run(["aws","elbv2","describe-load-balancers","--output","json"], capture_output=True, text=True)
lbs = json.loads(r.stdout).get("LoadBalancers", [])
print(f"Load balancers: {len(lbs)}")

# For each LB, check if it has any target groups with healthy targets
for lb in lbs:
    name = lb["LoadBalancerName"]
    lb_arn = lb["LoadBalancerArn"]
    lb_type = lb["Type"]

    # Get target groups for this LB
    tg_r = subprocess.run(["aws","elbv2","describe-target-groups","--load-balancer-arn",lb_arn,"--output","json"], capture_output=True, text=True)
    time.sleep(0.2)  # Rate limit: sequential describe calls
    tgs = json.loads(tg_r.stdout).get("TargetGroups", [])

    healthy = 0
    for tg in tgs:
        th_r = subprocess.run(["aws","elbv2","describe-target-health","--target-group-arn",tg["TargetGroupArn"],"--output","json"], capture_output=True, text=True)
        time.sleep(0.2)  # Rate limit: sequential describe-target-health calls
        targets = json.loads(th_r.stdout).get("TargetHealthDescriptions", [])
        healthy += sum(1 for t in targets if t.get("TargetHealth",{}).get("State") == "healthy")

    flag = " *** NO HEALTHY TARGETS" if healthy == 0 else ""
    print(f"  {name:<50} {lb_type:<8} targets:{healthy:>3}{flag}")
PYEOF
```

Waste signals: LBs with 0 healthy targets are idle but still charged ~$0.008/LCU-hour plus $0.018/hour base. Classic waste after a service is decommissioned but the LB is forgotten.

**CloudFront**
```bash
aws cloudfront list-distributions --output json | jq -r '
  "CloudFront distributions: \(.DistributionList.Items | length)",
  (.DistributionList.Items[] | [
    .DomainName,
    .PriceClass,
    (.Enabled | tostring),
    (.Origins.Items[0].DomainName // "no-origin" | .[0:40]),
    (if .Enabled == false then "*** DISABLED"
     elif .PriceClass == "PriceClass_All" then "*** ALL EDGE LOCATIONS"
     else "" end)
  ] | @tsv)'
```

Waste signals: distributions with `Enabled=False` still incur charges for SSL certificates and stored objects; `PriceClass_All` (all edge locations) costs more than `PriceClass_100` (US/EU only) — verify global reach is required; distributions with no traffic in 30 days (check `Requests` CloudWatch metric).

**WAF (Web Application Firewall)**
```bash
python3 << 'PYEOF'
import subprocess, json, time

total_cost = 0

for scope in ["REGIONAL", "CLOUDFRONT"]:
    r = subprocess.run(["aws","wafv2","list-web-acls","--scope",scope,"--output","json"], capture_output=True, text=True)
    if r.returncode != 0:
        continue
    acls = json.loads(r.stdout).get("WebACLs", [])
    print(f"WAF Web ACLs ({scope}): {len(acls)}")
    for acl in acls:
        acl_r = subprocess.run(["aws","wafv2","get-web-acl","--name",acl["Name"],"--scope",scope,"--id",acl["Id"],"--output","json"], capture_output=True, text=True)
        time.sleep(0.2)  # Rate limit: sequential get-web-acl calls
        if acl_r.returncode == 0:
            acl_detail = json.loads(acl_r.stdout).get("WebACL", {})
            rules = len(acl_detail.get("Rules", []))
            est_cost = 5 + rules  # $5/ACL + $1/rule
            total_cost += est_cost
            print(f"  {acl['Name']:<50} {rules} rules  ~${est_cost}/month")

print(f"\nTotal WAF estimated cost: ~${total_cost}/month")
print("Note: actual cost also includes $0.60 per 1M requests inspected")
PYEOF
```

Waste signals: WAF Web ACLs cost $5/month each plus $1/month per rule — unused ACLs (not attached to ALB/CloudFront/API GW) are pure waste; managed rule groups add $1+/month per 10 rules.

**CloudTrail**
```bash
aws cloudtrail describe-trails --output json | jq -r '
  "CloudTrail trails: \(.trailList | length)",
  (.trailList[] | [
    .Name,
    .S3BucketName,
    (.IsMultiRegionTrail | tostring),
    (.CloudWatchLogsLogGroupArn // "none" | split(":")[-1] | .[0:40])
  ] | @tsv),
  "Note: first trail/region is free; additional = \$2/100k events; CW Logs delivery = \$0.50/GB"'
```

Waste signals: multiple trails covering the same region/events — the first trail is free, additional ones charge $2/100k events; trails delivering to CloudWatch Logs incur ingestion cost ($0.50/GB) — if logs aren't actively queried, disable CW delivery and keep only S3.

**GuardDuty**
```bash
aws guardduty list-detectors --output json | jq -r '"GuardDuty detectors: \(.DetectorIds | length)", .DetectorIds[]' | {
  read -r header; echo "$header"
  while IFS= read -r did; do
    aws guardduty get-detector --detector-id "$did" --output json | jq -r --arg did "$did" '
      "  Detector: \($did)  Status: \(.Status)",
      "  Enabled features: \([.Features[]? | select(.Status == "ENABLED") | .Name] | join(", "))"'
    sleep 0.2  # Rate limit: sequential get-detector calls
  done
}
echo "Note: charged per GB analyzed; optional features (S3 Protection, EKS Runtime, Malware Scan) add per-event charges"
```

Waste signals: GuardDuty is charged per GB of data analyzed — high VPC flow log or CloudTrail volume directly increases cost; optional features (S3 Protection, EKS Runtime, Malware Protection) each add significant per-event charges — verify each is actively acted on, not just enabled and ignored; check if GuardDuty is enabled in all regions (including unused regions where it finds nothing but still charges).

**AWS Config**
```bash
aws configservice describe-configuration-recorders --output json | jq -r '
  "Config recorders: \(.ConfigurationRecorders | length)",
  (.ConfigurationRecorders[] | [
    .name,
    ("allSupported=" + (.recordingGroup.allSupported | tostring)),
    ("explicitTypes=" + (.recordingGroup.resourceTypes | length | tostring)),
    (if .recordingGroup.allSupported then "*** RECORDING ALL TYPES" else "" end)
  ] | @tsv)'

aws configservice describe-delivery-channels --output json | jq -r '
  "Delivery channels: \(.DeliveryChannels | length)",
  (.DeliveryChannels[] | ["S3:", .s3BucketName, "SNS:", (.snsTopicARN // "none")] | @tsv),
  "Note: \$0.003 per configuration item recorded — allSupported=true can be very expensive at scale"'
```

Waste signals: `allSupported=True` records every resource change across all resource types — at scale this generates millions of items/month at $0.003 each; scope the recorder to only the resource types required for compliance; multiple Config recorders in the same region (common after account merges).

---

#### Domain D — Identity, Messaging & Data
*Covers: Cognito, SES, API Gateway, Kinesis, MSK, Transfer Family, Secrets Manager, CloudWatch Logs*
*Startup delay: `sleep 15` before issuing any AWS CLI calls*

**CloudWatch Log Groups**
```bash
aws logs describe-log-groups --output json | jq -r '
  .logGroups as $g |
  "Total log groups: \($g | length)",
  "No retention policy: \([$g[] | select(.retentionInDays == null)] | length)",
  "Total stored: \([$g[].storedBytes // 0] | add / 1073741824 | . * 10 | round / 10) GB",
  "",
  "Top 15 largest log groups:",
  ($g | sort_by(-.storedBytes) | .[0:15][] |
    [(.logGroupName | .[0:64]),
     (((.storedBytes // 0) / 1073741824 | . * 100 | round / 100 | tostring) + " GB"),
     (.retentionInDays // "NONE" | tostring),
     (if .retentionInDays == null then "*** NO RETENTION" else "" end)]
    | @tsv)'
```

Waste signals: log groups with no retention policy; very large groups (>100 GB) with 365-day retention that could be reduced to 30–90 days; VPC flow logs in particular grow large quickly.

**API Gateway**
```bash
python3 << 'PYEOF'
import subprocess, json, time
from datetime import datetime, timezone, timedelta

end = datetime.now(timezone.utc)
start = end - timedelta(days=30)
S = start.strftime("%Y-%m-%dT%H:%M:%SZ")
E = end.strftime("%Y-%m-%dT%H:%M:%SZ")

# REST APIs (v1)
r = subprocess.run(["aws","apigateway","get-rest-apis","--output","json"], capture_output=True, text=True)
apis = json.loads(r.stdout).get("items", [])
print(f"REST APIs (v1): {len(apis)}")
for api in apis:
    q = json.dumps([{"Id":"req","MetricStat":{"Metric":{"Namespace":"AWS/ApiGateway","MetricName":"Count","Dimensions":[{"Name":"ApiName","Value":api["name"]}]},"Period":2592000,"Stat":"Sum"}}])
    cw = subprocess.run(["aws","cloudwatch","get-metric-data","--start-time",S,"--end-time",E,"--metric-data-queries",q,"--output","json"], capture_output=True, text=True)
    time.sleep(0.5)  # Rate limit: CloudWatch get-metric-data
    vals = json.loads(cw.stdout).get("MetricDataResults",[{}])[0].get("Values",[])
    req_count = int(vals[0]) if vals else 0
    flag = " *** NO TRAFFIC" if req_count == 0 else ""
    print(f"  {api['name']:<50} {req_count:>10} requests/30d{flag}")

# HTTP APIs (v2)
r2 = subprocess.run(["aws","apigatewayv2","get-apis","--output","json"], capture_output=True, text=True)
time.sleep(0.2)
apis2 = json.loads(r2.stdout).get("Items", [])
print(f"\nHTTP/WebSocket APIs (v2): {len(apis2)}")
for api in apis2:
    print(f"  {api['Name']:<50} {api['ProtocolType']}")
PYEOF
```

Waste signals: REST APIs with 0 requests in 30 days — API Gateway itself has no idle charge, but the associated Lambda, VPC Link, or WAF resources do. Flag for cleanup review.

**Cognito**
```bash
aws cognito-idp list-user-pools --max-results 60 --output json | jq -r '
  "Cognito User Pools: \(.UserPools | length)",
  (.UserPools[] | [.Name, .Id, (.LastModifiedDate // "?" | .[0:10])] | @tsv)'

aws cognito-identity list-identity-pools --max-results 60 --output json 2>/dev/null | jq -r '
  "Cognito Identity Pools: \(.IdentityPools | length)",
  (.IdentityPools[] | [.IdentityPoolName, .IdentityPoolId] | @tsv)' || true
```

Waste signals: Cognito is priced per Monthly Active User (MAU) — the first 50,000 MAUs are free. Cost only appears above that threshold. Check for dev/staging user pools that could be consolidated or deleted. Each separate user pool incurs overhead even with few users. No direct "rightsizing" exists — flag pools that appear to be unused/dev.

**SES (Simple Email Service)**
```bash
# Dedicated IPs — $24.95/IP/month regardless of usage
aws sesv2 list-dedicated-ip-pools --output json 2>/dev/null | jq -r '.DedicatedIpPools[]' | while read -r pool; do
  count=$(aws sesv2 get-dedicated-ips --pool-name "$pool" --output json 2>/dev/null | jq '.DedicatedIps | length')
  echo "SES Dedicated IP Pool '$pool': $count IPs = \$$(echo "$count * 24.95" | awk '{printf "%.2f", $1}') /month"
  sleep 0.2  # Rate limit: sequential get-dedicated-ips calls
done

# Sending statistics (last 14 days)
aws ses get-send-statistics --output json | jq -r '
  .SendDataPoints as $dp |
  "SES sending (14 days): \([$dp[].DeliveryAttempts] | add // 0) emails sent, \([$dp[].Bounces] | add // 0) bounced",
  "Approx cost at \$0.10/1000: \$\(([$dp[].DeliveryAttempts] | add // 0) / 1000 * 0.10 | . * 100 | round / 100)"'
```

Waste signals: dedicated IPs at $24.95/IP/month are the primary fixed cost — if sending volume is low (< ~100k emails/month), shared IPs are free and preferable; high bounce rate (> 5%) may indicate list hygiene issues inflating send volume.

**Kinesis**
```bash
# Kinesis Data Streams
aws kinesis list-streams --output json | jq -r '"Kinesis Data Streams: \(.StreamNames | length)", .StreamNames[]' | {
  read -r header; echo "$header"
  while IFS= read -r stream; do
    aws kinesis describe-stream-summary --stream-name "$stream" --output json \
      | jq -r --arg s "$stream" '"  \($s)  shards:\(.StreamDescriptionSummary.OpenShardCount)  retention:\(.StreamDescriptionSummary.RetentionPeriodHours)h"'
    sleep 0.2  # Rate limit: sequential describe-stream-summary calls
  done
}
echo "Cost: each shard = \$0.015/hr = \$10.95/month regardless of utilization"

# Kinesis Firehose
aws firehose list-delivery-streams --output json | jq -r '"Kinesis Firehose: \(.DeliveryStreamNames | length)", .DeliveryStreamNames[]' | {
  read -r header; echo "$header"
  while IFS= read -r stream; do
    aws firehose describe-delivery-stream --delivery-stream-name "$stream" --output json \
      | jq -r --arg s "$stream" '"  \($s)  status:\(.DeliveryStreamDescription.DeliveryStreamStatus)  → \(.DeliveryStreamDescription.Destinations[0] | keys[0])"'
    sleep 0.2  # Rate limit: sequential describe-delivery-stream calls
  done
}
```

Waste signals: Kinesis Data Streams with shards consistently under 10% utilization (check `IncomingBytes` and `IncomingRecords` CloudWatch metrics); idle Firehose streams in ACTIVE state still charge for data processed.

**MSK (Managed Streaming for Kafka)**
```bash
aws kafka list-clusters --output json | jq -r '
  "MSK clusters: \(.ClusterInfoList | length)",
  (.ClusterInfoList[] | [
    .ClusterName,
    .State,
    .BrokerNodeGroupInfo.InstanceType,
    ((.BrokerNodeGroupInfo.ClientSubnets | length | tostring) + " AZs"),
    ((.BrokerNodeGroupInfo.StorageInfo.EbsStorageInfo.VolumeSize // "?") | tostring) + "GB EBS"
  ] | @tsv)' 2>&1 || echo "No MSK clusters or insufficient permissions"
```

Waste signals: MSK brokers in 3 AZs triple the broker-hour cost — verify HA is required (dev clusters rarely need 3 AZs); `kafka.m5.4xlarge` or larger brokers at low throughput; EBS storage over-provisioned (storage can be expanded but not shrunk).

**Transfer Family**
```bash
aws transfer list-servers --output json | jq -r '
  "Transfer Family servers: \(.Servers | length)",
  "Note: each server = \$0.30/hr = \$219/month regardless of usage",
  (.Servers[] | [
    .ServerId,
    (.Protocols | join(",")),
    .State,
    .EndpointType,
    (if .State == "OFFLINE" then "*** OFFLINE"
     elif .State == "STOPPING" then "*** STOPPING"
     else "" end)
  ] | @tsv)'
```

Waste signals: Transfer Family servers cost $0.30/hr (~$219/month) each whether or not anyone is connected — OFFLINE/unused servers are pure waste; servers with no active users configured; `PUBLIC` endpoint type is less common and often an oversight.

**Secrets Manager**
```bash
aws secretsmanager list-secrets --output json | jq -r '
  .SecretList as $s |
  "Secrets: \($s | length)  (~$\($s | length * 0.40)/month at \$0.40/secret)",
  "Note: +\$0.05 per 10,000 API calls",
  ($s | sort_by(.LastAccessedDate // "") | .[0:30][] |
    [(.Name | .[0:59]),
     (.LastAccessedDate // "NEVER" | .[0:10]),
     (.LastChangedDate // "?" | .[0:10]),
     (if .LastAccessedDate == null then "*** NEVER ACCESSED" else "" end)]
    | @tsv)'
```

Waste signals: secrets never accessed or not accessed in > 90 days are candidates for deletion; $0.40/secret/month is small individually but accumulates — 100 forgotten secrets = $40/month.

---

#### Domain E — Cost & RI
*Covers: Cost Explorer 3-month spend, Savings Plans coverage, reservation utilization, tag coverage*
*Startup delay: `sleep 20` before issuing any AWS CLI calls*
*Rate limit: `sleep 1` after EVERY `aws ce` call — Cost Explorer hard limit is 1 request/second*

**OpenSearch**
```bash
DOMAINS=$(aws opensearch list-domain-names --output json | jq -r '.DomainNames[].DomainName' | tr '\n' ' ')
echo "OpenSearch domains: $(aws opensearch list-domain-names --output json | jq '.DomainNames | length')"
[ -n "$DOMAINS" ] && aws opensearch describe-domains --domain-names $DOMAINS --output json \
  | jq -r '.DomainStatusList[] | [
      .DomainName,
      .ClusterConfig.InstanceType,
      ((.ClusterConfig.InstanceCount | tostring) + "x"),
      ("ZoneAware:" + (.ClusterConfig.ZoneAwarenessEnabled | tostring)),
      ("DedicatedMaster:" + (.ClusterConfig.DedicatedMasterEnabled | tostring)),
      ((.EBSOptions.VolumeSize // "?") | tostring) + "GB"
    ] | @tsv'
```

Waste signals: clusters with `DedicatedMasterEnabled=True` but fewer than 10 nodes (dedicated masters rarely needed at small scale, ~$200+/month extra); `ZoneAwarenessEnabled=True` triples instance count — verify HA is genuinely required; instance type vs actual query volume via CloudWatch `SearchRate` metric.

**Cost Explorer — 3-Month Spend Breakdown**
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json | jq -r '
    .ResultsByTime[] | . as $p |
    "=== \($p.TimePeriod.Start) (Total: $\([$p.Groups[].Metrics.BlendedCost.Amount | tonumber] | add | . * 100 | round / 100)) ===",
    ($p.Groups
      | sort_by(-.Metrics.BlendedCost.Amount | tonumber)
      | .[0:15][]
      | select(.Metrics.BlendedCost.Amount | tonumber > 1)
      | "  $\(.Metrics.BlendedCost.Amount | tonumber | . * 100 | round / 100)  \(.Keys[0])")'
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

**Savings Plans Coverage**
```bash
aws ce get-savings-plans-coverage \
  --time-period Start=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --output json
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

**Reservation Utilization**
```bash
aws ce get-reservation-utilization \
  --time-period Start=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --output json
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

**Tag Coverage**
```bash
aws ce get-tags \
  --time-period Start=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --output json
sleep 1  # Rate limit: Cost Explorer 1 req/s
```

---

### Phase 2 — Analyze

For each domain, compare collected data against these signals:

| Domain | Waste Signal |
|--------|-------------|
| EC2 | Avg CPU < 10% over 14 days → downsize or consolidate; no Savings Plan/RI coverage > 60% |
| EBS | Volumes in `available` state (unattached); snapshots older than 90 days with no retention policy |
| S3 | Buckets with no lifecycle policy; Standard storage for objects > 90 days old |
| NAT Gateway | High data processing charges; check if VPC endpoints could replace traffic |
| Elastic IPs | No `AssociationId` AND no `NetworkInterfaceId` = truly idle |
| ELB | Load balancers with 0 healthy targets — idle LBs still charge base + LCU fee; common after service decommission |
| RDS | Avg CPU < 10% or avg connections < 5 over 14 days → downsize instance class; UAT instances running 24/7 |
| ElastiCache | Avg CPU < 20% over 14 days → downsize node type; hit rate < 80% → investigate over-allocation |
| Lambda | 1024MB+ functions where avg duration < 10% of timeout → reduce memory; use Power Tuning tool |
| Amazon MQ | Dev/staging brokers using same instance type as production (mq.m5.xlarge is expensive — dev rarely needs it) |
| Kinesis Data Streams | Shards consistently < 10% utilized (check `IncomingBytes` CloudWatch metric) — each shard costs ~$11/month regardless of usage |
| Kinesis Firehose | ACTIVE delivery streams with no recent data — charge per GB processed but still worth auditing for orphaned streams |
| DynamoDB | PROVISIONED tables where consumed RCU/WCU < 20% of provisioned → switch to PAY_PER_REQUEST; small/dev tables almost always cheaper on-demand |
| EKS | Control plane costs $73/month per cluster regardless of usage; dev clusters left running 24/7; node groups where desiredSize == minSize with low CPU |
| OpenSearch | `DedicatedMasterEnabled=True` with fewer than 10 nodes (~$200+/month wasted); `ZoneAwarenessEnabled=True` triples instance count — verify HA is required |
| API Gateway | REST APIs with 0 requests in 30 days — no idle API charge, but associated Lambda, VPC Link, WAF resources still run |
| Cognito | Dev/staging user pools that could be consolidated or deleted; cost only appears above 50k MAUs (free tier) but orphaned pools accumulate |
| SES | Dedicated IPs at $24.95/IP/month — if sending < 100k emails/month, shared IPs are free; high bounce rate inflating send volume |
| CloudFront | Disabled distributions still charge for SSL/objects; `PriceClass_All` costs more than `PriceClass_100` — verify global reach needed |
| ECR | Untagged (orphaned) images; repos with no active deployment reference; total storage > 50 GB without a lifecycle policy |
| Secrets Manager | Secrets never accessed or not accessed in > 90 days ($0.40/secret/month); 100 forgotten secrets = $40/month |
| WAF | Web ACLs not attached to any resource; managed rule groups enabled but alerts never reviewed |
| CloudTrail | Multiple trails covering same region (first is free, additional = $2/100k events); CW Logs delivery adds $0.50/GB ingestion cost — disable if logs aren't actively queried |
| GuardDuty | Optional features (S3 Protection, EKS Runtime, Malware Protection) each add per-event charges — verify each is acted on; enabled in unused regions |
| Config | `allSupported=True` records every resource type at $0.003/item — scope to only compliance-required types; duplicate recorders after account merges |
| MSK | 3-AZ broker deployment triples broker-hour cost — dev clusters rarely need 3 AZs; large broker types at low throughput |
| Redshift | No pause/resume schedule (queries only run business hours); single-node large instance; no recent queries |
| Transfer Family | Each server = $219/month regardless of usage — OFFLINE or unused servers are pure waste |
| CloudWatch | Log groups with no retention policy; large groups (>100 GB) at 365-day retention; VPC flow logs are the most common culprit |
| Reserved Instances | For every underutilized instance flagged above, check if its class is covered by an active RI — RI-covered instances carry a fixed cost regardless of size, so early downsize wastes the commitment |
| Tagging | Resources missing `env`, `team`, or `cost-center` tags — invisible spend |

---

### Phase 3 — Prioritize

Score each finding:

```
score = estimated_monthly_savings_USD × (1 / effort_points)
```

Effort points: `1` = CLI one-liner, `2` = config change, `3` = IaC refactor, `5` = architectural change.

Present the **top 10 findings** ranked by score in a table:

| # | Finding | Domain | Est. Monthly Savings | Effort | Score |
|---|---------|--------|---------------------|--------|-------|
| 1 | ... | ... | $X | 1 | X |

---

### Phase 4 — Generate Implementation Artifacts

For each top-10 finding, generate the exact fix — **do not apply it**:

- **Terraform/CDK/CloudFormation patch** if IaC exists in the repo
- **AWS CLI command** the human can run when ready
- **Policy JSON** for S3 lifecycle, IAM, or resource policies

Label every artifact clearly:

```
## Fix for Finding #1: [title]
> REVIEW BEFORE APPLYING. This is a recommendation only.

[code block with the exact change]

Estimated savings: $X/month
```

**Rightsizing fixes must include a "When" field** based on RI coverage from Phase 1:

| When value | Condition | Action |
|---|---|---|
| **Now** | No active RI covers this instance class | Safe to downsize immediately |
| **After [expiry date]** | Active RI covers this class | Wait until RI expires to avoid wasted commitment |
| **Modify RI** | Active RI is `No Upfront` or `Partial Upfront` | AWS may allow modification within the same instance family (e.g., 1× r7g.large → 2× r7g.medium); use the EC2 console → Reserved Instances → Modify |

Example format:
```
**When:** After 2027-01-15 (active r7g.large RI expires) — or modify RI to 2× r7g.medium now
```

---

### Phase 5 — Report

Save the full report to `docs/cost-report-YYYY-MM-DD.md`:

```markdown
# AWS Cost Audit Report — YYYY-MM-DD

> **READ-ONLY AUDIT.** No changes were made to AWS infrastructure.
> All items below are recommendations. A human must review and apply them.

## Executive Summary

**Account:** [account-id] ([region]) · Audit date: YYYY-MM-DD

### Spending at a Glance

| | Amount |
|--|--------|
| Current monthly run rate ([most recent full month]) | **$X/month** |
| Savings actionable right now | **$X/month (X%)** |
| Additional savings after RI expiry | **$X/month** |
| **Total savings opportunity** | **$X/month ($X/year)** |

### Where the Money Is Going

[2-3 sentence narrative: which services dominate, any surprises, overall health of Savings Plans utilization]

### What We Can Save Now

| Priority | Action | Monthly Saving |
|----------|--------|---------------|
| Quick wins (Effort 1) | [list] | **$X/month** |
| Config changes (Effort 2) | [list] | **$X/month** |
| IaC changes (Effort 3) | [list] | **$X/month** |

### What We Can Save Later (RI-Locked)

| When | Action | Monthly Saving |
|------|--------|---------------|
| After [date] | [action] | **$X/month** |

---

## Cost Trend — Last 3 Months

| Service | [Month-2] | [Month-1] | [Month] | Trend |
|---------|----------:|----------:|--------:|-------|
| ...     | $X        | $X        | $X      | ↑/↓/→ |
| **Total** | **$X** | **$X** | **$X** | |

[Key trends narrative: which services grew fastest, any anomalies]

---

## Top 10 Findings

[Top 10 table from Phase 3 with Timing column]

---

## Implementation Artifacts

[All generated fixes from Phase 4, each with When and Estimated savings]

---

## Full Data Summary

[Resource counts table]
```

Also output a brief terminal summary after saving the file.

---

## Focused Mode (optional)

If the user specifies a single domain, skip Phases 1–3 for all other domains and deep-dive only the named one. Example trigger: _"just look at our S3 costs"_.

## Anomaly Mode (optional)

If the user reports a surprise bill spike, start Phase 1 with only the cost-and-usage query, identify the top-growing service, then run the full domain analysis only for that service.

---

## Multi-Call Block: Bash+jq vs Python

The remaining Python blocks (RDS/ElastiCache utilization, ELB health, EC2 CloudWatch fallback, Lambda duration, EKS, API Gateway, WAF, SES dedicated IPs) make multiple dependent API calls or merge results across several responses. Python is kept here because:
- `jq` cannot make additional CLI calls mid-pipeline
- Data merging from N separate responses requires a loop with accumulator state

**General bash+jq pattern** for simple 1-level loops (list → describe per item):
```bash
aws <service> list-<things> --output json | jq -r '.<Things>[].<id>' | while IFS= read -r id; do
  aws <service> describe-<thing> --<id-flag> "$id" --output json | jq -r --arg id "$id" '"  \($id): \(.Thing.Field)"'
done
```

**When to choose bash+jq over Python:**
- 1 level of nesting (list → per-item describe)
- No arithmetic across responses
- No need to merge multiple API call results into one table

**When to keep Python:**
- 2+ levels of nesting (cluster → nodegroup → describe nodegroup)
- Merging results from N separate CloudWatch calls into one table (RDS, ElastiCache)
- Math across responses (hit rate = hits / (hits + misses), timeout utilization %)
- Need to skip items mid-loop based on complex logic (EC2 ASG filter)

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Skipping prioritization and trying to fix everything | Always score and rank — focus the human on the top 10 |
| Running write commands "just to test" | Forbidden. Read-only means read-only. |
| Reporting savings without effort estimate | Always include effort so the human can prioritize |
| Patching IaC without checking if it exists | Check for `.tf`, `cdk.json`, or `template.yaml` first |
| Assuming credentials are valid | Always verify with `aws sts get-caller-identity` before starting |
| Recommending downsize without RI check | Always run RI discovery first — downsizing an RI-covered instance wastes the committed spend; apply RI-aware "When" field to every rightsizing recommendation |
| Recommending "schedule UAT RDS off-hours" when covered by a No Upfront RI | RDS No Upfront RIs charge the committed hourly rate whether the instance is running or stopped — scheduling saves nothing during the RI term. Only recommend scheduling AFTER RI expiry. |
| Using `--filters name=finding,values=Overprovisioned` with `get-ec2-instance-recommendations` | This flag raises `InvalidParameterValueException`. Fetch all recommendations and filter in Python: `[r for r in recs if r.get('finding') == 'OVER_PROVISIONED']` |
| Listing all IAM actions individually in the policy document | IAM policy documents have a size limit. Use service-level wildcards instead: `ec2:Describe*`, `rds:Describe*`, `ce:Get*`, `mq:List*`, `mq:Describe*`, etc. |
| Using `apigatewayv2:GET` in IAM policy | Invalid — the IAM namespace for API Gateway v2 (HTTP APIs) is still `apigateway:`, same as v1. `apigateway:GET` covers both. The `apigatewayv2` prefix only exists in the CLI, not IAM. |
| Using `sesv2:List*` or `sesv2:Get*` in IAM policy | Invalid — SES v2 uses the same IAM namespace as SES v1: `ses:List*` and `ses:Get*`. The `sesv2` prefix only exists in the CLI, not IAM. |
| Omitting Amazon MQ from discovery | MQ can be a top-5 cost item. Always include `aws mq list-brokers` and `aws mq describe-broker` in Phase 1. Requires `mq:ListBrokers` + `mq:DescribeBroker` permissions. |
| Sending multiple Metrics Insights expressions in one CloudWatch call | CloudWatch allows only **1** `SELECT ... EXPRESSION` per `get-metric-data` call — make one call per metric and merge results in Python |
| Running Metrics Insights GROUP BY on 500+ instance fleets | Parallel burst throttles; filter to relevant instances only and use a sequential Python per-instance loop; skip ECS ASG nodes (they auto-scale) |
| Using `compute-optimizer:GetRDSInstanceRecommendations` in IAM policy | This IAM action does not exist — use CloudWatch metrics for RDS rightsizing instead |
