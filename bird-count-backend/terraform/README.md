# Bird Count Backend - Terraform Infrastructure

This Terraform configuration creates a simple web application hosting infrastructure using AWS S3 and CloudFront.

## Architecture

- **S3 Bucket**: Private bucket to store HTML files and web assets
- **CloudFront**: CDN distribution for fast, secure content delivery
- **OAC (Origin Access Control)**: Secure access from CloudFront to S3

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5 installed

## Deployment

1. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init
   ```

2. **Plan deployment for development:**
   ```bash
   terraform plan -var-file=environments/dev.tfvars
   ```

3. **Deploy to development:**
   ```bash
   terraform apply -var-file=environments/dev.tfvars
   ```

4. **Deploy to production:**
   ```bash
   terraform apply -var-file=environments/prod.tfvars
   ```

## Uploading Web Content

After deployment, upload your HTML files to the S3 bucket:

```bash
# Get the bucket name
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Upload files
aws s3 sync ./web-content s3://$BUCKET_NAME/

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
```

## Outputs

- `website_url`: The CloudFront URL for your web application
- `s3_bucket_name`: The S3 bucket name for uploading content
- `cloudfront_distribution_id`: CloudFront distribution ID for cache invalidation

## Directory Structure

```
terraform/
├── main.tf                 # Main configuration
├── variables.tf            # Variable definitions
├── outputs.tf              # Output values
├── backend.tf              # Remote state configuration
├── environments/           # Environment-specific configs
│   ├── dev.tfvars
│   └── prod.tfvars
└── modules/
    └── storage/            # S3 + CloudFront module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```