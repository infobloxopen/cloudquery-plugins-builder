# ──────────────────────────────────────────────────────────────────────────────
# Makefile — Developer-facing targets for cloudquery-plugins-builder
#
# Delegates to scripts/ for implementation. Run `make help` for a target list.
# ──────────────────────────────────────────────────────────────────────────────
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

MANIFEST   ?= plugins.yaml
SCHEMA     ?= schemas/plugins-manifest.schema.json
PLUGIN     ?=
PLATFORM   ?=

# ─── Plugin names (derived from manifest) ────────────────────────────────────
PLUGINS := $(shell yq '.plugins[].name' $(MANIFEST) 2>/dev/null)

# ─── Build targets ───────────────────────────────────────────────────────────
.PHONY: build
build: ## Build a single plugin image (PLUGIN=<name>)
	@if [ -z "$(PLUGIN)" ]; then \
		echo "Error: PLUGIN is required. Usage: make build PLUGIN=postgresql"; \
		exit 1; \
	fi
	@./scripts/build.sh $(PLUGIN) $(if $(PLATFORM),--platform $(PLATFORM))

.PHONY: build-all
build-all: ## Build all plugins defined in plugins.yaml
	@./scripts/build-all.sh

# Generate per-plugin build targets: build-postgresql, build-s3, build-file
define PLUGIN_BUILD_TARGET
.PHONY: build-$(1)
build-$(1): ## Build the $(1) plugin image
	@./scripts/build.sh $(1) $$(if $$(PLATFORM),--platform $$(PLATFORM))
endef
$(foreach p,$(PLUGINS),$(eval $(call PLUGIN_BUILD_TARGET,$(p))))

# ─── Test targets ─────────────────────────────────────────────────────────────
.PHONY: smoke-test
smoke-test: ## Run smoke test for a single plugin (PLUGIN=<name>)
	@if [ -z "$(PLUGIN)" ]; then \
		echo "Error: PLUGIN is required. Usage: make smoke-test PLUGIN=postgresql"; \
		exit 1; \
	fi
	@KIND=$$(yq ".plugins[] | select(.name == \"$(PLUGIN)\") | .kind" $(MANIFEST)); \
	VERSION=$$(yq ".plugins[] | select(.name == \"$(PLUGIN)\") | .version" $(MANIFEST)); \
	GIT_SUFFIX=$$(git describe --always --dirty 2>/dev/null || echo "unknown"); \
	IMAGE="ghcr.io/infobloxopen/cq-$${KIND}-$(PLUGIN):$${VERSION}-$${GIT_SUFFIX}"; \
	./scripts/smoke-test.sh "$${IMAGE}" 7777 30

# Generate per-plugin smoke-test targets: smoke-test-postgresql, smoke-test-s3, ...
define PLUGIN_SMOKE_TARGET
.PHONY: smoke-test-$(1)
smoke-test-$(1): ## Smoke test the $(1) plugin image
	@KIND=$$(yq ".plugins[] | select(.name == \"$(1)\") | .kind" $(MANIFEST)); \
	VERSION=$$(yq ".plugins[] | select(.name == \"$(1)\") | .version" $(MANIFEST)); \
	GIT_SUFFIX=$$(git describe --always --dirty 2>/dev/null || echo "unknown"); \
	IMAGE="ghcr.io/infobloxopen/cq-$${KIND}-$(1):$${VERSION}-$${GIT_SUFFIX}"; \
	./scripts/smoke-test.sh "$${IMAGE}" 7777 30
endef
$(foreach p,$(PLUGINS),$(eval $(call PLUGIN_SMOKE_TARGET,$(p))))

# ─── Validation targets ──────────────────────────────────────────────────────
.PHONY: validate
validate: ## Validate plugins.yaml (schema + upstream refs)
	@./scripts/validate-manifest.sh $(MANIFEST)

.PHONY: validate-manifest
validate-manifest: validate ## Alias for validate

.PHONY: lint-scripts
lint-scripts: ## Run shellcheck on all scripts
	@echo "Running shellcheck..."
	@shellcheck scripts/*.sh
	@echo "All scripts passed shellcheck ✓"

.PHONY: lint-entrypoint
lint-entrypoint: ## Run go vet on the entrypoint wrapper
	@echo "Running go vet on entrypoint..."
	@cd cmd/entrypoint && go vet ./...
	@echo "Entrypoint passed go vet ✓"

.PHONY: lint
lint: lint-scripts lint-entrypoint ## Run all linters

# ─── Build index ──────────────────────────────────────────────────────────────
.PHONY: build-index
build-index: ## Generate build-index.json from per-plugin metadata
	@./scripts/generate-build-index.sh

# ─── Matrix generation ────────────────────────────────────────────────────────
.PHONY: matrix
matrix: ## Print the CI matrix JSON
	@./scripts/generate-matrix.sh

# ─── Clean targets ────────────────────────────────────────────────────────────
.PHONY: clean
clean: ## Remove built images and temp files
	@echo "Cleaning up..."
	@GIT_SUFFIX=$$(git describe --always --dirty 2>/dev/null || echo "unknown"); \
	for plugin in $(PLUGINS); do \
		KIND=$$(yq ".plugins[] | select(.name == \"$$plugin\") | .kind" $(MANIFEST)); \
		VERSION=$$(yq ".plugins[] | select(.name == \"$$plugin\") | .version" $(MANIFEST)); \
		IMAGE="cq-$$KIND-$$plugin:$$VERSION-$$GIT_SUFFIX"; \
		if docker image inspect "$$IMAGE" >/dev/null 2>&1; then \
			echo "  Removing $$IMAGE"; \
			docker rmi "$$IMAGE" 2>/dev/null || true; \
		fi; \
	done
	@docker rm -f $$(docker ps -aq --filter "name=smoke-" 2>/dev/null) 2>/dev/null || true
	@echo "Clean complete ✓"

# ─── Help ─────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help message
	@echo "cloudquery-plugins-builder — Developer targets"
	@echo ""
	@echo "Usage: make <target> [PLUGIN=<name>] [PLATFORM=<platforms>]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' | \
		sort
	@echo ""
	@echo "Available plugins: $(PLUGINS)"
	@echo ""
	@echo "Examples:"
	@echo "  make build PLUGIN=postgresql     Build postgresql image"
	@echo "  make build-s3                    Build s3 image"
	@echo "  make smoke-test PLUGIN=file      Smoke test file image"
	@echo "  make build-all                   Build all plugins"
	@echo "  make validate                    Validate manifest"
	@echo "  make clean                       Remove built images"
