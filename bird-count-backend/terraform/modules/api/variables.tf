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

variable "seq_table_name" {
  description = "DynamoDB table holding the observationNumber counter, passed as SEQ_TABLE_NAME"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
