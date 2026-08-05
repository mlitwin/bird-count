output "endpoint_address" {
  description = "ElastiCache Serverless endpoint (host:port); pass as VALKEY_ENDPOINT to Lambdas"
  value       = "${aws_elasticache_serverless_cache.valkey.endpoint[0].address}:6379"
}

output "security_group_id" {
  value = aws_security_group.valkey.id
}
