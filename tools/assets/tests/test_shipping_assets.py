"""Invariants every committed shipping asset must keep holding.

Seam: the committed `.glb` files themselves, plus — when Godot is installed —
the engine's own import of them. These are the regression tests for the asset
pipeline's output: if someone reconverts an asset with the wrong flags, or hand-
edits the recipe in `rebuild_assets.sh`, this is what notices.
"""

import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_info  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
SHIPPING_GLBS = sorted(REPO.glob("assets/**/*.glb"))
CC0_CHARACTER = REPO / "assets" / "characters" / "skeleton" / "Skeleton.glb"
CC0_KNIGHT = REPO / "assets" / "characters" / "knight" / "KnightCharacter.glb"


class EveryShippingAsset(unittest.TestCase):
    def test_there_is_at_least_one(self):
        self.assertTrue(SHIPPING_GLBS, "no .glb under assets/ — nothing ships yet")

    def test_is_gltf_2_with_a_single_skeleton_root(self):
        for path in SHIPPING_GLBS:
            with self.subTest(asset=path.name):
                doc = gltf_info.read_gltf_json(path)
                self.assertEqual(doc["asset"]["version"], "2.0")
                roots = gltf_info.skeleton_roots(doc)
                if roots:
                    self.assertEqual(len(roots), 1, f"root bones: {roots}")

    def test_carries_no_exporter_leaf_bones(self):
        for path in SHIPPING_GLBS:
            with self.subTest(asset=path.name):
                leftovers = [b for b in gltf_info.bone_names(gltf_info.read_gltf_json(path))
                             if b.endswith("_end")]
                self.assertEqual(leftovers, [])

    def test_intake_fbx_is_hidden_from_godot(self):
        """FBX is an intake format only: Godot must not import it as a scene.

        A `.gdignore` in each intake/ directory keeps the engine out, so the
        committed FBX stays reproducibility evidence rather than a second,
        uncorrected copy of the character that someone could use by mistake.
        """
        intake_dirs = {p.parent for p in REPO.glob("assets/**/intake/*.fbx")}
        self.assertTrue(intake_dirs, "no intake FBX found")
        for directory in intake_dirs:
            with self.subTest(directory=str(directory)):
                self.assertTrue((directory / ".gdignore").exists(),
                                f"{directory} needs a .gdignore")
                self.assertEqual(list(directory.glob("*.import")), [])

    def test_carries_no_fbx_mangled_animation_names(self):
        for path in SHIPPING_GLBS:
            with self.subTest(asset=path.name):
                mangled = [a for a in gltf_info.animation_names(
                    gltf_info.read_gltf_json(path)) if "|" in a]
                self.assertEqual(mangled, [])


class TheCC0Character(unittest.TestCase):
    """The Quaternius Skeleton: the end-to-end proof that the pipeline works."""

    def setUp(self):
        if not CC0_CHARACTER.exists():
            self.skipTest(f"{CC0_CHARACTER} is not committed")
        self.summary = gltf_info.summary(CC0_CHARACTER)

    def test_its_intake_fbx_is_committed_so_the_conversion_is_reproducible(self):
        self.assertTrue((CC0_CHARACTER.parent / "intake" / "Skeleton.fbx").exists())

    def test_it_is_human_scale(self):
        self.assertAlmostEqual(self.summary["height_y"], 1.8, delta=0.05)

    def test_it_keeps_all_five_source_animations(self):
        self.assertEqual(sorted(self.summary["animations"]),
                         ["Skeleton_Attack", "Skeleton_Death", "Skeleton_Idle",
                          "Skeleton_Running", "Skeleton_Spawn"])

    def test_its_bones_use_the_shared_humanoid_names(self):
        for bone in ("Root", "Hips", "Spine", "Neck", "Head",
                     "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
                     "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"):
            self.assertIn(bone, self.summary["bones"])

    def test_the_animations_drive_the_renamed_bones(self):
        targets = set(self.summary["animation_targets"])
        self.assertTrue({"Hips", "Spine", "LeftUpperArm"} <= targets,
                        f"animations only drive {sorted(targets)}")

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_godot_imports_it_and_plays_every_animation(self):
        result = subprocess.run(
            ["bash", "tools/assets/verify_in_godot.sh",
             str(CC0_CHARACTER.relative_to(REPO)), "1.8"],
            cwd=REPO, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         result.stdout[-4000:] + result.stderr[-2000:])
        self.assertIn("0 failed", result.stdout)


class TheCC0Knight(unittest.TestCase):
    """A second character, whose rig names line up with the profile only after
    mapping by position in the hierarchy."""

    def setUp(self):
        if not CC0_KNIGHT.exists():
            self.skipTest(f"{CC0_KNIGHT} is not committed")
        self.summary = gltf_info.summary(CC0_KNIGHT)

    def test_it_keeps_all_twelve_source_animations(self):
        self.assertEqual(len(self.summary["animations"]), 12,
                         f"got {self.summary['animations']}")

    def test_its_spine_chain_was_remapped_without_colliding(self):
        for bone in ("Root", "Hips", "Spine", "Chest", "UpperChest"):
            self.assertIn(bone, self.summary["bones"])
        collisions = [b for b in self.summary["bones"]
                      if "." in b and not b.startswith("PoleTarget")]
        self.assertEqual(collisions, [], f"a rename collided: {self.summary['bones']}")

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_godot_imports_it_and_plays_every_animation(self):
        result = subprocess.run(
            ["bash", "tools/assets/verify_in_godot.sh",
             str(CC0_KNIGHT.relative_to(REPO)), "1.8", "12"],
            cwd=REPO, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         result.stdout[-4000:] + result.stderr[-2000:])


class AnimationIsInterchangeable(unittest.TestCase):
    """What the shared humanoid skeleton buys: one rig's animation drives another."""

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_the_skeletons_run_cycle_drives_the_knight(self):
        for asset in (CC0_CHARACTER, CC0_KNIGHT):
            if not asset.exists():
                self.skipTest(f"{asset} is not committed")
        result = subprocess.run(
            ["bash", "tools/assets/verify_retarget_in_godot.sh",
             str(CC0_CHARACTER.relative_to(REPO)), "Skeleton_Running",
             str(CC0_KNIGHT.relative_to(REPO))],
            cwd=REPO, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         result.stdout[-4000:] + result.stderr[-2000:])
        self.assertIn("0 failed", result.stdout)


class TheGeneratedEnemyBodies(unittest.TestCase):
    """The three Enemies are generated rather than converted since #79, so what
    there is to assert about them is **not** in this file.

    This class is deliberately a pointer rather than a set of tests.
    `test_generated_enemies.py` is the one that regenerates them from
    `tools/assets/enemy_recipe.py` and compares the bytes, which is #57's stronger
    instrument for a committed output — and the KayKit class that stood here, six
    characters and four animation libraries of it, went with the cast #79 replaced.
    A pack nothing reads is art nothing reads, which is the rule `Definitions`
    applies to a tuning key.
    """

    def test_the_enemy_bodies_are_committed_and_have_their_own_suite(self):
        bodies = sorted((REPO / "assets" / "characters" / "insects").glob("*.glb"))
        self.assertTrue(bodies, "assets/characters/insects/ is empty")
        self.assertTrue(
            (Path(__file__).parent / "test_generated_enemies.py").exists(),
            "the suite that regenerates and compares them")

    def test_the_kaykit_pack_is_gone_rather_than_unread(self):
        """#79's deletion, asserted so that somebody restoring the directory has to
        decide to rather than drift into it. There is nothing left that loads it:
        `EnemyBodies.recipe_for` names `assets/characters/insects/`."""
        self.assertFalse((REPO / "assets" / "characters" / "kaykit_skeletons").exists())
        self.assertFalse((REPO / "tools" / "assets" / "enemy_grade.py").exists())


if __name__ == "__main__":
    unittest.main()
