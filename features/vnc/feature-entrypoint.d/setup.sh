# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Point the session at the VNC feature's virtual display so X clients land on
# it. The stack itself is started by commands.startup in spec.yaml.
#
# DISPLAY is process-wide for every tool in the session, which also flips the
# behavior of anything that treats a set DISPLAY as "a GUI is available"
# (pinentry, SSH_ASKPASS, GIT_ASKPASS): those prompts render on the contained
# display instead of the terminal. The feature README documents this.
export DISPLAY="${VNC_DISPLAY:-:99}"

# Routing "open in browser" flows (xdg-open, $BROWSER consumers) to the
# contained Chromium is opt-in: it would also catch login flows, and whatever a
# human types into that browser is readable by the agent. The registration
# lives in files, so it also covers processes started with `docker exec`, which
# never see these exports.
if [ "${VNC_OPEN_LINKS:-}" = 1 ]; then
    export BROWSER=/usr/local/bin/enclave-vnc-open
    install -D -m 644 /usr/local/share/enclave-vnc/enclave-vnc-open.desktop \
        "${XDG_DATA_HOME:-$HOME/.local/share}/applications/enclave-vnc-open.desktop" &&
        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}" &&
        xdg-mime default enclave-vnc-open.desktop x-scheme-handler/http x-scheme-handler/https ||
        echo "vnc: cannot register enclave-vnc-open as the http/https handler" >&2
fi
