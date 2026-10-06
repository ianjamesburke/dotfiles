#!/usr/bin/env python3
"""Deterministic sweep: surface decision-log entries whose review is due.

Scans ~/.decision-log/decision_history.json for entries with outcome==null and
review_due <= today. On each run it (1) overwrites STATUS.md in the skill dir,
(2) manages a sentinel-delimited block in MEMORY.md (loaded every session), and
(3) posts a best-effort macOS notification if any reviews are due. Does NOT run
any LLM — the interactive follow-up is handled by the /decision-review skill.
Fails loud: a malformed log or missing field is surfaced, not swallowed.
"""

from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

LOG = Path.home() / ".decision-log" / "decision_history.json"
STATUS = (
    Path.home()
    / ".agents"
    / "skills"
    / "deciding-how-long-to-decide"
    / "STATUS.md"
)
MEMORY = (
    Path.home()
    / ".claude"
    / "projects"
    / "-Users-ianburke"
    / "memory"
    / "MEMORY.md"
)
MEM_START = "<!-- DECISION-REVIEW:START -->"
MEM_END = "<!-- DECISION-REVIEW:END -->"


def update_memory_block(due: list[dict], today: dt.date) -> None:
    """Manage a sentinel-delimited block in MEMORY.md (loaded every session).

    The script owns ONLY the region between MEM_START/MEM_END. When reviews are
    due it inserts/refreshes the block; when none are due it removes the block
    entirely so MEMORY.md stays clean. Hand-curated content is never touched.
    """
    if not MEMORY.exists():
        # Don't create MEMORY.md from here — it's hand-curated. Nothing to do.
        return

    text = MEMORY.read_text()
    start = text.find(MEM_START)
    end = text.find(MEM_END)
    has_block = start != -1 and end != -1 and end > start

    if not due:
        if has_block:
            before = text[:start].rstrip("\n")
            after = text[end + len(MEM_END):].lstrip("\n")
            new = (before + "\n\n" + after).rstrip("\n") + "\n" if after else before + "\n"
            MEMORY.write_text(new)
        return

    n = len(due)
    block = (
        f"{MEM_START}\n"
        f"## ⚠️ Decision Reviews Overdue\n\n"
        f"{n} logged decision(s) are due for review (as of {today.isoformat()}). "
        f"Proactively offer to run `/decision-review` this session.\n"
        f"{MEM_END}"
    )

    if has_block:
        new = text[:start] + block + text[end + len(MEM_END):]
    else:
        new = text.rstrip("\n") + "\n\n" + block + "\n"
    MEMORY.write_text(new)


def write_status(due: list[dict], today: dt.date) -> None:
    """Overwrite the skill-local status file. Script owns this file entirely."""
    if due:
        lines = [
            "# Decision Review Status",
            "",
            f"**⚠️ OVERDUE: {len(due)} decision(s) due for review "
            f"(as of {today.isoformat()}).**",
            "",
            "Run `/decision-review` to resolve them. Overdue entries:",
            "",
        ]
        for e in due:
            d = e.get("decision", "(unnamed)")
            lines.append(f"- {d} (due {str(e.get('review_due'))[:10]})")
    else:
        lines = [
            "# Decision Review Status",
            "",
            f"✅ No reviews due (checked {today.isoformat()}).",
        ]
    STATUS.parent.mkdir(parents=True, exist_ok=True)
    STATUS.write_text("\n".join(lines) + "\n")


def notify(title: str, message: str) -> None:
    """Post a macOS notification via osascript. Best-effort: a blocked or missing
    notification channel must never stall the sweep, so it is timeout-guarded and
    failures are logged, not raised (STATUS.md is the durable signal)."""
    script = (
        f'display notification {json.dumps(message)} '
        f'with title {json.dumps(title)}'
    )
    try:
        subprocess.run(
            ["osascript", "-e", script],
            check=True,
            timeout=10,
            capture_output=True,
        )
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, OSError) as e:
        print(f"decision-review-check: notification failed (non-fatal): {e}", file=sys.stderr)


def main() -> int:
    today = dt.date.today()

    if not LOG.exists():
        # No log yet is not an error — nothing to review.
        write_status([], today)
        update_memory_block([], today)
        return 0

    try:
        entries = json.loads(LOG.read_text())
    except json.JSONDecodeError as e:
        print(f"decision-review-check: {LOG} is not valid JSON: {e}", file=sys.stderr)
        return 1

    if not isinstance(entries, list):
        print(f"decision-review-check: {LOG} must be a JSON array", file=sys.stderr)
        return 1

    due = []
    for i, entry in enumerate(entries):
        if entry.get("outcome") is not None:
            continue
        raw = entry.get("review_due")
        if not raw:
            print(
                f"decision-review-check: entry {i} ({entry.get('id', '?')}) "
                f"is unresolved but has no review_due",
                file=sys.stderr,
            )
            continue
        try:
            review_due = dt.date.fromisoformat(str(raw)[:10])
        except ValueError as e:
            print(
                f"decision-review-check: entry {i} has bad review_due {raw!r}: {e}",
                file=sys.stderr,
            )
            continue
        if review_due <= today:
            due.append(entry)

    write_status(due, today)
    update_memory_block(due, today)

    if not due:
        return 0

    n = len(due)
    sample = due[0].get("decision", "(unnamed decision)")
    preview = sample if len(sample) <= 60 else sample[:57] + "..."
    msg = f'{n} decision{"s" if n != 1 else ""} due for review. e.g. "{preview}"'
    notify("Decision review due", msg)
    print(msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
