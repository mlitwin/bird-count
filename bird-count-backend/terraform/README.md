# Terraform — Bird Count Backend

Infrastructure for the sync backend. Overview: [../README.md](../README.md).
Run all commands through the parent `Makefile` (credentials come from
1Password via `op run` — see `../aws.env`).

## Stacks

Per-environment stack (state key `<env>/terraform.tfstate`):

| Module | Resources |
|---|---|
| `auth` | Cognito user pool + SignInWithApple IdP + PKCE app client + hosted UI domain `birdcount-<env>` |
| `db` | DynamoDB `birdcount-data-<env>` (pk/sk + `changes` GSI, PITR; deletion protection in prod) |
| `api` | Lambda (`birdcount-<env>-api`, from `../api/dist`) + HTTP API + JWT authorizer + routes + throttling + CloudWatch alarms (optional SNS email via `alarm_email`) |
| `storage` | S3 + CloudFront static hosting for a future web front-end |

Account-global stack (`bootstrap/`, state key `bootstrap/terraform.tfstate`,
applied once via `make bootstrap`): GitHub OIDC provider + the
`birdcount-github-deploy` role that CI assumes (trusts only `main` and `v*`
tag refs of `mlitwin/bird-count`).

## Usage

```sh
make init ENV=dev      # terraform init -backend-config=environments/dev.backend.hcl
make plan ENV=dev
make apply ENV=dev     # builds the Lambda bundle first
```

Requirements: Terraform >= 1.10 (S3 native lockfile locking). The provider
lock file is committed; state lives in `s3://birdcount-tfstate-477808199271`.

`environments/<env>.tfvars` hold only non-secrets (env name, region,
alarm email). Sign in with Apple values arrive as `TF_VAR_apple_*` from
`../siwa.env` (locally) or GitHub Actions secrets (CI).

Normally you don't apply by hand: CI deploys `main` → dev and `vX.Y.Z`
tags → prod (`.github/workflows/deploy.yml`).
