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

variable "issuer_url" {
  description = "Cognito user pool issuer URL for the JWT authorizer"
  type        = string
}

variable "jwt_audience" {
  description = "Cognito app client ids accepted by the JWT authorizer"
  type        = list(string)
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

variable "tags" {
  type    = map(string)
  default = {}
}
