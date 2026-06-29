# Domain: Data Residency & Cross-Border Transfer

## Controls

| Clause    | Name                                        | Severity |
|-----------|---------------------------------------------|----------|
| A.7.5.1   | Identify basis for PII transfer             | Critical |
| A.7.5.2   | Countries and international organizations   | High     |
| B.8.5.1   | Basis for PII transfer between jurisdictions| Critical |
| B.8.5.2   | Countries and international organizations   | High     |

Controller clauses (A.7.x) apply when role = Controller or Both.
Processor clauses (B.8.x) apply when role = Processor or Both.

---

## IaC Checks

### RES-I1: S3 buckets declare an explicit region (A.7.5.1 / B.8.5.1)

Search all `.tf` files for `resource "aws_s3_bucket"` blocks. Inspect the effective region by looking at:
- The `provider "aws"` block the resource uses (default provider or aliased via `provider = aws.name`)
- An explicit `region` attribute on the resource (CloudFormation inline style)

**REPORT:** Record the declared region for each bucket in the PII-scoped set.
**FAIL:** If `ALLOWED_REGIONS` is provided and a bucket's declared region is outside the allowlist.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`, record regions without issuing a verdict.

Remediation (Terraform) — pin a bucket to an allowed region via aliased provider:
```hcl
provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
}

resource "aws_s3_bucket" "user_uploads" {
  provider = aws.eu
  bucket   = "user-uploads"
}
```
Closes: A.7.5.1

### RES-I2: S3 replication destinations are in allowed regions (A.7.5.1 / B.8.5.1)

Search `.tf` files for `resource "aws_s3_bucket_replication_configuration"`. For each `rule { destination { bucket = "arn:aws:s3:::NAME" } }`, determine the destination bucket's region (follow the `aws_s3_bucket` resource reference if present; otherwise REPORT unknown).

**PASS:** All destination regions are in `ALLOWED_REGIONS`.
**FAIL:** Any destination region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** `SKIP_REGION_CHECK=true` — list destinations without verdict.

Remediation (Terraform) — same as RES-I1 example: use an aliased EU provider for the destination bucket.
Closes: A.7.5.1

### RES-I3: RDS instances declare an explicit region (A.7.5.1 / B.8.5.1)

Search `.tf` files for `resource "aws_db_instance"` and `resource "aws_rds_cluster"`. Identify each instance's region via its provider reference.

**REPORT:** Record the declared region for each instance in the PII-scoped set.
**FAIL:** If a region is outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.

Remediation (Terraform):
```hcl
resource "aws_db_instance" "app" {
  provider      = aws.eu
  identifier    = "app-db"
  engine        = "postgres"
  instance_class = "db.t3.medium"
  # ...
}
```
Closes: A.7.5.1

### RES-I4: Terraform providers declare only allowed regions (A.7.5.2 / B.8.5.2)

Search `.tf` files for `provider "aws"` blocks. List every `region` attribute used across the module.

**REPORT:** Enumerate all declared provider regions.
**FAIL:** Any provider declares a region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.

This check surfaces "shadow" regions — places where the module could create resources even if none currently exist there.

Closes: A.7.5.2

### RES-I5: DynamoDB global-table replicas are in allowed regions (A.7.5.1 / B.8.5.1)

Search `.tf` files for `resource "aws_dynamodb_table"` blocks with `replica { region_name = "..." }` entries.

**PASS:** All replica regions are in `ALLOWED_REGIONS`.
**FAIL:** Any replica region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.

Remediation (Terraform) — remove disallowed replica regions:
```hcl
resource "aws_dynamodb_table" "user_data" {
  provider = aws.eu
  name     = "user-data"
  hash_key = "id"
  # ... attributes ...

  replica {
    region_name = "eu-central-1"
  }
}
```
Closes: A.7.5.1

---

## Live Infra Checks

### RES-L1: PII-scoped S3 buckets are in allowed regions (A.7.5.1 / B.8.5.1)

For each bucket in the PII-scoped inventory:
```bash
aws s3api get-bucket-location --bucket "$bucket" --output json \
  | jq -r --arg b "$bucket" '"\($b)\t\(.LocationConstraint // "us-east-1")"'
sleep 0.2
```

**PASS:** All returned regions are in `ALLOWED_REGIONS`.
**FAIL:** Any region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true` — list each bucket with its region.
Evidence required: list of PII buckets with their regions.

Remediation (AWS CLI) — create a new bucket in the allowed region, migrate data with `aws s3 sync`, then delete the original. Never use `aws s3api put-bucket-location` (it is not a real API; buckets are immutable in region).
Closes: A.7.5.1

### RES-L2: PII-scoped RDS instances are in allowed regions (A.7.5.1 / B.8.5.1)

```bash
for region in $(aws ec2 describe-regions --output text --query 'Regions[].RegionName'); do
  aws rds describe-db-instances --region "$region" --output json \
    | jq -r --arg r "$region" '.DBInstances[] | [.DBInstanceIdentifier, $r] | @tsv'
  sleep 0.2
done
```

Filter the results to only instances present in the PII-scoped inventory. Iterating all regions is required because `describe-db-instances` only returns instances in a single region at a time.

**PASS:** All PII instances are in regions within `ALLOWED_REGIONS`.
**FAIL:** Any PII instance in a region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.
Evidence required: list of PII RDS instances with their regions.

### RES-L3: DynamoDB global-table replicas are in allowed regions (A.7.5.1 / B.8.5.1)

```bash
aws dynamodb list-tables --output json | jq -r '.TableNames[]' | while read -r tbl; do
  aws dynamodb describe-table --table-name "$tbl" --output json \
    | jq -r --arg t "$tbl" '.Table.Replicas[]? | [$t, .RegionName, .ReplicaStatus] | @tsv'
  sleep 0.2
done
```

Filter to tables in the PII-scoped inventory.

**PASS:** All replica regions in `ALLOWED_REGIONS`.
**FAIL:** Any replica region outside `ALLOWED_REGIONS`.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.
Evidence required: replica list with status.

Remediation:
```bash
aws dynamodb update-table \
  --table-name "$tbl" \
  --replica-updates "Delete={RegionName=us-east-1}"
```
Closes: A.7.5.1

### RES-L4: S3 replication destinations are in allowed regions (A.7.5.1 / B.8.5.1)

For each PII-scoped bucket:
```bash
if repl_json=$(aws s3api get-bucket-replication --bucket "$bucket" --output json 2>/dev/null); then
  echo "$repl_json" | jq -r --arg b "$bucket" \
    '.ReplicationConfiguration.Rules[] | [$b, .Destination.Bucket, (.Destination.Bucket | sub("^arn:aws:s3:::"; ""))] | @tsv'
fi
sleep 0.2
```

For each destination bucket ARN returned, run `aws s3api get-bucket-location` to determine the region, then compare against `ALLOWED_REGIONS`.

**PASS:** All destination regions in `ALLOWED_REGIONS`.
**FAIL:** Any destination region outside.
**REPORT-ONLY:** If `SKIP_REGION_CHECK=true`.
Evidence required: replication rules with destination regions resolved.

Remediation — replace the replication rule with one pointing to an in-allowlist destination bucket, or remove the rule entirely:
```bash
aws s3api delete-bucket-replication --bucket "$bucket"
```
Closes: A.7.5.1
