variable "project_name" { type = string }
variable "environment" { type = string }

variable "vpc_id" {
  description = "VPC to place the ElastiCache cluster in"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs (≥2 AZs required by ElastiCache Serverless)"
  type        = list(string)
}

variable "lambda_sg_id" {
  description = "Lambda security group; the module adds an outbound 6379 rule to it"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
