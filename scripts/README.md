# dotfiles/scripts

Personal automation scripts shared across machines (macOS + Linux/Omarchy).

## The System: Git-Backed Daily Logging

`~/github/daily_log/` is the **single source of truth** for all personal data — voice transcripts, screen time, journals. Everything writes files there; a background timer auto-syncs to GitHub every 5 minutes.

### Data Flow

```
Mac                                          Omarchy (Linux)
───                                          ───────────────
screen_time_watcher_v2.py                    DJI Wireless Mic (WAV)
  │ writes JSONL                                   │
  ▼                                            dji-pull
daily_log/_screen.jsonl ◄── git sync ──►         │
                                             audio-compress
journal scripts                                  │
  │ writes markdown                          audio-transcribe
  ▼                                              │
daily_log/_am.md        ◄── git sync ──►     daily_log/_mlog.md

                    ┌─── ~/github/daily_log/ ───┐
                    │  YYYY-MM-DD_screen.jsonl   │ ← raw screen time (JSONL)
                    │  YYYY-MM-DD_screen.md      │ ← formatted summary
                    │  YYYY-MM-DD_mlog.md        │ ← voice transcript
                    │  YYYY-MM-DD_am.md          │ ← morning journal
                    │  YYYY-MM-DD_log.md         │ ← general journal
                    └────────────┬───────────────┘
                                 │
                         daily-log-sync (timer, 5 min)
                                 │
                              GitHub
```

### File Formats

**Screen time** (`_screen.jsonl`) — append-only, one JSON object per line:
```json
{"t":"2026-02-21T09:15:23","app":"VS Code","detail":"mlog.sh","secs":300}
{"t":"2026-02-21T09:20:15","app":"Chrome","detail":"GitHub","secs":180}
{"t":"2026-02-21T14:00:00","app":"Ghostty","secs":45,"active":true}
```
- `active: true` = currently using this app right now
- `idle: true` = user went idle
- Last entry shows what's happening *right now* (updated every 5 min)

**Screen time summary** (`_screen.md`) — human-readable, auto-generated every 15 min from the JSONL.

## Audio Pipeline

Each script works standalone and outputs file paths to stdout for piping.

| Script | Purpose | Usage |
|--------|---------|-------|
| `dji-pull` | Mount DJI recorder, copy WAVs to `~/mlog_audio/inbox/` | `dji-pull` or `dji-pull --all` |
| `audio-compress` | Normalize + convert to MP3 (-10 LUFS) | `audio-compress file.wav [file2.wav ...]` |
| `audio-transcribe` | Whisper → markdown in daily_log | `audio-transcribe file.mp3 [--date YYYY-MM-DD]` |
| `mlog` | Orchestrator: pull → compress → transcribe | `mlog` or `mlog -f file.wav` |

## Screen Time

| Script | Where | Purpose |
|--------|-------|---------|
| `screen_time_watcher_v2.py` | Mac (`scripts-from-mac/WIP/`) | Writes JSONL to daily_log |
| `screen-time-status` | Omarchy (`dotfiles/scripts/`) | CLI: show current screen time |
| `screen-time-log` | Omarchy (`dotfiles/scripts/`) | Timer: write `_screen.md` summary |

**Mac setup:**
```bash
# Start the watcher (from ~/Documents/Github/scripts-from-mac/)
killall -9 Python 2>/dev/null
nohup WIP/screen_time_watcher_v2.py > /dev/null 2>&1 &
```

The watcher writes directly to the Mac's local `daily_log` clone. Git sync (on both machines) keeps them in sync.

## Background Services (systemd user timers)

| Timer | Interval | Purpose |
|-------|----------|---------|
| `daily-log-sync.timer` | 5 min | Git add/commit/push daily_log |
| `screen-time-log.timer` | 15 min | Generate `_screen.md` from JSONL |
| `check_log.timer` | 10 min | Desktop notification if no journal today |

```bash
# Check all timers
systemctl --user list-timers

# Manually trigger sync
systemctl --user start daily-log-sync.service
```

## Other Scripts

| Script | Purpose |
|--------|---------|
| `log` | Open today's journal in neovim |
| `note` | Quick note to daily log |
| `check_log` | Nag notification if journal is stale |
| `sync-nvim.sh` | Sync neovim config |
| `todo` | Quick task management |

## Cross-Machine Architecture

| | Mac | Omarchy |
|--|-----|---------|
| **Screen time** | `screen_time_watcher_v2.py` writes JSONL | `screen-time-log` generates summary |
| **Voice logs** | — | `mlog` (DJI recorder plugs in here) |
| **Journals** | `journal-morning.sh` (in daily_log/scripts/) | `log` script |
| **Git sync** | Needs cron/launchd equivalent | `daily-log-sync.timer` (systemd) |

### Mac Setup

**Git sync** (launchd plist in `dotfiles/launchd/`):
```bash
# Symlink and load the plist
ln -sf ~/dotfiles/launchd/com.ian.daily-log-sync.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.ian.daily-log-sync.plist

# Verify it's running
launchctl list | grep daily-log-sync
```

**Screen time watcher:**
```bash
# Start V2 (from scripts-from-mac/)
nohup WIP/screen_time_watcher_v2.py > /dev/null 2>&1 &
```

- [ ] Switch from `app_switch_listener.py` (V1) to `screen_time_watcher_v2.py` once confirmed working
- [ ] Ensure daily_log repo is cloned at `~/Documents/Github/daily_log` (or set `DAILY_LOG_PATH`)

## Dependencies

- `ffmpeg` / `ffprobe` — audio processing
- `whisper` — transcription (`pipx install openai-whisper`)
- `udisksctl` — USB auto-mounting (Linux)
- `python3` — screen time scripts
- `PyObjC` — Mac screen time watcher (AppKit, Quartz)
