#!/usr/bin/env bash
# Deploy the web viewer: generate taxonomy + config, sync to S3, invalidate CloudFront.
# Shared by `make web-deploy` (bird-count-backend/Makefile) and CI (deploy.yml).
#
# Usage: terraform output -json | scripts/web-deploy.sh [--local]
#   --local  set redirectURI to http://localhost:8788/ (dev serve)
#
# Expects AWS credentials in the environment (op run locally, OIDC in CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/bird-count-web"

TF_JSON="$(cat)"

tf_output() {
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => process.stdout.write(JSON.parse(d)[process.argv[1]].value));
  ' "$1" <<<"$TF_JSON"
}

BUCKET="$(tf_output s3_bucket_name)"
CF_ID="$(tf_output cloudfront_distribution_id)"

node "$WEB/scripts/make-taxonomy.mjs"
node "$WEB/scripts/make-config.mjs" "$@" <<<"$TF_JSON"

aws s3 sync "$WEB/" "s3://$BUCKET/" \
  --exclude "scripts/*" --exclude "test/*" --exclude "package.json" \
  --exclude ".gitignore" --delete
aws cloudfront create-invalidation --distribution-id "$CF_ID" --paths "/*"
