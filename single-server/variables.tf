variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "domain_name" {
  type    = string
  default = "appointments.emmanuelfornah.com"
}

variable "root_domain" {
  description = "Pre-existing Route 53 hosted zone, managed outside Terraform."
  type        = string
  default     = "emmanuelfornah.com"
}

variable "instance_type" {
  description = "Graviton. 1 GB is enough to build the image on first boot (with the swap file user-data adds) and run Django + Caddy."
  type        = string
  default     = "t4g.micro"
}

variable "repo_url" {
  description = "Public repo the instance clones and builds the image from on first boot. No ECR or pipeline needed."
  type        = string
  default     = "https://github.com/emmanuelfornah/deployment-evolution.git"
}

variable "git_ref" {
  type    = string
  default = "main"
}

variable "announcements_table" {
  description = "Existing DynamoDB table the index view scans. Referenced, not managed, so it survives a destroy of either stack."
  type        = string
  default     = "DEV_Announcement"
}

variable "point_dns" {
  description = "false: the app is reachable only on the Elastic IP over HTTP, for checking before cutover. true: the domain's A record points at this instance (UPSERT over the ALB alias) and Caddy serves HTTPS."
  type        = bool
  default     = false
}
