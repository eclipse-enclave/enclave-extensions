# Copyright (C) 2026 EclipseSource GmbH and others.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License, which is available in the project root.
#
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# Persist the whole gws config dir (credentials, encryption key, OAuth client,
# token and discovery caches) in the shared feature auth store.
#
# The core entrypoint links each declared auth file into ~/.config/gws on its
# own and touches an empty placeholder when the file is missing. gws writes
# through a temp file and rename, which replaces such a link with a file that
# dies with the container, so link the directory instead and drop the
# placeholder. Without a store (ephemeral sessions, --auth-scope=project) gws
# keeps its config in the container.

_enclave_gws_store="$HOME/.enclave-feature-auth/gws-cli"
_enclave_gws_config="$HOME/.config/gws"

if [ -d "$_enclave_gws_store" ]; then
    if [ -f "$_enclave_gws_store/client_secret.json" ] && [ ! -s "$_enclave_gws_store/client_secret.json" ]; then
        rm -f "$_enclave_gws_store/client_secret.json"
    fi
    rm -f "$_enclave_gws_config/client_secret.json"
    if rmdir "$_enclave_gws_config" 2>/dev/null; then
        ln -s "$_enclave_gws_store" "$_enclave_gws_config"
    else
        echo "Warning: gws-cli: $_enclave_gws_config is not empty; gws config will not persist" >&2
    fi
fi

unset _enclave_gws_store _enclave_gws_config
