data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda-attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.observations_writepolicy.arn
}

data "aws_iam_policy_document" "observations_s3_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::birdcount-api-storage/*",
    ]

  }
}

resource "aws_iam_role" "iam_for_lambda_authorizer" {
  name               = "iam_for_lambda_authorizer"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "reads3policy" {
  name   = "${local.app_name}-${local.region}-observations-S3-Read-Policy"
  policy = "${data.aws_iam_policy_document.observations_s3_policy.json}"
}


resource "aws_iam_role_policy_attachment" "lambda_s3_attach" {
  role       = aws_iam_role.iam_for_lambda_authorizer.name
  policy_arn = aws_iam_policy.reads3policy.arn
}


resource "aws_lambda_function" "observations_lambda" {
  filename      = "${path.module}/lambda/dist/index.zip"
  function_name = "birdcount_api"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"

  source_code_hash = filebase64sha256("${path.module}/lambda/dist/index.zip")

  runtime = "nodejs16.x"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.observations_table.name
    }
  }
}

resource "aws_lambda_function" "observations_lambda_authorizer" {
  filename      = "${path.module}/lambda_authorizer/dist/index.zip"
  function_name = "birdcount_api_authorizer"
  role          = aws_iam_role.iam_for_lambda_authorizer.arn
  handler       = "index.handler"

  source_code_hash = filebase64sha256("${path.module}/lambda_authorizer/dist/index.zip")

  runtime = "nodejs16.x"
}


