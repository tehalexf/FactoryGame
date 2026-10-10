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


def _tuned_millimetres(tuning: str, section: str, key: str) -> int:
    """One `key = <decimal>` out of one `[section]` of `content/tuning.toml`, in
    millimetres.

    Hand-read rather than parsed with `tomllib`, deliberately: the file is only
    a documented subset of TOML (`sim/toml_document.gd` says which), and this
    needs one number out of it rather than a document. Same digit-by-digit
    conversion `machine_specs` uses, for the same reason — a height is compared
    for equality.
    """
    here = None
    for line in tuning.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            here = stripped[1:-1]
        elif here == section and stripped.startswith(key + " ="):
            written = stripped.split("=", 1)[1].strip()
            return machine_specs._require_millimetres(
                {"value": written, "__line__": "0"}, "value", "content/tuning.toml")
    raise AssertionError(f"content/tuning.toml has no [{section}] {key}")


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
        # Its `ore_s1` output is on the south edge (+Z), tile 1 of 0..1, so the
        # second 2 m tile along X: centre at -2000 + 1.5 * 2000 = +1000 mm.
        # The port id carries the face and the tile since #47, because a face is
        # declared tile by tile and two rows cannot share a name.
        miner = machine_specs.by_id(machine_specs.load(), "miner_mk1")
        ore = machine_specs.port_by_id(miner, "ore_s1")
        self.assertEqual(machine_specs.port_position_mm(miner, ore), (1000, 900, 2000))

    def test_runs_along_z_on_the_east_and_west_edges(self):
        # smelter_mk1 is 3x3, so 6 m x 6 m: X and Z span -3000..+3000 mm.
        # `coal_w1` is on the west edge (-X), tile 1 of 0..2 — the middle tile, so
        # Z is dead centre at 0.
        smelter = machine_specs.by_id(machine_specs.load(), "smelter_mk1")
        coal = machine_specs.port_by_id(smelter, "coal_w1")
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
    authority on footprints and on housing heights. These are the tests that make
    "the mesh agrees with what the Simulation believes" a mechanical fact rather
    than a good intention.

    The table is written here as a literal rather than read from the repository,
    so these keep testing the rule even before the gameplay tickets have landed
    their rows — and `TheShippedTables` below checks the real files.
    """

    HEADER = ("id,display_name,role,footprint_x,footprint_z,height_metres,"
              "power_draw_kw,health,max_depth,recipe_id\n")
    BODIES = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
              "miner_mk1,miner,2,2,2100\n"
              "nest,nest,4,4,2800\n")
    PORTS = ("machine_id,port_id,direction,edge,tile,height_mm\n"
             "miner_mk1,ore,output,south,1,900\n"
             "nest,delivery,input,south,1,900\n")
    #: The geography half of the Simulation, also a literal. Written the way
    #: `sim/map_layout.gd` writes it, so a test that wants the Nest's footprint
    #: to disagree can say so by changing one number here.
    MAP_LAYOUT = "const NEST_FOOTPRINT_TILES: int = 4\n"

    def simulation_says(self, rows: str) -> str:
        return self.HEADER + rows

    def load(self, machines_rows: str, bodies: str | None = None,
             map_layout: str | None = None):
        return machine_specs.load(
            bodies_source=bodies or self.BODIES,
            ports_source=self.PORTS,
            machines_source=self.simulation_says(machines_rows),
            map_layout_source=self.MAP_LAYOUT if map_layout is None else map_layout)

    def test_the_simulations_footprint_wins_over_the_body_tables(self):
        """A disagreement is an error, not a silent override, so nobody gets to
        find out later which file the generator happened to prefer."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load("miner_mk1,Miner Mk1,miner,3,3,2.1,120,400,1,mine_iron_ore\n")
        message = str(caught.exception)
        self.assertIn("machines.csv", message)
        self.assertIn("machine_bodies.csv", message)
        self.assertIn("miner_mk1", message)
        self.assertIn("3x3", message)
        self.assertIn("2x2", message)

    def test_an_agreeing_footprint_is_marked_as_checked(self):
        machines = self.load("miner_mk1,Miner Mk1,miner,2,2,2.1,120,400,1,mine_iron_ore\n")
        miner = machine_specs.by_id(machines, "miner_mk1")
        self.assertTrue(miner.footprint_from_simulation)
        self.assertEqual(miner.footprint_authority, "content/machines.csv")
        self.assertEqual((miner.footprint_x, miner.footprint_z), (2, 2))
        # And a body the Simulation says nothing about is not falsely marked.
        # Not the Nest: since #61 `sim/map_layout.gd` declares that one, so the
        # unchecked example has to be a body with no authority anywhere — which
        # is what `press_mk1` is until its Recipe arrives.
        bodies = self.BODIES + "press_mk1,press,2,3,2400\n"
        loose = machine_specs.by_id(self.load(
            "miner_mk1,Miner Mk1,miner,2,2,2.1,120,400,1,mine_iron_ore\n",
            bodies=bodies), "press_mk1")
        self.assertFalse(loose.footprint_from_simulation)
        self.assertEqual(loose.footprint_authority, "content/machine_bodies.csv")

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
                "miner_mk1,Miner Mk1,miner,4,3,2.1,120,400,1,mine_iron_ore\n"))
        miner = machine_specs.by_id(machines, "miner_mk1")
        self.assertEqual((miner.footprint_x, miner.footprint_z), (4, 3))
        # The port validated against the *Simulation's* footprint: tile 2 only
        # exists on a south edge four tiles long.
        self.assertEqual(machine_specs.port_by_id(miner, "ore").tile, 2)

    def test_a_blank_footprint_with_nothing_to_defer_to_is_an_error(self):
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "press_mk1,press,,,2400\n")
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(bodies_source=bodies,
                               machines_source=self.HEADER,
                               map_layout_source=self.MAP_LAYOUT)
        self.assertIn("press_mk1", str(caught.exception))
        self.assertIn("machines.csv", str(caught.exception))

    def test_the_simulations_height_wins_over_the_body_tables(self):
        """The same rule as the footprint, one column later, and it matters more:
        the Simulation stands a player on this number (#30), so a mesh and a roof
        that disagreed would be a surface you fall through."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load("miner_mk1,Miner Mk1,miner,2,2,1.8,120,400,1,mine_iron_ore\n")
        message = str(caught.exception)
        self.assertIn("machines.csv", message)
        self.assertIn("machine_bodies.csv", message)
        self.assertIn("miner_mk1", message)
        self.assertIn("1800", message)
        self.assertIn("2100", message)

    def test_a_blank_height_defers_to_the_simulation(self):
        """The end state for every row the Simulation declares: the body table
        stops restating the height and the duplicate disappears."""
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "miner_mk1,miner,,,\n")
        ports = ("machine_id,port_id,direction,edge,tile,height_mm\n"
                 "miner_mk1,ore,output,south,1,900\n")
        machines = machine_specs.load(
            bodies_source=bodies, ports_source=ports,
            machines_source=self.simulation_says(
                "miner_mk1,Miner Mk1,miner,2,2,1.8,120,400,1,mine_iron_ore\n"))
        self.assertEqual(
            machine_specs.by_id(machines, "miner_mk1").body_height_mm, 1800)

    def test_a_height_in_millimetres_is_exact_rather_than_rounded(self):
        """Metres are decimal in the file and millimetres everywhere here, and
        the conversion is digit by digit rather than through a float — a height
        is compared for equality, and a binary float is not the type to do that
        with."""
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "miner_mk1,miner,,,\n")
        ports = ("machine_id,port_id,direction,edge,tile,height_mm\n"
                 "miner_mk1,ore,output,south,1,900\n")
        for written, millimetres in (("2", 2000), ("2.4", 2400), ("10.425", 10425),
                                     ("0.9", 900), ("1.05", 1050)):
            machines = machine_specs.load(
                bodies_source=bodies, ports_source=ports,
                machines_source=self.simulation_says(
                    f"miner_mk1,Miner Mk1,miner,2,2,{written},120,400,1,mine_iron_ore\n"))
            self.assertEqual(
                machine_specs.by_id(machines, "miner_mk1").body_height_mm, millimetres,
                f"{written} m should be {millimetres} mm")

    def test_a_blank_height_with_nothing_to_defer_to_is_an_error(self):
        bodies = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "nest,nest,4,4,\n")
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(bodies_source=bodies,
                               machines_source=self.HEADER)
        self.assertIn("nest", str(caught.exception))
        self.assertIn("body_height_mm", str(caught.exception))
        self.assertIn("machines.csv", str(caught.exception))


class TheNestsFootprint(unittest.TestCase):
    """The one generated body whose footprint is geography rather than a Machine
    row, and the one that had two authorities and no cross-check until #61.

    The Nest has no row in `content/machines.csv` and never will — DESIGN.md
    lists it alongside Belt and Wall, outside the eight Machines — so the rule
    that checks a Machine's footprint could not reach it, and
    `content/machine_bodies.csv` was a second opinion on the 4x4 a player
    respawns on top of and every Belt in every scenario docks against.

    Every case here supplies **both** sides as literals, so the two numbers can
    be made to genuinely disagree. A cross-check whose only exercised case is one
    where it is trivially true is the shape of a test that passed for several
    tickets while the rule it claimed to cover was broken, and this project has
    already paid for one of those.
    """

    BODIES_4X4 = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                  "nest,nest,4,4,4200\n")
    BODIES_BLANK = ("machine_id,body,footprint_x,footprint_z,body_height_mm\n"
                    "nest,nest,,,4200\n")
    PORTS = ("machine_id,port_id,direction,edge,tile,height_mm\n"
             "nest,delivery,input,south,1,900\n")
    NO_MACHINES = ("id,display_name,role,footprint_x,footprint_z,height_metres,"
                   "power_draw_kw,health,max_depth,recipe_id\n")

    def load(self, bodies: str, map_layout: str):
        return machine_specs.load(bodies_source=bodies, ports_source=self.PORTS,
                                  machines_source=self.NO_MACHINES,
                                  map_layout_source=map_layout)

    def test_comes_from_the_map_layouts_constant_when_the_row_is_blank(self):
        """The end state, and the one the shipped table is in: the body table
        stops restating the footprint and there is one authority left."""
        nest = machine_specs.by_id(
            self.load(self.BODIES_BLANK, "const NEST_FOOTPRINT_TILES: int = 3\n"),
            "nest")
        self.assertEqual((nest.footprint_x, nest.footprint_z), (3, 3))
        self.assertTrue(nest.footprint_from_simulation)
        self.assertEqual(nest.footprint_authority, "sim/map_layout.gd")

    def test_a_disagreement_is_an_error_naming_both_files(self):
        """The acceptance criterion, and the reason the fixture is a literal: the
        two numbers really disagree here, where on the shipped tree they agree by
        construction. 3 tiles in the Simulation against 4 in the body table is a
        mesh two metres wider than the thing a player collides with."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load(self.BODIES_4X4, "const NEST_FOOTPRINT_TILES: int = 3\n")
        message = str(caught.exception)
        self.assertIn("sim/map_layout.gd", message)
        self.assertIn("machine_bodies.csv", message)
        self.assertIn("nest", message)
        self.assertIn("3x3", message)
        self.assertIn("4x4", message)
        # And it points at the authority it really has, not at the Machine table
        # the Nest is deliberately absent from.
        self.assertNotIn("machines.csv is the authority", message)

    def test_an_agreement_is_marked_as_checked_rather_than_merely_passing(self):
        """Agreeing is not the same as being checked, and the flag is how the
        shipped-table test below can tell the difference."""
        nest = machine_specs.by_id(
            self.load(self.BODIES_4X4, "const NEST_FOOTPRINT_TILES: int = 4\n"),
            "nest")
        self.assertEqual((nest.footprint_x, nest.footprint_z), (4, 4))
        self.assertTrue(nest.footprint_from_simulation)
        self.assertEqual(nest.footprint_authority, "sim/map_layout.gd")

    def test_a_constant_that_has_been_renamed_is_an_error_naming_the_file(self):
        """Resolving a missing authority to a plausible default is exactly the
        silence this closes, so it is refused instead — and the message says
        where to go and what to rename."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load(self.BODIES_BLANK, "const NEST_SIZE_TILES: int = 4\n")
        message = str(caught.exception)
        self.assertIn("sim/map_layout.gd", message)
        self.assertIn("NEST_FOOTPRINT_TILES", message)
        self.assertIn("SQUARE_FOOTPRINT_CONSTANTS", message)

    def test_two_authorities_for_one_body_is_an_error_naming_both(self):
        """If somebody ever gives the Nest a row in `machines.csv`, that is the
        defect this ticket closed arriving from the other direction: two files
        declaring one footprint. One authority, so this is refused rather than
        silently preferring whichever the merge happened to put second."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            machine_specs.load(
                bodies_source=self.BODIES_BLANK, ports_source=self.PORTS,
                machines_source=self.NO_MACHINES
                + "nest,Nest,crafter,4,4,4.2,0,8000,1,none\n",
                map_layout_source="const NEST_FOOTPRINT_TILES: int = 4\n")
        message = str(caught.exception)
        self.assertIn("machines.csv", message)
        self.assertIn("sim/map_layout.gd", message)
        self.assertIn("nest", message)

    def test_the_port_rules_are_checked_against_the_simulations_footprint(self):
        """The footprint is not a label — it is what a port's tile index has to
        fit inside. A Nest the Simulation says is 1x1 has no south tile 1, so a
        port the 4x4 body table would have allowed is refused."""
        with self.assertRaises(machine_specs.DeclarationError) as caught:
            self.load(self.BODIES_BLANK, "const NEST_FOOTPRINT_TILES: int = 1\n")
        self.assertIn("delivery", str(caught.exception))
        self.assertIn("1 tile(s) long", str(caught.exception))


class TheShippedTables(unittest.TestCase):
    def test_at_least_one_footprint_is_the_simulations_own(self):
        """The mechanism is live, not merely available. If this ever reads zero,
        the mesh pipeline has stopped being checked against the Simulation at
        all and every other agreement test below is passing vacuously."""
        checked = [m for m in machine_specs.load() if m.footprint_from_simulation]
        self.assertTrue(checked,
                        "no generated Machine's footprint comes from content/machines.csv")

    def test_the_nests_footprint_is_the_simulations_own(self):
        """Read live off both ends, because this is the pair #61 found drifting
        apart unobserved. `sim/map_layout.gd` is the authority, the body table
        defers to it, and the generator therefore builds the mesh at exactly the
        size the Simulation obstructs, respawns a player on and docks Belts
        against."""
        nest = machine_specs.by_id(machine_specs.load(), "nest")
        self.assertEqual(nest.footprint_authority, "sim/map_layout.gd")
        self.assertTrue(nest.footprint_from_simulation)
        declared = machine_specs.structure_footprints()["nest"]
        self.assertEqual((nest.footprint_x, nest.footprint_z), declared)
        # And the body table has stopped restating it, which is what makes the
        # sentence above "one authority" rather than "two that agree today".
        row = next(r for r in machine_specs.parse_table(
            (REPO / "content" / "machine_bodies.csv").read_text(),
            "content/machine_bodies.csv") if r["machine_id"] == "nest")
        self.assertEqual((row["footprint_x"], row["footprint_z"]), ("", ""))

    def test_agree_with_the_simulations_machine_table_as_far_as_it_goes(self):
        """Loading the real files is the check. It tightens by itself as gameplay
        tickets add rows — which is the point: nobody has to remember to come
        back and connect the two."""
        declared = machine_specs.simulation_footprints()
        machines = machine_specs.load()
        # `simulation_footprints` is the merged view of both authorities — every
        # Machine's row plus the Nest's constant — so this covers the Nest too.
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

    def test_the_two_heights_the_simulation_tunes_match_the_bodies_that_wear_them(self):
        """A Belt's deck and the Nest's crown are the two solid heights that are
        **not** a Machine's, so they live in `content/tuning.toml` rather than in
        `machines.csv` — a Belt and the Nest run no Recipe (DESIGN.md) and have no
        row there to carry a column.

        That makes them the one pair of heights the footprint rule cannot cover,
        so they get this cross-check instead: the Simulation stands a player on
        the tuned number and the generator models the body at the declared one,
        and a disagreement would be a deck you walk through.
        """
        tuning = (REPO / "content" / "tuning.toml").read_text()
        for machine_id, section, key in (("belt_straight", "belt", "deck_height_metres"),
                                         ("nest", "nest", "height_metres")):
            with self.subTest(machine_id=machine_id):
                tuned_mm = _tuned_millimetres(tuning, section, key)
                body = machine_specs.by_id(machine_specs.load(), machine_id)
                self.assertEqual(
                    body.body_height_mm, tuned_mm,
                    f"content/machine_bodies.csv gives {machine_id} "
                    f"{body.body_height_mm} mm but content/tuning.toml's "
                    f"[{section}] {key} says {tuned_mm} mm")


if __name__ == "__main__":
    unittest.main()
