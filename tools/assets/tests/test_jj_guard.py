"""The licence guard must hold under jj as well as under git.

jj does not run git hooks, has no hook system of its own, and refuses to let an
alias shadow a built-in command, so the `pre-commit` hook that protects a `git
commit` protects nothing when the commit is made through jj. What protects it
instead is the wrapper `tools/git/install_hooks.sh` installs as the `jj` on PATH.

Seam: the installed wrapper, run as `jj` inside a colocated repository. Its
contract is the same as the hook's — exit status and message, nothing else.

Skips itself when jj is not installed: jj is optional here, git is not.
"""

import os
import shutil
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

REPO = Path(__file__).resolve().parents[3]
INSTALLER = REPO / "tools" / "git" / "install_hooks.sh"
TEMPLATE = REPO / "tools" / "git" / "jj-wrapper.sh"


def jj_binary():
    """The real jj, not whatever wrapper is on PATH — a test must not depend on
    the developer having already run the installer, and must not mistake the
    wrapper for the thing it wraps.

    Same place `tools/git/install_hooks.sh` looks and `.github/ci/install_toolchain.sh`
    installs to, which is why neither of them puts the bare binary on PATH."""
    opt = Path(os.environ.get("TOOLCHAIN_DIR", Path.home() / ".local" / "opt"))
    for candidate in sorted(opt.glob("jj-*/jj"), reverse=True):
        if os.access(candidate, os.X_OK):
            return candidate
    return None


def git(repo, *args, check=True):
    env = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="t@e.com",
               GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@e.com")
    return subprocess.run(["git", *args], cwd=repo, check=check,
                          capture_output=True, text=True, env=env)


class JjLicenceGuard(unittest.TestCase):
    def setUp(self):
        self.jj = jj_binary()
        if self.jj is None:
            self.skipTest("jj is not installed under ~/.local/opt/jj-*/jj")
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        self.bin = Path(self.tmp.name) / "bin"
        self.repo.mkdir()
        self._make_colocated_repo()
        self._install_wrapper()

    def _make_colocated_repo(self):
        """A repository shaped like this one: public, assets_licensed/ ignored,
        carrying this repo's own guard tooling, with jj colocated onto git."""
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "t@e.com")
        git(self.repo, "config", "user.name", "T")
        for sub in ("tools/assets", "tools/git"):
            dst = self.repo / sub
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(REPO / sub, dst)
        (self.repo / ".gitignore").write_text(
            "/assets_licensed/\n!/assets_licensed/.gdignore\n/.jj/\n")
        quarantine = self.repo / "assets_licensed"
        quarantine.mkdir()
        (quarantine / ".gdignore").write_text("")
        (self.repo / "README.md").write_text("hello\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "tooling")
        subprocess.run([str(self.jj), "git", "init", "--colocate"], cwd=self.repo,
                       check=True, capture_output=True, text=True)

    def _install_wrapper(self):
        subprocess.run(["bash", str(INSTALLER)], cwd=self.repo, check=True,
                       capture_output=True, text=True,
                       env=dict(os.environ, JJ_WRAPPER_BIN=str(self.bin),
                                JJ_REAL=str(self.jj)))
        config = Path(self.tmp.name) / "jj.toml"
        config.write_text('[user]\nname = "T"\nemail = "t@e.com"\n')
        self.env = dict(os.environ,
                        PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                        JJ_CONFIG=str(config))
        self.env.pop("JJ_GUARD_RUNNING", None)

    def jj_run(self, *args):
        return subprocess.run(["jj", *args], cwd=self.repo, capture_output=True,
                              text=True, env=self.env)

    def test_the_installer_puts_a_wrapper_on_path(self):
        wrapper = self.bin / "jj"
        self.assertTrue(wrapper.exists(), f"missing {wrapper}")
        self.assertTrue(os.access(wrapper, os.X_OK), f"{wrapper} is not executable")
        self.assertNotIn("@JJ_REAL@", wrapper.read_text(),
                         "the installer left the template's placeholder in place")
        self.assertEqual(self.jj_run("--version").returncode, 0,
                         "the wrapper does not pass an ordinary command through")

    def test_an_ordinary_commit_is_allowed(self):
        (self.repo / "notes.md").write_text("fine\n")
        result = self.jj_run("commit", "-m", "ordinary work")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_quarantined_file_in_the_working_copy_blocks_a_commit(self):
        # The way this happens in practice: the .gitignore entry stops covering
        # the quarantine, and jj — which snapshots the working copy on its own,
        # with no `git add` in the way — picks the whole of it up at the next
        # command. There is no index to leave it out of.
        (self.repo / ".gitignore").write_text("!/assets_licensed/.gdignore\n/.jj/\n")
        purchased = self.repo / "assets_licensed" / "synty" / "Hero.fbx"
        purchased.parent.mkdir()
        purchased.write_bytes(b"purchased")

        result = self.jj_run("commit", "-m", "sneak it in")
        self.assertNotEqual(result.returncode, 0,
                            "jj committed a quarantined asset:\n" + result.stdout)
        self.assertIn("LICENCE GUARD FAILED", result.stderr)
        self.assertIn("assets_licensed/synty/Hero.fbx", result.stderr)

    def test_a_vendor_named_file_outside_the_quarantine_blocks_a_commit(self):
        # Renaming a purchased file does not launder it, and this is the case the
        # .gitignore cannot see at all: the path is not in the quarantine, so
        # only the guard's vendor list catches it.
        sneaky = self.repo / "assets" / "sonniss_boom.wav"
        sneaky.parent.mkdir()
        sneaky.write_bytes(b"purchased")

        result = self.jj_run("commit", "-m", "sneak it in")
        self.assertNotEqual(result.returncode, 0,
                            "jj committed a non-redistributable vendor's file:\n"
                            + result.stdout)
        self.assertIn("LICENCE GUARD FAILED", result.stderr)
        self.assertIn("sonniss", result.stderr)

    def test_a_push_is_blocked_too(self):
        # The last line before the public repo, and the only one that still
        # matters once a local commit exists.
        sneaky = self.repo / "assets" / "sonniss_boom.wav"
        sneaky.parent.mkdir()
        sneaky.write_bytes(b"purchased")

        result = self.jj_run("git", "push", "--allow-new")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("LICENCE GUARD FAILED", result.stderr)

    def test_a_file_committed_then_deleted_still_fails(self):
        # jj's working-copy tree would no longer mention it, but the unpushed
        # commit does, and that is what would reach the remote.
        sneaky = self.repo / "assets" / "sonniss_boom.wav"
        sneaky.parent.mkdir()
        sneaky.write_bytes(b"purchased")
        # Commit it the only way that gets past the wrapper: the real jj.
        subprocess.run([str(self.jj), "commit", "-m", "landed"], cwd=self.repo,
                       check=True, capture_output=True, text=True, env=self.env)
        sneaky.unlink()

        result = self.jj_run("git", "push", "--allow-new")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("touched by an unpushed jj commit", result.stderr)

    def test_jj_refuses_to_run_inside_a_git_worktree(self):
        # A git worktree has no .jj/, so jj walks up to the enclosing workspace
        # and drives *its* working copy from inside the worktree — a commit made
        # there lands somebody else's work. The agent worktrees in
        # .claude/worktrees/ are git's, so this is the live case, not a corner.
        git(self.repo, "worktree", "add", "-q", "-b", "side", "wt")
        worktree = self.repo / "wt"
        self.assertFalse((worktree / ".jj").exists())

        result = subprocess.run(["jj", "st"], cwd=worktree, capture_output=True,
                                text=True, env=self.env)
        self.assertNotEqual(result.returncode, 0,
                            "jj drove the enclosing workspace from a git worktree:\n"
                            + result.stdout)
        self.assertIn("refusing to run here", result.stderr)
        self.assertIn(str(self.repo), result.stderr)

    def test_a_subdirectory_of_the_workspace_is_not_mistaken_for_a_worktree(self):
        subdir = self.repo / "tools" / "assets"
        result = subprocess.run(["jj", "st"], cwd=subdir, capture_output=True,
                                text=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_empty_godot_marker_is_still_allowed(self):
        # The one path inside the quarantine that may be committed, and only
        # while it is empty.
        (self.repo / ".gitignore").write_text("!/assets_licensed/.gdignore\n/.jj/\n")
        result = self.jj_run("commit", "-m", "the marker alone")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        (self.repo / "assets_licensed" / ".gdignore").write_text("not empty\n")
        result = self.jj_run("commit", "-m", "bytes in the marker")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("assets_licensed/.gdignore", result.stderr)


class JjWrapperTemplate(unittest.TestCase):
    """The template is the thing that is version-controlled; the wrapper on PATH
    is generated from it and can be regenerated at any time."""

    def test_template_exists_and_carries_the_placeholder(self):
        self.assertTrue(TEMPLATE.exists(), f"missing {TEMPLATE}")
        self.assertIn("@JJ_REAL@", TEMPLATE.read_text(),
                      "the template has no placeholder for the real jj binary")

    def test_template_guards_commit_and_push(self):
        text = TEMPLATE.read_text()
        for command in ("commit", "describe", "new", "squash", "split", "push"):
            self.assertIn(f" {command} ", text,
                          f"the wrapper does not guard `jj {command}`")

    def test_installer_can_be_told_to_leave_jj_alone(self):
        self.assertIn("SKIP_JJ_WRAPPER", INSTALLER.read_text())


if __name__ == "__main__":
    unittest.main()
