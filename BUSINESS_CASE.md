# Cloud-Native Appointment Scheduler Platform

## Business Case and Architecture Overview

---

## Executive Summary

This project delivers a production-grade appointment scheduling application
for a hair salon client. The solution transforms an incomplete Django
application into a fully automated, cloud-native platform capable of
reliable deployments, automated quality enforcement, and zero-downtime
updates.

**The platform runs today** on EC2 behind an Application Load Balancer,
backed by Amazon RDS and DynamoDB, deployed through a fully automated AWS
CodePipeline. Every code change is automatically tested, containerized, and
deployed via blue/green cutover — with full rollback capability — without
any manual intervention. Live at
[appointments.emmanuelfornah.com](https://appointments.emmanuelfornah.com).

It didn't start there. The platform was originally delivered on Amazon EKS,
built and verified end-to-end, then migrated to EC2 after a real cost/traffic
review showed the Kubernetes control plane bought no availability guarantee
this workload needed. Both phases are real and evidenced — see
[Why We Migrated](#why-we-migrated-eks--ec2) below.

---

## Business Problem

### Client Pain Points

- No reliable appointment booking system — appointments managed manually
- Customer dissatisfaction from double-bookings and scheduling errors
- No visibility into available appointment slots
- No system to broadcast salon announcements to customers
- Manual deployment processes prone to human error

### Technical Debt Inherited

- Incomplete codebase left by a departed senior developer
- Unit test coverage at 98% — untested code paths in production logic
- Application running only on local SQLite — not suitable for multi-user access
- No containerization, no CI/CD, no cloud deployment

---

## Solution Delivered

### Application Features

- Real-time appointment slot availability with automatic conflict detection
- Hairdresser selection with service-level filtering
- Dynamic salon announcements powered by Amazon DynamoDB
- Available slot count displayed to customers before booking

### Infrastructure Delivered (current — EC2 phase, live)

| Component | Service | Purpose |
|-----------|---------|---------|
| Compute | EC2 (Graviton/t4g), Auto Scaling Group | Containerized application, blue/green deployment |
| Deployment | AWS CodeDeploy | Zero-downtime blue/green cutover with automatic rollback on alarm |
| Database | Amazon RDS MySQL | Appointment and scheduling data, IAM database authentication |
| NoSQL | Amazon DynamoDB | Real-time salon announcements |
| Container Registry | Amazon ECR | Versioned Docker image storage (immutable, commit-SHA tags) |
| Load Balancer | AWS ALB | Traffic routing, health checks |
| DNS / TLS | Route 53 + ACM | Custom domain, valid HTTPS |
| CI/CD | AWS CodePipeline + CodeBuild | Automated test, build, deploy |
| Source Control | GitHub (CodeStarSourceConnection) | Code versioning and pipeline trigger |

### Quality Metrics Achieved

| Metric | Before | After |
|--------|--------|-------|
| Test Coverage | 98% | **100%** |
| Pylint Code Quality | Unknown | **10.00 / 10** |
| Deployment Process | Manual | **Fully Automated** |
| Rollback Capability | None | **Automatic, alarm-gated (blue/green)** |
| Database | SQLite (local only) | **Amazon RDS MySQL, IAM auth (multi-user)** |
| Infrastructure | None | **Live, HA, custom domain over HTTPS** |

---

## Platform Architecture (current)

### System Architecture

```
Users
  │
  ▼
Route 53 (appointments.emmanuelfornah.com)
  │
  ▼
Application Load Balancer (ACM/TLS)
  │
  ▼
EC2 Auto Scaling Group (blue/green, CodeDeploy-managed)
  │
  ├─ Amazon RDS MySQL (appointments data, IAM auth)
  └─ Amazon DynamoDB (announcements)
```

### CI/CD Pipeline Architecture

```
GitHub Push
  │
  ▼
AWS CodePipeline (CodeStarSourceConnection)
  │
  ▼
CodeBuild: UnitTest
  │
  ▼
CodeBuild: BuildImage (ARM64, native Graviton build)
  │
  ▼
Docker → Amazon ECR
  │
  ▼
CodeDeploy: blue/green cutover to EC2
  │
  ▼
Live, health-checked, old fleet held for rollback window
```

---

## Why We Migrated (EKS → EC2)

- EKS's control plane is a fixed ~$0.10/hr (~$73/mo) charge regardless of
  traffic — for low, bursty appointment-booking traffic, that line bought no
  HA guarantee an Auto Scaling Group + ALB doesn't already provide.
- The migration kept the same VPC, IAM posture, and HA characteristics
  (multi-AZ, self-healing, zero-downtime deploys) while cutting the shared
  core of the bill (control plane, compute, NAT, ALB, RDS) from
  ~$180-220/mo to ~$115/mo at list price (see MONITORING.md).
- Kubernetes competency is still demonstrated and evidenced — the original
  EKS build was completed, verified end-to-end (rolling deploys, rollback,
  a real production incident diagnosed via `kubectl logs` and fixed), then
  deliberately torn down once proven, rather than left running at a cost
  the workload didn't justify.
- Getting from "Terraform applies cleanly" to "actually live" on EC2 took 7
  distinct, real bugs — IAM permission gaps only CloudTrail could reveal, a
  Docker/IMDS hop-limit issue, and a third-party library defaulting to the
  wrong database port. Each was found via direct evidence, not guessed.

---

## Security Design Decisions

**IAM Database Authentication for RDS**

Database connections use AWS IAM token authentication — no long-lived
password is stored in environment variables, code, or configuration files.
Tokens are generated per-session and expire automatically. The app
authenticates as a dedicated, least-privilege database user — never as the
RDS master account.

**No SSH, No Hardcoded Credentials**

Instance access is exclusively via AWS Systems Manager Session Manager —
no SSH keypairs, no open port 22, every session logged to CloudTrail. All
sensitive values (database host, region, secret ARN) are passed via the EC2
instance role, scoped to exactly the resources the app needs.

**IMDSv2 Enforced**

Instance metadata requires IMDSv2 tokens (`http_tokens = required`), closing
the SSRF-to-credential-theft path IMDSv1 allows.

**Immutable Image Tags**

Every deployed image is tagged with its commit SHA and cannot be
overwritten — a running deployment always traces back to an exact, specific
commit.

---

## Non-Functional Requirements

### Availability
- Multi-AZ Auto Scaling Group behind an ALB
- Health checks ensure traffic only routes to healthy instances
- Zero-downtime blue/green deployments with an automatic rollback window

### Scalability
- Horizontal scaling via Auto Scaling Group capacity
- Stateless application design enables seamless scaling
- RDS and DynamoDB handle increased load independently

### Security
- IAM database authentication — no long-lived DB password
- No SSH anywhere; SSM Session Manager only, logged to CloudTrail
- Least-privilege IAM roles scoped to specific resource ARNs
- IMDSv2 enforced, EBS encrypted, images scanned on push

### Deployment Reliability
- CI/CD pipeline enforces code quality gates before any deploy
- Blue/green deployment with alarm-gated automatic rollback
- Full audit trail via Git commit history and immutable image tags

### Performance
- Application responds in < 2 seconds for booking requests
- ALB distributes load across multiple instances
- Database queries optimized with proper indexing

---

## Risk Management

### Rollback Strategy

**Blue/green automatic rollback (current, EC2)**

CodeDeploy holds the previous fleet up during a configured window; a
CloudWatch alarm on unhealthy hosts triggers an automatic rollback if the
new revision fails health checks — no manual step required for the common
failure case.

**Git revert + pipeline (any phase)**

```bash
git revert <bad-commit> --no-edit
git push
# Pipeline automatically rebuilds and redeploys the reverted state
```

Used when bad application code reached production and an auditable,
reviewable fix is preferred over an infrastructure-level rollback.

*(The original EKS phase additionally demonstrated `kubectl rollout undo`
as a Kubernetes-native rollback path — see `screenshots/` for that
evidence.)*

### Quality Gates — Automated Enforcement

The pipeline enforces non-negotiable quality standards before any code
reaches ECR or production:

- Pylint score below 10.00 → pipeline fails, nothing deploys
- Test coverage below 100% → pipeline fails, nothing deploys

This means code quality standards are enforced by infrastructure, not by
convention.

---

## Operational Capabilities

### Monitoring and Troubleshooting

```bash
# Session into a running instance (no SSH)
aws ssm start-session --target <instance-id>

# Application logs
docker logs <container-id>

# Deployment status
aws deploy get-deployment --deployment-id <id>

# ALB target health
aws elbv2 describe-target-health --target-group-arn <arn>
```

### Scaling

Capacity is managed by the Auto Scaling Group CodeDeploy creates on each
deployment. Scaling policy work is an active area — see the project's
technical notes for the current state of seasonal/dynamic scaling.

---

## Business Value Delivered

### For the Salon

- Customers can book appointments 24/7 without calling
- Real-time slot availability prevents double-bookings
- Announcements (promotions, closures, holiday hours) update instantly via DynamoDB
- System handles multiple concurrent users reliably on RDS

### Operational Efficiency

- Repeatable, documented deployment process, proven across two different
  compute architectures
- Automated quality enforcement reduces bug escape rate to near zero
- Infrastructure as code (Terraform) — the entire system can be reproduced
  in a new AWS account
- Full audit trail — every deployment traceable to a specific commit
- Zero manual deployment steps after initial setup
- Rollback time reduced from hours (manual) to minutes (automated,
  alarm-gated)

---

## Estimated Business Impact

Manual scheduling previously required staff time and caused booking conflicts.

The automated system enables:

- **24/7 appointment booking** — customers book outside business hours
- **Reduced staff workload** — no phone calls for appointment scheduling
- **Improved customer satisfaction** — instant confirmation, no double-bookings
- **Scalable infrastructure** — supports business growth without infrastructure changes
- **Operational cost savings** — the EKS→EC2 migration roughly halved the
  core run cost (~$180-220/mo to ~$115/mo at list price) with no loss of HA
  characteristics

---

## Conclusion

The delivered platform transforms a manually managed, error-prone process
into a reliable, automated system live today on a cost-appropriate
architecture. The hair salon client has a professional booking platform
with enterprise-grade reliability — and the platform's own history (EKS
built and proven, then migrated to EC2 after a real cost review) is itself
evidence of the same judgment that shaped every other design decision here:
IAM auth over passwords, immutable image tags, alarm-gated rollback,
production reliability and operational simplicity as the primary goals
throughout, not just at delivery.

---

*Emmanuel Fornah — Cloud Developer*
