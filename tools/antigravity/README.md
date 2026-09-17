# Antigravity CLI

Experimental. Google's
[Antigravity CLI](https://antigravity.google/docs/cli/overview) (`agy`) as an
Enclave tool: the agent runs on the project directory inside the usual
container, with the read-write project mount and the DNS allowlist.

**Needs an Enclave with the nested skills directory fix.** `agy` keeps its
skills two levels below the config directory, the one store shape Enclave does
not pre-create, so the container runtime creates the parent as root and `agy`
dies on its first write
([enclave#92](https://github.com/eclipse-enclave/enclave/issues/92), fixed by
[enclave#93](https://github.com/eclipse-enclave/enclave/pull/93)). Until that
ships in the rolling release, use the workaround in
[NOTES.md](NOTES.md#the-root-owned-config-directory).

`agy` is distributed as a prebuilt binary; upstream publishes a changelog,
examples, and an issue tracker at
[google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli),
but no source. Everything here about its on-disk and on-the-wire behaviour was
checked against the 1.2.5 Linux build rather than taken from the docs, which
are thin on both. Usage caveats in one list, the telemetry paths, and what the
tool leaves in the config store are in [NOTES.md](NOTES.md).

## Try it

```bash
enclave tools add eclipse-enclave/enclave-extensions --name antigravity
cd /path/to/your/project
enclave --tool antigravity
```

The first run builds the image, then starts `agy`, which asks you to sign in
with your Google account. Everyday invocations:

```bash
enclave --tool antigravity -- --model gemini-3-pro
enclave --tool antigravity continue        # --continue, the most recent conversation
```

`install.sh` fetches the release tarball from GitHub and installs the binary as
`~/.local/bin/agy`. It does not run upstream's
`curl https://antigravity.google/cli/install.sh | bash`, which resolves the
build through a Cloud Run auto-updater manifest and then edits shell profiles
the image already sets up. The GitHub asset is the same archive that manifest
points at, byte for byte, and the installer verifies it against the manifest's
SHA-512 whenever the manifest describes the release being installed.

The install tracks the newest upstream tag, and `check-update.sh` reports that
tag to Enclave's update probe. Upstream cuts a release most weekdays. Pin a
version by setting `ANTIGRAVITY_VERSION` in both `install.sh` and
`check-update.sh`; pinning only one leaves the probe reporting a change the
rebuild cannot deliver.

## Authentication

Two ways in, and they are independent:

- **Antigravity account (Google sign-in).** Run `agy` and follow the prompt.
  The CLI detects that it is in a container and uses the paste-a-code flow: it
  prints an authorization URL, you open it in your host browser and paste the
  code back. No callback port has to be published. Credentials land in a file
  under `~/.gemini/antigravity-cli/` (the OS keyring is skipped without a
  D-Bus session bus), which the config store persists across sessions.
- **Gemini API key.** Export `GEMINI_API_KEY` *and* set `"modelProvider":
  "gemini"` in the CLI settings; the key alone is ignored. The gateway injects
  the key as `x-goog-api-key` on requests to
  `generativelanguage.googleapis.com`, so it is never present in the container
  environment in the clear.

`/logout` clears the stored session.

## Data privacy

The settings template ships the three switches that matter, and
`entrypoint.d/setup.sh` re-applies them at every start:

| Setting | Effect |
|---|---|
| `enableTelemetry: false` | Opts out of the anonymous usage statistics Google collects by default |
| `showFeedbackSurvey: false` | No post-task survey prompts |
| `allowNonWorkspaceAccess: false` | The agent stays inside the workspace; files elsewhere in the container need explicit approval |

The re-application is required, not belt and braces: `agy` persists settings
sparsely and drops every key that still matches its session default, so the
template alone would apply exactly once. [NOTES.md](NOTES.md) explains the
mechanism and what it means for values you change inside a session.

The network policy adds two denials that do not depend on a setting being
honoured: `play.googleapis.com`, the Clearcut endpoint the analytics worker
posts to, and the auto-updater host. `AGY_CLI_DISABLE_AUTO_UPDATE=true` also
stops the CLI from spawning the update process in the first place.

Prompts, file contents, and command output go to Google as part of normal
operation in any case, and the CLI records command usage over the same gRPC
connection the agent itself uses. Blocking that would block the agent, so
`enableTelemetry` is the only lever there.

## Approvals

Sessions start with `--dangerously-skip-permissions`, as they do for the other
agent tools, since yolo is Enclave's default. Pass `--no-yolo` for the CLI's own
review prompts.

## State and egress

`~/.gemini` lives in the persistent config store, so settings, conversations,
the sign-in, and the skills and MCP configuration the CLI shares with the
Antigravity IDE all survive restarts. Managed skills compose into
`~/.gemini/config/skills`, the scope every Antigravity product reads, so a
feature extension that ships skills reaches this tool too. Host config
passthrough covers settings, keybindings, MCP servers, skills, and workflows;
plugins and the hook configuration are left out, since both execute code the
session did not build.

`gateway-allowlist.conf` allows `antigravity.google` (sign-in landing page,
OAuth client metadata, changelog) and the Google fragment (sign-in, token
refresh, the `cloudcode-pa` and `aicode` agent backend, `generativelanguage`
for API-key mode, and the `aiplatform`, `iamcredentials`, and `sts` hosts that
enterprise Agent Platform and ADC need), plus GitHub and the usual package
registries so the agent can work in the project. Widen it for one run with
`--allow-domain`, host-wide with `enclave network add-domain <domain>
--global`, or replace it with
`~/.config/enclave/gateway-allowlists/antigravity.conf`. To see where the agent
actually went, read `enclave network log` (`--follow`, `--verdict deny`,
`--summary`, `--since session`).

## Not supported

- Running on an Enclave without the fix for
  [enclave#92](https://github.com/eclipse-enclave/enclave/issues/92). See the
  note at the top and the workaround in [NOTES.md](NOTES.md).
- `enclave auth import` and `enclave auth export`. Upstream does not document
  the credential file's name, so `spec.yaml` declares no `authFiles`; sign in
  once inside a session and the config store keeps it.
- `enclave resume`. `agy` has no flag for its conversation picker, so it falls
  back to `--continue`; use `/resume` inside the session.
- The browser tools. They download a Playwright browser at runtime
  (`~/.cache/ms-playwright-go`), which the allowlist does not cover.
