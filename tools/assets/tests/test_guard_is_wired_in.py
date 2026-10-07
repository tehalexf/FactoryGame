"""The guard must be impossible to forget, not merely available.

Seam: `tools/git/install_hooks.sh` run inside a repository, then ordinary
`git commit`. A developer who has run the one-time setup cannot commit a
licensed asset by accident.
"""

import os
import shutil
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

REPO = Path(__file__).resolve().parents[3]
INSTALLER = REPO / "tools" / "git" / "install_hooks.sh"


def git(repo, *args, check=True):
    env = dict(os.environ, GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="t@e.com",
               GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@e.com")
    return subprocess.run(["git", *args], cwd=repo, check=check,
                          capture_output=True, text=True, env=env)


def clone_tooling(tmp):
    """A fresh repo carrying this repo's asset tooling, as a new clone would."""
    repo = Path(tmp)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "t@e.com")
    git(repo, "config", "user.name", "T")
    for sub in ("tools/assets", "tools/git"):
        dst = repo / sub
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(REPO / sub, dst)
    (repo / ".gitignore").write_text("/assets_licensed/\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "tooling")
    return repo


class GuardIsWiredIn(unittest.TestCase):
    def test_installer_exists_and_is_executable(self):
        self.assertTrue(INSTALLER.exists(), f"missing {INSTALLER}")
        self.assertTrue(os.access(INSTALLER, os.X_OK), f"{INSTALLER} is not executable")

    def test_installed_hook_blocks_a_commit_containing_a_licensed_asset(self):
        with TemporaryDirectory() as tmp:
            repo = clone_tooling(tmp)
            subprocess.run(["bash", "tools/git/install_hooks.sh"], cwd=repo,
                           check=True, capture_output=True, text=True)
            before = git(repo, "rev-parse", "HEAD").stdout.strip()

            licensed = repo / "assets_licensed" / "synty" / "Hero.fbx"
            licensed.parent.mkdir(parents=True)
            licensed.write_bytes(b"purchased")
            git(repo, "add", "-f", "assets_licensed/synty/Hero.fbx")

            result = git(repo, "commit", "-m", "sneak it in", check=False)
            self.assertNotEqual(result.returncode, 0,
                                "the pre-commit hook let a licensed asset through")
            self.assertIn("LICENCE GUARD FAILED", result.stdout + result.stderr)
            self.assertEqual(git(repo, "rev-parse", "HEAD").stdout.strip(), before)

    def test_installed_hook_allows_an_ordinary_commit(self):
        with TemporaryDirectory() as tmp:
            repo = clone_tooling(tmp)
            subprocess.run(["bash", "tools/git/install_hooks.sh"], cwd=repo,
                           check=True, capture_output=True, text=True)
            (repo / "notes.md").write_text("fine\n")
            git(repo, "add", "notes.md")
            result = git(repo, "commit", "-m", "notes", check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_continuous_integration_runs_the_guard(self):
        """CI is the backstop for anyone who never ran the installer."""
        workflows = list((REPO / ".github" / "workflows").glob("*.yml"))
        self.assertTrue(workflows, "no GitHub Actions workflows found")
        text = "\n".join(p.read_text() for p in workflows)
        self.assertIn("check_licensed_staged.py", text)


if __name__ == "__main__":
    unittest.main()
