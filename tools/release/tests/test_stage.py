"""Building the tree that gets exported, which is not the working copy.

Seam: `tools/release/stage.py`'s `prepare(...)` and the directory it leaves behind.
Everything here runs against a fixture project in a temporary directory — no
Godot, no purchased packs, no network — because what is being asserted is the
*shape* of the staged tree, and that is the whole of the trick this module plays.

The trick, stated once: Godot will not put a file in the PCK unless its
`EditorFileSystem` can see it, and `assets_licensed/.gdignore` exists precisely to
stop it seeing seven gigabytes of purchased WAV. So the three runtime asset
classes have to be staged into a tree with **no `.gdignore`** over them — and then
each file needs an `importer="keep"` sidecar, or Godot imports it and the PCK gets
a converted resource at a different path while `FileAccess.file_exists` on the
path the game actually asks for returns false. Which is a build that runs,
sounds worse, looks worse, and says nothing.
"""

import configparser
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stage  # noqa: E402


class PreparingTheStagingTree(unittest.TestCase):
    def setUp(self) -> None:
        if shutil.which("rsync") is None:
            self.skipTest("rsync is not on PATH")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.licensed = root / "quarantine"
        self.stage = root / "stage"

        self._write(self.repo / "project.godot", 'config/name="FIXTURE"\n')
        self._write(self.repo / "game/main.gd", "extends Node\n")
        self._write(self.repo / "assets_licensed/.gdignore", "")
        self._write(self.repo / "content/.gdignore", "")
        self._write(self.repo / "content/machines.csv", "id,role\nminer_mk1,miner\n")
        self._write(self.repo / "content/tuning.toml", "[heat]\n")
        self._write(self.repo / ".git/HEAD", "ref: refs/heads/main\n")
        self._write(self.repo / ".godot/uid_cache.bin", "cache")
        self._write(self.repo / "build/windows/old.exe", "stale")

        self._write(self.licensed / "generated/gear/bolt_rifle.glb", "glTF")
        self._write(self.licensed / "generated/audio/silo_commit.ogg", "OggS")
        self._write(self.licensed / "generated/props/atlas.png", "PNG")
        self._write(self.licensed / "generated/props/props.json", "{}")
        # A pack that must never be staged: the quarantine is 7.5 GB of it.
        self._write(self.licensed / "sonniss/huge.wav", "RIFF" * 1000)

    def _write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def _prepare(self) -> stage.Staged:
        return stage.prepare(self.repo, self.licensed, self.stage)

    def test_the_project_is_there_to_be_exported(self) -> None:
        self._prepare()
        self.assertTrue((self.stage / "project.godot").is_file())
        self.assertTrue((self.stage / "game/main.gd").is_file())

    def test_the_generated_assets_are_at_the_paths_the_game_asks_for(self) -> None:
        self._prepare()
        for relative in (
            "assets_licensed/generated/gear/bolt_rifle.glb",
            "assets_licensed/generated/audio/silo_commit.ogg",
            "assets_licensed/generated/props/atlas.png",
            "assets_licensed/generated/props/props.json",
        ):
            with self.subTest(relative):
                self.assertTrue((self.stage / relative).is_file())

    def test_the_gdignore_is_not_staged_or_nothing_would_be_bundled(self) -> None:
        self._prepare()
        self.assertFalse((self.stage / "assets_licensed/.gdignore").exists())

    def test_the_content_definitions_ship_as_rows_rather_than_not_at_all(self) -> None:
        # The first export of this project contained no `content/` at all, so the
        # build had no Machines, no Recipes and no tuning: `content/.gdignore` hides
        # the directory from the exporter exactly as it hides it from the importer.
        staged = self._prepare()
        self.assertFalse((self.stage / "content/.gdignore").exists())
        self.assertIn("content/machines.csv", staged.kept)
        self.assertIn("content/tuning.toml", staged.kept)
        self.assertTrue((self.stage / "content/machines.csv.import").is_file())

    def test_every_staged_asset_is_marked_keep_so_it_ships_unconverted(self) -> None:
        staged = self._prepare()
        self.assertEqual(len(staged.kept), 6)
        for relative in staged.kept:
            sidecar = self.stage / (relative + ".import")
            with self.subTest(relative):
                self.assertTrue(sidecar.is_file())
                parsed = configparser.ConfigParser()
                parsed.read_string(sidecar.read_text())
                self.assertEqual(parsed["remap"]["importer"], '"keep"')

    def test_the_rest_of_the_quarantine_is_never_staged(self) -> None:
        self._prepare()
        self.assertFalse((self.stage / "assets_licensed/sonniss").exists())

    def test_the_working_copy_is_left_exactly_as_it_was(self) -> None:
        self._prepare()
        self.assertTrue((self.repo / "assets_licensed/.gdignore").is_file())
        self.assertFalse(
            (self.repo / "assets_licensed/generated/gear/bolt_rifle.glb").exists()
        )

    def test_git_and_the_import_cache_and_old_builds_are_not_staged(self) -> None:
        self._prepare()
        for junk in (".git", ".godot", "build"):
            with self.subTest(junk):
                self.assertFalse((self.stage / junk).exists())

    def test_a_second_run_drops_an_asset_the_quarantine_no_longer_has(self) -> None:
        # The staging tree is kept between builds so Godot's import cache survives,
        # which means a cue deleted from the quarantine would otherwise be shipped
        # from the last build for ever.
        self._prepare()
        (self.licensed / "generated/audio/silo_commit.ogg").unlink()
        self._prepare()
        self.assertFalse(
            (self.stage / "assets_licensed/generated/audio/silo_commit.ogg").exists()
        )
        self.assertFalse(
            (
                self.stage / "assets_licensed/generated/audio/silo_commit.ogg.import"
            ).exists()
        )

    def test_a_second_run_keeps_the_import_cache_it_found(self) -> None:
        self._prepare()
        cache = self.stage / ".godot/marker"
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text("warm")
        self._prepare()
        self.assertEqual(cache.read_text(), "warm")

    def test_an_absent_quarantine_is_an_error_rather_than_an_empty_build(self) -> None:
        shutil.rmtree(self.licensed / "generated")
        with self.assertRaises(stage.NothingToStage):
            self._prepare()


if __name__ == "__main__":
    unittest.main()
