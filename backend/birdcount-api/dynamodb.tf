resource "aws_dynamodb_table" "observations_table" {
  name         = "birdcount-observations"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "compilation"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

   attribute {
    name = "timestamp"
    type = "N"
  }

  hash_key  = "compilation"
  range_key = "id"

  local_secondary_index {
    name = "timestamp"
    projection_type = "ALL"
    range_key = "timestamp"
  }

  point_in_time_recovery {
    enabled = true
  }
}


// dynamodb table Read Policy
data "aws_iam_policy_document" "observations_readpolicy" {
  statement {
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:ListTables",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]

    resources = [aws_dynamodb_table.observations_table.arn]

    effect = "Allow"
  }
}

resource "aws_iam_policy" "readpolicy" {
  name   = "${local.app_name}-${local.region}-observations-DynamoDb-Read-Policy"
  policy = "${data.aws_iam_policy_document.observations_readpolicy.json}"
}

// dynamodb table Write Policy
data "aws_iam_policy_document" "observations_writepolicy" {
  statement {
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:ListTables",
      "dynamodb:PutItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
    ]

    resources = [aws_dynamodb_table.observations_table.arn]

    effect = "Allow"
  }
}

resource "aws_iam_policy" "observations_writepolicy" {
  name   = "${local.app_name}-${local.region}-observations-DynamoDb-Write-Policy"
  policy = "${data.aws_iam_policy_document.observations_writepolicy.json}"
}