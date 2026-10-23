#!/usr/bin/env sh
# Usage: install.sh [--all]
#   (no flag)  core install, then ask about each optional component
#   --all      accept every optional component that applies to this machine
# Piped installs (curl | sh) read answers from /dev/tty; with no terminal,
# optional components are skipped.
set -e

DOTFILES="$HOME/dotfiles"
REPO="https://github.com/ianjamesburke/dotfiles.git"
OS="$(uname)"
ALL=0
[ "$1" = "--all" ] && ALL=1

cat <<'WELCOME'

  Ian's Command Line Configs

  Core (always): clone to ~/dotfiles, load shared aliases in your shell.
  Everything else is optional and explained before it asks.
  Nothing outside your home directory is touched without a yes.

WELCOME

# ask "<name>" "<one-line explainer>": returns 0 to install.
ask() {
  printf '\n- %s\n  %s\n' "$1" "$2"
  if [ "$ALL" -eq 1 ]; then return 0; fi
  if ! ( : < /dev/tty ) 2>/dev/null; then
    echo "  (no terminal, skipping)"
    return 1
  fi
  printf '  Install? [y/N] '
  read -r ans < /dev/tty
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# Root, or membership in an admin group. Avoids a sudo attempt on shared
# servers where the user is not a sudoer (those get logged and reported).
can_sudo() {
  [ "$(id -u)" -eq 0 ] && return 0
  command -v sudo >/dev/null 2>&1 || return 1
  id -Gn | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

append_once() { # file, marker, line
  if grep -qF "$2" "$1" 2>/dev/null; then
    echo "$1 already wired, skipping."
  else
    printf '\n# dotfiles\n%s\n' "$3" >> "$1"
    echo "Appended source line to $1"
  fi
}

# ── Core ─────────────────────────────────────────────────────────────
if [ -d "$DOTFILES/.git" ]; then
  echo "dotfiles already cloned, pulling latest..."
  git -C "$DOTFILES" pull --ff-only
else
  echo "Cloning dotfiles..."
  git clone "$REPO" "$DOTFILES"
fi

# ── Optional: system packages (Linux) ────────────────────────────────
if [ "$OS" = "Linux" ]; then
  MISSING=""
  command -v zsh >/dev/null 2>&1 || MISSING="$MISSING zsh"
  command -v nvim >/dev/null 2>&1 || MISSING="$MISSING neovim"
  if [ -n "$MISSING" ]; then
    if can_sudo; then
      if ask "System packages:$MISSING" "zsh is the shell the full config targets; neovim is the editor. Installs system-wide via your package manager (needs sudo), so other users get them too."; then
        if command -v apt-get >/dev/null 2>&1; then
          run_privileged apt-get update
          # shellcheck disable=SC2086
          run_privileged apt-get install -y $MISSING
        elif command -v dnf >/dev/null 2>&1; then
          # shellcheck disable=SC2086
          run_privileged dnf install -y $MISSING
        elif command -v pacman >/dev/null 2>&1; then
          # shellcheck disable=SC2086
          run_privileged pacman -Sy --noconfirm $MISSING
        elif command -v apk >/dev/null 2>&1; then
          # shellcheck disable=SC2086
          run_privileged apk add $MISSING
        else
          echo "No supported package manager found; install$MISSING manually." >&2
        fi
      fi
    else
      echo "Missing:$MISSING. No sudo rights here, so skipping. Bash gets your aliases and completions instead."
    fi
  fi
fi

# ── Optional: Homebrew + Brewfile (macOS) ────────────────────────────
if [ "$OS" = "Darwin" ]; then
  if ask "Homebrew + Brewfile" "Homebrew is an app store for developer tools. Installs everything in ~/dotfiles/Brewfile (eza, bat, fzf, ffmpeg, fonts, ...)."; then
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    brew bundle --file="$DOTFILES/Brewfile"
  fi
fi

# ── Optional: user-level toolchains ──────────────────────────────────
if ! command -v rustc >/dev/null 2>&1 && ask "Rust (rustup)" "Rust compiler in ~/.cargo. Only needed to build Rust projects; large download."; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

if ! command -v uv >/dev/null 2>&1 && ask "uv" "Fast Python package and project manager, installed to ~/.local/bin."; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if command -v npm >/dev/null 2>&1 && ask "Agent CLIs (npm)" "Global npm install of claude-code and pi-coding-agent. Fails without write access to the npm prefix."; then
  npm install -g @anthropic-ai/claude-code @earendil-works/pi-coding-agent
fi

if command -v node >/dev/null 2>&1 && ask "Pi settings" "Seeds Pi's config so terminal text selection works."; then
  node "$DOTFILES/scripts/pi-settings-seed.mjs"
fi

# ── Optional: zsh plugins ────────────────────────────────────────────
if command -v zsh >/dev/null 2>&1 && ask "zsh plugins (antidote)" "Plugin manager for zsh. Adds autosuggestions, syntax highlighting and richer completion. Installed in ~/.antidote (or via Homebrew)."; then
  if command -v brew >/dev/null 2>&1; then
    ANTIDOTE_ZSH="$(brew --prefix antidote)/share/antidote/antidote.zsh"
  else
    ANTIDOTE_DIR="$HOME/.antidote"
    if [ -d "$ANTIDOTE_DIR/.git" ]; then
      git -C "$ANTIDOTE_DIR" pull --ff-only
    else
      git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_DIR"
    fi
    ANTIDOTE_ZSH="$ANTIDOTE_DIR/antidote.zsh"
  fi
  ANTIDOTE_ZSH="$ANTIDOTE_ZSH" DOTFILES="$DOTFILES" zsh -c '
    source "$ANTIDOTE_ZSH"
    antidote bundle < "$DOTFILES/zsh_plugins.txt" > "$DOTFILES/zsh_plugins.zsh"
  '
fi

# ── Core: wire the shell ─────────────────────────────────────────────
# zsh present: zshrc is the entry point. Linux also gets bashrc, which hands
# interactive logins over to zsh (no chsh needed). No zsh: bashrc loads the
# shared aliases and completions directly.
if command -v zsh >/dev/null 2>&1; then
  append_once "$HOME/.zshrc" "dotfiles/zshrc" '[[ -f ~/dotfiles/zshrc ]] && source ~/dotfiles/zshrc'
fi
if [ "$OS" = "Linux" ]; then
  append_once "$HOME/.bashrc" "dotfiles/bashrc" '[ -f ~/dotfiles/bashrc ] && . ~/dotfiles/bashrc'
fi

echo ""
echo "Done. Open a new terminal (or log in again)."
if [ "$OS" = "Darwin" ]; then
  echo ""
  echo "REQUIRED: set your terminal font to 'JetBrainsMono Nerd Font Mono'"
  echo "(without it, eza --icons shows broken boxes)."
fi
