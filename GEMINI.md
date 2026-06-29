# Cloudwright (Gemini context)

Cloudwright provides AWS Well-Architected skills (design + read-only governance auditors) following
the Agent Skills standard. The skills are in `.agents/skills/`: `cloud-architect`, `security-auditor`,
`privacy-auditor`, `cost-auditor`, `ri-planner`.

Activate a skill when its description matches the user's request. All skills are read-only against AWS
(local file writes only; never `terraform apply`). See AGENTS.md for the full skill list and posture.
