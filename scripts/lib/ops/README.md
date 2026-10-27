# Repo operations

`ops` scaffolds repo-local justfiles and checks existing ones against the same conventions.
Requires Python 3.11+, Git, just, and git-cliff. These are in the dotfiles Brewfile.
Rust projects also need Cargo, rustfmt, and Clippy.

```sh
cd /path/to/project
ops init --profile rust
just                         # list commands
ops audit
just check                   # lint, test, build; stop at the first failure
```

Use `--profile custom` for any other stack. Fill in `dev`, `build`, `lint`, and
`test` under `[commands]` in `.ops.toml`. For example, `build = "npm run build"`
and `test = "npm test"`. The Rust profile supplies Cargo commands; adapt their
flags, workspace/package selection, and build mode for the repo.

`lint` checks formatting without rewriting files. `check` groups the required
local checks; it does not install, publish, or establish human acceptance.

## Existing projects

```sh
ops audit /path/to/project
ops init /path/to/project --profile rust --dry-run
```

Audit checks command names, default-recipe behavior, declared `check`
dependencies, config, and tool availability. It does not run any recipe or
repo-owned helper, evaluate justfile backticks, fetch Git refs, or prove that a
recipe does what its name claims. Exit status is 1 for missing requirements or
invalid files, 0 otherwise. Warnings identify manual configuration or review.

Initialization writes `justfile`, `cliff.toml`, `.ops.toml`, and `scripts/ops.py`.
All are ordinary files owned by the target repo, with no dependency on dotfiles
after generation. Commit them together. Existing files and symlinked destinations
are refused before writing; `--dry-run` prints proposed diffs for manual adoption.
There is no automatic merge or overwrite mode.

## Changes and release notes

```sh
just changelog               # since a nearby reachable matching release tag
just changelog v2.9.1        # explicit comparison boundary
just changes main           # every commit in main..HEAD, without note filtering
just unpushed                # upstream..HEAD, using local refs without a fetch
```

The release tag pattern defaults to stable `vX.Y.Z` tags. Change
`[release] tag_pattern` and `[git] tag_pattern` in `cliff.toml` together if the
repo uses another scheme. Unreachable tags from sibling branches are excluded.
The first release includes all committed history. Previews are titled
`Unreleased`, without guessing the next version. Uncommitted files are excluded.

`cliff.toml` groups `feat`, `fix`, and `perf` commits and skips routine internal
changes and merge messages. Edit these filters for the product. Release notes
are a filtered view; use `changes` or `unpushed` to see all commits in a range.

## Bump, promote, and publish

The scaffold leaves release hooks empty. Set the source branch explicitly and
point hooks at the repo's release scripts in `.ops.toml`:

```toml
[release]
branch = "alpha"
tag_pattern = '^v[0-9]+\.[0-9]+\.[0-9]+$'
bump = 'bash scripts/bump.sh "$1"'
publish = 'bash scripts/publish.sh'

[promote]
beta = 'bash scripts/promote.sh "$1"'
```

```sh
just bump                    # patch
just bump minor
just bump major
just promote beta
just release
```

Before invoking these hooks, the helper requires a clean worktree, including
untracked files, on the configured branch. It runs `just check` and checks the
branch and worktree again. Everything runs in the checkout containing the
generated helper, including linked worktrees. The helper never redirects to the
primary worktree or guesses a push destination.

Hooks are shell commands run with `sh -eu`. `bump` receives patch/minor/major as
`$1`; a promotion hook receives its configured target as `$1`. Keep each script
responsible for its own validation and error handling:

- Bump updates version files and locks, generates the changelog, commits, and
  tags locally. It should leave push and publication for later commands.
- Promotion validates the source and destination, moves the approved commit,
  and handles any destination worktree. Omit targets the repo does not use.
- Publication validates the prepared version and tag against the intended
  commit, then pushes and publishes through that repo's registries or CI.

The helper guards invocation. It cannot validate the contents of a custom hook
or make multi-service publication atomic. Test hooks in the target repo before
using them to release.

## Tests

From dotfiles:

```sh
uv run --no-project --python 3.13 python -m unittest discover -s scripts/lib/ops -p 'test_*.py' -v
```

Tests exercise the CLI, generated recipes, changelog boundaries, upstream
comparisons, failure handling, and worktree isolation using real tools in
temporary repositories. The fresh Rust crate check also requires Cargo with
rustfmt and Clippy.
