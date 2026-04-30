#!/usr/bin/zsh

get_system_prompt() {
  local file="$1"
  local PROMPT_FILE="$HOME/prompts/work_mode.md"

  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: System prompt file '$PROMPT_FILE' not found." >&2
    return 1
  fi

  # Prepare System Prompt
  export TASK_CONTENT=$(cat "$file")
  export TASK_FILE_PATH="$file"
  export PROMPT_SRC="$PROMPT_FILE"
  
  python3 -c '
import os
import sys

try:
    with open(os.environ["PROMPT_SRC"], "r") as f:
        template = f.read()
    
    content = os.environ.get("TASK_CONTENT", "")
    path = os.environ.get("TASK_FILE_PATH", "")
    
    output = template.replace("{{TASK_CONTENT}}", content).replace("{{TASK_FILE_PATH}}", path)
    print(output)
except Exception as e:
    sys.exit(1)
'
}

copy_prompt_to_clipboard() {
  local file="$1"
  local SYSTEM_PROMPT
  SYSTEM_PROMPT=$(get_system_prompt "$file")
  
  if [[ $? -ne 0 ]]; then
    echo "Error preparing system prompt."
    return 1
  fi

  if command -v wl-copy &> /dev/null; then
    echo -n "$SYSTEM_PROMPT" | wl-copy
    echo "System prompt copied to clipboard (wl-copy)."
  elif command -v xclip &> /dev/null; then
    echo -n "$SYSTEM_PROMPT" | xclip -selection clipboard
    echo "System prompt copied to clipboard (xclip)."
  else
    echo "Error: No clipboard tool found (xclip or wl-copy)."
    return 1
  fi
  sleep 1
}

start_ai_work() {
  local file="$1"
  local slug="$2"
  local focus_mode="$3"

  # Auto-update status to in-progress
  if grep -q "^status: todo" "$file"; then
    sed -i "s/^status: todo/status: in-progress/" "$file"
    echo "Updated task status to 'in-progress'."
  fi

  # Save current state and setup cleanup trap
  echo "Entering Work Mode for: $slug"
  
  if [[ "$focus_mode" == true ]]; then
    if command -v hyprctl &> /dev/null; then
      hyprctl dispatch fullscreen 1 > /dev/null
    fi
    if command -v makoctl &> /dev/null; then
      makoctl mode -s do-not-disturb > /dev/null
    fi
  fi

  cleanup() {
    echo "Exiting Work Mode..."
    
    # Auto-pause if still in-progress
    if [[ -f "$file" ]]; then
      # Re-read status in case the agent changed it
      current_st=$(grep -m 1 "^status:" "$file" | sed "s/^status: //" | tr -d '"')
      if [[ "$current_st" == "in-progress" ]]; then
        sed -i "s/^status: in-progress/status: paused/" "$file"
        echo "Task status set to 'paused'."
      fi
    fi

    if [[ "$focus_mode" == true ]]; then
      if command -v hyprctl &> /dev/null; then
        hyprctl dispatch fullscreen 1 > /dev/null # Toggle back
      fi
      if command -v makoctl &> /dev/null; then
        makoctl mode -r do-not-disturb > /dev/null
      fi
    fi
  }
  trap cleanup EXIT

  SYSTEM_PROMPT=$(get_system_prompt "$file")

  if [[ $? -ne 0 ]]; then
    echo "Error preparing system prompt."
    return 1
  fi

  INITIAL_MSG="I am ready to work on this task. Here is the context and operational guidelines:

$SYSTEM_PROMPT"

  gemini -i "$INITIAL_MSG"
}
