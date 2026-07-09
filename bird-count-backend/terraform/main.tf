# Main Terraform configuration for Bird Count Backend
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
  web_acl_arn  = var.enable_waf ? aws_wafv2_web_acl.web[0].arn : ""

  tags = local.common_tags
}

# Cognito user pool + Sign in with Apple
module "auth" {
  source = "./modules/auth"

  project_name = local.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  apple_team_id     = var.apple_team_id
  apple_services_id = var.apple_services_id
  apple_key_id      = var.apple_key_id
  apple_private_key = var.apple_private_key
  callback_urls     = var.callback_urls
  web_callback_urls = [
    "https://${module.storage.cloudfront_domain_name}/",
    "http://localhost:8788/",
  ]

  tags = local.common_tags
}

# DynamoDB observation ledger
module "db" {
  source = "./modules/db"

  project_name = local.project_name
  environment  = var.environment

  tags = local.common_tags
}

# Sync API: Lambda + HTTP API + JWT authorizer
module "api" {
  source = "./modules/api"

  project_name = local.project_name
  environment  = var.environment

  lambda_dist_dir   = "${path.module}/../api/dist"
  table_name        = module.db.table_name
  table_policy_json = module.db.readwrite_policy_json
  issuer_url        = module.auth.issuer_url
  jwt_audience      = [module.auth.client_id, module.auth.web_client_id]
  cors_allow_origins = [
    "https://${module.storage.cloudfront_domain_name}",
    "http://localhost:8788",
  ]
  alarm_email = var.alarm_email

  tags = local.common_tags
}
