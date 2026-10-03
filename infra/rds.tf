# App connects via IAM auth (rds-db:connect, see iam.tf) — no DB
# password ever touches app code, env vars, or the appspec. RDS still
# needs a master credential for administration; that's generated and
# rotated by RDS itself into Secrets Manager (manage_master_user_password),
# so nobody — including this Terraform run — ever sees it in plaintext.

resource "aws_kms_key" "rds" {
  description             = "RDS storage encryption - appointments"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_db_subnet_group" "main" {
  name       = "appointments-db-subnet-group"
  subnet_ids = aws_subnet.private_data[*].id
}

resource "aws_db_instance" "main" {
  identifier        = "scheduler-db" # matches the name already in use
  engine            = "mysql"
  engine_version    = "8.4" # RDS upgraded the instance to 8.4.x when MySQL 8.0 left standard support; "8.0" here would plan a downgrade AWS rejects
  instance_class    = var.db_instance_class
  allocated_storage = 20 # GB — RDS free-tier ceiling, plenty at this app's scale
  storage_type      = "gp3"

  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true # RDS-managed secret, auto-rotated, never exposed to us

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  iam_database_authentication_enabled = true

  multi_az                  = var.db_multi_az
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "scheduler-db-final"

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # RDS applies minor version upgrades itself (auto_minor_version_upgrade
  # defaults to true), so the exact running version (8.4.9 today) moves
  # under Terraform. Without this, every plan would show a change back
  # to the bare "8.4" and send a version-change request to the live DB.
  # allow_major_version_upgrade was set once for the 8.0 -> 8.4 upgrade
  # and is only a request flag, not a property of the instance.
  lifecycle {
    ignore_changes = [engine_version, allow_major_version_upgrade]
  }
}

# iam_database_authentication_enabled above only turns the *feature* on —
# it doesn't create or configure any MySQL user to use it. This runs once
# (idempotent) via SSM against a running app instance to create
# app_db_username as a dedicated IAM-auth-only user, separate from the
# password-based master account. Found via a real deployment failure
# ("Access denied ... using password: YES") that skipping this step
# silently succeeds at the Terraform/AWS level while breaking the app.
resource "null_resource" "bootstrap_rds_iam_user" {
  triggers = {
    db_instance_id = aws_db_instance.main.id
    script_hash    = filemd5("${path.module}/../scripts/bootstrap_rds_iam_user.py")
  }

  depends_on = [
    aws_db_instance.main,
    aws_iam_role_policy.app_secrets,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = templatefile("${path.module}/templates/bootstrap_rds_user.sh.tpl", {
      script_path       = "${path.module}/../scripts/bootstrap_rds_iam_user.py"
      aws_region        = var.aws_region
      aws_profile       = "capstone"
      master_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
      db_host           = aws_db_instance.main.address
      db_name           = var.db_name
      app_db_user       = var.app_db_username
      ecr_registry      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
      ecr_repo_name     = aws_ecr_repository.app.name
    })
  }
}
