#!/usr/bin/zsh

start_manual_work() {
  local file="$1"
  local slug="$2"

  # 1. Update status
  if grep -q "^status: todo" "$file" || grep -q "^status: paused" "$file"; then
    sed -i "s/^status: .*/status: in-progress/" "$file"
    echo "Status updated to 'in-progress'."
  fi
  
  # 2. Append Log
  # Check if "## Progress Log" exists, if not add it.
  if ! grep -q "^## Progress Log" "$file"; then
    echo -e "\n## Progress Log" >> "$file"
  fi
  
  local timestamp=$(date '+%Y-%m-%d %H:%M')
  local log_entry="- $timestamp Work session started."
  echo "$log_entry" >> "$file"
  
  # Get line number of last line
  local line_num=$(wc -l < "$file")
  
  echo "Opening task file..."
  # 3. Open nvim at the end
  ${EDITOR:-nvim} "+$line_num" "$file"
  
  # 4. Post-work check
  local new_status=$(get_frontmatter_value "status" "$file")
  
  echo -e "\n--- Work Session Ended ---"
  if [[ "$new_status" == "done" || "$new_status" == "completed" ]]; then
     echo "Task status is '$new_status'."
     # No archive prompt needed
  elif [[ "$new_status" == "in-progress" ]]; then
     echo -n "Task is still 'in-progress'. Update? [P]ause, [D]one, [B]locked? "
     read -k 1 post_action
     echo ""
     case "$post_action" in
       p|P|$'\n'|"")
         sed -i "s/^status: .*/status: paused/" "$file"
         echo "Status set to 'paused'."
         ;; 
       d|D)
         # Set status to done and call complete logic
         sed -i "s/^status: .*/status: done/" "$file"
         complete_task "$slug"
         ;; 
       b|B)
         sed -i "s/^status: .*/status: blocked/" "$file"
         echo "Status set to 'blocked'."
         ;; 
       *)
         echo "Status kept as 'in-progress'."
         ;; 
     esac
  else
     echo "Current status: $new_status"
  fi
}

work_task() {
  local focus_mode=false
  local slug=""

  for arg in "$@"; do
    case "$arg" in
      -f|--focus)
        focus_mode=true
        ;; 
      *)
        if [[ -z "$slug" ]]; then
          slug="$arg"
        fi
        ;; 
    esac
  done

  # Fallback to fzf selection if no slug provided
  if [[ -z "$slug" ]]; then
    if ! command -v fzf &> /dev/null; then
       echo "Error: fzf required for selection."
       return 1
    fi
    selection=$(list_tasks_raw | fzf --with-nth=2 --delimiter='\t')
    slug=$(echo "$selection" | cut -f1 | tr -d "'\"")
  fi
  
  [[ "$slug" != *.md ]] && file="$TODO_DIR/$slug.md" || file="$TODO_DIR/$slug"

  if [[ ! -f "$file" ]]; then
    echo "Error: Task file '$file' not found."
    return 1
  fi

  # WIP Handler
  local current_status=$(get_frontmatter_value "status" "$file")
  if [[ "$current_status" == "wip" ]]; then
      echo "Task '$slug' is marked as WIP (Work In Progress/Draft)."
      echo -n "Open in editor to flesh it out? [Y/n] "
      read -k 1 confirm
      echo ""
      if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
          edit_task "$slug"
      fi
      return 0
  fi
  
  echo "Selected Task: $slug"
  echo -n "Select Mode: [A]I Partner, [M]anual Work, [C]opy Prompt, [X]ancel? "
  read -k 1 mode
  echo ""
  
  case "$mode" in
    a|A|$'\n'|"")
      start_ai_work "$file" "$slug" "$focus_mode"
      ;; 
    m|M)
      start_manual_work "$file" "$slug"
      ;; 
    c|C)
      copy_prompt_to_clipboard "$file"
      ;;
    *)
      echo "Cancelled."
      return 0
      ;; 
  esac
}

render_dashboard_view() {
  local sort_mode="$1"
  # Default priority: Sort by column 4 (priority) numeric ascending
  # This puts Priority 1 tasks at the bottom of the list (closest to fzf prompt)
  local sort_cmd="sort -t$'\t' -k4n"
  
  if [[ "$sort_mode" == "time" ]]; then
    # Sort by column 5 (created) string/numeric. Ascending (oldest first).
    sort_cmd="sort -t$'\t' -k5"
  fi
  
  list_tasks_raw | eval "$sort_cmd" | awk -F"\t" '
      BEGIN {
        RESET = "\033[0m"
        BOLD = "\033[1m"
        GREEN = "\033[32m"
        YELLOW = "\033[33m"
        BLUE = "\033[34m"
        CYAN = "\033[36m"
        GRAY = "\033[90m"
        RED = "\033[31m"
        
        # Header - using dummy slug "HEADER" which matches the column structure
        printf "HEADER\t" BOLD "%-40s  %-12s %-6s %s" RESET "\n", "TASK", "STATUS", "PRIO", "CREATED"
      }
      {
        slug = $1
        name = $2
        status = $3
        priority = $4
        created = $5
        
        # Truncate/Pad Name (Limit to 40 chars)
        if (length(name) > 40) name = substr(name, 1, 37) "..."
        
        color = GRAY
        if (status == "in-progress") color = GREEN
        else if (status == "paused") color = YELLOW
        else if (status == "blocked") color = RED
        else if (status == "todo") color = BLUE
        else if (status == "wip") color = CYAN

        prio_color = GRAY
        if (priority == 1) prio_color = RED
        else if (priority == 2) prio_color = YELLOW
        
        # Format: slug <tab> Name (padded) | Status (colored) | Priority (padded) | Created
        printf "%s\t%-40s  %s%-12s%s %s%-6s%s %s\n", slug, name, color, status, RESET, prio_color, priority, RESET, created
      }
    '
}

dashboard() {
  if ! command -v fzf &> /dev/null; then
    echo "fzf not found. Using simple list."
    render_dashboard_view "priority"
    return
  fi

  # Interactive Loop
  while true; do
    # Capture query, key pressed, and selected line
    # Start in "Normal Mode" (fzf --disabled)
    # i or / : Switch to Search Mode (enable-search + unbind nav keys)
    # ESC    : Switch to Normal Mode (disable-search + rebind nav keys)
    
    output=$($TODO_BIN _render_dashboard_view priority | fzf \
      --header "NORMAL: j/k=Nav | i=Search | n=New | d=Done | e=Edit | h=Hide | Enter=Work | p=Layout | q=Quit" \
      --prompt "Normal> " \
      --disabled \
      --bind "j:down,k:up,ctrl-j:down,ctrl-k:up,ctrl-u:half-page-up,ctrl-d:half-page-down" \
      --bind "d:become(printf '%s\n' \"{q}\" d \"{+}\")" \
      --bind "e:become(printf '%s\n' \"{q}\" e \"{+}\")" \
      --bind "h:become(printf '%s\n' \"{q}\" h \"{+}\")" \
      --bind "n:become(printf '%s\n' \"{q}\" n \"{+}\")" \
      --bind "q:abort" \
      --bind "p:change-preview-window(down|hidden|right)" \
      --bind "enter:accept" \
      --bind "ctrl-t:reload($TODO_BIN _render_dashboard_view time)" \
      --bind "ctrl-p:reload($TODO_BIN _render_dashboard_view priority)" \
      --bind "i:unbind(j,k,d,e,h,n,i,p,q,/)+change-prompt(Search> )+enable-search+clear-query" \
      --bind "/:unbind(j,k,d,e,h,n,i,p,q,/)+change-prompt(Search> )+enable-search+clear-query" \
      --bind "esc:rebind(j,k,d,e,h,n,i,p,q,/)+change-prompt(Normal> )+disable-search" \
      --bind "ctrl-c:abort" \
      --expect=enter \
      --delimiter='\t' \
      --with-nth=2.. \
      --ansi \
      --header-lines=1 \
      --no-wrap \
      --print-query \
      --preview "cat $TODO_DIR/{1}.md" \
      --preview-window=right:50%:wrap)
    
    
    if [[ -z "$output" ]]; then
      break
    fi

    query=$(echo "$output" | head -n1)
    key=$(echo "$output" | head -n2 | tail -n1)
    selection=$(echo "$output" | tail -n +3)

    # Parse selection. Aggressively strip quotes because fzf or shell expansion 
    # sometimes wraps fields in single quotes if they contain certain characters.
    slug=$(echo "$selection" | cut -f1 | tr -d "'\"")

    if [[ -z "$slug" ]]; then
        # If 'n' pressed or 'enter' pressed with query, create new task
        if [[ "$key" == "n" ]] || [[ "$key" == "enter" && -n "$query" ]]; then
            create_task_interactive "$query"
            continue
        fi
        continue
    fi

    case "$key" in
      n) 
        if [[ -n "$query" ]]; then
            create_task_interactive "$query"
        else
            create_task_interactive
        fi
        ;; 
      e)
        edit_task "$slug"
        ;; 
      d)
        complete_task "$slug"
        ;; 
      h)
        ignore_task "$slug"
        ;; 
      enter)
        work_task "$slug"
        break
        ;; 
    esac
  done
}
