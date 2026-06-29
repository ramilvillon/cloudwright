# Domain: IAM & Access Control

## Controls

| Control ID | Name                     | Severity |
|------------|--------------------------|----------|
| A.8.2      | Privileged Access Rights | Critical |
| A.8.5      | Secure Authentication    | Critical |

---

## IaC Checks

### IAM-I1: No wildcard (*) actions in IAM policies (A.8.2)
Search all `.tf` files for `aws_iam_policy`, `aws_iam_role_policy`, `aws_iam_user_policy` where the policy JSON document contains `"Action": "*"` or `"Action":["*"]`.

**PASS:** No wildcard action found in any customer-managed policy.
**FAIL:** Any policy document contains `Action: *` without a scoping `Condition`.

Remediation (Terraform):
```hcl
resource "aws_iam_policy" "example" {
  name   = "example-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]  # specific actions only
      Resource = "arn:aws:s3:::my-bucket/*"
    }]
  })
}
```
Closes: A.8.2

### IAM-I2: No aws_iam_user resources for human access (A.8.2)
Search `.tf` files for `resource "aws_iam_user"` blocks.

**PASS:** No `aws_iam_user` resources, or only service accounts clearly commented as non-human.
**FAIL:** `aws_iam_user` resources present for human access.
**PARTIAL:** `aws_iam_user` present but appears to be a CI/CD service account (contains `ci`, `deploy`, `service` in name).

Remediation (Terraform) — replace human IAM users with Identity Center:
```hcl
resource "aws_ssoadmin_permission_set" "engineer" {
  name             = "EngineerAccess"
  instance_arn     = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  session_duration = "PT8H"
}

resource "aws_ssoadmin_account_assignment" "engineer" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.engineer.arn
  principal_id       = "<user-id-from-identity-center>"
  principal_type     = "USER"
  target_id          = data.aws_caller_identity.current.account_id
  target_type        = "AWS_ACCOUNT"
}
```
Closes: A.8.2

### IAM-I3: IAM account password policy meets requirements (A.8.5)
Search `.tf` files for `resource "aws_iam_account_password_policy"`.

**PASS:** Resource exists with all of: `minimum_password_length >= 12`, `require_uppercase_characters = true`, `require_lowercase_characters = true`, `require_numbers = true`, `require_symbols = true`, `password_reuse_prevention >= 5`, `max_password_age <= 90`.
**FAIL:** Resource absent or any required parameter below threshold.
**PARTIAL:** Resource exists but one or more parameters are below threshold.

Remediation (Terraform):
```hcl
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 5
  max_password_age               = 90
}
```
Closes: A.8.5

### IAM-I4: No hardcoded credentials in IaC files (A.8.2)
Grep all `.tf`, `.yaml`, `.yml` files for patterns: literal strings assigned to `access_key`, `secret_key`, `password`, `api_key`, `token` that are not variable or data source references.

**PASS:** No hardcoded credential literals found.
**FAIL:** Literal credential strings (not `var.x` or `data.x`) found in any IaC file.

Remediation (Terraform) — use Secrets Manager:
```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/db/master-password"
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
  # ...
}
```
Closes: A.8.2

---

## Live Infra Checks

### IAM-L1: Root MFA enabled (A.8.5)
```bash
aws iam get-account-summary --output json \
  | jq '.SummaryMap | {AccountMFAEnabled, AccountAccessKeysPresent}'
```
**PASS:** `AccountMFAEnabled = 1` (root access key presence checked separately in IAM-L2)
**FAIL:** `AccountMFAEnabled = 0`
Evidence required: IAM console screenshot showing root MFA status.

### IAM-L2: No root access keys (A.8.2)
```bash
aws iam get-account-summary --output json \
  | jq '.SummaryMap.AccountAccessKeysPresent'
```
**PASS:** `AccountAccessKeysPresent = 0`
**FAIL:** `AccountAccessKeysPresent = 1`
Evidence required: IAM credential report showing root access key status = inactive/none.

Remediation:
```bash
aws iam list-access-keys --user-name root
aws iam delete-access-key --access-key-id <AccessKeyId> --user-name root
```
Closes: A.8.2

### IAM-L3: No IAM users with console passwords (prefer Identity Center) (A.8.2)
```bash
aws iam list-users --output json | jq -r '.Users[] | [.UserName, (.PasswordLastUsed // "never"), .CreateDate] | @tsv'
```
Then for each user, check if console password exists:
```bash
aws iam list-users --output json | jq -r '.Users[].UserName' | while read -r user; do
  if aws iam get-login-profile --user-name "$user" 2>/dev/null; then
    echo "HAS_CONSOLE_PASSWORD: $user"
  fi
  sleep 0.2
done
```
**PASS:** No IAM users have console passwords.
**PARTIAL:** IAM users exist but none have console passwords (service accounts only).
**FAIL:** One or more users have active console passwords.
Evidence required: IAM user list, Identity Center configuration screenshot.

Remediation:
```bash
# Deactivate console password for a user (migrate to Identity Center first)
aws iam delete-login-profile --user-name <username>
```
Closes: A.8.2

### IAM-L4: No customer-managed policies with wildcard actions (A.8.2)
```bash
aws iam list-policies --scope Local --output json \
  | jq -r '.Policies[] | [.Arn, .DefaultVersionId] | @tsv' \
  | while IFS=$'\t' read -r arn version; do
    aws iam get-policy-version --policy-arn "$arn" --version-id "$version" \
      --output json \
      | jq -r --arg arn "$arn" \
        'if (.PolicyVersion.Document | tostring | test("\"Action\"\\s*:\\s*\\[?\"\\*\"\\]?")) then "WILDCARD_FOUND: \($arn)" else empty end'
    sleep 0.2
done
```
**PASS:** No output (no wildcards found).
**FAIL:** Any `WILDCARD_FOUND:` lines in output.
Evidence required: IAM Access Analyzer findings report, before/after policy diff.

### IAM-L5: Access keys not older than 90 days (A.8.2)
```bash
aws iam generate-credential-report 2>/dev/null; sleep 5
aws iam get-credential-report --output json \
  | jq -r '.Content' | base64 -d | python3 -c "
import sys, csv, datetime
reader = csv.DictReader(sys.stdin)
today = datetime.datetime.now(datetime.timezone.utc)
expired = []
for row in reader:
    for key_num in ['1', '2']:
        if row.get(f'access_key_{key_num}_active') == 'true':
            last = row.get(f'access_key_{key_num}_last_rotated', '')
            if last and last not in ('N/A', 'no_information'):
                try:
                    age = (today - datetime.datetime.fromisoformat(last.replace('Z','+00:00'))).days
                except (ValueError, AttributeError):
                    print(f'Skipping {row[\"user\"]} key{key_num} — unparseable date: {last}')
                    continue
                if age > 90:
                    expired.append(f'EXPIRED ({age}d): {row[\"user\"]} key{key_num}')
                    print(f'*** EXPIRED ({age}d): {row[\"user\"]} access_key_{key_num}')
                else:
                    print(f'ok ({age}d): {row[\"user\"]} access_key_{key_num}')
if not expired:
    print('ALL_KEYS_CURRENT')
"
```
**PASS:** All active keys rotated within 90 days (`ALL_KEYS_CURRENT` or no `EXPIRED` lines).
**FAIL:** Any `*** EXPIRED` lines in output.
Evidence required: IAM credential report (dated), key rotation records.

Remediation:
```bash
# Create new key first, update applications, then deactivate old key
aws iam create-access-key --user-name <username>
aws iam update-access-key --access-key-id <old-key-id> --status Inactive --user-name <username>
# After confirming new key works:
aws iam delete-access-key --access-key-id <old-key-id> --user-name <username>
```
Closes: A.8.2

### IAM-L6: IAM password policy meets requirements (A.8.5)
```bash
aws iam get-account-password-policy --output json | jq '{
  MinimumPasswordLength,
  RequireUppercaseCharacters,
  RequireLowercaseCharacters,
  RequireNumbers,
  RequireSymbols,
  PasswordReusePrevention,
  MaxPasswordAge
}'
```
**PASS:** `MinimumPasswordLength >= 12`, all Require* = true, `PasswordReusePrevention >= 5`, `MaxPasswordAge <= 90`.
**FAIL:** Policy absent or any parameter below threshold.
Evidence required: IAM password policy config screenshot.

Remediation:
```bash
aws iam update-account-password-policy \
  --minimum-password-length 14 \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --require-numbers \
  --require-symbols \
  --allow-users-to-change-password \
  --password-reuse-prevention 5 \
  --max-password-age 90
```
Closes: A.8.5
