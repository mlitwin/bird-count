.PHONY: help whoami aws tf init plan apply output api-test api-build web-config web-test web-deploy

# AWS credentials come from 1Password via `op run` (see aws.env).
ENV ?= dev
TF_DIR = terraform
TFVARS = environments/$(ENV).tfvars
OP_RUN = op run --env-file aws.env --
# terraform needs the Sign in with Apple secrets too (TF_VAR_apple_*)
OP_RUN_TF = op run --env-file ../aws.env --env-file ../siwa.env --

.DEFAULT_GOAL := help

help:
	@echo "Targets (ENV=dev|prod, default dev):"
	@echo "  whoami      Verify AWS credentials (sts get-caller-identity)"
	@echo "  aws         Run an aws CLI command: make aws CMD='s3 ls'"
	@echo "  tf          Run a terraform command: make tf CMD='validate'"
	@echo "  init        terraform init for ENV"
	@echo "  plan        terraform plan for ENV"
	@echo "  apply       terraform apply for ENV"
	@echo "  output      terraform output"
	@echo "  web-config  Generate bird-count-web/js/config.js from terraform output"
	@echo "              Set LOCAL=1 for redirectURI=localhost:8788 (local dev)"
	@echo "  web-test    Run bird-count-web unit tests"
	@echo "  web-deploy  Build + sync web viewer to S3 + invalidate CloudFront"
	@echo "              Set LOCAL=1 for redirectURI=localhost:8788"

whoami:
	$(OP_RUN) aws sts get-caller-identity

aws:
	$(OP_RUN) aws $(CMD)

tf:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform $(CMD)

init:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform init -backend-config=environments/$(ENV).backend.hcl

plan:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform plan -var-file=$(TFVARS)

apply:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform apply -var-file=$(TFVARS)

output:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform output

api-test:
	cd api && npm test

api-build:
	cd api && npm run generate && npm run build

# Generate bird-count-web/js/config.js from the current terraform state.
# LOCAL=1 sets redirectURI to http://localhost:8788/ for local dev.
web-config:
	node ../bird-count-web/scripts/make-taxonomy.mjs
	cd $(TF_DIR) && $(OP_RUN_TF) terraform output -json $(if $(LOCAL),| node ../../bird-count-web/scripts/make-config.mjs --local,| node ../../bird-count-web/scripts/make-config.mjs)

web-test:
	cd ../bird-count-web && npm test

WEB_DIR = ../bird-count-web

# Deploy web viewer: generate assets, sync to S3, invalidate CloudFront.
# LOCAL=1: set redirectURI to localhost:8788 (omit for deployed CloudFront URL).
web-deploy: web-test
	node $(WEB_DIR)/scripts/make-taxonomy.mjs
	cd $(TF_DIR) && $(OP_RUN_TF) terraform output -json | \
	  node ../../bird-count-web/scripts/make-config.mjs $(if $(LOCAL),--local,)
	$(eval _BUCKET := $(shell cd $(TF_DIR) && $(OP_RUN_TF) terraform output -raw s3_bucket_name))
	$(eval _CF_ID  := $(shell cd $(TF_DIR) && $(OP_RUN_TF) terraform output -raw cloudfront_distribution_id))
	$(OP_RUN) aws s3 sync $(WEB_DIR)/ s3://$(_BUCKET)/ \
	  --exclude "scripts/*" --exclude "test/*" --exclude "package.json" \
	  --exclude ".gitignore" --delete
	$(OP_RUN) aws cloudfront create-invalidation \
	  --distribution-id $(_CF_ID) --paths "/*"

# One-time, account-global: GitHub OIDC provider + deploy role for CI
bootstrap:
	cd $(TF_DIR)/bootstrap && op run --env-file ../../aws.env -- terraform init && op run --env-file ../../aws.env -- terraform apply

apply: api-build
