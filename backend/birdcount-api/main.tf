terraform {
  required_providers {
    aws = {
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "birdcount-terraform-state"
    key    = "tfstate/birdcount-api"
    region = "us-east-1"
  }
}

locals {
  region = "us-east-1"
  app_name = "birdcount-api"
}

data "aws_caller_identity" "current" {}

