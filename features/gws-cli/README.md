# Google Workspace CLI

Experimental.
The [Google Workspace CLI](https://github.com/googleworkspace/cli) (`gws`) as an
Enclave feature, together with its agent skills for Drive, Gmail, Calendar,
Docs, Sheets, Slides, Chat, Tasks, and the rest. It works with every tool. The
feature is opt-in. `install.sh` pins one gws release, and the vendored skills
come from the same one.

## Try it

```bash
enclave features add eclipse-enclave/enclave-extensions --name gws-cli
enclave gws-cli-import            # reuse the gws login you already have on the host
enclave --features +gws-cli
```

To enable it for one project only, add `"features": ["+gws-cli"]` to that
project's `~/.config/enclave/projects/<hash>/config.json`.

gws needs an OAuth client: the `client_secret.json` of a Desktop OAuth client
in a Google Cloud project with the Workspace APIs enabled. On the host it lives
at `~/.config/gws/client_secret.json`. `gws auth setup` creates one if you have
`gcloud`; otherwise download it from the Cloud console or from whoever runs the
project for your organization.

## Logging in

There are two ways to get a login into the sandbox. Both end up in the same
store, which every session with the feature shares, across projects and tools.

### Import the host login

Log in on the host the usual way, with the scope picker, the browser, and the
OS keyring:

```bash
gws auth login
gws auth status        # project_id, has_refresh_token: true
enclave gws-cli-import
```

`enclave gws-cli-import` is a host command. It copies `client_secret.json` and
reads the host login with `gws auth export --unmasked`, so it needs gws on the
host `PATH`. Rerun it with `--force` after logging in again on the host, for
example to change scopes. `--client-only` copies just the OAuth client.

The host key may be in the OS keyring, which the container cannot reach, so the
import stores the decrypted login as `credentials.json` (mode 0600, in a 0700
directory). gws reads that file directly.

### Log in inside a session

With the OAuth client imported (`enclave gws-cli-import --client-only`), run in
a session shell (`enclave shell --features +gws-cli`):

```bash
gws-auth-login              # Drive, Gmail, Calendar, Docs, Sheets, Slides, Tasks
gws-auth-login --readonly   # read-only variants of the same
gws-auth-login --full       # everything, including Chat, Meet, Forms, Keep
gws-auth-login -s drive,gmail
```

gws waits for Google's redirect on a localhost port inside the container, which
your browser cannot reach, so the helper asks you to paste the address the
browser fails to load and delivers it to gws. Arguments go to `gws auth login`.

There is no `gcloud` in the container, so gws cannot offer its scope picker
templates based on the project's enabled APIs. Choose scopes with the flags
above instead.

## What persists

The whole gws config directory lives in Enclave's feature auth store,
`~/.local/state/enclave/features/gws-cli/auth/` on Linux
(`~/Library/Application Support/org.eclipse.enclave/state/features/gws-cli/auth/`
on macOS), and is linked at `~/.config/gws` in the container:

| File | Content |
|------|---------|
| `client_secret.json` | OAuth client |
| `credentials.json` | Imported login (plaintext) |
| `credentials.enc`, `.encryption_key` | In-session login, encrypted with the key next to it |
| `token_cache.json` | Access tokens, encrypted |
| `cache/` | API discovery documents |
| `account_timezone` | Cached account time zone |

A stored `credentials.enc` takes precedence over `credentials.json`.
`gws auth logout` in a session removes both, along with the token cache.
`enclave cleanup --all` removes the store unless you pass `--keep auth`.

Sessions without a feature auth store keep gws state in the container and lose
it on exit. That applies to `--ephemeral` and `--auth-scope=project`.

## Security

The agent can read the login. Enclave's gateway hides API keys and bearer
tokens that a tool reads from the environment, but gws authenticates with a
refresh token stored in a file and sends it to Google in a request body, and
the gateway protects neither. Anything running in the session can read the
refresh token and use it outside Enclave until you revoke it
([enclave#133](https://github.com/eclipse-enclave/enclave/issues/133)).

Scope the login to what the agent needs. `--readonly` is the safe default for
reporting and summarizing. OAuth scopes are coarse: `gmail.modify` includes
sending mail, and `drive` write access includes sharing. Where you need finer
control, use your agent's command allowlist, for example Claude Code
`permissions` that allow `gws gmail users drafts create` but ask before
`gws gmail users messages send`. The bundled `gws-shared` skill also tells the
agent to confirm write and delete commands with you first.

Revoke a login you no longer trust at
<https://myaccount.google.com/permissions>, then run `gws auth logout` in a
session.

## Egress

The feature allows `*.googleapis.com`, which covers the Workspace APIs, API
discovery, and token exchange, plus `accounts.google.com`, which gws uses to
refresh access tokens. The consent page opens in your host browser and needs
no allowlisting. Verified with Drive, Gmail, and Calendar under the restricted
gateway and with `--network-log=requests`, which routes gws through the
gateway's MITM proxy (gws trusts `SSL_CERT_FILE`).

Other Google hosts, such as `*.googleusercontent.com`, stay blocked. Allow one
per run with `--allow-domain` if a command needs it.

## Skills

`skills/` holds the `gws-*` skills from the pinned gws release: one per
service, the `+helper` commands, and the cross-service workflows. Enclave adds
them to the tool's skills directory only in sessions that enable the feature.
The upstream persona and recipe skills are left out to keep the skill list
short; drop any you want into `~/.config/enclave/skills/`. The skills are
Apache-2.0 licensed by Google LLC; see [LICENSE.skills](LICENSE.skills).

## Updating gws

```bash
./sync.sh 0.23.0
```

`sync.sh` moves the pinned binary, its checksums in `install.sh`, and `skills/`
to another release together, so they never drift apart. Rebuild with
`--rebuild` and test before committing.

## Not supported

- Service-account keys and Application Default Credentials are untested.
- `gws auth setup`: it needs `gcloud`, which the image does not have. Run it on
  the host.
- Tested on Linux x86_64 only. The arm64 binary is pinned but has not been run.
