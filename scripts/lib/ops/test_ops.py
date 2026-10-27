"""CLI integration tests using real Git, just, and git-cliff in scratch repos."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


OPS = Path(__file__).resolve().parents[2] / "ops"


class OpsIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ops-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo with spaces"
        self.root.mkdir()
        self.env = dict(
            os.environ,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_AUTHOR_NAME="Ops Test",
            GIT_AUTHOR_EMAIL="ops@example.invalid",
            GIT_COMMITTER_NAME="Ops Test",
            GIT_COMMITTER_EMAIL="ops@example.invalid",
        )
        self.git("init", "-b", "main")

    def command(self, *args, cwd=None, expected=0):
        result = subprocess.run(
            args, cwd=cwd or self.root, env=self.env, capture_output=True, text=True
        )
        if expected is not None:
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def git(self, *args, cwd=None, expected=0):
        return self.command("git", *args, cwd=cwd, expected=expected)

    def init(self, profile="rust"):
        return self.command(sys.executable, str(OPS), "init", "--profile", profile)

    def commit(self, message="chore: initial scaffold", cwd=None):
        self.git("add", ".", cwd=cwd)
        self.git("commit", "-m", message, cwd=cwd)

    def configure(self, *, failing_lint=False, branch="main"):
        config = self.root / ".ops.toml"
        content = config.read_text()
        for name in ("dev", "build", "lint", "test"):
            old = next(
                line for line in content.splitlines() if line.startswith(name + " =")
            )
            command = (
                "exit 7" if failing_lint and name == "lint" else f"echo {name} >> trace"
            )
            content = content.replace(old, f"{name} = '{command}'")
        content = content.replace('branch = ""', f'branch = "{branch}"')
        content = content.replace(
            'bump = ""', """bump = 'printf "%s" "$1" > bump-result' """
        )
        content = content.replace(
            'publish = ""', """publish = 'echo publish > publish-result' """
        )
        content = content.replace(
            "[promote]", """[promote]\nbeta = 'printf "%s" "$1" > promote-result' """
        )
        config.write_text(content)
        (self.root / ".gitignore").write_text("trace\n*-result\n")

    def test_scaffold_lists_commands_and_audit_does_not_run_them(self):
        self.init()
        self.configure()
        output = self.command("just").stdout
        self.assertIn("check", output)
        self.assertNotIn("fmt ", output)
        self.assertFalse((self.root / "trace").exists())
        audit = self.command(sys.executable, str(OPS), "audit").stdout
        self.assertIn("0 failure(s)", audit)
        self.assertIn("check depends on lint, test, and build", audit)
        self.assertFalse((self.root / "trace").exists())

    def test_init_refuses_overwrite_and_dry_run_changes_nothing(self):
        original = "# owned by someone else\ncustom:\n    echo keep\n"
        (self.root / "justfile").write_text(original)
        result = self.command(
            sys.executable, str(OPS), "init", "--profile", "rust", expected=1
        )
        self.assertIn("refusing to overwrite", result.stderr)
        self.assertEqual((self.root / "justfile").read_text(), original)
        self.assertFalse((self.root / ".ops.toml").exists())
        preview = self.command(
            sys.executable, str(OPS), "init", "--profile", "rust", "--dry-run"
        )
        self.assertIn("--- a/justfile", preview.stdout)
        self.assertEqual((self.root / "justfile").read_text(), original)
        self.assertFalse((self.root / "scripts").exists())

    def test_init_refuses_symlinked_destination_without_partial_scaffold(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (self.root / "scripts").symlink_to(outside, target_is_directory=True)
        self.command(sys.executable, str(OPS), "init", "--profile", "rust", expected=1)
        self.assertFalse((self.root / "justfile").exists())
        self.assertEqual(list(outside.iterdir()), [])

    def test_custom_profile_requires_real_commands(self):
        self.init("custom")
        audit = self.command(sys.executable, str(OPS), "audit", expected=1)
        self.assertIn("configure [commands] build", audit.stdout)
        build = self.command("just", "build", expected=1)
        self.assertIn("configure [commands] build", build.stderr)

    def test_check_stops_on_failure_and_release_hook_never_runs(self):
        self.init()
        self.configure(failing_lint=True)
        self.commit()
        self.command("just", "check", expected=1)
        self.assertFalse((self.root / "trace").exists())
        self.command("just", "release", expected=1)
        self.assertFalse((self.root / "publish-result").exists())

    def test_release_hooks_require_configuration_cleanliness_and_branch(self):
        self.init()
        self.command("just", "bump", expected=1)
        self.configure()
        self.commit()
        (self.root / "untracked").touch()
        result = self.command("just", "bump", expected=1)
        self.assertIn("untracked files", result.stderr)
        self.assertFalse((self.root / "trace").exists())
        (self.root / "untracked").unlink()
        self.git("switch", "-c", "v3")
        result = self.command("just", "release", expected=1)
        self.assertIn("this worktree is on 'v3'", result.stderr)
        self.assertFalse((self.root / "publish-result").exists())

    def test_bump_and_promote_receive_arguments_after_passing_checks(self):
        self.init()
        self.configure()
        self.commit()
        self.command("just", "bump", "minor")
        self.assertEqual((self.root / "bump-result").read_text(), "minor")
        self.assertEqual((self.root / "trace").read_text(), "lint\ntest\nbuild\n")
        self.command("just", "promote", "beta")
        self.assertEqual((self.root / "promote-result").read_text(), "beta")
        self.command("just", "bump", "oops", expected=1)

    def test_changelog_uses_reachable_stable_tag_and_never_infers_version(self):
        self.init()
        self.commit()
        self.git("tag", "v1.0.0")
        self.git("switch", "-c", "sibling")
        (self.root / "sibling").touch()
        self.commit("feat: sibling-only change")
        self.git("tag", "v99.0.0")
        self.git("switch", "main")
        (self.root / "feature").touch()
        self.commit("feat: actual feature")
        self.git("tag", "v1.1.0-alpha.1")
        result = self.command("just", "changelog")
        self.assertIn("v1.0.0..HEAD", result.stdout)
        self.assertIn("## Unreleased", result.stdout)
        self.assertIn("actual feature", result.stdout)
        self.assertNotIn("sibling-only", result.stdout)
        self.assertNotIn("## 1.1.0", result.stdout)

    def test_first_release_and_empty_changelog(self):
        self.init()
        self.commit("feat: first feature")
        first = self.command("just", "changelog")
        self.assertIn("first feature", first.stdout)
        self.git("tag", "v1.0.0")
        empty = self.command("just", "changelog")
        self.assertIn("No commits since this release", empty.stdout)

    def test_ref_arguments_cannot_execute_shell_code(self):
        self.init()
        self.commit()
        malicious = "$(touch SHELL_EXECUTED)"
        result = self.command("just", "changes", malicious, expected=1)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse((self.root / "SHELL_EXECUTED").exists())

    def test_upstream_comparison_and_missing_upstream(self):
        self.init()
        self.commit()
        self.command("just", "unpushed", expected=1)
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("config", "remote.origin.url", "/nonexistent-no-fetch")
        self.git("config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
        self.git("config", "branch.main.remote", "origin")
        self.git("config", "branch.main.merge", "refs/heads/main")
        (self.root / "feature").touch()
        self.commit("fix: local-only fix")
        result = self.command("just", "unpushed")
        self.assertIn("local refs; no fetch", result.stdout)
        self.assertIn("local-only fix", result.stdout)

    def test_linked_worktree_runs_hooks_in_its_own_checkout(self):
        self.init()
        self.configure(branch="v3")
        self.commit()
        linked = Path(self.temp.name) / "v3"
        self.git("worktree", "add", "-b", "v3", str(linked))
        self.command("just", "bump", "major", cwd=linked)
        self.assertEqual((linked / "bump-result").read_text(), "major")
        self.assertFalse((self.root / "bump-result").exists())
        self.assertEqual(self.git("branch", "--show-current").stdout.strip(), "main")

    def test_audit_does_not_evaluate_backticks_or_execute_untrusted_helper(self):
        self.init()
        justfile = self.root / "justfile"
        justfile.write_text("danger := `touch AUDIT_EXECUTED`\n" + justfile.read_text())
        (self.root / "scripts/ops.py").write_text(
            "raise RuntimeError('untrusted helper ran')\n"
        )
        self.command(sys.executable, str(OPS), "audit")
        self.assertFalse((self.root / "AUDIT_EXECUTED").exists())

    def test_rust_profile_checks_a_new_crate_without_a_lockfile(self):
        self.command(
            "cargo", "init", "--bin", "--name", "ops_smoke", "--vcs", "none", "."
        )
        self.assertFalse((self.root / "Cargo.lock").exists())
        self.init()
        self.command("just", "check")
        self.assertTrue((self.root / "Cargo.lock").is_file())

    def test_audit_warns_when_default_lists_commands_and_also_mutates(self):
        self.init()
        justfile = self.root / "justfile"
        justfile.write_text(
            justfile.read_text().replace(
                "@just --list", "@just --list; touch UNSAFE_DEFAULT"
            )
        )
        audit = self.command(sys.executable, str(OPS), "audit")
        self.assertIn("WARN: bare just selects", audit.stdout)
        self.assertNotIn("PASS: bare just lists commands", audit.stdout)
        self.assertFalse((self.root / "UNSAFE_DEFAULT").exists())


if __name__ == "__main__":
    unittest.main()
