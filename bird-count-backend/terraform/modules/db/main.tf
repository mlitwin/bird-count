# DynamoDB single-table store for the observation ledger.
# PK pk: scope ("shared" in v1; later "trip#<uuid>" / "user#<sub>")
# SK sk: "obs#<uuid>"
# GSI "changes" (pk, serverUpdatedAt): "changes since cursor" per scope.
# Append-only ledger: no TTL, nothing is ever deleted.

resource "aws_dynamodb_table" "data" {
  name         = "${var.project_name}-data-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "serverUpdatedAt"
    type = "N"
  }

  global_secondary_index {
    name            = "changes"
    hash_key        = "pk"
    range_key       = "serverUpdatedAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "prod"

  tags = var.tags
}

data "aws_iam_policy_document" "readwrite" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.data.arn,
      "${aws_dynamodb_table.data.arn}/index/*",
    ]
  }
}
