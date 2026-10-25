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

# Sudo is only attempted after an explicit yes. Probing here would log a
# failed attempt on shared servers where the user is not a sudoer.
can_sudo() {
  [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1
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

# ── Optional: zsh via system package (Linux) ─────────────────────────
if [ "$OS" = "Linux" ] && ! command -v zsh >/dev/null 2>&1 && can_sudo; then
  if ask "zsh (system package, needs sudo)" "The shell the full config targets. Installs system-wide, so other users get it too (nobody's login shell changes). Skip if you are not an admin or the machine is IT-managed."; then
    if command -v apt-get >/dev/null 2>&1; then
      run_privileged apt-get update && run_privileged apt-get install -y zsh
    elif command -v dnf >/dev/null 2>&1; then
      run_privileged dnf install -y zsh
    elif command -v pacman >/dev/null 2>&1; then
      run_privileged pacman -Sy --noconfirm zsh
    elif command -v apk >/dev/null 2>&1; then
      run_privileged apk add zsh
    else
      echo "No supported package manager found; install zsh manually." >&2
    fi || echo "zsh install failed (see above); continuing with bash." >&2
  fi
fi

# ── Optional: neovim without root (Linux) ────────────────────────────
if [ "$OS" = "Linux" ] && ! command -v nvim >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) NVIM_ARCH=x86_64 ;;
    aarch64|arm64) NVIM_ARCH=arm64 ;;
    *) NVIM_ARCH="" ;;
  esac
  if [ -z "$NVIM_ARCH" ]; then
    echo "No prebuilt neovim for $(uname -m); skipping."
  elif ask "Neovim (user install)" "Editor. Downloads the official release tarball into ~/.local/nvim. No root needed, other users unaffected."; then
    NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$NVIM_ARCH.tar.gz"
    mkdir -p "$HOME/.local/nvim"
    curl -fsSL "$NVIM_URL" | tar -xz -C "$HOME/.local/nvim" --strip-components=1
    if ! "$HOME/.local/nvim/bin/nvim" --version >/dev/null 2>&1; then
      echo "Neovim installed but will not run (likely an old glibc: $(ldd --version | head -1)). Removing ~/.local/nvim." >&2
      rm -rf "$HOME/.local/nvim"
    fi
  fi
fi

# ── Optional: gitleaks without root (Linux) ──────────────────────────
# daily-log-sync refuses to commit without it. macOS gets it from the Brewfile.
if [ "$OS" = "Linux" ] && ! command -v gitleaks >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) GL_ARCH=x64 ;;
    aarch64|arm64) GL_ARCH=arm64 ;;
    *) GL_ARCH="" ;;
  esac
  if [ -z "$GL_ARCH" ]; then
    echo "No prebuilt gitleaks for $(uname -m); skipping."
  elif ask "gitleaks (user install)" "Secret scanner. daily-log-sync uses it to redact API keys before committing logs, and refuses to commit without it. Downloads the release binary into ~/.local/bin. No root needed."; then
    GL_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/gitleaks/gitleaks/releases/latest)"
    GL_VER="${GL_TAG##*/v}"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v$GL_VER/gitleaks_${GL_VER}_linux_$GL_ARCH.tar.gz" \
      | tar -xz -C "$HOME/.local/bin" gitleaks
    "$HOME/.local/bin/gitleaks" version >/dev/null 2>&1 \
      || echo "gitleaks installed but will not run; daily-log-sync will refuse to commit." >&2
  fi
fi

# ── Optional: LazyVim (Linux) ────────────────────────────────────────
# Never overwrites an existing ~/.config/nvim.
if [ "$OS" = "Linux" ] && [ ! -e "$HOME/.config/nvim" ] \
   && { command -v nvim >/dev/null 2>&1 || [ -x "$HOME/.local/nvim/bin/nvim" ]; }; then
  if ask "LazyVim" "Neovim distribution with LSP, fuzzy finding, git UI and a file tree preconfigured. Clones the official starter into ~/.config/nvim; plugins download on first launch. Needs git and a C compiler. Live grep wants ripgrep; icons want a Nerd Font in your terminal."; then
    git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
  fi
fi

# ── Optional: bash tab-completion framework (Linux) ──────────────────
if [ "$OS" = "Linux" ] && [ ! -f /usr/share/bash-completion/bash_completion ] && [ ! -f /etc/bash_completion ]; then
  if ask "bash-completion (user install)" "The framework behind tab-completing git, ssh, systemctl and similar in bash. Cloned into ~/.local/share/bash-completion, pure shell, no root."; then
    if [ -d "$HOME/.local/share/bash-completion/.git" ]; then
      git -C "$HOME/.local/share/bash-completion" pull --ff-only
    else
      git clone --depth=1 https://github.com/scop/bash-completion.git "$HOME/.local/share/bash-completion"
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
