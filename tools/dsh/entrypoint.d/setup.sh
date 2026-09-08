# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# DeepSeek Harness extension setup

mkdir -p "$HOME/.dsh"

# The web UI's workspace picker opens at homedir() and has no configurable
# root (dsh-host-directory-picker-browse resolves `path ?? homedir()`), so the
# mounted project, which lives under its real host path, is several levels
# away from anything the first listing shows. Link it into $HOME so it appears
# in that first listing under its own name. The registry canonicalizes through
# realpath on create, so the workspace records the real path, not the link.
if [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ]; then
    ln -sfn "$PROJECT_DIR" "$HOME/$(basename "$PROJECT_DIR")" 2>/dev/null || true
fi

# Belt and braces only. This file is sourced (verified), but exports made here
# do not survive to the tool process, so nothing may depend on them. Permission
# mode is delivered through templates/cordis.patch.yml instead.
export DSH_HOME="$HOME/.dsh"

# DSH_PERMISSION_MODE is deliberately NOT exported here. dsh fails closed when
# no sandbox backend is usable, and bwrap cannot create user namespaces in this
# container, so the mode matters, which is exactly why it must travel by a
# channel that works. See the sandbox-policy and approval rows in
# templates/cordis.patch.yml.
