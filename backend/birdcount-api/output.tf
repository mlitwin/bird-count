output "observations_db_id" {
  value = aws_dynamodb_table.observations_table.id
}

output "observations_db_arn" {
  value = aws_dynamodb_table.observations_table.arn
}

output api_endpoint {
  value = aws_apigatewayv2_api.birdcount_api.api_endpoint
}