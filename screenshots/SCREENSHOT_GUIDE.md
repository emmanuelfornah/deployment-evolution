# Screenshot Guide

## Setup, Testing & CI (Phases 1–4)

| # | Filename | What It Shows |
|---|----------|---------------|
| 01 | `01_ide_workspace_setup.png` | IDE workspace with cloned repository |
| 02 | `02_codecommit_repository.png` | CodeCommit repository in AWS Console |
| 03 | `03_application_initial_launch.png` | Application running — clean homepage |
| 04 | `04_appointment_timeslot_selection.png` | Appointment booking with timeslots visible |
| 05 | `05_unit_test_coverage_100.png` | Test coverage at 100% |
| 06 | `06_coverage_views_module.png` | Coverage report — views module detail |
| 07 | `07_coverage_full_report.png` | Full coverage report |
| 08 | `08_template_update_push.png` | Git push of template changes |
| 09 | `09_codebuild_succeeded.png` | CodeBuild project — build succeeded |
| 10 | `10_pipeline_all_stages_green.png` | CodePipeline — all stages green |

## Troubleshooting, Rollbacks & ALB (Phase 5)

| # | Filename | What It Shows |
|---|----------|---------------|
| 11 | `11_kubectl_pod_error_logs.png` | Terminal: `kubectl logs` showing the `wrongregion` endpoint error |
| 12 | `12_region_fix_deployed.png` | Terminal: `kubectl apply` output + `curl` returning HTML after region fix |
| 13 | `13_base_template_orange_update.png` | Base template changed to the orange background |
| 14 | `14_pipeline_orange_build_succeeded.png` | CodePipeline: all stages green after orange background push |
| 15 | `15_app_orange_background.png` | Browser: application with orange background color |
| 16 | `16_pipeline_cadetblue_build_succeeded.png` | CodePipeline: all stages green after cadetblue background push |
| 17 | `17_app_cadetblue_background.png` | Browser: application with cadetblue background color |
| 18 | `18_rollout_history.png` | Terminal: `kubectl rollout history` for the deployment |
| 19 | `19_rollback_to_orange.png` | Terminal: `kubectl rollout undo` + browser showing orange restored |
| 20 | `20_eks_cluster_verified.png` | EKS cluster verified |
| 21 | `21_alb_controller_installed.png` | AWS Load Balancer Controller installed |
| 22 | `22_helm_installed.png` | Helm installed |

## Screenshots — EKS Deploy Pipeline & Rollback (Phase 6)

Located in `screenshots/deploy-pipeline/`:

| # | Filename | What It Shows |
|---|----------|---------------|
| 01 | `01-deploy-buildspec-configuration.png` | CodeBuild DeployPods project buildspec configuration |
| 02 | `02-application-running-verification.png` | Application running via ALB after EKS deployment |
| 03 | `03-pipeline-all-stages-succeeded.png` | Full CI/CD pipeline — all 4 stages succeeded |
| 04 | `04-ui-theme-update-cadetblue.png` | UI theme update to cadetblue triggered via pipeline |
| 05 | `05-ui-cadetblue-deployed.png` | Application displaying cadetblue background |
| 06 | `06-git-revert-rollback-to-original.png` | Git revert rollback — original theme restored |

## EC2 Blue/Green — Live (current)

Located in `screenshots/ec2-live/`:

| # | Filename | What It Shows |
|---|----------|---------------|
| 01 | `01_live_app_booking_form.png` | Live app booking form on the production domain |
| 02 | `02_live_app_booking_confirmed.png` | Booking confirmed — live domain, valid HTTPS |
| 03 | `03_pipeline_all_stages_green.png` | CodePipeline — all 4 stages green |
| 04 | `04_codedeploy_bluegreen_traffic_shift.png` | CodeDeploy blue/green traffic shift |
| 05 | `05_alb_listeners_https.png` | ALB listeners — HTTPS with HTTP redirect |
| 06 | `06_codedeploy_deployment_history.png` | CodeDeploy deployment history |
| 07 | `07_s3_buckets_overview.png` | S3 buckets overview |
| 08 | `08_cost_explorer_actual_spend.png` | Cost Explorer — actual spend |

## Architecture Diagrams

Located in `screenshots/architecture/`:

| Filename | What It Shows |
|----------|---------------|
| `ec2-full-infrastructure-architecture.webp` | Current infrastructure: 3-tier VPC, ALB, Auto Scaling Group, RDS, DynamoDB, SSM |
| `ec2-bluegreen-pipeline-architecture.webp` | Current CI/CD pipeline and CodeDeploy blue/green rollout |
| `ec2-bluegreen-pipeline-simple.png` | Simplified view of the current pipeline and blue/green flow |
| `cicd-pipeline-eks-architecture.png` | Phase 1: end-to-end CI/CD pipeline and EKS infrastructure architecture |

## Monitoring & Alerting (live)

Located in `screenshots/monitoring/`. Built by [`infra/monitoring.tf`](../infra/monitoring.tf); see [`MONITORING.md`](../MONITORING.md).

| # | Filename | What It Shows |
|---|----------|---------------|
| 01 | `01_sns_subscription_confirmed.png` | SNS email subscription to `appointments-alerts` confirmed |
| 02 | `02_alarm_email_slo_slow_burn.png` | Alarm email: 6h error-budget burn-rate SLO alarm entering OK, with its metric-math expression |
| 03 | `03_alarm_detail_slo_slow_burn.png` | Alarm configuration: 6h burn-rate threshold (0.6%), error-budget math expression over three ALB metrics, SNS actions enabled, state OK |
| 04 | `04_alarm_graph_slo_slow_burn.png` | 6h 5xx error rate at 0% against the 0.6% burn-rate threshold; state timeline from insufficient data to OK at apply time |
| 05 | `05_alarms_list_all_ok.png` | All 12 `appointments-` alarms created by Terraform, state OK, actions enabled |
| 06 | `06_cloudwatch_overview_alarms_by_service.png` | CloudWatch overview: 12 alarms OK across ALB, RDS and the agent namespace `appointments/ContainerMetrics`; p95 latency ~2 ms against the 500 ms SLO |
| 07 | `07_application_map_summary.png` | CloudWatch Application Map for the ALB: 0 5xx, 100% availability; most traffic is 4xx from scanners, which is why 4xx is excluded from the availability SLI |
| 08 | `08_dashboard_appointments.png` | The Terraform-built `appointments` dashboard: SLO targets, all 12 alarms OK, requests/sec, p95/p50 latency against the 500 ms SLO line, 5xx error rate against the 0.1% error-budget line |
| 09 | `09_resource_group_tagged_resources.png` | Resource group by tag: 79 resources carrying the cost-allocation tags, including an app instance launched after apply (tags applied through the launch template) |
| 10 | `10_terraform_plan_no_drift.txt` | `terraform plan` after apply: no differences between the code and AWS |
