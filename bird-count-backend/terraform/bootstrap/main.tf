# Account-global CI/CD bootstrap: GitHub OIDC federation for deploys.
# Applied ONCE locally (make bootstrap) — not part of the per-env stacks.
# Pattern: https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "birdcount-tfstate-477808199271"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "bird-count"
      ManagedBy = "terraform"
      Scope     = "bootstrap"
    }
  }
}

locals {
  github_repo  = "mlitwin/bird-count"
  state_bucket = "birdcount-tfstate-477808199271"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# Only main-branch pushes and vX.Y.Z tags of the monorepo may deploy —
# no pull_request or fork federation.
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.github_repo}:ref:refs/heads/main",
        "repo:${local.github_repo}:ref:refs/tags/v*",
      ]
    }
  }
}

# Terraform manages IAM roles/policies for the Lambda, which PowerUserAccess
# excludes — grant IAM scoped to this project's naming prefix.
data "aws_iam_policy_document" "deploy_iam" {
  statement {
    sid    = "ProjectScopedIAM"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole",
      "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:PassRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::*:role/birdcount-*"]
  }

  statement {
    sid       = "ReadOIDCProvider"
    effect    = "Allow"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "birdcount-github-deploy"
  description        = "Assumed by GitHub Actions (${local.github_repo}) to deploy the backend"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "deploy_iam" {
  name   = "project-scoped-iam"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.deploy_iam.json
}

resource "aws_iam_role_policy_attachment" "poweruser" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

# Cost backstop for the whole account: email alerts as spend approaches
# a modest monthly ceiling (throttling limits per-service abuse; this
# catches everything else).
resource "aws_budgets_budget" "monthly" {
  name         = "birdcount-monthly"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["mlitwin@sonic.net"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["mlitwin@sonic.net"]
  }
}
