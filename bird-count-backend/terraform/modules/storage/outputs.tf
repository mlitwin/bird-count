output "s3_bucket_name" {
  description = "Name of the web application S3 bucket"
  value       = aws_s3_bucket.web_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the web application S3 bucket"
  value       = aws_s3_bucket.web_bucket.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.web_distribution.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.web_distribution.id
}