"""What the committed Enemy bodies must be true of, checked against the
declaration they were generated from.

Seam: the committed `.glb` files under `assets/characters/insects/`, read with the
standard-library glTF reader. Nothing here imports Blender or calls into the
generator's internals — these tests ask only whether the artifact on disk agrees
with `tools/assets/enemy_recipe.py`, with `dieselpunk_palette.json`, and with the
budget `game/enemy_bodies.gd` bakes inside.

**This is #57's rule applied to a committed output: where the output is committed,
prove it.** These three files are gitignored by nothing, so they are deliberately
absent from `asset_staleness.py` — dating a file against its recipe is the weaker
instrument and is for the outputs a clone cannot see. Regenerating and comparing
the bytes is the stronger one, and it is what makes "change a dimension by editing
the declaration and re-running" a claim rather than a hope.
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import enemy_recipe  # noqa: E402
import gltf_info  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
INSECT_DIR = REPO / "assets" / "characters" / "insects"
GENERATOR = REPO / "tools" / "assets" / "generate_enemies.sh"
PALETTE: list[dict] = json.loads(
    (REPO / "tools" / "assets" / "dieselpunk_palette.json").read_text()
)["materials"]
ENEMY_BODIES = REPO / "game" / "enemy_bodies.gd"

#: The bake writes `bone_count * TEXELS_PER_BONE` texels across one row a frame, and
#: `game/enemy_bodies.gd`'s whole argument for baking bone poses rather than vertex
#: positions is that the texture is a property of the *rig* and does not grow with the
#: model. 23 is what the KayKit cast used and is the figure that file's own note quotes,
#: so it is the ceiling a declared rig may not quietly walk past.
BONE_BUDGET = 23

#: `EnemyBodies.INFLUENCES` is 4 and keeps the four heaviest, so a fifth would be dropped
#: in silence. These bodies are rigid plate and use exactly one, which is both what an
#: exoskeleton is and the reason the renormalisation in `_merge` has nothing to do.
INFLUENCES_PER_VERTEX = 1

#: "Not too detailed" is the user's own instruction and a performance one: these are drawn
#: through one MultiMesh a kind in the thousands. The KayKit characters were 4,858 vertices
#: each; a declared body is well under a fifth of that, and this is the ceiling that keeps
#: it so when somebody adds a part. Per kind, because the Breaker has four legs and the
#: other two have six.
TRIANGLE_BUDGET = 1200

#: How far off exactly one metre tall a committed body may be. `EnemyBodies._bake`
#: normalises whatever it is handed, so this is not load-bearing for the engine — it is the
#: claim that the *generator* already did it, which is what makes the shader's grime field
#: read in body fractions (`grime_metres`) rather than in whatever units an artist used.
HEIGHT_TOLERANCE = 1e-4


def glb_for(kind_id: str) -> Path:
    return INSECT_DIR / f"{kind_id}.glb"


def primitives(doc: dict) -> list[dict]:
    return [prim for mesh in doc.get("meshes", []) for prim in mesh["primitives"]]


def node_named(doc: dict, name: str) -> dict | None:
    for node in doc.get("nodes", []):
        if node.get("name") == name:
            return node
    return None


def read(kind_id: str) -> dict:
    return gltf_info.read_gltf_json(glb_for(kind_id))


def _extents_of_material(kind_id: str, material: str) -> tuple[list[float], list[float]]:
    """The bounding box of just the primitives wearing one palette entry, read out of
    the accessors' own declared `min`/`max`."""
    doc = read(kind_id)
    names = [entry["name"] for entry in doc.get("materials", [])]
    low = [float("inf")] * 3
    high = [float("-inf")] * 3
    found = False
    for prim in primitives(doc):
        if names[prim["material"]] != material:
            continue
        found = True
        accessor = doc["accessors"][prim["attributes"]["POSITION"]]
        for axis in range(3):
            low[axis] = min(low[axis], accessor["min"][axis])
            high[axis] = max(high[axis], accessor["max"][axis])
    assert found, f"{kind_id} has no surface wearing {material}"
    return low, high


def weights_of(kind_id: str) -> list[list[tuple]]:
    """Every primitive's `WEIGHTS_0`, one list a primitive, read out of the binary
    chunk — because the claim is about what is in the file rather than about what the
    generator meant."""
    doc, binary = gltf_info.read_glb(glb_for(kind_id))
    return [
        gltf_info._read_vectors(doc, binary, prim["attributes"]["WEIGHTS_0"], 4)
        for prim in primitives(doc)
    ]


class EveryDeclaredKindIsCommitted(unittest.TestCase):
    """The declaration and the directory agree in both directions."""

    def test_every_kind_in_the_recipe_has_a_committed_body(self):
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                self.assertTrue(glb_for(kind_id).exists(),
                                f"{glb_for(kind_id)} is not committed")

    def test_no_committed_body_is_left_over_from_a_kind_that_is_gone(self):
        """A `.glb` the declaration no longer names is art nothing reads, which is
        the rule `Definitions` applies to a tuning key nothing reads."""
        committed = sorted(path.stem for path in INSECT_DIR.glob("*.glb"))
        self.assertEqual(committed, sorted(enemy_recipe.kind_ids()))


class TheRigFitsInsideTheBake(unittest.TestCase):
    """The constraints `game/enemy_bodies.gd` bakes inside, asserted from the
    asset's side — because the engine would not refuse a rig that broke them, it
    would quietly produce a bigger texture or drop an influence."""

    def test_no_body_carries_more_bones_than_the_pose_texture_is_sized_for(self):
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                doc = read(kind_id)
                self.assertEqual(len(doc["skins"]), 1, "one skin per body")
                joints = len(doc["skins"][0]["joints"])
                self.assertLessEqual(joints, BONE_BUDGET,
                                     "the pose texture grows with this")

    def test_every_vertex_has_exactly_one_influence_at_full_weight(self):
        """Rigid plate, which is both what chitin is and what keeps
        `EnemyBodies._influences` with nothing to drop."""
        for kind_id in enemy_recipe.kind_ids():
            for index, weights in enumerate(weights_of(kind_id)):
                with self.subTest(kind=kind_id, primitive=index):
                    self.assertTrue(weights, "a skinned primitive has weights")
                    for vertex in weights:
                        heavy = [w for w in vertex if w > 0.0]
                        self.assertEqual(len(heavy), INFLUENCES_PER_VERTEX)
                        self.assertAlmostEqual(heavy[0], 1.0, places=5)

    def test_the_root_bone_is_the_first_joint(self):
        """`EnemyBodies._pose` replaces **bone 0**'s horizontal travel with its rest,
        so a rig whose first joint is not the root would have a leg pinned instead of
        a walk cycle de-travelled."""
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                doc = read(kind_id)
                first = doc["nodes"][doc["skins"][0]["joints"][0]]
                self.assertEqual(first.get("name"), "Root")


class TheBodyIsTheShapeTheRendererExpects(unittest.TestCase):

    def test_every_body_is_one_metre_tall_with_its_feet_on_the_ground(self):
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                low, high = gltf_info.position_extents(read(kind_id))
                self.assertAlmostEqual(low[1], 0.0, delta=HEIGHT_TOLERANCE)
                self.assertAlmostEqual(high[1], 1.0, delta=HEIGHT_TOLERANCE)

    def test_every_body_faces_its_own_positive_z(self):
        """`WorldView._write_instance` maps a body's local +Z to its facing, so the
        mandibles have to be at +Z and the abdomen behind them. The one axis fact in
        the pipeline, and the one a Y-up conversion is easiest to get backwards.

        Read off the **mandible geometry** rather than off the head bone, which is
        the version of this that passes while being wrong: a bone node's translation
        is local to its parent and expressed in the parent bone's own axes, so the
        Head bone sits at `+y` along the Thorax whichever way the body faces, and
        every kind reported exactly 0 on z. The mandibles are the frontmost part of
        an insect and wear a material of their own, so their primitive's own extents
        are the claim."""
        for insect in enemy_recipe.KINDS:
            with self.subTest(kind=insect.kind_id):
                low, high = _extents_of_material(
                    insect.kind_id, insect.material("mandible"))
                self.assertGreater(low[2], 0.0,
                                   "every mandible vertex is in front of the origin")
                self.assertGreater(high[2], 0.5, "and well in front of it")

    def test_every_body_carries_uvs_for_the_palette_map_to_tile_through(self):
        for kind_id in enemy_recipe.kind_ids():
            doc = read(kind_id)
            for index, prim in enumerate(primitives(doc)):
                with self.subTest(kind=kind_id, primitive=index):
                    self.assertIn("TEXCOORD_0", prim["attributes"])

    def test_no_body_embeds_an_image(self):
        """The palette's generated set is eight 1024-square PNGs and `world_view.gd`
        resolves them by material name, so embedding them three times would put
        megabytes of duplicated pixels in a public repository."""
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                self.assertEqual(read(kind_id).get("images", []), [])

    def test_not_too_detailed_is_a_number(self):
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                doc = read(kind_id)
                triangles = sum(
                    doc["accessors"][prim["indices"]]["count"] // 3
                    for prim in primitives(doc))
                self.assertLessEqual(triangles, TRIANGLE_BUDGET)


class EverySurfaceIsAPaletteEntry(unittest.TestCase):
    """`WorldView._skinned_mesh` resolves `assets/machines/materials/<name>.tres` by
    the surface's own name, so a material the palette does not declare is a part
    drawn in flat white — and nothing would say so."""

    def test_every_material_names_a_palette_entry(self):
        declared = {entry["name"] for entry in PALETTE}
        for kind_id in enemy_recipe.kind_ids():
            doc = read(kind_id)
            for material in doc.get("materials", []):
                with self.subTest(kind=kind_id, material=material["name"]):
                    self.assertIn(material["name"], declared)

    def test_a_material_name_never_drifts_with_a_suffix(self):
        """Blender renames a second material called `CastIron` to `CastIron.001`,
        and the first run of the generator did exactly that by rebuilding the
        palette per kind. The surface name is what resolves the `.tres`, so the
        suffix would have been a silently unpainted Breaker."""
        for kind_id in enemy_recipe.kind_ids():
            for material in read(kind_id).get("materials", []):
                with self.subTest(kind=kind_id, material=material["name"]):
                    self.assertNotRegex(material["name"], r"\.\d{3}$")

    def test_every_material_a_recipe_assigns_reaches_the_file(self):
        for insect in enemy_recipe.KINDS:
            wanted = set(insect.materials.values())
            got = {m["name"] for m in read(insect.kind_id).get("materials", [])}
            with self.subTest(kind=insect.kind_id):
                self.assertEqual(got, wanted)


class TheClipsAreTheOnesTheGameAsksFor(unittest.TestCase):
    """The casting table is GDScript and this suite is Python, so the cross-check is
    a read of the one and a read of the other — the arrangement
    `machine_specs.footprint_authorities` has against `sim/map_layout.gd`, and for
    the same reason: the dependency runs one way and `game/` has never heard of the
    asset pipeline."""

    def _clips_the_game_asks_for(self) -> dict[str, set[str]]:
        text = ENEMY_BODIES.read_text()
        wanted: dict[str, set[str]] = {}
        for kind_id in enemy_recipe.kind_ids():
            start = text.find(f'INSECTS + "{kind_id}.glb"')
            self.assertNotEqual(start, -1,
                                f"EnemyBodies.recipe_for does not name {kind_id}")
            block = text[start:text.index("}", start)]
            wanted[kind_id] = set(re.findall(r':\s*"([a-z_]+)"', block))
        return wanted

    def test_every_body_carries_every_clip_the_declaration_names(self):
        declared = {clip.name for clip in enemy_recipe.CLIPS}
        for kind_id in enemy_recipe.kind_ids():
            with self.subTest(kind=kind_id):
                got = {a["name"] for a in read(kind_id).get("animations", [])}
                self.assertEqual(got, declared)

    def test_every_clip_a_kind_is_cast_with_is_in_that_kinds_file(self):
        for kind_id, clips in self._clips_the_game_asks_for().items():
            got = {a["name"] for a in read(kind_id).get("animations", [])}
            with self.subTest(kind=kind_id):
                self.assertTrue(clips, "the casting names at least one clip")
                self.assertTrue(clips <= got, f"{clips - got} resolve to nothing")

    def test_no_declared_clip_is_read_by_nobody(self):
        """A clip in every file that no kind is cast with is the asset-pipeline
        version of a tuning key nothing reads. `walk` and `run` both earn their place
        because the Crawler runs and the other two march (#34)."""
        asked = set()
        for clips in self._clips_the_game_asks_for().values():
            asked |= clips
        declared = {clip.name for clip in enemy_recipe.CLIPS}
        self.assertEqual(declared - asked, set(),
                         "these clips are generated and cast onto nothing")

    def test_a_cycle_closes_on_itself(self):
        """The bake samples `[0, length)` and wraps, so a clip whose last frame is
        not its first reads as a hitch once a cycle. Checked on the declaration,
        which is where the cycle is written."""
        for insect in enemy_recipe.KINDS:
            for clip in enemy_recipe.CLIPS:
                with self.subTest(kind=insect.kind_id, clip=clip.name):
                    first = enemy_recipe.pose_at(insect, clip.name, 0.0)
                    last = enemy_recipe.pose_at(insect, clip.name, 1.0)
                    self.assertEqual(sorted(first), sorted(last))
                    for bone, angles in first.items():
                        for axis in range(3):
                            self.assertAlmostEqual(angles[axis], last[bone][axis],
                                                   places=6)


class TheWeakPointIsInTheMesh(unittest.TestCase):
    """#16's vent is the only place in this project where geometry carries a rule, so
    the one thing it must not be is a pair of numbers in the renderer that the body
    can drift away from."""

    def test_the_boss_names_its_weak_point_and_the_others_do_not(self):
        for insect in enemy_recipe.KINDS:
            with self.subTest(kind=insect.kind_id):
                marker = node_named(read(insect.kind_id), "Vent")
                if insect.has_vent:
                    self.assertIsNotNone(marker, "a declared vent is exported")
                else:
                    self.assertIsNone(marker, "no kind else claims one")

    def test_the_weak_point_is_behind_the_body_rather_than_on_its_front(self):
        """`_armoured` shrugs off a hit from the front and nothing from the back, and
        nothing tells a player that in words — so a vent at +Z would be a glowing
        invitation to shoot the armour."""
        for insect in enemy_recipe.KINDS:
            if not insect.has_vent:
                continue
            marker = node_named(read(insect.kind_id), "Vent")
            with self.subTest(kind=insect.kind_id):
                self.assertLess(marker["translation"][2], 0.0)
                self.assertGreater(marker["translation"][1], 0.0,
                                   "and off the ground")


class RegeneratingFromTheDeclaration(unittest.TestCase):
    """The claim the ticket actually makes: changing a proportion and re-running is
    the whole workflow, with no manual step in between."""

    def test_reproduces_the_committed_bodies_byte_for_byte(self):
        """Determinism in the art pipeline too. If regeneration churns bytes, every
        re-run is a meaningless diff and nobody will re-run it."""
        with tempfile.TemporaryDirectory() as work:
            subprocess.run(
                ["bash", str(GENERATOR), "--output-dir", work],
                check=True, cwd=REPO, capture_output=True, text=True, timeout=900)
            for kind_id in enemy_recipe.kind_ids():
                with self.subTest(kind=kind_id):
                    fresh = Path(work) / f"{kind_id}.glb"
                    self.assertTrue(fresh.exists(), "the generator produced no file")
                    self.assertEqual(fresh.read_bytes(), glb_for(kind_id).read_bytes(),
                                     "regenerating changed the committed body")

    def test_follows_a_changed_proportion_without_a_manual_step(self):
        """The parameter-change criterion, done the way a developer would do it:
        edit the declaration, re-run, and the body is the new shape. The Crawler's
        foot spread is what sets its width, so this is a test of the whole chain —
        declaration, assembly, normalisation, export — rather than of one vertex.

        **The `__pycache__` removal is load-bearing and was found by this test
        passing while being wrong.** Blender imports `enemy_recipe` as an ordinary
        module, and CPython reuses a cached `.pyc` when the source's mtime *second*
        and byte count both match — which `0.66` for `0.96` satisfies exactly. So
        the first version of this edited the file, regenerated, and measured the
        body the *old* declaration describes, reporting no change and calling it a
        failure of the generator."""
        with tempfile.TemporaryDirectory() as work:
            recipe = REPO / "tools" / "assets" / "enemy_recipe.py"
            cache = REPO / "tools" / "assets" / "__pycache__"
            original = recipe.read_text()
            # **Unique, and asserted to be.** The first version edited `foot_out=0.66`,
            # which was the Crawler's when it was written and is the Siege Hulk's now —
            # so it regenerated the Crawler, measured no change and reported the generator
            # broken. A substitution that silently moves to another kind is #63's lesson
            # about `String.replace` in a fixture, in Python.
            target = "            foot_out=0.50,"
            self.assertEqual(original.count(target), 1,
                             f"{target!r} no longer names the Crawler alone")
            widened = original.replace(target, "            foot_out=0.95,", 1)
            try:
                recipe.write_text(widened)
                shutil.rmtree(cache, ignore_errors=True)
                subprocess.run(
                    ["bash", str(GENERATOR), "--output-dir", work, "--only", "crawler"],
                    check=True, cwd=REPO, capture_output=True, text=True, timeout=300)
            finally:
                recipe.write_text(original)
                shutil.rmtree(cache, ignore_errors=True)
            low, high = gltf_info.position_extents(
                gltf_info.read_gltf_json(Path(work) / "crawler.glb"))
            was_low, was_high = gltf_info.position_extents(read("crawler"))
            self.assertGreater(high[0] - low[0], was_high[0] - was_low[0],
                               "a wider knee makes a wider Crawler")
            # And it is still normalised, which is what proves the generator
            # re-measured rather than scaling by whatever it had last time.
            self.assertAlmostEqual(high[1], 1.0, delta=HEIGHT_TOLERANCE)


if __name__ == "__main__":
    unittest.main()
