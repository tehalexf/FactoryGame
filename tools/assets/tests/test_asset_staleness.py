"""That the staleness check fires, and that it stays quiet when it should.

Seam: `asset_staleness.audit`, against **throwaway git repositories this file
builds**, the way `test_licence_guard.py` builds one. That is not an
indirection — it is the only way to assert any of this:

* the one case worth catching is a generated file older than its recipe, and the
  only honest way to put a tree in that state is to **backdate the file**. A test
  that read whatever happened to be on the developer's disk would pass or fail
  for reasons nobody chose, which is the same category of thing as a staleness
  check that has quietly become a no-op.
* the answer depends on **git** — see `asset_staleness`' header on why a tracked
  file's mtime is a checkout date and not an edit date — so a fixture needs a
  repository with real commits in it rather than a directory of files.
* **it must run on a clone with no purchased packs**, which is every clone and
  every CI runner. Skipping here would make the suite silently stop covering the
  thing the ticket is about, and `.github/ci/expected_skips.txt` is explicit that
  a licensed-asset skip is a failure rather than a note.

The recipe files are copied out of the real repository rather than invented, so
the fixture is asking about the declarations the project actually ships.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import asset_staleness  # noqa: E402

REPO = Path(__file__).resolve().parents[3]

#: An hour either side of a commit, which is far larger than any filesystem
#: timestamp resolution and far smaller than the eleven hours #57 measured.
AN_HOUR = 3600.0


class Fixture:
    """A throwaway repository with the real recipes committed into it."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.licensed = root / "assets_licensed"
        shutil.copytree(
            REPO / "tools" / "assets",
            root / "tools" / "assets",
            ignore=shutil.ignore_patterns("tests", "__pycache__", "godot_verify"),
        )
        self._git("init", "-q")
        self._git("config", "user.email", "fixture@example.com")
        self._git("config", "user.name", "Fixture")
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "the recipes")
        #: What git says the recipes' content dates from. Every mtime this
        #: fixture sets is relative to it, so the test never has to care what
        #: the wall clock said.
        self.committed_at = float(
            self._git("log", "-1", "--format=%ct").strip()
        )

    def _git(self, *arguments: str) -> str:
        done = subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            capture_output=True,
            text=True,
            check=True,
        )
        return done.stdout

    def generate(self, relative: str, *, at: float, content: bytes = b"glb") -> Path:
        """Write a generated output under the quarantine and date it `at`."""
        path = self.licensed / Path(relative).relative_to(asset_staleness.QUARANTINE)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        os.utime(path, (at, at))
        return path

    def touch_recipe(self, relative: str, *, at: float) -> None:
        """Give a tracked recipe a new mtime without changing its content.

        This is what a `git clone` or a `git worktree add` does to every tracked
        file in the tree, and reproducing it is the whole of
        `test_a_fresh_checkout_is_not_stale`.
        """
        os.utime(self.root / relative, (at, at))

    def edit_recipe(self, relative: str, *, at: float) -> None:
        """Change a tracked recipe in the working copy without committing it."""
        path = self.root / relative
        path.write_text(path.read_text() + "\n# an uncommitted correction\n")
        os.utime(path, (at, at))

    def audit(self) -> list[asset_staleness.Stale]:
        return asset_staleness.audit(self.root, self.licensed)

    def weapon_files(self) -> list[str]:
        return asset_staleness.groups(self.root)["weapons"].outputs


class TheCheckFires(unittest.TestCase):
    """The acceptance criterion, and it is asserted by backdating a file."""

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.fixture = Fixture(Path(self.work.name))

    def test_a_generated_asset_older_than_its_recipe_is_reported(self):
        """#57's measured defect, reproduced: the recipe was corrected and
        committed, the converter was never re-run, and the output is older."""
        for relative in self.fixture.weapon_files():
            self.fixture.generate(relative, at=self.fixture.committed_at - AN_HOUR)

        stale = self.fixture.audit()

        self.assertEqual([entry.name for entry in stale], ["weapons"])

    def test_the_report_names_both_files_and_the_converter_to_run(self):
        """The whole value of the complaint. A reader must not have to go and
        find out which script this was — `manifest.Problem.report`'s standard."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at - AN_HOUR,
        )

        report = self.fixture.audit()[0].report()

        self.assertIn("tools/assets/convert_weapons.sh", report)
        self.assertIn("assets_licensed/generated/gear/bolt_rifle.glb", report)
        self.assertIn("run:  bash tools/assets/convert_weapons.sh", report)

    def test_an_uncommitted_correction_is_stale_before_any_commit_exists(self):
        """The case that catches somebody mid-change, which is the moment the
        fix is cheapest. A modified tracked file is as new as its mtime, because
        the edit in the working copy is the thing that has not been converted."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at + AN_HOUR,
        )
        self.assertEqual(self.fixture.audit(), [], "not stale yet, by premise")

        self.fixture.edit_recipe(
            "tools/assets/convert_weapons.sh", at=self.fixture.committed_at + 2 * AN_HOUR
        )

        stale = self.fixture.audit()
        self.assertEqual([entry.name for entry in stale], ["weapons"])
        self.assertIn("tools/assets/convert_weapons.sh", stale[0].report())

    def test_a_recipe_that_is_not_the_converter_is_reported_too(self):
        """A converter's shell script is never the only input: these arms are
        framed by `fbx_to_viewmodel.py`, and #57's own eleven-hour defect was a
        correction to the framing. A recipe set of one would have missed it."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at + AN_HOUR,
        )
        self.fixture.edit_recipe(
            "tools/assets/fbx_to_viewmodel.py", at=self.fixture.committed_at + 2 * AN_HOUR
        )

        stale = self.fixture.audit()

        self.assertEqual([entry.name for entry in stale], ["weapons"])
        self.assertIn("tools/assets/fbx_to_viewmodel.py", stale[0].report())


class AbsenceIsNotStaleness(unittest.TestCase):
    """The rule that must not be weakened: a clone with no packs is unaffected.

    `convert_weapons.sh` exits 0 with no packs, `WeaponViewmodel` draws boxes,
    and `tests/cases/test_weapon_viewmodel.gd` asserts a pack-less clone builds
    and plays. None of that may become a complaint.
    """

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.fixture = Fixture(Path(self.work.name))

    def test_a_clone_with_no_purchased_packs_is_not_stale(self):
        """No quarantine at all, which is what every CI runner has."""
        self.assertFalse(self.fixture.licensed.exists(), "no quarantine, by premise")
        self.assertEqual(self.fixture.audit(), [])

    def test_an_empty_quarantine_is_not_stale(self):
        """A quarantine holding only its own `.gdignore`, which is the one
        tracked file in there and what an unlinked worktree really looks like."""
        self.fixture.licensed.mkdir()
        (self.fixture.licensed / ".gdignore").write_text("")

        self.assertEqual(self.fixture.audit(), [])

    def test_one_backdated_file_among_absent_ones_is_still_reported(self):
        """Absence being silent must not make a *present* stale file silent —
        otherwise a developer with one converter's output and not another's
        would be told nothing about the one they have."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at - AN_HOUR,
        )

        stale = self.fixture.audit()

        self.assertEqual([entry.name for entry in stale], ["weapons"])
        self.assertEqual(stale[0].total, 1, "the absent files are not counted")

    def test_a_zero_byte_output_is_absent_rather_than_stale(self):
        """An interrupted ffmpeg or Blender run leaves exactly that, and
        `manifest.audit` already calls it missing. Two answers to one file would
        be two complaints about it, and the missing one is the useful one."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at - AN_HOUR,
            content=b"",
        )

        self.assertEqual(self.fixture.audit(), [])


class WhatAFilesAgeIs(unittest.TestCase):
    """The subtle half, and the half with no second line of defence.

    A check that cries wolf in the normal case is a check somebody switches off,
    and the normal case in this project is an agent worktree: every tracked file
    minutes old, every generated file hours old and reached through the symlinks
    `link_licensed.sh` makes.
    """

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.fixture = Fixture(Path(self.work.name))

    def test_a_fresh_checkout_is_not_stale(self):
        """Measured before it was written: in a real worktree of this project
        the recipes carried the checkout's timestamp and the generated gear was
        nearly three hours older, so a plain mtime comparison called the whole
        pipeline stale with nothing having been edited.

        It has already earned its place once: an attempt to find modified files
        with `git diff-index` failed here, because that command is stat-based and
        does not refresh the index, so it reports a touched file whose content is
        identical — which put the same false positive straight back in by a
        different door."""
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at + AN_HOUR,
        )
        for relative in ("tools/assets/convert_weapons.sh", "tools/assets/fbx_to_viewmodel.py"):
            self.fixture.touch_recipe(relative, at=self.fixture.committed_at + 2 * AN_HOUR)

        self.assertEqual(
            self.fixture.audit(),
            [],
            "a clean tracked file is no newer than the commit that carried it",
        )

    def test_an_output_newer_than_every_recipe_is_not_stale(self):
        """The ordinary state of a machine whose converters have been re-run."""
        for relative in self.fixture.weapon_files():
            self.fixture.generate(relative, at=self.fixture.committed_at + AN_HOUR)

        self.assertEqual(self.fixture.audit(), [])

    def test_a_tree_with_no_git_history_falls_back_to_mtimes(self):
        """An exported tarball. `git` answers nothing, so an mtime is the whole
        answer — which is worth less, and is reported as such rather than
        guessed at. It is still the truth in the checkout where the editing
        happens, which is the one that bit."""
        shutil.rmtree(self.fixture.root / ".git")
        self.fixture.generate(
            "assets_licensed/generated/gear/bolt_rifle.glb",
            at=self.fixture.committed_at - AN_HOUR,
        )
        self.fixture.touch_recipe(
            "tools/assets/convert_weapons.sh", at=self.fixture.committed_at
        )

        self.assertEqual([entry.name for entry in self.fixture.audit()], ["weapons"])
        self.assertFalse(asset_staleness._Ages(self.fixture.root).git_answered)


class TheDeclarationsPointAtRealFiles(unittest.TestCase):
    """A recipe path that names nothing is a recipe whose change goes
    unreported, and it would do so in silence — the exact shape of the hole #57
    is about. So the declarations are checked against the real repository.
    """

    def test_every_declared_recipe_exists(self):
        for name, group in asset_staleness.groups(REPO).items():
            for relative in group.recipes:
                with self.subTest(group=name, recipe=relative):
                    self.assertTrue(
                        (REPO / relative).is_file(),
                        f"{relative} is declared a recipe of {name} and is not there",
                    )

    def test_every_group_declares_a_converter_command_and_some_recipes(self):
        groups = asset_staleness.groups(REPO)
        self.assertEqual(sorted(groups), ["audio", "props", "weapons"])
        for name, group in groups.items():
            with self.subTest(group=name):
                self.assertTrue(group.converter.startswith("bash tools/assets/"))
                self.assertGreaterEqual(len(group.recipes), 2)

    def test_every_group_writes_into_the_quarantine(self):
        """What keeps a pack-less clone silent is that every output lives under
        `assets_licensed/`, so the whole list is absent at once. A group writing
        anywhere else would be one a clean clone could be told off about — see
        this module's header on why the committed Machine meshes are not here."""
        for name, group in asset_staleness.groups(REPO).items():
            for relative in group.outputs:
                with self.subTest(group=name, output=relative):
                    self.assertTrue(
                        relative.startswith(asset_staleness.QUARANTINE + "/"),
                        f"{relative} is outside the quarantine",
                    )


if __name__ == "__main__":
    unittest.main()
