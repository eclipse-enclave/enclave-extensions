# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Antigravity CLI extension setup
mkdir -p "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config"

# Re-assert the privacy defaults on every start.
#
# The settings template is copied once, only when no settings.json exists yet,
# and agy rewrites that file sparsely: on exit it keeps just the keys whose
# value differs from the default it holds for the session, so enableTelemetry
# is gone from disk after the first run and the template never gets a second
# chance. Merging the defaults under the file (`defaults * .`) restores what
# was dropped and leaves everything the file still carries untouched -- which
# also means a key you flipped inside a session survives only as long as agy
# kept writing it down.
_settings="${ENCLAVE_TOOL_SETTINGS_TARGET:-$HOME/.gemini/antigravity-cli/settings.json}"
if command -v jq >/dev/null 2>&1; then
    [ -s "$_settings" ] || echo '{}' > "$_settings"
    _tmp="$(mktemp)"
    if jq '{
            enableTelemetry: false,
            showFeedbackSurvey: false,
            allowNonWorkspaceAccess: false
        } * .' "$_settings" > "$_tmp" 2>/dev/null; then
        mv "$_tmp" "$_settings"
    else
        # A settings.json agy itself refuses to parse is repaired by hand, not
        # by this script: overwriting it here would discard the broken file.
        rm -f "$_tmp"
        echo "Warning: could not parse $_settings; privacy defaults not applied" >&2
    fi
    unset _tmp
fi
unset _settings
