# playwright-mcp

Playwright's MCP server and a Chromium for it, registered with Claude Code so
the agent can drive a headless browser for automation and UI testing. Opt-in
(disabled by default).

This was core Enclave's built-in `playwright` feature and its
`--playwright-mcp` flag. Both are gone from core; this feature replaces them.

**Priority**: 75

## Usage

```bash
enclave features add eclipse-enclave/enclave-extensions --name playwright-mcp
enclave --tool claude --features +playwright-mcp
```

Inside the session, `claude mcp list` shows `playwright`. To have it in every
session, add it to the features in `~/.config/enclave/config.json`:

```json
{
  "features": ["default", "playwright-mcp"]
}
```

Claude Code only. With another tool, the feature still installs the browser
and sets `PLAYWRIGHT_BROWSERS_PATH`, but registers nothing.

## Installation

Runs as root (`needsRoot: true`):

1. Installs `@playwright/mcp` globally with npm. Enclave puts its
   agent-private Node runtime on `PATH` for root installs, so `node-dev` is
   not needed.
2. Installs Chromium and its system libraries to `/opt/playwright-browsers`,
   with the Playwright bundled in `@playwright/mcp`, so the browser matches
   what the server expects.

Nothing is pinned: each image build installs the current `@playwright/mcp`.

## MCP registration

On every session start, `feature-entrypoint.d/setup.sh` registers the server
in Claude Code's local scope (the project's entry in `~/.claude.json`):

```json
{
  "type": "stdio",
  "command": "$ENCLAVE_AGENT_NODE_DIR/bin/npx",
  "args": ["@playwright/mcp", "--headless", "--no-sandbox", "--browser", "chromium"],
  "env": { "PLAYWRIGHT_BROWSERS_PATH": "/opt/playwright-browsers" }
}
```

`$ENCLAVE_AGENT_NODE_DIR` is expanded (default `/opt/enclave/node`).

The local scope persists across sessions in the config store, and a disabled
feature's scripts don't run. So Enclave's Claude setup removes this exact
registration on every start, and the feature adds it back while it is
enabled: a session without `+playwright-mcp` has no `playwright` server.
Enclave versions that still have `--playwright-mcp` remove `playwright` on
every start without the flag, with the same result.

If the project already has its own local `playwright` server that differs
from the one above, Enclave leaves it alone and this feature doesn't replace
it. To use this feature's server instead, run
`claude mcp remove -s local playwright` in the session and start a new one.
