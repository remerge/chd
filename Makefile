PROJECT_ID := chd
PROJECT_NAME := CHD Minimal Perfect Hash
PROJECT_REPO := github.com/remerge/$(PROJECT_ID)

# Provide local development fallbacks if there are no CI variables
DEV_WHOAMI := $(shell whoami)
DEV_COMMIT := dev.$(DEV_WHOAMI).$(shell git rev-parse --short HEAD)

# Set CI variables from GitHub Actions workflow run
CI_COMMIT ?= $(or $(GITHUB_SHA), $(DEV_COMMIT))
CI_REPO ?= $(or $(GITHUB_REPOSITORY), $(PROJECT_REPO))
CI_NUM ?= $(or $(GITHUB_RUN_ID), $(DEV_WHOAMI))

# Base URL of our Google Cloud Artifact Registry for Docker images being
# deployed as Nomad service jobs by GitHub Actions workflows or local divert
SERVICES_ARTIFACT_REGISTRY := europe-west4-docker.pkg.dev/artifact-registry-ff9b/services/

# Use bash instead of sh as the shell to run commands
# https://www.gnu.org/software/make/manual/html_node/Choosing-the-Shell.html
SHELL = bash

# Show auto-generated help text when invoking make without a target
# https://www.gnu.org/software/make/manual/html_node/Special-Variables.html
.DEFAULT_GOAL := help

.PHONY: help
help: ## generate help text from Makefile comments
	@grep -hE '^[a-zA-Z_0-9%-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# https://www.gnu.org/software/make/manual/html_node/Double_002dColon.html
.PHONY: install
install:: ## prepare environment and install dependencies
	@:

.PHONY: update
update:: ## update environment and dependencies
	@:

.PHONY: generate
generate:: ## generate documentation, configuration, schemas, etc
	@:

.PHONY: format
format:: ## run formatters on source code
	@:

.PHONY: check
check:: ## run formatters and linters
	@:

.PHONY: test
test:: ## run unit and integration tests
	@:

.PHONY: build
build:: ## run build steps and create artifact
	@:

.PHONY: run
run:: ## run build artifact locally in development mode
	@:

.PHONY: clean
clean:: ## remove build artifacts and caches
	@:

.PHONY: reset
reset: ## cleanup and reset repository to remote state
ifeq ($(FORCE),1)
	git reset --hard @{upstream}
	git clean -fdx
else
	@echo -e "\u001b[41mThis is a dangerous operation – use \`make reset FORCE=1' to execute\u001b[0m"
	@echo "Would execute \`git reset --hard @{upstream}'"
	@echo "Would execute \`git clean -fdx'"
	@git clean -ndx
endif

## copier

.PHONY: copier-copy
copier-copy: ## copy template without merging updates
	copier recopy$(if $(FORCE), -f,)$(if $(REF), -r $(REF),)

.PHONY: copier-update
copier-update: ## update project from copier template
	copier update$(if $(FORCE), -f,)$(if $(REF), -r $(REF),)
update:: copier-update

## pre-commit

.PHONY: pre-commit-install
pre-commit-install: ## install pre-commit hook
	pre-commit install -t pre-commit -t prepare-commit-msg -t commit-msg

.PHONY: pre-commit-format
pre-commit-format: ## run pre commit hooks
pre-commit-format: pre-commit-check
format:: pre-commit-format

.PHONY: pre-commit-check
pre-commit-check: ## run pre commit hooks
	pre-commit run --all-files
check:: pre-commit-check

.PHONY: pre-commit-clean
pre-commit-clean: ## remove pre-commit hook
	pre-commit uninstall
clean:: pre-commit-clean

-include *.mk

## legacy compatibility targets

.PHONY: dep
dep: install

.PHONY: gen
gen: generate

.PHONY: fmt
fmt: format

.PHONY: lint
lint: check
