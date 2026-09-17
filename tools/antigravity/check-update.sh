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

curl -fsS https://api.github.com/repos/google-antigravity/antigravity-cli/releases/latest | jq -r '.tag_name'
