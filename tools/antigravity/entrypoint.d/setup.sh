# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Antigravity CLI extension setup
mkdir -p "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config"

# Re-assert the privacy settings on every start.
#
# The settings template is copied once, only when no settings.json exists yet,
# and agy rewrites that file sparsely: on exit it keeps just the keys whose
# value differs from the default it holds for the session, so enableTelemetry
# is gone from disk after the first run and the template never gets a second
# chance. Merge the template over the file on every start: its privacy values
# win while unrelated user settings remain untouched.
_settings="${ENCLAVE_TOOL_SETTINGS_TARGET:-$HOME/.gemini/antigravity-cli/settings.json}"
_defaults="${ENCLAVE_TOOL_SETTINGS_TEMPLATE:-/usr/local/share/enclave/templates/antigravity-settings.json}"
if command -v jq >/dev/null 2>&1; then
    [ -s "$_settings" ] || echo '{}' > "$_settings"
    _tmp="$(mktemp)"
    if jq -s '.[0] * .[1]' "$_settings" "$_defaults" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$_settings"
    else
        # A settings.json agy itself refuses to parse is repaired by hand, not
        # by this script: overwriting it here would discard the broken file.
        rm -f "$_tmp"
        echo "Warning: could not apply privacy defaults to $_settings" >&2
    fi
    unset _tmp
fi
unset _settings _defaults
