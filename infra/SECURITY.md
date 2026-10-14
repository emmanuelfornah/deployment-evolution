# Security considerations — appointments infrastructure

## Network
- App and data tiers have no route to the internet inbound; only the
  ALB sits in public subnets. Three-tier security group chain
  (internet → ALB → app → RDS) — nothing skips a hop.
- No inbound SSH anywhere. Instance access is via SSM Session Manager
  (IAM + CloudTrail-logged), not key pairs or an open port 22.
- VPC Flow Logs enabled, shipped to CloudWatch Logs.
- S3 and DynamoDB gateway endpoints keep that traffic inside AWS. Other
  AWS API calls (ECR, Logs, Secrets Manager, SSM) leave through the NAT
  gateway, still TLS and IAM-scoped. Interface endpoints were removed
  for cost; re-adding them is the fix if NAT egress must be avoided.

## Identity & access
- Every IAM policy is scoped to a specific resource ARN — no `*`
  resource except the one action (`ecr:GetAuthorizationToken`) that AWS
  doesn't support resource-level scoping for.
- App instances authenticate to RDS via IAM database authentication —
  no DB password is generated, stored, or handled by app code at all.
- The one remaining app secret (Django `SECRET_KEY`) lives in Secrets
  Manager and is fetched at deploy time by the CodeDeploy hook, not
  baked into the AMI, launch template, or env vars in a manifest.
- RDS's own master credential is created and rotated by RDS
  (`manage_master_user_password`) — nobody, including this Terraform
  config, ever sees it in plaintext.

## Compute
- IMDSv2 enforced (`http_tokens = "required"`) — closes the SSRF path
  to instance credential theft that IMDSv1 allows.
- EBS volumes encrypted at rest.
- ECR image tags are immutable — a deployed image reference can't be
  silently repointed after the fact, and blue/green deploys always
  reference an unambiguous, specific image.
- Images are scanned on push (`scan_on_push = true`).

## Data
- RDS: encrypted at rest (customer-managed KMS key, rotation enabled),
  not publicly accessible, automated backups (7-day retention),
  deletion protection on, slow/error/general logs shipped to
  CloudWatch.
- DynamoDB: encryption at rest, point-in-time recovery enabled.

## Deployment safety
- Blue/green via CodeDeploy: new revision is health-checked on a fully
  separate target group before it ever takes production traffic.
- Automatic rollback on deployment failure or on a CloudWatch alarm
  (unhealthy host count > 0 during rollout).
- Old (blue) instances stay up for a 30-minute bake window after
  cutover — rollback is a traffic re-point, not a rebuild.

## Continuous compliance (AWS Config)
Four managed rules watch for configuration drift after deploy, so a
control documented above doesn't silently stop being true:
- `restricted-ssh` — nothing should ever open inbound 22; this catches
  it if someone adds the rule later, not just at review time.
- `iam-policy-no-statements-with-admin-access` — guards against a
  future `AdministratorAccess`-style policy getting attached to
  `appointments-app-instance-role` or the CodeDeploy role.
- `rds-storage-encrypted` — RDS encryption is a create-time property;
  this is a tripwire, not a redundant check.
- `dynamodb-table-encryption-enabled` — same idea for the
  announcements table.

## STRIDE threat model
| Threat | Example | Mitigating control |
|---|---|---|
| **S**poofing | Stolen credentials used to call AWS APIs as the app | IAM roles only (no long-lived keys on instances), IMDSv2, SSM for human access instead of SSH keys |
| **T**ampering | A deployed image or config silently altered after the fact | Immutable ECR tags, CodeDeploy blue/green (new revision never overwrites the running one in place), Config drift rules above |
| **R**epudiation | No record of who did what during an incident | VPC Flow Logs, CloudTrail (SSM sessions, all IAM/API calls), RDS query logs to CloudWatch |
| **I**nformation disclosure | DB credentials or app secrets leaked via env vars/logs/manifests | IAM DB auth (no DB password to leak), Secrets Manager for the one app secret, KMS encryption at rest for RDS/DynamoDB/EBS |
| **D**enial of service | One bad deploy or AZ failure takes the app down | Multi-AZ ASG, ALB health checks, CodeDeploy auto-rollback on alarm; cross-region DR (pilot light) is the next tier up, see the migration notes |
| **E**levation of privilege | App role or CodeDeploy role used to reach beyond its intended scope | Every IAM policy scoped to a specific resource ARN (no `*`), `iam-policy-no-statements-with-admin-access` Config rule as a backstop |

## Known gaps / deliberately out of scope for v1
- No WAF in front of the ALB yet — add `aws_wafv2_web_acl` +
  association if/when this needs protecting against common web
  exploits or bot traffic, not required to demonstrate the
  architecture itself.
- Single NAT gateway (not one per AZ) — cost tradeoff explained in
  `networking.tf`; doesn't affect inbound availability, only outbound
  egress resilience.
- Cross-region DR (pilot light: RDS read replica, DynamoDB Global
  Table, Route 53 failover) is designed but not yet in this Terraform —
  see the private planning notes for that design; it's additive on top
  of this stack, not a rework of it. Primary region is `us-east-2`
  (nearest full AWS region to a Texas-based business — AWS has none
  physically in Texas); DR target is `us-west-2` specifically because
  it's on a different power grid/weather system than the Gulf
  Coast/central-US severe-winter-storm risk (2021 Texas/ERCOT-style
  event) this design is meant to survive, not picked as "AWS's other
  big region." See `DR_SCENARIO.md` for the real event this is
  grounded in, cited, and the precise (not hand-wavy) technical
  parallel to why cross-region independence matters.
- Security Hub / GuardDuty / Inspector / Macie deliberately not
  enabled — genuine recurring per-check costs and another always-on
  surface to remember to tear down, disproportionate for this app's
  traffic. AWS Config's rule evaluations give most of the same
  "continuous compliance" story for a fraction of the cost; revisit if
  this ever carries real user data.
- No S3 bucket / SSE-KMS pattern — the app has no S3 usage (DynamoDB
  only), so there's nothing to attach bucket encryption to. If a future
  feature adds file uploads or static asset storage, encrypt with a
  customer-managed KMS key and block all public access by default,
  same as this stack already does for RDS/DynamoDB.
