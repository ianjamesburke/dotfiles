# Dotfiles Agent Instructions

## Package Dependency Rule

Any zsh function or alias added to `zshrc` that depends on an external tool **must** have a corresponding entry in `Brewfile`. The install flow (`install.sh`) runs `brew bundle` from that file — it is the single source of truth for packages on a new machine.

Before adding a function, check whether its dependencies are already in `Brewfile`. If not, add them under the appropriate section (`# Core shell tools`, `# Media`, etc.) in the same commit.

Examples:
- `noise` uses `sox` → `brew "sox"` in `Brewfile`
- A function using `ffmpeg` is already covered
- A new function using `imagemagick` is already covered

## Repo Layout

- `zshrc` — all general zsh config; sourced by `~/.zshrc`
- `Brewfile` — all Homebrew packages; drives `brew bundle` in `install.sh`
- `install.sh` — full new-machine bootstrap (Homebrew, Rust, uv, npm globals)
- `scripts/` — standalone scripts symlinked into `~/dotfiles/scripts/`
- `launchd/` — launchd plists symlinked to `~/Library/LaunchAgents/`
- `themes/` — shell themes
