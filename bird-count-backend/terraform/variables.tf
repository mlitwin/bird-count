variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Sign in with Apple — values come from 1Password via `op run --env-file siwa.env`
# (TF_VAR_apple_*); see docs/apple-siwa-setup.md.
variable "apple_team_id" {
  type = string
}

variable "apple_services_id" {
  type = string
}

variable "apple_key_id" {
  type = string
}

variable "apple_private_key" {
  type      = string
  sensitive = true
}

variable "callback_urls" {
  description = "OAuth callback/logout URLs for the app client"
  type        = list(string)
  default     = ["birdcount://auth/callback", "http://localhost:8400/callback"]
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications; empty disables notifications"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Attach a WAF (per-IP rate limit + AWS common rules) to the CloudFront distribution (~$6-8/mo)"
  type        = bool
  default     = false
}
