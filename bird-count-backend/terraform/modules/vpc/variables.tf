variable "project_name" { type = string }
variable "environment" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

# Whether to create the CloudWatch Logs interface VPC endpoint.
# Set to true for environments (e.g., prod) where Lambdas are in the VPC
# and need private access to CloudWatch Logs. Defaults to false to avoid
# per-AZ interface endpoint charges in dev/local environments.
variable "create_logs_endpoint" {
  type    = bool
  default = false
}
