# Domain: Encryption

## Controls

| Control ID | Name                | Severity |
|------------|---------------------|----------|
| A.8.24     | Use of Cryptography | Critical |

---

## IaC Checks

### ENC-I1: S3 buckets have server-side encryption (A.8.24)
Search `.tf` files for `resource "aws_s3_bucket"`. For each, check for a corresponding `aws_s3_bucket_server_side_encryption_configuration`.

**PASS:** Every `aws_s3_bucket` has an associated `aws_s3_bucket_server_side_encryption_configuration` with `sse_algorithm = "aws:kms"` or `"AES256"`.
**FAIL:** Any S3 bucket lacks an encryption configuration resource.

Remediation (Terraform):
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}
```
Closes: A.8.24

### ENC-I2: RDS instances have storage_encrypted = true (A.8.24)
Search `.tf` files for `resource "aws_db_instance"` and `resource "aws_rds_cluster"`.

**PASS:** All `aws_db_instance` and `aws_rds_cluster` resources have `storage_encrypted = true`.
**FAIL:** Any DB resource missing `storage_encrypted = true` or has `storage_encrypted = false`.

Remediation (Terraform):
```hcl
resource "aws_db_instance" "main" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
}
```
Closes: A.8.24

### ENC-I3: EBS volumes have encrypted = true (A.8.24)
Search `.tf` files for `resource "aws_ebs_volume"` and `resource "aws_instance"` block device mappings.

**PASS:** All `aws_ebs_volume` and block device mappings have `encrypted = true`.
**FAIL:** Any volume or block device missing encryption.

Remediation (Terraform):
```hcl
resource "aws_ebs_volume" "data" {
  availability_zone = "ap-southeast-1a"
  size              = 100
  encrypted         = true
  kms_key_id        = aws_kms_key.ebs.arn
}

resource "aws_instance" "app" {
  root_block_device {
    encrypted  = true
    kms_key_id = aws_kms_key.ebs.arn
  }
}
```
Closes: A.8.24

### ENC-I4: EBS encryption by default enabled (A.8.24)
Search `.tf` files for `resource "aws_ebs_encryption_by_default"`.

**PASS:** Resource exists with `enabled = true`.
**FAIL:** Resource absent.

Remediation (Terraform):
```hcl
resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}
```
Closes: A.8.24

---

## Live Infra Checks

### ENC-L1: S3 buckets have encryption enabled (A.8.24)
```bash
aws s3api list-buckets --output json | jq -r '.Buckets[].Name' | while read -r bucket; do
  enc_json=$(aws s3api get-bucket-encryption --bucket "$bucket" --output json 2>/dev/null)
  if [ -n "$enc_json" ]; then
    algo=$(echo "$enc_json" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')
    echo "ENC_OK: $bucket ($algo)"
  else
    echo "NO_ENCRYPTION: $bucket"
  fi
  sleep 0.2
done
```
**PASS:** No `NO_ENCRYPTION:` lines.
**FAIL:** Any bucket without server-side encryption.
Evidence required: S3 bucket encryption configuration for each bucket.

### ENC-L2: EBS encryption by default enabled (A.8.24)
```bash
aws ec2 get-ebs-encryption-by-default --output json \
  | jq '"EBS encryption by default: \(.EbsEncryptionByDefault)"'
```
**PASS:** `EbsEncryptionByDefault = true`
**FAIL:** `EbsEncryptionByDefault = false`
Evidence required: EC2 account settings showing EBS encryption by default.

Remediation:
```bash
aws ec2 enable-ebs-encryption-by-default
```
Closes: A.8.24

### ENC-L3: RDS instances are encrypted at rest (A.8.24)
```bash
aws rds describe-db-instances --output json | jq -r '
  .DBInstances[] |
  if .StorageEncrypted then
    "ENC_OK: \(.DBInstanceIdentifier)"
  else
    "NOT_ENCRYPTED: \(.DBInstanceIdentifier)"
  end'
```
**PASS:** No `NOT_ENCRYPTED:` lines.
**FAIL:** Any RDS instance without encryption.
Evidence required: RDS instance list showing `StorageEncrypted = true`.

### ENC-L4: No unencrypted EBS volumes (A.8.24)
```bash
aws ec2 describe-volumes --output json | jq -r '
  .Volumes[] |
  select(.Encrypted == false) |
  "UNENCRYPTED_EBS: \(.VolumeId) (\(.Size)GB, \(.State), attached to \(.Attachments[0].InstanceId // "unattached"))"'
```
**PASS:** No `UNENCRYPTED_EBS:` lines.
**FAIL:** Any unencrypted EBS volumes found.
Evidence required: EBS volume list showing all volumes encrypted.
