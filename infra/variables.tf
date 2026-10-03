variable "aws_region" {
  description = "Primary region. AWS has no region physically in Texas; us-east-2 (Ohio) is the nearest full region to a Texas-based salon business and what the DR pairing below assumes as primary."
  type        = string
  default     = "us-east-2"
}

variable "domain_name" {
  description = "Subdomain the ALB is reachable at. The root domain (emmanuelfornah.com) and its Route 53 hosted zone are pre-existing — registered and managed outside this Terraform, referenced here via data source."
  type        = string
  default     = "appointments.emmanuelfornah.com"
}

variable "root_domain" {
  type    = string
  default = "emmanuelfornah.com"
}

variable "dr_region" {
  description = "Cross-region DR target (pilot light — see DR_SCENARIO.md, not yet built as Terraform). us-west-2 deliberately, not us-east-1: it's on a different power grid and weather system than the Gulf Coast/central-US winter-storm risk (2021 Texas/ERCOT-style event) that's the actual disaster scenario here, not just 'AWS's other big region.'"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "app_port" {
  description = "Port the Django/gunicorn container listens on"
  type        = number
  default     = 8088
}

variable "instance_type" {
  type    = string
  default = "t4g.small" # Graviton — cheaper; Dockerfile must build a multi-arch or arm64 image
}

variable "asg_min_size" {
  type    = number
  default = 2 # one per AZ minimum, for HA
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "db_name" {
  type    = string
  default = "django_appointments"
}

variable "db_username" {
  description = "RDS master/admin account — password-based (RDS-managed secret), for administration only. The app never connects as this user. (Left as the original variable/value to avoid forcing RDS replacement — username is immutable on aws_db_instance once created.)"
  type        = string
  default     = "appointments_web"
}

variable "app_db_username" {
  description = "Dedicated IAM-auth-only MySQL user the app actually connects as. Deliberately distinct from db_username: found on a real deployment that pointing the app at the master account meant its IAM token was presented to a user never configured for IAM auth — access denied, not because the user was missing."
  type        = string
  default     = "appointments_app"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Set true for RDS-level HA within the region. Off by default to keep the base stack cheap; DR posture is handled by the separate cross-region read replica, not this flag."
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "No dedicated health endpoint exists in the app yet (checked appointments/urls.py and hairdresser_django/urls.py — only /, /service/..., /create, /admin/). Defaults to the index route so the stack is deployable as-is; switch to a real /healthz view once one exists — the index route renders a full page and hits the DB, which is a heavier and less reliable liveness check than a dedicated endpoint should be."
  type        = string
  default     = "/"
}

variable "github_repo_owner" {
  description = "GitHub org/user that owns the app repo the pipeline sources from"
  type        = string
  default     = "emmanuelfornah"
}

variable "github_repo_name" {
  type    = string
  default = "deployment-evolution"
}

variable "github_branch" {
  description = "Branch CodePipeline tracks for automatic triggers"
  type        = string
  default     = "main"
}

variable "acm_certificate_arn" {
  description = "ACM cert for the ALB HTTPS listener — must be issued in the same region as the ALB. No default: HTTPS is not optional."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on 443. Defaults to the internet since this is a public demo app; narrow this if it ever isn't."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarm notifications (monitoring.tf). AWS sends a confirmation link after apply; alerts start once it's clicked. Empty = topic and alarms are still created, nobody is subscribed."
  type        = string
  default     = ""
}

variable "slo_availability_target" {
  description = "Availability SLO: share of ALB requests that are not 5xx, over 30 days (MONITORING.md). Drives the error-budget burn-rate alarms."
  type        = number
  default     = 99.9
}

variable "slo_latency_p95_seconds" {
  description = "Latency SLO: p95 TargetResponseTime at the ALB. 0.5s to start (server-rendered Django + an RDS query + a DynamoDB scan per page); tighten toward 0.3s once a few weeks of dashboard data confirm the real baseline."
  type        = number
  default     = 0.5
}
