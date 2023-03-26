resource "aws_dynamodb_table" "observations_table" {
  name         = "birdcount-observations-dev"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "group"
    type = "S"
  }

  attribute {
    name = "ksuid"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  hash_key  = "group"
  range_key = "ksuid"

  local_secondary_index {
    name = "user_created_guid"
    projection_type = "KEYS_ONLY"
    range_key = "id"
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