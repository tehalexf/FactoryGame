"""The Machine declaration: which bodies exist, how big they are, where their
ports sit, and which file wins when two of them describe the same footprint.

Seam: `machine_specs`' public functions, which are the asset pipeline's only
reader of the content tables. Nothing here reaches into the Blender generator;
these tests are about the declaration both the Simulation and the generator read.

Expected positions are worked by hand from the grid rules in docs/DESIGN.md
(2 m tiles, origin at the footprint centre on the ground), never by re-running
the formula under test.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import machine_specs  # noqa: E402

REPO = Path(__file__).resolve().parents[3]


class TheMachineTable(unittest.TestCase):
    def test_declares_every_milestone_1_machine(self):
        """DESIGN.md's Milestone 1 list, plus the Nest and a Belt segment.

        `coal_miner_mk1` is here because a Steam Boiler burns coal and nothing
        else mines any: #7 added it to `content/machines.csv` and it drew as a
        placeholder box until it got a body.
        """
        expected = {
            "miner_mk1", "coal_miner_mk1", "smelter_mk1", "press_mk1",
            "assembler_mk1", "steam_boiler_mk1", "generator_mk1",
            "ammo_press_mk1", "silo_mk1", "nest", "belt_straight",
        }
        self.assertEqual({m.machine_id for m in machine_specs.load()}, expected)

    def test_is_ordered_by_id_regardless_of_file_order(self):
        ids = [m.machine_id for m in machine_specs.load()]
        self.assertEqual(ids, sorted(ids))

    def test_reads_footprints_in_tiles(self):
        miner = machine_specs.by_id(machine_specs.load(), "miner_mk1")
        self.assertEqual((miner.footprint_x, miner.footprint_z), (2, 2))
        silo = machine_specs.by_id(machine_specs.load(), "silo_mk1")
        self.assertEqual((silo.footprint_x, silo.footprint_z), (4, 4))

    def test_converts_a_footprint_to_metres_on_the_2_m_grid(self):
        """A 3x3 Machine is 6 m x 6 m. The tile size is not the generator's to
        choose: it is the grid rule, and it lives in one constant."""
        self.assertEqual(machine_specs.TILE_SIZE_MM, 2000)
        smelter = machine_specs.by_id(machine_specs.load(), "smelter_mk1")
        self.assertEqual(smelter.footprint_mm(), (6000, 6000))

    def test_keeps_every_machine_inside_the_grid_rules(self):
        """Machines are 2x2 to 4x4 tiles; a Belt is 1 tile wide."""
        for machine in machine_specs.load():
            with self.subTest(machine=machine.machine_id):
                self.assertGreaterEqual(machine.footprint_x, 1)
                self.assertGreaterEqual(machine.footprint_z, 1)
                self.assertLessEqual(machine.footprint_x, 4)
                self.assertLessEqual(machine.footprint_z, 4)
                if machine.body != "belt":
                    self.assertGreaterEqual(min(machine.footprint_x, machine.footprint_z), 2)


class APortPosition(unittest.TestCase):
    """Worked by hand from the grid rules, so the formula has something to
    disagree with."""

    def test_sits_at_the_centre_of_its_edge_tile_on_the_footprint_boundary(self):
        # miner_mk1 is 2x2, so 4 m x 4 m: X and Z both span -2000..+2000 mm.
        # Its `ore` output is on the south edge (+Z), tile 1 of 0..1, so the
        # second 2 m tile along X: centre at -2000 + 1.5 * 2000 = +1000 mm.
        miner = machine_specs.by_id(machine_specs.load(), "miner_mk1")
        ore = machine_specs.port_by_id(miner, "ore")
        self.assertEqual(machine_specs.port_position_mm(miner, ore), (1000, 900, 2000))

    def test_runs_along_z_on_the_east_and_west_edges(self):
        # smelter_mk1 is 3x3, so 6 m x 6 m: X and Z span -3000..+3000 mm.
        # `coal` is on the west edge (-X), tile 1 of 0..2 — the middle tile, so
        # Z is dead centre at 0.
        smelter = machine_specs.by_id(machine_specs.load(), "smelter_mk1")
        coal = machine_specs.port_by_id(smelter, "coal")
        self.assertEqual(machine_specs.port_position_mm(smelter, coal), (-3000, 900, 0))

    def test_takes_its_height_from_the_declaration_not_from_a_default(self):
        # The Steam Boiler's steam outlet is deliberately high, at 1800 mm.
        boiler = machine_specs.by_id(machine_specs.load(), "steam_boiler_mk1")
        steam = machine_specs.port_by_id(boiler, "steam")
        self.assertEqual(machine_specs.port_position_mm(boiler, steam)[1], 1800)

    def test_lands_on_a_whole_metre_for_every_declared_port(self):
        """A port is the centre of a 2 m tile on an edge, so every coordinate is
        a whole number of metres. A fractional one means the grid slipped."""
        for machine in machine_specs.load():
            for port in machine.ports:
                with self.subTest(port=f"{machine.machine_id}.{port.port_id}"):
                    x, _y, z = machine_specs.port_position_mm(machine, port)
                    self.assertEqual(x % 1000, 0)
                    self.assertEqual(z % 1000, 0)


class TheDeclarationItself(unittest.TestCase):
    def test_gives_every_machine_at_least_one_port(self):
        for machine in machine_specs.load():
            with self.subTest(machine=machine.machine_id):
                self.assertTrue(machine.ports, "no ports declared")

    def test_rejects_a_port_whose_tile_falls_off_its_edge(self):
        source = "machine_id,port_id,direction,edge,tile,height_mm\nminer_mk1,ore,output,south,2,900\n"
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(ports_source=source)
        self.assertIn("tile", str(caught.exception))
        self.assertIn("machine_ports.csv", str(caught.exception))

    def test_rejects_two_ports_sharing_a_tile(self):
        source = ("machine_id,port_id,direction,edge,tile,height_mm\n"
                  "miner_mk1,ore,output,south,0,900\n"
                  "miner_mk1,slag,output,south,0,900\n")
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(ports_source=source)
        self.assertIn("south", str(caught.exception))

    def test_rejects_a_port_on_an_unknown_machine(self):
        source = "machine_id,port_id,direction,edge,tile,height_mm\nconveyor_mk9,in,input,north,0,900\n"
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(ports_source=source)
        self.assertIn("conveyor_mk9", str(caught.exception))

    def test_rejects_an_unknown_direction(self):
        source = "machine_id,port_id,direction,edge,tile,height_mm\nminer_mk1,ore,sideways,south,0,900\n"
        with self.assertRaises(machine_specs.DeclarationError):
            machine_specs.load(ports_source=source)

    def test_rejects_an_unknown_edge(self):
        source = "machine_id,port_id,direction,edge,tile,height_mm\nminer_mk1,ore,output,up,0,900\n"
        with self.assertRaises(machine_specs.DeclarationError):
            machine_specs.load(ports_source=source)

    def test_names_the_file_and_line_when_a_number_will_not_parse(self):
        source = "machine_id,port_id,direction,edge,tile,height_mm\nminer_mk1,ore,output,south,middle,900\n"
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(ports_source=source)
        self.assertIn("line 2", str(caught.exception))

    def test_hides_the_content_tables_from_godots_importer(self):
        """Godot claims .csv as translation tables unless a .gdignore says no."""
        self.assertTrue((REPO / "content" / ".gdignore").exists())


class WhenTheSimulationAlsoDeclaresAFootprint(unittest.TestCase):
    """`content/machines.csv` is the Simulation's own Machine table and the
    authority on footprints. These are the tests that make "the mesh agrees with
    what the Simulation believes" a mechanical fact rather than a good intention.

    The table is written here as a literal rather than read from the repository,
    so these keep testing the rule even before the gameplay tickets have landed
    their rows — and `TheShippedTables` below checks the real files.
    """

    HEADER = ("id,display_name,role,footprint_x,footprint_z,"
              "power_draw_kw,health,max_depth,recipe_id\n")
    BODIES = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
              "miner_mk1,miner,2,2,2100\n"
              "nest,nest,4,4,2800\n")
    PORTS = ("machine_id,port_id,direction,edge,tile,height_mm\n"
             "miner_mk1,ore,output,south,1,900\n"
             "nest,delivery,input,south,1,900\n")

    def simulation_says(self, rows: str) -> str:
        return self.HEADER + rows

    def load(self, machines_rows: str, bodies: str | None = None):
        return machine_specs.load(bodies_source=bodies or self.BODIES,
                                  ports_source=self.PORTS,
                                  machines_source=self.simulation_says(machines_rows))

    def test_the_simulations_footprint_wins_over_the_body_tables(self):
        """A disagreement is an error, not a silent override, so nobody gets to
        find out later which file the generator happened to prefer."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load("miner_mk1,Miner Mk1,miner,3,3,120,400,1,mine_iron_ore\n")
        message = str(caught.exception)
        self.assertIn("machines.csv", message)
        self.assertIn("machine_bodies.csv", message)
        self.assertIn("miner_mk1", message)
        self.assertIn("3x3", message)
        self.assertIn("2x2", message)

    def test_an_agreeing_footprint_is_marked_as_checked(self):
        machines = self.load("miner_mk1,Miner Mk1,miner,2,2,120,400,1,mine_iron_ore\n")
        miner = machine_specs.by_id(machines, "miner_mk1")
        self.assertTrue(miner.footprint_from_simulation)
        self.assertEqual((miner.footprint_x, miner.footprint_z), (2, 2))
        # And a body the Simulation says nothing about is not falsely marked.
        self.assertFalse(machine_specs.by_id(machines, "nest").footprint_from_simulation)

    def test_a_blank_footprint_defers_to_the_simulation(self):
        """The end state for every row: the body table stops restating the
        footprint and the duplicate disappears."""
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "miner_mk1,miner,,,2100\n")
        ports = ("machine_id,port_id,direction,edge,tile,height_mm\n"
                 "miner_mk1,ore,output,south,2,900\n")
        machines = machine_specs.load(
            bodies_source=bodies, ports_source=ports,
            machines_source=self.simulation_says(
                "miner_mk1,Miner Mk1,miner,4,3,120,400,1,mine_iron_ore\n"))
        miner = machine_specs.by_id(machines, "miner_mk1")
        self.assertEqual((miner.footprint_x, miner.footprint_z), (4, 3))
        # The port validated against the *Simulation's* footprint: tile 2 only
        # exists on a south edge four tiles long.
        self.assertEqual(machine_specs.port_by_id(miner, "ore").tile, 2)

    def test_a_blank_footprint_with_nothing_to_defer_to_is_an_error(self):
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "nest,nest,,,2800\n")
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(bodies_source=bodies,
                               machines_source=self.HEADER)
        self.assertIn("nest", str(caught.exception))
        self.assertIn("machines.csv", str(caught.exception))


class TheShippedTables(unittest.TestCase):
    def test_at_least_one_footprint_is_the_simulations_own(self):
        """The mechanism is live, not merely available. If this ever reads zero,
        the mesh pipeline has stopped being checked against the Simulation at
        all and every other agreement test below is passing vacuously."""
        checked = [m for m in machine_specs.load() if m.footprint_from_simulation]
        self.assertTrue(checked,
                        "no generated Machine's footprint comes from content/machines.csv")

    def test_agree_with_the_simulations_machine_table_as_far_as_it_goes(self):
        """Loading the real files is the check. It tightens by itself as gameplay
        tickets add rows — which is the point: nobody has to remember to come
        back and connect the two."""
        declared = machine_specs.simulation_footprints()
        machines = machine_specs.load()
        checked = [m for m in machines if m.footprint_from_simulation]
        self.assertEqual({m.machine_id for m in checked},
                         {i for i in declared if i in {m.machine_id for m in machines}})
        for machine in checked:
            with self.subTest(machine=machine.machine_id):
                self.assertEqual((machine.footprint_x, machine.footprint_z),
                                 declared[machine.machine_id])

    def test_give_a_belt_segment_a_deck_at_its_own_port_height(self):
        """A Belt's deck height and its port height are the same fact in two
        tables, and a Belt whose deck is not where its ports are would hand goods
        to thin air."""
        belt = machine_specs.by_id(machine_specs.load(), "belt_straight")
        for port in belt.ports:
            with self.subTest(port=port.port_id):
                self.assertEqual(port.height_mm, belt.body_height_mm)


if __name__ == "__main__":
    unittest.main()
