"""Behaviour of the FBX-to-glTF conversion path.

Seam: the converter's command line
(`blender --background --python tools/assets/fbx_to_gltf.py -- ...`) and the
`.glb` it writes. The output is inspected with `tools/assets/gltf_info.py`, a
standard-library glTF reader that knows nothing about Blender, so these tests
check the artefact rather than the implementation.

Each test corresponds to one breakage reproduced by `build_fixtures.py`.
"""

import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_info  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
CONVERTER = REPO / "tools" / "assets" / "fbx_to_gltf.py"
BUILDER = Path(__file__).resolve().parent / "build_fixtures.py"
BLENDER = shutil.which("blender")

_fixture_dir: Path | None = None


def blender_run(script: Path, *args: str):
    command = [BLENDER, "--background", "--factory-startup", "--python", str(script), "--", *args]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(
            f"blender failed: {' '.join(command)}\n--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}")
    return result


def setUpModule():
    """Build the FBX fixtures once for the whole module."""
    global _fixture_dir
    if BLENDER is None:
        raise unittest.SkipTest("blender is not on PATH")
    import tempfile
    _fixture_dir = Path(tempfile.mkdtemp(prefix="fbx-fixtures-"))
    blender_run(BUILDER, "--out-dir", str(_fixture_dir))


_counter = iter(range(10000))


def convert_to(fixture: str, *extra: str) -> Path:
    """Convert a fixture and return the path of the .glb written."""
    source = _fixture_dir / fixture
    out = _fixture_dir / f"{Path(fixture).stem}-{next(_counter)}.glb"
    blender_run(CONVERTER, "--input", str(source), "--output", str(out), *extra)
    assert out.exists(), f"converter produced no file at {out}"
    return out


def convert(fixture: str, *extra: str) -> dict:
    """Convert a fixture and return the glTF summary of the result."""
    return gltf_info.summary(convert_to(fixture, *extra))


class CorrectsRigBreakages(unittest.TestCase):
    def test_multiple_root_bones_become_one(self):
        after = convert("multi_root.fbx")
        self.assertEqual(len(after["skeleton_roots"]), 1,
                         f"expected a single skeleton root, got {after['skeleton_roots']}")

    def test_the_single_root_is_named_for_the_shared_convention(self):
        after = convert("multi_root.fbx", "--root-bone", "Root")
        self.assertEqual(after["skeleton_roots"], ["Root"])

    def test_no_bone_is_lost_when_roots_are_merged(self):
        after = convert("multi_root.fbx", "--root-bone", "Root")
        for bone in ("Hips", "Spine", "WeaponSocket", "PropHandle"):
            self.assertIn(bone, after["bones"])


    def test_unweighted_vertices_do_not_add_a_second_skeleton_root(self):
        """Blender invents a `neutral_bone` for orphan vertices; it must not survive."""
        after = convert("orphan_weights.fbx", "--root-bone", "Root")
        self.assertEqual(after["skeleton_roots"], ["Root"],
                         f"bones: {after['bones']}")
        self.assertNotIn("neutral_bone", after["bones"])

    def test_renaming_a_bone_onto_the_root_name_does_not_duplicate_the_root(self):
        """The bone map and the root unification must not fight over the name."""
        bone_map = _fixture_dir / "root_rename_map.json"
        bone_map.write_text(json.dumps({"Hips": "Root", "Spine": "Spine"}))
        after = convert("multi_root.fbx", "--root-bone", "Root",
                        "--bone-map", str(bone_map))
        self.assertEqual(after["skeleton_roots"], ["Root"])
        self.assertEqual([b for b in after["bones"] if b.startswith("Root.")], [],
                         f"a duplicate root crept in: {after['bones']}")


class CorrectsUnityConventions(unittest.TestCase):
    def test_scale_is_applied_so_a_100_unit_character_becomes_1_unit(self):
        after = convert("unity_conventions.fbx", "--scale", "0.01")
        self.assertAlmostEqual(after["height_y"], 1.0, delta=0.01,
                               msg=f"extents were {after['mesh_extents_xyz']}")

    def test_a_target_height_normalises_a_wrongly_scaled_character(self):
        after = convert("unity_conventions.fbx", "--target-height", "1.8")
        self.assertAlmostEqual(after["height_y"], 1.8, delta=0.02,
                               msg=f"extents were {after['mesh_extents_xyz']}")

    def test_leftover_axis_rotation_is_baked_out_of_the_armature(self):
        path = convert_to("unity_conventions.fbx", "--scale", "0.01")
        doc = gltf_info.read_gltf_json(path)
        root = gltf_info.scene_roots(doc)[0]
        self.assertTrue(gltf_info.node_transform_is_identity(doc, root),
                        f"root node {root!r} still carries a transform")

    def test_export_is_gltf_2_point_0(self):
        after = convert("unity_conventions.fbx", "--scale", "0.01")
        self.assertEqual(after["version"], "2.0")


class DeduplicatesTextures(unittest.TestCase):
    def test_identical_textures_collapse_to_one_image(self):
        after = convert("duplicate_textures.fbx")
        self.assertEqual(after["images"], 1,
                         "byte-identical textures should be shared, not duplicated")

    def test_materials_are_preserved(self):
        after = convert("duplicate_textures.fbx")
        self.assertGreaterEqual(len(after["materials"]), 1)


class FindsRelocatedTextures(unittest.TestCase):
    def test_a_texture_whose_authoring_path_is_gone_is_dropped_by_default(self):
        after = convert("relocated_textures.fbx")
        self.assertEqual(after["images"], 0,
                         "a broken texture reference must not be exported")

    def test_a_texture_directory_recovers_it(self):
        after = convert("relocated_textures.fbx",
                        "--texture-dir", str(_fixture_dir) + "-textures")
        self.assertEqual(after["images"], 1,
                         "the texture should have been found and embedded")


class CleansAnimationNames(unittest.TestCase):
    def test_fbx_take_name_prefixes_are_stripped(self):
        after = convert("prefixed_actions.fbx")
        self.assertEqual(sorted(after["animations"]), ["Attack", "Walk"],
                         f"got {after['animations']}")


class RenamesOntoTheSharedSkeleton(unittest.TestCase):
    def test_a_bone_map_renames_bones_to_the_shared_humanoid_names(self):
        bone_map = _fixture_dir / "map.json"
        bone_map.write_text(json.dumps({"Hips": "Hips", "Spine": "Spine",
                                        "WeaponSocket": "LeftHand",
                                        "PropHandle": "RightHand"}))
        after = convert("multi_root.fbx", "--root-bone", "Root",
                        "--bone-map", str(bone_map))
        self.assertIn("LeftHand", after["bones"])
        self.assertIn("RightHand", after["bones"])
        self.assertNotIn("WeaponSocket", after["bones"])

    def test_animation_follows_a_renamed_bone(self):
        """A rename that loses the animation channels would be worse than no rename."""
        bone_map = _fixture_dir / "animated_map.json"
        bone_map.write_text(json.dumps({"Hips": "Hips", "Spine": "Chest"}))
        after = convert("prefixed_actions.fbx", "--root-bone", "Root",
                        "--bone-map", str(bone_map))
        self.assertEqual(sorted(after["animations"]), ["Attack", "Walk"])
        self.assertIn("Chest", after["animation_targets"],
                      f"animations target {after['animation_targets']}")

    def test_a_map_that_shifts_names_along_a_chain_does_not_collide(self):
        """Real rigs need Hips->Spine while another bone becomes Hips."""
        bone_map = _fixture_dir / "shifting_map.json"
        bone_map.write_text(json.dumps({"Hips": "Spine", "Spine": "Chest",
                                        "WeaponSocket": "Hips"}))
        after = convert("multi_root.fbx", "--root-bone", "Root",
                        "--bone-map", str(bone_map))
        for bone in ("Hips", "Spine", "Chest"):
            self.assertIn(bone, after["bones"])
        self.assertEqual([b for b in after["bones"] if "." in b], [],
                         f"a rename collided: {after['bones']}")

    def test_an_unmapped_bone_is_reported_rather_than_silently_kept(self):
        bone_map = _fixture_dir / "partial_map.json"
        bone_map.write_text(json.dumps({"Hips": "Hips"}))
        source = _fixture_dir / "multi_root.fbx"
        out = _fixture_dir / "partial.glb"
        result = blender_run(CONVERTER, "--input", str(source), "--output", str(out),
                             "--bone-map", str(bone_map))
        self.assertIn("Spine", result.stdout + result.stderr,
                      "unmapped bones should be named in the report")


if __name__ == "__main__":
    unittest.main()
