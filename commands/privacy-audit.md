---
description: Run a read-only ISO 27701:2019 privacy audit (PII residency, retention, discovery, sharing) of Terraform/CloudFormation files or live AWS infrastructure. Produces a privacy scorecard plus PII inventory. Never modifies AWS.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:privacy-auditor` skill. Let the skill run its normal interview (audit mode, domains, PII role/scope, allowed regions) unless the user has already specified those.
