# Main Terraform configuration for Bird Count Backend
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "bird-count"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  project_name = "birdcount"
  common_tags = {
    Project     = "bird-count"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# S3 and CloudFront for web application hosting
module "storage" {
  source = "./modules/storage"

  project_name = local.project_name
  environment  = var.environment
  
  tags = local.common_tags
}