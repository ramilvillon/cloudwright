---
description: Run a read-only ISO 27001:2022 security compliance audit of Terraform/CloudFormation files or live AWS infrastructure. Produces a scorecard plus remediation artifacts. Never modifies AWS.
disable-model-invocation: true
---

Use the Skill tool to invoke the `cloudwright:security-auditor` skill. Let the skill run its normal interview (audit mode: IaC vs live; domain selection) unless the user has already specified those.
