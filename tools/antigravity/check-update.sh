#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Upstream fingerprint for enclave's automatic update probe: the newest
# Antigravity CLI release tag. ANTIGRAVITY_VERSION is read exactly as install.sh
# reads it, so pinning the variable pins the probe with it and the probe cannot
# report a change the rebuild will not deliver.
set -euo pipefail

ANTIGRAVITY_VERSION="${ANTIGRAVITY_VERSION:-latest}"

version="$ANTIGRAVITY_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsSL https://api.github.com/repos/google-antigravity/antigravity-cli/releases/latest | jq -r '.tag_name // empty')"
fi

if [ -z "$version" ]; then
    echo "Could not resolve the latest Antigravity CLI release" >&2
    exit 1
fi

printf '%s\n' "$version"
