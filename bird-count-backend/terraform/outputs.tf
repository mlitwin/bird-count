output "website_url" {
  description = "CloudFront distribution URL for the web application"
  value       = "https://${module.storage.cloudfront_domain_name}"
}

output "s3_bucket_name" {
  description = "S3 bucket name for web assets"
  value       = module.storage.s3_bucket_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.storage.cloudfront_distribution_id
}

output "user_pool_id" {
  value = module.auth.user_pool_id
}

output "client_id" {
  value = module.auth.client_id
}

output "web_client_id" {
  value = module.auth.web_client_id
}

output "hosted_ui_domain" {
  value = module.auth.hosted_ui_domain
}

output "issuer_url" {
  value = module.auth.issuer_url
}

output "api_url" {
  value = module.api.api_url
}

output "table_name" {
  value = module.db.table_name
}

output "e2e_resource_server" {
  description = "Cognito resource server identifier (scope prefix) for E2E tests"
  value       = module.auth.resource_server_identifier
}

output "e2e_client_id" {
  description = "M2M client ID for E2E tests"
  value       = module.auth.e2e_client_id
}

output "e2e_client_secret" {
  description = "M2M client secret for E2E tests"
  value       = module.auth.e2e_client_secret
  sensitive   = true
}

output "token_endpoint" {
  description = "Cognito token endpoint for client credentials flow"
  value       = module.auth.token_endpoint
}