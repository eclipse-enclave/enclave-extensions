#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Upstream fingerprint for enclave's automatic update probe: the newest
# Antigravity CLI release tag. Pin this to the same value as install.sh's
# ANTIGRAVITY_VERSION when you pin the version, or the probe will report a
# change the rebuild cannot deliver.
set -euo pipefail

ANTIGRAVITY_VERSION="${ANTIGRAVITY_VERSION:-latest}"

version="$ANTIGRAVITY_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsS https://api.github.com/repos/google-antigravity/antigravity-cli/releases/latest | jq -r '.tag_name // empty')"
fi

if [ -z "$version" ]; then
    echo "Could not resolve the latest Antigravity CLI release" >&2
    exit 1
fi

printf '%s\n' "$version"
