"""Behaviour of the set-dressing conversion path.

Seam: `tools/assets/convert_props.sh`'s command line and the `.glb` files it
writes, read back with a plain glTF chunk reader. The artefact, not the
implementation.

**Every one of these runs on a fixture, never on a purchased pack**, for the
reason `test_fbx_to_viewmodel.py` gives: the packs forbid redistribution, are not
in this repository, and a test that needed them would be a test only one machine
could run. The fixture reproduces the two things about the real files the
converter exists to deal with — a GLB that points at a shared atlas by relative
URI, and a material with no `baseColorFactor` of its own to tint.
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import convert_props  # noqa: E402
import prop_grade  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
RECIPE = REPO / "tools" / "assets" / "convert_props.sh"

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

# A four-pixel atlas: the pack's safety yellow, its process teal, white and
# black. Small enough to inline and real enough to be *graded* — which the
# earlier one-pixel fixture was not, because it was copied rather than decoded
# and nothing had ever checked its adler32.
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000020000000208020000"
    "00fdd49a73000000164944415478da6338324bc72e299ee1d3a74f0c"
    "0c0c002a2205604d4400030000000049454e44ae426082"
)


def write_glb(path: Path, document: dict, binary: bytes) -> None:
    json_bytes = json.dumps(document).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    padded = binary + b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(json_bytes) + (8 + len(padded) if padded else 0)
    out = bytearray(struct.pack("<III", 0x46546C67, 2, total))
    out += struct.pack("<II", len(json_bytes), JSON_CHUNK) + json_bytes
    if padded:
        out += struct.pack("<II", len(padded), BIN_CHUNK) + padded
    path.write_bytes(bytes(out))


def a_prop(base_colour=None) -> tuple[dict, bytes]:
    """One cube-ish prop that wears the shared atlas by relative URI."""
    positions = struct.pack("<9f", -0.5, 0.0, -0.5, 0.5, 0.0, -0.5, 0.0, 1.25, 0.5)
    material = {"name": "props", "pbrMetallicRoughness": {"metallicFactor": 0}}
    material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
    if base_colour is not None:
        material["pbrMetallicRoughness"]["baseColorFactor"] = base_colour
    document = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
        "materials": [material],
        "images": [{"uri": "../textures/atlas.png", "mimeType": "image/png"}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729}],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-0.5, 0.0, -0.5],
                "max": [0.5, 1.25, 0.5],
            }
        ],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(positions)}],
        "buffers": [{"byteLength": len(positions)}],
    }
    return document, positions


def read_glb(path: Path) -> dict:
    data = path.read_bytes()
    offset = 12
    while offset + 8 <= len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        if kind == JSON_CHUNK:
            return json.loads(data[offset + 8 : offset + 8 + length])
        offset += 8 + length
    raise AssertionError(f"{path} carries no JSON chunk")


class ConvertPropsTest(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix="props-fixture-"))
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        self.quarantine = self.work / "quarantine"
        self.out = self.work / "out"

    def _stand_up_a_pack(self, pack: str, sources: list[str], base_colour=None) -> None:
        for source in sources:
            path = self.quarantine / pack / source
            path.parent.mkdir(parents=True, exist_ok=True)
            write_glb(path, *a_prop(base_colour))
        textures = self.quarantine / pack / "textures"
        textures.mkdir(parents=True, exist_ok=True)
        (textures / "atlas.png").write_bytes(PNG)
        (textures / "atlas_glow.png").write_bytes(PNG)

    def _convert(self) -> int:
        return convert_props.convert(self.quarantine, self.out)

    # ── The conversion itself ────────────────────────────────────────────────

    def test_the_shared_atlas_comes_out_of_every_prop_and_is_copied_once(self):
        # 213 props wear one 2048 atlas. Carrying the reference forward would mean
        # a decode and a VRAM copy per prop for one image, so the images come out
        # and the PNGs are copied beside them for the game to build one material.
        self._stand_up_a_pack(
            convert_props.HEYHEYTHERE, ["glb/crate_large.glb", "glb/pallet.glb"]
        )
        self._convert()

        written = read_glb(self.out / "crate_large.glb")
        self.assertNotIn("images", written)
        self.assertNotIn("textures", written)
        self.assertNotIn(
            "baseColorTexture", written["materials"][0]["pbrMetallicRoughness"]
        )
        self.assertTrue((self.out / "atlas.png").is_file())
        self.assertTrue((self.out / "atlas_glow.png").is_file())

    def test_the_atlas_is_graded_on_the_way_out_rather_than_copied(self):
        # The one that matters, and the one the first pass got wrong. Every
        # heyheythere prop is drawn with a single `material_override` built over
        # this atlas, so the atlas is the only thing that decides what a prop in
        # the foreground is coloured — a tint on a `baseColorFactor` nothing
        # reads was a tint on nobody. See `prop_grade.py`.
        self._stand_up_a_pack(convert_props.HEYHEYTHERE, ["glb/crate_large.glb"])
        self._convert()
        written = (self.out / "atlas.png").read_bytes()
        self.assertNotEqual(written, PNG, "the atlas went through ungraded")
        _, _, _, pixels = prop_grade.read_png(written)
        self.assertLessEqual(
            sum(
                channel * weight
                for channel, weight in zip(
                    [prop_grade.SRGB_TO_LINEAR[value] for value in pixels[:3]],
                    prop_grade.LUMA,
                )
            ),
            0.14,
            "a graded texel is brighter than the brightest Machine surface",
        )

    def test_the_pack_that_keeps_its_own_materials_still_gets_its_tint(self):
        # The far-yard packs are not on the shared atlas and are drawn from their
        # own materials, so for them the `baseColorFactor` is still the knob.
        self._stand_up_a_pack(convert_props.LUKAMI, ["Smooth/GLB/Storage_Silo.glb"])
        self._convert()
        factor = read_glb(self.out / "yard_silo.glb")["materials"][0][
            "pbrMetallicRoughness"
        ]["baseColorFactor"]
        self.assertEqual(factor, convert_props.TINTS[convert_props.LUKAMI])

    def test_the_atlas_pack_is_not_tinted_as_well_as_graded(self):
        # Belt and braces would be a double darkening, and worse, a second
        # authority on what these props are coloured.
        self.assertNotIn(convert_props.HEYHEYTHERE, convert_props.TINTS)

    def test_the_manifest_records_where_each_prop_came_from_and_how_big_it_is(self):
        # The packs disagree about origins — a high-bay light hangs below its pivot
        # — so where a prop sits relative to the ground is measured, not assumed.
        self._stand_up_a_pack(convert_props.HEYHEYTHERE, ["glb/crate_large.glb"])
        self._convert()
        manifest = json.loads((self.out / "props.json").read_text())["props"]
        self.assertIn("crate_large", manifest)
        entry = manifest["crate_large"]
        self.assertEqual(entry["pack"], convert_props.HEYHEYTHERE)
        self.assertEqual(entry["min"], [-0.5, 0.0, -0.5])
        self.assertEqual(entry["max"], [0.5, 1.25, 0.5])

    # ── Absence is an ordinary state ─────────────────────────────────────────

    def test_an_absent_pack_is_a_clean_no_op_rather_than_a_failure(self):
        # Which is the ordinary case: the packs are not in this repository and on
        # most clones the quarantine holds nothing at all.
        self.quarantine.mkdir(parents=True, exist_ok=True)
        self.assertEqual(self._convert(), 0)
        self.assertEqual(
            json.loads((self.out / "props.json").read_text())["props"], {}
        )

    def test_one_pack_present_and_another_absent_converts_the_one_that_is_here(self):
        self._stand_up_a_pack(convert_props.HEYHEYTHERE, ["glb/crate_large.glb"])
        written = self._convert()
        self.assertEqual(written, 1)
        manifest = json.loads((self.out / "props.json").read_text())["props"]
        self.assertEqual(list(manifest), ["crate_large"])

    # ── The recipe, end to end ───────────────────────────────────────────────

    def test_the_recipe_runs_with_no_quarantine_at_all_and_says_so(self):
        result = subprocess.run(
            ["bash", str(RECIPE)],
            env={
                **os.environ,
                "LICENSED_ROOT": str(self.work / "nothing-here"),
                "PROP_OUT": str(self.out),
            },
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing to convert", result.stderr)

    def test_the_recipe_converts_what_the_catalogue_names(self):
        self._stand_up_a_pack(
            convert_props.HEYHEYTHERE, ["glb/crate_large.glb", "glb/pipe_straight.glb"]
        )
        result = subprocess.run(
            ["bash", str(RECIPE)],
            env={
                **os.environ,
                "LICENSED_ROOT": str(self.quarantine),
                "PROP_OUT": str(self.out),
            },
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.out / "crate_large.glb").is_file())
        self.assertTrue((self.out / "pipe_straight.glb").is_file())

    # ── The catalogue is the record, so it has to be consistent ──────────────

    def test_every_catalogued_prop_is_a_role_the_game_asks_for(self):
        # `game/set_dressing.gd`'s `KINDS` and this catalogue are the two halves of
        # one set of names: a prop the game never asks for is a conversion nobody
        # needs, and a name the game asks for that is not here would silently fall
        # back to a stand-in for ever.
        wanted = set()
        source = (REPO / "game" / "set_dressing.gd").read_text()
        block = source[source.index("const KINDS"):source.index("## How far from the Nest")]
        for chunk in block.split('"'):
            if chunk in convert_props.CATALOGUE:
                wanted.add(chunk)
        self.assertEqual(
            sorted(set(convert_props.CATALOGUE) - wanted),
            [],
            "a converted prop that nothing draws",
        )
        self.assertTrue(len(wanted) > 40, "and the game asks for a yard's worth")


if __name__ == "__main__":
    unittest.main()
