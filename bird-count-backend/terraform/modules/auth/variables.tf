variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "apple_team_id" {
  description = "Apple Developer team ID"
  type        = string
}

variable "apple_services_id" {
  description = "Apple Services ID (Cognito's client_id toward Apple)"
  type        = string
}

variable "apple_key_id" {
  description = "Sign in with Apple key ID"
  type        = string
}

variable "apple_private_key" {
  description = "Contents of the Sign in with Apple .p8 key"
  type        = string
  sensitive   = true
}

variable "callback_urls" {
  description = "OAuth callback/logout URLs for the iOS app client"
  type        = list(string)
}

variable "web_callback_urls" {
  description = "OAuth callback/logout URLs for the web viewer client"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
