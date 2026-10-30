# deb-dev

Debian packaging tools, for building `.deb` packages (`dpkg-buildpackage`,
Enclave's `make deb`). Opt-in (disabled by default).

**Priority**: 40

```bash
enclave features add eclipse-enclave/enclave-extensions --name deb-dev
enclave --features +deb-dev
```

## Packages (apt)

| Package | Purpose |
|---------|---------|
| `debhelper` | `dh` build helpers |
| `fakeroot` | Builds packages with root-owned files without root |
| `lintian` | Package checker |

`dpkg-dev` (`dpkg-buildpackage`) is not listed: Enclave's base image already
has it, because `build-essential` depends on it.
