resource "aws_ecr_repository" "app" {
  name         = "containers-image-repository" # matches the name already in use
  force_delete = true                          # teardown deletes the images with the repo
  # IMMUTABLE means the buildspec can no longer push a reusable "latest"
  # tag — deploys must reference the commit-SHA tag instead. That's a
  # deliberate change, not just a stricter default: blue/green needs an
  # unambiguous, non-overwritable image reference per deployment, and it
  # closes the "someone re-pushes latest and prod silently changes"
  # class of issue. Update the BuildImage/DeployPods buildspecs to drop
  # the `latest`/`staging-test-image` tags and pass the SHA tag through.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_repository_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAccountPullPush"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
      ]
    }]
  })
}
