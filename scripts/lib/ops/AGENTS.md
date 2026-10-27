# Repo operations scaffold

## Purpose

Own `scripts/ops`'s templates, generated runtime, and CLI integration tests.

## Local Contracts

- `scripts/ops` generates `justfile`, `cliff.toml`, `.ops.toml`, and `scripts/ops.py` from these sources. Generated repos own their copies and need no dotfiles checkout.
- Initialization never overwrites existing paths or follows symlinked destinations. `--dry-run` prints proposed diffs.
- Audit parses justfiles and config without executing recipes, backticks, or repo-owned Python helpers. It reports conventions, not runtime acceptance.
- Bare `just` lists commands. `check` runs lint, tests, then build. No formatting recipe; lint validates formatting without rewriting files.
- Bump, promotion, and publication require explicit hooks, a clean checkout on the configured source branch, and a passing `just check`. Branch movement, tag validation, and publication details belong to the repo's hooks.
- Changelog previews use reachable matching release tags and committed history, without inferring a version. Tags are shared across Git worktrees; operate on the invoked checkout.

## Verification

- `uv run --no-project --python 3.13 python -m unittest discover -s scripts/lib/ops -p 'test_*.py' -v`
- Integration tests require `git`, `just`, `git-cliff`, and Cargo with rustfmt and Clippy; all mutations happen in temporary repositories.
- The install workflow runs the suite on macOS and Ubuntu after installing the Brewfile.
