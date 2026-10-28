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
go-build: local
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

# Code maintenance

GENERATE_SOURCES ?=

generate:: $(GENERATE_SOURCES)
	go generate ./...
	$(MAKE) fmt

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

GO_LOCAL_CHECK_TARGETS=.lint-mod-tidy .lint-golangci
# for CI, `golangci` linter is called within the job
GO_CI_CHECK_TARGETS=.lint-mod-tidy
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
