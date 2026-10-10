"""Behaviour of the licence guard, driven through its command line.

Seam: `tools/assets/check_licensed_staged.py` run with a repository as its
working directory. The guard's contract is its exit status and its message —
nothing else about it is public.
"""

import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

GUARD = Path(__file__).resolve().parents[1] / "check_licensed_staged.py"


def git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, check=True,
                          capture_output=True, text=True).stdout


def make_repo(tmp):
    """A repository shaped like this one: public, with assets_licensed/ ignored."""
    repo = Path(tmp)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "test@example.com")
    git(repo, "config", "user.name", "Test")
    (repo / ".gitignore").write_text("/assets_licensed/\n")
    (repo / "README.md").write_text("hello\n")
    git(repo, "add", ".gitignore", "README.md")
    git(repo, "commit", "-qm", "initial")
    return repo


def run_guard(repo):
    return subprocess.run(["python3", str(GUARD)], cwd=repo,
                          capture_output=True, text=True)


class LicenceGuard(unittest.TestCase):
    def test_passes_when_nothing_licensed_is_staged(self):
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            (repo / "notes.md").write_text("fine\n")
            git(repo, "add", "notes.md")
            result = run_guard(repo)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fails_when_a_licensed_asset_is_staged(self):
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            licensed = repo / "assets_licensed" / "synty" / "Hero.fbx"
            licensed.parent.mkdir(parents=True)
            licensed.write_bytes(b"not redistributable")
            git(repo, "add", "-f", "assets_licensed/synty/Hero.fbx")
            result = run_guard(repo)
            self.assertNotEqual(result.returncode, 0)
            output = result.stdout + result.stderr
            self.assertIn("assets_licensed/synty/Hero.fbx", output)

    def test_fails_when_a_licensed_asset_is_already_committed(self):
        """A past mistake must keep failing, not pass because nothing is staged."""
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            licensed = repo / "assets_licensed" / "sonniss" / "boom.wav"
            licensed.parent.mkdir(parents=True)
            licensed.write_bytes(b"RIFF")
            git(repo, "add", "-f", "assets_licensed/sonniss/boom.wav")
            git(repo, "commit", "-qm", "oops")
            result = run_guard(repo)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("assets_licensed/sonniss/boom.wav", result.stdout + result.stderr)

    def test_fails_on_a_licensed_vendor_name_outside_the_quarantine_directory(self):
        """Moving a purchased asset out of assets_licensed/ must not launder it."""
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            sneaked = repo / "assets" / "characters" / "Synty_PolygonHero.fbx"
            sneaked.parent.mkdir(parents=True)
            sneaked.write_bytes(b"purchased")
            git(repo, "add", "assets/characters/Synty_PolygonHero.fbx")
            result = run_guard(repo)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Synty_PolygonHero.fbx", result.stdout + result.stderr)

    def test_reports_every_offending_path_not_just_the_first(self):
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            for name in ("one.fbx", "two.fbx"):
                p = repo / "assets_licensed" / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b"x")
                git(repo, "add", "-f", f"assets_licensed/{name}")
            output = run_guard(repo).stdout + run_guard(repo).stderr
            self.assertIn("one.fbx", output)
            self.assertIn("two.fbx", output)

    def test_allows_the_empty_gdignore_that_keeps_godot_out_of_the_quarantine(self):
        """The one committable path inside the quarantine. It carries no data."""
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            marker = repo / "assets_licensed" / ".gdignore"
            marker.parent.mkdir(parents=True)
            marker.write_bytes(b"")
            git(repo, "add", "-f", "assets_licensed/.gdignore")
            result = run_guard(repo)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fails_when_that_gdignore_is_not_empty(self):
        """The exception is for a marker, not for a file that could carry data."""
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            marker = repo / "assets_licensed" / ".gdignore"
            marker.parent.mkdir(parents=True)
            marker.write_bytes(b"purchased\n")
            git(repo, "add", "-f", "assets_licensed/.gdignore")
            result = run_guard(repo)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("assets_licensed/.gdignore", result.stdout + result.stderr)

    def test_pass_is_quiet_enough_to_live_in_a_pre_commit_hook(self):
        with TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            result = run_guard(repo)
            self.assertEqual(result.returncode, 0)
            self.assertLessEqual(len(result.stdout.splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
