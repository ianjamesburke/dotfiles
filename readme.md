# dotfiles

Portable Zsh configuration shared across machines (macOS + Linux).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ianjamesburke/dotfiles/main/install.sh | sh
```

This will:
1. Clone the repo to `~/dotfiles`
2. Install Homebrew (if missing, macOS only)
3. Install [antidote](https://getantidote.github.io/) for plugin management
4. Append a source line to `~/.zshrc`

## Structure

- `zshrc` — main config (sourced by `~/.zshrc`)
- `zsh_plugins.txt` — full plugin list (macOS)
- `zsh_plugins_lite.txt` — trimmed plugin list (Linux)
- `scripts/` — shell utilities on `$PATH` via `$DOTFILES/scripts`
- `themes/` — zsh prompt themes

## Machine-specific config

Put overrides, secrets, and machine-specific `PATH` additions in `~/.zshrc` *after* the source line. Keep `~/.zsh_secrets` (gitignored) for API keys and tokens.

## Neovim sync

To pull nvim config from another machine:

```sh
./scripts/sync-nvim.sh <user@host>
```
