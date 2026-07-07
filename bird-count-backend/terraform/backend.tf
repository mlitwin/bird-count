# Remote state configuration
terraform {
  backend "s3" {
    # Configure these values in terraform init command or backend config file
    # bucket         = "birdcount-terraform-state"
    # key            = "terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "birdcount-terraform-locks"
    # encrypt        = true
  }
}