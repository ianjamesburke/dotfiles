# ~/.dotfiles/zshrc - Portable Zsh configuration

# ------------------------------------------------------------------------------
# SYSTEM DETECTION
# ------------------------------------------------------------------------------
IS_MACOS=false
IS_LINUX=false

if [[ "$OSTYPE" == "darwin"* ]]; then
  IS_MACOS=true
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  IS_LINUX=true
fi

# ------------------------------------------------------------------------------
# PATH & ENVIRONMENT
# ------------------------------------------------------------------------------
export PROMPT_EOL_MARK=""
export GH_NO_UPDATE_NOTIFIER=1
export DOTFILES="$HOME/dotfiles"
export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"
alias python='python3'
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
export PATH="$DOTFILES/scripts:$PATH"
export PATH="$DOTFILES/scripts/wip:$PATH"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
export PATH="$PATH:$HOME/.npm-global/bin"
export PATH="$HOME/.local/nvim/bin:$PATH"
export PATH="$HOME/.cline/cli/bin:$PATH"
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$HOME/.cont/bin:$PATH"

unalias co 2>/dev/null
co() { cd "$(cont open "$1")" || return; }

# Rust/Cargo
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# ------------------------------------------------------------------------------
# COMPLETION INIT (skip audit for fast startup; run 'compinit' manually after installing new tools)
# ------------------------------------------------------------------------------
autoload -Uz compinit
compinit -C

# ------------------------------------------------------------------------------
# PLUGIN MANAGEMENT (Antidote)
# ------------------------------------------------------------------------------
if [[ "$(hostname)" == "omarchy" ]]; then
    [[ -f "$DOTFILES/zsh_plugins_lite.zsh" ]] && source "$DOTFILES/zsh_plugins_lite.zsh"
else
    [[ -f "$DOTFILES/zsh_plugins.zsh" ]] && source "$DOTFILES/zsh_plugins.zsh"
fi

# Source the custom theme
[[ -f "$DOTFILES/themes/ultima.zsh-theme" ]] && source "$DOTFILES/themes/ultima.zsh-theme"

# ------------------------------------------------------------------------------
# TOOLS (FZF, ZOXIDE)
# ------------------------------------------------------------------------------
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
function z() { [[ "$1" == "add" ]] && zoxide add "${2:-.}" || __zoxide_z "$@"; }
if command -v wtp >/dev/null; then
    eval "$(wtp shell-init zsh)"

    # Override wtp to enforce worktrees/ at repo root (never ../worktrees)
    wtp() {
        for arg in "$@"; do
            if [[ "$arg" == "--generate-shell-completion" ]]; then
                command wtp "$@"
                return $?
            fi
        done

        # Ensure .wtp.yml exists with base_dir: worktrees before any add/init
        if [[ "$1" == "add" || "$1" == "init" ]]; then
            local repo_root
            repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
            if [[ -n "$repo_root" && ! -f "$repo_root/.wtp.yml" ]]; then
                cat > "$repo_root/.wtp.yml" <<'EOF'
version: "1.0"
defaults:
  base_dir: worktrees
hooks:
  post_create:
    - type: command
      command: wtp list
EOF
            fi
        fi

        if [[ "$1" == "cd" ]]; then
            local target_dir
            if [[ -z "$2" ]]; then
                target_dir=$(command wtp cd 2>/dev/null)
            else
                target_dir=$(command wtp cd "$2" 2>/dev/null)
            fi
            if [[ $? -eq 0 && -n "$target_dir" ]]; then
                cd "$target_dir"
            else
                if [[ -z "$2" ]]; then
                    command wtp cd
                else
                    command wtp cd "$2"
                fi
            fi
        else
            command wtp "$@"
        fi
    }
fi

# FZF completion and keybindings (System-specific paths)
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude .rustup --exclude node_modules'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

fzf-history-widget() {
  BUFFER=$(fc -l 1 | fzf --height 40% --reverse --tac | sed 's/ *[0-9]* *//')
  CURSOR=${#BUFFER}
  zle redisplay
}
zle -N fzf-history-widget
bindkey '^R' fzf-history-widget

autoload -z edit-command-line
zle -N edit-command-line
bindkey "^X^E" edit-command-line

# ------------------------------------------------------------------------------
# ALIASES & FUNCTIONS
# ------------------------------------------------------------------------------
# General
alias toonl='jq -s "." | toon'
alias zshconfig="nvim $DOTFILES/zshrc"
alias dotconfig="nvim $DOTFILES/zshrc"
alias nvimconfig='nvim ~/.config/nvim/init.lua'
alias n='nvim .'
alias k='kiro .'
alias ls='eza -l --icons --git --header --group-directories-first'
alias files='spf'
alias c='IS_DEMO=1 claude --model sonnet --dangerously-skip-permissions --allow-dangerously-skip-permissions'
alias cs='IS_DEMO=1 claude --model haiku --dangerously-skip-permissions --allow-dangerously-skip-permissions'
alias cl='IS_DEMO=1 claude --model claude-opus-4-6 --dangerously-skip-permissions --allow-dangerously-skip-permissions'
if [[ "$IS_MACOS" == "true" ]]; then
  alias p='pbpaste'
elif [[ "$IS_LINUX" == "true" ]]; then
  alias p='wl-paste'
fi

# Re-run last command and copy a capsule: timestamp, dir, command, output
alias cap='capsule'
capsule() {
  local cmd="$(fc -ln -1)"
  local ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local dir="$PWD"
  echo "Re-running for clipboard: $cmd"
  local output
  output="$(eval "$cmd" 2>&1)" || true
  local capsule
  capsule="$(printf '[%s] %s\n$ %s\n%s' "$ts" "$dir" "$cmd" "$output")"
  if [[ -n "$SSH_CONNECTION" ]]; then
    printf '\033]52;c;%s\a' "$(printf '%s' "$capsule" | base64)"
  elif [[ "$IS_MACOS" == "true" ]]; then
    printf '%s' "$capsule" | pbcopy
  elif [[ "$IS_LINUX" == "true" ]]; then
    printf '%s' "$capsule" | wl-copy
  fi
  echo "Copied."
}
alias here='pwd | pbcopy && echo "$(pwd) copied to clipboard"'
alias x='clear'
alias py='python3'
alias ..='cd ..'
alias ...='cd ../..'
alias reload='exec zsh'

alias oc='opencode'

alias jj='just --choose'

# Run a just recipe; on failure, open Claude Code with full error context for fixing.
jc() {
  local output exit_code
  output=$(just "$@" 2>&1)
  exit_code=$?
  printf '%s\n' "$output"
  if [[ $exit_code -ne 0 ]]; then
    claude "Command 'just $*' failed with exit $exit_code:\n\n$output\n\nFix it."
  fi
}
if [[ "$IS_MACOS" == "true" ]]; then
  alias procs='ps -u $USER -o pid,pcpu,pmem,stat,start,command | (read h; echo "$h"; sort -k2 -rn) | awk "NR==1 || (\$2>0 || \$3>0)"'
elif [[ "$IS_LINUX" == "true" ]]; then
  alias procs='ps -u $USER -o pid,pcpu,pmem,stat,start,command --sort=-%cpu | awk "NR==1 || (\$2>0 || \$3>0)"'
fi

pkill-pick() {
  local ps_cmd
  if [[ "$IS_MACOS" == "true" ]]; then
    ps_cmd='ps -u '"$USER"' -o pid,pcpu,pmem,command | (read h; echo "$h"; sort -k2 -rn) | awk "NR==1 || (\$2>0 || \$3>0)"'
  else
    ps_cmd='ps -u '"$USER"' -o pid,pcpu,pmem,command --sort=-%cpu | awk "NR==1 || (\$2>0 || \$3>0)"'
  fi
  eval "$ps_cmd" | fzf \
    --header-lines=1 \
    --prompt="Kill> " \
    --bind "enter:execute-silent(kill {1})+reload($ps_cmd)" \
    --bind "esc:abort"
}

# Git
alias i='gh issue create'
alias issues='gh issue list'
alias go='git open'
gs() {
  git rev-parse --git-dir &>/dev/null || { echo "not a git repo"; return 1; }

  local reset=$'\033[0m'   bold=$'\033[1m'     dim=$'\033[2m'
  local gray=$'\033[90m'   cyan=$'\033[36m'    magenta=$'\033[35m'
  local green=$'\033[32m'  yellow=$'\033[33m'  red=$'\033[31m'
  local b_cyan=$'\033[1;36m'  b_green=$'\033[1;32m'  b_yellow=$'\033[1;33m'
  local b_red=$'\033[1;31m'   b_magenta=$'\033[1;35m'

  local n=1
  [[ "$1" =~ ^[0-9]+$ ]] && n=$1

  local branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
  local upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)

  local sync_label="" sync_color=""
  if [[ -n "$upstream" ]]; then
    local ahead=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null)
    local behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null)
    if [[ $ahead -gt 0 && $behind -gt 0 ]]; then
      sync_label=" ↑${ahead} ↓${behind}"; sync_color="$b_yellow"
    elif [[ $ahead -gt 0 ]]; then
      sync_label=" ↑${ahead}";            sync_color="$yellow"
    elif [[ $behind -gt 0 ]]; then
      sync_label=" ↓${behind}";           sync_color="$b_red"
    else
      sync_label=" ✓";                    sync_color="$b_green"
    fi
  fi

  local total=$(git rev-list --count HEAD 2>/dev/null)
  local commits
  commits=$(git log -${n} --format="%h%x1f%s%x1f%cr%x1f%ci" 2>/dev/null)

  echo ""
  printf "  ${gray}branch${reset}  ${b_cyan}%s${reset}${sync_color}%s${reset}${gray}%s${reset}\n" \
    "$branch" "$sync_label" "${upstream:+  vs $upstream}"

  local i=0
  while IFS=$'\x1f' read -r hash msg rel abs_raw; do
    printf "  ${gray}commit${reset}  ${b_magenta}#%s${reset}  ${magenta}%s${reset}  %s\n" \
      "$(( total - i ))" "$hash" "$msg"
    printf "          ${gray}%s · %s${reset}\n" "$rel" "${abs_raw%:*}"
    (( i++ )) || true
  done <<< "$commits"

  local status_lines
  status_lines=$(git status --short 2>/dev/null)
  [[ -z "$status_lines" ]] && { echo ""; return; }

  _gs_mini_diff() {
    local diff_raw="$1"
    local count
    count=$(printf '%s\n' "$diff_raw" | grep -E '^[+-]' | grep -cvE '^(\+\+\+|---)' || true)
    [[ $count -eq 0 || $count -gt 10 ]] && return
    while IFS= read -r dline; do
      case "$dline" in
        diff\ --git*) printf "    ${gray}╌ %s${reset}\n" "${dline##* b/}" ;;
        +++*|---*|@@*|index*|Binary*) ;;
        +*) printf "    ${b_green}+${reset} ${green}%s${reset}\n" "${dline:1}" ;;
        -*) printf "    ${b_red}-${reset} ${red}%s${reset}\n"  "${dline:1}" ;;
      esac
    done <<< "$diff_raw"
  }

  echo ""
  while IFS= read -r line; do
    local x="${line:0:1}" y="${line:1:1}" file="${line:3}"
    local xc="" yc=""

    if [[ "$x" == "?" && "$y" == "?" ]]; then
      printf "  ${red}??${reset}  ${red}%s${reset}\n" "$file"
      continue
    fi

    case "$x" in
      A) xc="$b_green"  ;;
      M) xc="$b_green"  ;;
      D) xc="$b_red"    ;;
      R) xc="$b_cyan"   ;;
      C) xc="$b_cyan"   ;;
      " ") xc="$gray"   ;;
      *) xc="$reset"    ;;
    esac
    case "$y" in
      M) yc="$b_yellow" ;;
      D) yc="$b_red"    ;;
      " ") yc="$gray"   ;;
      *) yc="$reset"    ;;
    esac

    printf "  ${xc}%s${reset}${yc}%s${reset}  %s\n" "$x" "$y" "$file"

    # Inline diff for this file if changes are small
    local fname="${file%% ->*}"  # handle renames: take left side
    [[ "$y" == "M" || "$y" == "D" ]] && _gs_mini_diff "$(git diff --unified=0 --no-color -- "$fname" 2>/dev/null)"
    [[ "$x" == "M" || "$x" == "A" || "$x" == "R" ]] && _gs_mini_diff "$(git diff --cached --unified=0 --no-color -- "$fname" 2>/dev/null)"
  done <<< "$status_lines"

  echo ""
}
alias gp='git pull'
gd() {
  if [[ $# -eq 0 ]]; then
    read -q "REPLY?discard all unstaged changes? [y/N] " && echo && git restore . && gs || echo ""
  else
    git restore "$@" && gs
  fi
}

# cat wrapper — markdown → glow, everything else → bat
# cat -50 file.md reads first 50 lines through glow
cat() {
  if [[ $# -eq 0 ]]; then
    command cat
    return
  fi
  local lines=""
  local files=()
  for arg in "$@"; do
    if [[ "$arg" =~ ^-([0-9]+)$ ]]; then
      lines="${match[1]}"
    else
      files+=("$arg")
    fi
  done
  local use_glow=0
  for f in "${files[@]}"; do
    [[ "$f" == *.md || "$f" == *.markdown ]] && use_glow=1 && break
  done
  if [[ $use_glow -eq 1 ]]; then
    if [[ -n "$lines" ]]; then
      head -"$lines" "${files[@]}" | glow -
    else
      glow "${files[@]}"
    fi
  else
    if [[ -n "$lines" ]]; then
      head -"$lines" "${files[@]}" | bat --language=md
    else
      bat "${files[@]}"
    fi
  fi
}
alias gpu='git push'
alias lg='lazygit'
alias poosh='git add . | git commit -a -m "$(git diff --cached | gemini --model=gemini-2.5-flash --prompt \"Generate a short, clear commit message\")" && git push'

# poosh but with claude code
yeet() {
  echo "→ staging changes..."
  git add . || { echo "yeet: git add failed"; return 1; }

  local diff=$(git diff --cached)
  if [[ -z "$diff" ]]; then
    echo "yeet: nothing staged to commit"
    return 1
  fi

  echo "→ generating commit message..."
  local prompt="Generate a short, clear commit message without any markdown, code fences, or extra formatting. Just the message.

Changes:
$diff"
  local msg
  msg=$(claude -p "$prompt" --model claude-haiku-4-5-20251001 2>/dev/null)
  local claude_exit=$?

  if [[ $claude_exit -ne 0 ]]; then
    echo "yeet: claude exited with code $claude_exit"
    echo "output: $msg"
    return 1
  fi

  if [[ -z "$msg" ]]; then
    echo "yeet: claude returned empty message"
    return 1
  fi

  echo "→ committing: $msg"
  git commit -m "$msg" || { echo "yeet: git commit failed"; return 1; }

  echo "→ pushing..."
  git push || { echo "yeet: git push failed"; return 1; }
}

# Tools & Apps
alias nvimconfig='nvim ~/.config/nvim/init.lua'
alias minuetconfig='nvim ~/.config/nvim/lua/plugins/minuet.lua'
alias vimconfig='vim ~/.vimrc'
if [[ "$IS_MACOS" == "true" ]]; then
  alias finder='open .'
  alias myip='ipconfig getifaddr en0'
elif [[ "$IS_LINUX" == "true" ]]; then
  alias finder='xdg-open .'
fi
alias nq='networkQuality'
alias ze='zoxide edit'
alias log='$DOTFILES/scripts/log'

# Gemini & AI
alias g='gemini --yolo'
alias gf='gemini -m "gemini-3-flash-preview" --yolo'
alias oracle='GEMINI_SYSTEM_MD=$HOME/prompts/oracle.md gemini'
alias geminiconfig='code ~/.gemini/'
alias esconfig='nvim ~/.config/espanso/match/base.yml'

# Taskwarrior
alias t='task'
alias ta='task add'
alias tl='task list'
alias td='task done'
alias tm='task modify'
alias ts='task start'
alias tst='task stop'
alias tn='task next'
alias tp='task projects'
alias tt='task tags'
alias dtom='due:tomorrow'
alias dtoy='due:today'



# Fly.io
if [[ "$IS_MACOS" == "true" ]]; then
  alias flystage='open "https://$(basename "$PWD" | tr "[:upper:]" "[:lower:]" | tr " " "-")-staging.fly.dev/"'
  alias flyprod='open "https://$(basename "$PWD" | tr "[:upper:]" "[:lower:]" | tr " " "-").fly.dev/"'
elif [[ "$IS_LINUX" == "true" ]]; then
  alias flystage='xdg-open "https://$(basename "$PWD" | tr "[:upper:]" "[:lower:]" | tr " " "-")-staging.fly.dev/"'
  alias flyprod='xdg-open "https://$(basename "$PWD" | tr "[:upper:]" "[:lower:]" | tr " " "-").fly.dev/"'
fi
alias logsstage='fly logs -c fly.staging.toml'
alias logsprod='fly logs -c fly.prod.toml'

# Fun
alias stars='astroterm --color --constellations --speed 1000 --fps 64 --city Detroit -m'
alias mandelbrot='python3 $DOTFILES/scripts/mandelbrot.py'
alias stars-now='astroterm --color --constellations --speed 1 --city Detroit -m'

# ------------------------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------------------------
# Clear any 'open' alias from plugins before defining functions
unalias open 2>/dev/null || true

# Only define open() wrapper on Linux (macOS already has the 'open' command)
if [[ "$IS_LINUX" == "true" ]]; then
  open() {
    xdg-open "$@" >/dev/null 2>&1 &
  }
fi

# Jump to a git worktree by partial name; no args = fzf picker
# wt merge — rebase onto main, merge, delete worktree + branch
wt() {
  local worktrees dir

  # Try current dir first; if not a git repo, walk up to find the parent repo
  if ! worktrees=$(git worktree list 2>/dev/null); then
    dir="$PWD"
    while [[ "$dir" != "/" ]]; do
      if [[ -d "$dir/.git" ]]; then
        cd "$dir"
        worktrees=$(git worktree list 2>/dev/null)
        break
      fi
      dir="${dir:h}"
    done
  fi
  [[ -z "$worktrees" ]] && { echo "Not in a git repo"; return 1; }

  if [[ "$1" == "merge" ]]; then
    local branch main_path worktree_path
    branch=$(git branch --show-current)
    worktree_path=$(pwd)
    main_path=$(echo "$worktrees" | awk '$3 == "[main]" || $3 == "[master]" {print $1}' | head -1)

    [[ -z "$branch" ]] && { echo "Not on a branch (detached HEAD?)"; return 1; }
    [[ "$branch" == "main" || "$branch" == "master" ]] && { echo "Already on main"; return 1; }
    [[ -z "$main_path" ]] && { echo "Could not find main/master worktree"; return 1; }
    [[ "$worktree_path" == "$main_path" ]] && { echo "Already in main worktree"; return 1; }

    echo "Fetching origin..."
    git fetch origin || return 1

    echo "Updating main..."
    git -C "$main_path" fetch origin || return 1
    git -C "$main_path" rebase origin/main || {
      echo "Rebase in main failed — resolve conflicts in main worktree and retry"
      return 1
    }

    local main_ref
    main_ref=$(git -C "$main_path" rev-parse HEAD)

    echo "Rebasing $branch onto main..."
    git rebase "$main_ref" || {
      echo "Rebase has conflicts — resolve them, run 'git rebase --continue', then retry 'wt merge'"
      return 1
    }

    echo "Squash-merging $branch into main..."
    git -C "$main_path" merge --squash "$branch" || {
      echo "Squash merge failed — check main worktree state"
      return 1
    }
    git -C "$main_path" commit -m "Merge branch '$branch'" || {
      echo "Commit failed — check main worktree state"
      return 1
    }

    echo "Pushing main to origin..."
    git -C "$main_path" push origin main || return 1

    if [[ "$2" == "--keep" ]]; then
      echo "Done — $branch squash-merged into main (worktree and branch kept)"
    else
      echo "Removing worktree and branch..."
      cd "$main_path"
      git worktree remove "$worktree_path" 2>/dev/null || git worktree remove --force "$worktree_path"
      git branch -D "$branch"
      local issue_number
      issue_number=$(echo "$branch" | grep -oE '[0-9]+' | tail -1)
      if [[ -n "$issue_number" ]] && command -v gh &>/dev/null; then
        gh issue close "$issue_number" &>/dev/null &
        echo "Closing issue #$issue_number in background"
      fi
      echo "Done — $branch squash-merged into main and cleaned up"
    fi

  elif [[ -z "$1" ]]; then
    local selection
    selection=$(echo "$worktrees" | fzf --prompt="worktree> " --layout=reverse) || return
    cd "${selection%% *}"

  else
    local match
    match=$(echo "$worktrees" | awk '{print $1}' | grep -i "$1" | head -1)
    [[ -n "$match" ]] && cd "$match" || echo "No worktree matching '$1'"
  fi
}

# Re-run last command and copy output (including errors)
last() {
  local cmd="$(fc -ln -1)"
  if [[ -n "$SSH_CONNECTION" ]]; then
    echo "Re-running for clipboard (OSC 52): $cmd"
    local output
    output="$(eval "$cmd" 2>&1)" || true
    local clip_text
    clip_text="$(printf '$ %s\n%s' "$cmd" "$output")"
    printf '\033]52;c;%s\a' "$(printf '%s' "$clip_text" | base64)"
  elif [[ "$IS_MACOS" == "true" ]]; then
    echo "Re-running for clipboard: $cmd"
    local output
    output="$(eval "$cmd" 2>&1)" || true
    printf '$ %s\n%s' "$cmd" "$output" | pbcopy
  elif [[ "$IS_LINUX" == "true" ]]; then
    echo "Re-running for clipboard: $cmd"
    local output
    output="$(eval "$cmd" 2>&1)" || true
    printf '$ %s\n%s' "$cmd" "$output" | wl-copy
  fi
}

# Write iso file to sd card
iso2sd() {
  if [ $# -ne 2 ]; then
    echo "Usage: iso2sd <input_file> <output_device>"
    echo "Example: iso2sd ~/Downloads/ubuntu-25.04-desktop-amd64.iso /dev/sda"
    echo -e "\nAvailable SD cards:"
    lsblk -d -o NAME | grep -E '^sd[a-z]' | awk '{print "/dev/"$1}'
  else
    sudo dd bs=4M status=progress oflag=sync if="$1" of="$2"
    sudo eject $2
  fi
}

# Transcode functions
transcode-video-1080p() {
  ffmpeg -i $1 -vf scale=1920:1080 -c:v libx264 -preset fast -crf 23 -c:a copy ${1%.*}-1080p.mp4
}

img2jpg() {
  img="$1"
  shift
  magick "$img" $@ -quality 95 -strip ${img%.*}-optimized.jpg
}

# ------------------------------------------------------------------------------
# ZSH OPTIONS
# ------------------------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# ------------------------------------------------------------------------------
# ZSH AUTOSUGGESTIONS CONFIGURATION
# ------------------------------------------------------------------------------
# Strategy: Suggest from history, then from completions
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Keybindings:
bindkey '^ ' forward-word              # Ctrl + Space: Accept next word
bindkey '^[[1;5C' forward-word       # Ctrl + RightArrow: Accept next word
bindkey '^f' forward-word             # Ctrl + F: Accept next word
bindkey '^E' autosuggest-accept       # Ctrl + E: Accept full suggestion

# ------------------------------------------------------------------------------
# ZSH COMPLETION CONFIGURATION
# ------------------------------------------------------------------------------
LISTMAX=500
zstyle ':completion:*' menu select
zstyle ':completion:*' file-sort modification
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# zsh-autocomplete: disable async zpty workers to prevent runaway subshells.
# Async mode spawns /bin/zsh -l workers via zpty for each completion; if a
# completion function hangs the worker spins at 100% CPU indefinitely.
# Synchronous mode blocks briefly instead — imperceptible in practice.
zstyle ':autocomplete:*' async off

# ------------------------------------------------------------------------------
# TERMINAL TAB/WINDOW TITLES
# ------------------------------------------------------------------------------
# Manual label: `title "my project"` — sticks until `untitle` clears it
_CUSTOM_TITLE=""
title() { _CUSTOM_TITLE="$1"; echo -ne "\033]0;$1\007" }
untitle() { _CUSTOM_TITLE=""; echo -ne "\033]0;${PWD/#$HOME/~}\007" }

_title_precmd() {
  if [[ -n "$_CUSTOM_TITLE" ]]; then
    echo -ne "\033]0;$_CUSTOM_TITLE\007"
  else
    echo -ne "\033]0;${PWD/#$HOME/~}\007"
  fi
}
_title_preexec() {
  if [[ -z "$_CUSTOM_TITLE" ]]; then
    echo -ne "\033]0;$1 @ ${PWD/#$HOME/~}\007"
  fi
}
autoload -Uz add-zsh-hook

# ------------------------------------------------------------------------------
# HOOKS
# ------------------------------------------------------------------------------
add-zsh-hook precmd _title_precmd
add-zsh-hook preexec _title_preexec
chpwd_ls() {
  if git rev-parse --git-dir &>/dev/null 2>&1; then
    gs
  else
    eza -l --icons --git --color=always -s modified --reverse | head -5
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd chpwd_ls

auto_activate_venv() {
  if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
  elif [[ -n "$VIRTUAL_ENV" && ! -f .venv/bin/activate ]]; then
    deactivate
  fi
}
add-zsh-hook chpwd auto_activate_venv
auto_activate_venv
export PATH="$HOME/.cargo/bin:$PATH"

# Mise (version manager)
command -v mise >/dev/null && eval "$(mise activate zsh)"

# Bun
if [[ -d "$HOME/.bun" ]]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  [[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"
fi

# Local env
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# ------------------------------------------------------------------------------
# PLEXI ISSUE WORKFLOW
# plexi-work <issue>  — fetch issue, create worktree, start Claude
# plexi-pr            — conflict-check, open PR, watch for reviews in background
# ------------------------------------------------------------------------------

plexi-work() {
  local issue_number=$1
  [[ -z "$issue_number" ]] && { echo "Usage: plexi-work <issue-number>"; return 1; }

  # Repo context comes from CWD — must be run from inside the target repo.
  # Use worktree list to get the real repo root; --show-toplevel returns the
  # worktree's own directory when called from a linked worktree (e.g. worktrees/alpha).
  local repo_root
  repo_root=$(git worktree list --porcelain 2>/dev/null | awk 'NR==1{print $2}') || true
  [[ -z "$repo_root" ]] && { echo "❌ not in a git repo — cd into the repo first"; return 1; }

  # gh detects the repo from the git remote automatically (no --repo flag needed)
  echo "→ fetching issue #${issue_number}..."
  local issue_json
  issue_json=$(gh issue view "$issue_number" --json number,title,body 2>&1) || {
    echo "❌ gh error: $issue_json"; return 1
  }
  local title body
  title=$(echo "$issue_json" | jq -r '.title')
  body=$(echo "$issue_json"  | jq -r '.body // "(no body)"')

  # Build branch name from slugified title
  local slug branch
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-40)
  branch="feature/${issue_number}-${slug}"

  # Find farthest-along branch: alpha > beta > main/master
  local base_branch base_wt
  if git ls-remote --exit-code --heads origin alpha &>/dev/null; then
    base_branch="alpha"
  elif git ls-remote --exit-code --heads origin beta &>/dev/null; then
    base_branch="beta"
  else
    base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    base_branch="${base_branch:-main}"
  fi

  # Find the local worktree that has base_branch checked out
  base_wt=$(git worktree list --porcelain | awk -v b="refs/heads/$base_branch" \
    '/^worktree /{wt=$2} $0=="branch " b {print wt; exit}')
  if [[ -z "$base_wt" ]]; then
    echo "❌ no local worktree found for branch '$base_branch' — check out $base_branch first"
    return 1
  fi

  echo "→ creating worktree from $base_branch: $branch"
  (cd "$base_wt" && wtp add -b "$branch") || return 1

  local worktree_path="$repo_root/worktrees/$branch"

  # Detect available test/build targets from Justfile
  local test_section=""
  local justfile=""
  [[ -f "$repo_root/Justfile"  ]] && justfile="$repo_root/Justfile"
  [[ -f "$repo_root/justfile"  ]] && justfile="$repo_root/justfile"
  if [[ -n "$justfile" ]]; then
    local targets
    targets=$(just --justfile "$justfile" --list --unsorted 2>/dev/null | awk 'NR>1{print $1}')
    local checks=()
    echo "$targets" | grep -qx "build"  && checks+=("just build")
    echo "$targets" | grep -qx "test"   && checks+=("just test")
    echo "$targets" | grep -qx "check"  && checks+=("just check")
    echo "$targets" | grep -qx "lint"   && checks+=("just lint")
    if (( ${#checks[@]} > 0 )); then
      test_section="\n## Before submitting\nRun these in order — all must pass:\n"
      for cmd in "${checks[@]}"; do
        test_section+="- \`$cmd\`\n"
      done
    else
      test_section="\n## Before submitting\nCheck \`just --list\` for any test/build targets and run them.\n"
    fi
  elif [[ -f "$repo_root/package.json" ]]; then
    test_section="\n## Before submitting\n- \`npm test\` — must pass\n"
  fi

  # Write issue context — Claude reads this, no second fetch needed
  printf "# Issue #%s: %s\n\n%s%b\n" \
    "$issue_number" "$title" "$body" "$test_section" \
    > "$worktree_path/.claude-issue.md"

  cd "$worktree_path"
  print -P "\n%F{cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f"
  print -P "%F{cyan}  Issue #${issue_number}:%f ${title}"
  print -P "%F{cyan}  Branch:%f ${branch}"
  print -P "%F{cyan}  Context:%f .claude-issue.md (issue + test checklist)"
  print -P "%F{cyan}  Done?%f run plexi-pr"
  print -P "%F{cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f\n"

  claude
}

plexi-pr() {
  local branch repo_root base_branch
  branch=$(git branch --show-current)
  repo_root=$(git worktree list --porcelain 2>/dev/null | awk 'NR==1{print $2}')
  [[ -z "$branch" || "$branch" == "main" || "$branch" == "master" ]] && {
    echo "❌ run from inside a feature worktree"; return 1
  }

  # Detect base branch: use alpha if it exists, else main/master
  if git -C "$repo_root" rev-parse --verify origin/alpha &>/dev/null; then
    base_branch="alpha"
  else
    base_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    base_branch="${base_branch:-main}"
  fi

  # Must be clean before we poke the index
  [[ -n "$(git status --porcelain)" ]] && {
    echo "❌ uncommitted changes — commit first"; return 1
  }

  # Conflict pre-check: merge base into branch index, abort immediately
  echo "→ conflict check vs ${base_branch}..."
  git fetch origin "$base_branch" &>/dev/null
  if git merge --no-commit --no-ff FETCH_HEAD &>/dev/null; then
    git merge --abort &>/dev/null || git reset --merge &>/dev/null || true
    echo "✓ clean"
  else
    git merge --abort &>/dev/null || git reset --merge &>/dev/null || true
    echo "❌ conflicts with ${base_branch} — resolve before opening PR"; return 1
  fi

  # Infer PR title from context file written by plexi-work, or gh
  local issue_number pr_title pr_body
  issue_number=$(echo "$branch" | grep -oE '[0-9]+' | head -1)
  if [[ -f .claude-issue.md ]]; then
    pr_title=$(head -1 .claude-issue.md | sed 's/^# Issue [0-9]*: //')
  elif [[ -n "$issue_number" ]]; then
    pr_title=$(gh issue view "$issue_number" --json title -q '.title' 2>/dev/null || echo "$branch")
  else
    pr_title="$branch"
  fi
  pr_body=${issue_number:+"Closes #${issue_number}"}

  echo "→ opening PR: $pr_title"
  local pr_url pr_number
  pr_url=$(gh pr create --base "$base_branch" \
    --title "$pr_title" \
    --body "${pr_body:-}" 2>&1) || { echo "❌ $pr_url"; return 1 }
  pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
  echo "✓ PR #${pr_number}: $pr_url"

  # Background watcher: 5 attempts × 90s = 7.5 min max
  local log="$TMPDIR/plexi-pr-${pr_number}.log"
  echo "→ review watcher running in background (log: $log)"
  _plexi_watch_reviews "$pr_number" "$branch" "$base_branch" "$repo_root" "$log" &
  disown
}

# Background: poll for reviews, auto-approve if clean, else notify user
_plexi_watch_reviews() {
  local pr_number=$1 branch=$2 base_branch=$3 repo_root=$4 log=$5
  local tries=0

  while (( tries < 5 )); do
    sleep 90
    (( tries++ ))

    local count
    count=$(gh pr view "$pr_number" --json reviews --jq '.reviews | length' 2>/dev/null || echo 0)
    echo "[$(date +%H:%M:%S)] attempt ${tries}/5 — ${count} review(s)" >> "$log"
    (( count == 0 )) && continue

    # Check for blocking keywords across review bodies and inline comments
    local text
    text=$(gh pr view "$pr_number" --json reviews,comments \
      --jq '([.reviews[].body] + [.comments[].body]) | join("\n")' 2>/dev/null)

    if echo "$text" | grep -iqE 'critical|blocking|must.?fix|security|vulnerability'; then
      echo "[$(date +%H:%M:%S)] HIGH SEVERITY — manual review required" >> "$log"
      osascript -e "display notification \"PR #${pr_number}: high-severity issues — review required\" with title \"plexi ⚠️\"" &>/dev/null
      return 1
    fi

    echo "[$(date +%H:%M:%S)] no blocking issues — auto-approving" >> "$log"
    gh pr review "$pr_number" --approve \
      --body "Auto-approved: no blocking issues found in reviews." >> "$log" 2>&1

    _plexi_merge "$pr_number" "$branch" "$base_branch" "$repo_root" >> "$log" 2>&1
    osascript -e "display notification \"PR #${pr_number} merged and cleaned up\" with title \"plexi ✅\"" &>/dev/null
    return 0
  done

  echo "[$(date +%H:%M:%S)] no reviews after 5 attempts — PR left open" >> "$log"
  osascript -e "display notification \"PR #${pr_number}: no reviews after 7.5min — left open\" with title \"plexi ⏰\"" &>/dev/null
}

# Final conflict check → squash merge → install → cleanup
_plexi_merge() {
  local pr_number=$1 branch=$2 base_branch=$3 repo_root=$4

  # Find the primary worktree (first in list = the main checkout)
  local primary_wt
  primary_wt=$(git -C "$repo_root" worktree list --porcelain | awk '/^worktree /{print $2; exit}')

  git -C "$primary_wt" fetch origin "$base_branch" &>/dev/null
  if ! git -C "$primary_wt" merge --no-commit --no-ff "origin/$base_branch" &>/dev/null; then
    git -C "$primary_wt" merge --abort &>/dev/null || git -C "$primary_wt" reset --merge &>/dev/null || true
    echo "❌ new conflicts with ${base_branch} — merge blocked"; return 1
  fi
  git -C "$primary_wt" merge --abort &>/dev/null || git -C "$primary_wt" reset --merge &>/dev/null || true

  gh pr merge "$pr_number" --squash || return 1
  git -C "$primary_wt" pull || return 1

  # Run install if a matching just target exists
  local justfile=""
  [[ -f "$repo_root/Justfile" ]] && justfile="$repo_root/Justfile"
  [[ -f "$repo_root/justfile" ]] && justfile="$repo_root/justfile"
  if [[ -n "$justfile" ]]; then
    local targets
    targets=$(just --justfile "$justfile" --list --unsorted 2>/dev/null | awk 'NR>1{print $1}')
    if echo "$targets" | grep -qx "install-${base_branch}"; then
      (cd "$primary_wt" && just "install-${base_branch}") || return 1
    elif echo "$targets" | grep -qx "install"; then
      (cd "$primary_wt" && just install) || return 1
    fi
  fi

  # Remove worktree and remote branch
  local wt_path="$repo_root/worktrees/$branch"
  git -C "$primary_wt" worktree remove "$wt_path" --force &>/dev/null || true
  git push origin --delete "$branch" &>/dev/null || true

  echo "[$(date +%H:%M:%S)] done — PR #${pr_number} merged, branch cleaned up"
}

# ------------------------------------------------------------------------------
# CONT — Isolated worktree manager
# Creates a git worktree + branch per label, symlinks .env.<label> into it.
# Usage: cont <label>   → create (if needed) and cd into worktree
#        cont main      → cd back to main repo root
#        cont rm <label>→ remove worktree and branch
#        cont           → list active worktrees
# Binary: ~/.local/bin/cont (uv run wrapper → ~/Documents/github/cont)
# ------------------------------------------------------------------------------
function cont() {
  if [[ -z "$1" ]]; then
    $HOME/.local/bin/cont ls
    return
  elif [[ "$1" == "rm" ]]; then
    $HOME/.local/bin/cont "${@}"
    return
  elif [[ "$1" == "main" ]]; then
    cd "$(git worktree list --porcelain | awk '/^worktree /{path=$2} /^branch refs\/heads\/(main|master)$/{print path; exit}')"
  else
    cd "$($HOME/.local/bin/cont new "$1")"
  fi
}

_cont_complete() {
  local repo_root worktrees_dir
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  worktrees_dir="$repo_root/worktrees"
  local labels=("main")
  if [[ -d "$worktrees_dir" ]]; then
    labels+=("${worktrees_dir}"/*(N:t))
  fi
  # rm subcommand: complete worktree labels
  if [[ "${words[2]}" == "rm" ]]; then
    compadd -- "${labels[@]}"
    return
  fi
  compadd -- "${labels[@]}"
}
compdef _cont_complete cont

# Parallax CLI tab completion
[[ -f ~/.cache/zsh/parallax-completion.zsh ]] && source ~/.cache/zsh/parallax-completion.zsh
