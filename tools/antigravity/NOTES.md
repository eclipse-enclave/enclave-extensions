# Antigravity CLI extension: findings and caveats

Background for anyone running, changing, or debugging this extension. The README
is the short path to a working session; this file collects the usage caveats,
the telemetry paths, and what the tool leaves on disk. Observations come from
the 1.2.5 Linux build, so version-specific details will drift. Upstream ships
no source, so nothing here was read off code: it was observed on disk and on
the wire.

## Usage caveats, collected

- On an Enclave without the fix for
  [enclave#92](https://github.com/eclipse-enclave/enclave/issues/92), the
  first start fails with `mkdir /home/agent/.gemini/config/projects: permission
  denied`. See [the root-owned config directory](#the-root-owned-config-directory)
  for the workaround.
- `GEMINI_API_KEY` alone does nothing. Set `"modelProvider": "gemini"` in the
  settings as well, or the CLI keeps asking for a Google sign-in.
- Sign-in may not survive a restart. Upstream
  [issue #479](https://github.com/google-antigravity/antigravity-cli/issues/479)
  reports the container's file-backed token being written but never read
  back, so every fresh process asks you to sign in again. Whether 1.2.5 still
  does this was not verifiable here; it needs an account to reproduce. The
  API-key route is unaffected.
- You cannot read your telemetry state back off disk, and `agy -p /config`
  does not report it either
  ([issue #1010](https://github.com/google-antigravity/antigravity-cli/issues/1010)).
  The setting is the documented opt-out and the CLI does read it at startup;
  it is not something this extension can verify for you.
- A setting you change with `/config` inside a session survives only as long
  as `agy` keeps writing it down. See [sparse settings](#sparse-settings).
- The browser tools want to download a Playwright browser at runtime, which
  the allowlist does not cover. Treat them as unavailable.
- `enclave tools update antigravity` refreshes this extension from git. The
  pinned version, if you set one, changes only when `install.sh` changes here.

## Installing from the GitHub release

Upstream's `install.sh` fetches a per-platform manifest from a Cloud Run
service (`antigravity-cli-auto-updater-974169037036.us-central1.run.app`),
which names the newest version, a download URL in the `antigravity-public`
Google Cloud Storage bucket, and a SHA-512. The same service backs the CLI's
background self-updater, which is why `spec.yaml` denies the host for sessions.

The GitHub release carries the same archive. Checked for 1.2.5: the SHA-512 of
`agy_cli_linux_x64.tar.gz` from the release page equals the `sha512` in the
`linux_amd64` manifest. The release is therefore the source here, because it
is pinnable by tag and sits on a host the allowlist covers anyway, and the
manifest is consulted only for its checksum:

- Manifest reachable and describing the release being installed: the archive
  is verified and the build fails on a mismatch.
- Manifest describing a different version, which is what a pinned older
  release sees: no checksum is published for it, and the script says so.
- Manifest unreachable: the script warns and continues. The archive still came
  over TLS from the upstream org, which is what the pin already trusts.

GitHub publishes no checksum beside the asset. The archive holds a single
binary named `antigravity`, which upstream installs as `agy`, the name the
docs, the status line, and the entrypoint use.

The smoke test at the end runs `agy --version` with
`AGY_CLI_DISABLE_AUTO_UPDATE=true`, because that run happens at build time,
outside the session environment `spec.yaml` pins, and the CLI spawns its
self-updater on every start otherwise.

## Sparse settings

`agy` rewrites `settings.json` on exit keeping only the keys whose value
differs from the default it holds for the session. `enableTelemetry: false`
therefore disappears from the file after the very first run. Enclave copies a
settings template only when the target does not exist yet, so without help the
privacy opt-out would apply exactly once.

`entrypoint.d/setup.sh` merges the three defaults under the file on every
start (`defaults * .` in `jq`), which restores what was dropped and touches
nothing else. The same mechanism means a value you flip inside a session is
kept only while it differs from the CLI's default: flip it back and it
vanishes, and the entrypoint's value returns.

A `settings.json` that `agy` itself refuses to parse is left alone with a
warning rather than overwritten, so a broken file is repaired by hand.

## Telemetry paths

Three paths carry usage data out, and the extension treats each differently:

| Path | Handling |
|---|---|
| Clearcut, `https://play.googleapis.com/log`, from the analytics worker | Denied in `network.deniedDomains`. It sits under `googleapis.com`, which has to resolve for the agent backend, so it cannot simply be left out of the allowlist. Deny outranks allow, dnsmasq resolves by longest match, and the gateway's proxy refuses the host as well |
| The background self-updater, a `*.run.app` service | Denied in `network.deniedDomains`, and `AGY_CLI_DISABLE_AUTO_UPDATE=true` stops the process from being spawned. Without it every session tries to replace the binary the image was built with |
| `exa.analytics_pb.AnalyticsService/RecordCommandUsage` on the agent backend | Not blockable: it shares the gRPC connection the agent runs on. `enableTelemetry: false` is the only lever |

Upstream's terms state that interactions data is collected to improve the
product unless you opt out. Prompts, file contents, and command output go to
Google as part of normal operation regardless.

Two identifiers are generated on first run and then persist in the config
store for the life of that store: `~/.gemini/antigravity-cli/installation_id`
and a second installation UUID. Enclave keeps stores per tool and per project,
so they do not follow you across projects, and deleting the store resets them.

## Configuration layout

`agy` keeps two trees under `~/.gemini`, both inside the single config store
this extension declares:

| Path | Holds |
|---|---|
| `.gemini/antigravity-cli/` | `settings.json`, `keybindings.json`, conversations (SQLite, WAL), caches, logs, credentials, `installation_id` |
| `.gemini/config/` | What the CLI shares with the Antigravity IDE: `skills/`, `mcp_config.json`, `workflows/`, `global_workflows/`, per-project permissions |

Conversations live in SQLite databases opened in WAL mode (`conversations/`,
`conversation_summaries.db`), which is why `qemuStoreCacheMmap` is set.

`passthroughPaths` covers settings, keybindings, MCP servers, skills, and
workflows. Plugins and the hook configuration are deliberately left out: both
execute code the session did not build.

## The root-owned config directory

`skillsDir` is `.gemini/config/skills`, two levels below `configDir` and in a
different subtree than the settings file. Enclave prepares the store ahead of
the session for the parents of `settingsTarget` and the declared auth files
only, so when the skills bind mount is created, the container runtime creates
`~/.gemini/config` itself, as root. `agy` then fails on its first write below
it:

```
mkdir /home/agent/.gemini/config/projects: permission denied
```

This is [enclave#92](https://github.com/eclipse-enclave/enclave/issues/92),
fixed by [enclave#93](https://github.com/eclipse-enclave/enclave/pull/93).
Until that fix is in your Enclave, replace the directory in the store with one
you own after the first failed start, then start again:

```bash
store=~/.local/state/enclave/projects/<hash>/antigravity/config-store/default
podman unshare rm -rf "$store/config"   # docker: sudo rm -rf
mkdir -p "$store/config"
```

Ephemeral sessions (`--no-persist`) recreate the store, so they hit it again.

## Credentials

The Antigravity account session is not declared in `spec.yaml`: `agy` stores
it in the OS keyring, falling back without a D-Bus session bus to a file under
`~/.gemini/antigravity-cli/` whose name upstream does not document and which
is not discoverable in the binary. The config store persists it either way,
but `enclave auth import` and `enclave auth export` have nothing to copy.

`GEMINI_API_KEY` is declared with `serviceAuth`, so the container sees a
per-session placeholder and the gateway injects the real key as
`x-goog-api-key` on `generativelanguage.googleapis.com`. The CLI ignores the
key unless `modelProvider` is `gemini` in the settings.

## Egress

The rendered allowlist is `antigravity.google` plus the shared fragments for
Google, GitHub, npm, PyPI, Go, Rust, CDNs, and TLS. `antigravity.google` is
its own top-level domain and not covered by the Google fragment. The Google
fragment is wide, and most of it is needed: `accounts.google.com` and
`oauth2.googleapis.com` for sign-in and token refresh, `cloudcode-pa` and
`aicode.googleapis.com` for the agent backend, `generativelanguage` for
API-key mode, and `aiplatform`, `iamcredentials`, and `sts` for enterprise
Agent Platform, ADC, and workload identity.

The two denials in `spec.yaml` out-rank all of that. The updater host is
already unreachable under the deny-all allowlist and is denied by policy so
that widening the allowlist does not reopen it.

## Paths

| What | Where |
|---|---|
| Installed extension | `~/.config/enclave/extensions/tools/antigravity/` |
| Container config dir | `~/.gemini`, backed by the persistent config store |
| Settings template in image | `/usr/local/share/enclave/templates/antigravity-settings.json` |
| Host config override | `~/.config/enclave/tools/antigravity/` |
| Project config override | `~/.config/enclave/projects/<hash>/antigravity/config/` |
| Allowlist override | `~/.config/enclave/gateway-allowlists/antigravity.conf` |
| Gateway event log | `~/.local/state/enclave/projects/<hash>/antigravity/logs/network.log` |

## Debugging recipes

```bash
enclave exec --tool antigravity -- agy --version
enclave exec --tool antigravity -- cat ~/.gemini/antigravity-cli/settings.json   # what the entrypoint left behind
enclave exec --tool antigravity -- ls -la ~/.gemini                             # is config/ owned by you?
enclave network log --verdict deny        # what the allowlist refused
enclave network status                    # effective policy
```
