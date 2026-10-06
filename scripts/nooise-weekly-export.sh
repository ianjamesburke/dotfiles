#!/bin/bash
# Weekly YouTube export into the adhdisntreal analytics folder. Run by launchd (Saturdays).
set -euo pipefail
cd /Users/ianburke/adhdisntreal
exec /usr/local/bin/python3 "$HOME/.claude/skills/youtube-companion/scripts/yt-export.py" --out "analytics/$(date +%F)"
