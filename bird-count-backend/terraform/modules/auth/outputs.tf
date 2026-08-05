output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.ios.id
}

output "web_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "hosted_ui_domain" {
  value = "${aws_cognito_user_pool_domain.hosted_ui.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "issuer_url" {
  description = "JWT iss claim; API Gateway JWT authorizer target"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
}

output "resource_server_identifier" {
  description = "Cognito resource server URI; add to JWT authorizer audience to accept M2M tokens"
  value       = aws_cognito_resource_server.api.identifier
}

output "e2e_client_id" {
  description = "M2M app client ID for E2E tests"
  value       = aws_cognito_user_pool_client.e2e.id
}

output "e2e_client_secret" {
  description = "M2M app client secret for E2E tests"
  value       = aws_cognito_user_pool_client.e2e.client_secret
  sensitive   = true
}

output "token_endpoint" {
  description = "Cognito OAuth2 token endpoint for client credentials flow"
  value       = "https://${aws_cognito_user_pool_domain.hosted_ui.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}
