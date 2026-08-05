variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_dist_dir" {
  description = "Directory containing the built index.mjs bundle"
  type        = string
}

variable "table_name" {
  type = string
}

variable "table_policy_json" {
  description = "IAM policy document granting the Lambda access to the table"
  type        = string
}

variable "user_pool_id" {
  description = "Cognito user pool ID (used by the Lambda authorizer to build the JWKS URL)"
  type        = string
}

variable "user_audiences" {
  description = "Cognito app client IDs for user tokens (iOS + web); M2M tokens are validated by scope instead"
  type        = list(string)
}

variable "m2m_scope" {
  description = "Required OAuth2 scope for M2M (client_credentials) tokens, e.g. resource_server_id/sync"
  type        = string
}

variable "cors_allow_origins" {
  description = "Origins allowed to call the API from a browser"
  type        = list(string)
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications; empty disables the SNS topic"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Private subnet IDs for Lambda VPC placement"
  type        = list(string)
}

variable "lambda_sg_id" {
  description = "Security group ID shared by all Lambda functions"
  type        = string
}

variable "valkey_endpoint" {
  description = "ElastiCache Serverless Valkey endpoint (host:port) passed as VALKEY_ENDPOINT"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
