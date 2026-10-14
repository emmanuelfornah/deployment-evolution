terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same state bucket and lock table as infra/, separate key, so this
  # stack and the full stack never share or overwrite each other's state.
  backend "s3" {
    bucket         = "aws-eks-cicd-capstone-tfstate-460223322833"
    key            = "deployment-evolution/single-server/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "aws-eks-cicd-capstone-tflock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "appointments"
      Environment = "demo"
      Owner       = "emmanuel"
      ManagedBy   = "terraform"
    }
  }
}
