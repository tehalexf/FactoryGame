"""What the committed Machine meshes must be true of, checked against the
declaration they were generated from.

Seam: the committed `.glb` files under `assets/machines/`, read with the
standard-library glTF reader. Nothing here imports Blender or calls into the
generator's internals — these tests ask only whether the artifact on disk agrees
with `content/machines.csv` and `content/machine_ports.csv`.

That is the whole point of the ticket: a footprint or a port position that drifts
away from what the Simulation believes is caught here rather than discovered by a
player watching a Belt feed thin air.
"""

import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_info  # noqa: E402
import machine_specs  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
MACHINE_DIR = REPO / "assets" / "machines"
PALETTE = json.loads((REPO / "tools" / "assets" / "dieselpunk_palette.json").read_text())

#: A port position read back out of a glTF is a 32-bit float that went through a
#: metres conversion, so it is compared to the declaration within a tenth of a
#: millimetre rather than exactly. A real disagreement is a whole metre out.
TOLERANCE_MM = 0.1


def glb_for(machine: machine_specs.Machine) -> Path:
    return MACHINE_DIR / f"{machine.machine_id}.glb"


def node_translation_mm(doc: dict, name: str) -> tuple[float, float, float]:
    """Where a named node sits, in millimetres, accumulated down from the scene
    root so a parented marker is reported in the Machine's own space."""
    nodes = doc.get("nodes", [])
    parent_of: dict[int, int] = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            parent_of[child] = index
    index = next((i for i, n in enumerate(nodes) if n.get("name") == name), None)
    if index is None:
        raise KeyError(f"no node named {name!r}; have {[n.get('name') for n in nodes]}")
    total = [0.0, 0.0, 0.0]
    while index is not None:
        translation = nodes[index].get("translation", [0, 0, 0])
        for axis in range(3):
            total[axis] += translation[axis]
        index = parent_of.get(index)
    return (total[0] * 1000.0, total[1] * 1000.0, total[2] * 1000.0)


class EveryDeclaredMachine(unittest.TestCase):
    def setUp(self) -> None:
        self.machines = machine_specs.load()

    def test_has_a_generated_mesh_and_no_mesh_has_no_machine(self):
        """The set of meshes and the set of declared Machines are the same set.
        A stray .glb is a Machine someone deleted; a missing one is a Machine
        someone added without re-running the generator."""
        declared = {m.machine_id for m in self.machines}
        generated = {p.stem for p in MACHINE_DIR.glob("*.glb")}
        self.assertEqual(generated, declared)

    def test_is_gltf_2(self):
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                self.assertEqual(doc["asset"]["version"], "2.0")

    def test_occupies_exactly_its_declared_footprint(self):
        """The acceptance criterion with the shortest path to a broken game: a
        Machine whose mesh is wider than its tiles overlaps its neighbour, and a
        narrower one leaves a visible gap in the Factory."""
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                low, high = gltf_info.position_extents(doc)
                width_mm, depth_mm = machine.footprint_mm()
                self.assertAlmostEqual((high[0] - low[0]) * 1000.0, width_mm,
                                      delta=TOLERANCE_MM,
                                      msg=f"X extent is not {width_mm} mm")
                self.assertAlmostEqual((high[2] - low[2]) * 1000.0, depth_mm,
                                      delta=TOLERANCE_MM,
                                      msg=f"Z extent is not {depth_mm} mm")

    def test_is_centred_on_its_footprint_and_stands_on_the_ground(self):
        """The origin convention every other number here depends on: the centre
        of the footprint, at ground level, so a Machine placed at a tile centre
        is placed correctly."""
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                low, high = gltf_info.position_extents(doc)
                half_x, half_z = machine.half_extent_mm()
                self.assertAlmostEqual(low[0] * 1000.0, -half_x, delta=TOLERANCE_MM)
                self.assertAlmostEqual(high[0] * 1000.0, half_x, delta=TOLERANCE_MM)
                self.assertAlmostEqual(low[2] * 1000.0, -half_z, delta=TOLERANCE_MM)
                self.assertAlmostEqual(high[2] * 1000.0, half_z, delta=TOLERANCE_MM)
                self.assertAlmostEqual(low[1] * 1000.0, 0.0, delta=TOLERANCE_MM,
                                       msg="the base is not at y=0")

    def test_reads_at_human_scale(self):
        """The player is 1.8 m. A Machine shorter than knee height or taller than
        a four-storey building has lost its scale reference, which is the one
        mistake procedural geometry makes silently."""
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                low, high = gltf_info.position_extents(doc)
                height_m = high[1] - low[1]
                self.assertGreater(height_m, 0.4)
                self.assertLess(height_m, 16.0)

    def test_carries_a_marker_node_at_every_declared_port_position(self):
        """The criterion most likely to drift silently. Both sides of this
        comparison come from `content/machine_ports.csv`: the declaration, and
        the mesh that was generated from it."""
        checked = 0
        for machine in self.machines:
            doc = gltf_info.read_gltf_json(glb_for(machine))
            for port in machine.ports:
                name = machine_specs.port_node_name(port)
                with self.subTest(port=f"{machine.machine_id}.{port.port_id}"):
                    actual = node_translation_mm(doc, name)
                    expected = machine_specs.port_position_mm(machine, port)
                    for axis, label in enumerate("xyz"):
                        self.assertAlmostEqual(
                            actual[axis], expected[axis], delta=TOLERANCE_MM,
                            msg=f"{name}: {label} is {actual[axis]} mm, "
                                f"declared {expected[axis]} mm")
                    checked += 1
        self.assertGreater(checked, 0, "no ports were checked")

    def test_carries_no_marker_node_that_is_not_a_declared_port(self):
        """A leftover marker is a Belt connection the Simulation does not know
        about, which is the same bug in the other direction."""
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                found = sorted(n.get("name", "") for n in doc.get("nodes", [])
                               if n.get("name", "").startswith(machine_specs.PORT_NODE_PREFIX))
                expected = sorted(machine_specs.port_node_name(p) for p in machine.ports)
                self.assertEqual(found, expected)

    def test_keeps_its_port_markers_free_of_geometry(self):
        """A port marker must be a bare node, not a mesh: it is a connection
        point the engine reads, and geometry on it would show up in the model."""
        for machine in self.machines:
            doc = gltf_info.read_gltf_json(glb_for(machine))
            for node in doc.get("nodes", []):
                if node.get("name", "").startswith(machine_specs.PORT_NODE_PREFIX):
                    with self.subTest(node=node["name"]):
                        self.assertNotIn("mesh", node)


class TheSharedPalette(unittest.TestCase):
    """One palette across every Machine, which is the thing hand-modelling
    cannot hold. Checked by name *and* by value, because two materials called
    CastIron with different base colours are worse than two different names."""

    def setUp(self) -> None:
        self.machines = machine_specs.load()
        self.declared = {m["name"]: m for m in PALETTE["materials"]}

    def test_names_only_materials_the_palette_declares(self):
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                used = set(gltf_info.material_names(gltf_info.read_gltf_json(glb_for(machine))))
                self.assertTrue(used, "no materials at all")
                self.assertEqual(used - set(self.declared), set())

    def test_gives_each_material_the_palettes_own_numbers(self):
        for machine in self.machines:
            doc = gltf_info.read_gltf_json(glb_for(machine))
            for material in doc.get("materials", []):
                declared = self.declared[material["name"]]
                pbr = material.get("pbrMetallicRoughness", {})
                with self.subTest(machine=machine.machine_id, material=material["name"]):
                    for axis, value in enumerate(declared["base_color"]):
                        self.assertAlmostEqual(
                            pbr.get("baseColorFactor", [1, 1, 1, 1])[axis], value, places=4)
                    self.assertAlmostEqual(pbr.get("metallicFactor", 1.0),
                                           declared["metallic"], places=4)
                    self.assertAlmostEqual(pbr.get("roughnessFactor", 1.0),
                                           declared["roughness"], places=4)

    def test_is_actually_shared_rather_than_coincidental(self):
        """Every material that appears in more than one Machine must be
        byte-identical between them."""
        seen: dict[str, dict] = {}
        for machine in self.machines:
            doc = gltf_info.read_gltf_json(glb_for(machine))
            for material in doc.get("materials", []):
                name = material["name"]
                body = material.get("pbrMetallicRoughness", {})
                if name in seen:
                    self.assertEqual(body, seen[name],
                                     f"{name} differs between Machines")
                seen[name] = body

    def test_is_drawn_on_often_enough_to_be_a_palette(self):
        """If every Machine used one material the palette would be decoration.
        Several materials per Machine is what makes the silhouettes legible."""
        for machine in self.machines:
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                self.assertGreaterEqual(len(gltf_info.material_names(doc)), 3)


class TheGeneratedAsset(unittest.TestCase):
    def test_embeds_no_textures(self):
        """These are flat-shaded procedural meshes; texturing is a later ticket.
        An embedded image here means something was imported by accident."""
        for machine in machine_specs.load():
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                self.assertEqual(gltf_info.image_count(doc), 0)

    def test_carries_no_skeleton(self):
        """Machines are static. A skin here is a sign the shared humanoid rig
        leaked in from the character pipeline."""
        for machine in machine_specs.load():
            with self.subTest(machine=machine.machine_id):
                doc = gltf_info.read_gltf_json(glb_for(machine))
                self.assertEqual(gltf_info.skeleton_roots(doc), [])

    def test_is_small_enough_to_belong_in_a_git_repository(self):
        for machine in machine_specs.load():
            with self.subTest(machine=machine.machine_id):
                size_kb = glb_for(machine).stat().st_size / 1024
                self.assertLess(size_kb, 512, f"{size_kb:.0f} KB is too large")


@unittest.skipIf(shutil.which("godot") is None, "godot is not on PATH")
class GodotsOwnImporter(unittest.TestCase):
    def test_accepts_every_machine_with_its_footprint_and_ports_intact(self):
        """The acceptance criterion "loads in-engine without manual fixing", asked
        of the engine rather than of the file.

        Everything above reads the glTF bytes directly. This lets Godot's importer
        have its say: an importer that rescaled or reoriented a mesh would pass
        every byte-level check here and still put the Belt in the wrong place.
        """
        result = subprocess.run(
            ["bash", str(REPO / "tools" / "assets" / "verify_machines_in_godot.sh")],
            cwd=REPO, capture_output=True, text=True, timeout=600)
        self.assertEqual(result.returncode, 0,
                         f"{result.stdout[-4000:]}\n{result.stderr[-2000:]}")
        self.assertIn("0 failure(s)", result.stdout)


@unittest.skipIf(shutil.which("blender") is None, "blender is not on PATH")
class RegeneratingFromTheDeclaration(unittest.TestCase):
    """The claim the ticket actually makes: changing a parameter and re-running
    is the whole workflow, with no manual step in between."""

    def test_reproduces_the_committed_meshes_byte_for_byte(self):
        """Determinism in the art pipeline too. If regeneration churns bytes,
        every re-run is a meaningless diff and nobody will re-run it."""
        import tempfile
        with tempfile.TemporaryDirectory() as work:
            subprocess.run(
                ["bash", str(REPO / "tools" / "assets" / "generate_machines.sh"),
                 "--output-dir", work],
                check=True, cwd=REPO, capture_output=True, text=True, timeout=900)
            for machine in machine_specs.load():
                with self.subTest(machine=machine.machine_id):
                    fresh = Path(work) / f"{machine.machine_id}.glb"
                    self.assertTrue(fresh.exists(), "generator produced no file")
                    self.assertEqual(fresh.read_bytes(), glb_for(machine).read_bytes(),
                                     "regenerating changed the committed mesh")

    def test_follows_a_changed_footprint_without_a_manual_step(self):
        """Edit the footprint in the declaration, re-run, and the mesh is the new
        size. This is the parameter-change criterion, done the way a developer
        would do it rather than by calling a function."""
        import tempfile
        with tempfile.TemporaryDirectory() as work:
            # press_mk1 is a body whose footprint content/machines.csv does not
            # declare yet, so the body table is its authority and editing it is
            # the whole change. (A Machine the Simulation *has* declared is
            # widened there instead; machines.csv always wins.)
            table = (REPO / "content" / "machine_bodies.csv").read_text()
            widened = table.replace("press_mk1,press,2,3,", "press_mk1,press,4,3,")
            self.assertNotEqual(widened, table, "the test's edit matched nothing")
            bodies_csv = Path(work) / "machine_bodies.csv"
            bodies_csv.write_text(widened)
            subprocess.run(
                ["bash", str(REPO / "tools" / "assets" / "generate_machines.sh"),
                 "--output-dir", work,
                 "--bodies-csv", str(bodies_csv),
                 "--only", "press_mk1"],
                check=True, cwd=REPO, capture_output=True, text=True, timeout=300)
            doc = gltf_info.read_gltf_json(Path(work) / "press_mk1.glb")
            low, high = gltf_info.position_extents(doc)
            self.assertAlmostEqual((high[0] - low[0]) * 1000.0, 8000, delta=TOLERANCE_MM)
            self.assertAlmostEqual((high[2] - low[2]) * 1000.0, 6000, delta=TOLERANCE_MM)
            # And the ports moved with it: the north edge is now 4 tiles long, so
            # tile 0's centre is at -4000 + 0.5 * 2000 = -3000 mm.
            self.assertAlmostEqual(
                node_translation_mm(doc, "Port_input_ingot")[0], -3000, delta=TOLERANCE_MM)


if __name__ == "__main__":
    unittest.main()
