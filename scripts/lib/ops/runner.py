#!/usr/bin/env python3
"""Repo-owned justfile helpers. Commands and release hooks live in .ops.toml."""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit("ops: Python 3.11+ is required")
import tomllib


class OpsError(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(1, f"ops: {message}\n")


def capture(root: Path, *args: str) -> str:
    result = subprocess.run(args, cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise OpsError(result.stderr.strip() or f"{shlex.join(args)} failed")
    return result.stdout.strip()


def execute(root: Path, *args: str) -> None:
    print(f"$ {shlex.join(args)}", flush=True)
    subprocess.run(args, cwd=root, check=True)


def load_config(root: Path) -> dict:
    config = tomllib.loads((root / ".ops.toml").read_text())
    if config.get("schema") != 1:
        raise OpsError(".ops.toml must have schema = 1")
    for section in ("commands", "release", "promote"):
        value = config.get(section, {})
        if not isinstance(value, dict) or any(
            not isinstance(v, str) for v in value.values()
        ):
            raise OpsError(f"[{section}] must contain string values")
    return config


def hook(root: Path, command: str, *args: str) -> None:
    # Arguments are shell positional parameters, never interpolated into code.
    execute(root, "sh", "-eu", "-c", command, "ops", *args)


def require_hook(config: dict, section: str, name: str) -> str:
    command = config.get(section, {}).get(name, "").strip()
    if not command:
        raise OpsError(f"configure [{section}] {name} in .ops.toml first")
    return command


def release_guard(root: Path, config: dict) -> None:
    expected = require_hook(config, "release", "branch")
    branch = capture(root, "git", "symbolic-ref", "--quiet", "--short", "HEAD")
    if branch != expected:
        raise OpsError(
            f"release branch is {expected!r}; this worktree is on {branch!r}"
        )
    if capture(root, "git", "status", "--porcelain", "--untracked-files=normal"):
        raise OpsError("working tree has uncommitted or untracked files; commit first")


def resolve_commit(root: Path, ref: str) -> str:
    return capture(
        root, "git", "rev-parse", "--verify", "--end-of-options", ref + "^{commit}"
    )


def release_base(root: Path, pattern: str) -> str | None:
    try:
        matcher = re.compile(pattern)
    except re.error as error:
        raise OpsError(f"invalid release.tag_pattern: {error}") from error
    tags = capture(root, "git", "tag", "--merged", "HEAD").splitlines()
    tags = [tag for tag in tags if matcher.fullmatch(tag)]
    if not tags:
        return None
    # Git chooses a nearby reachable tag; neither sibling branches nor the
    # numerically largest tag in the shared worktree tag namespace can win.
    return capture(
        root,
        "git",
        "describe",
        "--tags",
        "--abbrev=0",
        *[f"--match={t}" for t in tags],
        "HEAD",
    )


def changelog(root: Path, config: dict, base: str) -> None:
    resolve_commit(root, "HEAD")
    pattern = config.get("release", {}).get("tag_pattern", r"^v[0-9]+\.[0-9]+\.[0-9]+$")
    base = base or release_base(root, pattern)
    head = resolve_commit(root, "HEAD")
    start = resolve_commit(root, base) if base else None
    label = (
        f"{base}..HEAD"
        if base
        else "all commits through HEAD (no matching release tag)"
    )
    print(
        f"Release notes: {label}\nCommitted changes only; filtered by cliff.toml.",
        flush=True,
    )
    if start == head:
        print("No commits since this release.")
        return
    if capture(root, "git", "status", "--porcelain", "--untracked-files=normal"):
        print("Note: uncommitted and untracked files are excluded.", flush=True)
    execute(
        root,
        "git-cliff",
        "--config",
        "cliff.toml",
        "--tag-pattern",
        pattern,
        "--tag",
        "Unreleased",
        "--strip",
        "header",
        "--offline",
        "--no-exec",
        f"{start}..{head}" if start else head,
    )


def main() -> int:
    parser = Parser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    run = sub.add_parser("run")
    run.add_argument("name", choices=("dev", "build", "lint", "test"))
    notes = sub.add_parser("changelog")
    notes.add_argument("base", nargs="?", default="")
    changes = sub.add_parser("changes")
    changes.add_argument("base")
    sub.add_parser("unpushed")
    bump = sub.add_parser("bump")
    bump.add_argument(
        "kind", choices=("patch", "minor", "major"), default="patch", nargs="?"
    )
    promote = sub.add_parser("promote")
    promote.add_argument("target")
    sub.add_parser("release")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        config = load_config(root)
        if args.action == "run":
            hook(root, require_hook(config, "commands", args.name))
        elif args.action == "changelog":
            changelog(root, config, args.base)
        elif args.action in ("changes", "unpushed"):
            base = (
                args.base
                if args.action == "changes"
                else capture(
                    root,
                    "git",
                    "rev-parse",
                    "--abbrev-ref",
                    "--symbolic-full-name",
                    "@{upstream}",
                )
            )
            start = resolve_commit(root, base)
            head = resolve_commit(root, "HEAD")
            print(
                f"Commits: {base}..HEAD"
                + (" (local refs; no fetch)" if args.action == "unpushed" else ""),
                flush=True,
            )
            execute(root, "git", "log", "--oneline", f"{start}..{head}")
        else:
            section, name = (
                ("promote", args.target)
                if args.action == "promote"
                else ("release", "publish" if args.action == "release" else "bump")
            )
            command = require_hook(config, section, name)
            release_guard(root, config)
            execute(root, "just", "check")
            release_guard(root, config)
            values = (
                [args.kind]
                if args.action == "bump"
                else ([args.target] if args.action == "promote" else [])
            )
            hook(root, command, *values)
        return 0
    except (OpsError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"ops: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
