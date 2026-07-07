# main.tf

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Lambda function
resource "aws_lambda_function" "example_lambda" {
  filename         = "lambda.zip"
  function_name    = "example-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("lambda.zip")
  runtime          = "nodejs14.x"
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "example-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "example_api" {
  name        = "example-api"
  description = "Example API Gateway"
}

resource "aws_api_gateway_resource" "example_resource" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  parent_id   = aws_api_gateway_rest_api.example_api.root_resource_id
  path_part   = "example"
}

resource "aws_api_gateway_method" "example_method" {
  rest_api_id   = aws_api_gateway_rest_api.example_api.id
  resource_id   = aws_api_gateway_resource.example_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "example_integration" {
  rest_api_id             = aws_api_gateway_rest_api.example_api.id
  resource_id             = aws_api_gateway_resource.example_resource.id
  http_method             = aws_api_gateway_method.example_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.example_lambda.invoke_arn
}

# Aurora Serverless PostgreSQL
resource "aws_rds_cluster" "example_db" {
  cluster_identifier      = "example-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "serverless"
  database_name           = "exampledb"
  master_username         = "root"
  master_password         = "changeme"  # Change this in production
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 4
    min_capacity             = 2
    seconds_until_auto_pause = 300
    timeout_action           = "ForceApplyCapacityChange"
  }
}

# Outputs
output "api_url" {
  value = aws_api_gateway_deployment.example_deployment.invoke_url
}

output "db_endpoint" {
  value = aws_rds_cluster.example_db.endpoint
}
