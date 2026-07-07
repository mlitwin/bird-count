# Remote state: S3 with native lockfile locking (Terraform >= 1.10).
# Bucket/key/region come from environments/<env>.backend.hcl via
# `make init ENV=<env>` (terraform init -backend-config=...).
terraform {
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
