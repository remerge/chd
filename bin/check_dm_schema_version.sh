#!/usr/bin/env bash

set -o pipefail
set -o errexit

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
