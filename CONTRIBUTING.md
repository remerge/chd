# Contributing Guide

The following document describes how to contribute to this repository and the
required setup for your development environment.

This repository is generated using [`copier`](https://copier.readthedocs.io).
The [template documentation](https://github.com/remerge/template#readme)
explains how to generate and update this repository from the template.

## Getting Started

The [template repository](https://github.com/remerge/template) provides a
`make`-based development workflow that can be extended and customized per
project.

The [template documentation](https://github.com/remerge/template#readme)
explains the default development workflow and all `make` targets in detail.

To get started quickly clone this repository and use `make install check` to
install project dependencies and ensure that your development environment works.

The following system dependencies are are not managed by this repository and
need to be installed manually.

- [docker](https://www.docker.com/products/docker-desktop/) or access to a
  working docker host
- [pre-commit](https://pre-commit.com) to run formatting and linting
- [pipx](https://pypa.github.io/pipx/) to install global dependencies
- [direnv](https://direnv.net) to ensure a working environment
- [copier](https://copier.readthedocs.io) to update this repository from the
  template

Most dependencies can be installed using [Homebrew](https://brew.sh):

```shell
brew install --cask docker
brew install pre-commit pipx direnv copier
```

Once `pre-commit` hook is activated (`make pre-commit-install`),
set of formatting and linting routines is run automatically on each commit.
The step could be avoided by providing `--no-verify` flag for `git commit`.

## Go Makefile Targets

### Building binaries

To build a binary matching the local architecture.

```shell
make local
```

The resulting binary can be found in `.build/`.

To build a binary that matches the architecture of our servers (run by the CI as
well).

```shell
make dist
```

For a specific OS/architecture the hidden target `.build/<app>.<os>.<arch>` can
be used.

### Go versions

One of easiest ways to use multiple Go versions is
[golang.org/dl](https://github.com/golang/dl):

```shell
GO111MODULE=off go get golang.org/dl/go1.11.6
go1.11.6 download
PATH=$HOME/sdk/go1.11.6/bin make lint test
```

Go version is not counted by Make targets. Use `make clean` to ensure that
artifacts are built against correct version.

```shell
make clean && PATH=$HOME/sdk/go1.11.6/bin make lint test
```

### Generating artifacts

We use `go generate` to generate various artefacts (parsers and more). The `gen`
target can be used to trigger the generation.

```shell
make gen
```

### Testing

From the box you can use three targets:

- `test` Run tests
- `race` Run tests with race detection. Recommended over `test`
- `bench` Run benchmarks

Behaviour can be altered with following variables:

- `TESTS` Tests pattern
- `TEST_TIMEOUT` Tests timeout
- `TEST_TAGS` Use specific tags for tests delimited by comma
- `TEST_ARGS` Additional test arguments

```shell
make test TESTS=TestSomething TEST_TAGS="integration,postgres" TEST_ARGS=-v
```

To run the tests without test caching use `test-nocache` (and `race-nocache`)
It's highly recommends to use the `*-nocache` targets in CI to detect fragile
tests.

### watching changes

Watch your Go code for changes, rebuild and run test on change.

```shell
make watch T=NameOfTestWithoutTestPrefix
```

### Linting

This target lints the source code using various tools: `go fmt`, `goimports`,
the modules consistency check, `go check`, `go vet` and `revive`.

If any of these 3rd-party checkers hasn't been downloaded, they will be
automatically fetched and employed. `go.mk` file contains constants that specify
the particular version of each checker to retrieve (see `*_LINTER_VERSION*`).

Usage of the latest version of a checker could be indicated by setting
the corresponding constant in `go.mk` to `latest`.

```shell
make lint
```

⚠️ This target is run automatically as part of `pre-commit` hook on each commit.

> The target will not change sources.

`lint-mod-outdated` checks all modules are up to date. It's disabled until we
migrate to upstream pq and sarama.

### vet configuration

To use specific vet flags use `VET_FLAGS` variable.

```make
VET_FLAGS = -unsafeptr=false
```

### revive configuration

Revive will be installed automatically if it is not present.
Use `REVIVELINTER_EXCLUDES` variable to add excludes.

```make
REVIVELINTER_EXCLUDES = $(foreach p,$(wildcard **/*_fsm.go),-exclude $(p))
```

### gofmt and goimports configuration

Use `GOFMT_EXCLUDES` variable to exclude files from import checking.

```make
GOFMT_EXCLUDES = -not -path "./vendor/*"
```

## Deploying

We use Chef to deploy binaries to our servers. The git branch that is used to
build bianries from is `production`. If changes to the production branch are
detected, the CI executes our test suite and if succesfull builds a new binary.
Usually the new binary is roled out to all servers within a window of 30
minutes.

The `release` target can be used to trigger this process. It pushes the current
`master` branch to `production`.

```shell
make release
```

If the deployment needs to be done faster (enforced) the `deploy` target can be
used. **This should only be used if there is a good reason!**

```shell
make deploy
```

### Modules

To clean update the modules include via `go.mod` you can use the `mod-tidy`
target.

```shell
make mod-tidy
```

### Isolated test deployment

In very rare case a custom build needs to be deployed in production. Diversions
make this possible. **This should be use carefully and only under special
curcumstances**

### Requirements
