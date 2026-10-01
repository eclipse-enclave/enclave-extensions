# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Antigravity CLI extension setup
mkdir -p "$HOME/.gemini/antigravity-cli" "$HOME/.gemini/config"

# Pre-seed onboarding completion in the cache so agy skips the first-run
# welcome screen, terminal theme selection, and "Help improve Antigravity"
# telemetry opt-in prompt for new projects.
_cache_dir="$HOME/.gemini/antigravity-cli/cache"
mkdir -p "$_cache_dir"
_onboarding="$_cache_dir/onboarding.json"
if [ ! -f "$_onboarding" ]; then
    cat <<'EOF' > "$_onboarding"
{
  "consumerOnboardingComplete": true,
  "enterpriseOnboardingComplete": false,
  "onboardingComplete": true
}
EOF
fi
unset _cache_dir _onboarding

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

# jq ships in the base image, and the template is baked in from
# templates/settings.json. Fail closed if either is ever absent: continuing
# would start the session with telemetry and workspace access left at agy's own
# defaults, which is the opposite of what this extension promises.
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to apply the Antigravity privacy defaults" >&2
    exit 1
fi
if [ ! -f "$_defaults" ]; then
    echo "Error: Antigravity settings template is missing: $_defaults" >&2
    exit 1
fi

[ -s "$_settings" ] || echo '{}' > "$_settings"
_tmp="$(mktemp)"
if jq -s '.[0] * .[1]' "$_settings" "$_defaults" > "$_tmp" 2>/dev/null; then
    mv "$_tmp" "$_settings"
else
    # A settings.json agy itself refuses to parse is repaired by hand, not by
    # this script: overwriting it here would discard the broken file. Do not
    # start with the privacy defaults unapplied either.
    rm -f "$_tmp"
    echo "Error: could not apply the privacy defaults to $_settings" >&2
    exit 1
fi

# In yolo mode, default the workspace to trusted so agy skips its folder trust prompt.
# In non-yolo mode, remove the workspace so trust granted in a previous yolo session
# does not persist into a --no-yolo session in the same project.
if [ -n "${PROJECT_DIR:-}" ]; then
    _tmp="$(mktemp)"
    if [ "${ENCLAVE_YOLO:-}" = "1" ]; then
        if jq --arg dir "$PROJECT_DIR" \
            '.trustedWorkspaces = (((.trustedWorkspaces // []) + [$dir]) | unique)' \
            "$_settings" > "$_tmp" 2>/dev/null; then
            mv "$_tmp" "$_settings"
        else
            rm -f "$_tmp"
        fi
    else
        if jq --arg dir "$PROJECT_DIR" \
            '.trustedWorkspaces = ((.trustedWorkspaces // []) - [$dir])' \
            "$_settings" > "$_tmp" 2>/dev/null; then
            mv "$_tmp" "$_settings"
        else
            rm -f "$_tmp"
        fi
    fi
fi
unset _tmp _settings _defaults

