#!/bin/bash
# Drain the local nooise backlog when a release slot is due. Run by launchd.
set -euo pipefail
cd /Users/ianburke/adhdisntreal
exec /usr/local/bin/python3 /Users/ianburke/adhdisntreal/.claude/skills/nooise-jam-publish/scripts/queue-runner.py
