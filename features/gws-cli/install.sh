#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Install the Google Workspace CLI (gws) and the in-container login helper.
set -euo pipefail

# Pinned together with the vendored skills/; bump both with sync.sh.
GWS_VERSION=0.22.5
GWS_SHA256_X86_64=de78ecdbd2f1a84cca0063a7ecbc440240fc14b6ebccbb17f4646b792a8c5c1f
GWS_SHA256_AARCH64=94490295d9580e1e88574e715a0a162991747d12d62f8c7b8dcc8268b6c1cea0

case "$(dpkg --print-architecture)" in
    amd64) arch=x86_64; sha256=$GWS_SHA256_X86_64 ;;
    arm64) arch=aarch64; sha256=$GWS_SHA256_AARCH64 ;;
    *) echo "gws-cli: unsupported architecture $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

tarball="google-workspace-cli-${arch}-unknown-linux-gnu.tar.gz"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

curl -fsSL -o "$workdir/$tarball" \
    "https://github.com/googleworkspace/cli/releases/download/v${GWS_VERSION}/${tarball}"
echo "${sha256}  $workdir/$tarball" | sha256sum -c -
tar -xzf "$workdir/$tarball" -C "$workdir" ./gws
install -m 0755 "$workdir/gws" /usr/local/bin/gws

install -m 0755 "$(dirname "$0")/bin/gws-auth-login" /usr/local/bin/gws-auth-login

echo "Google Workspace CLI installed: $(gws --version | head -1)"
