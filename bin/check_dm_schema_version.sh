#!/usr/bin/env bash

set -o pipefail
set -o errexit

# git hooks export GIT_DIR, GIT_INDEX_FILE etc. In a worktree these are absolute paths,
# so `git clone` below would write the dm index into the current repository.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

declare localSchemaVersion
declare remoteSchemaVersion

grep -q "module github.com/remerge/dm" go.mod && exit 0 # exit if it's the dm itself
grep -q "github.com/remerge/dm" go.mod || exit 0        # exit if dm is not a dependency

localSchemaVersion=$(go doc -src github.com/remerge/dm SchemaVersion | grep "const SchemaVersion")

TMP_DIR=$(mktemp --directory)
git clone --quiet git@github.com:remerge/dm "$TMP_DIR"
remoteSchemaVersion=$(go doc -C "$TMP_DIR" -src github.com/remerge/dm SchemaVersion | grep "const SchemaVersion")
rm -rf "$TMP_DIR"

if [ "$localSchemaVersion" != "$remoteSchemaVersion" ]; then
    echo "dm.SchemaVersion mismatch"
    exit 1
fi
