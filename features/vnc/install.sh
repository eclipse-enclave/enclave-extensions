#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# Install Chromium and the VNC runtime scripts. The display/VNC packages
# themselves come from aptPackages in spec.yaml.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chromium is installed here rather than via aptPackages so the failure is
# attributable: `chromium` is only a real deb on Debian archives (Ubuntu ships a
# snap stub), and an unavailable package makes the shared apt step fail with
# apt's own message and no mention of this feature. Either way the build stops
# (failOnInstallError), but this way it stops with an actionable one.
apt-get update
if ! apt-get install -y --no-install-recommends chromium; then
    echo "vnc: cannot install chromium: this feature needs a base image whose" \
        "archive ships Chromium as a deb (the default Debian base does;" \
        "Ubuntu only ships it as a snap)" >&2
    exit 1
fi
apt-get clean
rm -rf /var/lib/apt/lists/*

install -D -m 755 "$dir/bin/enclave-vnc-supervisor" /usr/local/bin/enclave-vnc-supervisor
install -D -m 755 "$dir/bin/enclave-vnc-open" /usr/local/bin/enclave-vnc-open
install -D -m 755 "$dir/bin/enclave-vnc-chromium" /usr/local/bin/enclave-vnc-chromium
install -D -m 644 "$dir/waiting.html" /usr/local/share/enclave-vnc/waiting.html

# Staged outside /usr/share/applications: its MimeType line alone would make it
# the image-wide http/https handler. setup.sh registers it per user when
# VNC_OPEN_LINKS=1.
install -D -m 644 "$dir/enclave-vnc-open.desktop" /usr/local/share/enclave-vnc/enclave-vnc-open.desktop

echo "vnc: installed chromium, the enclave-vnc-* scripts, waiting page, and URL handler"
