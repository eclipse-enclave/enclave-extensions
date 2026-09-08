# Enclave Extensions

Community tool and feature extensions for [Eclipse Enclave](https://github.com/eclipse-enclave/enclave),
the Docker sandbox for agentic coding tools.

Enclave ships Claude, Codex, OpenCode, Theia, and a handful of features in its
own repository. This repo is for everything that lives outside it: experimental
agents or features, or extensions that are too niche to be built in.

## Install

Enclave installs extensions straight from a git repository.

```bash
enclave tools add eclipse-enclave/enclave-extensions
```

With more than one tool in the repo, `add` lists what it found and asks which
one you meant. Skip the question by naming it:

```bash
enclave tools add eclipse-enclave/enclave-extensions --name <extension-name>
enclave --tool <extension-name>
```

Before writing anything, `add` prints what the extension can do: root install
steps, install and startup scripts, network changes, declared credentials,
files seeded into your project. Read that summary. An extension is code that
runs at container build and start time. Proceed at your own risk, extensions
here are not signed or are not reviewed or tested in depth by Eclipse Enclave
core team.

Afterwards:

```bash
enclave tools list                     # built-in and installed, with provenance
enclave tools update <extension-name>  # refresh from the recorded source
enclave tools remove <extension-name>
```

If `enclave tools --help` has no `add` subcommand, your Enclave predates the
installer. Update from the
[rolling release](https://github.com/eclipse-enclave/enclave/releases/tag/rolling).

Alternatively, you can skip the installer entirely: download or clone this
repository yourself and copy the individual `tools/<name>/` or
`features/<name>/` directories you want (not necessarily all of them) into
the matching `tools/` or `features/` subdirectory of
`~/.config/enclave/extensions/`. This gets you the same extensions without
provenance tracking or update checks. See Enclave's [extension
docs](https://github.com/eclipse-enclave/enclave/tree/main/docs/extensions)
for more information.

## What is in here

| Tool | Status | What it is |
|------|--------|------------|
| [openclaw](tools/openclaw) | Experimental | [OpenClaw](https://openclaw.ai/) personal assistant: gateway, terminal UI, and browser dashboard |
| [dsh](tools/dsh) | Experimental | [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) with its browser UI |

Experimental means what it says: each one pins a fast-moving upstream, gets
thinner testing than a built-in tool, and has rough edges written down in its
own README. Read that README before the first session, the security notes
above all.

## Contribute

Bring your favorite agent or enclave feature. A tool extension is a directory with a
`spec.yaml` and usually an `install.sh`. A feature extension can be as small as a spec
and a package list.

- Tools live in `tools/<name>/` and declare `kind: sandbox`.
- Features live in `features/<name>/` and declare `kind: mixin`.
- The directory name must match the spec's `name`.
- Every extension needs a `README.md` that covers credentials, egress,
  persistence, and whatever does not work.

Start from Enclave's guide to
[adding a tool](https://github.com/eclipse-enclave/enclave/blob/main/docs/extensions/adding-a-tool.md)
and the [extension reference](https://github.com/eclipse-enclave/enclave/blob/main/docs/extensions/README.md),
try it locally with `enclave tools add ./path/to/clone --name <name>`, then open
a pull request. Also rough extensions marked experimental are welcome. But please make
sure to properly document the state of your extension and its edges.

## Questions & Support

Got a question, an idea, or ran into trouble with one of these extensions?
Head over to
[Enclave's discussions](https://github.com/eclipse-enclave/enclave/discussions)
and start a thread. It's the best place for support, feature requests, and
just chatting about what you're building.

## License

MIT. See [LICENSE](LICENSE).
