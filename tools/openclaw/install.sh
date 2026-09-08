#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

set -e

enclave-install-npm-tool openclaw openclaw OpenClaw

session_wrapper="$HOME/.local/bin/enclave-openclaw-session"
cat > "$session_wrapper" <<'WRAPPER'
#!/bin/bash
# Start the OpenClaw gateway, wait for it to listen, then run the TUI in the
# foreground so the Enclave session lifetime matches the TUI's.
set -uo pipefail

port="${OPENCLAW_GATEWAY_PORT:-18789}"

openclaw gateway run --port "$port" &
gateway_pid=$!
trap 'kill "$gateway_pid" 2>/dev/null || true' EXIT

ready=0
for _ in $(seq 1 60); do
    if ! kill -0 "$gateway_pid" 2>/dev/null; then
        echo "openclaw gateway exited before it started listening" >&2
        wait "$gateway_pid"
        exit 1
    fi
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done

if [ "$ready" != "1" ]; then
    echo "openclaw gateway did not listen on port $port within 60s" >&2
    exit 1
fi

openclaw tui "$@"
WRAPPER
chmod 0755 "$session_wrapper"

openclaw --version
