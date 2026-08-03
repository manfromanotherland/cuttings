# Root task runner for the ReadControl polyrepo.
#
# Drives every sub-repo (core, extension, macos, website) from this umbrella
# directory via scripts/repos.sh, so you don't cd between folders to run the
# same command five times.
#
#   make push            # git push the current branch of every repo
#   make lint            # lint every repo
#   make test            # unit tests in every repo
#   make build           # build every repo
#   make check           # lint + test (fast pre-push gate)
#   make ci              # lint + test + build
#   make status          # git status of every repo
#   make REPO=core test  # narrow a target to one repo
#
# REPO is optional; leave it empty to hit all repos.

RUN  := scripts/repos.sh
REPO ?=

.DEFAULT_GOAL := help
.PHONY: help status push pull fetch fmt lint test build check ci

help:   ## Show this runner's help and per-repo command mapping
	@$(RUN) help

status: ## git status -sb for every repo
	@$(RUN) status $(REPO)

push:   ## git push the current branch of every repo (sets upstream)
	@$(RUN) push $(REPO)

pull:   ## git pull --ff-only every repo
	@$(RUN) pull $(REPO)

fetch:  ## git fetch --all --prune every repo
	@$(RUN) fetch $(REPO)

fmt:    ## Auto-format every repo
	@$(RUN) fmt $(REPO)

lint:   ## Lint every repo
	@$(RUN) lint $(REPO)

test:   ## Run unit tests in every repo
	@$(RUN) test $(REPO)

build:  ## Build every repo
	@$(RUN) build $(REPO)

check:  ## lint + test (fast pre-push gate)
	@$(RUN) check $(REPO)

ci:     ## lint + test + build (full)
	@$(RUN) ci $(REPO)
