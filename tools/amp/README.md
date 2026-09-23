# Amp

Experimental. Sourcegraph's [Amp](https://ampcode.com/docs/cli) coding agent
CLI as an Enclave tool: the agent runs on the project directory inside the
usual container, with the read-write project mount and the DNS allowlist.

Amp is proprietary: a prebuilt binary with no public source repository and no
issue tracker, and a changelog at
[ampcode.com/chronicle](https://ampcode.com/chronicle). The documentation is
good, but everything here about on-disk paths, flags, and the wire format was
checked against the Linux build `0.0.1789660852-g000545` rather than taken
from it.

Usage caveats in one list, what the tool leaves in the config store, and the
findings behind the pinned settings are in [NOTES.md](NOTES.md). Read
[What leaves the container](#what-leaves-the-container) before pointing it at a
repository you care about: Amp is an account-based service and stores threads
server-side.

## Try it

```bash
export AMP_API_KEY=sgamp_...   # or log in with `amp login` inside the session
enclave tools add eclipse-enclave/enclave-extensions --name amp
cd /path/to/your/project
enclave --tool amp
```

The first run builds the image, then starts the Amp TUI. Everyday invocations:

```bash
enclave --tool amp -- -m high       # agent mode: low, medium, high, ultra
enclave --tool amp continue         # `amp last`, the most recent thread in this checkout
enclave --tool amp resume           # `amp threads continue`, the thread picker
```

`install.sh` fetches the binary from `static.ampcode.com`, verifies it against
the SHA-256 published beside it, and installs it as `~/.local/bin/amp`. It does
not run upstream's `curl https://ampcode.com/install.sh | bash`, which unpacks
into `~/.amp/bin`, symlinks the binary onto `PATH`, appends `PATH` lines to
shell profiles the image already provides, and leaves the self-update path in
place.

The install tracks the newest upstream build, and `check-update.sh` reports
that build to Enclave's update probe. Amp versions carry a build timestamp and
move several times a day, so expect this tool to report a stale image more
eagerly than the others. Pin a build by setting `AMP_VERSION`; `install.sh` and
`check-update.sh` both read it, so the probe reports the build the rebuild will
actually deliver.

## Authentication

Two ways in:

- **`amp login`.** The CLI uses a device-code flow: it prints a
  `https://auth.ampcode.com/device?user_code=...` URL and a code, and you
  confirm both in your host browser. No callback port has to be published, so
  unlike the OAuth tools this one needs no `oauthPorts` mapping. The token lands
  in the selected auth store and survives the session. Named identities work
  with `enclave --tool amp --auth-name <name>`; Amp's account-local data stays
  with that identity so switching names cannot reuse another login. `amp
  logout` removes the selected identity's token.
- **`AMP_API_KEY`.** An access token from
  [Settings, Security](https://ampcode.com/settings/security), prefixed
  `sgamp_`. It authenticates on its own with no local login state. The session
  token `amp login` stores is *not* usable here: it expires within the hour and
  cannot be refreshed from an environment variable.

`--auth-name` selects stored login state; it does not scope or suppress an
`AMP_API_KEY` supplied by the host or Enclave's persisted env store. If you
want the selected login to take precedence, run with `--no-api-key`.

Amp authenticates with `Authorization: Bearer <token>`, which `spec.yaml`
declares, so Enclave holds the key on the host and the gateway attaches it to
requests for `ampcode.com`. The container only sees a per-session placeholder.

## What leaves the container

The sandbox contains the agent's *execution*: the loop, the tool calls, the
edits, and the shell commands all run in the container, since `amp --executor
local` is the default. It does not contain the conversation. Amp is an
account-based service: prompts, file contents, and command output go to Amp's
backend as a matter of normal operation, threads are stored server-side, and
their default visibility is workspace-wide, with admin access for workspace
management. There is no local-only mode to switch on. Set a per-repository
default with `amp threads visibility`, or start a session with
`-- --visibility private`.

Three things that would reach past the container are disabled by default:

| Disabled | Why |
|---|---|
| `AMP_REMOTE_CONTROL_TERMINAL=0` (`spec.yaml`) | Grants ampcode.com terminal access to a thread opened on another client. Amp documents `0` as disabled; an explicit `--remote-control-terminal` argument can still opt in |
| `amp.remoteThreadCreation.enabled: false` (template and startup setup) | Lets ampcode.com open new threads in a TUI running here. It is already the upstream default and is re-asserted on every start |
| `static.ampcode.com` denied (`spec.yaml`) | `amp update` would replace the binary the image was built with |

Two more move work outside the sandbox on request, and stay available because
they are explicit: `amp -ox` (and `--executor orb`) runs the thread on Amp's
servers instead of in the container, and `amp --no-tui --runner-id <id>` turns
the session into an executor for threads created elsewhere.

The template also turns off the `Amp-Thread:` and `Co-authored-by:` commit
trailers, so an agent's thread URL does not end up in the repository's history.
Delete those two keys from `templates/settings.json` to get them back.

## Approvals

Amp still accepts `--dangerously-allow-all` for compatibility even though it
omits the flag from `--help`; `spec.yaml` supplies it in Enclave's default yolo
mode. `entrypoint.d/setup.sh` also writes the matching
`amp.dangerouslyAllowAll` setting on every start so persisted state cannot leak
between yolo and no-yolo sessions.

The setting alone cannot enforce `--no-yolo`: Amp gives a repository's
`.amp/settings.json` higher precedence, and its ordinary file-editing tool does
not require approval. The extension therefore ships a system plugin at
`plugins/enclave-approvals.ts`. In no-yolo mode its `tool.call` hook asks before
every tool call and fails closed when no approval UI is available. The
entrypoint links the plugin from the root-owned extension tree and refuses a
same-named project plugin that would shadow it. In yolo mode the plugin does
not register the hook, leaving Amp and any other policy plugins unchanged.

## State and egress

Under shared auth, Amp's XDG data directory lives directly in the selected
auth store, so the login token, device id, and local thread state follow
`--auth-name`. Under project auth it lives in the persistent project config
store's Amp-only XDG root. Amp keeps its settings and global skills in
`~/.config/amp` upstream; `entrypoint.d/setup.sh` redirects both into the
project config store, so `settings.json` and managed skills persist too.
[NOTES.md](NOTES.md) has the layout.

`gateway-allowlist.conf` allows `ampcode.com` (the API, the web app, and
`auth.ampcode.com` for device login) and `ampworkers.com` (the WebSocket workers
carrying live thread updates), plus GitHub and the usual package registries so
the agent can work in the project. `static.ampcode.com` is denied, since
`ampcode.com` would otherwise cover it: dnsmasq matches subdomains, and deny
outranks allow.

No model provider hosts are allowlisted. Amp proxies inference through its own
backend, so the whole egress surface of a session is those two domains. Widen
it for one run with `--allow-domain`, host-wide with `enclave network
add-domain <domain> --global`, or replace it with
`~/.config/enclave/gateway-allowlists/amp.conf`. To see where the agent
actually went, read `enclave network log` (`--follow`, `--verdict deny`,
`--summary`, `--since session`).

## Not supported

- Host config passthrough. It resolves below `hostConfigDir`, which is the
  store, `~/.local/share/amp`. The host files worth passing through,
  `settings.json` and `skills/`, live in `~/.config/amp`, outside it, so
  `spec.yaml` declares no `passthroughPaths`.
- JSONC in the settings file. Amp accepts comments, `jq` does not, and
  `entrypoint.d/setup.sh` rewrites the file with `jq` on every start. A file
  with comments makes startup fail rather than running with the update,
  remote-creation, or permission defaults unenforced.
- Bring-your-own-key providers (`amp config model-providers`). Whether the CLI
  then calls provider APIs directly, which the allowlist does not cover, or
  keeps routing through Amp's backend was not verified here. If BYOK requests
  fail in a session, that is the first thing to check.
