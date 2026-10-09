"""What the committed Build Gun viewmodel must be true of.

Seam: the committed `assets/gear/build_gun.glb`, read with the standard-library
glTF reader, plus the generator run as a developer runs it. Nothing here imports
Blender or calls into the generator's internals.

**It is committed, which is why these are proofs rather than dates.** #57's rule
is *where the output is committed, prove it; where it is gitignored, date it*, and
the Build Gun is the one viewmodel in the game on the committed side of that line:
every weapon frame is converted out of a purchased pack and is a derivative of
something non-redistributable, where this is assembled from `machine_parts` and a
palette of numbers and is this project's own work. So it is **absent from
`tools/assets/asset_staleness.py` on purpose** — the proof here is the stronger
instrument, exactly as it is for the Machine meshes and for `assets/generated/`.

The three claims, and each is one a render cannot make:

* the bytes come from the recipe, so re-running is a reviewable diff;
* the surfaces are the shared palette plus one declared emissive, so the thing in
  a player's hands belongs to the world they are building;
* the framing refusal **fires**, which is the half that matters — a guard nobody
  has watched fail is indistinguishable from one that has become a no-op.
"""

import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_gun_recipe as recipe  # noqa: E402
import gltf_info  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
BUILD_GUN = REPO / "assets" / "gear" / "build_gun.glb"
GENERATOR = REPO / "tools" / "assets" / "generate_build_gun.sh"
PALETTE = json.loads((REPO / "tools" / "assets" / "dieselpunk_palette.json").read_text())


def blender_is_available() -> bool:
    return shutil.which("blender") is not None


def generate(work: Path, *extra: str) -> subprocess.CompletedProcess:
    """Run the generator the way a developer does, into a scratch directory."""
    return subprocess.run(
        ["bash", str(GENERATOR), "--output", str(work / "build_gun.glb"), *extra],
        cwd=REPO, capture_output=True, text=True, timeout=600)


class TheCommittedModel(unittest.TestCase):
    """Claims about the artifact on disk. These need no Blender, so they run in
    every clone and in CI."""

    def setUp(self) -> None:
        self.assertTrue(
            BUILD_GUN.exists(),
            f"{BUILD_GUN} is missing. It is committed, unlike every weapon "
            f"viewmodel: run bash tools/assets/generate_build_gun.sh")
        self.doc = gltf_info.read_gltf_json(BUILD_GUN)

    def test_it_is_committed_rather_than_gitignored(self):
        """The one viewmodel on the committed side of the licence line.

        Asked of git rather than of the filesystem, because "the file is there" is
        also true of every gitignored converted weapon on the author's machine —
        and the claim being made is that *a clone* has it.
        """
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", str(BUILD_GUN.relative_to(REPO))],
            cwd=REPO, capture_output=True, text=True)
        self.assertEqual(tracked.returncode, 0,
                         "the Build Gun model is not tracked by git, so a clone "
                         "without the purchased packs would see placeholder boxes")

    def test_it_carries_a_draw_and_a_putaway_take(self):
        """A swap times itself off the clip lengths of the model on screen, so a
        Build Gun with no takes would snap into frame while every weapon swings.

        Matched the way `WeaponViewmodel.CLIP_NEEDLES` matches — lowercased
        substrings — rather than by exact name, because that is the code whose
        agreement actually matters.
        """
        names = [a.get("name", "") for a in self.doc.get("animations", [])]
        lowered = [n.lower() for n in names]
        self.assertTrue(any("draw" in n for n in lowered),
                        f"no Draw take; have {names}")
        self.assertTrue(any("putaway" in n or "holster" in n for n in lowered),
                        f"no PutAway take; have {names}")

    def test_every_surface_is_the_shared_palette_or_the_one_declared_light(self):
        """A third material creeping in is how a tool stops belonging to the world
        it builds. The palette is the surfaces of interwar heavy industry and has
        no emissive entry because no Machine emits anything; a projector lens does,
        so `build_gun_recipe.EMISSIVE_MATERIAL` is named and nothing else is."""
        allowed = {entry["name"] for entry in PALETTE["materials"]}
        allowed.add(recipe.EMISSIVE_MATERIAL)
        used = {m.get("name", "") for m in self.doc.get("materials", [])}
        self.assertTrue(used, "the model declares no materials at all")
        self.assertEqual(used - allowed, set(),
                         f"materials outside the palette: {sorted(used - allowed)}")

    def test_the_lens_and_the_rail_actually_emit(self):
        """`SHADING_MODE_UNSHADED` is not expressible in glTF, so what stands in
        for #29's unshaded rail is emission — and it is the one thing that keeps
        the rail reading as lit when the player faces away from the sun, which is
        the failure the placeholder's unshaded material was avoiding."""
        light = next((m for m in self.doc.get("materials", [])
                      if m.get("name") == recipe.EMISSIVE_MATERIAL), None)
        self.assertIsNotNone(light, f"no {recipe.EMISSIVE_MATERIAL} material")
        emissive = light.get("emissiveFactor", [0.0, 0.0, 0.0])
        self.assertGreater(max(emissive), 0.0,
                           "the projector material emits nothing, so the rail is "
                           "a dark stripe rather than a lit instrument")

    def test_it_embeds_no_image(self):
        """The same rule every generated Machine obeys, and here for a sharper
        reason: this is loaded at *runtime* through `GLTFDocument` rather than
        imported, so Godot substitutes nothing and whatever is in the file is what
        ships in the PCK."""
        self.assertEqual(self.doc.get("images", []), [],
                         "the Build Gun embeds texture data")

    def test_nothing_is_behind_the_eye(self):
        """The one viewmodel defect that has actually shipped in this project
        (`convert_weapons.sh`'s `--offset=0.0,0.0,-0.10`), asserted against the
        committed artifact rather than only inside the generator.

        A viewmodel is authored in camera space and glTF -Z is the way a Godot
        camera looks, so every vertex must sit at negative Z.
        """
        low, high = gltf_info.position_extents(self.doc)
        self.assertLess(high[2], 0.0,
                        f"part of the Build Gun is behind the camera: z extents "
                        f"{low[2]:.3f} to {high[2]:.3f}")

    def test_the_rest_pose_is_the_pose_the_recipe_declares(self):
        """**The defect no measurement of the recipe could see.**

        The generator measures its own geometry against the frustum, which is a
        statement about what it *meant* to export. What actually reached the file
        is a separate question, and it got a different answer: with the NLA
        strips holding their first frame outside their own range, the exporter
        wrote `Draw`'s stowed opening key as the root node's transform, so the
        tool shipped half a metre below the frame with every other check green.
        So this asks the **file** where the geometry is, and it asks it the way
        Godot will: the root carries no transform of its own, and the extents are
        where `build_gun_recipe` puts them.
        """
        root = next(n for n in self.doc["nodes"] if n.get("children"))
        self.assertNotIn("translation", root,
                         "the root carries a transform, so the rest pose is a "
                         "frame of a take rather than the pose declared")
        self.assertNotIn("rotation", root, "the same, as a rotation")

        low, high = gltf_info.position_extents(self.doc)
        # Forward is -Z and the grip is the aft end, so the nearest geometry sits
        # at about the grip's own distance. A metre of slack either way: this is
        # catching a model at the stowed pose, not auditing centimetres.
        self.assertAlmostEqual(-high[2], recipe.GRIP[1], delta=0.15,
                               msg="the tool does not begin where the grip does")
        # And it is below the eye and to the right of it, which is what being
        # held in a right hand means. The right-hand claim is about where the
        # tool's **mass** is rather than its nearest vertex: the yaw swings the
        # trigger guard a fraction of a millimetre across the centre line, and a
        # test that failed on that would be measuring the rounding rather than
        # the pose.
        self.assertLess(high[1], 0.0, "the tool is not below the eye")
        self.assertGreater((low[0] + high[0]) / 2.0, 0.05,
                           "the tool is not held to the right of the eye")

    def test_it_is_a_hand_tool_rather_than_a_rifle_in_size(self):
        """A loose bound, and it is about the *silhouette* rather than about taste:
        a metre of geometry hanging off the camera is not a thing somebody holds,
        and the shape this ticket exists to restore is read at arm's length."""
        low, high = gltf_info.position_extents(self.doc)
        length = high[2] - low[2]
        self.assertGreater(abs(length), 0.20, "the tool is too small to read")
        self.assertLess(abs(length), 0.80, "the tool is longer than an arm")


class RegeneratingFromTheRecipe(unittest.TestCase):
    """The workflow claim: edit `build_gun_recipe.py`, re-run, and the committed
    model is the new truth — with no manual step and no churn."""

    def setUp(self) -> None:
        if not blender_is_available():
            self.skipTest("blender is not on PATH")

    def test_reproduces_the_committed_model_byte_for_byte(self):
        """Determinism in the art pipeline. If regeneration churns bytes, every
        re-run is a meaningless diff and nobody will re-run it."""
        import tempfile
        with tempfile.TemporaryDirectory() as work:
            done = generate(Path(work))
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            fresh = Path(work) / "build_gun.glb"
            self.assertTrue(fresh.exists(), "the generator produced no file")
            self.assertEqual(fresh.read_bytes(), BUILD_GUN.read_bytes(),
                             "regenerating changed the committed model")

    def test_a_model_that_would_leave_the_frame_is_refused_rather_than_written(self):
        """**The half that matters.** A guard nobody has watched fire is
        indistinguishable from one that has quietly become a no-op — #57's lesson
        about the staleness check, applied to this one.

        Driven by narrowing the field of view rather than by moving the geometry,
        because the field of view is the quantity that is actually *tuned*: this is
        the real failure mode, which is somebody turning 75 down and the strike
        clipping, and it is exactly how `convert_weapons.sh` bracketed the wrench.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as work:
            done = generate(Path(work), "--field-of-view", "20")
            self.assertNotEqual(done.returncode, 0,
                                "a 20-degree field of view framed the whole tool, "
                                "so the measurement is not measuring anything")
            self.assertIn("leaves the frame", done.stdout + done.stderr)
            self.assertFalse((Path(work) / "build_gun.glb").exists(),
                             "a model that leaves the frame was written anyway")

    def test_a_field_of_view_it_cannot_read_is_an_error_naming_the_file(self):
        """No defaults anywhere, which is `Definitions`' rule and #61's: resolving
        a missing authority to a plausible number is the silence that gets
        shipped."""
        import tempfile
        with tempfile.TemporaryDirectory() as work:
            empty = Path(work) / "tuning.toml"
            empty.write_text("[player]\n")
            done = generate(Path(work), "--tuning", str(empty))
            self.assertNotEqual(done.returncode, 0, "a missing key was tolerated")
            self.assertIn("field_of_view_degrees", done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
