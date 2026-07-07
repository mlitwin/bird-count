# AI Agent Instructions - Bird Count Backend

## Project Overview
Backend infrastructure for the Bird Count iOS app, deployed on AWS using Terraform. This project manages cloud resources for a mobile application that likely handles bird observation data collection and storage.

## Terraform Best Practices

### Project Structure
- Keep Terraform files organized in logical modules (e.g., `modules/api/`, `modules/database/`, `modules/storage/`)
- Use `main.tf`, `variables.tf`, `outputs.tf` pattern for each module
- Store environment-specific configurations in separate `.tfvars` files
- Use `terraform/` or `infra/` as root directory for infrastructure code

### AWS Resource Conventions
- Use consistent naming: `birdcount-{environment}-{service}-{resource}`
- Tag all resources with: `Project = "bird-count"`, `Environment = "{env}"`, `ManagedBy = "terraform"`
- Prefer AWS managed services for backend APIs (API Gateway, Lambda, RDS/DynamoDB)

### State Management
- Always use remote state (S3 backend with DynamoDB locking)
- Never commit `.tfstate` files or `.terraform/` directories
- Use workspaces for environment separation: `dev`, `staging`, `prod`

### Security Practices
- Store secrets in AWS Secrets Manager or Parameter Store, not in Terraform files
- Use least-privilege IAM policies with specific resource ARNs
- Enable CloudTrail and VPC Flow Logs for auditing
- Use Security Groups with specific port/protocol restrictions

### Mobile Backend Architecture Considerations
- API Gateway for REST endpoints with proper CORS configuration
- Lambda functions for business logic (consider cold starts for mobile responsiveness)
- DynamoDB for scalable NoSQL data storage (good for user-generated content like bird observations)
- S3 for media storage (bird photos/audio) with CloudFront distribution
- Cognito for user authentication and authorization

### Development Workflow
```bash
# Initialize and plan changes
terraform init
terraform plan -var-file=environments/dev.tfvars

# Apply with approval
terraform apply -var-file=environments/dev.tfvars

# Validate configurations
terraform validate
terraform fmt -check
```

### Common Commands
- `terraform state list` - View all managed resources
- `terraform import` - Import existing AWS resources
- `terraform destroy` - Clean up development resources
- `terraform output` - Display output values (API endpoints, etc.)

### Key Files to Monitor
- `provider.tf` - AWS provider and version constraints
- `backend.tf` - Remote state configuration  
- `terraform.tfvars.example` - Template for environment variables
- `.gitignore` - Ensure secrets and state files are excluded

## Mobile-Specific Considerations
- Configure API Gateway with proper throttling for mobile clients
- Set up CloudWatch alarms for API latency and error rates
- Use SES or SNS for push notifications about bird activity
- Consider data sync patterns for offline-first mobile experience
- Implement proper CORS policies for web dashboard access

When making changes, always run `terraform plan` first and consider the impact on the mobile application's functionality.