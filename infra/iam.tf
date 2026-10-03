# Least-privilege IAM: every policy below is scoped to a specific
# resource ARN, not "*". This replaces the appointments-sa IRSA role
# from the EKS design — same permission set, different trust model.

data "aws_caller_identity" "current" {}

# --- EC2 instance role (what the app itself runs as) ---

resource "aws_iam_role" "app_instance" {
  name = "appointments-app-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "appointments-app-instance-profile"
  role = aws_iam_role.app_instance.name
}

# SSM Session Manager instead of SSH keypairs/open port 22 — access is
# via `aws ssm start-session`, logged to CloudTrail, no bastion host,
# no key material to leak.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "codedeploy_agent" {
  role       = aws_iam_role.app_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy" "app_ecr_pull" {
  name = "ecr-pull-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this specific action has no resource-level permission support
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages", # scripts/bootstrap_rds_user.sh.tpl looks up the latest pushed tag
        ]
        Resource = aws_ecr_repository.app.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "app_dynamodb" {
  name = "dynamodb-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan", # appointments/views.py's index view scans the whole table
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
      ]
      Resource = aws_dynamodb_table.announcements.arn
    }]
  })
}

resource "aws_iam_role_policy" "app_rds_iam_auth" {
  name = "rds-iam-auth-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.main.resource_id}/${var.app_db_username}"
    }]
  })
}

resource "aws_iam_role_policy" "app_secrets" {
  name = "secrets-read-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_secretsmanager_secret.app_config.arn,
        # RDS-managed master secret — only needed by
        # scripts/bootstrap_rds_iam_user.py (run once via SSM to create
        # the appointments_web IAM-auth MySQL user, null_resource in
        # rds.tf). Widens the app's normal runtime role to also
        # read the master credential permanently, which isn't ideal
        # least-privilege — accepted as a documented tradeoff rather
        # than a two-phase apply for a one-time bootstrap step.
        aws_db_instance.main.master_user_secret[0].secret_arn,
      ]
    }]
  })
}

# CloudWatch agent metrics (user-data.sh.tpl). PutMetricData has no
# resource-level scoping, so the namespace condition is the only way to
# stop the instance writing into any other namespace.
resource "aws_iam_role_policy" "app_cloudwatch_metrics" {
  name = "cloudwatch-metrics-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "cloudwatch:PutMetricData"
      Resource = "*"
      Condition = {
        StringEquals = { "cloudwatch:namespace" = local.agent_metrics_namespace }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_cloudwatch_logs" {
  name = "cloudwatch-logs-scoped"
  role = aws_iam_role.app_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # No logs:CreateLogGroup — compute.tf already creates this log group,
      # and start_container.sh runs the awslogs driver with
      # awslogs-create-group=false, so the instance never needs to create one.
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.app.arn}:*"
    }]
  })
}

# --- CodeDeploy service role (what CodeDeploy assumes to drive the ASG/ALB) ---

resource "aws_iam_role" "codedeploy" {
  name = "appointments-codedeploy-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# AWSCodeDeployRole deliberately excludes iam:PassRole and ec2:RunInstances.
# COPY_AUTO_SCALING_GROUP blue/green needs both: CodeDeploy calls RunInstances
# directly (confirmed via CloudTrail, not just guessed) to populate the
# replacement ASG, and since the launch template carries an IAM instance
# profile, it also needs to pass that role along. The managed policy's own
# generic "no permission for AmazonAutoScaling operations" error was
# misleading — CloudTrail showed the actual denial was ec2:RunInstances,
# not an AutoScaling API at all.
resource "aws_iam_role_policy" "codedeploy_pass_role" {
  name = "pass-app-instance-role-scoped"
  role = aws_iam_role.codedeploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = aws_iam_role.app_instance.arn
    }]
  })
}

resource "aws_iam_role_policy" "codedeploy_run_instances" {
  name = "run-instances-scoped"
  role = aws_iam_role.codedeploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:launch-template/*",
          "arn:aws:ec2:${var.aws_region}::image/*", # AMI — no account ID, may be Amazon-owned
        ]
      },
      {
        # RunInstances via ASG also tags the new instance (Name=appointments-app,
        # CodeDeployProvisioningDeploymentId=...) — caught via CloudTrail after
        # RunInstances itself started succeeding.
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
        ]
      },
    ]
  })
}
