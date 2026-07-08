SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WEB_DIR := $(ROOT)/bird-count-web
TF_DIR := $(ROOT)/bird-count-backend/terraform

.PHONY: help deploy

TYPE ?=
BUMP_TYPE := $(if $(strip $(TYPE)),$(TYPE),$(if $(strip $(type)),$(type),patch))

help:
	@echo "Targets:"
	@echo "  deploy TYPE=patch|minor|major  Create and push the next vX.Y.Z tag from origin"

deploy:
	@set -euo pipefail; \
	bump_type="$(BUMP_TYPE)"; \
	case "$$bump_type" in \
	  patch|minor|major) ;; \
	  *) echo "Error: invalid TYPE '$$bump_type' (use patch, minor, or major)" >&2; exit 1 ;; \
	esac; \
	if ! git -C "$(ROOT)" diff --quiet || ! git -C "$(ROOT)" diff --cached --quiet; then \
	  echo "Error: uncommitted changes found" >&2; \
	  exit 1; \
	fi; \
	git -C "$(ROOT)" fetch --tags origin >/dev/null; \
	current_tag="$$(git -C "$(ROOT)" ls-remote --tags --refs origin 'v*' | awk '{print $$2}' | sed 's#refs/tags/##' | sort -V | tail -1)"; \
	current_tag="$${current_tag:-v0.0.0}"; \
	version="$${current_tag#v}"; \
	IFS=. read -r major minor patch <<< "$$version"; \
	case "$$bump_type" in \
	  patch) patch=$$((patch + 1)) ;; \
	  minor) minor=$$((minor + 1)); patch=0 ;; \
	  major) major=$$((major + 1)); minor=0; patch=0 ;; \
	esac; \
	next_tag="v$${major}.$${minor}.$${patch}"; \
	if git -C "$(ROOT)" ls-remote --tags --refs origin "$$next_tag" | grep -q .; then \
	  echo "Error: $$next_tag already exists on origin" >&2; \
	  exit 1; \
	fi; \
	if git -C "$(ROOT)" rev-parse -q --verify "$$next_tag" >/dev/null; then \
	  echo "Error: $$next_tag already exists locally" >&2; \
	  exit 1; \
	fi; \
	node "$(WEB_DIR)/scripts/make-taxonomy.mjs"; \
	cd "$(TF_DIR)" && terraform output -json | node "$(WEB_DIR)/scripts/make-config.mjs"; \
	git -C "$(ROOT)" tag -a "$$next_tag" -m "Release $$next_tag"; \
	git -C "$(ROOT)" push origin "$$next_tag"; \
	echo "Created and pushed $$next_tag from $$current_tag"
