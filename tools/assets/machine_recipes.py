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

**Silhouette is the whole job, and it is a gameplay requirement.** The core skill
in a factory game is reading your own production line at a glance; a player must
know what a building is from its outline alone, at distance, in peripheral
vision, while something is chasing them. So each recipe commits to one **gross
form** — not one detail — and the forms are chosen to be mutually unmistakable:

| Machine | The form, in one phrase |
|---|---|
| `miner` | an open drill derrick: a tall narrow lattice you can see sky through |
| `coal_miner` | a pithead: two big winding wheels on a raked headframe |
| `smelter` | a blast furnace: a bellied vessel that flares out and tapers in |
| `boiler` | a horizontal drum on a brick setting, long and low |
| `generator` | an engine bed under one oversized open-spoked flywheel |
| `press` | an H-frame: two posts with a ram travelling through the gap |
| `ammo_press` | a magazine drum lying across the top, under a raking feed |
| `assembler` | a wide shed with a sawtooth roof, and nothing above it |
| `silo` | one enormous vertical launch tube on a low fort |
| `nest` | a stepped ziggurat under a beacon mast |
| `belt` | a trestle deck, one tile long |

Height, mass, roof shape, how many things rise and where — never surface
detailing, which is gone by thirty metres. `tools/assets/machine_silhouette.py`
measures the result and the asset suite fails if any two Machines converge, so
this table is checked rather than asserted.
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


#: Bodies whose corner frame is deliberately shorter than their housing.
#:
#: The shared frame posts are what tie every Machine to the same factory, but
#: four posts at full height draw a box around whatever is inside them — which is
#: exactly the silhouette this ticket exists to break. A Machine whose form is a
#: pyramid, an H-frame or a wheel keeps its posts down at plinth height, where
#: they read as a bolted-down base instead of as a crate.
_SHORT_FRAMES = {"press": 1.0, "nest": 1.3, "generator": 1.1, "smelter": 1.5}


def frame_height(machine) -> float:
    """How tall the shared corner posts stand on this body."""
    return _SHORT_FRAMES.get(machine.body, housing_height(machine) + 0.15)


# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------

def _miner(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A rotary drill derrick: a low shed under a tall open lattice tower.

    The tower is the silhouette and it is deliberately **open**. A solid tapered
    tower and a furnace stack are the same trapezoid in black, and the Miner and
    the Smelter are the two Machines a player most needs to tell apart in the
    first five minutes of a Run.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.24)
    derrick_base, derrick_height = top - 0.1, 6.2
    derrick_top = derrick_base + derrick_height
    parts.truss_tower(a, "CastIron", 0.88, 0.36, derrick_base, derrick_height,
                      leg=0.3, bands=5)
    # The crown block, and the drill stem hanging down inside the derrick.
    a.add("WeldedSteel", parts.box((1.0, 1.0, 0.34),
                                   center=(0.0, 0.0, derrick_top + 0.17)))
    a.add("OiledSteel", parts.cylinder(0.14, derrick_height * 0.8,
                                       center=(0.0, 0.0, derrick_base + derrick_height * 0.4),
                                       segments=10))
    a.add("CastIron", parts.cylinder(0.26, 0.5, center=(0.0, 0.0, top + 0.3),
                                     segments=12))
    # The spoil hopper the Resource comes up into.
    a.add("Soot", parts.frustum((1.6, 1.6), (0.9, 0.9), 0.8,
                                center_bottom=(0.0, 0.0, 0.3)))
    for sx in (-1, 1):
        parts.hydraulic_ram(a, (sx * (hx - 0.5), hy * 0.45, 0.3), 0.8, 0.6)
    parts.gauge_cluster(a, (0.0, -hy + 0.2, 1.25), count=2)
    parts.access_door(a, (0.0, hy - 0.2, 0.95), (0.8, 1.2))


def _coal_miner(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A pithead: two winding sheaves on a raked headframe over a coal bunker.

    Coal is dug, not drilled, and a pithead is the one industrial silhouette a
    player already knows. Two wheels, side by side, standing clear of everything
    else on the Machine — a circle is a shape nothing else in the kit makes, and
    two of them cannot be read as one.
    """
    top = housing_height(machine)
    # A battered winding house — walls that lean inward — rather than the upright
    # box the Generator has. The two share a 2x2 footprint and a wheel, so the
    # base they stand on has to disagree as well as the thing above it.
    a.add("OliveDrab", parts.prism((0.0, 0.0, 0.26), (hx * 2 - 0.5, hy * 2 - 0.5),
                                   (0.0, 0.0, top), (hx * 2 - 1.6, hy * 2 - 1.6)))
    a.add("OxideRed", parts.box((hx * 2 - 0.42, hy * 2 - 0.42, 0.1),
                                center=(0.0, 0.0, 0.31), chamfer=0.02))
    # The headframe, and the back-stays that rake away from it to the south. The
    # rake is load-bearing to the look: a vertical frame would be a derrick.
    frame_base, frame_height_m = top - 0.1, 3.1
    wheel_z = frame_base + frame_height_m + 0.75
    parts.truss_tower(a, "CastIron", 0.95, 0.82, frame_base, frame_height_m,
                      leg=0.26, bands=3)
    for sx in (-1, 1):
        a.add("WeldedSteel", parts.prism(
            (sx * (hx - 0.4), hy - 0.35, 0.3), (0.3, 0.3),
            (sx * 0.75, 0.0, wheel_z - 0.3), (0.26, 0.26)))
    a.add("WeldedSteel", parts.box((2.1, 0.46, 0.3), center=(0.0, 0.0, wheel_z)))
    for sx in (-1, 1):
        parts.spoked_wheel(a, (sx * 0.92, 0.0, wheel_z), 0.84, 0.24,
                           axis="y", spokes=6)
    # The bunker the coal drops into, and the winding engine house beside it.
    a.add("Soot", parts.frustum((1.8, 1.4), (1.0, 0.8), 0.7,
                                center_bottom=(0.0, hy * 0.3, 0.3)))
    a.add("CastIron", parts.box((hx * 2 - 1.4, 0.9, 0.5),
                                center=(0.0, -hy + 0.75, top + 0.2)))
    parts.gauge_cluster(a, (0.0, -hy + 0.2, 1.3), count=2)
    parts.access_door(a, (-hx * 0.45, -hy + 0.2, 1.0), (0.75, 1.3))


def _smelter(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A blast furnace: a bellied vessel that flares out, then tapers in.

    Not a box with a chimney. A furnace is a *shape* — wide at the bosh, pinched
    at the throat — and that profile is the one thing in a Factory that cannot be
    mistaken for a shed. The downcomer running back down the flank is the second
    read, and it is a pipe rather than a stack on purpose.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.3)
    hearth = top - 0.1
    a.add("CastIron", parts.frustum((2.0, 2.0), (2.9, 2.9), 1.7,
                                    center_bottom=(0.0, 0.0, hearth)))
    a.add("OxideRed", parts.frustum((2.9, 2.9), (2.5, 2.5), 1.3,
                                    center_bottom=(0.0, 0.0, hearth + 1.7)))
    a.add("CastIron", parts.frustum((2.5, 2.5), (1.6, 1.6), 2.3,
                                    center_bottom=(0.0, 0.0, hearth + 3.0)))
    throat = hearth + 5.3
    a.add("WeldedSteel", parts.cylinder(0.86, 0.26, center=(0.0, 0.0, throat),
                                        segments=20))
    a.add("CastIron", parts.cylinder(0.62, 0.9, center=(0.0, 0.0, throat + 0.45),
                                     segments=16))
    a.add("Soot", parts.cylinder(0.5, 0.2, center=(0.0, 0.0, throat + 0.95),
                                 segments=16))
    # Binding hoops, which is what a furnace has instead of a chimney's collar.
    for level in (1.1, 2.3, 3.6):
        half = 1.45 - max(0.0, (level - 1.7)) * 0.2
        a.add("WeldedSteel", parts.box((half * 2 + 0.08, half * 2 + 0.08, 0.14),
                                       center=(0.0, 0.0, hearth + level), chamfer=0.03))
    # The downcomer: gas off the throat and back down the flank, a fat pipe that
    # breaks the vessel's outline without pretending to be a second stack.
    parts.pipe_run(a, [(0.0, 0.0, throat + 0.6),
                       (hx - 0.42, 0.0, throat + 0.6),
                       (hx - 0.42, 0.0, 1.0)], radius=0.26)
    # The tap: a sooted mouth and the launder the iron runs down.
    a.add("Soot", parts.box((1.1, 0.34, 0.55), center=(0.0, hy - 0.26, 0.95)))
    a.add("OxideRed", parts.frustum((1.3, 0.9), (1.0, 0.5), 0.5,
                                    center_bottom=(0.0, hy - 0.6, 0.3)))
    parts.gauge_cluster(a, (-hx * 0.55, -hy + 0.22, 1.1), count=3)
    parts.access_door(a, (-hx * 0.5, hy - 0.24, 0.95), (0.85, 1.2), face="y")


def _press(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A two-post hydraulic press: crosshead up top, ram and die below. The
    silhouette is the gap the ram travels through, so nothing fills it."""
    top = housing_height(machine)
    a.add("CastIron", parts.box((hx * 2 - 0.4, hy * 2 - 0.6, 0.8),
                                center=(0.0, 0.0, 0.66)))
    post_depth = 2.0
    for sx in (-1, 1):
        a.add("WeldedSteel", parts.box((0.46, post_depth, top + 1.9),
                                       center=(sx * (hx - 0.36), 0.0, (top + 1.9) / 2.0)))
        parts.rivet_run(a, "WeldedSteel",
                        (sx * (hx - 0.36), -post_depth / 2.0 + 0.2, 1.2),
                        (sx * (hx - 0.36), post_depth / 2.0 - 0.2, 1.2), 4, axis="y")
    crosshead = top + 1.6
    a.add("CastIron", parts.box((hx * 2 - 0.4, post_depth + 0.4, 0.7),
                                center=(0.0, 0.0, crosshead)))
    a.add("OliveDrab", parts.box((hx * 2 - 1.1, post_depth - 0.2, 0.55),
                                 center=(0.0, 0.0, crosshead + 0.62)))
    # The ram hangs from the crosshead rather than standing on the bed, which is
    # what makes a press read as a press.
    a.add("CastIron", parts.cylinder(0.3, 0.8, center=(0.0, 0.0, crosshead - 0.75),
                                     segments=12))
    a.add("OiledSteel", parts.cylinder(0.16, 1.0, center=(0.0, 0.0, crosshead - 1.6),
                                       segments=12))
    a.add("WeldedSteel", parts.box((1.1, 1.1, 0.3), center=(0.0, 0.0, crosshead - 2.2)))
    a.add("OiledSteel", parts.box((1.4, 1.4, 0.2), center=(0.0, 0.0, 1.16)))
    parts.pipe_run(a, [(hx - 0.75, -hy + 0.45, 1.2),
                       (hx - 0.75, -hy + 0.45, crosshead + 0.3),
                       (0.2, -hy + 0.45, crosshead + 0.3)])
    parts.gauge_cluster(a, (0.0, -hy + 0.35, 1.7), count=2)


def _assembler(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A wide shed under a sawtooth roof, and nothing at all above it.

    The one Machine that does not reach upward, and the only roofline in the
    Factory that is not flat. Three north-lit bays: a shape that cannot be read
    as a stack, a mast, a drum or a crate, and that announces itself as the place
    work is *done* rather than burned.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.2)
    bays = 3
    bay_width = (hx * 2 - 0.4) / bays
    for index in range(bays):
        centre_x = -hx + 0.2 + bay_width * (index + 0.5)
        a.add("OliveDrab", parts.wedge((bay_width, hy * 2 - 0.4, 0.0),
                                       (centre_x, 0.0, top), 0.25, 1.05))
        # The glazed face of each tooth, which is what makes it read as a roof
        # and not as a row of ramps.
        a.add("GaugeGlass", parts.box((0.1, hy * 2 - 0.9, 0.74),
                                      center=(centre_x + bay_width / 2.0 - 0.07,
                                              0.0, top + 0.68), chamfer=0.01))
        a.add("WeldedSteel", parts.box((0.16, hy * 2 - 0.4, 0.16),
                                       center=(centre_x + bay_width / 2.0, 0.0,
                                               top + 1.07)))
    a.add("WeldedSteel", parts.box((hx * 2 - 0.3, hy * 2 - 0.3, 0.18),
                                   center=(0.0, 0.0, top + 0.09)))
    a.add("GaugeGlass", parts.box((hx * 2 - 1.5, 0.08, 0.8),
                                  center=(0.0, -hy + 0.19, 1.5), chamfer=0.01))
    parts.rib_run(a, "WeldedSteel", (-hx + 0.6, hy - 0.2, 1.3), (hx - 0.6, hy - 0.2, 1.3),
                  4, size=(0.16, 0.14, top - 0.6))
    parts.gauge_cluster(a, (hx * 0.55, -hy + 0.22, 2.0), count=3)
    parts.access_door(a, (-hx * 0.45, -hy + 0.2, 1.1), (0.8, 1.4))


def _boiler(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A fire-tube boiler: a riveted drum lying in a brick setting, long and low.

    The lowest wide Machine in the Factory and the only one whose mass is
    horizontal and round. A steam dome at one end and a short stack at the other
    make it asymmetric, which is the cue that survives being half-seen.
    """
    top = housing_height(machine)
    # The firebrick house, on the west half, with the stack on it. The drum sits
    # on the east half and runs *along* the Belt line, so what faces a player
    # walking the line is a 2.6 m riveted circle rather than another flat flank.
    a.add("Soot", parts.box((hx - 0.35, hy * 2 - 0.3, top),
                            center=(-hx * 0.5, 0.0, 0.26 + (top - 0.26) / 2.0),
                            chamfer=0.05))
    # The capping slab oversails the brickwork, and stops at hx - 0.2 so that it
    # is still inside the footprint: everything on a Machine may go up and
    # nothing may go sideways.
    a.add("CastIron", parts.box((hx - 0.2, hy * 2 - 0.2, 0.26),
                                center=(-hx * 0.5, 0.0, top + 0.1)))
    parts.chimney(a, (-hx * 0.5, hy * 0.3, top + 0.2), 2.6, radius=0.32)
    drum_radius = min(hy - 0.3, 1.3)
    drum_z = 0.26 + drum_radius + 0.26
    drum_length = hy * 2 - 0.5
    a.add("CastIron", parts.cylinder(drum_radius, drum_length,
                                     center=(hx * 0.46, 0.0, drum_z),
                                     axis="y", segments=22))
    for sy in (-1, 1):
        a.add("WeldedSteel", parts.cylinder(drum_radius * 1.07, 0.16,
                                            center=(hx * 0.46, sy * (hy - 0.33), drum_z),
                                            axis="y", segments=22))
    # The front tube plate, with the firebox mouth let into it: a boiler without
    # one is a water tank.
    a.add("OxideRed", parts.cylinder(drum_radius * 0.84, 0.18,
                                     center=(hx * 0.46, -hy + 0.32, drum_z),
                                     axis="y", segments=20))
    a.add("Soot", parts.cylinder(drum_radius * 0.42, 0.14,
                                 center=(hx * 0.46, -hy + 0.25, drum_z),
                                 axis="y", segments=16))
    parts.rivet_run(a, "WeldedSteel",
                    (hx * 0.46, -hy + 0.55, drum_z + drum_radius - 0.02),
                    (hx * 0.46, hy - 0.55, drum_z + drum_radius - 0.02), 6,
                    radius=0.05, depth=0.05, axis="z")
    # Saddles, so the drum is carried rather than floating.
    for sy in (-1, 1):
        a.add("CastIron", parts.box((drum_radius * 1.8, 0.4, drum_z - 0.26),
                                    center=(hx * 0.46, sy * (hy - 0.7),
                                            0.26 + (drum_z - 0.26) / 2.0)))
    # The steam dome and its safety valve, standing proud on the drum.
    a.add("CastIron", parts.cylinder(0.46, 0.72,
                                     center=(hx * 0.46, hy * 0.3,
                                             drum_z + drum_radius + 0.26),
                                     segments=16))
    a.add("DullBrass", parts.cylinder(0.2, 0.32,
                                      center=(hx * 0.46, hy * 0.3,
                                              drum_z + drum_radius + 0.76),
                                      segments=12))
    parts.pipe_run(a, [(hx * 0.46, hy * 0.3, drum_z + drum_radius + 0.9),
                       (-hx * 0.5 + 0.4, hy * 0.3, drum_z + drum_radius + 0.9),
                       (-hx * 0.5 + 0.4, hy * 0.3, top + 0.4)], radius=0.09)
    parts.gauge_cluster(a, (-hx * 0.5, -hy + 0.2, 1.5), count=3)
    parts.access_door(a, (-hx * 0.5, hy - 0.2, 1.0), (0.8, 1.2))


def _generator(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A single-cylinder engine under one oversized open-spoked flywheel.

    The wheel is the whole Machine. It is as large as the footprint allows and it
    stands clear of the engine bed, so the outline is a low block with a circle
    rising out of it — and the sky between the spokes is what keeps it from
    reading as a drum.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.22)
    radius = min(hx, hy) - 0.28
    wheel_z = 0.26 + radius + 0.2
    parts.spoked_wheel(a, (0.0, -hy + 0.52, wheel_z), radius, 0.3,
                       axis="y", spokes=6)
    # The steam cylinder, the crosshead guide and the rod that ties them to the
    # wheel: the mechanism a player can read the direction of.
    a.add("CastIron", parts.cylinder(0.34, hx * 1.2, center=(0.0, hy * 0.42, top - 0.5),
                                     axis="x", segments=14))
    a.add("WeldedSteel", parts.cylinder(0.4, 0.12,
                                        center=(-hx * 0.6, hy * 0.42, top - 0.5),
                                        axis="x", segments=14))
    a.add("OiledSteel", parts.cylinder(0.09, hy * 1.1,
                                       center=(hx * 0.55, 0.0, top - 0.5),
                                       axis="y", segments=10))
    a.add("OiledSteel", parts.cylinder(0.08, radius * 0.9,
                                       center=(radius * 0.3, -hy + 0.52,
                                               wheel_z - radius * 0.35),
                                       segments=10))
    parts.gauge_cluster(a, (0.0, hy - 0.2, 1.4), count=2)
    parts.pipe_run(a, [(-hx + 0.35, hy - 0.35, 0.6), (-hx + 0.35, hy - 0.35, top - 0.3)])


def _ammo_press(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A magazine drum lying across the top, under a raking feed arm.

    The Press reaches up through a gap; this one lies down. The drum runs
    east-west so it reads as a bar on the skyline rather than as another circle,
    and the feed arm is the only raking line in the Factory.
    """
    top = housing_height(machine)
    parts.painted_housing(a, hx, hy, 0.26, top, inset=0.2)
    a.add("CastIron", parts.box((hx * 2 - 0.5, hy * 2 - 0.5, 0.24),
                                center=(0.0, 0.0, top + 0.1)))
    drum_radius = 0.82
    drum_z = top + 0.3 + drum_radius
    a.add("OliveDrab", parts.cylinder(drum_radius, hx * 2 - 0.8,
                                      center=(0.0, hy * 0.22, drum_z),
                                      axis="x", segments=18))
    for sx in (-1, 1):
        a.add("DullBrass", parts.cylinder(drum_radius * 0.44, 0.22,
                                          center=(sx * (hx - 0.42), hy * 0.22, drum_z),
                                          axis="x", segments=12))
        a.add("WeldedSteel", parts.cylinder(drum_radius * 1.06, 0.12,
                                            center=(sx * (hx - 0.62), hy * 0.22, drum_z),
                                            axis="x", segments=18))
    # The feed arm: a raking conveyor from the intake corner up over the drum.
    a.add("WeldedSteel", parts.prism(
        (-hx + 0.5, -hy + 0.5, 0.4), (0.8, 0.5),
        (hx * 0.2, hy * 0.22 - 0.1, drum_z + drum_radius + 0.2), (0.7, 0.45)))
    a.add("OiledSteel", parts.cylinder(0.12, 0.7,
                                       center=(-hx + 0.5, -hy + 0.5, 0.55),
                                       axis="x", segments=10))
    a.add("Soot", parts.frustum((0.9, 0.7), (0.5, 0.4), 0.45,
                                center_bottom=(hx * 0.35, -hy + 0.45, 0.3)))
    parts.gauge_cluster(a, (-hx * 0.3, -hy + 0.22, 1.5), count=2)
    parts.access_door(a, (hx * 0.4, hy - 0.2, 1.0), (0.75, 1.3))


def _silo(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """One enormous vertical launch tube standing on a low raked fort.

    The Silo fires only what it was loaded with, and loading is irreversible, so
    the mesh has to make the tube unmistakable — it is the tallest thing on the
    Map and the only straight-sided column on it. The fort under it is kept low
    and raked so nothing competes with the tube for the outline.
    """
    top = housing_height(machine)
    a.add("OliveDrab", parts.prism((0.0, 0.0, 0.26), (hx * 2 - 0.3, hy * 2 - 0.3),
                                   (0.0, 0.0, top), (hx * 2 - 1.5, hy * 2 - 1.5)))
    a.add("CastIron", parts.box((hx * 2 - 1.7, hy * 2 - 1.7, 0.4),
                                center=(0.0, 0.0, top + 0.16)))
    tube_base, tube_height, tube_radius = top + 0.3, 7.0, 1.42
    a.add("CastIron", parts.cylinder(tube_radius, tube_height,
                                     center=(0.0, 0.0, tube_base + tube_height / 2.0),
                                     segments=24))
    for fraction in (0.08, 0.42, 0.76):
        a.add("WeldedSteel", parts.cylinder(tube_radius * 1.07, 0.22,
                                            center=(0.0, 0.0,
                                                    tube_base + tube_height * fraction),
                                            segments=24))
    a.add("WeldedSteel", parts.cylinder(tube_radius, 0.7,
                                        center=(0.0, 0.0, tube_base + tube_height + 0.35),
                                        radius_top=tube_radius * 1.3, segments=24))
    a.add("Soot", parts.cylinder(tube_radius * 1.05, 0.3,
                                 center=(0.0, 0.0, tube_base + tube_height + 0.75),
                                 segments=24))
    parts.rivet_run(a, "WeldedSteel",
                    (0.0, -tube_radius - 0.03, tube_base + 1.2),
                    (0.0, -tube_radius - 0.03, tube_base + tube_height - 1.2), 9,
                    radius=0.06, depth=0.06, axis="y")
    # The loading cradle: a hazard-striped rack on the north face, where the two
    # declared inputs arrive.
    a.add("HazardYellow", parts.box((hx * 2 - 2.4, 0.3, 0.16),
                                    center=(0.0, -hy + 0.35, 1.4)))
    for index in range(3):
        a.add("OiledSteel", parts.cylinder(0.14, 0.9,
                                           center=(-1.4 + index * 1.4, -hy + 0.5, 1.65),
                                           axis="y", segments=10))
    for sx in (-1, 1):
        parts.hydraulic_ram(a, (sx * 2.2, hy * 0.45, top + 0.2), 1.0, 0.8)
    parts.gauge_cluster(a, (hx * 0.6, -hy + 0.3, 1.9), count=3)
    # A railing around the fort's roof. The Silo is the tallest thing on the Map
    # and a 7 m tube has no scale of its own; a handrail is a human-sized object,
    # so it is what tells the eye how big the tube actually is.
    parts.catwalk(a, hx - 0.9, hy - 0.9, top + 0.4)


def _nest(machine, a: parts.Assembly, hx: float, hy: float) -> None:
    """A stepped ziggurat under a beacon mast.

    The structure the Run is lost with, built to read as *fortified* rather than
    industrial. Three raked tiers: nothing else in the Factory steps, so the Nest
    is identifiable from any direction and at any distance, which matters because
    it is both the thing to defend and the point to run back to.

    **The tier walls are cast iron and only the caps are oxide, which is #80.**
    Two of the three used to be `OliveDrab` and every cap `OxideRed`, which made
    the Nest 55% painted surface — and because a tier wall is *raked*, those two
    bands are the one large thing in the game turned face-on to a 23-degree sun.
    Measured at eye level it rendered at 6.4 times the ground it stands on. A
    fortification is iron, not paint, so the walls carry `CastIron` and the caps
    keep `OxideRed` as the rust on the capping plates — which is what holds the
    three steps apart from above, where the caps are most of what is visible.
    """
    top = housing_height(machine)
    tiers = ((0.26, 1.7, hx * 2 - 0.3, hx * 2 - 0.9),
             (1.7, 3.2, hx * 2 - 1.6, hx * 2 - 2.2),
             (3.2, top, hx * 2 - 2.9, hx * 2 - 3.5))
    for base, head, wide, narrow in tiers:
        a.add("CastIron", parts.prism((0.0, 0.0, base), (wide, wide),
                                      (0.0, 0.0, head), (narrow, narrow)))
        a.add("OxideRed", parts.box((narrow + 0.3, narrow + 0.3, 0.2),
                                    center=(0.0, 0.0, head + 0.08), chamfer=0.04))
    # Observation slits, as recessed dark bands rather than as real holes.
    for sy in (-1, 1):
        a.add("Soot", parts.box((hx * 2 - 2.4, 0.12, 0.3),
                                center=(0.0, sy * (hy - 1.25), 2.1), chamfer=0.02))
    mast_base = top + 0.2
    parts.truss_tower(a, "WeldedSteel", 0.55, 0.3, mast_base, 3.0,
                      leg=0.22, bands=3)
    beacon = mast_base + 3.2
    a.add("CastIron", parts.cylinder(0.3, 0.3, center=(0.0, 0.0, beacon), segments=14))
    a.add("GaugeGlass", parts.cylinder(0.26, 0.44, center=(0.0, 0.0, beacon + 0.36),
                                       segments=14))
    a.add("CastIron", parts.cylinder(0.32, 0.12, center=(0.0, 0.0, beacon + 0.64),
                                     segments=14))
    # The Delivery intake: progression is physical, so there is a real doorway to
    # carry goods through.
    a.add("Soot", parts.box((1.5, 0.3, 1.9), center=(0.0, hy - 0.35, 1.2)))
    a.add("HazardYellow", parts.box((1.75, 0.12, 0.16), center=(0.0, hy - 0.22, 2.25)))
    parts.gauge_cluster(a, (hx - 1.5, -hy + 1.0, 1.5), count=2)


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
    "coal_miner": _coal_miner,
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
