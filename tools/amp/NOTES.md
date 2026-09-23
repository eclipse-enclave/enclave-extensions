# Amp extension: findings and caveats

Background for anyone running, changing, or debugging this extension. The README
is the short path to a working session; this file collects the usage caveats,
what the tool leaves on disk, and the checks behind the pinned settings.
Observations come from the Linux build `0.0.1789660852-g000545`, so
version-specific details will drift. Upstream ships no source, so nothing here
was read off code: it was observed on disk and on the wire.

## Usage caveats, collected

- The conversation leaves the container. Prompts, file contents, and command
  output go to Amp's backend, threads are stored server-side, and their default
  visibility is workspace-wide. Set `amp threads visibility` per repository or
  pass `-- --visibility private`. There is no local-only mode.
- Keep `AMP_API_KEY` in the host environment. The container sees a per-session
  placeholder, so a key copied into `settings.json` is stale by the next start.
- The token `amp login` stores is not usable as `AMP_API_KEY`: it expires
  within the hour and cannot be refreshed from an environment variable. Use an
  access token from Settings, Security, prefixed `sgamp_`.
- `--auth-name` selects Amp's stored account state, but an `AMP_API_KEY` from
  the host or Enclave's persisted env store remains active across names. Add
  `--no-api-key` when selecting a login identity if both are present.
- Amp still accepts `--dangerously-allow-all` even though the flag is hidden
  from `--help`. Yolo mode supplies that flag, and `entrypoint.d/setup.sh`
  writes the matching setting in both directions. Under `--no-yolo`, the
  `enclave-approvals` system plugin asks before every tool call; this is the
  enforcement path because repository settings outrank the user setting.
- Keep `settings.json` plain JSON. Amp accepts JSONC, `jq` does not, and the
  entrypoint rewrites the file with `jq`. A file with comments makes startup
  fail rather than leaving update, remote-creation, or permission defaults
  unenforced.
- `amp -ox`, `--executor orb`, and `amp --no-tui --runner-id <id>` move work
  outside the sandbox on purpose. They are left available because they are
  explicit; do not treat them as contained.
- `enclave tools update amp` refreshes this extension from git. The pinned
  build, if you set one, changes only when `install.sh` changes here.
- The update probe fires often. Amp cuts builds several times a day, and
  `check-update.sh` reports the newest one, so the image is marked stale more
  often than for tools with releases.

## Installing from release storage

`install.sh` downloads `amp-linux-<arch>.gz` from `static.ampcode.com/cli/<version>/`
and the SHA-256 published beside it. The checksum covers the uncompressed
binary, so the script decompresses first and verifies after. `latest` resolves
through `cli-version.txt` on the same host.

The first smoke test at the end runs `amp --version` against a throwaway
settings file that sets `amp.updates.mode` to `disabled`. Update mode defaults
to `auto`, and the image has no settings file yet at that point, so a bare
`amp --version` could replace the build whose checksum was just verified. A
second local-only `amp plugins exec` check loads the no-yolo policy plugin
against the installed build so a plugin API incompatibility fails the image
build.

## Configuration layout

Amp spreads its state over three XDG directories, and only one of them can be
the Enclave config store:

| Path | Holds upstream | Here |
|---|---|---|
| `$XDG_DATA_HOME/amp/` | `secrets.json` (login token), `device-id.json`, local thread state | The selected auth store under shared auth; the Amp-only project config store under project auth |
| `~/.config/amp/` | `settings.json`, `skills/`, system plugins | Settings and skills are redirected into the store; the approval plugin is linked read-only from the extension |
| `~/.cache/amp/` | `logs/cli.log` | Left alone, not persisted |

The config store is mounted at `~/.local/share/enclave-amp`. Under shared auth,
`entrypoint.d/setup.sh` points `XDG_DATA_HOME` directly at the selected
`~/.enclave-auth` mount, so Amp reads and atomically rewrites
`~/.enclave-auth/amp/secrets.json` without breaking an auth-file symlink. Its
device and local thread state follow the same named identity. Under project
auth there is no shared auth mount, so Amp uses that config store as its XDG
data home. On first start
after upgrading, an old shared-store `secrets.json` is copied to
`amp/secrets.json`, and the old config-store settings file is moved under the
new `amp/` directory.

The settings file remains project configuration in both modes:
`entrypoint.d/setup.sh` exports `AMP_SETTINGS_FILE`, Amp's documented override,
pointing at `~/.local/share/enclave-amp/amp/settings.json`, which is also where Enclave
copies the template.

Managed skills are composed into `~/.local/share/enclave-amp/amp/skills`, since Enclave
requires `skillsDir` below `configDir`, and the same script links
`~/.config/amp/skills`, the path Amp actually searches, at it. Amp follows that
symlink (checked), and `amp.skills.path` stays free for directories you want to
add yourself. A feature extension that ships skills therefore reaches this tool
too. Anything real already sitting at `~/.config/amp/skills` is left alone.

The setup script pins `XDG_CONFIG_HOME=~/.config` and links the system plugin
path `~/.config/amp/plugins/enclave-approvals.ts` to the copy in the root-owned
extension tree. Pinning the root keeps a passed environment value from moving
the policy into the writable project. Approval mode is derived from the final
Amp argv and exported after project `.env` values are loaded, so a repository
cannot spoof `ENCLAVE_YOLO=1` to disable the hook. Amp gives a same-named
project plugin higher precedence, so no-yolo startup refuses such a collision.
Once loaded, the system plugin's `tool.call` hook makes every attempted edit
or command pass through the approval UI, including an attempt to create a
shadowing plugin or change `.amp/settings.json`. With no approval UI it returns
an error instead of allowing the call.

Both halves of that ride on the process environment and on argv, which
`tools/dsh` warns is unreliable ("variables it exports ... are absent from the
live process environment ... this affects any tool extension that configures
through environment exports"). Checked against the Enclave this runs on
(`3e28d12`): `entrypoint.sh` sources each `entrypoint.d/*.sh` into its own
shell, so an export lands in that shell and `"$@"` there is the whole container
command, yolo flag included; it then starts the agent with `exec "$@"` through
a wrapper that itself ends in `exec "$@"`. Nothing on that path drops or
rewrites the environment, so both channels hold and dsh's warning is broader
than the mechanism supports. The one gap is the session monitor, which starts
the agent under `tmux new-session`: a fresh server inherits this environment,
but a server already listening on the `enclave` socket would hand the agent its
own, and the shipped tmux config sets no `update-environment`. That needs a
pre-existing server in the same container, which a normal start does not have.

Amp also reads `~/.claude/skills`, `~/.config/agents/skills`,
`~/.agents/skills`, and the project's `.agents/skills` and `.claude/skills`;
`amp.skills.disableClaudeCodeSkills` and `amp.skills.disableGlobalAgentsSkills`
turn those off.

## Credentials and the gateway

Amp authenticates with `Authorization: Bearer <token>`. The `serviceAuth` entry
in `spec.yaml` was confirmed against `POST ampcode.com/api/internal`: the
container carries the placeholder, the gateway swaps in the real key. The
device-code login needs no callback port, so there is no `oauthPorts` mapping.

Verified for HTTP only. Whether the WebSocket connection to
`production.ampworkers.com` authenticates the same way is untested, so a
session run with the key suppressed from the container may lose live thread
updates while ordinary requests keep working.

`spec.yaml` declares `amp/secrets.json` as the provider's auth file and a
`file_exists` check on it, so `enclave auth import` and `enclave auth export`
can carry a login between hosts, and Enclave can tell a logged-in store from an
empty one.

## Remote control, disabled by default

Two Amp features let ampcode.com reach into a running CLI, and the extension
disables both by default:

- `AMP_REMOTE_CONTROL_TERMINAL=0` in the spec's environment block. This grants
  the web app terminal access to a thread opened on another client. Amp
  documents `0` as disabled; an explicit `--remote-control-terminal` argument
  takes precedence and can still opt in.
- `amp.remoteThreadCreation.enabled: false` in the template and startup setup.
  This lets the web app open new threads in a TUI running here. It is already
  the upstream default and is re-asserted on every start.

`amp.updates.mode: disabled` is set in the template and re-asserted by the
entrypoint on every start, because `amp update` would replace the binary the
image was built with. `static.ampcode.com` is denied on top of that in
`network.deniedDomains`, so a widened allowlist does not reopen the path.

## Egress

The rendered allowlist is `ampcode.com` and `ampworkers.com` plus the shared
fragments for GitHub, npm, PyPI, Go, Rust, CDNs, and TLS. No model provider
appears, because Amp proxies inference through its own backend. That makes the
egress surface smaller than for the built-in agent tools, but it also means
every request, including the ones carrying your code, terminates at Amp.

BYOK is not modelled. Amp supports bringing your own provider keys and
subscriptions, and whether the CLI then calls the provider directly or still
routes through Amp needs an account with a key attached to observe.

## Persistence details

The binary bundles SQLite and keeps local thread state in the store.
`qemuStoreCacheMmap` is set defensively: which database files it opens, and
whether they use WAL, needs an account to observe. The flag is required for WAL
databases under the QEMU backend and harmless otherwise.

## Paths

| What | Where |
|---|---|
| Installed extension | `~/.config/enclave/extensions/tools/amp/` |
| Container config dir | `~/.local/share/enclave-amp`, backed by the persistent project config store |
| Shared Amp data dir | `~/.enclave-auth/amp`, backed by the selected shared auth identity |
| Settings file in the store | `~/.local/share/enclave-amp/amp/settings.json`, via `AMP_SETTINGS_FILE` |
| Settings template in image | `/usr/local/share/enclave/templates/amp-settings.json` |
| No-yolo policy plugin | `~/.config/amp/plugins/enclave-approvals.ts`, linked from the extension |
| Allowlist override | `~/.config/enclave/gateway-allowlists/amp.conf` |
| Gateway event log | `~/.local/state/enclave/projects/<hash>/amp/logs/network.log` |

## Debugging recipes

```bash
enclave exec --tool amp -- amp --version
enclave exec --tool amp -- cat ~/.local/share/amp/settings.json   # what the entrypoint left behind
enclave exec --tool amp -- amp threads list
enclave network log --verdict deny        # what the allowlist refused
enclave network status                    # effective policy
```
