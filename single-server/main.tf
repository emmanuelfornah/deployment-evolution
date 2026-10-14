# Cost control on a portfolio project: keeps the public URL serving the
# real app on one Graviton instance in the default VPC's public subnet,
# running the same Docker image as the full stack with SQLite instead of
# RDS, and Caddy in front for automatic Let's Encrypt HTTPS. No ALB, NAT,
# RDS or endpoints. The full stack stays in infra/ and can be re-applied
# for a demo of the HA architecture.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_route53_zone" "root" {
  name = var.root_domain
}

data "aws_dynamodb_table" "announcements" {
  name = var.announcements_table
}

resource "aws_security_group" "web" {
  name        = "appointments-single-server"
  description = "HTTP/HTTPS from anywhere; no SSH, admin access is SSM only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP (ACME challenge + redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "app" {
  name = "appointments-single-server"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "announcements_read" {
  name = "announcements-read"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Scan"]
      Resource = data.aws_dynamodb_table.announcements.arn
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "appointments-single-server"
  role = aws_iam_role.app.name
}

# Allocated before the instance so its address can go into user-data:
# Caddy serves plain HTTP on the IP for checking before DNS cutover.
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "appointments-single-server" }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/templates/user-data.sh.tpl", {
    aws_region  = var.aws_region
    domain_name = var.domain_name
    public_ip   = aws_eip.app.public_ip
    repo_url    = var.repo_url
    git_ref     = var.git_ref
  })
  user_data_replace_on_change = true

  # IMDSv2 only. hop_limit=2 (not 1 as in infra/) because the app runs
  # in a bridge-networked container and needs instance-role credentials
  # for the DynamoDB scan; at 1 the extra hop drops the IMDS response.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  # A newer AL2023 AMI shouldn't replace a working instance (and wipe
  # its SQLite bookings) on some unrelated apply.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "appointments-single-server" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# UPSERT over the full stack's ALB alias record. Run
# `terraform state rm aws_route53_record.app` in infra/ before
# destroying it, or that destroy deletes this record too.
resource "aws_route53_record" "app" {
  count           = var.point_dns ? 1 : 0
  zone_id         = data.aws_route53_zone.root.zone_id
  name            = var.domain_name
  type            = "A"
  ttl             = 60
  records         = [aws_eip.app.public_ip]
  allow_overwrite = true
}
