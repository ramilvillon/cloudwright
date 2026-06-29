# Domain: Transfer & Sharing

## Controls

| Clause    | Name                                                | Severity |
|-----------|-----------------------------------------------------|----------|
| A.7.5.3   | Records of PII disclosures to third parties         | High     |
| A.7.5.4   | Notify PII principals of disclosure requests        | Medium   |
| B.8.5.3   | Records of PII disclosures to third parties         | High     |
| B.8.5.4   | Notification of PII disclosure requests             | Medium   |
| B.8.5.8   | Disclosure of subcontractors used to process PII    | High     |

Controller clauses (A.7.x) apply when role = Controller or Both.
Processor clauses (B.8.x) apply when role = Processor or Both.

---

## IaC Checks

### TS-I1: S3 bucket policies do not grant wildcard principals on PII buckets (A.7.5.3 / B.8.5.3)

Search `.tf` files for `resource "aws_s3_bucket_policy"` attached to buckets in the PII-scoped set. Parse the `policy` JSON document.

**PASS:** No statement with `Effect = "Allow"` has `Principal = "*"` or `Principal = { "AWS": "*" }`.
**FAIL:** Any `Allow` statement on a PII bucket has a wildcard principal.
**REPORT:** Any `Allow` statement with a specific cross-account principal (ARN from a different account ID than `data.aws_caller_identity.current.account_id`) — these are legitimate but must be recorded.

Remediation (Terraform) — scope the policy to a specific principal:
```hcl
data "aws_iam_policy_document" "user_uploads" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::123456789012:role/PartnerReadRole"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.user_uploads.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "user_uploads" {
  bucket = aws_s3_bucket.user_uploads.id
  policy = data.aws_iam_policy_document.user_uploads.json
}
```
Closes: A.7.5.3

### TS-I2: S3 replication destinations are within trusted accounts (A.7.5.3 / B.8.5.3)

Search `.tf` files for `resource "aws_s3_bucket_replication_configuration"`. For each rule, resolve the destination `bucket` ARN to an account ID (the ARN pattern `arn:aws:s3:::NAME` does not include an account; follow the destination bucket resource if declared in the same module, or mark as "external").

**REPORT:** Destination bucket + account ID (or "external" if unresolvable) per rule. Always REPORT — cross-account replication is legitimate but must be recorded for A.7.5.3.
**FAIL:** Only if an explicit policy forbids cross-account replication (not assumed by default).

Remediation — none automatic; this is a disclosure record. Document the destination in your ROPA.

### TS-I3: AWS RAM resource shares involving PII data stores (A.7.5.3 / B.8.5.8)

Search `.tf` files for `resource "aws_ram_resource_share"` and `resource "aws_ram_resource_association"`. Filter associations whose `resource_arn` points to an ARN of a PII-scoped data store (S3, RDS, DynamoDB, etc.).

**REPORT:** Each share: share name, resource ARN, and associated principals (from `aws_ram_principal_association`).

Remediation — none automatic; document each share in your ROPA.

### TS-I4: RDS snapshots shared with other accounts (A.7.5.3 / B.8.5.3)

Search `.tf` files for `resource "aws_db_snapshot"` or `resource "aws_db_cluster_snapshot"` with a `shared_accounts` attribute, and for `resource "aws_db_snapshot_copy"` with a `source_db_snapshot_identifier` referencing a shared snapshot.

Also check `aws_rds_cluster` and `aws_db_instance` for `copy_tags_to_snapshot = true` (indicates automatic snapshot propagation).

**REPORT:** Each snapshot resource with its shared account IDs.
**FAIL:** Any snapshot shared with `all` (public) — this is always a privacy violation for PII data.

Remediation (Terraform) — remove `all` from shared accounts:
```hcl
resource "aws_db_snapshot" "app_export" {
  db_snapshot_identifier = "app-export-2026-04"
  db_instance_identifier = aws_db_instance.app.id
  shared_accounts        = ["123456789012"]  # specific account only, never "all"
}
```
Closes: A.7.5.3

---

## Live Infra Checks

### TS-L1: S3 bucket policies on PII buckets — cross-account principals (A.7.5.3 / B.8.5.3)

For each bucket in the PII-scoped inventory:
```bash
if policy_json=$(aws s3api get-bucket-policy --bucket "$bucket" --output json 2>/dev/null); then
  echo "$policy_json" | jq -r '.Policy' | jq -r --arg b "$bucket" \
    '.Statement[] | select(.Effect == "Allow") | [$b, (.Principal | tostring)] | @tsv'
fi
sleep 0.2
```

For each returned principal string, extract the account ID and compare against the current account.

**FAIL:** Any `Allow` statement with `Principal = "*"` or `Principal = {"AWS": "*"}`.
**REPORT:** Cross-account principals (different account ID) — each is a disclosure record.
**PASS:** Only same-account principals in all Allow statements.
Evidence required: `get-bucket-policy` output per PII bucket.

Remediation — replace the policy:
```bash
cat > /tmp/policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::123456789012:role/PartnerReadRole" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$bucket/*"
    }
  ]
}
EOF
aws s3api put-bucket-policy --bucket "$bucket" --policy file:///tmp/policy.json
```
Closes: A.7.5.3

### TS-L2: S3 replication destinations — account and region (A.7.5.3 / B.8.5.3)

For each bucket in the PII-scoped inventory:
```bash
if repl_json=$(aws s3api get-bucket-replication --bucket "$bucket" --output json 2>/dev/null); then
  echo "$repl_json" | jq -r --arg b "$bucket" \
    '.ReplicationConfiguration.Rules[] | [$b, .Destination.Bucket, (.Destination.Account // "same-account")] | @tsv'
fi
sleep 0.2
```

**REPORT:** Each rule: source bucket, destination bucket ARN, destination account ID. Always REPORT — replication is a disclosure record for A.7.5.3.
**FAIL:** Only if replication is to a public (no-policy) destination — check by running `get-bucket-policy-status` on the destination bucket.
Evidence required: replication config per PII bucket.

### TS-L3: AWS RAM shares involving PII data stores (A.7.5.3 / B.8.5.8)

```bash
aws ram list-resource-shares --resource-owner SELF --output json \
  | jq -r '.resourceShares[] | [.resourceShareArn, .name, .status] | @tsv'

aws ram list-resource-shares --resource-owner SELF --output json \
  | jq -r '.resourceShares[].resourceShareArn' \
  | while read -r share_arn; do
    aws ram list-resources --resource-owner SELF --resource-share-arns "$share_arn" --output json \
      | jq -r --arg s "$share_arn" '.resources[] | [$s, .arn, .type] | @tsv'
    sleep 0.2
  done

aws ram list-resource-shares --resource-owner SELF --output json \
  | jq -r '.resourceShares[].resourceShareArn' \
  | while read -r share_arn; do
    aws ram list-principals --resource-owner SELF --resource-share-arn "$share_arn" --output json \
      | jq -r --arg s "$share_arn" '.principals[] | [$s, .id] | @tsv'
    sleep 0.2
  done
```

Filter returned ARNs to those matching PII-scoped data stores.

**REPORT:** Each share involving PII data: share name, resources, principals.
Evidence required: RAM share output.

### TS-L4: RDS and DynamoDB snapshots shared with other accounts (A.7.5.3 / B.8.5.3)

For each region with PII RDS instances:
```bash
aws rds describe-db-snapshots --region "$region" --snapshot-type manual --output json \
  | jq -r '.DBSnapshots[] | [.DBSnapshotIdentifier, .DBInstanceIdentifier] | @tsv' \
  | while IFS=$'\t' read -r snap_id db_id; do
    aws rds describe-db-snapshot-attributes --region "$region" --db-snapshot-identifier "$snap_id" --output json \
      | jq -r --arg s "$snap_id" --arg d "$db_id" \
        '.DBSnapshotAttributesResult.DBSnapshotAttributes[] | select(.AttributeName == "restore") | [$s, $d, (.AttributeValues | join(","))] | @tsv'
    sleep 0.2
  done
```

Filter to snapshots of PII-scoped RDS instances.

For DynamoDB backups:
```bash
aws dynamodb list-backups --output json \
  | jq -r '.BackupSummaries[] | [.BackupName, .TableName, .BackupType, .BackupStatus] | @tsv'
sleep 0.2
```

DynamoDB backups are account-local (not shareable cross-account via attributes), so the DynamoDB check is REPORT-only — list backups for PII tables without a verdict.

**FAIL:** Any RDS snapshot's `AttributeValues` contains `all` (public).
**REPORT:** RDS snapshots shared with specific account IDs (disclosure record).
**REPORT:** All DynamoDB backups of PII tables.
Evidence required: describe-db-snapshot-attributes output per snapshot.

Remediation — remove public sharing:
```bash
aws rds modify-db-snapshot-attribute \
  --db-snapshot-identifier "$snap_id" \
  --attribute-name restore \
  --values-to-remove all
```
Closes: A.7.5.3
