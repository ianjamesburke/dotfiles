#!/usr/bin/env sh
set -e

DOTFILES="$HOME/dotfiles"
REPO="https://github.com/ianjamesburke/dotfiles.git"
SOURCE_LINE='[[ -f ~/dotfiles/zshrc ]] && source ~/dotfiles/zshrc'
OS="$(uname -s)"

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
  ║   • We'll install the command-line tools this setup needs.   ║
  ║     macOS uses Homebrew; Linux uses its system package tool. ║
  ║                                                              ║
  ║   • You may be asked for your administrator password once.   ║
  ║     normal. Some tools need admin access to install.         ║
  ║     Nothing sketchy, promise. It's the same password you     ║
  ║     use to unlock your computer. The characters won't show   ║
  ║     as you type. That's a security feature, not a bug.       ║
  ║                                                              ║
  ║   Sit back. This takes about 2 minutes.                      ║
  ║                                                              ║
  ╚══════════════════════════════════════════════════════════════╝

WELCOME

# 1. Clone repo
if [ -d "$DOTFILES/.git" ]; then
  echo "dotfiles already cloned, pulling latest..."
  git -C "$DOTFILES" pull --ff-only
else
  echo "Cloning dotfiles..."
  git clone "$REPO" "$DOTFILES"
fi

# 2. Install platform packages
if [ "$OS" = "Darwin" ] && ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure Homebrew-installed tools are on PATH for this session
[ "$OS" = "Darwin" ] && [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ "$OS" = "Darwin" ] && [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
[ "$OS" = "Linux" ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# macOS: Brewfile is the single source of truth for all Homebrew packages.
if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  echo "Installing packages from Brewfile..."
  brew bundle --file="$DOTFILES/Brewfile"
elif [ "$OS" = "Linux" ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "No supported Linux package manager found (expected apt-get)."
    echo "Install zsh, git, fzf, jq, zoxide, bat, fd, eza, gh, and antidote manually."
    exit 1
  fi

  echo "Installing Linux shell tools with apt..."
  sudo -v
  sudo apt-get update
  sudo apt-get install -y zsh git fzf jq zoxide bat fd-find gh

  # eza is available in newer Debian/Ubuntu releases; leave an existing binary alone.
  if ! command -v eza >/dev/null 2>&1 && apt-cache show eza >/dev/null 2>&1; then
    sudo apt-get install -y eza
  else
    command -v eza >/dev/null 2>&1 || echo "eza is not available from this apt repository; install it separately if desired."
  fi

  # Debian names these binaries batcat and fdfind. Keep dotfile commands portable.
  mkdir -p "$HOME/.local/bin"
  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
  if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
else
  echo "Unsupported operating system: $OS"
  exit 1
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

# 8. Install Antidote and generate plugin bundles
ANTIDOTE_ZSH=""
if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  ANTIDOTE_ZSH="$(brew --prefix antidote 2>/dev/null)/share/antidote/antidote.zsh"
elif [ "$OS" = "Linux" ]; then
  ANTIDOTE_ZSH="$HOME/.antidote/antidote.zsh"
  if [ ! -f "$ANTIDOTE_ZSH" ]; then
    echo "Installing Antidote to ~/.antidote..."
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
  fi
fi

if [ -f "$ANTIDOTE_ZSH" ]; then
  echo "Generating Antidote plugin bundles..."
  zsh -c "source '$ANTIDOTE_ZSH' && antidote bundle < '$DOTFILES/zsh_plugins.txt' > '$DOTFILES/zsh_plugins.zsh'"
  zsh -c "source '$ANTIDOTE_ZSH' && antidote bundle < '$DOTFILES/zsh_plugins_lite.txt' > '$DOTFILES/zsh_plugins_lite.zsh'"
else
  echo "Antidote was not found; plugin bundles were not generated."
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
echo ""
if [ "$OS" = "Darwin" ]; then
  echo "⚠  REQUIRED: Set your terminal font to 'JetBrainsMono Nerd Font Mono'"
  echo "   Without it, eza --icons will show broken boxes instead of file icons."
  echo ""
  echo "   iTerm2:    Preferences → Profiles → Text → Font"
  echo "   Terminal:  Settings → Profiles → Font"
  echo "   Ghostty:   Add 'font-family = JetBrainsMono Nerd Font Mono' to config"
else
  echo "Linux skips macOS-only Homebrew casks and fonts. Install a Nerd Font in your terminal if you want eza icons."
fi
