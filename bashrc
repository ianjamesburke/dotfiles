# ~/dotfiles/bashrc - bash entry point for machines where zsh is unavailable
# (shared servers without root). Sourced from ~/.bashrc by install.sh.

case $- in *i*) ;; *) return 0 ;; esac

export DOTFILES="$HOME/dotfiles"
export PATH="$HOME/.local/bin:$HOME/.local/nvim/bin:$DOTFILES/scripts:$PATH"

command -v nvim >/dev/null 2>&1 && export EDITOR=nvim VISUAL=nvim || export EDITOR=vi

# Prefer zsh when installed (full config lives in zshrc). No chsh needed.
if [ -z "$ZSH_VERSION" ] && [ -z "$DOTFILES_NO_ZSH" ] && command -v zsh >/dev/null 2>&1; then
  exec zsh
fi

source "$DOTFILES/aliases.sh"

# History
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend checkwinsize

# Completion: system bash-completion if present (covers git, ssh, systemctl, ...)
for f in /usr/share/bash-completion/bash_completion /etc/bash_completion \
         "$HOME/.local/share/bash-completion/bash_completion"; do
  [ -f "$f" ] && { source "$f"; break; }
done
for f in /usr/share/fzf/completion.bash /usr/share/fzf/shell/completion.bash; do
  [ -f "$f" ] && source "$f"
done
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# Tool completions and hooks, only for tools actually on this machine
for tool in gh uv just; do
  command -v "$tool" >/dev/null 2>&1 || continue
  case $tool in
    gh)   source <(gh completion -s bash) ;;
    uv)   source <(uv generate-shell-completion bash) ;;
    just) source <(just --completions bash) ;;
  esac
done
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"
