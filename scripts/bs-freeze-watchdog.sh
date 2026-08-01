#!/usr/bin/env bash

set -uo pipefail

PATH=/usr/local/bin:/usr/bin:/bin
export PATH

state_dir=/Users/ianburke/.claude/babysit-runs
log_file="$state_dir/watchdog.log"
consec_file="$state_dir/watchdog-consec"
nudges_file="$state_dir/watchdog-nudges"

log() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ) || timestamp=unknown-time
    printf '%s\t%s\n' "$timestamp" "$*" >>"$log_file" 2>/dev/null || true
}

if ! mkdir -p "$state_dir" 2>/dev/null; then
    exit 0
fi

selected_socket=
panes_json=
list_probe_succeeded=0
for socket in /Users/ianburke/.plexi-beta/notify.sock /Users/ianburke/.plexi/notify.sock; do
    if [[ ! -S "$socket" ]]; then
        continue
    fi

    export PLEXI_SOCKET="$socket"
    if ! candidate_json=$(plexi pane list 2>/dev/null); then
        continue
    fi
    list_probe_succeeded=1

    if candidate_has_head=$(printf '%s' "$candidate_json" | /usr/bin/python3 -c '
import json
import sys

try:
    panes = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    sys.exit(1)

print(int(any("bs-head" in (pane.get("title") or "") for pane in panes)))
'); then
        if [[ "$candidate_has_head" == 1 ]]; then
            selected_socket=$socket
            panes_json=$candidate_json
            break
        fi
    fi
done

if [[ -z "$selected_socket" ]]; then
    printf '0\n' >"$consec_file" 2>/dev/null || true
    if [[ "$list_probe_succeeded" == 0 ]]; then
        log "plexi pane list failed on all candidate sockets"
    fi
    log "no bs-head pane found"
    exit 0
fi

export PLEXI_SOCKET="$selected_socket"

# Only real run lanes may suppress a nudge. A lane is a pane the head spawned:
# either its title carries a lane prefix, or RUN_STATE.md names its id. An
# interactive "me" session is neither, and must never keep the watchdog quiet.
run_state_file=/Users/ianburke/Documents/GitHub/PLEXI/.agents/skills/babysitter/RUN_STATE.md
run_state_ids=
if [[ -r "$run_state_file" ]]; then
    run_state_ids=$(grep -oiE 'pane[[:space:]]+#?[0-9]+' "$run_state_file" 2>/dev/null \
        | grep -oE '[0-9]+' | sort -u | tr '\n' ',')
fi
export WD_RUN_STATE_IDS="$run_state_ids"

if ! pane_summary=$(printf '%s' "$panes_json" | /usr/bin/python3 -c '
import json
import os
import sys

try:
    panes = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError):
    sys.exit(1)

lane_ids = {
    part for part in os.environ.get("WD_RUN_STATE_IDS", "").split(",") if part
}
lane_prefixes = ("worker-", "tester-", "merge-", "bs-")

eligible = [
    pane for pane in panes
    if pane.get("context_name") == "me" and pane.get("agent") is not None
]
heads = [pane for pane in eligible if "bs-head" in (pane.get("title") or "")]
if not heads:
    print()
    sys.exit(0)

head = heads[0]
head_id = head.get("id")
state = head.get("agent", {}).get("state", "unknown")


def is_lane(pane):
    if pane.get("id") == head_id:
        return False
    title = pane.get("title") or ""
    if any(prefix in title for prefix in lane_prefixes):
        return True
    return str(pane.get("id")) in lane_ids


working_lanes = sum(
    1 for pane in eligible
    if is_lane(pane) and pane.get("agent", {}).get("state") == "working"
)
skipped = sum(
    1 for pane in eligible
    if not is_lane(pane)
    and pane.get("id") != head_id
    and pane.get("agent", {}).get("state") == "working"
)
print(
    str(head_id) + "\t" + str(state) + "\t" + str(working_lanes)
    + "\t" + str(skipped)
)
'); then
    log "socket $selected_socket: unable to parse pane list"
    exit 0
fi

if [[ -z "$pane_summary" ]]; then
    printf '0\n' >"$consec_file" 2>/dev/null || true
    log "socket $selected_socket; no eligible bs-head pane in context me; frozen=no; consecutive=0"
    exit 0
fi

IFS=$'\t' read -r head_id head_state working_lanes non_lane_working <<<"$pane_summary"
head_status=
if ! head_status=$(plexi pane slot read status "$head_id" 2>/dev/null); then
    head_status=
fi
status_display=$head_status
if [[ -z "$status_display" ]]; then
    status_display='<empty>'
fi

if [[ "$head_status" == *:done || "$head_status" == *:blocked || "$head_status" == *:failed ]]; then
    printf '0\n' >"$consec_file" 2>/dev/null || true
    log "socket $selected_socket; head pane $head_id state=$head_state; working-lanes=$working_lanes (non-lane working panes ignored: $non_lane_working); head status=$status_display; frozen=no; consecutive=0; head terminal ($head_status) - no action"
    exit 0
fi

frozen=0
if [[ "$head_state" != working && "$working_lanes" == 0 ]]; then
    frozen=1
fi

consecutive=0
if [[ -f "$consec_file" ]]; then
    consecutive=$(<"$consec_file")
fi
if [[ ! "$consecutive" =~ ^[0-9]+$ ]]; then
    consecutive=0
fi

if [[ "$frozen" == 0 ]]; then
    printf '0\n' >"$consec_file" 2>/dev/null || true
    log "socket $selected_socket; head pane $head_id state=$head_state; working-lanes=$working_lanes (non-lane working panes ignored: $non_lane_working); head status=$status_display; frozen=no; consecutive=0; no action"
    exit 0
fi

consecutive=$((consecutive + 1))
printf '%s\n' "$consecutive" >"$consec_file" 2>/dev/null || true
log "socket $selected_socket; head pane $head_id state=$head_state; working-lanes=$working_lanes (non-lane working panes ignored: $non_lane_working); head status=$status_display; frozen=yes; consecutive=$consecutive"

if (( consecutive < 2 )); then
    log "debounce awaiting second consecutive frozen detection - no action"
    exit 0
fi

now=$(date +%s) || now=0
cutoff=$((now - 3600))
kept_nudges=
recent_nudges=0
if [[ -f "$nudges_file" ]]; then
    nudge_history=$(<"$nudges_file")
    while IFS= read -r epoch || [[ -n "$epoch" ]]; do
        if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch >= cutoff )); then
            kept_nudges+="${epoch}"$'\n'
            recent_nudges=$((recent_nudges + 1))
        fi
    done <<<"$nudge_history"
fi
printf '%s' "$kept_nudges" >"$nudges_file" 2>/dev/null || true

if (( recent_nudges >= 3 )); then
    log "nudge cap reached (3/hour) - skipping"
    exit 0
fi

# Single line on purpose: an embedded newline submits the first line on its own,
# so the marker and the instruction would arrive as two separate prompts.
nudge_message='[AGENT MSG — from: freeze-watchdog — not Ian] You are idle with the run unfinished. Resume per RUN_STATE.md, or end properly: write status slot head:done or head:blocked with the ask in last_error.'
if ! plexi pane send "$head_id" "$nudge_message" 2>/dev/null; then
    log "nudge send failed - no action"
    exit 0
fi
if ! plexi pane key "$head_id" enter 2>/dev/null; then
    log "nudge enter failed - no action"
    exit 0
fi

printf '%s\n' "$now" >>"$nudges_file" 2>/dev/null || true
printf '0\n' >"$consec_file" 2>/dev/null || true
log "nudge sent; consecutive=0"
