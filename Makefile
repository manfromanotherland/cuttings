# Root task runner for the Cuttings monorepo.
#
# Drives the core, extension, and macOS component toolchains from the repository
# root via scripts/components.sh.
#
#   make push            # git push the current monorepo branch once
#   make lint            # lint every component
#   make test            # unit tests in every component
#   make build           # build every component
#   make check           # lint + test (fast pre-push gate)
#   make ci              # lint + test + build
#   make status          # git status for the monorepo
#   make REPO=core test  # narrow a quality target to one component
#
# REPO is optional for quality targets; leave it empty to hit all components.

RUN  := scripts/components.sh
REPO ?=

.DEFAULT_GOAL := help
.PHONY: help status push pull fetch fmt lint test build check ci

help:   ## Show this runner's help and per-component command mapping
	@$(RUN) help

status: ## git status -sb for the monorepo
	@$(RUN) status $(REPO)

push:   ## git push the current monorepo branch (sets upstream)
	@$(RUN) push $(REPO)

pull:   ## git pull --ff-only for the monorepo
	@$(RUN) pull $(REPO)

fetch:  ## git fetch --all --prune for the monorepo
	@$(RUN) fetch $(REPO)

fmt:    ## Auto-format every component
	@$(RUN) fmt $(REPO)

lint:   ## Lint every component
	@$(RUN) lint $(REPO)

test:   ## Run unit tests in every component
	@$(RUN) test $(REPO)

build:  ## Build every component
	@$(RUN) build $(REPO)

check:  ## lint + test (fast pre-push gate)
	@$(RUN) check $(REPO)

ci:     ## lint + test + build (full)
	@$(RUN) ci $(REPO)
