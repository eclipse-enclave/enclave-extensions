# rpm-dev

RPM packaging tools, for building `.rpm` packages (`rpmbuild`, Enclave's
`make rpm`). Opt-in (disabled by default).

**Priority**: 40

```bash
enclave features add eclipse-enclave/enclave-extensions --name rpm-dev
enclave --features +rpm-dev
```

## Packages (apt)

| Package | Purpose |
|---------|---------|
| `rpm` | RPM package build tools (`rpmbuild`) |
