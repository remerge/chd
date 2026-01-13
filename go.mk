SHADOW_LINTER := golang.org/x/tools/go/analysis/passes/shadow/cmd/shadow
SHADOW_LINTER_VERSION := v0.30.0

GOIMPORTS_LINTER_VERSION := v0.30.0
GOIMPORTS_LINTER := golang.org/x/tools/cmd/goimports

REVIVE_LINTER_VERSION := v1.6.1
REVIVE_LINTER := github.com/mgechev/revive


.PHONY: go-update
go-update:: ## update Go modules
	go get -u -x ./... 2>&1 | grep -vP '^(#|mkdir|cd|\d\.\d\d\ds #)' || :
	go mod tidy -v -x
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

$(SHADOW_LINTER):
	make $(TOOLS)/$@ GOTOOL_VERSION_TO_INSTALL=$(SHADOW_LINTER_VERSION)

$(REVIVE_LINTER):
	make $(TOOLS)/$@ GOTOOL_VERSION_TO_INSTALL=$(REVIVE_LINTER_VERSION)

$(GOIMPORTS_LINTER):
	make $(TOOLS)/$@ GOTOOL_VERSION_TO_INSTALL=$(GOIMPORTS_LINTER_VERSION)

# Code maintenance

GENERATE_SOURCES ?=

gen: $(GENERATE_SOURCES)
	go generate ./...
	$(MAKE) fmt

fmt:: .fmt-gofmt .fmt-goimports

GOFMT_EXCLUDES ?= %.pb.go %_gen.go %_easyjson.go
GOFMT_SOURCES = $(filter-out $(GOFMT_EXCLUDES),$(GO_SOURCES))

.fmt-gofmt: $(GOFMT_SOURCES)	## format go sources
	if [[ "$(GOFMT_SOURCES)" != "" ]]; then gofmt -w -s -l $(GOFMT_SOURCES); fi

.fmt-goimports: $(GOIMPORTS_LINTER) $(GOFMT_SOURCES)	## group and correct imports
	if [[ "$(GOFMT_SOURCES)" != "" ]]; then $(TOOLS)/$< -w -l $(GOFMT_SOURCES); fi

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

# *lint* target will run go fmt check, vet, goimports and revive.
# Use "REVIVELINTER_EXCLUDES" to exclude files from revive.
# Use "GOFMT_EXCLUDES" to exclude files from gofmt and goimports.
# Use "VET_FLAGS" to define vet linter flags.

lint:: .lint-mod-tidy .lint-fmt .lint-goimports .lint-vet .lint-shadow .lint-revive .lint-fix ## run all linters

.lint-fmt: $(GOFMT_SOURCES) ## compare gofmt and goimports output
	@test -z "$(GOFMT_SOURCES)" || DIFF=`gofmt -s -d $(GOFMT_SOURCES)` && test -z "$$DIFF" || echo "$$DIFF" && test -z "$$DIFF"

.lint-goimports: $(GOIMPORTS_LINTER) $(GOFMT_SOURCES)
	@test -z "$(GOFMT_SOURCES)" || DIFF=`$(TOOLS)/$< -d $(GOFMT_SOURCES)` && test -z "$$DIFF" || echo "$$DIFF" && test -z "$$DIFF"

.lint-vet: $(GO_SOURCES) go.mod ## run vet
	go vet $(VET_FLAGS) ./...
.NOTPARALLEL: .lint-vet

.lint-shadow: $(SHADOW_LINTER) $(GO_SOURCES) ## run shadow linter
	go vet -vettool=$(TOOLS)/$< ./...
.NOTPARALLEL: .lint-shadow

REVIVE_CONFIG = $(wildcard revive.toml)
.lint-revive: $(REVIVE_LINTER) $(GO_SOURCES) $(REVIVE_CONFIG)	## run revive linter
	$(TOOLS)/$< -config $(REVIVE_CONFIG) -formatter friendly -exclude ./vendor/... $(REVIVELINTER_EXCLUDES) ./...

.lint-fix: $(GO_SOURCES) ## run fix
	@DIFF=`go tool fix -go=go$$(grep '^go ' < go.mod | awk '{print $$2}') -diff $^` && test -z "$$DIFF" || echo "$$DIFF" && test -z "$$DIFF"

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
export NOMAD_ADDR = http://nomad.service.$(DIVERT_CLUSTER).consul:4646/
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

.check-dependencies: .check-support
	@command -v nomad >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install hashicorp nomad to proceed ..."; exit 1; }

	@command -v nomad-pack >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install nomad-pack to proceed ..."; exit 1; }

	@command -v docker >/dev/null 2>&1 \
	|| { echo >&2 "Error: Please install docker to proceed ..."; exit 1; }

divert: .check-dependencies .nomad-env .input-validation
	@mkdir -p .build
	@docker build \
	--build-arg "CI_COMMIT=$(TASK_IMAGE)" \
	--build-arg "CI_REPO=$(PROJECT_REPO)" \
	--build-arg "CI_REPO=$(DEV_WHOAMI)" \
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
		nomad-pack registry add remerge-pack github.com/remerge/nomad-pack; \
		nomad-pack run docker_service \
		--var='task_image=$(TASK_IMAGE)' --var='priority=$(PRIORITY)' \
		--var='cluster=${DIVERT_CLUSTER}' \
		--var='constraints=[{"attribute":"$$$${attr.unique.hostname}","value": "${DIVERT_HOST_NAME}", "operator": "="}]' \
		--var='environment=production' --namespace='diverts' \
		--var-file=.build/.divert.nomad.variables.hcl \
		--name=$(PROJECT_ID)-${DIVERT_HOST_NAME} --registry=remerge-pack; \
	else \
		sed "s/job \"\(.*\)\" {/job \"\1-${DIVERT_HOST_NAME}\" \
		{/" nomad.hcl > .build/.divert.nomad.hcl; \
		sed -i -e "s|nomad/jobs/$(PROJECT_ID)|nomad/jobs/$(PROJECT_ID)-${DIVERT_HOST_NAME}|" \
		.build/.divert.nomad.hcl; \
		nomad job run -namespace "diverts" -region ${DIVERT_CLUSTER} \
		-var 'task_image=$(TASK_IMAGE)' -var 'cluster=${DIVERT_CLUSTER}' \
		-var 'priority=$(PRIORITY)' \
		-var 'contraint_value=${DIVERT_HOST_NAME}' -var 'environment=production' \
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
