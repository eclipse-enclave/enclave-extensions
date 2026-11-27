#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Move the gws-cli feature to another gws release: pin the binary and its
# checksums in install.sh and replace skills/ with that release's gws-* skills.
# Maintainer tool; not used at build or run time.
#
# Usage: ./sync.sh <version>   e.g. ./sync.sh 0.22.5
set -euo pipefail

version="${1:?usage: $0 <version>}"
version="${version#v}"
here="$(cd "$(dirname "$0")" && pwd)"
base="https://github.com/googleworkspace/cli/releases/download/v${version}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

sha256_for() {
    curl -fsSL "$base/google-workspace-cli-$1-unknown-linux-gnu.tar.gz.sha256" | awk '{print $1}'
}
sha_x86_64="$(sha256_for x86_64)"
sha_aarch64="$(sha256_for aarch64)"

curl -fsSL -o "$workdir/src.tar.gz" \
    "https://github.com/googleworkspace/cli/archive/refs/tags/v${version}.tar.gz"
mkdir "$workdir/src"
tar -xzf "$workdir/src.tar.gz" -C "$workdir/src" --strip-components=1

rm -rf "$here/skills"
mkdir "$here/skills"
cp -R "$workdir/src/skills"/gws-* "$here/skills/"
cp "$workdir/src/LICENSE" "$here/LICENSE.skills"

sed -i.bak \
    -e "s/^GWS_VERSION=.*/GWS_VERSION=${version}/" \
    -e "s/^GWS_SHA256_X86_64=.*/GWS_SHA256_X86_64=${sha_x86_64}/" \
    -e "s/^GWS_SHA256_AARCH64=.*/GWS_SHA256_AARCH64=${sha_aarch64}/" \
    "$here/install.sh"
rm -f "$here/install.sh.bak"

echo "gws-cli now pins gws ${version} with $(find "$here/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') skills."
echo "Rebuild with --rebuild and test before committing."
