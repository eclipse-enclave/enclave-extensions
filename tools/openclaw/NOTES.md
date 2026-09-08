# OpenClaw extension: findings and caveats

Background for anyone running, changing, or debugging this extension. The README
is the short path to a working session; this file collects the usage caveats and
what the tool actually leaves on disk. Observations come from OpenClaw
`2026.7.1-2` on a real project store, so version-specific details will drift.

## Usage caveats, collected

- OpenClaw seeds files into your project directory. A first session in a scratch
  repo produced `AGENTS.md`, `BOOTSTRAP.md`, `HEARTBEAT.md`, `IDENTITY.md`,
  `SOUL.md`, `TOOLS.md`, `USER.md`, and `openclaw-workspace-state.json`, all in
  the workspace root. `entrypoint.d/setup.sh` points
  `agents.defaults.workspace` at `$PROJECT_DIR`, which under Enclave is your
  mounted host repository, so expect a dirty worktree. Try it in a scratch
  directory first, or ignore those paths deliberately.
- Keep provider keys in the host environment. The container sees a per-session
  `ENCLAVE_SECRET_<hex>` placeholder, so a key copied into `openclaw.json` is
  stale by the next start.
- Change configuration with `openclaw config set`, not by hand-editing
  `openclaw.json` in the config store. Every write is audited and the file is
  rotated, and OpenClaw records anomalies it notices about the previous state.
- `--no-yolo` does not undo yolo. The yolo branch of the entrypoint writes
  `tools.exec.security full` and `tools.exec.ask off` into the config, and there
  is no branch that puts them back, so a store that ran once with yolo keeps
  those values. Reset them yourself with `openclaw config set` if you want
  approvals back.
- The dashboard token lives in the config store, so it is stable across
  restarts and specific to that project store. It is printed at startup;
  `enclave exec --tool openclaw -- openclaw config get gateway.auth.token`
  retrieves it later.
- Host port 18789 is fixed by default, so a second concurrent session needs
  `-p 0:18789`.
- `openclaw gateway start` is not usable here. It manages a launchd or systemd
  service and rejects `--port`; the session wrapper runs `gateway run` in the
  foreground instead.
- `enclave continue` and `enclave resume` are not wired up. Resume from inside
  with `openclaw tui --session <key>`; `tui/last-session.json` in the store
  records the last key used.
- Messaging-channel connectors need their own allowlist domains and their own
  pairing flow. Nothing here sets that up.

## The session wrapper

`install.sh` writes `~/.local/bin/enclave-openclaw-session`, which starts
`openclaw gateway run --port "${OPENCLAW_GATEWAY_PORT:-18789}"` in the
background, polls `/dev/tcp` for up to 60 seconds, and then runs `openclaw tui`
in the foreground. It traps `EXIT` to kill the gateway, and it fails loudly with
a distinct message for the two failure shapes: the gateway exiting early, and
the gateway never listening within the timeout.

The gateway needs a non-loopback bind inside the container for Docker port
publishing to work, and it refuses that bind without auth
(`refusing to bind gateway ... without auth`). That is why
`entrypoint.d/setup.sh` runs `openclaw doctor --generate-gateway-token
--non-interactive` when no token exists yet. The `--non-interactive` part
matters: doctor is a full wizard by default and would block a session with no
TTY, including background runs.

A published port is reachable from other containers on the Docker bridge, not
just from host loopback. OpenClaw is better off than a tool with no auth of its
own, since the gateway requires the token, but the exposure itself is not
specific to any tool. The mechanics are written up in
[../dsh/NOTES.md](../dsh/NOTES.md), under bridge exposure.

## What the config store holds

`.openclaw` maps to the persistent per-project config store, so all of this
survives restarts:

| Path | What it is |
|---|---|
| `openclaw.json` | Live config, plus `.bak`, `.bak.1` through `.bak.3`, and `.last-good` rotations |
| `logs/config-audit.jsonl` | One record per config write: argv, pid, cwd, previous and next content hash and size, and a `suspicious` array |
| `identity/device.json`, `identity/device-auth.json` | This installation's device keypair and auth material |
| `devices/paired.json` | Paired clients. The TUI appears as `openclaw-tui` with role `operator` and scope `operator.admin` |
| `agents/main/sessions/` | Session and trajectory JSONL, including soft-deleted ones kept under a dated suffix |
| `state/openclaw.sqlite` | Plus `-wal` and `-shm`, so the store carries live SQLite artifacts |
| `tui/last-session.json` | Last session key per workspace |
| `skills/`, `plugin-skills/` | Managed skills, and plugin-shipped ones (`browser-automation`, `canvas` were present) |
| `skill-workshop/proposals.json` | Skill proposals the agent has drafted |
| `workspace-attestations/<hash>.attested` | Records the files OpenClaw generated in that workspace, each with a content hash |

The audit log is worth knowing about when something looks wrong: it shows
exactly which command rewrote the config. On the first write over the seeded
template it flagged `missing-meta-before-write`, which is expected rather than
alarming, since the template carries no `meta` block for it to compare against.

## Approvals and the yolo path

OpenClaw exposes approvals through config, not a CLI flag, so there is nothing
for `sandbox.yoloFlag` to set. `entrypoint.d/setup.sh` reads `ENCLAVE_YOLO`
instead and writes `tools.exec.security full` and `tools.exec.ask off`. Both
values were observed in a real store after a yolo session, alongside
`gateway.auth.mode: token`.

The one-way behavior noted above follows from that design: config persists, the
entrypoint only writes the yolo values, and nothing restores OpenClaw's own
defaults on a later `--no-yolo` run.

## First run

`templates/settings.json` seeds `gateway.port`, `gateway.mode` (the gateway
refuses to start without a mode), and `agents.defaults.model`. Together with the
non-interactive doctor run, that removes the onboarding wizard, so the first
session goes straight to the TUI. The wizard still records what it did in
`openclaw.json` under `wizard.lastRunAt`, `lastRunVersion`, `lastRunCommand`,
and `lastRunMode`, which is a quick way to see which version last touched a
store.

Switch models later with `openclaw configure --section model` in
`enclave shell --tool openclaw`. The seeded model is an Anthropic one, so a
session with only `OPENAI_API_KEY` on the host needs that change.

## Egress

`gateway-allowlist.conf` blocks everything by default and then includes the
shared fragments for Anthropic, OpenAI, Google, npm, GitHub, and TLS. npm and
GitHub are for the agent's work on the project. Anything else the agent reaches
for, including messaging connectors and plugin downloads, needs a domain added
with `--allow-domain` for one run, `enclave network add-domain <domain>
--global` host-wide, or a replacement file at
`~/.config/enclave/gateway-allowlists/openclaw.conf`.

## Paths

| What | Where |
|---|---|
| Installed extension | `~/.config/enclave/extensions/tools/openclaw/` |
| Container config dir | `~/.openclaw`, backed by the persistent config store |
| Host config override | `~/.config/enclave/tools/openclaw/` |
| Project config override | `~/.config/enclave/projects/<hash>/openclaw/config/` |
| Allowlist override | `~/.config/enclave/gateway-allowlists/openclaw.conf` |
| Gateway event log | `~/.local/state/enclave/projects/<hash>/openclaw/logs/network.log` |

## Debugging recipes

```bash
enclave exec --tool openclaw -- openclaw --version
enclave exec --tool openclaw -- openclaw config get gateway.auth.token
enclave shell --tool openclaw            # then: openclaw configure --section model
enclave network log --verdict deny        # what the allowlist refused
enclave network status                    # effective policy
```
