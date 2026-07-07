# Sync API: Lambda (TypeScript, nodejs20.x) behind an API Gateway HTTP API
# with a Cognito JWT authorizer. Build the bundle first: `make api-build`.

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${var.lambda_dist_dir}/index.mjs"
  output_path = "${var.lambda_dist_dir}/lambda.zip"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-api"
  retention_in_days = 30
  tags              = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-${var.environment}-api-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "table_access" {
  name   = "table-access"
  role   = aws_iam_role.lambda.id
  policy = var.table_policy_json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-${var.environment}-api"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
  tags       = var.tags
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito"

  jwt_configuration {
    audience = [var.client_id]
    issuer   = var.issuer_url
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /v1/health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "sync" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /v1/sync"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "observations" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /v1/observations"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  tags = var.tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
