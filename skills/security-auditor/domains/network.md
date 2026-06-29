# Domain: Network Security

## Controls

| Control ID | Name                         | Severity |
|------------|------------------------------|----------|
| A.8.20     | Networks Security            | Critical |
| A.8.21     | Security of Network Services | High     |
| A.8.22     | Segregation of Networks      | High     |

---

## IaC Checks

### NET-I1: No security groups open SSH/RDP to 0.0.0.0/0 (A.8.20)
Search `.tf` files for `aws_security_group` or `aws_security_group_rule` ingress rules with `cidr_blocks = ["0.0.0.0/0"]` and `from_port` matching 22, 3389, or `protocol = "-1"`.

**PASS:** No security groups allow SSH (22), RDP (3389), or all traffic (-1) from 0.0.0.0/0.
**FAIL:** Any security group allows SSH, RDP, or all traffic from 0.0.0.0/0.

Remediation (Terraform):
```hcl
resource "aws_security_group_rule" "ssh_restricted" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]  # internal only, never 0.0.0.0/0
  security_group_id = aws_security_group.bastion.id
}
```
Closes: A.8.20

### NET-I2: Private subnets have map_public_ip_on_launch = false (A.8.22)
Search `.tf` files for `resource "aws_subnet"` with `map_public_ip_on_launch = true` on subnets tagged or named as private.

**PASS:** All subnets named or tagged as "private" have `map_public_ip_on_launch = false`.
**FAIL:** Any private subnet has `map_public_ip_on_launch = true`.

Remediation (Terraform):
```hcl
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  tags = { Name = "private-subnet-1a", Tier = "private" }
}
```
Closes: A.8.22

### NET-I3: WAF attached to public-facing ALBs (A.8.21)
Search `.tf` files for `aws_alb` or `aws_lb` (internet-facing) and check for corresponding `aws_wafv2_web_acl_association`.

**PASS:** Every internet-facing ALB has an `aws_wafv2_web_acl_association`.
**FAIL:** Internet-facing ALBs found with no WAF association.

Remediation (Terraform):
```hcl
resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_lb.api.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```
Closes: A.8.21

### NET-I4: VPC has separate public/private subnet tiers (A.8.22)
Search `.tf` files for `aws_subnet` resources — verify both public and private subnets are defined in the same VPC.

**PASS:** Both public and private tagged/named subnets present in the same VPC.
**FAIL:** All subnets are public, or no VPC defined at all.

Remediation (Terraform):
```hcl
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false  # assign public IPs via EIP/NAT, not auto-assign
}
```
Closes: A.8.22

---

## Live Infra Checks

### NET-L1: No security groups open SSH/RDP to 0.0.0.0/0 (A.8.20)
```bash
aws ec2 describe-security-groups --output json | jq -r '
  .SecurityGroups[] |
  .GroupId as $gid |
  .GroupName as $gname |
  (.IpPermissions[] |
    select(
      (.FromPort == 22 or .FromPort == 3389 or .IpProtocol == "-1") and
      ([.IpRanges[].CidrIp] | any(. == "0.0.0.0/0" or . == "::/0"))
    ) |
    "OPEN_TO_WORLD: \($gid) (\($gname)) port \(.FromPort // "all")"
  )' 2>/dev/null || echo "No unrestricted ingress rules found"
```
**PASS:** No `OPEN_TO_WORLD:` lines.
**FAIL:** Any unrestricted SSH, RDP, or all-traffic rules found.
Evidence required: Security group rules showing restricted access.

### NET-L2: WAF Web ACLs attached to internet-facing ALBs (A.8.21)
```bash
aws elbv2 describe-load-balancers --output json \
  | jq -r '.LoadBalancers[] | select(.Scheme == "internet-facing") | [.LoadBalancerArn, .LoadBalancerName] | @tsv' \
  | while IFS=$'\t' read -r arn name; do
  waf_json=$(aws wafv2 get-web-acl-for-resource \
    --resource-arn "$arn" \
    --scope REGIONAL \
    --output json 2>/dev/null)
  if [ -n "$waf_json" ]; then
    waf_name=$(echo "$waf_json" | jq -r '.WebACL.Name')
    echo "WAF_OK: $name → $waf_name"
  else
    echo "NO_WAF: $name ($arn)"
  fi
  sleep 0.2
done
```
**PASS:** All internet-facing ALBs have WAF associations (`WAF_OK` for all).
**FAIL:** Any internet-facing ALB without WAF (`NO_WAF` lines present).
Evidence required: WAF Web ACL associations list.

### NET-L3: No running instances in default VPC (A.8.22)
```bash
default_vpc=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --output json | jq -r '.Vpcs[0].VpcId // "none"')
echo "Default VPC: $default_vpc"

if [ "$default_vpc" != "none" ] && [ "$default_vpc" != "null" ]; then
  aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$default_vpc" "Name=instance-state-name,Values=running" \
    --output json | jq -r '
      .Reservations[].Instances[] |
      "INSTANCE_IN_DEFAULT_VPC: \(.InstanceId) (\(.InstanceType))"'
fi
```
**PASS:** No running instances in default VPC.
**PARTIAL:** Default VPC exists but is empty.
**FAIL:** Running instances found in default VPC.
Evidence required: VPC configuration showing custom VPC in use for all workloads.
