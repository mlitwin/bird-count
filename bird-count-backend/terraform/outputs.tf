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