# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# OpenClaw extension setup

mkdir -p "$HOME/.openclaw"

if command -v openclaw >/dev/null 2>&1; then
    # Inside a container the gateway's bind mode resolves to 0.0.0.0 so the
    # published port works, and a non-loopback bind refuses to start without
    # auth ("refusing to bind gateway ... without auth"). Generate the shared
    # token once; it lives in the config store and stays stable across restarts.
    # --non-interactive matters: doctor is a full wizard by default and would
    # block the session on prompts, including background runs with no TTY.
    if [ -z "$(openclaw config get gateway.auth.token 2>/dev/null | tr -d '"[:space:]')" ]; then
        openclaw doctor --generate-gateway-token --non-interactive || true
    fi

    # Operate on the mounted project instead of OpenClaw's own workspace dir.
    if [ -n "${PROJECT_DIR:-}" ]; then
        openclaw config set agents.defaults.workspace "$PROJECT_DIR" || true
    fi

    # OpenClaw exposes approvals through config, not a CLI flag, so yolo mode is
    # applied here rather than through sandbox.yoloFlag.
    if [ "${ENCLAVE_YOLO:-}" = "1" ]; then
        openclaw config set tools.exec.security full || true
        openclaw config set tools.exec.ask off || true
    fi

    _openclaw_token="$(openclaw config get gateway.auth.token 2>/dev/null | tr -d '"[:space:]')"
    if [ -n "$_openclaw_token" ]; then
        echo "OpenClaw dashboard token: $_openclaw_token"
    fi
    unset _openclaw_token
fi
