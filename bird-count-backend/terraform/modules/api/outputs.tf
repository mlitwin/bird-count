output "api_url" {
  description = "Base URL for all v1 API routes"
  value       = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/v1"
}

output "lambda_function_name" {
  value = aws_lambda_function.api.function_name
}
