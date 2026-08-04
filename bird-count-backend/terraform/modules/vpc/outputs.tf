output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  description = "SG shared by all Lambda functions; the valkey module adds outbound 6379 to it"
  value       = aws_security_group.lambda.id
}
