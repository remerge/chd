.PHONY: go-install
go-install:: ## install Go modules
	go get ./...
update:: go-install

.PHONY: go-update
go-update:: ## update Go modules
	go get ./...
	go mod tidy
update:: go-update

.PHONY: go-build
go-build: ## build a Go binary matching the local architecture
go-build: .build/$(.BIN_LOCAL)
build:: go-build

.PHONY: go-clean
go-clean: ## remove local Go artifacts
	rm -rf $(TOOLS)
	rm -fv .build/$(.BIN_LOCAL)
clean:: go-clean


# all go sources in build tree excluding vendor
GO_SOURCES = $(shell find . -type f \( -iname '*.go' \) -not \( -path "./vendor/*" -path ".*" \))

export GO111MODULE = on
export CGO_ENABLED = 0
export GOPRIVATE ?= github.com/remerge/*

GIT_REMOTE ?= origin
BASE_REF ?= $(if $(GIT_BASE_REF),$(GIT_BASE_REF),$(shell \
  ref=$$(git symbolic-ref --quiet "refs/remotes/$(GIT_REMOTE)/HEAD" 2>/dev/null \
    | sed 's|^refs/remotes/||'); \
  if [ -n "$$ref" ]; then \
    echo "$$ref"; \
  else \
    echo "__UNRESOLVED__"; \
  fi \
))

BASE_REMOTE = $(firstword $(subst /, ,$(BASE_REF)))
BASE_BRANCH = $(patsubst $(BASE_REMOTE)/%,%,$(BASE_REF))
export BASE_REF BASE_BRANCH

# do not use automatic targets
.SUFFIXES:

.PHONY: gen


# External tools

# Use as prerequisite. Requested tool will be installed automatically on demand.
#
# 	lint-shadow: $(TOOLS)/golang.org/x/tools/go/analysis/passes/shadow/cmd/shadow $(GO_SOURCES)
#		go vet -vettool=$< ./...
#

TOOLS ?= .tools
GOTOOL_VERSION_TO_INSTALL ?= latest
$(TOOLS)/%:
	test -x "$@" || GOBIN=$(shell pwd)/$(dir $@) go install $*@$(GOTOOL_VERSION_TO_INSTALL)

# Code maintenance

GENERATE_SOURCES ?=

generate:: $(GENERATE_SOURCES)
	go generate ./...
	$(MAKE) fmt

format::
	pre-commit run golangci-lint-fmt --all-files

# Dependencies cleanup

mod-tidy:	## tidy go.mod
	go mod tidy
.NOTPARALLEL: mod-tidy
.PHONY: mod-tidy


# Testing

TEST_TIMEOUT ?= 600s
TESTS ?= .
TEST_TAGS ?=
TEST_ARGS ?=

test:: $(GO_SOURCES) go.mod	## regular tests
	go test $(TEST_ARGS) -tags="$(TEST_TAGS)" -timeout=$(TEST_TIMEOUT) -run=$(TESTS) ./...

race:: $(GO_SOURCES) go.mod	## race tests
	CGO_ENABLED=1 go test  $(TEST_ARGS) -tags="$(TEST_TAGS)" -race -timeout=$(TEST_TIMEOUT) -run=$(TESTS) ./...

bench:: $(GO_SOURCES) go.mod	## benchmarks
	go test  $(TEST_ARGS) -tags="$(TEST_TAGS)" -run=^$ -bench=$(TESTS) -benchmem -cpu 32 ./...

test-nocache:: $(GO_SOURCES) go.mod
	go test  $(TEST_ARGS) -tags="$(TEST_TAGS)" -count=1 -timeout=$(TEST_TIMEOUT) -run=$(TESTS) ./...

race-nocache:: $(GO_SOURCES) go.mod
	CGO_ENABLED=1 go test  $(TEST_ARGS) -tags="$(TEST_TAGS)" -race -count=1 -timeout=$(TEST_TIMEOUT) -run=$(TESTS) ./...

escape: $(GO_SOURCES) go.mod ## builds with escape analysis active
	go build -v -gcflags '-m -m -l -e' ./...


watch: $(TOOLS)/github.com/cespare/reflex
	$< -r '\.go$$' -s -- sh -c 'clear && go test -v -run=Test$(T)'
.PHONY: watch

# Linting

# *lint* target will run golang-ci.

GO_LOCAL_CHECK_TARGETS=.lint-mod-tidy .lint-golangci .lint-dm
# for CI, `golangci` linter is called within the job
GO_CI_CHECK_TARGETS=.lint-mod-tidy .lint-dm
go-check:
ifeq ($(GITHUB_JOB),pre-commit)
	$(MAKE) $(GO_CI_CHECK_TARGETS)
else ifneq ($(strip $(GITHUB_JOB)),)
	@echo "Warning: GITHUB_JOB is set to '$(GITHUB_JOB)', skipping linters"
else # local run
	$(MAKE) $(GO_LOCAL_CHECK_TARGETS)
endif

.lint-golangci: .golangci.yml
	pre-commit run golangci-lint --all-files

.lint-mod-tidy:	## check go mod tidy is applied
# clean up from the last run
	rm -f /tmp/$(PROJECT_ID).go.mod.tidy.bak /tmp/$(PROJECT_ID).go.sum.tidy.bak /tmp/$(PROJECT_ID).go.mod.tidy /tmp/$(PROJECT_ID).go.sum.tidy
# backup the current files
	cp go.mod /tmp/$(PROJECT_ID).go.mod.tidy.bak
	cp go.sum /tmp/$(PROJECT_ID).go.sum.tidy.bak
# let go do its magic
	go mod tidy
# move cleaned files out of the way
	mv go.mod /tmp/$(PROJECT_ID).go.mod.tidy
	mv go.sum /tmp/$(PROJECT_ID).go.sum.tidy
# get original files back
	mv /tmp/$(PROJECT_ID).go.mod.tidy.bak go.mod
	mv /tmp/$(PROJECT_ID).go.sum.tidy.bak go.sum
# compare cleaned and original files
	diff go.mod /tmp/$(PROJECT_ID).go.mod.tidy
.NOTPARALLEL: .lint-mod-tidy
.PHONY: .lint-mod-tidy

.lint-dm: ## check if dm.SchemaVersion is up-to-date
	@if [ -x ./bin/check_dm_schema_version.sh ]; then \
		./bin/check_dm_schema_version.sh; \
	else \
		echo "Skipping dm schema version check: ./bin/check_dm_schema_version.sh not present"; \
	fi

# Building binaries

LDIMPORT=github.com/remerge/go-service
LDFLAGS=-X $(LDIMPORT).CodeVersion=$(CI_COMMIT) -X $(LDIMPORT).CodeBuild=$(CI_REPO)\#$(CI_NUM)@$(shell date -u +%FT%TZ)
MAIN ?= main

# NOTE: logically pull out binaries from source tree
.build/$(PROJECT_ID).%: $(GO_SOURCES) go.mod
	mkdir -p $(@D)
	CGO_ENABLED=0 GOOS=$(basename $*) GOARCH=$(patsubst .%,%,$(suffix $*)) go build -trimpath -o $@ -ldflags "$(LDFLAGS)" $(PROJECT_REPO)/$(MAIN)

dist: .build/$(PROJECT_ID).linux.amd64	## linux amd64 binary

.BIN_LOCAL = $(PROJECT_ID).$(shell go env GOOS).$(shell go env GOARCH)

local: .build/$(.BIN_LOCAL)

# Deployment

release:
	git push origin master:production

_DIVERT_HOST_NAME ?= $(shell echo $(DIVERT_TARGET) | cut -d . -f 1)
_DIVERT_CLUSTER ?= $(shell echo $(DIVERT_TARGET) | cut -d . -f 2)
TASK_IMAGE = $(SERVICES_ARTIFACT_REGISTRY)$(PROJECT_ID):$(DEV_COMMIT)
PRIORITY := 70
DIVERT_HOST_NAME = $(shell echo $(_DIVERT_HOST_NAME) | tr '[:upper:]' '[:lower:]')
DIVERT_CLUSTER ?= $(shell echo $(_DIVERT_CLUSTER) | tr '[:upper:]' '[:lower:]')
UPPER_DIVERT_CLUSTER = $(shell echo $(DIVERT_CLUSTER) | tr '[:lower:]' '[:upper:]')

define setup-nomad-env
export NOMAD_ADDR = http://nomad.$(DIVERT_CLUSTER).rmge.net:4646/
export NOMAD_TOKEN = $(shell \
	auto_nomad_token=""; \
	if which op > /dev/null 2>&1; then \
		if token=$$(op read op://Development/NOMAD_TOKEN_$(UPPER_DIVERT_CLUSTER)/credential); then \
			auto_nomad_token="$$token"; \
		fi; \
	fi; \
	if [ -z "$${auto_nomad_token}" ]; then \
		eval "echo $$NOMAD_TOKEN_$(UPPER_DIVERT_CLUSTER)"; \
	else\
		echo "$${auto_nomad_token}"; \
	fi\
)
endef

.nomad-env:
	$(eval $(call setup-nomad-env))

.input-validation-host:
ifeq ($(DIVERT_HOST_NAME),)
	@echo "DIVERT_HOST_NAME is empty (validate DIVERT_TARGET='$(DIVERT_TARGET)' against '%node%.%host%' format)"
	@exit 1
endif

.token-validation:
ifeq ($${NOMAD_TOKEN},)
	@echo "Error: Missing Token: Please set Nomad Token for \
$(DIVERT_CLUSTER) as NOMAD_TOKEN_$(UPPER_DIVERT_CLUSTER)!"
	@exit 1
endif

.input-validation-cluster:
ifeq ($(DIVERT_CLUSTER),)
	@echo "DIVERT_CLUSTER is empty (validate DIVERT_TARGET='$(DIVERT_TARGET)' against '%node%.%host%' format)"
	@exit 1
endif

.check-support:
	@if [ ! -f nomad.hcl ] && [ ! -f nomad.variables.hcl ]; \
	then echo "Error: Divert not supported"; \
	exit 1; fi

.input-validation: .input-validation-host .input-validation-cluster .token-validation

.check-master-sync:
	@if [ "$(BASE_REF)" = "__UNRESOLVED__" ]; then \
		echo ""; \
		printf "\033[30;43mWARNING:\033[0m Could not determine the default branch for remote '$(GIT_REMOTE)'\n"; \
		echo "         This repository may not expose a remote HEAD or uses a non-standard base branch."; \
		echo ""; \
		echo "         Please specify it explicitly, for example:"; \
		echo "           make GIT_BASE_REF=$(GIT_REMOTE)/main"; \
		echo "           make GIT_BASE_REF=$(GIT_REMOTE)/master"; \
		echo ""; \
		exit 1; \
	fi

	@echo "Checking if branch includes latest $(BASE_REF)..."

	@git fetch "$(BASE_REMOTE)" "$(BASE_BRANCH)" --quiet 2>/dev/null || \
		echo "Warning: failed to fetch $(BASE_REF); using local ref"

	@if ! git merge-base --is-ancestor "$(BASE_REF)" HEAD 2>/dev/null; then \
		echo ""; \
		printf "\033[30;43mWARNING:\033[0m Your branch does not include the latest changes from $(BASE_REF)\n"; \
		echo "         Consider rebasing or merging:"; \
		echo "           git rebase $(BASE_REF)"; \
		echo "           git merge  $(BASE_REF)"; \
		echo ""; \
		read -p "Continue with deployment anyway? [y/N] " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "Deployment aborted."; \
			exit 1; \
		fi; \
	fi

.check-dependencies: .check-support
	@command -v nomad >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install hashicorp nomad to proceed ..."; exit 1; }

	@command -v nomad-pack >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install nomad-pack to proceed ..."; exit 1; }

	@command -v docker >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install docker to proceed ..."; exit 1; }

divert: .check-master-sync .check-dependencies .nomad-env .input-validation
	@mkdir -p .build
	@docker build \
	--platform linux/amd64 \
	--build-arg "CI_COMMIT=$(CI_COMMIT)" \
	--build-arg "CI_REPO=$(CI_REPO)" \
	--ssh default . \
	-t "$(TASK_IMAGE)"

	@docker push $(TASK_IMAGE)

	@data=$$(nomad var get -region ${DIVERT_CLUSTER} -out json nomad/jobs/$(PROJECT_ID)) && \
	echo $${data} | nomad var put  -force -namespace "diverts" -region ${DIVERT_CLUSTER} \
	 -in json nomad/jobs/$(PROJECT_ID)-${DIVERT_HOST_NAME} -

	@if [ -f nomad.variables.hcl ]; \
	then \
		sed "s/job_name = \"\(.*\)\"/job_name = \"\1-${DIVERT_HOST_NAME}\"/" \
		nomad.variables.hcl > .build/.divert.nomad.variables.hcl; \
		sed -i -e "s|nomad/jobs/$(PROJECT_ID)|nomad/jobs/$(PROJECT_ID)-${DIVERT_HOST_NAME}|" \
		.build/.divert.nomad.variables.hcl; \
		sed -i -e "s|\(.*\)count =\(.*\)|count = 1|" .build/.divert.nomad.variables.hcl;  \
		if [ -n "$(DIVERT_ROLLBAR_OFF)" ]; then \
			echo "*** WARNING: Rollbar alerts to be suppressed"; \
			sed -i '/rollbar-token/d' .build/.divert.nomad.variables.hcl; \
		fi; \
		nomad-pack registry add remerge-pack github.com/remerge/nomad-pack; \
		nomad-pack run docker_service \
		--var='task_image=$(TASK_IMAGE)' --var='priority=$(PRIORITY)' \
		--var='cluster=${DIVERT_CLUSTER}' --var='service_name=$(PROJECT_ID)' \
		--var='constraints=[{"attribute":"$$$${attr.unique.hostname}","value": "${DIVERT_HOST_NAME}", "operator": "="}]' \
		--var='environment=divert' --namespace='diverts' \
		--var-file=.build/.divert.nomad.variables.hcl \
		--var 'count_cluster_config={"${DIVERT_CLUSTER}": 1}' \
		--name=$(PROJECT_ID)-${DIVERT_HOST_NAME} --registry=remerge-pack; \
	else \
		sed "s/job \"\(.*\)\" {/job \"\1-${DIVERT_HOST_NAME}\" \
		{/" nomad.hcl > .build/.divert.nomad.hcl; \
		sed -i -e "s|nomad/jobs/$(PROJECT_ID)|nomad/jobs/$(PROJECT_ID)-${DIVERT_HOST_NAME}|" \
		.build/.divert.nomad.hcl; \
		sed -i -e "s|\(.*\)count =\(.*\)|\1count = 1|" \
		.build/.divert.nomad.hcl; \
		if [ -n "$(DIVERT_ROLLBAR_OFF)" ]; then \
			echo "*** WARNING: Rollbar alerts to be suppressed"; \
			sed -i '/rollbar-token/d' .build/.divert.nomad.hcl; \
		fi; \
		nomad job run -namespace "diverts" -region ${DIVERT_CLUSTER} \
		-var 'task_image=$(TASK_IMAGE)' -var 'cluster=${DIVERT_CLUSTER}' \
		-var 'priority=$(PRIORITY)' \
		-var 'contraint_value=${DIVERT_HOST_NAME}' -var 'environment=divert' \
		-var 'contraint_attribute=attr.unique.hostname' \
		.build/.divert.nomad.hcl; \
	fi \

divert-stop: .check-dependencies .nomad-env .input-validation
	@nomad job stop -purge -namespace "diverts" \
	-region ${DIVERT_CLUSTER} $(PROJECT_ID)-${DIVERT_HOST_NAME}
	@nomad var purge -namespace "diverts" -region ${DIVERT_CLUSTER} \
	nomad/jobs/$(PROJECT_ID)-${DIVERT_HOST_NAME}

divert-journal: .check-dependencies .nomad-env .input-validation
	@for allocs in \
	$$(nomad job allocs -namespace "diverts" -region ${DIVERT_CLUSTER} \
	-t '{{range .}}{{printf "%s \n" .ID}}{{end}}' $(PROJECT_ID)-${DIVERT_HOST_NAME}); \
	do \
	for id in \
	$$(nomad job inspect -namespace "diverts" -region ${DIVERT_CLUSTER} \
	-t '{{range .TaskGroups}} {{range .Tasks}} {{ .Name  }}{{end}}{{end}}' $(PROJECT_ID)-${DIVERT_HOST_NAME}); \
	do \
	nomad alloc logs -namespace "diverts" $$allocs $$id; \
	done; \
	done;


divert-status: .check-dependencies .nomad-env .input-validation
	@echo "==> The divert for ${NAME} in ${DIVERT_CLUSTER} is \
	`nomad job inspect -namespace diverts -region ${DIVERT_CLUSTER} \
	-t '{{  .Status  }}' $(PROJECT_ID)-${DIVERT_HOST_NAME}` \
	`nomad job inspect -namespace diverts -region ${DIVERT_CLUSTER}  \
	-t '{{range .TaskGroups}} {{range .Tasks}} {{ .Config.image  }}{{end}}{{end}}' \
	 $(PROJECT_ID)-${DIVERT_HOST_NAME}` ...."

divert-list: .check-dependencies .nomad-env .input-validation-cluster .token-validation
	@nomad status -namespace diverts -region ${DIVERT_CLUSTER}

.PHONY: divert divert-update divert-stop divert-status .check-dependencies .input-validation .nomad-env
