# vnc feature

Opt-in feature that gives a session a **contained GUI**: a virtual X display
(TigerVNC's `Xvnc`) running a fullscreened Chromium, served over **VNC (RFB)**.
The raw RFB port is published on the host loopback, so you can attach any VNC
client of your choice.

Install and enable it:

```bash
enclave features add eclipse-enclave/enclave-extensions --name vnc
enclave --features +vnc …
```

The feature needs a base image whose archive ships Chromium as a deb. The
default Debian base does. On an Ubuntu base, which only ships Chromium as a
snap, the install fails and the build stops with an error naming this feature.

It also ships a **host command**, `enclave vnc-viewer`, which runs on your host
outside the sandbox. `enclave features add` reports that before writing
anything. See [Connecting a VNC client](#connecting-a-vnc-client).

## Connecting a VNC client

```bash
enclave vnc-viewer [container-or-session-name]
```

`enclave vnc-viewer` resolves the session's published port and password itself
and launches a host-installed viewer: `xtigervncviewer` on Linux, the built-in
Screen Sharing on macOS, or whatever `vnc_viewer` configures (see
[Viewer configuration](#viewer-configuration)). Without an argument it picks
the current project's only VNC-enabled container. With several running it
lists them and asks for a name.

It is a host command rather than something enclave runs in the session, because
driving a host GUI is exactly what a sandboxed session cannot do. It needs
[`jq`](https://jqlang.github.io/jq/) on the host (`apt install jq`,
`brew install jq`) to read `enclave ps --json` and `enclave config --json`.

To attach a client by hand instead: the RFB port (container `5900`) is
published with an OS-assigned host port on the loopback interface, so
concurrent sessions get distinct ports. The session prints the resolved
`vnc://localhost:<port>` at startup, and `enclave ps --json` reports it too
(look for container port `5900`). Read the per-session password out of the
session and point your client at it:

```bash
enclave exec --name <session> -- cat /tmp/enclave-vnc/vnc-password
vncviewer 127.0.0.1:<published-host-port>
```

## What runs in the container

`commands.startup` launches `enclave-vnc-supervisor` (installed to
`/usr/local/bin`) as the sandbox user. It keeps three components alive with
per-component restart loops, logging to `/tmp/enclave-vnc/log/`:

1. **Xvnc**: virtual X display `:99`, RFB server on the published container
   port `5900`, VncAuth required. It listens on all container interfaces
   (no `-localhost`) so the host's loopback-published port reaches it.
2. **matchbox-window-manager**: fullscreens every window (kiosk-style).
3. **Chromium**: headful on the virtual display. It starts on a local
   waiting page and stays there until a page is opened. When `$VNC_URL` is set,
   a one-shot watcher probes it and forwards it into the running browser once
   its TCP port accepts connections. Loading the URL directly would instead park
   the display on a connection-refused error page whenever the target server
   starts later than the stack. Sessions can also drive the browser on demand
   via `enclave-vnc-open`, which is how a consuming feature opens a URL it only
   knows at runtime.

A component that keeps crashing restarts after a delay that doubles up to a
minute, and its log rotates to `<name>.log.1` once it passes 1 MiB. Stopping
the supervisor with TERM or HUP stops all three components.

Both the supervisor and `enclave-vnc-open` launch Chromium through the shared
`/usr/local/bin/enclave-vnc-chromium` wrapper, so the browser behaves the same
however it was started. That script's header documents the switches it sets
and why.

The feature entrypoint additionally exports `DISPLAY=:99`, so X clients land
on the contained display. `enclave-vnc-open <url>` reuses the supervisor's
Chromium profile, waiting briefly for its singleton if the stack is still
booting, so each URL opens as a new tab in the running browser instead of
racing it. It refuses arguments that start with a dash and logs to
`/tmp/enclave-vnc/log/vnc-open.log`.

### Opening links on the display

Routing "open in browser" flows to the contained Chromium is opt-in, because
it also catches login flows such as `gh auth login --web`, and whatever you
type into that browser is readable by the agent (see
[Residual risks](#residual-risks)). Without it, nothing routes links to the
display, so a login flow ends in the URL the tool prints, which you open on
the host. Enable it per session:

```bash
VNC_OPEN_LINKS=1 enclave --features +vnc --pass-env VNC_OPEN_LINKS …
```

The feature entrypoint then exports `BROWSER=/usr/local/bin/enclave-vnc-open`
and registers `enclave-vnc-open` as the sandbox user's `x-scheme-handler` for
http/https (`enclave-vnc-open`'s header explains why that registration, not
just `$BROWSER`, is load-bearing). The registration lives in files, so it also
covers processes started with `docker exec`. Consuming features can call
`enclave-vnc-open` directly either way.

A set `DISPLAY` is also how many tools decide a GUI is available, so with this
feature enabled `gpg` pinentry, `SSH_ASKPASS`, and `GIT_ASKPASS` prompts render
on the contained display rather than in the terminal. Check the VNC client if
an interactive command appears to hang.

## Access control

The supervisor generates a random password on first start and enforces it at
the RFB layer (VncAuth), so Xvnc demands it from every client. It writes two
copies:

- obfuscated auth file: `/tmp/enclave-vnc/rfb-passwd` (Xvnc)
- plaintext: `/tmp/enclave-vnc/vnc-password` (mode 0600)

Holding that password is what grants control of the display, and nothing else
does. It is generated per session, so it reaches exactly one session's display
and no other. That is why the (untrusted) agent knowing it is harmless, and
why reading it out of the session is safe.

The plaintext path is the **integration contract** for a trusted host-side
viewer: `/tmp/enclave-vnc/vnc-password` inside the session, alongside the
container port `5900` binding that `enclave ps --json` reports. The path is the
contract, and how a viewer reads it is up to the backend it drives.
`enclave exec` always allocates a TTY, so it serves the interactive flow above
but not a headless one. A non-interactive viewer needs a backend-level read
(`docker exec` or `podman exec`) until the CLI grows a non-TTY exec.

The `commands/host/vnc-viewer` script is that viewer: it reads the password
through `docker exec` or `podman exec` (whichever engine holds the container)
and hands it to the client through the environment (`VNC_PASSWORD`,
`ENCLAVE_VNC_PASSWORD`) rather than argv, which `/proc` would expose to every
local user for the viewer's lifetime. The session can also rewrite the file, so
the script refuses anything but the 20 characters of `[A-Za-z0-9]` the
supervisor generates before it reaches a `vnc://` URL.

## Viewer configuration

`enclave vnc-viewer` reads the `vnc_viewer` key out of enclave's own config
files, global (`~/.config/enclave/config.json`) first and the project config
(`~/.config/enclave/projects/<hash>/config.json`) on top:

```json
{ "vnc_viewer": ["remmina", "-c", "vnc://:{password}@{host}:{port}"] }
```

enclave itself ignores the key, since the viewer is a host command rather than
a session option, so it does not appear in `enclave config`.

Unset, the default is `xtigervncviewer` on Linux and Screen Sharing on macOS.
Screen Sharing takes the password only inside a `vnc://` URL, so the script
hands that URL to `osascript` on stdin rather than to `open` in argv.
Placeholders substituted into a configured command:

| Placeholder | Value |
|-------------|-------|
| `{host}` | Host address of the published RFB port (loopback) |
| `{port}` | Published host port |
| `{password}` | Per-session VNC password |
| `{container}` | Container name |

A command that references neither `{host}` nor `{port}` gets `<host>:<port>`
appended, so `{"vnc_viewer": ["vncviewer"]}` works. The password is also
exported as `VNC_PASSWORD` and `ENCLAVE_VNC_PASSWORD`, which is why the default
Linux viewer needs no placeholder: TigerVNC reads `VNC_PASSWORD` from the
environment. Prefer that over `{password}` where the viewer supports it: argv is
world-readable via `/proc` for the viewer's lifetime, while a process
environment is not.

## Configuration

Environment variables read by the feature (set via a consuming feature's
`environment.variables`, the project `.env`, or `--pass-env`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `VNC_OPEN_LINKS` | unset | `1` routes "open in browser" flows to the display (see [Opening links on the display](#opening-links-on-the-display)). |
| `VNC_URL` | unset | Optional URL auto-forwarded into the browser once its port is reachable. Left unset, the display stays on the waiting page and sessions open pages on demand via `enclave-vnc-open`. |
| `VNC_URL_WAIT_SECONDS` | `300` | How long that forward waits for the URL's port before giving up and logging. |
| `VNC_GEOMETRY` | `1600x1000` | Initial display size (a resize-capable client can change it) |
| `VNC_DISPLAY` | `:99` | X display number |

The RFB port is not configurable: it must match the `ports:` declaration in
`spec.yaml` (container port `5900`), so the supervisor hardcodes it.

A consuming feature should leave `VNC_URL` unset whenever the page it wants is
only determined at runtime, and call `enclave-vnc-open` with the full URL
instead. Auto-forwarding a bare server root in that situation lands the
display on a default view, which can clobber whatever state the intended URL
would have selected.

## Credentials

None declared. The only secret is the per-session VNC password (see
[Access control](#access-control)).

## Egress

The feature adds no allowlist entries and needs none at runtime. The contained
Chromium browses through the session gateway like every other process in the
session: pages the session serves on `localhost` load, anything else needs its
domain on the allowlist. A denied domain fails at DNS, which Chromium shows as
its offline page with `DNS_PROBE_FINISHED_NO_INTERNET` rather than as a
gateway error. `enclave network log --verdict deny` names the domain. Widen the
allowlist for one run with `--allow-domain`, or host-wide with
`enclave network add-domain <domain> --global`.

Chromium's own background traffic (component updates, sync, safe browsing) is
switched off, so it does not fill the network log with denials.

## Persistence

Nothing persists. The Chromium profile (cookies, logins, history, open tabs),
the password, and the logs live under `/tmp/enclave-vnc/` and go with the
container when the session ends. That is deliberate: the agent runs as the
same user and can read the profile, so a persistent one would hand every later
session whatever was logged in to the contained browser.

## Troubleshooting

The entrypoint starts the supervisor with its stdout and stderr discarded, so
the files under `/tmp/enclave-vnc/log/` are the only record. Start with
`supervisor.log` (startup, auth-file generation, URL forwarding), then
`xvnc.log`, `wm.log`, `browser.log`, and `vnc-open.log` for the individual
components. A rotated `<name>.log.1` holds older output.

On GNOME, the Locate Pointer accessibility setting (reveal the pointer with
left Ctrl) can keep left-Ctrl shortcuts from reaching the viewer. Turn it off
with `gsettings set org.gnome.desktop.interface locate-pointer false`.

## Not supported

- Ubuntu base images, which ship Chromium only as a snap.
- Audio. RFB carries no sound.
- Encrypted RFB. Xvnc only offers VncAuth (see
  [Residual risks](#residual-risks)).

## Residual risks

[Security boundaries](https://github.com/eclipse-enclave/enclave/blob/main/docs/security/README.md)
covers the overall threat model a published display sits in. Feature-specific:

- Holding the password is sufficient to drive the display, so keep it to
  trusted local viewers.
- `enclave vnc-viewer` runs on the host with your privileges, not in the
  sandbox. It is the extension's code, so install it only if you trust this
  repository.
- The host publish is loopback-only, but Xvnc listens on all interfaces
  inside the container's network namespace. Under network isolation that
  namespace belongs to the session's gateway container on a bridge shared with
  other containers of the same engine, so those (including other sessions'
  gateways) can reach the RFB port directly, with VncAuth as the only gate.
  VncAuth only authenticates. The framebuffer, keystrokes, and clipboard
  travel unencrypted, so anything that can observe traffic on that bridge sees
  the session in the clear.
- A human can be phished by what the streamed page *shows*. A viewer cannot
  vouch for the session's content.
- Whatever you enter in the contained Chromium (account passwords, 2FA codes,
  the resulting session cookies) is readable by the agent: Chromium runs as
  the sandbox user, keeps its profile in `/tmp/enclave-vnc/chromium` with
  `--password-store=basic`, and draws on a display the agent can read. With
  `VNC_OPEN_LINKS=1` that includes login flows that would otherwise end on the
  host.
- Clipboard crossing: Xvnc syncs the display's X selections with the RFB
  clipboard natively (`SendCutText`/`AcceptCutText`/`SetPrimary`/`SendPrimary`,
  all on by default), so any authenticated RFB client can exchange clipboard
  text with the session. Nothing in this feature gates that. A viewer built on
  top of it has to mediate the clipboard itself if it wants to.

## Cost

Chromium + X + VNC + fonts add roughly 600 MB to the image and a persistent
browser process to the session, hence `defaultEnabled: false`.
