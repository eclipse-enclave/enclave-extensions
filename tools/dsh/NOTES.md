# dsh extension: findings and caveats

Background for anyone running, changing, or debugging this extension. The README
is the short path to a working session; this file collects every usage caveat in
one list and then records what we learned building it, including the dead ends.
Everything here was observed against
`@deepseek-ai/dsh@0.1.1-rc.2` and the dependency versions it pins, so upstream
file and line references are version-specific by nature.

## Usage caveats, collected

The traps you can walk into during a normal session, in one place. Each is
explained further down or in the README.

- Leave the API-key field blank on every provider route in the UI. The
  inherited environment is a read-only credential layer and `credentials.set`
  throws rather than silently dropping a write that would shadow it, so typing
  a key in fails for `deepseek`, `anthropic`, `openai`, and `google` alike.
- On the `google` route, typing a key fails permanently, not just once. dsh
  records `apiKeyEnv: GOOGLE_API_KEY` in `settings.yaml` from the route id and
  keeps using it, so the working `GEMINI_API_KEY` path stays broken until you
  hand-edit `settings.yaml` in the config store.
- Keep keys on the host. Anything you write inside the container, in
  `.credentials.yaml` or a `.env`, captures a per-session placeholder that is
  stale by the next start.
- Do not edit `~/.dsh/cordis.patch.yml` from inside. It is rewritten on every
  start. Use `~/.config/enclave/tools/dsh/cordis.patch.yml` or the per-project
  path instead.
- The `read-only` and `workspace-write` presets appear in the UI and fail on
  every command, because no sandbox backend works in this container.
- A permission default saved in the UI's General settings outranks the template
  for later sessions, including the two presets that cannot work.
- Do not leave a session running next to containers you do not trust. The UI has
  no authentication and the bridge reaches it.
- Pick the project from the entry linked into `$HOME`, and let the UI create the
  workspace. Hand-editing `storages/` corrupts a registry that fails loud.
- A second concurrent session needs `-p 0:3080`, since the first one holds host
  port 3080.
- Switching `web_search` to Perplexity or Exa needs that provider's host added
  with `--allow-domain`. Only DeepSeek's is declared.
- `enclave tools update dsh` refreshes this extension from git. It does not bump
  the pinned dsh version unless `install.sh` changed here, and the new content
  hash is what triggers the image rebuild on the next run.

## What dsh is

An agent harness from DeepSeek AI where everything is a plugin, built on
[Cordis](https://github.com/cordiverse/cordis). Published as `@deepseek-ai/dsh`
(bin `dsh`), engines `^22.19.0 || >=24.0.0`, which fits the Node 24 that
Enclave's base image ships. Upstream calls it a developer preview and promises
compatibility-breaking changes, which is why `install.sh` pins an exact version
rather than tracking latest.

Surfaces:

| Command | What it is |
|---|---|
| `dsh web` | Alias of `--profile web`. Browser UI, bound to `127.0.0.1:3080` by default. |
| `dsh --profile headless "task"` | One shot: run, print the final answer, exit. Opens no port. |
| `dsh plugin --profile <name> <pnpm args>` | Plugin management. Forwards to `pnpm`, which is not on `PATH` here. |

There is no in-box TUI. The `tui` profile in upstream docs assumes a
third-party plugin (`github:deepseek-harness/turtle-ui`), so the web server is
this extension's foreground process. `dsh web` accepts `--host`, `--port`,
repeatable `--trusted-host`, and `--no-open`.

## Configuration model

`$DSH_HOME` defaults to `~/.dsh` and holds:

- `settings.yaml`: providers and models, written by the UI at runtime.
- `.credentials.yaml`: write-only credential store, populated by the UI.
- `cordis.patch.yml`: home-level plugin-tree patch layer.
- `profiles/<name>/`: `web` and `headless` initialize from shipped templates on
  first use.
- `storages/`: durable state, including the workspace registry.

Composition order is bundle patches, then the profile's `cordis.patch.yml`, then
the home-level one, then any `--patch` overlay. Later wins, and a patch replaces
the targeted row's whole `config` instead of deep-merging it, which is why
`templates/cordis.patch.yml` restates every key of the rows it touches.
`dsh web --dump-config` prints the composed tree and names the file that
supplied each row.

## The bind, and what verified it

The composed tree shows `webserver` with `host: 0.0.0.0`, `port: 3080`,
`inject: [webStartup]` preserved, and no unmatched-patch-target warning. dsh's
own startup line corroborates the bind: it prints
`dsh web: http://127.0.0.1:3080 (LAN: http://172.17.0.2:3080)`, and it only
advertises a LAN address when bound non-loopback.

Every `/api` request passes `isTrustedApiRequest`
(`packages/client/connection/src/api-request-trust.ts`), which accepts a
loopback `Host` header or a configured `trustedHosts` authority and rejects
`Sec-Fetch-Site: cross-site` or a mismatched `Origin`. A host browser pointed at
`http://localhost:<host_port>` sends a loopback name, so it passes with no
`--trusted-host` flag even though the socket landed on a `0.0.0.0` bind.
Measured through the published port: `/api` returns 404 for a loopback `Host`
(no such route) and 403 for `Host: evil.example`.

That fence is not a defense against the bridge exposure below. A caller on the
bridge sends whatever `Host` it likes.

## Bridge exposure, in detail

The README states the consequence. The mechanics:

- Docker port publishing requires the in-container service to accept
  connections on the container's own address, because that is where
  `docker-proxy` connects from. A loopback-only bind cannot be published.
- Enclave creates no dedicated Docker network for session containers, so they
  land on the default bridge, and any other container there can connect to
  `<container-ip>:3080` directly, bypassing the host publish entirely.
- Under network isolation the session container shares the gateway sidecar's
  network namespace and has no bridge IP of its own. `docker inspect` on the
  session container returns empty networks; read the address from inside with
  `enclave exec --tool dsh -- hostname -i` instead.
- Verified with `docker run --rm --network bridge busybox wget -qO- http://172.17.0.2:3080/`,
  which returned the UI.

Not fixable in an extension. Any address `docker-proxy` can reach is reachable
from bridge peers by construction, and application-level `Host` checks do not
help. The fixes belong in Enclave: a per-session or per-project Docker network,
or restricting ingress in the gateway netns to the host-facing source.

## No usable sandbox backend

dsh confines bash and filesystem mutations itself, preferring `bwrap` and
falling back to Landlock, and it fails closed when neither works:

```
sandbox mode "<mode>" is requested but no sandbox backend is usable on this
host; refusing to run the command unconfined.
```

In this container `bubblewrap 0.11.0` is installed but `--ro-bind / / --dev
/dev` fails with `No permissions to create new namespace`, from the host
kernel's unprivileged-userns policy, and `/sys/kernel/security/lsm` is
unreadable. So every confining mode refuses every command, and pinning
`danger-full-access` states the truth rather than promising containment that
does not exist.

Upstream's own defaults, for reference:

| `DSH_PERMISSION_MODE` | sandbox | approval |
|---|---|---|
| unset | `workspace-write` | `ask` |
| `read-only` | `read-only` | `ask` |
| `danger-full-access` | `danger-full-access` | `never` |

`danger-full-access` is the only row that needs no backend, which is what makes
it the workable choice here.

## Why configuration travels through the patch template

`entrypoint.d/setup.sh` runs. A probe `echo` appeared in `docker logs` as the
right user with `ENCLAVE_YOLO=1` visible. But variables it exports, including
`DSH_HOME` and `DSH_PERMISSION_MODE`, are absent from the live `dsh` process
environment. `ENCLAVE_YOLO` reaches the process only because it is a
container-level variable, not a shell export.

This affects any tool extension that configures through environment exports,
and it is an Enclave-side issue rather than a dsh one. The workaround here is
`templates/cordis.patch.yml`, which is recomposed on every start and reads
`ENCLAVE_YOLO` directly.

dsh's preset table couples the sandbox mode and the approval policy and ships no
entry pairing `danger-full-access` with `ask`, so a `--no-yolo` session composed
a state matching no preset and the plugin refused to boot with `composed sandbox
and approval defaults match no preset`. Hence the extra `unconfined-ask` preset
and an explicit `defaultPreset`
(schema: `packages/interaction/permission-presets/src/index.ts`).

## Two authoring traps

- A `!!js` expression containing `": "` must be quoted, or YAML parses it as a
  nested mapping and dsh dies at boot. The base bundle quotes it for the same
  reason.
- `enclave validate-extensions` validates `spec.yaml` and never looks inside
  `templates/`, so a malformed patch surfaces only as a container that dies on
  startup. Parse the template yourself and assert that every composable
  (mode, approval) pair matches a preset.

## Credentials, verified rather than inferred

Resolution order is inherited environment, then `$DSH_HOME/.credentials.yaml`,
then the invoking directory's `.env`, then `$DSH_HOME/.env`. Environment-first
is what makes the extension work at all: Enclave injects a per-session
placeholder as an env var and the gateway swaps in the real key on declared
hosts, with no glue in between.

- Header names were read off the pinned `@earendil-works/pi-ai@0.82.1` from
  npm: `x-api-key` for Anthropic, `Authorization: Bearer` for OpenAI,
  `x-goog-api-key` for Google. The residual risk is an upstream pi-ai bump
  changing a route id or a catalog default.
- DeepSeek's `web_search` sends the key in both `x-api-key` and `authorization`.
  It works because substitution applies to any header carrying the placeholder,
  while `valueFormat` applies only to the named one.
- Release is fail-closed against a tampering agent: the gateway's
  `rewriteHeaders` denies a request that carries a placeholder to a host outside
  that secret's rule hosts.
- A key typed into the UI derives its reference from the route id
  (`${route.toUpperCase()}_API_KEY`, `store.ts`), which is why `google` yields
  `GOOGLE_API_KEY` and permanently breaks that route. See the README.
- `web_fetch` is disabled unless a patch layer enables it.

## Odds and ends

- Skills work despite the web bundle disabling the host-plane
  `skill-filesystem` row: the agent presets re-register it, so `~/.dsh/skills`
  is scanned as the `user-dsh` root.
- The workspace choice cannot be preseeded. The registry is runtime storage
  reachable only through `ctx.workspaceRegistry.create(path)`, with no config
  seam. Do not hand-write the storage JSON either: the registry writes an
  explicit pending-mutation marker and fails loud on unexplained corruption.
- The rendered allowlist is wider than dsh needs. `google.conf` earns nothing,
  since `generativelanguage.googleapis.com` already arrives as a credential
  release host, and it adds `google.com`, `googleapis.com`, `gstatic.com`, and
  `googleusercontent.com`. `github.conf` drags in three `githubcopilot.com`
  hosts. Trimming this means shipping a narrower `gateway-allowlist.conf`
  instead of including the shared fragments.
- Persistence leaves no SQLite WAL artifacts behind in `$DSH_HOME`.
- A `check-update.sh` would make version bumps deliberate: Enclave runs it in a
  containerized probe and its fingerprint gates automatic rebuilds. This
  extension does not ship one yet, so the pin is updated by hand.

## Paths

| What | Where |
|---|---|
| Installed extension | `~/.config/enclave/extensions/tools/dsh/` |
| Container config dir | `~/.dsh` (`$DSH_HOME`), backed by the persistent config store |
| Settings template in image | `/usr/local/share/enclave/templates/dsh-cordis.patch.yml` |
| Host config override | `~/.config/enclave/tools/dsh/` |
| Project config override | `~/.config/enclave/projects/<hash>/dsh/config/` |
| Allowlist override | `~/.config/enclave/gateway-allowlists/dsh.conf` |
| Gateway event log | `~/.local/state/enclave/projects/<hash>/dsh/logs/network.log` |

## Debugging recipes

```bash
enclave exec --tool dsh -- dsh --version
enclave shell --tool dsh                     # then: dsh web --dump-config
enclave exec --tool dsh -- ss -ltn           # did it bind 0.0.0.0:3080?
enclave exec --tool dsh -- hostname -i       # the netns address, for bridge probes
enclave network status                       # effective policy
enclave network print --tool dsh             # rendered dnsmasq config
```
