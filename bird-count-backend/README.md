# Bird Count Backend

Cloud sync backend for the bird-count iOS app: observations sync across
devices and users via an authenticated API. The data model is an append-only
ledger — deletes are negative-count adjustment children, never tombstones.

## Architecture

- **Auth** — Cognito user pool federated with Sign in with Apple; the app
  uses the hosted UI (`ASWebAuthenticationSession` + PKCE, no Amplify).
  One-time Apple portal setup: [docs/apple-siwa-setup.md](docs/apple-siwa-setup.md).
- **API** — API Gateway HTTP API with a Cognito JWT authorizer in front of a
  TypeScript Lambda (`api/`): `POST /v1/sync` (push + pull in one round
  trip), `GET /v1/observations` (delta read), `GET /v1/health`.
  Requests are ajv-validated against the shared schemas in
  [`../bird-count-schema/`](../bird-count-schema/).
- **DB** — one DynamoDB table `birdcount-data-<env>` (PK = scope, SK =
  `obs#<uuid>`), GSI `changes` on `serverUpdatedAt` for cursor deltas.
  Nothing is ever deleted.
- **Storage** — S3 + CloudFront static hosting for a future web front-end.
- **Alarms** — CloudWatch on Lambda errors and API 5xx (email via
  `alarm_email` tfvar, prod only by default).

Cursor contract: server pulls are strictly-after-cursor (pagination always
advances); clients rewind their stored cursor ~5s at sync-session start and
apply idempotently (put-if-absent + last-writer-wins on `updatedAt`).

## Local development

AWS credentials come from 1Password via `op run` — nothing is configured in
`~/.aws`. See the `Makefile`:

```sh
make whoami            # verify credentials
make api-test          # vitest incl. DynamoDB Local (docker)
make api-build         # regen types from schema + esbuild bundle
make plan ENV=dev      # terraform plan
make apply ENV=dev     # build + terraform apply
```

Sign in with Apple secrets flow through `siwa.env` (1Password references)
as `TF_VAR_apple_*`; the `.p8` never touches the repo.

## CI/CD

`.github/workflows/deploy.yml`:

- every push/PR: schema fixtures validate, generated-types drift gate,
  API tests
- push to `main` → deploy **dev**; tag `vX.Y.Z` → deploy **prod**

GitHub authenticates to AWS via OIDC federation (no stored keys, per the
[AWS pattern](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)):
the `birdcount-github-deploy` role trusts only `main` and `v*` tag refs of
`mlitwin/bird-count`. SIWA values are GitHub Actions secrets
(`APPLE_TEAM_ID`, `APPLE_SERVICES_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`),
seeded from 1Password with `op read ... | gh secret set ...`. The OIDC
provider + role live in `terraform/bootstrap/` (account-global, applied once
locally via `make bootstrap`).

Before the first prod tag: add the prod Cognito domain
(`birdcount-prod.auth.us-east-1.amazoncognito.com`) and its
`/oauth2/idpresponse` return URL to the Apple Services ID.

## Terraform layout

```
terraform/
  main.tf                    # wires modules: storage, auth, db, api
  backend.tf                 # S3 remote state (use_lockfile)
  environments/              # <env>.tfvars + <env>.backend.hcl
  bootstrap/                 # GitHub OIDC provider + deploy role (separate state)
  modules/{storage,auth,db,api}/
```
