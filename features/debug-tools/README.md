# debug-tools

Low-level debugging, tracing, and diagnostics tools. Opt-in (disabled by
default).

This was a built-in feature of core Enclave until it moved here.

**Priority**: 80

```bash
enclave features add eclipse-enclave/enclave-extensions --name debug-tools
enclave --features +debug-tools
```

## Packages

| Package | Purpose |
|---------|---------|
| `gdb` | GNU debugger |
| `ltrace` | Library call tracer |
| `strace` | System call tracer |
| `lsof` | List open files |
| `tcpdump` | Network packet capture |
| `valgrind` | Memory error and leak checker |
| `sysstat` | Performance statistics (`pidstat`, `iostat`, `mpstat`, `sar`) |
| `iproute2` | Network configuration and sockets (`ip`, `ss`) |
| `file` | File type detection |
