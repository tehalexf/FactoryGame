#!/usr/bin/env python3
"""One recipe per Machine: what it is made of, in the parts kit's vocabulary.

This is the artifact the ticket is actually about. A Machine's look is a function
here, not a `.blend` file somebody once saved, so changing the Press's ram travel
is an edit and a re-run rather than a remodelling session.

Each recipe is handed the resolved `Machine` (so footprint comes from
the content tables and nowhere else) and an `Assembly` to add parts to. The
footprint, the plinth, the frame posts and the port fittings are added for every
Machine by the generator before the recipe runs, so a recipe only describes what
makes *this* Machine recognisable at a hundred metres.

**Silhouette is the whole job.** A player identifies a Machine across a Factory by
its outline against the sky, never by its surface. So each recipe commits to one
strong vertical gesture — a drill tower, a stack, a ram, a gantry, a drum, a
flywheel, a launch tube — and resists adding a second.
"""

from __future__ import annotations

import machine_parts as parts


def build(machine, assembly: parts.Assembly) -> None:
    """Dispatch to the body's recipe. An unknown body is a declaration error, not
    a silently empty mesh."""
    recipe = _RECIPES.get(machine.body)
    if recipe is None:
        raise KeyError(
            f"{machine.machine_id}: no mesh recipe for body {machine.body!r}. "
            f"Known bodies: {', '.join(sorted(_RECIPES))}")
    recipe(machine, assembly, *_half_extents(machine))


def housing_height(machine) -> float:
    """The housing height in metres, from `content/machine_bodies.csv`.

    Declared rather than written into this file, so that making a Machine taller
    is an edit to a table and a re-run — the same workflow as changing its
    footprint. Masts, stacks and launch tubes are measured up from here, so
    raising a housing raises everything above it too.
    """
    return machine.body_height_mm / 1000.0


def _half_extents(machine) -> tuple[float, float]:
    half_x_mm, half_z_mm = machine.half_extent_mm()
    return (half_x_mm / 1000.0, half_z_mm / 1000.0)


def needs_standard_shell(machine) -> bool:
    """A Belt is not a Machine in a housing — it is a deck on legs — so it opts
    out of the plinth and frame the other recipes share."""
    return machine.body != "belt"


def needs_port_fittings(machine) -> bool:
    """A Machine's ports are hazard-striped collars let into its flank. A Belt's
    ports are its own open ends, so giving it collars would wall off the deck
    goods are supposed to travel along. The marker nodes are added either way:
    they are the declaration, not decoration.
    """
    return machine.body != "belt"


# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------

def _miner(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A drill tower over a sloped spoil hopper. The silhouette is the mast."""
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.2)
    # The mast: a tapered lattice-less tower, because a lattice at this scale
    # reads as noise. Height is deliberately above the housing's own, so the
    # Miner is the tallest thing on an early Factory floor.
    mast_base, mast_top = top - 0.1, top + 2.5
    a.add("CastIron", parts.frustum((1.1, 1.1), (0.66, 0.66), mast_top - mast_base,
                                    center_bottom=(0.0, 0.0, mast_base)))
    parts.rib_run(a, "WeldedSteel",
                  (0.0, 0.0, mast_base + 0.4), (0.0, 0.0, mast_top - 0.3), 5,
                  size=(1.18, 1.18, 0.09))
    # The drill head and its spoil chute.
    a.add("OiledSteel", parts.cylinder(0.3, 1.0, center=(0.0, 0.0, mast_top + 0.3),
                                       segments=12))
    a.add("OiledSteel", parts.cylinder(0.3, 0.7, center=(0.0, 0.0, mast_top + 1.05),
                                       radius_top=0.0, segments=12))
    a.add("Soot", parts.frustum((1.5, 1.5), (0.8, 0.8), 0.7,
                                center_bottom=(0.0, 0.0, 0.3)))
    for sx in (-1, 1):
        parts.hydraulic_ram(a, (sx * (hx - 0.5), 0.0, 0.3), 0.85, 0.7)
    parts.gauge_cluster(a, (0.0, -hy + 0.2, 1.55), count=2)
    parts.access_door(a, (0.0, hy - 0.2, 0.95), (0.8, 1.3))


def _smelter(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A furnace shell with a tapped firebox and one dominating stack."""
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.22)
    a.add("CastIron", parts.box((hx * 2 - 0.3, hy * 2 - 0.3, 0.3),
                                center=(0.0, 0.0, top + 0.12)))
    parts.chimney(a, (hx * 0.42, -hy * 0.42, top + 0.2), 2.9, radius=0.36)
    # The tap: a glowing-hot mouth would need emission, which is a texture-pass
    # concern, so the hole is modelled and left sooted.
    a.add("Soot", parts.box((1.0, 0.3, 0.5), center=(0.0, hy - 0.26, 0.95)))
    a.add("OxideRed", parts.frustum((1.3, 0.9), (1.0, 0.5), 0.5,
                                    center_bottom=(0.0, hy - 0.55, 0.3)))
    parts.gauge_cluster(a, (-hx * 0.45, -hy + 0.22, 1.9), count=3)
    parts.pipe_run(a, [(-hx + 0.3, -hy + 0.35, 0.5),
                       (-hx + 0.3, -hy + 0.35, top - 0.5),
                       (hx * 0.42 - 0.3, -hy + 0.35, top - 0.5),
                       (hx * 0.42 - 0.3, -hy * 0.42, top - 0.5)], radius=0.08)
    parts.access_door(a, (-hx * 0.5, hy - 0.24, 1.35), (0.85, 1.5), face="y")
    parts.catwalk(a, hx, hy, top + 0.3)


def _press(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A two-post hydraulic press: crosshead up top, ram and die below. The
    silhouette is the gap the ram travels through, so nothing fills it."""
    top = housing_height(machine)
    a.add("CastIron", parts.box((hx * 2 - 0.4, hy * 2 - 0.4, 0.7),
                                center=(0.0, 0.0, 0.6)))
    for sx in (-1, 1):
        a.add("WeldedSteel", parts.box((0.42, hy * 2 - 0.5, top + 1.3),
                                       center=(sx * (hx - 0.35), 0.0, (top + 1.3) / 2.0)))
        parts.rivet_run(a, "WeldedSteel",
                        (sx * (hx - 0.35), -hy + 0.3, 1.0),
                        (sx * (hx - 0.35), hy - 0.3, 1.0), 4, axis="y")
    crosshead = top + 1.0
    a.add("CastIron", parts.box((hx * 2 - 0.4, hy * 2 - 0.7, 0.6),
                                center=(0.0, 0.0, crosshead)))
    a.add("OliveDrab", parts.box((hx * 2 - 0.9, hy * 2 - 1.1, 0.5),
                                 center=(0.0, 0.0, crosshead + 0.55)))
    # The ram hangs from the crosshead rather than standing on the bed, which is
    # what makes a press read as a press.
    a.add("CastIron", parts.cylinder(0.26, 0.7, center=(0.0, 0.0, crosshead - 0.6),
                                     segments=12))
    a.add("OiledSteel", parts.cylinder(0.14, 0.8, center=(0.0, 0.0, crosshead - 1.3),
                                       segments=12))
    a.add("WeldedSteel", parts.box((1.0, 1.0, 0.26), center=(0.0, 0.0, crosshead - 1.8)))
    a.add("OiledSteel", parts.box((1.3, 1.3, 0.18), center=(0.0, 0.0, 1.05)))
    parts.pipe_run(a, [(hx - 0.6, -hy + 0.4, 1.0),
                       (hx - 0.6, -hy + 0.4, crosshead + 0.2),
                       (0.2, -hy + 0.4, crosshead + 0.2)])
    parts.gauge_cluster(a, (0.0, -hy + 0.3, 1.5), count=2)


def _assembler(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A long housing under a travelling gantry. The silhouette is horizontal on
    purpose: it is the one Machine that does not reach upward."""
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.18)
    a.add("GaugeGlass", parts.box((hx * 2 - 1.5, 0.08, 0.8),
                                  center=(0.0, -hy + 0.17, 1.6), chamfer=0.01))
    parts.rib_run(a, "WeldedSteel", (-hx + 0.6, hy - 0.2, 1.5), (hx - 0.6, hy - 0.2, 1.5),
                  4, size=(0.16, 0.14, top - 0.7))
    # The gantry: two rails and a carriage, inset so it never leaves the tiles.
    rail = top + 0.55
    for sy in (-1, 1):
        a.add("WeldedSteel", parts.box((hx * 2 - 0.5, 0.17, 0.17),
                                       center=(0.0, sy * (hy - 0.55), rail)))
        for sx in (-1, 1):
            a.add("WeldedSteel", parts.box((0.2, 0.2, 0.55),
                                           center=(sx * (hx - 0.5), sy * (hy - 0.55),
                                                   rail - 0.36)))
    a.add("CastIron", parts.box((1.1, hy * 2 - 0.8, 0.3), center=(hx * 0.3, 0.0, rail)))
    a.add("OiledSteel", parts.cylinder(0.1, 0.9, center=(hx * 0.3, 0.0, rail - 0.55),
                                       segments=10))
    a.add("OliveDrab", parts.box((0.5, 0.5, 0.3), center=(hx * 0.3, 0.0, rail - 1.1)))
    parts.gauge_cluster(a, (hx * 0.55, -hy + 0.22, 2.1), count=3)
    parts.access_door(a, (-hx * 0.45, -hy + 0.2, 1.1), (0.8, 1.4))


def _boiler(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A fire-tube boiler: a riveted horizontal drum in a cradle, firebox at one
    end, stack at the other. The drum is the whole identity."""
    top = housing_height(machine)
    drum_radius = min(hy - 0.35, 1.0)
    drum_z = 0.26 + drum_radius + 0.35
    a.add("CastIron", parts.cylinder(drum_radius, hx * 2 - 0.9, center=(0.0, 0.0, drum_z),
                                     axis="x", segments=20))
    for sx in (-1, 1):
        a.add("WeldedSteel", parts.cylinder(drum_radius * 1.06, 0.12,
                                            center=(sx * (hx - 0.5), 0.0, drum_z),
                                            axis="x", segments=20))
        a.add("CastIron", parts.box((0.5, drum_radius * 1.6, drum_z - 0.26),
                                    center=(sx * (hx - 0.55), 0.0,
                                            0.26 + (drum_z - 0.26) / 2.0)))
    # Riveted seams around the drum: a boiler without them is a water tank.
    parts.rivet_run(a, "WeldedSteel",
                    (-hx + 0.8, 0.0, drum_z + drum_radius - 0.02),
                    (hx - 0.8, 0.0, drum_z + drum_radius - 0.02), 7,
                    radius=0.05, depth=0.05, axis="z")
    a.add("OxideRed", parts.cylinder(drum_radius * 0.8, 0.2,
                                     center=(-hx + 0.35, 0.0, drum_z), axis="x",
                                     segments=16))
    a.add("Soot", parts.cylinder(drum_radius * 0.55, 0.12,
                                 center=(-hx + 0.27, 0.0, drum_z), axis="x", segments=16))
    parts.chimney(a, (hx - 0.75, 0.0, drum_z + drum_radius - 0.1), 1.9, radius=0.26)
    parts.gauge_cluster(a, (0.0, -hy + 0.2, drum_z + 0.35), count=3)
    parts.pipe_run(a, [(0.3, -hy + 0.3, drum_z + drum_radius - 0.1),
                       (0.3, -hy + 0.3, top + 0.9),
                       (hx - 0.1, -hy + 0.3, top + 0.9)], radius=0.09)
    # A safety valve, standing proud. Boiler startup and pressure relief are
    # diegetic controls, so the thing a player grabs has to be visible.
    a.add("DullBrass", parts.cylinder(0.1, 0.4, center=(-hx * 0.3, 0.0,
                                                        drum_z + drum_radius + 0.2),
                                      segments=10))
    a.add("OiledSteel", parts.cylinder(0.035, 0.42, center=(-hx * 0.3, -0.18,
                                                            drum_z + drum_radius + 0.45),
                                       axis="y", segments=6))


def _generator(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A single-cylinder engine turning an oversized flywheel. The flywheel is
    the silhouette, so it is as large as the footprint allows."""
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.3)
    radius = min(hx, hy) - 0.42
    a.add("OiledSteel", parts.cylinder(radius, 0.26,
                                       center=(0.0, -hy + 0.36, 0.26 + radius + 0.1),
                                       axis="y", segments=24))
    a.add("CastIron", parts.cylinder(radius * 0.34, 0.34,
                                     center=(0.0, -hy + 0.4, 0.26 + radius + 0.1),
                                     axis="y", segments=12))
    # Spokes, as a rib array rather than as a real wheel.
    for index in range(3):
        from mathutils import Matrix  # type: ignore
        spoke = parts.box((radius * 1.7, 0.2, 0.17),
                          center=(0.0, 0.0, 0.0), chamfer=0.02)
        import bmesh  # type: ignore
        bmesh.ops.rotate(spoke, verts=spoke.verts, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(index * 1.0471975511965976, 3, 'Y'))
        bmesh.ops.translate(spoke, verts=spoke.verts,
                            vec=(0.0, -hy + 0.36, 0.26 + radius + 0.1))
        a.add("CastIron", spoke)
    a.add("CastIron", parts.cylinder(0.3, hx * 1.1, center=(0.0, hy * 0.3, top - 0.45),
                                     axis="x", segments=14))
    a.add("OiledSteel", parts.cylinder(0.1, 0.9, center=(-hx * 0.75, hy * 0.3, top - 0.45),
                                       axis="x", segments=10))
    parts.chimney(a, (hx - 0.55, hy - 0.55, top), 1.5, radius=0.22)
    parts.gauge_cluster(a, (0.0, hy - 0.2, 1.5), count=2)
    parts.pipe_run(a, [(-hx + 0.35, hy - 0.35, 0.6), (-hx + 0.35, hy - 0.35, top - 0.3)])


def _ammo_press(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A press with a magazine drum on top: the same mechanism as the Press, but
    the drum says 'this one makes Ammunition' before you read the label."""
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.2)
    a.add("CastIron", parts.box((hx * 2 - 0.5, hy * 2 - 0.5, 0.26),
                                center=(0.0, 0.0, top + 0.1)))
    drum_radius = min(hx, hy) - 0.45
    a.add("OliveDrab", parts.cylinder(drum_radius, 1.0,
                                      center=(0.0, hy * 0.25, top + 0.75), segments=18))
    a.add("WeldedSteel", parts.cylinder(drum_radius * 1.05, 0.1,
                                        center=(0.0, hy * 0.25, top + 1.2), segments=18))
    a.add("DullBrass", parts.cylinder(drum_radius * 0.42, 1.08,
                                      center=(0.0, hy * 0.25, top + 0.75), segments=12))
    for sx in (-1, 1):
        parts.hydraulic_ram(a, (sx * (hx - 0.45), -hy * 0.45, top + 0.12), 0.6, 0.55)
    a.add("Soot", parts.frustum((0.9, 0.7), (0.5, 0.4), 0.45,
                                center_bottom=(0.0, -hy + 0.42, 0.3)))
    parts.gauge_cluster(a, (hx * 0.4, -hy + 0.22, 1.7), count=2)
    parts.access_door(a, (-hx * 0.4, -hy + 0.2, 1.1), (0.75, 1.35))


def _silo(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """An armoured magazine with a vertical launch tube and blast doors.

    The Silo fires only what it was loaded with, and loading is irreversible, so
    the mesh has to make the loading cradle and the tube unmistakable.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.24)
    a.add("CastIron", parts.box((hx * 2 - 0.35, hy * 2 - 0.35, 0.4),
                                center=(0.0, 0.0, top + 0.16)))
    tube_z = top + 0.3
    a.add("CastIron", parts.cylinder(0.78, 4.4, center=(0.0, hy * 0.35, tube_z + 2.2),
                                     segments=20))
    a.add("WeldedSteel", parts.cylinder(0.9, 0.18, center=(0.0, hy * 0.35, tube_z + 0.4),
                                        segments=20))
    a.add("WeldedSteel", parts.cylinder(0.9, 0.18, center=(0.0, hy * 0.35, tube_z + 3.9),
                                        segments=20))
    a.add("Soot", parts.cylinder(0.64, 0.3, center=(0.0, hy * 0.35, tube_z + 4.35),
                                 segments=20))
    parts.rivet_run(a, "WeldedSteel",
                    (0.0, hy * 0.35 - 0.79, tube_z + 0.8),
                    (0.0, hy * 0.35 - 0.79, tube_z + 3.5), 7,
                    radius=0.05, depth=0.05, axis="y")
    # The loading cradle: a hazard-striped rack on the north face, where the two
    # declared inputs arrive.
    a.add("HazardYellow", parts.box((hx * 2 - 1.6, 0.3, 0.14),
                                    center=(0.0, -hy + 0.3, 1.5)))
    for index in range(3):
        a.add("OiledSteel", parts.cylinder(0.14, 0.9,
                                           center=(-1.4 + index * 1.4, -hy + 0.45, 1.75),
                                           axis="y", segments=10))
    parts.gauge_cluster(a, (hx * 0.6, -hy + 0.25, 2.3), count=3)
    parts.hydraulic_ram(a, (-hx + 0.6, hy * 0.35, top + 0.2), 1.1, 0.9)
    parts.hydraulic_ram(a, (hx - 0.6, hy * 0.35, top + 0.2), 1.1, 0.9)
    parts.catwalk(a, hx, hy, top + 0.4)


def _nest(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """The structure the Run is lost with: a stepped bunker under a beacon mast.

    Built to read as *fortified* rather than industrial — stepped armour, a wide
    base, a single light at the top that is visible from anywhere on the Map,
    because it is both the thing to defend and the respawn point to run back to.
    """
    top = housing_height(machine)
    a.add("CastIron", parts.box((hx * 2 - 0.3, hy * 2 - 0.3, 1.1),
                                center=(0.0, 0.0, 0.26 + 0.55), chamfer=0.08))
    a.add("OliveDrab", parts.frustum((hx * 2 - 1.0, hy * 2 - 1.0),
                                     (hx * 2 - 2.2, hy * 2 - 2.2), top - 1.4,
                                     center_bottom=(0.0, 0.0, 1.36)))
    a.add("OxideRed", parts.box((hx * 2 - 2.3, hy * 2 - 2.3, 0.35),
                                center=(0.0, 0.0, top - 0.05)))
    # Observation slits, as recessed dark bands rather than as real holes.
    for sy in (-1, 1):
        a.add("Soot", parts.box((hx * 2 - 2.0, 0.12, 0.3),
                                center=(0.0, sy * (hy - 1.1), 2.0), chamfer=0.02))
    mast_base = top + 0.1
    a.add("WeldedSteel", parts.frustum((0.7, 0.7), (0.34, 0.34), 3.0,
                                       center_bottom=(0.0, 0.0, mast_base)))
    parts.rib_run(a, "WeldedSteel", (0.0, 0.0, mast_base + 0.5),
                  (0.0, 0.0, mast_base + 2.6), 4, size=(0.76, 0.76, 0.08))
    a.add("CastIron", parts.cylinder(0.3, 0.3, center=(0.0, 0.0, mast_base + 3.15),
                                     segments=14))
    a.add("GaugeGlass", parts.cylinder(0.26, 0.42, center=(0.0, 0.0, mast_base + 3.5),
                                       segments=14))
    a.add("CastIron", parts.cylinder(0.32, 0.12, center=(0.0, 0.0, mast_base + 3.77),
                                     segments=14))
    # The Delivery intake: progression is physical, so there is a real doorway to
    # carry goods through.
    a.add("Soot", parts.box((1.5, 0.3, 2.0), center=(0.0, hy - 0.4, 1.3)))
    a.add("HazardYellow", parts.box((1.75, 0.12, 0.16), center=(0.0, hy - 0.26, 2.38)))
    parts.catwalk(a, hx - 0.9, hy - 0.9, top + 0.05)
    parts.gauge_cluster(a, (hx - 1.4, -hy + 1.05, 1.6), count=2)


def _belt(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """One tile of Belt, running north to south: side frames, rollers, deck.

    Belts are the only logistics primitive and connect directly to Machine ports,
    so this segment's deck sits at exactly the 900 mm port height and its frame
    fills the tile precisely — segments must butt together with no seam.
    """
    deck = housing_height(machine)
    for sx in (-1, 1):
        a.add("WeldedSteel", parts.box((0.16, hy * 2, 0.5),
                                       center=(sx * (hx - 0.08), 0.0, deck - 0.12),
                                       chamfer=0.02))
        # A leg at each end rather than one in the middle, so butted segments
        # read as a continuous trestle rather than as a row of tables.
        for sy in (-1, 1):
            a.add("CastIron", parts.box((0.22, 0.22, deck - 0.3),
                                        center=(sx * (hx - 0.13), sy * (hy - 0.18),
                                                (deck - 0.3) / 2.0)))
        parts.rivet_run(a, "WeldedSteel",
                        (sx * (hx - 0.04), -hy + 0.25, deck - 0.12),
                        (sx * (hx - 0.04), hy - 0.25, deck - 0.12), 4,
                        radius=0.04, depth=0.05, axis="x")
    a.add("BeltRubber", parts.box((hx * 2 - 0.32, hy * 2, 0.07),
                                  center=(0.0, 0.0, deck), chamfer=0.01))
    a.add("BeltRubber", parts.box((hx * 2 - 0.32, hy * 2, 0.06),
                                  center=(0.0, 0.0, deck - 0.3), chamfer=0.01))
    for index in range(4):
        a.add("OiledSteel", parts.cylinder(0.08, hx * 2 - 0.36,
                                           center=(0.0, -hy + 0.25 + index * (hy * 2 - 0.5) / 3.0,
                                                   deck - 0.12),
                                           axis="x", segments=10))
    a.add("HazardYellow", parts.box((0.1, hy * 2 - 0.4, 0.06),
                                    center=(hx - 0.17, 0.0, deck + 0.17), chamfer=0.0))
    a.add("HazardYellow", parts.box((0.1, hy * 2 - 0.4, 0.06),
                                    center=(-hx + 0.17, 0.0, deck + 0.17), chamfer=0.0))


_RECIPES = {
    "miner": _miner,
    "smelter": _smelter,
    "press": _press,
    "assembler": _assembler,
    "boiler": _boiler,
    "generator": _generator,
    "ammo_press": _ammo_press,
    "silo": _silo,
    "nest": _nest,
    "belt": _belt,
}

#: The bodies this kit can build. The generator checks every row in
#: `content/machine_bodies.csv` against it, so adding a Machine without a recipe
#: fails loudly instead of shipping an empty file.
KNOWN_BODIES = frozenset(_RECIPES)
