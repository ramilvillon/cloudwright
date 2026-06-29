# Domain: Logging & Audit Trail

## Controls

| Control ID | Name                  | Severity |
|------------|-----------------------|----------|
| A.8.15     | Logging               | Critical |
| A.8.16     | Monitoring Activities | High     |

---

## IaC Checks

### LOG-I1: CloudTrail multi-region trail with integrity validation (A.8.15)
Search `.tf` files for `resource "aws_cloudtrail"`.

**PASS:** Resource exists with `is_multi_region_trail = true` AND `enable_log_file_validation = true` AND `include_global_service_events = true`.
**FAIL:** Resource absent, or missing any of those flags.
**PARTIAL:** Resource exists but one or two flags are missing.

Remediation (Terraform):
```hcl
resource "aws_cloudtrail" "main" {
  name                          = "main-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }
}
```
Closes: A.8.15

### LOG-I2: CloudTrail S3 bucket has Object Lock / deny-delete policy (A.8.15)
Search `.tf` files for the S3 bucket used by CloudTrail. Check for:
- `aws_s3_bucket_object_lock_configuration` with `rule.default_retention`
- `aws_s3_bucket_policy` that denies `s3:DeleteObject` and `s3:DeleteBucket`

**PASS:** Both Object Lock configuration and deny-delete policy present.
**FAIL:** Neither present.
**PARTIAL:** One of the two present.

Remediation (Terraform):
```hcl
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_deny_delete" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyDelete"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["s3:DeleteObject", "s3:DeleteBucket", "s3:PutLifecycleConfiguration"]
      Resource  = [
        "${aws_s3_bucket.cloudtrail.arn}",
        "${aws_s3_bucket.cloudtrail.arn}/*"
      ]
    }]
  })
}
```
Closes: A.8.15

### LOG-I3: VPC Flow Logs enabled (A.8.15)
Search `.tf` files for `resource "aws_flow_log"` targeting each `aws_vpc`.

**PASS:** One `aws_flow_log` resource per `aws_vpc` with `traffic_type = "ALL"`.
**FAIL:** No flow log resources found, or VPCs without corresponding flow logs.

Remediation (Terraform):
```hcl
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-logs"
  retention_in_days = 14
}
```
Closes: A.8.15

### LOG-I4: CloudWatch log groups have retention policies (A.8.16)
Search `.tf` files for `resource "aws_cloudwatch_log_group"` without `retention_in_days`.

**PASS:** All `aws_cloudwatch_log_group` resources have `retention_in_days` set.
**FAIL:** Any log group resource missing `retention_in_days`.

Remediation (Terraform):
```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/production"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_group" "security" {
  name              = "/aws/cloudtrail"
  retention_in_days = 2555
}
```
Closes: A.8.16

---

## Live Infra Checks

### LOG-L1: CloudTrail multi-region trail enabled with integrity validation (A.8.15)
```bash
aws cloudtrail describe-trails --include-shadow-trails false --output json \
  | jq '[.trailList[] | {
      Name,
      IsMultiRegionTrail,
      LogFileValidationEnabled,
      IncludeGlobalServiceEvents,
      S3BucketName
    }]'
```
Then check logging status for each trail:
```bash
aws cloudtrail describe-trails --output json \
  | jq -r '.trailList[].Name' | while read -r name; do
    aws cloudtrail get-trail-status --name "$name" --output json \
      | jq -r --arg name "$name" '"Trail: \($name) IsLogging: \(.IsLogging)"'
    sleep 0.2
done
```
**PASS:** At least one trail with `IsMultiRegionTrail=true`, `LogFileValidationEnabled=true`, `IncludeGlobalServiceEvents=true`, and `IsLogging=true`.
**FAIL:** No multi-region trail, or validation disabled, or logging stopped.
Evidence required: CloudTrail console showing all-region trail active.

### LOG-L2: CloudTrail S3 bucket has versioning and deny-delete policy (A.8.15)
```bash
BUCKET=$(aws cloudtrail describe-trails --output json | jq -r '.trailList[0].S3BucketName // empty')
if [ -z "$BUCKET" ]; then
  echo "NO_TRAIL_CONFIGURED"
else
  echo "CloudTrail bucket: $BUCKET"

  aws s3api get-bucket-versioning --bucket "$BUCKET" --output json

  aws s3api get-bucket-policy --bucket "$BUCKET" --output json \
    | jq '.Policy | fromjson | .Statement[] | select(.Effect == "Deny")'
fi
```
**PASS:** Bucket versioning enabled AND policy contains a Deny statement for delete actions.
**FAIL:** No versioning or no deny policy.
**PARTIAL:** One of the two present.
Evidence required: S3 bucket policy, MFA delete status, Object Lock config.

### LOG-L3: VPC Flow Logs enabled for all VPCs (A.8.15)
```bash
aws ec2 describe-vpcs --output json | jq -r '.Vpcs[].VpcId' | while read -r vpc_id; do
  flow_log_count=$(aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$vpc_id" \
    --output json | jq '.FlowLogs | length')
  if [ "$flow_log_count" -eq 0 ]; then
    echo "NO_FLOW_LOG: $vpc_id"
  else
    echo "OK: $vpc_id ($flow_log_count flow log(s))"
  fi
  sleep 0.2
done
```
**PASS:** No `NO_FLOW_LOG:` lines.
**FAIL:** Any VPC missing flow logs.
Evidence required: VPC Flow Log configuration, sample log entries.

### LOG-L4: CloudWatch log groups all have retention policies (A.8.16)
```bash
aws logs describe-log-groups --no-paginate --output json | jq -r '
  .logGroups as $g |
  "Total log groups: \($g | length)",
  "No retention: \([$g[] | select(.retentionInDays == null)] | length)",
  ([$g[] | select(.retentionInDays == null)] | .[0:20][] | "NO_RETENTION: \(.logGroupName)")'
```
**PASS:** Zero log groups with `retentionInDays = null`.
**FAIL:** Any log groups without retention policies.
Evidence required: CloudWatch log group retention settings.

Remediation:
```bash
aws logs put-retention-policy \
  --log-group-name "/app/production" \
  --retention-in-days 365
```
Closes: A.8.16
