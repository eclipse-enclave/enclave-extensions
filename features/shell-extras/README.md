# shell-extras

Enhanced shell experience with zsh and oh-my-zsh. Opt-in (disabled by default).

This was a built-in feature of core Enclave until it moved here.

**Priority**: 90

```bash
enclave features add eclipse-enclave/enclave-extensions --name shell-extras
enclave --features +shell-extras
```

## Packages (apt)

- `zsh`
- `bash-completion`

## Installation

The install script:

1. Installs oh-my-zsh (robbyrussell theme), from its current `master`
2. Configures `~/.zshrc` with PATH, nvm, and terminal size handling

Enclave's base image adds the direnv hooks for bash and, once this feature has
created `~/.zshrc`, for zsh. The feature doesn't add them itself.
