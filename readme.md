# dotfiles

## What are dotfiles?

Dotfiles are configuration files that live in your home directory and shape how your terminal and tools behave. The name comes from the leading dot (`.`) that makes them hidden by default on macOS and Linux — files like `~/.zshrc`, `~/.gitconfig`, and `~/.ssh/config`.

Why they matter: every time you open a terminal, your shell reads these files to set up your prompt, load aliases, configure your `$PATH`, and initialize plugins. They make your terminal *yours* — consistent keybindings, shortcuts, and defaults that travel with you.

This repo is a portable Zsh config you can drop on any Mac or Linux machine in a few seconds. It handles the common setup so you can focus on the overrides that matter to you. Windows is not supported.

## Viewing hidden files

Dotfiles start with `.` and are hidden by default.

- **Terminal:** `ls -a` shows hidden files and folders in any directory.
- **Finder:** Press `Shift-Cmd-.` to toggle hidden file visibility.

---

Portable Zsh configuration for macOS and Linux.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ianjamesburke/dotfiles/main/install.sh | sh
```

On macOS, this will:
1. Clone the repo to `~/dotfiles`
2. Install Homebrew (if missing, macOS only)
3. Install packages from `Brewfile`, including [antidote](https://getantidote.github.io/)
4. Append a source line to `~/.zshrc`

On Debian/Ubuntu Linux, it installs `zsh`, `git`, `fzf`, `jq`, `zoxide`, `bat`, `fd-find`, and `gh` with `apt`, installs `eza` when that package is available, and clones Antidote into `~/.antidote`. It creates `bat` and `fd` compatibility symlinks for distributions that call them `batcat` and `fdfind`.

The installer deliberately skips macOS-only Homebrew casks and fonts on Linux. Install a Nerd Font in your terminal separately if you want eza icons. The full plugin set is used by default; use `DOTFILES_LITE=1` to load the lighter plugin bundle (also selected automatically on the `omarchy` host).

## Structure

- `zshrc` — main config (sourced by `~/.zshrc`)
- `zsh_plugins.txt` — full plugin list
- `zsh_plugins_lite.txt` — trimmed plugin list (Linux / slower machines)
- `scripts/` — shell utilities on `$PATH` via `$DOTFILES/scripts`
- `themes/` — zsh prompt themes

## Machine-specific config

Put overrides, secrets, and machine-specific `PATH` additions in `~/.zshrc` *after* the source line. Keep `~/.zsh_secrets` (gitignored) for API keys and tokens.
