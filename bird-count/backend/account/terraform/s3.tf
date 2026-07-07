resource "aws_s3_bucket" "tf" {
  bucket = "birdcount-terraform-state"

  tags = {
    Name = "Birdcount Terraform state and related"
  }
}

resource "aws_s3_bucket_versioning" "tf" {
  bucket = aws_s3_bucket.tf.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_acl" "tf" {
  bucket = aws_s3_bucket.tf.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "tf" {
  bucket = aws_s3_bucket.tf.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = false
}
