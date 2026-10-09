"""Behaviour of the first-person viewmodel conversion path.

Seam: the converter's command line
(`blender --background --python tools/assets/fbx_to_viewmodel.py -- ...`) and the
`.glb` it writes, read back with `tools/assets/gltf_info.py` — a standard-library
glTF reader that knows nothing about Blender. Same arrangement as
`test_fbx_to_gltf.py`, for the same reason: these check the artefact rather than
the implementation.

**Every one of these runs on a fixture, never on a purchased pack.** The packs the
real recipe reads forbid redistribution and are not in this repository
(docs/ASSETS.md), so a test that needed them would be a test only one machine
could run. `viewmodel.fbx` in `build_fixtures.py` reproduces the three things
about those files that actually bite: a take spread across an armature *and* a
loose weapon part, a `default` take holding every action end to end, and a weapon
body that arrives unparented and unanimated.
"""

import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_info  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
CONVERTER = REPO / "tools" / "assets" / "fbx_to_viewmodel.py"
RECIPE = REPO / "tools" / "assets" / "convert_weapons.sh"
BUILDER = Path(__file__).resolve().parent / "build_fixtures.py"
BLENDER = shutil.which("blender")

_fixture_dir: Path | None = None
_counter = iter(range(10000))


def setUpModule():
    global _fixture_dir
    if BLENDER is None:
        raise unittest.SkipTest("blender is not on PATH")
    import tempfile
    _fixture_dir = Path(tempfile.mkdtemp(prefix="viewmodel-fixtures-"))
    command = [BLENDER, "--background", "--factory-startup", "--python", str(BUILDER),
               "--", "--out-dir", str(_fixture_dir)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"blender failed building fixtures:\n{result.stdout}\n{result.stderr}")


def convert_to(*extra: str) -> Path:
    """Convert the viewmodel fixture and return the path of the .glb written."""
    out = _fixture_dir / f"viewmodel-{next(_counter)}.glb"
    command = [BLENDER, "--background", "--factory-startup", "--python", str(CONVERTER), "--",
               "--input", str(_fixture_dir / "viewmodel.fbx"), "--output", str(out),
               "--drop-take", "default", "--drop-take", "rest", *extra]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"converter failed:\n{result.stdout}\n{result.stderr}")
    assert out.exists(), f"converter produced no file at {out}"
    return out


def convert(*extra: str) -> dict:
    return gltf_info.summary(convert_to(*extra))


def raw(path: Path) -> dict:
    return gltf_info.read_gltf_json(path)


class KeepsTheNamedTakesAndDropsTheRest(unittest.TestCase):
    def test_every_named_take_becomes_an_animation_of_its_own_name(self):
        after = convert()
        self.assertEqual(sorted(after["animations"]), ["Shoot", "idle"])

    def test_the_take_holding_everything_end_to_end_is_dropped(self):
        # `default` spans the whole timeline and contains every action in
        # sequence (docs/LICENSED_ASSETS.md). Playing it would look like the
        # weapon having a seizure.
        self.assertNotIn("default", convert()["animations"])

    def test_a_take_name_keeps_the_name_the_artist_gave_it(self):
        # FBX takes import as `Part|Part|Shoot` — three parts, two of which name
        # the object and the authoring layer. What Godot's AnimationPlayer should
        # show is `Shoot`.
        for name in convert()["animations"]:
            self.assertNotIn("|", name)


class OneTakeIsOneAnimationAcrossEveryObjectItMoves(unittest.TestCase):
    def test_an_animation_drives_the_arms_and_the_weapon_part_together(self):
        # The thing this converter exists for. A weapon's magazine, bolt and
        # trigger are animated as *objects* while the hands are animated as
        # bones, so a take is a group of actions rather than one action — and an
        # exporter that wrote one animation per action would produce a dozen
        # same-named animations that each move a third of the weapon.
        document = raw(convert_to())
        nodes = document["nodes"]
        for animation in document["animations"]:
            targets = {nodes[channel["target"]["node"]].get("name")
                       for channel in animation["channels"]}
            self.assertIn("Part", targets,
                          f"{animation.get('name')} does not move the weapon part")
            self.assertTrue(
                targets - {"Part"},
                f"{animation.get('name')} moves nothing but the weapon part")


class AttachesAWeaponBodyTheImportLeftLoose(unittest.TestCase):
    def test_without_the_flag_the_body_hangs_off_the_root(self):
        document = raw(convert_to())
        self.assertEqual(self.parent_of(document, "WeaponBody"), "Viewmodel")

    def test_the_body_becomes_a_child_of_the_part_that_carries_it(self):
        # An FBX skin cluster over plain helpers does not survive Blender's
        # importer, so the weapon's own body arrives unparented and unanimated
        # at the world origin while the hands animate around it.
        document = raw(convert_to("--parent", "WeaponBody=Part"))
        self.assertEqual(self.parent_of(document, "WeaponBody"), "Part")

    def test_a_parent_that_is_not_in_the_file_is_refused_by_name(self):
        out = _fixture_dir / "unused.glb"
        command = [BLENDER, "--background", "--factory-startup", "--python", str(CONVERTER),
                   "--", "--input", str(_fixture_dir / "viewmodel.fbx"),
                   "--output", str(out), "--parent", "WeaponBody=NoSuchBone"]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertIn("NoSuchBone", result.stdout + result.stderr)

    @staticmethod
    def parent_of(document, name):
        nodes = document["nodes"]
        wanted = next(i for i, node in enumerate(nodes) if node.get("name") == name)
        for node in nodes:
            if wanted in node.get("children", []):
                return node.get("name")
        return None


class FramesTheModelAgainstTheAuthoringCamera(unittest.TestCase):
    """The root node carries the framing, which is what makes the model land in
    front of Godot's camera when it is parented there at identity."""

    def root_transform(self, *extra: str) -> dict:
        document = raw(convert_to(*extra))
        roots = {child for node in document["nodes"] for child in node.get("children", [])}
        top = [node for index, node in enumerate(document["nodes"]) if index not in roots]
        named = [node for node in top if node.get("name") == "Viewmodel"]
        self.assertTrue(named, [node.get("name") for node in top])
        return named[0]

    def test_the_origin_object_ends_up_at_the_origin(self):
        # The fixture's `EyePoint` stands 1.7 m up, so naming it moves everything
        # down by 1.7 m — which is what puts a viewmodel in frame when it is
        # parented to Godot's camera at identity. glTF is Y-up, so Blender's Z
        # becomes the Y of the translation.
        self.assertNotIn("translation", self.root_transform(),
                         "without a camera to frame against, nothing moves")
        framed = self.root_transform("--origin-object", "EyePoint")
        self.assertAlmostEqual(framed["translation"][1], -1.7, places=3)

    def test_an_offset_is_applied_after_the_framing(self):
        framed = self.root_transform("--origin-object", "EyePoint", "--offset", "0,0,-0.2")
        self.assertAlmostEqual(framed["translation"][1], -1.9, places=3)

    def test_the_middle_number_of_an_offset_is_forward_and_not_up(self):
        # The axis that bit. An offset is written in **Blender's** axes, where Y is
        # the horizontal depth axis and Z is up, and the exporter's Y-up conversion
        # then sends Blender +Y to glTF -Z. So the middle number of `--offset` moves
        # the model the way the camera is looking — it is *forward*, not back and not
        # up — and a recipe author who reads it as either of those pushes the model
        # into the camera rather than away from it. That is exactly how the Pneumatic
        # Wrench came to be framed with the viewer standing inside its arms.
        pushed = self.root_transform("--origin-object", "EyePoint", "--offset", "0,0.2,0")
        self.assertAlmostEqual(pushed["translation"][2], -0.2, places=3,
                               msg="Blender +Y is glTF -Z, which is the way the camera looks")
        self.assertAlmostEqual(pushed["translation"][1], -1.7, places=3,
                               msg="and it leaves the height the framing chose alone")

    def test_scale_is_carried_by_the_root_rather_than_left_on_each_object(self):
        scaled = self.root_transform("--scale", "0.5")
        for axis in range(3):
            self.assertAlmostEqual(abs(scaled["scale"][axis]), 0.5, places=3)


class RepaintsAPackThatShipsNoTextures(unittest.TestCase):
    def test_a_named_material_takes_the_colour_it_is_given(self):
        # Several of these packs reference textures they do not ship, so the arms
        # and the weapon arrive white. The replacement is a palette value in the
        # recipe, which is a number rather than an asset and so can be committed.
        document = raw(convert_to("--material-colour", "Material=40442F,0,0.58"))
        painted = [m for m in document["materials"] if m.get("name") == "Material"]
        self.assertTrue(painted, [m.get("name") for m in document["materials"]])
        pbr = painted[0]["pbrMetallicRoughness"]
        self.assertAlmostEqual(pbr["metallicFactor"], 0.0, places=3)
        self.assertAlmostEqual(pbr["roughnessFactor"], 0.58, places=3)
        # glTF's baseColorFactor is linear, so a colour picked by eye in sRGB
        # has to be converted. sRGB 0x40 is 64/255 = 0.2510, and the sRGB
        # transfer function puts that at 0.05127 linear.
        self.assertAlmostEqual(pbr["baseColorFactor"][0], 0.05127, places=4)

    def test_a_material_the_model_does_not_have_is_reported_rather_than_fatal(self):
        out = _fixture_dir / f"viewmodel-{next(_counter)}.glb"
        command = [BLENDER, "--background", "--factory-startup", "--python", str(CONVERTER),
                   "--", "--input", str(_fixture_dir / "viewmodel.fbx"), "--output", str(out),
                   "--material-colour", "NoSuchMaterial=40442F"]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("NoSuchMaterial", result.stdout)


class TheRecipeIsTheRecord(unittest.TestCase):
    """`convert_weapons.sh` is the only record of which pack became which weapon.

    The packs are not in git, so if this file stops naming them the mapping is
    lost — which is the same reason `docs/LICENSED_ASSETS.md` exists at all.
    """

    def setUp(self):
        self.recipe = RECIPE.read_text()

    def test_it_names_a_source_for_every_weapon_frame_in_the_gear_table(self):
        gear = (REPO / "content" / "gear.csv").read_text().splitlines()
        header = next(line for line in gear if line.startswith("id,"))
        columns = header.split(",")
        kind, identifier = columns.index("kind"), columns.index("id")
        frames = [line.split(",")[identifier] for line in gear
                  if not line.startswith("#") and "," in line
                  and len(line.split(",")) > kind
                  and line.split(",")[kind] == "weapon"]
        self.assertTrue(frames, "gear.csv declares no weapon frames")
        for weapon in frames:
            self.assertIn(f"{weapon}.glb", self.recipe,
                          f"{weapon} has no viewmodel recipe and would stay a box")

    def test_it_writes_where_the_game_looks_and_nowhere_else(self):
        seam = (REPO / "game" / "weapon_viewmodel.gd").read_text()
        directory = seam.split('WEAPON_BODY_DIRECTORY: String = "res://')[1].split('"')[0]
        self.assertIn(directory.rstrip("/"), self.recipe)

    def test_everything_it_writes_is_somewhere_the_licence_guard_refuses(self):
        # A converted GLB is a derivative of a non-redistributable asset and is
        # exactly as forbidden as the FBX it came from.
        ignored = (REPO / ".gitignore").read_text()
        self.assertIn("/assets_licensed/", ignored)
        seam = (REPO / "game" / "weapon_viewmodel.gd").read_text()
        self.assertIn('"res://assets_licensed/', seam)

    def test_a_viewmodel_with_no_authoring_camera_is_pushed_out_in_front_of_the_eye(self):
        """A rig framed by hand is framed *away* from the viewer, never at the origin.

        The two `Weapon pack` rifles are framed by `--origin-object Camera001`, which
        is the camera the vendor authored them against, and need no offset at all. The
        RgsDev arms ship no camera object, so the recipe places the eye by hand — and
        the thing that has twice been got wrong is which way to place it.

        `Prefabs/FPSController.prefab` parents those arms to a `WeaponHolder` at
        (0, 0, 0) under the camera, so the model's own origin is the eye. That is the
        reason the recipe needs an offset rather than the reason it does not: the hands
        are posed about 21 cm in front of that origin, which puts the knife hand 44
        degrees off the axis at rest and throws it behind the camera at the top of the
        swing. `--offset=0.0,0.0,-0.10` shipped on exactly that reasoning and is the
        build a player reported the knife animation still not playing in.

        The middle number is forward, and forward is away from the viewer — the test
        above pins that axis against the exporter. So a hand-framed viewmodel's forward
        push is strictly positive, and this refuses the zero that shipped as firmly as
        it would refuse a negative one.
        """
        # Command lines only. The comment above the RgsDev block quotes both offsets
        # that were wrong, because the reasons they were wrong are worth keeping next
        # to the number that replaced them, and a check that read them would never go
        # green.
        lines = [line for line in self.recipe.splitlines() if not line.lstrip().startswith("#")]
        offsets = re.findall(r"--offset=(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)", "\n".join(lines))
        self.assertTrue(offsets, "the recipe declares no --offset to check")
        for offset in offsets:
            forward = float(offset[1])
            self.assertGreater(
                forward, 0.0,
                "--offset=%s leaves a viewmodel %.2f m in front of the eye, so the arms "
                "are posed around the camera rather than out where they can be seen"
                % (",".join(offset), forward)
            )

    def test_it_is_a_no_op_rather_than_an_error_without_the_packs(self):
        # Most clones do not have them, and `tools/assets/run_tests.sh` must not
        # fail on a machine that never bought anything.
        result = subprocess.run(["bash", str(RECIPE)], capture_output=True, text=True,
                                env={**__import__("os").environ,
                                     "LICENSED_ROOT": str(_fixture_dir / "nothing-here"),
                                     "WEAPON_OUT": str(_fixture_dir / "unused-out")})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("placeholder", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
