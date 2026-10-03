resource "aws_cloudwatch_log_group" "app" {
  name              = "/appointments/app"
  retention_in_days = 30
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_launch_template" "app" {
  name_prefix   = "appointments-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  # No key_name — no SSH keypair exists for these instances at all.
  # Access is exclusively via SSM Session Manager (iam.tf), which is
  # logged to CloudTrail and doesn't require an open inbound port.

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only — closes the SSRF-to-credential-theft path IMDSv1 allows
    # 2, not 1: the app runs inside a Docker container, and a request
    # from inside it to IMDS crosses one extra network hop (the
    # container's bridge interface) beyond the host itself. hop_limit=1
    # silently blocked that, surfacing as "Unable to locate credentials"
    # from boto3 inside the container (django_iam_dbauth generating the
    # RDS auth token) — found via a real deployment, not anticipated.
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  monitoring {
    enabled = true # detailed CloudWatch metrics, matters for ASG scaling responsiveness
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tpl", {
    aws_region        = var.aws_region
    log_group         = aws_cloudwatch_log_group.app.name
    metrics_namespace = local.agent_metrics_namespace
    secret_arn        = aws_secretsmanager_secret.app_config.arn
    database_host     = aws_db_instance.main.address
    db_username       = var.app_db_username
    db_name           = var.db_name
    app_port          = var.app_port
    health_check_path = var.health_check_path
  }))

  # default_tags don't reach resources launched *from* a template, so
  # the instances and their volumes (the bulk of compute spend) need the
  # cost tags here explicitly or they show up as untagged in Cost Explorer.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.cost_tags, { Name = "appointments-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.cost_tags, { Name = "appointments-app" })
  }
}

# No aws_autoscaling_group resource here on purpose. There was one —
# "appointments-asg" — but CodeDeploy's ASG-copy blue/green (COPY_AUTO_
# SCALING_GROUP, codedeploy.tf) doesn't scale it, it *replaces* it: on
# the first successful deployment CodeDeploy created a new ASG
# (CodeDeploy_appointments-blue-green_<deployment-id>) using this launch
# template, cut traffic over, and deleted the original outright — not
# scaled to 0, gone. Every future deployment repeats this with a new
# ASG each time. Terraform owning a static "appointments-asg" resource
# after that first deploy meant every unrelated `apply` (e.g. adding
# dns.tf's Route 53 record) would try to recreate it — a duplicate,
# unused, real-cost ASG sitting next to the one CodeDeploy actually
# manages. Removed from state (`terraform state rm`) rather than fought
# with `ignore_changes`, since Terraform can't ignore a resource being
# gone entirely, only attribute-level drift on one that still exists.
# CodeDeploy fully owns the live compute going forward; Terraform still
# owns the launch template CodeDeploy copies from, and everything else
# in this stack (VPC, ALB, RDS, IAM, ECR, the pipeline itself).
#
# Consequence: `terraform destroy` no longer tears down the live ASG.
# Manually delete the current CodeDeploy_appointments-blue-green_*
# ASG (force-delete, terminates its instances) before destroying.
