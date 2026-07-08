#!/usr/bin/env bash
# next-version.sh — compute and echo the next semver tag from origin.
#
# Usage: next-version.sh [patch|minor|major]   (default: patch)
# Exits non-zero on invalid bump type or if the computed tag already exists.
#
# Output: the next tag string, e.g. "v0.1.4"

set -euo pipefail

BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  patch|minor|major) ;;
  *)
    echo "Error: invalid bump type '$BUMP_TYPE' (use patch, minor, or major)" >&2
    exit 1
    ;;
esac

# Fetch latest tags from origin so we always work from the remote state
git fetch --tags origin --quiet

current_tag="$(
  git ls-remote --tags --refs origin 'v*' \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | sort -V \
    | tail -1
)"
current_tag="${current_tag:-v0.0.0}"
version="${current_tag#v}"

IFS=. read -r major minor patch <<< "$version"

case "$BUMP_TYPE" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac

next_tag="v${major}.${minor}.${patch}"

if git ls-remote --tags --refs origin "$next_tag" | grep -q .; then
  echo "Error: $next_tag already exists on origin" >&2
  exit 1
fi

if git rev-parse -q --verify "$next_tag" > /dev/null 2>&1; then
  echo "Error: $next_tag already exists locally" >&2
  exit 1
fi

echo "$next_tag"
