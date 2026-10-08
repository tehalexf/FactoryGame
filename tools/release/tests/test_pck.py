"""Reading the file index back out of an exported Godot build.

Seam: `tools/release/pck.py`'s `read(path)`. It answers the one question a release
has to answer about itself — *is that file actually in there* — from the shipped
artefact rather than from the export log, which is the only answer worth having.

Two sources of truth, on purpose:

* a pack assembled **byte by byte in this file** from the documented format, which
  is what pins the reader's behaviour: an independent construction that would
  disagree with the reader if either drifted;
* the **real exported build**, when one has been made, which is what catches the
  reader having confidently agreed with a wrong idea of the format. Skipped rather
  than failed when `build/` is empty, because a clean clone has no build in it.
"""

import hashlib
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pck  # noqa: E402

REPO = Path(__file__).resolve().parents[3]

MAGIC = 0x43504447  # "GDPC"


FILE_BASE = 112  # where Godot 4.7 starts the data, measured off a real export


def build_pack(files: dict[str, bytes], *, embedded_in: bytes = b"") -> bytes:
    """A pack format 4 archive, assembled from the format rather than from `pck.py`.

    Laid out the way Godot 4.7 lays one out: header, then the data from the file
    base, then the index past the end of it. Stored paths carry no `res://` prefix
    and offsets are measured from the file base — the two things version 4 changed,
    and the two a reader gets quietly wrong.
    """
    data = b""
    index = struct.pack("<I", len(files))
    for path, content in files.items():
        encoded = path.removeprefix("res://").encode("utf-8")
        padding = (-len(encoded)) % 4
        index += struct.pack("<I", len(encoded) + padding)
        index += encoded + b"\0" * padding
        index += struct.pack("<qq", len(data), len(content))
        index += hashlib.md5(content).digest()
        index += struct.pack("<I", 0)
        data += content

    header = struct.pack("<IiiiiI", MAGIC, 4, 4, 7, 2, 0x2)  # relative file base
    header += struct.pack("<qq", FILE_BASE, FILE_BASE + len(data))
    header += b"\0" * (FILE_BASE - len(header))

    pack = header + data + index
    if not embedded_in:
        return pack
    return embedded_in + pack + struct.pack("<q", len(pack)) + struct.pack("<I", MAGIC)


class ReadingAStandalonePack(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "game.pck"

    def _write(self, files: dict[str, bytes], **kwargs) -> pck.Pack:
        self.path.write_bytes(build_pack(files, **kwargs))
        return pck.read(self.path)

    def test_every_path_is_listed(self) -> None:
        pack = self._write(
            {
                "res://project.binary": b"settings",
                "res://assets_licensed/generated/audio/silo_commit.ogg": b"OggS...",
            }
        )
        self.assertEqual(
            sorted(pack.files),
            [
                "res://assets_licensed/generated/audio/silo_commit.ogg",
                "res://project.binary",
            ],
        )

    def test_a_file_reports_the_size_it_was_stored_at(self) -> None:
        pack = self._write({"res://a.ogg": b"0123456789"})
        self.assertEqual(pack.files["res://a.ogg"].size, 10)

    def test_a_file_reports_the_digest_of_its_own_bytes(self) -> None:
        pack = self._write({"res://a.ogg": b"0123456789"})
        self.assertEqual(
            pack.files["res://a.ogg"].md5, hashlib.md5(b"0123456789").hexdigest()
        )

    def test_a_pack_with_no_magic_is_refused_rather_than_misread(self) -> None:
        self.path.write_bytes(b"this is not a pack" * 64)
        with self.assertRaises(pck.NotAPack):
            pck.read(self.path)

    def test_an_unknown_format_version_is_named_rather_than_guessed_at(self) -> None:
        # How a Godot upgrade is supposed to arrive: a build that stops, not a
        # reader that finds nothing in a pack it cannot parse. 4.7 already bumped
        # this once, from 2 to 4.
        raw = bytearray(build_pack({"res://a.ogg": b"x"}))
        raw[4:8] = struct.pack("<i", 99)
        self.path.write_bytes(bytes(raw))
        with self.assertRaisesRegex(pck.NotAPack, "99"):
            pck.read(self.path)

    def test_a_stored_path_is_reported_the_way_the_game_asks_for_it(self) -> None:
        # Version 4 drops the prefix on disk; everything upstream of here speaks
        # `res://`, including the constants in game/*.gd.
        pack = self._write({"res://assets_licensed/generated/props/atlas.png": b"PNG"})
        self.assertEqual(
            list(pack.files), ["res://assets_licensed/generated/props/atlas.png"]
        )

    def test_a_standalone_pack_knows_it_is_not_embedded(self) -> None:
        self.assertFalse(self._write({"res://a.ogg": b"x"}).embedded)


class ReadingAPackEmbeddedInAnExecutable(unittest.TestCase):
    """What this project actually ships: `binary_format/embed_pck=true`, one .exe.

    The licence is the reason. Those packs permit use in a shipped game and forbid
    redistribution as assets, so a loose `.pck` beside the binary — which anybody
    can open — is the wrong shape, and a single executable is the right one.
    """

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "Game.exe"

    def test_the_pack_is_found_past_the_executable(self) -> None:
        self.path.write_bytes(
            build_pack({"res://a.ogg": b"hello"}, embedded_in=b"MZ" + b"\0" * 4096)
        )
        pack = pck.read(self.path)
        self.assertTrue(pack.embedded)
        self.assertEqual(sorted(pack.files), ["res://a.ogg"])

    def test_sizes_survive_the_offset_the_executable_pushes_them_to(self) -> None:
        self.path.write_bytes(
            build_pack(
                {"res://a.ogg": b"hello", "res://b.glb": b"glTF" * 9},
                embedded_in=b"MZ" + b"\0" * 100_000,
            )
        )
        pack = pck.read(self.path)
        self.assertEqual(pack.files["res://a.ogg"].size, 5)
        self.assertEqual(pack.files["res://b.glb"].size, 36)

    def test_an_executable_with_nothing_appended_is_refused(self) -> None:
        self.path.write_bytes(b"MZ" + b"\0" * 8192)
        with self.assertRaises(pck.NotAPack):
            pck.read(self.path)


class ReadingTheRealExportedBuild(unittest.TestCase):
    """The reader against Godot's own output, which is the only authority."""

    def setUp(self) -> None:
        self.built = REPO / "build/windows/DeepFoundry.exe"
        if not self.built.exists():
            self.skipTest("no build yet — run tools/release/build_windows.sh")
        self.pack = pck.read(self.built)

    def test_the_project_settings_are_in_it(self) -> None:
        self.assertIn("res://project.binary", self.pack.files)

    def test_the_main_scene_is_in_it(self) -> None:
        self.assertIn("res://game/main.tscn.remap", self.pack.files)

    def test_a_stored_file_hashes_to_the_digest_the_index_recorded(self) -> None:
        # The one check that cannot be fooled by a plausible-looking index: read the
        # bytes back at the offset this reader computed and hash them. If the
        # file-base arithmetic were wrong this is what would notice.
        raw = self.built.read_bytes()
        entry = self.pack.files["res://project.binary"]
        chunk = raw[entry.offset : entry.offset + entry.size]
        self.assertEqual(hashlib.md5(chunk).hexdigest(), entry.md5)

    def test_it_is_the_engine_the_project_declares(self) -> None:
        self.assertEqual(self.pack.engine[:2], (4, 7))

    def test_no_entry_claims_to_live_past_the_end_of_the_file(self) -> None:
        # The offset arithmetic is where an embedded pack reader goes wrong, and it
        # goes wrong quietly: a plausible index over nonsense data.
        end = self.built.stat().st_size
        for path, entry in self.pack.files.items():
            with self.subTest(path):
                self.assertLessEqual(entry.offset + entry.size, end)


if __name__ == "__main__":
    unittest.main()
