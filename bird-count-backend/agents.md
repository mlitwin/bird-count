# Agent Instructions — Bird Count Backend

Guidance for AI agents working in `bird-count-backend/`. Human-oriented
overview: [README.md](README.md). Sync protocol details:
[../docs/sync-architecture.md](../docs/sync-architecture.md).

## Ground rules

- **AWS credentials come from 1Password via `op run`** — there is no
  configured AWS profile on this machine. Never suggest `aws configure` or
  plaintext credentials. Run everything through the Makefile:
  `make whoami`, `make aws CMD='…'`, `make tf CMD='…'`,
  `make init/plan/apply ENV=dev|prod`.
- Sign in with Apple secrets flow as `TF_VAR_apple_*` from `siwa.env`
  (1Password `op://` references). The `.p8` key must never land in the repo,
  shell history, or logs.
- The wire format is owned by [`../bird-count-schema/`](../bird-count-schema/).
  To change it: edit the schemas *and* fixtures there, run `npm run validate`,
  then `npm run generate` in `api/` (regenerates `src/generated/types.ts`,
  which is checked in — CI fails on drift). Never edit `src/generated/` by hand.
  The iOS `SchemaConformanceTests` consume the same fixtures; a schema change
  usually needs a matching iOS change in the same commit.
- The data model is an **append-only ledger**. Do not add delete endpoints,
  tombstones, TTLs, or in-place mutations. The only permitted overwrite is
  the `updatedAt`-guarded LWW put (location backfill).
- Pull queries must stay **strictly-after-cursor** — a server-side overlap
  window breaks pagination (see sync-architecture.md). The overlap is the
  client's job.

## Layout

```
api/            TypeScript Lambda (esbuild bundle; nodejs20.x)
  src/handler   route dispatch + auth sub extraction
  src/validate  ajv against ../../bird-count-schema/schemas (bundled)
  src/sync      push (conditional puts) + pull (GSI delta)
  src/dynamo    DocumentClient wrappers
  test/         vitest; sync tests run DynamoDB Local in docker
terraform/
  modules/{storage,auth,db,api}
  environments/ <env>.tfvars (tracked; never secrets) + <env>.backend.hcl
  bootstrap/    GitHub OIDC provider + deploy role + account budget
                (separate state, make bootstrap)
```

This Makefile also builds and deploys the static web viewer in
[`../bird-count-web/`](../bird-count-web/) (S3 + CloudFront from the storage
module; second Cognito app client `web` with browser PKCE). Its
`js/config.js` and `taxonomy.json` are generated, gitignored artifacts —
regenerate with `make web-config`, never edit by hand.

## Workflow

```sh
make api-test          # vitest (docker must be running)
make api-build         # regen types + esbuild bundle (required before apply)
make plan ENV=dev
make apply ENV=dev     # runs api-build first
make web-test          # web viewer unit tests (node --test)
make web-config ENV=dev LOCAL=1   # config.js for local dev (localhost:8788)
make web-deploy ENV=dev           # build + S3 sync + CloudFront invalidation
```

- Terraform ≥ 1.10 (S3 `use_lockfile`); provider lock file is committed.
- Remote state: s3://birdcount-tfstate-477808199271, key `<env>/terraform.tfstate`.
- CI (`.github/workflows/deploy.yml`) deploys `main` → dev and `vX.Y.Z` tags
  → prod via the OIDC role `birdcount-github-deploy`. Prefer letting CI
  deploy; local applies are for development iteration on dev.
- Cognito's Apple IdP has `ignore_changes = [provider_details]` (AWS
  backfills read-only keys). To rotate the Apple key:
  `terraform apply -replace=module.auth.aws_cognito_identity_provider.apple`.

## Gotchas

- The API Gateway JWT authorizer runs before the Lambda: handler code can
  assume `sub` exists on protected routes, and unauthenticated tests belong
  at the HTTP level, not the handler level.
- `serverUpdatedAt` stamps must remain unique within a push batch
  (`max(now, prev+1)`) — pagination correctness depends on it.
- vitest sync tests start their own DynamoDB Local container on port 8123
  and stop it afterward; failures that mention connection refused usually
  mean docker isn't running.
