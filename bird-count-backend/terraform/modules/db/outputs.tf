output "table_name" {
  value = aws_dynamodb_table.data.name
}

output "table_arn" {
  value = aws_dynamodb_table.data.arn
}

output "changes_index_name" {
  value = "changes"
}

output "readwrite_policy_json" {
  description = "IAM policy document granting read/write on the table and its indexes"
  value       = data.aws_iam_policy_document.readwrite.json
}
