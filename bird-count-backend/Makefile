.PHONY: help whoami aws tf init plan apply output validate api-test api-build e2e e2e-init web-config web-test web-deploy bootstrap

# AWS credentials come from 1Password via `op run` (see aws.env).
ENV ?= dev
TF_DIR  = terraform
TFVARS  = environments/$(ENV).tfvars
BACKEND = environments/$(ENV).backend.hcl
OP_RUN    = op run --env-file aws.env --
# terraform needs the Sign in with Apple secrets too (TF_VAR_apple_*)
OP_RUN_TF = op run --env-file ../aws.env --env-file ../siwa.env --

# Always init against the correct ENV backend before any state-reading command.
# `-upgrade=false -reconfigure` is fast (no module downloads) and switches the
# active backend without prompting.
TF_INIT = $(OP_RUN_TF) terraform init -reconfigure -upgrade=false \
            -backend-config=$(BACKEND) > /dev/null

.DEFAULT_GOAL := help

help:
	@echo "Targets (ENV=dev|prod, default dev):"
	@echo "  whoami      Verify AWS credentials (sts get-caller-identity)"
	@echo "  aws         Run an aws CLI command: make aws CMD='s3 ls'"
	@echo "  tf          Run a terraform command: make tf CMD='validate'"
	@echo "  init        terraform init for ENV"
	@echo "  plan        terraform plan for ENV"
	@echo "  apply       terraform apply for ENV"
	@echo "  output      terraform output for ENV"
	@echo "  validate    terraform validate (offline, no creds needed)"
	@echo "  web-config  Generate bird-count-web/js/config.js from terraform output"
	@echo "              Set LOCAL=1 for redirectURI=localhost:8788 (local dev)"
	@echo "  web-test    Run bird-count-web unit tests"
	@echo "  web-deploy  Build + sync web viewer to S3 + invalidate CloudFront"
	@echo "              Set LOCAL=1 for redirectURI=localhost:8788"
	@echo "  e2e-init    One-time: fetch M2M credentials from Terraform and store in 1Password"
	@echo "  e2e         Run E2E tests against deployed API (ENV=dev|prod)"
	@echo "  bootstrap   One-time: GitHub OIDC provider + deploy role + account budget"

whoami:
	$(OP_RUN) aws sts get-caller-identity

aws:
	$(OP_RUN) aws $(CMD)

tf:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform $(CMD)

init:
	cd $(TF_DIR) && $(OP_RUN_TF) terraform init -backend-config=$(BACKEND)

plan:
	cd $(TF_DIR) && $(TF_INIT) && $(OP_RUN_TF) terraform plan -var-file=$(TFVARS)

apply: api-build
	cd $(TF_DIR) && $(TF_INIT) && $(OP_RUN_TF) terraform apply -var-file=$(TFVARS)

output:
	cd $(TF_DIR) && $(TF_INIT) && $(OP_RUN_TF) terraform output

# validate is offline: no AWS creds, no backend/state — no op run needed.
# Requires an existing .terraform (any ENV's init will do).
validate:
	cd $(TF_DIR) && terraform validate

api-test:
	cd api && npm test

api-build:
	cd api && npm run generate && npm run build

# One-time setup: pull M2M credentials from Terraform state and store them in
# 1Password so subsequent `make e2e` runs need no AWS access.
# Re-run only if you terraform-destroy and recreate the Cognito resources.
e2e-init:
	@echo "Fetching e2e credentials from Terraform (ENV=$(ENV))..."
	@cd $(TF_DIR) && $(TF_INIT) > /dev/null && \
	  TF_OUT=$$($(OP_RUN_TF) terraform output -json) && \
	  API_URL=$$(echo "$$TF_OUT"        | jq -r '.api_url.value') && \
	  TOKEN_EP=$$(echo "$$TF_OUT"       | jq -r '.token_endpoint.value') && \
	  CLIENT_ID=$$(echo "$$TF_OUT"      | jq -r '.e2e_client_id.value') && \
	  CLIENT_SECRET=$$(echo "$$TF_OUT"  | jq -r '.e2e_client_secret.value') && \
	  RS=$$(echo "$$TF_OUT"             | jq -r '.e2e_resource_server.value') && \
	  ITEM="bird-count-e2e-$(ENV)" && \
	  FIELDS="api_url[text]=$$API_URL token_endpoint[text]=$$TOKEN_EP client_id[text]=$$CLIENT_ID client_secret[password]=$$CLIENT_SECRET resource_server[text]=$$RS" && \
	  (op item get "$$ITEM" --vault Private > /dev/null 2>&1 \
	    && op item edit "$$ITEM" --vault Private $$FIELDS \
	    || op item create --category Login --title "$$ITEM" --vault Private $$FIELDS) && \
	  echo "Done. Credentials stored in 1Password item '$$ITEM'."

# Run E2E tests against the deployed API.
# Credentials are read from 1Password via e2e-$(ENV).env — run `make e2e-init` first.
e2e:
	op run --env-file e2e-$(ENV).env -- \
	  api/node_modules/.bin/tsx api/test/e2e/run.ts

# Generate bird-count-web/js/config.js from the current terraform state.
# LOCAL=1 sets redirectURI to http://localhost:8788/ for local dev.
web-config:
	node ../bird-count-web/scripts/make-taxonomy.mjs
	cd $(TF_DIR) && $(TF_INIT) && $(OP_RUN_TF) terraform output -json \
	  $(if $(LOCAL),| node ../../bird-count-web/scripts/make-config.mjs --local, \
	                | node ../../bird-count-web/scripts/make-config.mjs)

web-test:
	cd ../bird-count-web && npm test

# Deploy web viewer: generate assets, sync to S3, invalidate CloudFront
# (shared script: ../scripts/web-deploy.sh, also used by CI).
# LOCAL=1: set redirectURI to localhost:8788 (omit for deployed CloudFront URL).
web-deploy: web-test
	cd $(TF_DIR) && $(TF_INIT) && $(OP_RUN_TF) terraform output -json | \
	  op run --env-file ../aws.env -- ../../scripts/web-deploy.sh $(if $(LOCAL),--local,)

# One-time, account-global: GitHub OIDC provider + deploy role for CI
bootstrap:
	cd $(TF_DIR)/bootstrap && op run --env-file ../../aws.env -- terraform init && op run --env-file ../../aws.env -- terraform apply
