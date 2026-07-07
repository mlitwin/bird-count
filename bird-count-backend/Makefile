.PHONY: help whoami aws tf init plan apply output

# AWS credentials come from 1Password via `op run` (see aws.env).
ENV ?= dev
TF_DIR = terraform
TFVARS = environments/$(ENV).tfvars
OP_RUN = op run --env-file aws.env --

.DEFAULT_GOAL := help

help:
	@echo "Targets (ENV=dev|prod, default dev):"
	@echo "  whoami   Verify AWS credentials (sts get-caller-identity)"
	@echo "  aws      Run an aws CLI command: make aws CMD='s3 ls'"
	@echo "  tf       Run a terraform command: make tf CMD='validate'"
	@echo "  init     terraform init for ENV"
	@echo "  plan     terraform plan for ENV"
	@echo "  apply    terraform apply for ENV"
	@echo "  output   terraform output"

whoami:
	$(OP_RUN) aws sts get-caller-identity

aws:
	$(OP_RUN) aws $(CMD)

tf:
	cd $(TF_DIR) && op run --env-file ../aws.env -- terraform $(CMD)

init:
	cd $(TF_DIR) && op run --env-file ../aws.env -- terraform init -backend-config=environments/$(ENV).backend.hcl

plan:
	cd $(TF_DIR) && op run --env-file ../aws.env -- terraform plan -var-file=$(TFVARS)

apply:
	cd $(TF_DIR) && op run --env-file ../aws.env -- terraform apply -var-file=$(TFVARS)

output:
	cd $(TF_DIR) && op run --env-file ../aws.env -- terraform output
