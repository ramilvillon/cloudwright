# Domain: Data Protection

## Controls

| Control ID | Name                     | Severity |
|------------|--------------------------|----------|
| A.8.11     | Data Masking             | High     |
| A.8.12     | Data Leakage Prevention  | High     |

---

## IaC Checks

### DATA-I1: S3 versioning enabled on data buckets (A.8.11)
Search `.tf` files for `resource "aws_s3_bucket_versioning"`.

**PASS:** Every data `aws_s3_bucket` has a corresponding `aws_s3_bucket_versioning` with `versioning_configuration.status = "Enabled"`.
**FAIL:** Data buckets without versioning configuration.

Remediation (Terraform):
```hcl
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}
```
Closes: A.8.11

### DATA-I2: RDS backup retention >= 7 days (A.8.11)
Search `.tf` files for `resource "aws_db_instance"` and check `backup_retention_period`.

**PASS:** All `aws_db_instance` and `aws_rds_cluster` resources have `backup_retention_period >= 7`.
**FAIL:** Any DB with `backup_retention_period < 7` or `= 0` (disabled).

Remediation (Terraform):
```hcl
resource "aws_db_instance" "main" {
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
}
```
Closes: A.8.11

### DATA-I3: S3 public access block enabled on all buckets (A.8.12)
Search `.tf` files for `resource "aws_s3_bucket_public_access_block"`.

**PASS:** Every `aws_s3_bucket` has a corresponding `aws_s3_bucket_public_access_block` with all four flags set to `true`.
**FAIL:** Any bucket missing the public access block resource or any flag set to `false`.

Remediation (Terraform):
```hcl
resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```
Closes: A.8.12

### DATA-I4: Amazon Macie enabled for sensitive data discovery (A.8.12)
Search `.tf` files for `resource "aws_macie2_account"`.

**PASS:** Resource exists with `status = "ENABLED"`.
**FAIL:** Resource absent.

Remediation (Terraform):
```hcl
resource "aws_macie2_account" "main" {
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  status                       = "ENABLED"
}
```
Closes: A.8.12

---

## Live Infra Checks

### DATA-L1: S3 versioning enabled on buckets (A.8.11)
```bash
aws s3api list-buckets --output json | jq -r '.Buckets[].Name' | while read -r bucket; do
  status=$(aws s3api get-bucket-versioning --bucket "$bucket" --output json 2>/dev/null \
    | jq -r '.Status // "NotEnabled"')
  if [ "$status" = "Enabled" ]; then
    echo "VERSIONING_OK: $bucket"
  else
    echo "NO_VERSIONING: $bucket ($status)"
  fi
  sleep 0.2
done
```
**PASS:** All data buckets have versioning enabled (no `NO_VERSIONING:` for non-logging buckets).
**PARTIAL:** Some buckets have versioning enabled.
**FAIL:** No buckets have versioning enabled.
Evidence required: S3 bucket list with versioning status.

### DATA-L2: RDS backup retention >= 7 days (A.8.11)
```bash
aws rds describe-db-instances --output json | jq -r '
  .DBInstances[] |
  if .BackupRetentionPeriod >= 7 then
    "OK: \(.DBInstanceIdentifier) (\(.BackupRetentionPeriod) days)"
  else
    "LOW_BACKUP_RETENTION: \(.DBInstanceIdentifier) (\(.BackupRetentionPeriod) days)"
  end'
```
**PASS:** All RDS instances have `BackupRetentionPeriod >= 7`.
**FAIL:** Any instance with retention < 7 (including 0 = disabled).
Evidence required: RDS backup configuration showing retention periods.

### DATA-L3: S3 public access block enabled on all buckets (A.8.12)
```bash
aws s3api list-buckets --output json | jq -r '.Buckets[].Name' | while read -r bucket; do
  all_blocked=$(aws s3api get-public-access-block --bucket "$bucket" --output json 2>/dev/null | jq '
    .PublicAccessBlockConfiguration |
    (.BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets)')
  if [ "$all_blocked" = "true" ]; then
    echo "BLOCKED_OK: $bucket"
  else
    echo "NOT_FULLY_BLOCKED: $bucket"
  fi
  sleep 0.2
done
```
**PASS:** All buckets show `BLOCKED_OK`.
**PARTIAL:** Some buckets have partial blocks.
**FAIL:** Any bucket with `NOT_FULLY_BLOCKED`.
Evidence required: S3 public access block configuration for each bucket.

### DATA-L4: Amazon Macie enabled (A.8.12)
```bash
if session=$(aws macie2 get-macie-session --output json 2>/dev/null); then
  echo "$session" | jq -r '"Macie status: \(.status) | Created: \(.createdAt)"'
else
  echo "MACIE_NOT_ENABLED"
fi
```
**PASS:** `status = "ENABLED"`
**PARTIAL:** `status = "PAUSED"`
**FAIL:** Macie not enabled.

Remediation:
```bash
aws macie2 enable-macie
```
Closes: A.8.12
