"""Catching an incomplete build from the artefact alone.

Seam: `tools/release/verify_pck.py`'s `report(binary, repo_root)` — a verdict and
the lines to print. Driven against packs assembled in `test_pck.py`'s own builder,
so the pack under test is one whose contents are known exactly, and against the
real exported build when there is one.

The negative cases are the ones that matter. A release check that only ever passes
is indistinguishable from no release check, and the whole premise of this directory
is that the failure it guards against produces a build that looks fine.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manifest  # noqa: E402
import verify_pck  # noqa: E402
from test_pck import build_pack  # noqa: E402

REPO = Path(__file__).resolve().parents[3]


def complete_pack() -> dict[str, bytes]:
    """Every path a finished build must carry, with a byte in each."""
    files = {
        "res://project.binary": b"settings",
        "res://content/machines.csv": b"id,role\n",
        "res://content/recipes.csv": b"id\n",
        "res://content/tuning.toml": b"[heat]\n",
    }
    for group in manifest.expected_bundle(REPO).values():
        for relative in group.files:
            files[f"res://{relative}"] = b"bytes"
    return files


class AnIncompleteBuildIsCaught(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "DeepFoundry.exe"

    def _report(self, files: dict[str, bytes]) -> tuple[bool, str]:
        self.path.write_bytes(build_pack(files, embedded_in=b"MZ" + b"\0" * 512))
        ok, lines = verify_pck.report(self.path, REPO)
        return ok, "\n".join(lines)

    def test_a_complete_pack_passes(self) -> None:
        ok, said = self._report(complete_pack())
        self.assertTrue(ok, said)

    def test_a_pack_with_no_licensed_assets_at_all_fails(self) -> None:
        # The first export of this project, exactly: 130 MB, runnable, and missing
        # every one of the 96 files that make it the real game.
        files = {
            path: body
            for path, body in complete_pack().items()
            if "assets_licensed" not in path
        }
        ok, said = self._report(files)
        self.assertFalse(ok)
        self.assertIn("0 of 3 bundled", said)
        self.assertIn("convert_audio.sh", said)
        self.assertIn("convert_props.sh", said)
        self.assertIn("convert_weapons.sh", said)

    def test_a_pack_with_no_content_fails_and_says_it_cannot_start(self) -> None:
        files = {
            path: body
            for path, body in complete_pack().items()
            if not path.startswith("res://content/")
        }
        ok, said = self._report(files)
        self.assertFalse(ok)
        self.assertIn("res://content/  0 file(s)", said)
        self.assertIn("cannot even start", said)

    def test_one_missing_cue_fails_the_whole_build(self) -> None:
        files = complete_pack()
        gone = f"res://{manifest.expected_bundle(REPO)['audio'].files[0]}"
        del files[gone]
        ok, said = self._report(files)
        self.assertFalse(ok)
        self.assertIn(gone, said)
        self.assertIn("convert_audio.sh", said)

    def test_a_file_bundled_at_zero_bytes_does_not_count(self) -> None:
        # An interrupted converter leaves exactly this, and the pack happily
        # carries it: `FileAccess.file_exists` would say yes and the loader would
        # then quietly hand back null.
        files = complete_pack()
        files[f"res://{manifest.expected_bundle(REPO)['weapons'].files[0]}"] = b""
        ok, said = self._report(files)
        self.assertFalse(ok)
        self.assertIn("convert_weapons.sh", said)

    def test_the_counts_are_reported_even_when_it_passes(self) -> None:
        # So a build log says how much got bundled rather than only whether the
        # check was happy, which is what makes a regression visible in a diff.
        _, said = self._report(complete_pack())
        self.assertIn("audio: 37 of 37 bundled", said)
        self.assertIn("weapons: 3 of 3 bundled", said)


class TheRealExportedBuild(unittest.TestCase):
    def test_it_is_complete(self) -> None:
        built = REPO / "build/windows/DeepFoundry.exe"
        if not built.exists():
            self.skipTest("no build yet — run tools/release/build_windows.sh")
        ok, lines = verify_pck.report(built, REPO)
        self.assertTrue(ok, "\n".join(lines))


if __name__ == "__main__":
    unittest.main()
