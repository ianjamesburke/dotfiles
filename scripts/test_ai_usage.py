"""Pace math for scripts/ai-usage. Run: uv run --with pytest pytest scripts/test_ai_usage.py"""
from datetime import datetime, timedelta, timezone
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

loader = SourceFileLoader("ai_usage", str(Path(__file__).with_name("ai-usage")))
ai_usage = module_from_spec(spec_from_loader("ai_usage", loader))
loader.exec_module(ai_usage)

NOW = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)


def week(used_pct: float, elapsed_h: float) -> dict:
    return ai_usage.window("7-day", used_pct, NOW + timedelta(hours=168 - elapsed_h), 168, now=NOW)


def test_early_window_shows_no_projection():
    w = week(12, 8)  # 12% used 8h into a 7d window used to read 252% OVER
    assert w["projected_pct"] is None and w["over_pace"] is None


def test_mid_window_projects_linearly():
    w = week(30, 84)  # half elapsed, 30% used -> 60%
    assert w["projected_pct"] == 60.0 and w["over_pace"] is False


def test_over_pace_flagged_once_signal_is_real():
    w = week(70, 84)
    assert w["projected_pct"] == 140.0 and w["over_pace"] is True
