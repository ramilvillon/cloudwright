# Domain: Threat Detection & Security Monitoring

## Controls

| Control ID | Name                       | Severity |
|------------|----------------------------|----------|
| A.8.7      | Protection Against Malware | Critical |
| A.8.16     | Monitoring Activities      | High     |

---

## IaC Checks

### THREAT-I1: GuardDuty detector enabled (A.8.7)
Search `.tf` files for `resource "aws_guardduty_detector"`.

**PASS:** Resource exists with `enable = true`.
**FAIL:** Resource absent or `enable = false`.

Remediation (Terraform):
```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes { audit_logs { enable = true } }
    malware_protection {
      scan_ec2_instance_with_findings { ebs_volumes { enable = true } }
    }
  }
}
```
Closes: A.8.7

### THREAT-I2: Security Hub enabled with standards (A.8.16)
Search `.tf` files for `resource "aws_securityhub_account"` and `resource "aws_securityhub_standards_subscription"`.

**PASS:** `aws_securityhub_account` present AND at least two `aws_securityhub_standards_subscription` resources (CIS + AWS Foundational).
**FAIL:** Neither resource present.
**PARTIAL:** Account resource present but fewer than two standards subscriptions.

Remediation (Terraform):
```hcl
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
}
```
Closes: A.8.16

### THREAT-I3: CloudWatch alarms for critical security events (A.8.16)
Search `.tf` files for `resource "aws_cloudwatch_metric_alarm"` with names or metric filters matching: root login, IAM policy changes, CloudTrail disabled, security group changes, S3 bucket policy changes.

**PASS:** At least 5 security alarms covering the above events.
**FAIL:** Fewer than 3 security alarms found.
**PARTIAL:** 3–4 security alarms found.

Remediation (Terraform):
```hcl
resource "aws_cloudwatch_log_metric_filter" "root_login" {
  name           = "RootAccountLogin"
  pattern        = "{ $.userIdentity.type = \"Root\" && $.eventType != \"AwsServiceEvent\" }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  metric_transformation {
    name      = "RootAccountLoginCount"
    namespace = "SecurityMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_login" {
  alarm_name          = "RootAccountLogin"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountLoginCount"
  namespace           = "SecurityMetrics"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```
Closes: A.8.16

---

## Live Infra Checks

### THREAT-L1: GuardDuty enabled in current region (A.8.7)
```bash
detector_count=$(aws guardduty list-detectors --output json | jq '.DetectorIds | length')
echo "GuardDuty detectors: $detector_count"

aws guardduty list-detectors --output json | jq -r '.DetectorIds[]' | while read -r did; do
  aws guardduty get-detector --detector-id "$did" --output json \
    | jq -r --arg did "$did" '"Detector \($did): Status=\(.Status) PublishFreq=\(.FindingPublishingFrequency)"'
  sleep 0.2
done
```
**PASS:** At least one detector with `Status = ENABLED`.
**FAIL:** No detectors, or all detectors disabled.
Evidence required: GuardDuty status dashboard showing all detectors active.

### THREAT-L2: GuardDuty findings export to S3 configured (A.8.7)
```bash
did=$(aws guardduty list-detectors --output json | jq -r '.DetectorIds[0]')
if [ -n "$did" ] && [ "$did" != "null" ]; then
  aws guardduty list-publishing-destinations --detector-id "$did" --output json \
    | jq '.Destinations[] | {DestinationType, Status}'
else
  echo "NO_DETECTOR_FOUND"
fi
```
**PASS:** At least one publishing destination with `Status = PUBLISHING`.
**FAIL:** No publishing destinations configured.
Evidence required: GuardDuty export config, S3 bucket for findings.

### THREAT-L3: Security Hub enabled with CIS and AWS Foundational standards (A.8.16)
```bash
if hub_json=$(aws securityhub describe-hub --output json 2>/dev/null); then
  echo "HUB_ENABLED"
  aws securityhub list-standards-subscriptions --output json \
    | jq -r '.Standards[] | [.StandardsArn, .StandardsStatus] | @tsv'
else
  echo "HUB_NOT_ENABLED"
fi
```
**PASS:** Hub exists (no NoSuchHubException) AND at least 2 standards with `StandardsStatus = READY`.
**FAIL:** Hub not enabled, or no standards subscribed.
**PARTIAL:** Hub enabled but fewer than 2 standards active.
Evidence required: Security Hub enabled, standards compliance scores, integrated findings list.

### THREAT-L4: CloudWatch alarms for critical security events exist (A.8.16)
```bash
aws cloudwatch describe-alarms --output json | jq -r '
  [.MetricAlarms[] | .AlarmName] |
  map(select(test("root|iam|cloudtrail|security[-_.]group|s3[-_.]bucket"; "i"))) |
  "Security-related alarms found: \(length)",
  .[]'
```
**PASS:** 5 or more security alarms found.
**PARTIAL:** 2–4 security alarms found.
**FAIL:** Fewer than 2 security alarms.
Evidence required: CloudWatch alarm list with thresholds, SNS topic, sample alert notification.
