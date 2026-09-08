# OpenClaw

Experimental. [OpenClaw](https://openclaw.ai/) as an Enclave tool: the gateway
daemon, the terminal UI, and the browser dashboard in one session.

Usage caveats in one list, plus what the tool leaves in the config store, are in
[NOTES.md](NOTES.md). Read the first section before pointing it at a repository
you care about: OpenClaw seeds Markdown files into the workspace.

## Try it

```bash
export ANTHROPIC_API_KEY=...   # or OPENAI_API_KEY, or GEMINI_API_KEY
enclave tools add eclipse-enclave/enclave-extensions --name openclaw
cd /path/to/your/project
enclave --tool openclaw
```

The first run rebuilds the image, then drops you into the TUI. The dashboard is
at http://localhost:18789, with the token printed at startup. This extension
seeds `anthropic/claude-sonnet-5` as `agents.defaults.model`; switch with
`openclaw configure --section model` inside `enclave shell --tool openclaw`.

Keep provider keys in the host environment, which is what the export above does.
Writing one into `openclaw.json` breaks on the next session. See
[Credentials](#credentials).

## The session

Container port 18789 is published to host loopback with the label
`OpenClaw Dashboard`. The default `hostAllocation: fixed` maps it to host port
18789, so two concurrent sessions contend for it. Start extra ones with
`-p 0:18789`.

The gateway refuses a non-loopback bind without auth, so
`entrypoint.d/setup.sh` generates a token on first start and prints it. Read it
again later with:

```bash
enclave exec --tool openclaw -- openclaw config get gateway.auth.token
```

There is no onboarding wizard to click through. `templates/settings.json` seeds
`gateway.mode`, without which the gateway refuses to start, plus a default
model, and setup runs doctor with `--non-interactive`.

`enclave-openclaw-session` starts `openclaw gateway run`, waits for it to
listen, then runs `openclaw tui` in the foreground. The wrapper traps `EXIT` and
kills the gateway, so the daemon never outlives the session. (`gateway start`
manages a launchd or systemd service, which does not exist in the container, and
it rejects `--port`.)

## Approvals

OpenClaw has no yolo CLI flag, so `entrypoint.d/setup.sh` reads `ENCLAVE_YOLO`
instead of `sandbox.yoloFlag`. With yolo on, which is Enclave's default, it sets
`tools.exec.security full` and `tools.exec.ask off`. When setting `--no-yolo`,
OpenClaw's own defaults apply.

## Credentials

`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GEMINI_API_KEY` are declared with
`serviceAuth`, so the container only ever sees a per-session
`ENCLAVE_SECRET_<hex>` placeholder and the gateway swaps in the real key on the
declared hosts. Keep the keys in the host environment. A key written into
`openclaw.json` breaks on the next start, because the placeholder changes every
session.

## State and egress

`.openclaw` lives in the persistent config store, so config, sessions, and
Markdown memory survive restarts.

`gateway-allowlist.conf` allows the three model providers plus npm, GitHub, and
TLS. Widen it for one run with `--allow-domain`, host-wide with
`enclave network add-domain <domain> --global` (running gateways reload), or
replace it with `~/.config/enclave/gateway-allowlists/openclaw.conf`, which is
baked into the gateway image and needs a session restart. To see where the agent
actually went, read `enclave network log` (`--follow`, `--verdict deny`,
`--summary`, `--since session`), or start the session with
`--network-log=requests` for per-request events.

## Not supported

- `enclave continue` and `enclave resume`. Use `openclaw tui --session <key>`.
- `enclave auth import` and `enclave auth export`.
- `openclaw tui --local`.
- Messaging-channel connectors, which need their own allowlist domains and
  pairing flow.
