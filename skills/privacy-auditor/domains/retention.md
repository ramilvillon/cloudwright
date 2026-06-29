# Domain: Retention & Deletion

## Controls

| Clause   | Name                                  | Severity |
|----------|---------------------------------------|----------|
| A.7.4.7  | Retention                             | High     |
| A.7.4.8  | Disposal                              | Critical |
| B.8.4.1  | Temporary files (processor-side)      | High     |

Controller clauses (A.7.x) apply when role = Controller or Both.
Processor clauses (B.8.x) apply when role = Processor or Both.

---

## IaC Checks

### RET-I1: PII S3 buckets have a lifecycle configuration (A.7.4.7 / A.7.4.8)

Search `.tf` files for every `aws_s3_bucket` resource in the PII-scoped set. For each one, verify a matching `aws_s3_bucket_lifecycle_configuration` resource exists referencing the same `bucket` id.

**PASS:** Every PII bucket has a lifecycle configuration with at least one `rule { expiration { days = N } }` block.
**FAIL:** Any PII bucket has no lifecycle configuration, or has one with no `expiration` block.
**PARTIAL:** Lifecycle configuration exists but only covers a subset of paths (e.g., single prefix filter while bucket holds PII at multiple prefixes).

Remediation (Terraform):
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "user_uploads" {
  bucket = aws_s3_bucket.user_uploads.id

  rule {
    id     = "pii-retention-365d"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```
Closes: A.7.4.7

### RET-I2: CloudWatch log groups have retention configured (A.7.4.7)

Search `.tf` files for `resource "aws_cloudwatch_log_group"` blocks.

**PASS:** Every log group has a `retention_in_days` attribute set to a positive integer.
**FAIL:** Any log group missing `retention_in_days` (defaults to Never Expire).
**REPORT:** The specific value each log group uses (the exact number is policy-dependent).

Remediation (Terraform):
```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/app"
  retention_in_days = 90
}
```
Closes: A.7.4.7

### RET-I3: RDS instances have a non-zero backup retention period (A.7.4.8)

Search `.tf` files for `resource "aws_db_instance"` and `resource "aws_rds_cluster"` in the PII-scoped set.

**PASS:** Every instance/cluster has `backup_retention_period` set to a positive integer.
**FAIL:** Any instance has `backup_retention_period = 0` or is missing the attribute (default 0 for clusters; default 7 for instances, but explicit is preferred).
**REPORT:** The specific value each instance uses.

Remediation (Terraform):
```hcl
resource "aws_db_instance" "app" {
  identifier              = "app-db"
  engine                  = "postgres"
  instance_class          = "db.t3.medium"
  backup_retention_period = 7
  delete_automated_backups = false
}
```
Closes: A.7.4.8

### RET-I4: DynamoDB tables have PITR enabled (A.7.4.8)

Search `.tf` files for `resource "aws_dynamodb_table"` in the PII-scoped set. Check for `point_in_time_recovery { enabled = true }` block.

**PASS:** Every PII table has PITR enabled.
**FAIL:** Any PII table missing the PITR block or with `enabled = false`.

Remediation (Terraform):
```hcl
resource "aws_dynamodb_table" "user_data" {
  name     = "user-data"
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
```
Closes: A.7.4.8

---

## Live Infra Checks

### RET-L1: PII S3 buckets have lifecycle rules (A.7.4.7 / A.7.4.8)

For each bucket in the PII-scoped inventory:
```bash
if lc_json=$(aws s3api get-bucket-lifecycle-configuration --bucket "$bucket" --output json 2>/dev/null); then
  count=$(echo "$lc_json" | jq '[.Rules[] | select(.Expiration.Days != null or .Expiration.Date != null)] | length')
  if [ "$count" -gt 0 ]; then
    echo "LIFECYCLE_OK: $bucket (${count} expiration rules)"
    echo "$lc_json" | jq -r --arg b "$bucket" '.Rules[] | select(.Expiration.Days != null) | "  \($b): rule=\(.ID // "unnamed") days=\(.Expiration.Days)"'
  else
    echo "LIFECYCLE_NO_EXPIRATION: $bucket"
  fi
else
  echo "NO_LIFECYCLE: $bucket"
fi
sleep 0.2
```

**PASS:** Every PII bucket returns `LIFECYCLE_OK`.
**FAIL:** Any bucket returns `NO_LIFECYCLE` or `LIFECYCLE_NO_EXPIRATION`.
**REPORT:** The `days` value per rule (specific number is policy-dependent).
Evidence required: `GetBucketLifecycleConfiguration` output per PII bucket.

Remediation:
```bash
cat > /tmp/lifecycle.json <<'EOF'
{
  "Rules": [
    {
      "ID": "pii-retention-365d",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": 365 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 }
    }
  ]
}
EOF
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$bucket" \
  --lifecycle-configuration file:///tmp/lifecycle.json
```
Closes: A.7.4.7

### RET-L2: CloudWatch log groups have retention set (A.7.4.7)

```bash
aws logs describe-log-groups --output json \
  | jq -r '.logGroups[] | [.logGroupName, (.retentionInDays // "never")] | @tsv'
```

The AWS CLI auto-paginates `describe-log-groups` by default, so this single call returns every log group in the region regardless of count. Do not pass `--no-paginate` — that flag caps the output at a single page (≤50 items).

**PASS:** No log groups return `never`.
**FAIL:** Any log group has `retentionInDays` unset.
**REPORT:** The specific value per log group.
Evidence required: list of log groups with retention values.

Remediation:
```bash
aws logs put-retention-policy \
  --log-group-name "$group" \
  --retention-in-days 90
```
Closes: A.7.4.7

### RET-L3: PII RDS instances have non-zero backup retention (A.7.4.8)

For each region where PII RDS instances live:
```bash
aws rds describe-db-instances --region "$region" --output json \
  | jq -r '.DBInstances[] | [.DBInstanceIdentifier, .BackupRetentionPeriod] | @tsv'
sleep 0.2
```

Filter results to the PII-scoped inventory.

**PASS:** Every PII instance has `BackupRetentionPeriod > 0`.
**FAIL:** Any PII instance has `BackupRetentionPeriod = 0`.
**REPORT:** The specific value per instance.
Evidence required: describe-db-instances output per PII instance.

Remediation:
```bash
aws rds modify-db-instance \
  --db-instance-identifier "$id" \
  --backup-retention-period 7 \
  --apply-immediately
```
Closes: A.7.4.8

### RET-L4: PII DynamoDB tables have PITR enabled (A.7.4.8)

For each PII-scoped DynamoDB table:
```bash
aws dynamodb describe-continuous-backups --table-name "$tbl" --output json \
  | jq -r --arg t "$tbl" '[$t, .ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus] | @tsv'
sleep 0.2
```

**PASS:** Every PII table returns `ENABLED`.
**FAIL:** Any PII table returns `DISABLED`.
Evidence required: describe-continuous-backups output per PII table.

Remediation:
```bash
aws dynamodb update-continuous-backups \
  --table-name "$tbl" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
```
Closes: A.7.4.8
