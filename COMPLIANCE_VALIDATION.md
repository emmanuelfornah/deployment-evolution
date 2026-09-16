# Compliance Validation — deployment-evolution

## Scope and framework choice

This validates the real, live infrastructure in `infra/` against a
compliance framework — not a hypothetical enterprise scenario.

**Framework: SOC 2 (Trust Services Criteria — Security, Availability).**
Deliberately not HIPAA, PCI-DSS, or GDPR: this app processes salon
appointment data — no PHI, no payment card data, no EU-resident personal
data at any meaningful scale. Forcing one of those frameworks onto this
system would misrepresent what it actually handles. SOC 2's Trust
Services Criteria are data-type-agnostic — built around whether a cloud
service is operated securely and reliably, which is a claim this project
can actually back up with evidence, unlike a regulated-data framework it
has no real exposure to.

## Baseline: policy-as-code already in place

`infra/config.tf` runs AWS Config as a continuous compliance baseline —
the direct equivalent of an Azure Policy regulatory-baseline initiative,
just AWS-native. Four managed rules, evaluating continuously, not a
point-in-time check:

| Rule | What it checks |
|---|---|
| `restricted-ssh` | No security group allows unrestricted inbound SSH |
| `iam-policy-no-statements-with-admin-access` | No IAM policy grants blanket admin access |
| `rds-storage-encrypted` | RDS storage is encrypted at rest |
| `dynamodb-table-encryption-enabled` | DynamoDB tables are encrypted at rest |

Deliberately just Config, not Security Hub/GuardDuty/Inspector/Macie —
those carry real recurring per-check costs disproportionate to this
app's traffic. Config rule evaluations get most of the same continuous-
compliance value for a few dollars a month — the same cost-proportionate
reasoning applied everywhere else in this project.

## Custom control

**`required-tags`** — added this pass, parameterized against this
project's actual tag keys (`Project=appointments`, `ManagedBy=terraform`,
from the provider's `default_tags` block in `versions.tf`, verified
against the real Terraform config before writing this rule, not assumed).

Precision note: this is an AWS **managed** rule with custom input
parameters, not a fully custom Lambda-backed rule. Calling it "custom
policy" the way the assignment does would overstate it slightly — it's
custom in the sense that its parameters are specific to this project's
real tags, not in the sense of custom-written evaluation logic. Stated
plainly rather than let the label do more work than it's earned.

Detective only, same as the other four rules: it reports non-compliance,
it cannot block a deployment. Adding it carried zero risk to the live
app — confirmed by the plan showing exactly one resource added, nothing
else touched.

**Status:** evaluation pending at time of writing (`INSUFFICIENT_DATA`)
— AWS Config's first compliance pass takes time after a rule is created.

**Exported rule definition** (`aws configservice describe-config-rules
--config-rule-names required-tags`, account ID redacted):

```json
{
  "ConfigRuleName": "required-tags",
  "ConfigRuleArn": "arn:aws:config:us-east-2:xxxxxxxx2833:config-rule/config-rule-xgrrgs",
  "ConfigRuleId": "config-rule-xgrrgs",
  "Source": { "Owner": "AWS", "SourceIdentifier": "REQUIRED_TAGS" },
  "InputParameters": "{\"tag1Key\":\"Project\",\"tag2Key\":\"ManagedBy\"}",
  "ConfigRuleState": "ACTIVE",
  "EvaluationModes": [{ "Mode": "DETECTIVE" }]
}
```

## Remediation — a real one, not staged for this document

**Finding:** AWS's own account-health recommendations flagged
`scheduler-db` (this app's RDS instance) as non-compliant with its
Multi-AZ high-availability best practice — a real, unprompted signal,
not a finding manufactured for this exercise.

**Before:** `multi_az = false` (deliberate initial choice — see
`README.md`'s Cost posture section for the original reasoning: the
compute tier already provided multi-AZ HA, so the database wasn't judged
to be the bottleneck).

**Remediation:** re-examined the tradeoff with AWS's real signal in
hand rather than dismissing it. Terraform plan confirmed a clean
in-place change (`multi_az: false -> true`, 0 resources destroyed).
Applied.

**After:** `multi_az = true`, standby now provisioning in a second AZ.
Cost impact: +~$15/mo, documented honestly in the Cost posture table
rather than absorbed silently.

This is the actual remediation evidence for this report — a real gap
AWS itself surfaced, a real Terraform-tracked before/after, not a
screenshot manufactured to satisfy a rubric.

## NIST CSF mapping

| Control | NIST CSF function | Category |
|---|---|---|
| AWS Config (4 baseline rules + `required-tags`) | Detect | DE.CM — Security Continuous Monitoring |
| `restricted-ssh`, IMDSv2 enforcement, SSM-only access | Protect | PR.AC — Identity Management and Access Control |
| RDS/DynamoDB encryption at rest | Protect | PR.DS — Data Security |
| CodeDeploy blue/green + alarm-gated auto-rollback | Recover | RC.RP — Recovery Planning |
| Multi-AZ RDS (this remediation) | Recover | RC.RP — Recovery Planning |
| CloudTrail-driven incident diagnosis (see `DEPLOYMENT_CODEBUILD.md`) | Respond | RS.AN — Analysis |

Not mapped to CSA Cloud Controls Matrix — that mapping requires a level
of familiarity with CCM's specific control taxonomy this document isn't
confident enough to represent accurately. A mapping table with entries
I can't personally defend is worse than a shorter, accurate one.

## Gap analysis

| Gap | Why it's open | Priority |
|---|---|---|
| `required-tags` evaluation not yet complete | Needs time after creation, not a real blocker | Low — will self-resolve |
| No Security Hub aggregation | Deliberate cost tradeoff (see baseline section above) | Low — revisit only if a real audit requires it |
| No cross-region DR | Explicitly deferred — see `DR_RUNBOOK.md`, triggered by an actual interview, not built speculatively | Accepted, documented |
| Seasonal auto-scaling non-functional | CodeDeploy's ASG-replacement behavior broke the original design; needs a Lambda-based redesign | Medium — tracked, not silently broken |

## Continuous compliance

AWS Config's rules run continuously, not as a point-in-time check —
compliance drift shows up automatically, without a manual re-audit. The
practical roadmap: revisit this document if the app's data scope ever
changes (e.g., if payment processing were added, PCI-DSS would become a
real, not hypothetical, consideration), and treat `terraform plan`
itself as the ongoing gap-detection mechanism — a plan that wants to
revert a compliant setting is exactly the kind of drift this whole
project has already caught and acted on once (see `DEPLOYMENT_CODEBUILD.md`'s
Bug 7).
