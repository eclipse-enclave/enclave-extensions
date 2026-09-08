# DeepSeek Harness

Experimental.
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`) as
an Enclave tool, with its browser UI as the session surface. Upstream is a
developer preview that promises breaking changes, so `install.sh` pins
`@deepseek-ai/dsh@0.1.1-rc.2` and everything below describes that version.

Deeper findings, the measurements behind the caveats, and the dead ends are in
[NOTES.md](NOTES.md).

## Try it

```bash
export DEEPSEEK_API_KEY=... # or ANTHROPIC_API_KEY=..., or OPENAI_API_KEY
enclave tools add eclipse-enclave/enclave-extensions --name dsh
cd /path/to/your/project
enclave --tool dsh
```

DeepSeek is not required. Export `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or
`GEMINI_API_KEY` instead, or several at once, and pick the matching provider in
the UI. Set the API keys in the host environment, not inside the container and not in
the UI.

The first run rebuilds the image and starts the UI at http://localhost:3080.
Two things to do there, both dsh's own onboarding, neither preseedable:

1. Pick your project from the workspace list. `entrypoint.d/setup.sh` links it
   into `$HOME` under its own name, so it shows up in the first listing. The
   choice persists per project.
2. Add the provider route for your key (`deepseek`, `anthropic`, `openai`, or
   `google`) and **leave the API-key field blank.** Enclave puts a per-session
   placeholder in the container environment and the gateway swaps in the real
   key on the way out, so a blank route finds it on its own. Typing a key in
   fails, and on the `google` route it fails permanently. See
   [Credentials](#credentials).

One caveat before you leave a session running: the UI has no authentication.

## Security

**The web UI has no authentication, and other containers can reach it.**

On the host side the port is published to `127.0.0.1` only, so no other machine
on your network gets in. Inside the container the bind is `0.0.0.0`, which
Docker port publishing requires, and that address is reachable from any
container on the same Docker bridge. Verified: a throwaway `busybox` container
on the default bridge fetched the UI at `172.17.0.2:3080`.

So the agent can be driven, with no credential of any kind, by any local process
or user on the host and by any container on the default bridge, including ones
you did not start. What that grants is full: an unconfined agent with read-write
access to the mounted project and to every allowlisted domain.

Enclave creates no dedicated Docker network for session containers, so this is
not specific to this tool. It applies to anything that publishes a port, and it
is worse here only because dsh has no equivalent of OpenClaw's gateway token.
Treat a running session the way you would any unauthenticated local service, and
do not leave one up alongside untrusted containers.

## Credentials

`DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GEMINI_API_KEY`
are declared. Provide them in the host environment or a layered secrets file. In
restricted mode, the default, the container sees only a per-session placeholder
and the gateway swaps in the real value on the declared hosts; unless you run
`--allow-all-network` in which case there is no Enclave gateway and the raw value
is injected instead.
The gateway substitutes into any header carrying the placeholder, which is why
DeepSeek's `web_search` works even though it sends the key twice. Nothing else
needs wiring: dsh reads credentials from the inherited process environment
first, ahead of `$DSH_HOME/.credentials.yaml` and any `.env`.

That environment is a read-only layer from inside the container, and
`credentials.set` throws on any write that would shadow it, so typing a key into
the Models page fails for every provider above. A route saved with a blank key
is reference-free and defers to the provider's own environment discovery, which
is what picks up the placeholder.

The `google` route is the sharp edge. dsh derives a UI-typed key's reference
from the route id (`google` becomes `GOOGLE_API_KEY`), not from the declared
`GEMINI_API_KEY`, and records that derivation permanently as `apiKeyEnv` in
`settings.yaml`. From then on every request fails on the missing reference, and
the working `GEMINI_API_KEY` path stays broken until you hand-edit
`settings.yaml` in the config store. `GEMINI_API_KEY` is the name pi-ai's own
Gemini provider discovers, which is why it is the declared one.
`GOOGLE_API_KEY` is deliberately not an alias, because it commonly holds an
unrelated Google Cloud key that would then be released to Google's endpoint.

## Permission mode

dsh confines commands with `bubblewrap` or Landlock and fails closed when
neither works. `bwrap` is in the base image but cannot create a user namespace
here, and `/sys/kernel/security/lsm` is unreadable, so any confining mode would
refuse every command. `templates/cordis.patch.yml` therefore pins
`sandbox-policy.mode` to `danger-full-access`, which leaves the container and
the gateway allowlist as the real boundary. The `read-only` and
`workspace-write` presets stay listed in the UI, and picking either will fail on
every command.

Approvals still follow yolo. A plain `enclave --tool dsh` runs with approvals
set to `never`; `--no-yolo` sets them to `ask`, so the agent prompts before
acting. It cannot restore file confinement, which was never available, and the
project is mounted read-write, so agent actions reach your host repository.
Because the spec sets `yoloEnabled` explicitly, a global `yolo: false`
preference does not apply here. The UI's General settings can store a permission
default that outranks the template for later sessions.

## The session

`dsh` ships no in-box TUI, so there is exactly one foreground process:
`enclave-dsh-session` changes into `$PROJECT_DIR` and runs `dsh web --no-open`.

Container port 3080 is published to host loopback. The default
`hostAllocation: fixed` maps it to host port 3080, so two concurrent sessions
contend for it. Start extra ones with `-p 0:3080`.

`.dsh` (`$DSH_HOME`) lives in the persistent config store, so provider settings,
the workspace registry, and session history survive restarts. Managed skills,
both shared and tool-specific, compose into `~/.dsh/skills`, which
`dsh-skill-filesystem` scans as its `user-dsh` root.

## The bind patch

`dsh web` rejects `--host 0.0.0.0` in its flag parser, while the webserver
plugin itself accepts it, so `templates/cordis.patch.yml` sets the bind through
the home-level patch layer at `~/.dsh/cordis.patch.yml`. Because a patch
replaces the targeted row's whole `config`, `--host` and `--port` no longer do
anything and the container port is pinned to 3080. The same file supplies the
permission rows above, including an `unconfined-ask` preset that dsh itself does
not ship; without it a `--no-yolo` session matches no preset and refuses to
start.

`~/.dsh/cordis.patch.yml` is a managed file: the runtime wipes the config store
and re-copies it on every start, so in-container edits do not survive. Override
it from the host at `~/.config/enclave/tools/dsh/cordis.patch.yml` globally or
`~/.config/enclave/projects/<hash>/dsh/config/` per project. To see what
actually composed, run `dsh web --dump-config` in `enclave shell --tool dsh`; it
names the file that supplied each row.

## Egress

`gateway-allowlist.conf` allows Anthropic, OpenAI, and Google plus npm, GitHub,
and TLS. The gateway image has no DeepSeek fragment and an outside extension
cannot ship one, so `api.deepseek.com`, which serves the model API and the
built-in `web_search` tool alike, is declared inline through
`network.allowedDomains`. Switching `web_search` to Perplexity or Exa, which dsh
also ships, needs that host added too.

Widen the allowlist for one run with `--allow-domain`, host-wide with
`enclave network add-domain <domain> --global`, or replace the fragment includes
with `~/.config/enclave/gateway-allowlists/dsh.conf`. That override replaces
only the built-in allowlist file: the spec-declared domains, `api.deepseek.com`
plus every credential-release host, are always unioned on top and cannot be
dropped this way.

Audit what the agent did with the gateway's JSONL log at
`~/.local/state/enclave/projects/<hash>/<tool>/logs/network.log`. The default
`--network-log coarse` records pass and deny decisions; `--network-log requests`
adds request-level detail. `enclave network status`, `print`, and `diff` show
the effective policy.

## Not supported

- Opening a file from the UI. It shells out to `xdg-open`, which the image does
  not have; the UI reports `spawn xdg-open ENOENT`. Read and edit files through
  the agent.
- The `headless` profile. Only the web UI is wired up as a session surface.
- `dsh plugin`, which forwards to `pnpm`.
- `enclave continue` and `enclave resume`. `dsh web` has no session-selection
  flags, so the spec declares no `continueArgs` or `resumeArgs`.
- `enclave auth import` and `enclave auth export`.
