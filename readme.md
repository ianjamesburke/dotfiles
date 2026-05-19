# dotfiles

## What are dotfiles?

Dotfiles are configuration files that live in your home directory and shape how your terminal and tools behave. The name comes from the leading dot (`.`) that makes them hidden by default on macOS and Linux — files like `~/.zshrc`, `~/.gitconfig`, and `~/.ssh/config`.

Why they matter: every time you open a terminal, your shell reads these files to set up your prompt, load aliases, configure your `$PATH`, and initialize plugins. They make your terminal *yours* — consistent keybindings, shortcuts, and defaults that travel with you.

This repo is a portable Zsh config you can drop on any machine in a few seconds. It handles the common setup so you can focus on the overrides that matter to you.

---

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

## Viewing hidden files

Dotfiles start with `.` and are hidden by default.

- **Terminal:** `ls -a` shows hidden files and folders in any directory.
- **Finder:** Press `Shift-Cmd-.` to toggle hidden file visibility.
