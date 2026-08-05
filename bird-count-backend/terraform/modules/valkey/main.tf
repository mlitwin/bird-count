# ElastiCache Serverless (Valkey) — sequence counter for observationNumber.
# maxmemory-policy is noeviction by default for Serverless; verified by the plan.

resource "aws_security_group" "valkey" {
  name        = "${var.project_name}-${var.environment}-valkey"
  description = "ElastiCache Serverless Valkey: inbound 6379 from Lambda only"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_lambda" {
  security_group_id            = aws_security_group.valkey.id
  description                  = "Valkey from Lambda SG"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = var.lambda_sg_id
}

# Add outbound Valkey rule to the Lambda SG here to avoid circular module dependency:
# vpc module creates the Lambda SG, valkey module references it — one-way only.
resource "aws_vpc_security_group_egress_rule" "lambda_to_valkey" {
  security_group_id            = var.lambda_sg_id
  description                  = "Valkey to ElastiCache Serverless"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.valkey.id
}

resource "aws_elasticache_serverless_cache" "valkey" {
  engine = "valkey"
  name   = "${var.project_name}-${var.environment}-seq"

  cache_usage_limits {
    data_storage {
      maximum = 1
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.valkey.id]

  tags = var.tags
}
