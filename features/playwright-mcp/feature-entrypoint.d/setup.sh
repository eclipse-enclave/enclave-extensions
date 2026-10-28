# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Point Playwright at the shared browser installation
export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

# Register the Playwright MCP server in Claude Code's local scope, which
# persists across sessions in the config store. Feature scripts run after the
# tool's entrypoint.d, so the .claude.json symlink is in place and claude's own
# write goes through the store.
#
# Core's Claude setup removes the local `playwright` server on every start if
# it equals exactly this payload, and this script adds it back while the
# feature is enabled, so a session without the feature has none. Keep the
# payload in sync with core's claude/entrypoint.d/setup.sh, or that cleanup no
# longer recognizes it. If the project has its own `playwright` server, add-json
# fails and leaves it alone.
if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _playwright_json=$(jq -n \
        --arg cmd "$ENCLAVE_AGENT_NODE_DIR/bin/npx" \
        '{type:"stdio",command:$cmd,args:["@playwright/mcp","--headless","--no-sandbox","--browser","chromium"],env:{PLAYWRIGHT_BROWSERS_PATH:"/opt/playwright-browsers"}}')
    claude mcp add-json -s local playwright "$_playwright_json" >/dev/null 2>&1 || true
    unset _playwright_json
fi
