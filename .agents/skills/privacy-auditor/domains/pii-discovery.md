# Domain: PII Discovery & Inventory

## Controls

| Clause   | Name                                          | Severity |
|----------|-----------------------------------------------|----------|
| A.7.2.1  | Identify and document purpose                 | High     |
| A.7.4.1  | Limit processing                              | High     |
| B.8.4.1  | Temporary files / identification of processing| High     |

Controller clauses (A.7.x) apply when role = Controller or Both.
Processor clauses (B.8.x) apply when role = Processor or Both.

---

## IaC Checks

### PII-I1: Data-store resources carry the PII tag (A.7.2.1)

**Applies only when scope is tag-based** (scope = `PII_TAG_KEY=PII_TAG_VALUE`).

Search `.tf` files for every `aws_s3_bucket`, `aws_db_instance`, `aws_rds_cluster`, `aws_dynamodb_table`, `aws_ebs_volume`, `aws_efs_file_system`, `aws_redshift_cluster` resource. For each, inspect the `tags = {}` map.

**PASS:** Every data-store resource has the PII tag (matching both key and value).
**FAIL:** Any data-store resource is untagged (no `tags` attribute, or missing the PII key).
**REPORT:** Data-store resources that carry the PII key but with a different value (e.g., `DataClass = "public"`) — these are legitimate non-PII stores; include them in a REPORT-ONLY list for human review.

Remediation (Terraform):
```hcl
resource "aws_s3_bucket" "user_uploads" {
  bucket = "user-uploads"

  tags = {
    DataClass = "PII"
    Owner     = "platform-team"
  }
}
```
Closes: A.7.2.1

### PII-I2: Macie is enabled via IaC (A.7.4.1)

Search `.tf` files for `resource "aws_macie2_account"` and `resource "aws_macie2_classification_job"` blocks.

**PASS:** Both an `aws_macie2_account` resource and at least one `aws_macie2_classification_job` exist.
**PARTIAL:** Only the `aws_macie2_account` resource exists — Macie is enabled but no classification job is defined.
**FAIL:** Neither resource exists.

Remediation (Terraform):
```hcl
resource "aws_macie2_account" "main" {
  finding_publishing_frequency = "SIX_HOURS"
  status                       = "ENABLED"
}

resource "aws_macie2_classification_job" "pii_buckets" {
  name     = "weekly-pii-scan"
  job_type = "SCHEDULED"

  schedule_frequency {
    weekly_schedule = "MONDAY"
  }

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = ["user-uploads", "user-backups"]
    }
  }

  depends_on = [aws_macie2_account.main]
}
```
Closes: A.7.4.1

---

## Live Infra Checks

### PII-L1: Macie is enabled at the account level (A.7.4.1)

```bash
if session=$(aws macie2 get-macie-session --output json 2>/dev/null); then
  echo "$session" | jq -r '"Macie status: \(.status) | Created: \(.createdAt)"'
else
  echo "MACIE_NOT_ENABLED"
fi
```

**PASS:** Output includes `Macie status: ENABLED`.
**FAIL:** Output is `MACIE_NOT_ENABLED` or status is `PAUSED`.
Evidence required: `get-macie-session` output.

Remediation:
```bash
aws macie2 enable-macie --finding-publishing-frequency SIX_HOURS
```
Closes: A.7.4.1

### PII-L2: Macie classification job coverage of PII buckets (A.7.4.1)

```bash
aws macie2 list-classification-jobs --output json \
  | jq -r '.items[] | [.jobId, .name, .jobStatus] | @tsv'
sleep 0.2

for job_id in $(aws macie2 list-classification-jobs --output json | jq -r '.items[] | select(.jobStatus == "RUNNING" or .jobStatus == "IDLE") | .jobId'); do
  aws macie2 describe-classification-job --job-id "$job_id" --output json \
    | jq -r --arg j "$job_id" '.s3JobDefinition.bucketDefinitions[]? | [$j, .accountId, (.buckets | join(","))] | @tsv'
  sleep 0.2
done
```

Cross-reference: how many PII-scoped buckets appear in at least one active classification job?

**REPORT:** Ratio `covered / total_pii_buckets` (e.g., `"7 of 12 PII buckets covered by Macie classification jobs"`). Always REPORT — coverage is a factual observation, not pass/fail (a bucket may legitimately be excluded for cost reasons).
Evidence required: list of classification jobs with their bucket definitions.

### PII-L3: Macie sensitive-data findings counts by type (A.7.2.1, A.7.4.1)

```bash
aws macie2 list-findings --finding-criteria '{"criterion":{"category":{"eq":["CLASSIFICATION"]}}}' --output json \
  | jq -r '.findingIds[]' \
  | head -50 \
  | while read -r fid; do
    aws macie2 get-findings --finding-ids "$fid" --output json \
      | jq -r '.findings[0] | [.type, .severity.description, .resourcesAffected.s3Bucket.name] | @tsv'
    sleep 0.2
  done
```

Limit to 50 findings for performance. Aggregate by finding type.

**REPORT:** Counts of findings per sensitive-data type (e.g., `"US_SSN: 12 findings across 3 buckets"`). Always REPORT — findings are evidence that needs human review against your ROPA.
Evidence required: sampled findings grouped by type.

### PII-L4: Inventory of PII-scoped resources with tags (A.7.2.1)

**Applies only when scope is tag-based.**

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key="$PII_TAG_KEY",Values="$PII_TAG_VALUE" \
  --output json \
  | jq -r '.ResourceTagMappingList[] | [.ResourceARN, ([.Tags[] | "\(.Key)=\(.Value)"] | join(","))] | @tsv'
```

**REPORT:** Full inventory of resources carrying the PII tag, with all their tags. Always REPORT — this IS the deliverable for the PII inventory section of the final report.
Evidence required: get-resources output.

**When scope is ALL_STORES**, replace this with:
```bash
aws s3api list-buckets --output json | jq -r '.Buckets[].Name'
aws rds describe-db-instances --output json | jq -r '.DBInstances[].DBInstanceIdentifier'
aws dynamodb list-tables --output json | jq -r '.TableNames[]'
# (extend to EBS, EFS, Redshift as needed)
```

Closes: A.7.2.1
