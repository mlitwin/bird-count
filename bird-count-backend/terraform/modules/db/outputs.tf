output "table_name" {
  value = aws_dynamodb_table.data.name
}

output "table_arn" {
  value = aws_dynamodb_table.data.arn
}

output "seq_table_name" {
  value = aws_dynamodb_table.seq.name
}

output "changes_index_name" {
  value = "changes"
}

output "readwrite_policy_json" {
  description = "IAM policy document granting read/write on the data table, its indexes, and the seq table"
  value       = data.aws_iam_policy_document.readwrite.json
}
