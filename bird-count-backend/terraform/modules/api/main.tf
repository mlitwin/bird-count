# Sync API: Lambda (TypeScript, nodejs24.x) behind an API Gateway HTTP API
# with a Lambda authorizer that handles both Cognito user tokens and M2M tokens.
# Build the bundle first: `make api-build`.

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${var.lambda_dist_dir}/index.mjs"
  output_path = "${var.lambda_dist_dir}/lambda.zip"
}

data "archive_file" "authorizer_zip" {
  type        = "zip"
  source_file = "${var.lambda_dist_dir}/authorizer.mjs"
  output_path = "${var.lambda_dist_dir}/authorizer.zip"
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

resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-${var.environment}-api"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      TABLE_NAME      = var.table_name
      VALKEY_ENDPOINT = var.valkey_endpoint
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
  tags       = var.tags
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"

  # Browser access from the web viewer
  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_headers = ["authorization", "content-type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    max_age       = 3600
  }

  tags = var.tags
}

# Lambda authorizer: handles Cognito user tokens (validates aud) and M2M tokens
# (validates scope). Must run outside the VPC to reach the Cognito JWKS URL.

resource "aws_iam_role" "authorizer" {
  name               = "${var.project_name}-${var.environment}-authorizer"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-authorizer"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-${var.environment}-authorizer"
  role             = aws_iam_role.authorizer.arn
  runtime          = "nodejs24.x"
  handler          = "authorizer.handler"
  filename         = data.archive_file.authorizer_zip.output_path
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256
  timeout          = 5

  environment {
    variables = {
      USER_POOL_ID   = var.user_pool_id
      USER_AUDIENCES = join(",", var.user_audiences)
      M2M_SCOPE      = var.m2m_scope
    }
  }

  depends_on = [aws_cloudwatch_log_group.authorizer]
  tags       = var.tags
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*"
}

resource "aws_apigatewayv2_authorizer" "lambda" {
  api_id                            = aws_apigatewayv2_api.http.id
  authorizer_type                   = "REQUEST"
  name                              = "lambda-authorizer"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_result_ttl_in_seconds  = 300
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
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
}

resource "aws_apigatewayv2_route" "observations" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /v1/observations"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
}

resource "aws_apigatewayv2_route" "summary" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /v1/summary"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
}

resource "aws_apigatewayv2_route" "observations_query" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /v1/observations/query"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
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

# Alerting: email is optional; without it the alarms are still visible in
# the CloudWatch console.
resource "aws_sns_topic" "alarms" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-api-alarms"
  tags  = var.tags
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-api-lambda-errors"
  alarm_description   = "Sync Lambda reported errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-api-5xx"
  alarm_description   = "HTTP API returning 5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.http.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  tags                = var.tags
}

# ── seq-maintenance Lambda ────────────────────────────────────────────────────
# Operator-invoked only (no API Gateway route). Seeds and backfills the Valkey
# sequence counter. Invoke via: aws lambda invoke --function-name <name> ...

data "archive_file" "seq_maintenance_zip" {
  type        = "zip"
  source_file = "${var.lambda_dist_dir}/seqMaintenance.mjs"
  output_path = "${var.lambda_dist_dir}/seqMaintenance.zip"
}

resource "aws_cloudwatch_log_group" "seq_maintenance" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-seq-maintenance"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_iam_role" "seq_maintenance" {
  name               = "${var.project_name}-${var.environment}-seq-maintenance"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "seq_maintenance_table" {
  name   = "table-access"
  role   = aws_iam_role.seq_maintenance.id
  policy = var.table_policy_json
}

resource "aws_iam_role_policy_attachment" "seq_maintenance_logs" {
  role       = aws_iam_role.seq_maintenance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "seq_maintenance_vpc" {
  role       = aws_iam_role.seq_maintenance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "seq_maintenance" {
  function_name    = "${var.project_name}-${var.environment}-seq-maintenance"
  role             = aws_iam_role.seq_maintenance.arn
  runtime          = "nodejs24.x"
  handler          = "seqMaintenance.handler"
  filename         = data.archive_file.seq_maintenance_zip.output_path
  source_code_hash = data.archive_file.seq_maintenance_zip.output_base64sha256
  timeout          = 300
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  environment {
    variables = {
      TABLE_NAME      = var.table_name
      VALKEY_ENDPOINT = var.valkey_endpoint
    }
  }

  depends_on = [aws_cloudwatch_log_group.seq_maintenance]
  tags       = var.tags
}
