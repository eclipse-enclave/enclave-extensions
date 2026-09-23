#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Upstream fingerprint for enclave's automatic update probe: the build the Amp
# CLI installer would fetch right now. AMP_VERSION is read exactly as install.sh
# reads it, so pinning the variable pins the probe with it and the probe cannot
# report a change the rebuild will not deliver.
#
# Amp versions carry a build timestamp and change several times a day, so left
# unpinned this probe reports a stale image far more often than a tool that
# cuts releases.
set -euo pipefail

AMP_VERSION="${AMP_VERSION:-latest}"

version="$AMP_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsSL https://static.ampcode.com/cli/cli-version.txt | tr -d '[:space:]')"
fi

if [ -z "$version" ]; then
    echo "Could not resolve the current Amp CLI build" >&2
    exit 1
fi

printf '%s\n' "$version"
