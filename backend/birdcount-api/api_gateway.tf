resource "aws_apigatewayv2_api" "birdcount_api" {
  name          = "birdcount-api"
  protocol_type = "HTTP"
}


resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "birdcount-api"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.observations_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.birdcount_api.execution_arn}/*"
}

resource "aws_lambda_permission" "api_gateway_authorizer" {
  statement_id  = "birdcount-api-authorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.observations_lambda_authorizer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.birdcount_api.execution_arn}/*"
}

resource "aws_apigatewayv2_integration" "birdcount_api" {
  api_id           = aws_apigatewayv2_api.birdcount_api.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  integration_uri           = aws_lambda_function.observations_lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id = aws_apigatewayv2_api.birdcount_api.id
  name   = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.birdcount_api.id
  route_key = "$default"
  authorization_type = "CUSTOM"
  authorizer_id  = aws_apigatewayv2_authorizer.birdcount_api.id
  target = "integrations/${aws_apigatewayv2_integration.birdcount_api.id}"
}

resource "aws_apigatewayv2_deployment" "birdcount_api" {
  api_id      = aws_apigatewayv2_api.birdcount_api.id
  description = "birdcount_api deployment"

  triggers = {
    redeployment = sha1(join(",", tolist([
      jsonencode(aws_apigatewayv2_integration.birdcount_api),
      jsonencode(aws_apigatewayv2_route.default),
    ])))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_authorizer" "birdcount_api" {
  api_id                            = aws_apigatewayv2_api.birdcount_api.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.observations_lambda_authorizer.invoke_arn
  authorizer_result_ttl_in_seconds  = 0
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "observations_lambda_authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses         = true
}
