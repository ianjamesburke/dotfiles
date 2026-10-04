#!/usr/bin/env sh
set -e

DOTFILES="$HOME/dotfiles"
REPO="https://github.com/ianjamesburke/dotfiles.git"
SOURCE_LINE='[[ -f ~/dotfiles/zshrc ]] && source ~/dotfiles/zshrc'

# ── Welcome ──────────────────────────────────────────────────────────
cat <<'WELCOME'

  ╔══════════════════════════════════════════════════════════════╗
  ║                                                              ║
  ║   🖥  Ian's Command Line Configs                              ║
  ║                                                              ║
  ║   This installs my current command line configs. Use it as   ║
  ║   a starting point. Point your agent at ~/dotfiles/zshrc     ║
  ║   to explore and modify the configurations.                  ║
  ║                                                              ║
  ║   Here's what's about to happen:                             ║
  ║                                                              ║
  ║   • "zsh" is the language your Terminal speaks. This script  ║
  ║     teaches it new tricks: aliases, shortcuts, and colors.   ║
  ║                                                              ║
  ║   • "Homebrew" is an app store for developer tools. We'll    ║
  ║     use it to install everything the setup needs.            ║
  ║                                                              ║
  ║   • Linux installs may ask for your administrator password.  ║
  ║     Some tools need admin access to install. The characters  ║
  ║     won't show as you type; that's a security feature.       ║
  ║                                                              ║
  ║   Sit back. This takes about 2 minutes.                      ║
  ║                                                              ║
  ╚══════════════════════════════════════════════════════════════╝

WELCOME

# ── Privileged package installs ───────────────────────────────────────
# macOS Homebrew manages its own privilege prompts. Linux package managers
# need sudo unless the script is already running as root.
run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Need root access to install $1. Re-run with sudo or install it manually." >&2
    return 1
  fi
}

# 1. Clone repo
if [ -d "$DOTFILES/.git" ]; then
  echo "dotfiles already cloned, pulling latest..."
  git -C "$DOTFILES" pull --ff-only
else
  echo "Cloning dotfiles..."
  git clone "$REPO" "$DOTFILES"
fi

# 2. Install Homebrew (macOS only)
if [ "$(uname)" = "Darwin" ] && ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure Homebrew-installed tools are on PATH for this session
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

# 3. Install the shell prerequisites before wiring up the configuration.
# macOS gets Neovim from the Brewfile. On Linux, install only what is missing.
if [ "$(uname)" = "Linux" ]; then
  LINUX_PACKAGES=""
  if ! command -v zsh >/dev/null 2>&1; then
    LINUX_PACKAGES="$LINUX_PACKAGES zsh"
  fi
  if ! command -v nvim >/dev/null 2>&1; then
    LINUX_PACKAGES="$LINUX_PACKAGES neovim"
  fi

  if [ -n "$LINUX_PACKAGES" ]; then
    echo "Installing Linux shell prerequisites:$LINUX_PACKAGES"
    if command -v apt-get >/dev/null 2>&1; then
      run_privileged apt-get update
      # Intentional word splitting: LINUX_PACKAGES is built from fixed package names above.
      run_privileged apt-get install -y $LINUX_PACKAGES
    elif command -v dnf >/dev/null 2>&1; then
      run_privileged dnf install -y $LINUX_PACKAGES
    elif command -v pacman >/dev/null 2>&1; then
      run_privileged pacman -Sy --noconfirm $LINUX_PACKAGES
    elif command -v apk >/dev/null 2>&1; then
      run_privileged apk add $LINUX_PACKAGES
    else
      echo "No supported Linux package manager found. Install zsh and Neovim, then re-run this script." >&2
      exit 1
    fi
  fi
fi

# 4. Install packages from Brewfile
if command -v brew >/dev/null 2>&1; then
  echo "Installing packages from Brewfile..."
  brew bundle --file="$DOTFILES/Brewfile"
else
  echo "Homebrew not available, skipping package install."
fi

# 5. Install Rust via rustup
if ! command -v rustc >/dev/null 2>&1; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . "$HOME/.cargo/env"
else
  echo "Rust already installed, skipping."
fi

# 6. Install uv (Python toolchain)
if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  echo "uv already installed, skipping."
fi

# 7. Install npm global tools
if command -v npm >/dev/null 2>&1; then
  echo "Installing npm global packages..."
  npm install -g @anthropic-ai/claude-code @toon-format/cli 2>/dev/null || true
else
  echo "npm not found. Install Node via mise ('mise use -g node@lts') then re-run."
fi

# 8. Install uv tools
if command -v uv >/dev/null 2>&1; then
  echo "Installing uv tools..."
  uv tool install mermaid-ascii 2>/dev/null || true
else
  echo "uv not available, skipping mermaid-ascii."
fi

# 9. Install Antidote and generate the zsh plugin bundle.
# Homebrew provides it on macOS. On Linux, keep the manager in ~/.antidote so
# the shell remains portable without requiring Linuxbrew.
ANTIDOTE_ZSH=""
if command -v brew >/dev/null 2>&1; then
  ANTIDOTE_ZSH="$(brew --prefix antidote 2>/dev/null)/share/antidote/antidote.zsh"
elif [ "$(uname)" = "Linux" ]; then
  ANTIDOTE_DIR="$HOME/.antidote"
  if [ -d "$ANTIDOTE_DIR/.git" ]; then
    echo "Updating antidote..."
    git -C "$ANTIDOTE_DIR" pull --ff-only
  else
    echo "Installing antidote..."
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_DIR"
  fi
  ANTIDOTE_ZSH="$ANTIDOTE_DIR/antidote.zsh"
fi

if [ -f "$ANTIDOTE_ZSH" ] && command -v zsh >/dev/null 2>&1; then
  echo "Generating zsh plugin bundle..."
  ANTIDOTE_ZSH="$ANTIDOTE_ZSH" DOTFILES="$DOTFILES" zsh -c '
    source "$ANTIDOTE_ZSH"
    antidote bundle < "$DOTFILES/zsh_plugins.txt" > "$DOTFILES/zsh_plugins.zsh"
  '
else
  echo "Antidote or zsh is unavailable; zsh plugins were not generated." >&2
fi

# 10. Wire up ~/.zshrc
ZSHRC="$HOME/.zshrc"
if grep -qF "dotfiles/zshrc" "$ZSHRC" 2>/dev/null; then
  echo "~/.zshrc already sources dotfiles, skipping."
else
  echo "" >> "$ZSHRC"
  echo "# dotfiles" >> "$ZSHRC"
  echo "$SOURCE_LINE" >> "$ZSHRC"
  echo "Appended source line to ~/.zshrc"
fi

echo ""
echo "Done. Open a new terminal or run: source ~/.zshrc"
echo ""
if [ "$(uname)" = "Darwin" ]; then
  echo "⚠  REQUIRED: Set your terminal font to 'JetBrainsMono Nerd Font Mono'"
  echo "   Without it, eza --icons will show broken boxes instead of file icons."
  echo ""
  echo "   iTerm2:    Preferences → Profiles → Text → Font"
  echo "   Terminal:  Settings → Profiles → Font"
  echo "   Ghostty:   Add 'font-family = JetBrainsMono Nerd Font Mono' to config"
fi
