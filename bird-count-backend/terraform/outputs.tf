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