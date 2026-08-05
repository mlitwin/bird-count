# VPC for Lambda + ElastiCache placement.
# Two private subnets (required by ElastiCache Serverless, which needs ≥2 AZs).
# No public subnets or NAT gateway — internet access is via VPC endpoints only:
#   DynamoDB  → Gateway endpoint (free)
#   CloudWatch Logs → Interface endpoint (required for Lambda logs from private subnet)

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.project_name}-${var.environment}" })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(var.tags, { Name = "${var.project_name}-${var.environment}-private-${count.index + 1}" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = var.tags
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group shared by all Lambda functions (API + seq-maintenance).
# Outbound 443 rule covers the CloudWatch Logs interface endpoint.
# The Valkey module adds an outbound 6379 rule to this SG via a separate resource
# so neither module circularly depends on the other.
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.environment}-lambda"
  description = "Lambda outbound: HTTPS to VPC endpoints, Valkey added by valkey module"
  vpc_id      = aws_vpc.main.id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to VPC interface endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Security group for VPC interface endpoints.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpc-endpoints"
  description = "Interface endpoint inbound HTTPS from Lambda"
  vpc_id      = aws_vpc.main.id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS from Lambda SG"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}

# DynamoDB Gateway endpoint — free, no SG needed, routes traffic within AWS network.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = var.tags
}

# CloudWatch Logs Interface endpoint — Lambda in a private subnet cannot reach
# the public Logs endpoint without this. Private DNS resolves logs.*.amazonaws.com
# to the endpoint ENIs inside the VPC.
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = var.tags
}
