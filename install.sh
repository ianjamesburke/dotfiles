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
  ║   • You'll be asked for your Mac password once. That's       ║
  ║     normal. Some tools need admin access to install.         ║
  ║     Nothing sketchy, promise. It's the same password you     ║
  ║     use to unlock your computer. The characters won't show   ║
  ║     as you type. That's a security feature, not a bug.       ║
  ║                                                              ║
  ║   Sit back. This takes about 2 minutes.                      ║
  ║                                                              ║
  ╚══════════════════════════════════════════════════════════════╝

WELCOME

# ── Keep sudo alive for the duration of the script ───────────────────
echo "We need admin access to install system tools."
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &

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

# 3. Install packages from Brewfile
if command -v brew >/dev/null 2>&1; then
  echo "Installing packages from Brewfile..."
  brew bundle --file="$DOTFILES/Brewfile"
else
  echo "Homebrew not available, skipping package install."
  echo "Install antidote manually: https://getantidote.github.io"
fi

# 4. Install Rust via rustup
if ! command -v rustc >/dev/null 2>&1; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . "$HOME/.cargo/env"
else
  echo "Rust already installed, skipping."
fi

# 5. Install uv (Python toolchain)
if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
else
  echo "uv already installed, skipping."
fi

# 6. Install npm global tools
if command -v npm >/dev/null 2>&1; then
  echo "Installing npm global packages..."
  npm install -g @anthropic-ai/claude-code @toon-format/cli 2>/dev/null || true
else
  echo "npm not found. Install Node via mise ('mise use -g node@lts') then re-run."
fi

# 7. Install uv tools
if command -v uv >/dev/null 2>&1; then
  echo "Installing uv tools..."
  uv tool install mermaid-ascii 2>/dev/null || true
else
  echo "uv not available, skipping mermaid-ascii."
fi

# 8. Generate antidote plugin bundle
if command -v brew >/dev/null 2>&1; then
  ANTIDOTE_ZSH="$(brew --prefix antidote 2>/dev/null)/share/antidote/antidote.zsh"
  if [ -f "$ANTIDOTE_ZSH" ]; then
    echo "Generating zsh plugin bundle..."
    zsh -c "source '$ANTIDOTE_ZSH' && antidote bundle < '$DOTFILES/zsh_plugins.txt' > '$DOTFILES/zsh_plugins.zsh'"
  fi
fi

# 9. Wire up ~/.zshrc
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
