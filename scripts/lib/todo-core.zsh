#!/usr/bin/zsh

# Directory configuration
export TODO_DIR="$HOME/todo"
export TEMPLATE="$TODO_DIR/task_template.md"
export COMPLETED_DIR="$TODO_DIR/completed"
export CACHE_FILE="$TODO_DIR/.task_cache"

# Ensure directories exist
mkdir -p "$COMPLETED_DIR"

# Function to slugify a string
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd '[:alnum:]-'
}

# Function to extract YAML frontmatter value
get_frontmatter_value() {
  local key="$1"
  local file="$2"
  # Look inside the first block bounded by ---
  grep -m 1 "^$key:" "$file" | sed "s/^$key: //" | tr -d '"'
}

refresh_cache() {
  # Check if cache needs update
  local newest_file
  newest_file=$(ls -t "$TODO_DIR"/*.md 2>/dev/null | head -n 1)
  
  if [[ -z "$newest_file" ]]; then return; fi

  # If cache missing OR directory changed (files added/removed) OR newest file is newer than cache
  if [[ ! -f "$CACHE_FILE" ]] || [[ "$TODO_DIR" -nt "$CACHE_FILE" ]] || [[ "$newest_file" -nt "$CACHE_FILE" ]]; then
    # Rebuild Cache
    # Format: filename|title|status|priority|ignore_until
    : > "$CACHE_FILE"
    for file in "$TODO_DIR"/*.md; do
      filename=$(basename "$file")
      if [[ "$filename" != "task_template.md" && "$filename" != "todo.md" ]]; then
        task_name=$(get_frontmatter_value "task" "$file")
        task_status=$(get_frontmatter_value "status" "$file")
        task_priority=$(get_frontmatter_value "priority" "$file")
        ignore_until=$(get_frontmatter_value "ignore_until" "$file")
        task_created=$(get_frontmatter_value "created" "$file")

        # Fallbacks
        [[ -z "$task_name" ]] && task_name="${filename%.md}"
        [[ -z "$task_status" ]] && task_status="todo"
        [[ -z "$task_priority" ]] && task_priority="3"
        [[ -z "$task_created" ]] && task_created="1970-01-01"

        echo "${filename%.md}|$task_name|$task_status|$task_priority|$ignore_until|$task_created" >> "$CACHE_FILE"
      fi
    done
  fi
}

validate_task_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: Task file '$file' not found."
        echo "Refreshing cache to remove stale entries..."
        rm -f "$CACHE_FILE"
        refresh_cache
        sleep 1
        return 1
    fi
    return 0
}

# Function to list tasks for fzf
# Format: filename [tab] Task Name [tab] Status [tab] Priority [tab] Created
list_tasks_raw() {
  refresh_cache
  
  current_date=$(date '+%Y-%m-%d')
  
  while IFS='|' read -r slug title task_status priority ignore_until created; do
      # Filter ignored tasks
      if [[ -n "$ignore_until" && "$ignore_until" > "$current_date" ]]; then
        continue
      fi

      # Filter completed tasks
      if [[ "$task_status" == "done" || "$task_status" == "completed" ]]; then
        continue
      fi
      
      printf "%s\t%s\t%s\t%s\t%s\n" "$slug" "$title" "$task_status" "$priority" "$created"
  done < "$CACHE_FILE"
}

select_ignore_date() {
  local days=""
  if command -v gum &> /dev/null; then
      # Gum mode
      local choice=$(gum choose "Tomorrow" "3 days" "1 week" "2 weeks" "1 month" "Cancel")
      
      case "$choice" in
        "Tomorrow") days=1 ;;
        "3 days") days=3 ;;
        "1 week") days=7 ;;
        "2 weeks") days=14 ;;
        "1 month") days=30 ;;
        *) return 1 ;; 
      esac
  else
      # Text mode
      echo "1) Tomorrow"
      echo "2) 3 days"
      echo "3) 1 week"
      echo "4) 2 weeks"
      echo "5) 1 month"
      echo "6) Cancel"
      echo -n "Select (1-6): "
      read -k 1 choice
      echo ""
      case "$choice" in
        1) days=1 ;; 
        2) days=3 ;; 
        3) days=7 ;; 
        4) days=14 ;; 
        5) days=30 ;; 
        *) return 1 ;; 
      esac
  fi
  
  if [[ -n "$days" ]]; then
     date -d "+$days days" '+%Y-%m-%d'
     return 0
  fi
  return 1
}

_create_task_file() {
  local title="$1"
  local priority="${2:-3}"
  local description="$3"
  local success_criteria="$4"
  local ignore_until="$5"
  local initial_status="todo"

  slug=$(slugify "$title")
  target_file="$TODO_DIR/$slug.md"
  
  if [[ -f "$target_file" ]]; then
    echo "Error: Task '$slug' already exists."
    return 1
  fi
  
  if [[ ! -f "$TEMPLATE" ]]; then
    # Fallback if template is missing
    echo "---" > "$target_file"
    echo "task: $title" >> "$target_file"
    echo "status: $initial_status" >> "$target_file"
    echo "priority: $priority" >> "$target_file"
    if [[ -n "$ignore_until" ]]; then
      echo "ignore_until: $ignore_until" >> "$target_file"
    fi
    echo "created: $(date '+%Y-%m-%d')" >> "$target_file"
    echo "---" >> "$target_file"
    echo "" >> "$target_file"
    echo "# $title" >> "$target_file"
    
    if [[ -n "$description" ]]; then
       echo "" >> "$target_file"
       echo "## Description" >> "$target_file"
       echo "$description" >> "$target_file"
    fi

    if [[ -n "$success_criteria" ]]; then
       echo "" >> "$target_file"
       echo "## Success Criteria" >> "$target_file"
       echo "$success_criteria" >> "$target_file"
    fi
  else
    cp "$TEMPLATE" "$target_file"
    
    # Update YAML frontmatter
    sed -i "s/^task: \[Task Name\]/task: $title/" "$target_file"
    sed -i "s/^created: \[Date\]/created: $(date '+%Y-%m-%d')/" "$target_file"
    
    # Update Status if needed (Template defaults to 'todo')
    if [[ "$initial_status" != "todo" ]]; then
        sed -i "s/^status: todo/status: $initial_status/" "$target_file"
    fi

    # Insert priority
    sed -i "/^status: /a priority: $priority" "$target_file"

    # Insert ignore_until if provided
    if [[ -n "$ignore_until" ]]; then
       sed -i "/^priority: /a ignore_until: $ignore_until" "$target_file"
    fi
    
    # Update Markdown Title
    sed -i "s/^# \[Task Name\]/# $title/" "$target_file"

    if [[ -n "$description" ]]; then
       # Replace the placeholder text
       sed -i "s| \[Provide a brief description of the task and its objectives.\].*|$description|" "$target_file"
    else
       # Remove the placeholder line if no description provided
       sed -i "/\[Provide a brief description of the task and its objectives.\]/d" "$target_file"
    fi

    if [[ -n "$success_criteria" ]]; then
       # Replace the placeholder text
       sed -i "s| \[List the specific requirements or outcomes that define successful completion.\].*|$success_criteria|" "$target_file"
    else
       # Remove the placeholder line if no success_criteria provided
       sed -i "/\[List the specific requirements or outcomes that define successful completion.\]/d" "$target_file"
    fi
  fi
  return 0
}

edit_task() {
  if [[ -z "$1" ]]; then return 1; fi
  slug="$1"
  [[ "$slug" != *.md ]] && file="$TODO_DIR/$slug.md" || file="$TODO_DIR/$slug"
  
  if validate_task_file "$file"; then
    	${EDITOR:-nvim} "$file"
  fi
}

create_task_interactive() {
  local title="$1"
  local priority="3"
  local description=""
  local success_criteria=""
  local ignore_until=""
  local ignore_days="0"
  
  if command -v gum &> /dev/null; then
    # --- Gum / TUI Mode ---
    if [[ -z "$title" ]]; then
      title=$(gum input --prompt "Title: " --placeholder "Task Title")
    fi
    
    if [[ -z "$title" ]]; then 
      echo "No title provided. Cancelled."
      return 1 
    fi
    
    # Priority (Default 3)
    priority=$(gum input --value "3" --prompt "Priority (1-3): " --placeholder "3")
    if [[ ! "$priority" =~ ^[1-3]$ ]]; then
       echo "Invalid priority '$priority', defaulting to 3."
       priority="3"
    fi
    
    # Description
    echo "Description (CTRL+D to finish):"
    description=$(gum write --placeholder "Optional. Leave empty for WIP status.")
    
    # Success Criteria
    echo "Success Criteria (CTRL+D to finish):"
    success_criteria=$(gum write --placeholder "Optional.")

    # Hide Until (Default 0 days)
    ignore_days=$(gum input --value "0" --prompt "Hide for days (0=None): " --placeholder "0")
    if [[ "$ignore_days" =~ ^[0-9]+$ ]] && [[ "$ignore_days" -gt 0 ]]; then
       ignore_until=$(date -d "+$ignore_days days" '+%Y-%m-%d')
    fi
    
    if gum confirm "Create Task?"; then
      _create_task_file "$title" "$priority" "$description" "$success_criteria" "$ignore_until"
      gum style --foreground 76 "Task Created!"
      sleep 1
    else
      gum style --foreground 196 "Cancelled."
      sleep 1
      return 1
    fi
    
  else
    # --- Fallback / Text Mode ---
    echo -e "\n--- Create New Task ---"
    # Title
    if [[ -z "$title" ]]; then
      echo -n "Title: "
      read title
    else
      echo "Title: $title"
    fi
    
    if [[ -z "$title" ]]; then return 1; fi

    # Priority
    echo -n "Priority (1-3) [Default: 3]: "
    read input_prio
    if [[ "$input_prio" =~ ^[1-3]$ ]]; then
      priority="$input_prio"
    fi
    
    # Description
    echo -n "Description (Optional): "
    read description

    # Success Criteria
    echo -n "Success Criteria (Optional): "
    read success_criteria
    
    # Hide Until
    echo -n "Hide for days (0=None) [Default: 0]: "
    read input_days
    if [[ "$input_days" =~ ^[0-9]+$ ]] && [[ "$input_days" -gt 0 ]]; then
       ignore_until=$(date -d "+$input_days days" '+%Y-%m-%d')
    fi

    echo -e "\nPreview:"
    echo "  Title:            $title"
    echo "  Priority:         $priority"
    if [[ -n "$description" ]]; then
        echo "  Description:      $description"
    fi
    if [[ -n "$success_criteria" ]]; then
        echo "  Success Criteria: $success_criteria"
    fi
    if [[ -n "$ignore_until" ]]; then
        echo "  Hide Until:       $ignore_until"
    fi
    
    echo -n -e "\n> [ENTER]Submit, [E]dit in nvim, [D]elete/Cancel? "
    read -k 1 confirm
    echo ""

    case "$confirm" in
      s|S|$'\n'|"")
        _create_task_file "$title" "$priority" "$description" "$success_criteria" "$ignore_until"
        echo "Task created."
        sleep 1
        ;; 
      e|E)
        _create_task_file "$title" "$priority" "$description" "$success_criteria" "$ignore_until"
        edit_task "$(slugify "$title")"
        ;; 
      d|D)
        echo "Deleted (Cancelled)."
        sleep 1
        return 1
        ;; 
      *)
        echo "Unknown input. Cancelled."
        sleep 1
        return 1
        ;; 
    esac
  fi
}

add_task() {
  local task_name="$*"
  create_task_interactive "$task_name"
}

complete_task() {
  if [[ -z "$1" ]]; then return 1; fi
  slug="$1"
  [[ "$slug" != *.md ]] && file="$TODO_DIR/$slug.md" || file="$TODO_DIR/$slug"
  
  if validate_task_file "$file"; then
    # Just update the status to done
    sed -i "s/^status: .*/status: done/" "$file"
    echo "Task marked as done: $slug"
  fi
}

ignore_task() {
  if [[ -z "$1" ]]; then return 1; fi
  slug="$1"
  [[ "$slug" != *.md ]] && file="$TODO_DIR/$slug.md" || file="$TODO_DIR/$slug"
  
  if ! validate_task_file "$file"; then
    return 1
  fi
  
  echo -e "\n--- Ignore Task: $slug ---"
  
  ignore_date=$(select_ignore_date)
  if [[ -z "$ignore_date" ]]; then
      echo "Cancelled."
      return 1
  fi

  # Check if ignore_until already exists
  if grep -q "^ignore_until:" "$file"; then
    sed -i "s/^ignore_until: .*/ignore_until: $ignore_date/" "$file"
  else
    # Insert after status or created or at the top of frontmatter
    if grep -q "^status:" "$file"; then
      sed -i "/^status:/a ignore_until: $ignore_date" "$file"
    else
      sed -i "/^---/a ignore_until: $ignore_date" "$file"
    fi
  fi
  echo "Task ignored until $ignore_date"
  sleep 1
}
