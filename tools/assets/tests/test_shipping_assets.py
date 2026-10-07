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
KAYKIT = REPO / "assets" / "characters" / "kaykit_skeletons"
# The pack's six characters, and the body height each one lands at under the one
# shared scale factor. Only the bare Minion is exactly 1.8: the rest carry
# headgear or sit on the larger rig, and keeping those differences is the point of
# scaling the whole pack by one factor instead of normalising each file.
KAYKIT_CHARACTERS = {
    "minion/Skeleton_Minion.glb": 1.80,
    "warrior/Skeleton_Warrior.glb": 2.04,
    "rogue/Skeleton_Rogue.glb": None,
    "mage/Skeleton_Mage.glb": None,
    "necromancer/Necromancer.glb": None,
    "golem/Skeleton_Golem.glb": None,
}
KAYKIT_LIBRARIES = {
    "Rig_Medium_General": 15,
    "Rig_Medium_MovementBasic": 11,
    "Rig_Large_General": 6,
    "Rig_Large_MovementBasic": 3,
}


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


class TheCC0KayKitSkeletons(unittest.TestCase):
    """Six characters on two rigs, with their animation in separate files.

    This is the first pack in the repository that separates animation from the
    characters, which is the arrangement docs/ASSET_PIPELINE.md section 4 asks
    for: the characters ship no animation at all, and four libraries of clips on
    the same shared skeleton ship beside them.
    """

    def setUp(self):
        if not KAYKIT.exists():
            self.skipTest(f"{KAYKIT} is not committed")

    def test_every_character_and_library_is_committed(self):
        for relative in list(KAYKIT_CHARACTERS) + [
                f"animations/{name}.glb" for name in KAYKIT_LIBRARIES]:
            with self.subTest(asset=relative):
                self.assertTrue((KAYKIT / relative).exists())

    def test_every_intake_fbx_is_committed_so_the_conversion_is_reproducible(self):
        for relative in KAYKIT_CHARACTERS:
            directory, name = relative.split("/")
            with self.subTest(asset=relative):
                self.assertTrue(
                    (KAYKIT / directory / "intake" / name.replace(".glb", ".fbx")).exists())
        for name in KAYKIT_LIBRARIES:
            with self.subTest(asset=name):
                self.assertTrue((KAYKIT / "animations" / "intake" / f"{name}.fbx").exists())

    def test_the_licence_ships_with_the_pack(self):
        self.assertIn("CC0", (KAYKIT / "LICENSE.txt").read_text(errors="replace"))

    def test_the_whole_pack_shares_one_scale_so_relative_sizes_survive(self):
        """One factor for every file, not --target-height per file.

        The bare Minion is the reference and lands on 1.8 m. The Golem is on the
        larger rig and must stay a giant, not be normalised down to human height,
        and the animation libraries must be scaled with the characters or borrowed
        root and hips translation lands in the wrong place.
        """
        minion = gltf_info.summary(KAYKIT / "minion/Skeleton_Minion.glb")
        self.assertAlmostEqual(minion["height_y"], 1.8, delta=0.01)
        golem = gltf_info.summary(KAYKIT / "golem/Skeleton_Golem.glb")
        self.assertGreater(golem["height_y"], 3.0,
                           "the Golem was normalised to human height; it is a giant")

    def test_the_characters_ship_no_animation_of_their_own(self):
        for relative in KAYKIT_CHARACTERS:
            with self.subTest(asset=relative):
                self.assertEqual(gltf_info.summary(KAYKIT / relative)["animations"], [])

    def test_every_rig_is_the_same_23_bone_shared_skeleton(self):
        expected = {"Root", "Hips", "Spine", "Chest", "Head",
                    "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftMiddleProximal",
                    "RightUpperArm", "RightLowerArm", "RightHand", "RightMiddleProximal",
                    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
                    "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
                    "handslot.l", "handslot.r"}
        for relative in list(KAYKIT_CHARACTERS) + [
                f"animations/{name}.glb" for name in KAYKIT_LIBRARIES]:
            with self.subTest(asset=relative):
                self.assertEqual(set(gltf_info.summary(KAYKIT / relative)["bones"]), expected)

    def test_the_rig_has_no_neck_which_is_why_the_verifier_is_told_so(self):
        """The one shared-skeleton bone this pack cannot supply.

        `head` is a direct child of `chest` in the source rig. Nothing is renamed
        into Neck and no joint is invented to satisfy the gate; the exception is
        passed to verify_in_godot.sh explicitly instead.
        """
        bones = gltf_info.summary(KAYKIT / "minion/Skeleton_Minion.glb")["bones"]
        self.assertNotIn("Neck", bones)
        self.assertNotIn("UpperChest", bones)

    def test_the_weapon_sockets_keep_their_pack_names(self):
        bones = gltf_info.summary(KAYKIT / "warrior/Skeleton_Warrior.glb")["bones"]
        self.assertIn("handslot.l", bones)
        self.assertIn("handslot.r", bones)

    def test_each_library_keeps_all_its_source_clips(self):
        for name, count in KAYKIT_LIBRARIES.items():
            with self.subTest(library=name):
                animations = gltf_info.summary(
                    KAYKIT / "animations" / f"{name}.glb")["animations"]
                self.assertEqual(len(animations), count, f"got {animations}")

    def test_the_library_clips_drive_shared_skeleton_bones(self):
        targets = set(gltf_info.summary(
            KAYKIT / "animations/Rig_Medium_MovementBasic.glb")["animation_targets"])
        self.assertTrue({"Root", "Hips", "Spine", "LeftUpperArm", "LeftUpperLeg"} <= targets,
                        f"clips only drive {sorted(targets)}")

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_godot_imports_every_character(self):
        for relative, height in KAYKIT_CHARACTERS.items():
            with self.subTest(asset=relative):
                result = subprocess.run(
                    ["bash", "tools/assets/verify_in_godot.sh",
                     str((KAYKIT / relative).relative_to(REPO)),
                     str(height) if height else "0", "0", "Neck"],
                    cwd=REPO, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0,
                                 result.stdout[-4000:] + result.stderr[-2000:])

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_godot_imports_every_library_and_plays_every_clip(self):
        for name, count in KAYKIT_LIBRARIES.items():
            with self.subTest(library=name):
                result = subprocess.run(
                    ["bash", "tools/assets/verify_in_godot.sh",
                     str((KAYKIT / "animations" / f"{name}.glb").relative_to(REPO)),
                     "0", str(count), "Neck"],
                    cwd=REPO, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0,
                                 result.stdout[-4000:] + result.stderr[-2000:])

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_a_library_clip_drives_a_character_that_ships_no_animation(self):
        """What separating animation from characters has to buy to be worth it."""
        result = subprocess.run(
            ["bash", "tools/assets/verify_retarget_in_godot.sh",
             str((KAYKIT / "animations/Rig_Medium_MovementBasic.glb").relative_to(REPO)),
             "Running_A",
             str((KAYKIT / "warrior/Skeleton_Warrior.glb").relative_to(REPO))],
            cwd=REPO, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0,
                         result.stdout[-4000:] + result.stderr[-2000:])

    @unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
    def test_animation_crosses_between_this_pack_and_the_quaternius_ones(self):
        """Two packs from different artists, one skeleton, either direction."""
        for donor, clip, recipient in (
                (CC0_CHARACTER, "Skeleton_Running", KAYKIT / "minion/Skeleton_Minion.glb"),
                (KAYKIT / "animations/Rig_Medium_MovementBasic.glb", "Walking_A", CC0_KNIGHT)):
            if not donor.exists() or not recipient.exists():
                self.skipTest(f"{donor} or {recipient} is not committed")
            with self.subTest(donor=donor.name, recipient=recipient.name):
                result = subprocess.run(
                    ["bash", "tools/assets/verify_retarget_in_godot.sh",
                     str(donor.relative_to(REPO)), clip, str(recipient.relative_to(REPO))],
                    cwd=REPO, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0,
                                 result.stdout[-4000:] + result.stderr[-2000:])


if __name__ == "__main__":
    unittest.main()
