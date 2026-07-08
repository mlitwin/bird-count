SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WEB_DIR := $(ROOT)/bird-count-web
TF_DIR  := $(ROOT)/bird-count-backend/terraform

.PHONY: help deploy

TYPE ?= patch

help:
	@echo "Targets:"
	@echo "  deploy [TYPE=patch|minor|major]  Tag and push the next semver release (default: patch)"

deploy:
	@if ! git -C "$(ROOT)" diff --quiet || ! git -C "$(ROOT)" diff --cached --quiet; then \
	  echo "Error: uncommitted changes found" >&2; exit 1; \
	fi
	$(eval NEXT_TAG := $(shell "$(ROOT)/scripts/next-version.sh" "$(TYPE)"))
	@echo "Tagging $(NEXT_TAG)…"
	git -C "$(ROOT)" tag -a "$(NEXT_TAG)" -m "Release $(NEXT_TAG)"
	git -C "$(ROOT)" push origin "$(NEXT_TAG)"
	@echo "✅ Created and pushed $(NEXT_TAG)"
