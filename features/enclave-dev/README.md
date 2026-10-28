# enclave-dev

What it takes to develop [Enclave](https://github.com/eclipse-enclave/enclave)
itself in an Enclave session: the Go linters Enclave's CI runs, at the
versions it pins. Opt-in (disabled by default).

**Priority**: 50

## Enable

Features can't depend on each other, so enable Go from core's `golang-dev`
feature with it:

```bash
enclave features add eclipse-enclave/enclave-extensions --name enclave-dev
enclave --features +golang-dev,+enclave-dev
```

For `make deb` and `make rpm`, also install [deb-dev](../deb-dev) and
[rpm-dev](../rpm-dev) and enable `+golang-dev,+enclave-dev,+deb-dev,+rpm-dev`.

`golang-dev` has priority 45, so its Go is in place before this feature's
`install.sh` runs. Without it the install fails with
`go is required to install linters` and the build stops.

## Installed via `install.sh`

`go install` into `~/.local/bin`, with retries on transient network errors:

- `golangci-lint` (`v2.14.0`)
- `gosec` (`v2.29.0`)
- `govulncheck` (`v1.9.0`)

These pins must match `scripts/install-go-linters.sh` in Enclave's
repository, which CI installs from. Bump both together. Nothing checks that
the two copies match.
