#!/bin/bash
# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

set -e

# Pinned: dsh is a developer preview whose README promises breaking changes,
# and the bind patch in templates/cordis.patch.yml targets an internal row id.
enclave-install-npm-tool "@deepseek-ai/dsh@0.1.1-rc.2" dsh "DeepSeek Harness"

session_wrapper="$HOME/.local/bin/enclave-dsh-session"
cat > "$session_wrapper" <<'WRAPPER'
#!/bin/bash
# Run the dsh web server in the foreground so the Enclave session lifetime
# matches it. There is no in-box TUI, so the web server is the session surface.
set -uo pipefail

cd "${PROJECT_DIR:-$PWD}" || exit 1

exec dsh web --no-open "$@"
WRAPPER
chmod 0755 "$session_wrapper"

dsh --version
