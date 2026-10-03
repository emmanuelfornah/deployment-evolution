terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Remote state, not local — this stack holds RDS/ASG/IAM resources
  # that must never be re-created from an empty local state file.
  backend "s3" {
    bucket         = "aws-eks-cicd-capstone-tfstate-460223322833"
    key            = "aws-eks-cicd-capstone/primary/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "aws-eks-cicd-capstone-tflock"
  }
}

# Cost-allocation tags. Activate Project, Environment and Owner as
# user-defined cost allocation tags in Billing so Cost Explorer can
# group spend by them (a one-time console step; tags only apply to
# usage from the activation date forward).
locals {
  cost_tags = {
    Project     = "appointments"
    Environment = "production"
    Owner       = var.github_repo_owner
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.cost_tags
  }
}
