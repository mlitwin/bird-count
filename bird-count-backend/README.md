# Bird Count Backend

Backend for the bird count ios app.

## Tech

AWS Infrastructure deployed via terraform

## Infrastructure

### Web Application

HTML files are stored in a private S3 bucket, which is the origin for a cloudfront distribution.

## Deployment

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5 installed

### Deploy Infrastructure

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

### Upload Web Content

After deployment, upload your HTML files to the S3 bucket:

```bash
# Get the bucket name and website URL
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
WEBSITE_URL=$(terraform output -raw website_url)

# Upload files
aws s3 sync ./web-content s3://$BUCKET_NAME/

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"

echo "Website available at: $WEBSITE_URL"
```

### Outputs

- `website_url`: The CloudFront URL for your web application
- `s3_bucket_name`: The S3 bucket name for uploading content
- `cloudfront_distribution_id`: CloudFront distribution ID for cache invalidation




#
https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/