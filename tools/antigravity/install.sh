#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Install the Antigravity CLI (agy) from the upstream GitHub release.
#
# Not upstream's own installer (curl https://antigravity.google/cli/install.sh
# | bash): that one resolves the build through a Cloud Run auto-updater
# manifest, downloads from a Google Cloud Storage bucket, then edits shell
# profiles and aliases that the image already provides. The GitHub release
# carries the same archive byte for byte (checked: the 1.2.5 asset's SHA-512
# equals the manifest's), is pinnable by tag, and sits on a host the allowlist
# covers anyway. GitHub publishes no checksum beside the asset, so the
# manifest is consulted for its SHA-512 whenever it describes the release
# being installed.
set -euo pipefail

# Release to install: "latest", or a pinned tag like "1.2.5". Pinning here
# without pinning check-update.sh means the update probe keeps reporting the
# newest upstream tag and marking the image stale -- pin both or neither.
ANTIGRAVITY_VERSION="${ANTIGRAVITY_VERSION:-latest}"

REPO="google-antigravity/antigravity-cli"
MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"

case "$(uname -m)" in
    x86_64)  ASSET_ARCH="x64";   MANIFEST_ARCH="amd64" ;;
    aarch64) ASSET_ARCH="arm64"; MANIFEST_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

version="$ANTIGRAVITY_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')"
fi

if [ -z "$version" ] || [ "$version" = "null" ]; then
    echo "Could not resolve which Antigravity CLI release to install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL \
    "https://github.com/${REPO}/releases/download/${version}/agy_cli_linux_${ASSET_ARCH}.tar.gz" \
    -o "$tmp/agy.tar.gz"

# Verify against upstream's manifest when it describes this very release. The
# manifest only ever names the newest build, so a pinned older release has no
# published checksum to check against, and an unreachable manifest host is
# reported rather than fatal: the download itself came over TLS from the
# upstream org, which is what the pin already trusts.
manifest="$(curl -fsSL "${MANIFEST_BASE}/linux_${MANIFEST_ARCH}.json" 2>/dev/null || true)"
manifest_version="$(printf '%s' "$manifest" | jq -r '.version // empty' 2>/dev/null || true)"
manifest_sha512="$(printf '%s' "$manifest" | jq -r '.sha512 // empty' 2>/dev/null || true)"
if [ -z "$manifest_version" ]; then
    echo "Warning: upstream manifest unavailable; installing ${version} without a checksum check" >&2
elif [ "$manifest_version" != "$version" ]; then
    echo "Note: upstream manifest describes ${manifest_version}, not ${version}; no checksum published for a pinned release" >&2
else
    echo "${manifest_sha512}  $tmp/agy.tar.gz" | sha512sum -c - > /dev/null
    echo "Checksum of ${version} verified against the upstream manifest"
fi

# The archive holds a single binary named "antigravity"; upstream installs it
# as "agy", which is the name the docs, the status line and the entrypoint use.
tar -xzf "$tmp/agy.tar.gz" -C "$tmp" antigravity
mkdir -p "$HOME/.local/bin"
install -m 0755 "$tmp/antigravity" "$HOME/.local/bin/agy"

# The image puts ~/.local/bin on PATH; say so explicitly so the check below
# also holds when this script is run outside an image build.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v agy >/dev/null 2>&1; then
    echo "agy not found in PATH after installation" >&2
    exit 1
fi

# The smoke test runs the binary once, at build time, outside the session
# environment that spec.yaml pins. Disable the background self-updater for
# that one run too, so it cannot swap the binary just installed.
echo "Antigravity CLI $(AGY_CLI_DISABLE_AUTO_UPDATE=true agy --version) installed at $(command -v agy)"
