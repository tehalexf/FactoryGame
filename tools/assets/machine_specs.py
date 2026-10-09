#!/usr/bin/env python3
"""The Machine declaration, as the asset pipeline sees it.

Three tables, each with one job, and one rule about which wins:

* `content/machines.csv` — the Simulation's own Machine table, and **the
  authority on footprints and on housing heights**. Where it names a Machine, its
  `footprint_x`/`footprint_z` and its `height_metres` are the footprint and the
  height, full stop — the Simulation collides a player against that height, so a
  mesh that disagreed with it would be a roof you fall through.
* `content/machine_bodies.csv` — which Machines have a generated mesh, and a
  footprint and height for bodies the Simulation does not yet declare. A
  footprint or a height given in two places must agree exactly, or loading fails
  naming both files.
* `content/machine_ports.csv` — the authority on port positions.

And one file that is not a table: `sim/map_layout.gd`, the authority on the
**Nest's** footprint. The Nest is not a Machine and never will be (DESIGN.md
lists it alongside Belt and Wall), so it has no row in `machines.csv` to carry a
footprint column, and its size lives where its position does — in the Map's
geography, as `MapLayout.NEST_FOOTPRINT_TILES`. `structure_footprints` reads it;
`footprint_authorities` is the merged view, and the one place that knows which
file owns which footprint.

That is the whole anti-drift mechanism. The Simulation reads `machines.csv` and
`machine_ports.csv` through `sim/csv_table.gd`; this module is the *only* other
reader of any of them, so a footprint or a port position cannot be true on the
mesh and false in the Simulation without the asset suite saying so. The
dependency runs one way, always: `tools/` reads `sim/`, never the reverse.

Standard library only, deliberately: it is read by Blender's bundled Python, by
the test suite, and by the verification scripts, none of which share an
environment.

    python3 tools/assets/machine_specs.py          # the declaration, resolved

Coordinates. A Machine's origin is the centre of its footprint at ground level,
in Godot's axes: +X east, +Y up, -Z north. Everything here is in integer
millimetres, because the grid is exact and floats are how exactness is lost.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

#: The grid rule from docs/DESIGN.md, fixed early because it is expensive to
#: change. Machines occupy 2x2 to 4x4 tiles; a Belt is one tile wide.
TILE_SIZE_MM = 2000

REPO = Path(__file__).resolve().parents[2]
BODIES_CSV = REPO / "content" / "machine_bodies.csv"
PORTS_CSV = REPO / "content" / "machine_ports.csv"

#: The Simulation's own Machine table. Optional *to the asset pipeline* only
#: because it arrives with the gameplay tickets; when it is present it overrules
#: this pipeline on every footprint it declares.
MACHINES_CSV = REPO / "content" / "machines.csv"

#: The Map's geography, and the authority on the footprint of the one generated
#: body that is **not** a Machine and never will be. See `structure_footprints`.
MAP_LAYOUT_GD = REPO / "sim" / "map_layout.gd"

#: Body id to the `sim/map_layout.gd` constant that declares its footprint in
#: tiles, for the bodies whose size is geography rather than a Machine row. The
#: Nest is square, so one integer is the whole footprint.
SQUARE_FOOTPRINT_CONSTANTS = {"nest": "NEST_FOOTPRINT_TILES"}

DIRECTIONS = ("input", "output")

#: Edge name to the unit step, in tiles, of the outward normal — Godot's axes,
#: where north is -Z. The edge an *input* faces is the side a Belt arrives from.
EDGE_NORMALS = {
    "north": (0, -1),
    "south": (0, 1),
    "east": (1, 0),
    "west": (-1, 0),
}


class DeclarationError(Exception):
    """A content table says something the grid rules do not allow.

    Always names the file and the line, because a validation error that does not
    is a treasure hunt.
    """


@dataclass(frozen=True)
class Port:
    """One place a Belt may connect to a Machine, one tile wide."""

    port_id: str
    direction: str
    edge: str
    tile: int
    height_mm: int

    @property
    def is_input(self) -> bool:
        return self.direction == "input"


@dataclass(frozen=True)
class Machine:
    """One generated body: its footprint, its housing height and its ports.

    `body` names the mesh recipe, and is deliberately separate from the `role`
    column in `machines.csv`: that is gameplay vocabulary (`miner`, `crafter`)
    and this is art vocabulary (`smelter`, `boiler`, `flywheel`-driven
    `generator`). Two Machines can share a role and look nothing alike.
    """

    machine_id: str
    body: str
    footprint_x: int
    footprint_z: int
    body_height_mm: int
    #: True when the Simulation declared this footprint, so the Simulation and
    #: the mesh have been checked against each other rather than merely being
    #: plausible.
    footprint_from_simulation: bool = False
    #: Which file that was — `content/machines.csv` for a Machine,
    #: `sim/map_layout.gd` for the Nest — or `content/machine_bodies.csv` when
    #: this table owns the number because nothing in the Simulation states it.
    footprint_authority: str = "content/machine_bodies.csv"
    ports: tuple[Port, ...] = field(default_factory=tuple)

    def footprint_mm(self) -> tuple[int, int]:
        """The footprint in millimetres: tiles times the grid's tile size."""
        return (self.footprint_x * TILE_SIZE_MM, self.footprint_z * TILE_SIZE_MM)

    def half_extent_mm(self) -> tuple[int, int]:
        """Distance from the origin to the footprint boundary on X and Z."""
        width, depth = self.footprint_mm()
        return (width // 2, depth // 2)

    def tiles_along(self, edge: str) -> int:
        """How many tiles an edge is long. North and south run along X."""
        return self.footprint_x if edge in ("north", "south") else self.footprint_z


def port_position_mm(machine: Machine, port: Port) -> tuple[int, int, int]:
    """Where a port sits relative to the Machine origin, in millimetres.

    The single implementation of the rule. The port is the centre of its edge
    tile, on the footprint boundary, at its declared height. Because the origin
    is the footprint centre and tiles are 2 m, every X and Z is a whole metre.

    This is what the generator places a marker at and what the asset suite
    asserts the generated glTF actually contains, so a change here moves the
    mesh and the Simulation's belief together or fails the suite.
    """
    half_x, half_z = machine.half_extent_mm()
    # Centre of tile `tile` measured from the edge's starting corner.
    along = (2 * port.tile + 1) * (TILE_SIZE_MM // 2)
    if port.edge in ("north", "south"):
        x = along - half_x
        z = half_z if port.edge == "south" else -half_z
    else:
        z = along - half_z
        x = half_x if port.edge == "east" else -half_x
    return (x, port.height_mm, z)


def outward_normal(port: Port) -> tuple[int, int]:
    """The port's outward direction on the grid, as (dx, dz) in tiles."""
    return EDGE_NORMALS[port.edge]


# ----------------------------------------------------------------------------
# Reading the content tables
# ----------------------------------------------------------------------------

def parse_table(source: str, path: str) -> list[dict[str, str]]:
    """The content-table dialect: `#` comments, blank lines skipped, the first
    remaining line is the header, fields comma-separated and trimmed, no quoting.

    Deliberately the same dialect `sim/csv_table.gd` reads, so the Simulation and
    the asset pipeline are looking at the same bytes the same way.
    """
    rows: list[dict[str, str]] = []
    header: list[str] | None = None
    for number, raw in enumerate(source.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in line.split(",")]
        if header is None:
            header = fields
            continue
        if len(fields) != len(header):
            raise DeclarationError(
                f"{path} line {number}: {len(fields)} fields, header has {len(header)}")
        row = dict(zip(header, fields))
        row["__line__"] = str(number)
        rows.append(row)
    if header is None:
        raise DeclarationError(f"{path}: no header line")
    return rows


def _require_int(row: dict[str, str], column: str, path: str) -> int:
    value = row.get(column, "")
    try:
        return int(value)
    except ValueError:
        raise DeclarationError(
            f"{path} line {row['__line__']}: column {column!r} is {value!r}, "
            f"which is not a whole number") from None


def _require_millimetres(row: dict[str, str], column: str, path: str) -> int:
    """A decimal number of metres as whole millimetres, exactly.

    Parsed digit by digit rather than through `float`, for the reason
    `Fixed.from_decimal_string` exists on the other side of the boundary: a
    height is compared against a declaration for equality, and a binary float is
    not the right type to do that with. Three decimal places, floored, which is
    millimetres and the resolution the rest of this module works in.
    """
    value = row.get(column, "")
    sign, digits = (-1, value[1:]) if value.startswith("-") else (1, value)
    whole, _, fraction = digits.partition(".")
    if not whole.isdigit() or (fraction and not fraction.isdigit()):
        raise DeclarationError(
            f"{path} line {row['__line__']}: column {column!r} is {value!r}, "
            f"which is not a number of metres")
    return sign * (int(whole) * 1000 + int((fraction + "000")[:3]))


def _require_one_of(row: dict[str, str], column: str, allowed, path: str) -> str:
    value = row.get(column, "")
    if value not in allowed:
        raise DeclarationError(
            f"{path} line {row['__line__']}: column {column!r} is {value!r}, "
            f"expected one of {', '.join(sorted(allowed))}")
    return value


def simulation_declarations(machines_source: str | None = None
                            ) -> dict[str, tuple[tuple[int, int], int]]:
    """What the Simulation declares about each Machine's box, from
    `content/machines.csv`: its footprint in tiles and its housing height in
    millimetres.

    An empty result when the file is absent: the gameplay tables arrive on their
    own tickets, and the art pipeline must not be blocked on them. Every id the
    file *does* carry is then checked against the body table, so the cross-check
    tightens by itself as Machines are added.
    """
    path = "content/machines.csv"
    if machines_source is None:
        if not MACHINES_CSV.exists():
            return {}
        machines_source = MACHINES_CSV.read_text()
    declared: dict[str, tuple[tuple[int, int], int]] = {}
    for row in parse_table(machines_source, path):
        machine_id = row.get("id", "")
        if not machine_id:
            raise DeclarationError(f"{path} line {row['__line__']}: empty id")
        declared[machine_id] = (
            (_require_int(row, "footprint_x", path), _require_int(row, "footprint_z", path)),
            _require_millimetres(row, "height_metres", path),
        )
    return declared


def structure_footprints(map_layout_source: str | None = None
                         ) -> dict[str, tuple[int, int]]:
    """What the Simulation declares about the footprint of a generated body that
    is **not** a Machine, read out of `sim/map_layout.gd`.

    There is exactly one of those: the **Nest**. It has no row in
    `content/machines.csv` and never will — DESIGN.md lists it alongside Belt and
    Wall, outside the eight Machines, and it runs no Recipe — so its size lives
    where its position does, in the Map's geography, as
    `MapLayout.NEST_FOOTPRINT_TILES`. That makes it the one footprint the rule in
    `simulation_declarations` could not reach, which is how `machine_bodies.csv`
    came to be a second authority on the 4x4 a player respawns on top of and
    every Belt in every scenario docks against.

    It is parsed rather than imported because nothing in this pipeline runs
    GDScript — Blender's bundled Python reads this module — and it is read rather
    than restated because a restatement is the defect. **The dependency runs one
    way:** `tools/` reads `sim/`, and `sim/` has never heard of the asset
    pipeline.

    A constant that has been renamed or removed is an error naming the file,
    because resolving it to a plausible default is exactly the silence this
    exists to end.
    """
    path = "sim/map_layout.gd"
    if map_layout_source is None:
        if not MAP_LAYOUT_GD.exists():
            return {}
        map_layout_source = MAP_LAYOUT_GD.read_text()
    declared: dict[str, tuple[int, int]] = {}
    for body_id, constant in sorted(SQUARE_FOOTPRINT_CONSTANTS.items()):
        match = re.search(
            r"^const\s+" + re.escape(constant) + r"\s*:\s*int\s*=\s*(-?\d+)\s*$",
            map_layout_source, re.MULTILINE)
        if match is None:
            raise DeclarationError(
                f"{path}: no `const {constant}: int = <n>` to read {body_id}'s "
                f"footprint from. It is the authority on that footprint; if it "
                f"was renamed, rename it in "
                f"machine_specs.SQUARE_FOOTPRINT_CONSTANTS too.")
        tiles = int(match.group(1))
        declared[body_id] = (tiles, tiles)
    return declared


def footprint_authorities(machines_source: str | None = None,
                          map_layout_source: str | None = None
                          ) -> dict[str, tuple[tuple[int, int], str]]:
    """Every footprint the Simulation declares and the file that declares it.

    Two files, because the Simulation holds the fact in two places for two good
    reasons — a Machine's footprint is a row in its own table, the Nest's is
    geography — and **one** reader of both, so a body cannot have two authorities
    without this function saying which.
    """
    authorities: dict[str, tuple[tuple[int, int], str]] = {
        machine_id: (box, "content/machines.csv")
        for machine_id, (box, _height) in
        simulation_declarations(machines_source).items()
    }
    for body_id, box in structure_footprints(map_layout_source).items():
        if body_id in authorities:
            raise DeclarationError(
                f"content/machines.csv declares {body_id!r} and so does "
                f"sim/map_layout.gd's "
                f"{SQUARE_FOOTPRINT_CONSTANTS[body_id]}. A footprint has one "
                f"authority: if {body_id} really is a Machine now, drop it from "
                f"machine_specs.SQUARE_FOOTPRINT_CONSTANTS.")
        authorities[body_id] = (box, "sim/map_layout.gd")
    return authorities


def simulation_footprints(machines_source: str | None = None,
                          map_layout_source: str | None = None
                          ) -> dict[str, tuple[int, int]]:
    """Just the footprints, for the callers that only want those."""
    return {body_id: box for body_id, (box, _path) in
            footprint_authorities(machines_source, map_layout_source).items()}


def load(bodies_source: str | None = None,
         ports_source: str | None = None,
         machines_source: str | None = None,
         map_layout_source: str | None = None) -> list[Machine]:
    """Every generated Machine body with its ports, sorted by id.

    Sorted, not in file order: anything the Simulation reads has to load
    deterministically, and the generator writes one file per Machine, so a
    reordered table must not reorder the build.

    The `*_source` arguments exist so the validation rules can be tested against
    a bad table without committing one.
    """
    bodies_path = "content/machine_bodies.csv"
    ports_path = "content/machine_ports.csv"
    machines_path = "content/machines.csv"
    if bodies_source is None:
        bodies_source = BODIES_CSV.read_text()
    if ports_source is None:
        ports_source = PORTS_CSV.read_text()
    declared_by_simulation = simulation_declarations(machines_source)
    # Footprints come from the merged view, because the Nest's authority is
    # `sim/map_layout.gd` rather than a Machine row; heights still come from
    # `machines.csv` alone, and the two the Simulation *tunes* — a Belt's deck
    # and the Nest's crown — are cross-checked against `content/tuning.toml` in
    # the asset suite instead, there being no column here for them to defer to.
    footprints_by_simulation = footprint_authorities(machines_source, map_layout_source)

    bare: dict[str, Machine] = {}
    for row in parse_table(bodies_source, bodies_path):
        machine_id = row.get("machine_id", "")
        if not machine_id:
            raise DeclarationError(
                f"{bodies_path} line {row['__line__']}: empty machine_id")
        if machine_id in bare:
            raise DeclarationError(
                f"{bodies_path} line {row['__line__']}: duplicate machine_id "
                f"{machine_id!r}")

        declaration = declared_by_simulation.get(machine_id)
        height_from_simulation = None if declaration is None else declaration[1]
        footprint_declaration = footprints_by_simulation.get(machine_id)
        from_simulation = None if footprint_declaration is None \
            else footprint_declaration[0]
        # The file to name in a refusal, which is per body rather than per rule:
        # a Machine's footprint is owned by `machines.csv` and the Nest's by
        # `sim/map_layout.gd`, and a message that named the wrong one would send
        # somebody to edit a file that is not the authority.
        authority = machines_path if footprint_declaration is None \
            else footprint_declaration[1]
        own = (row.get("footprint_x", ""), row.get("footprint_z", ""))
        if own == ("", ""):
            if from_simulation is None:
                raise DeclarationError(
                    f"{bodies_path} line {row['__line__']}: {machine_id} leaves its "
                    f"footprint blank, which means {machines_path} owns it, but "
                    f"{machines_path} does not declare {machine_id!r}")
            footprint = from_simulation
        else:
            footprint = (_require_int(row, "footprint_x", bodies_path),
                         _require_int(row, "footprint_z", bodies_path))
            if from_simulation is not None and from_simulation != footprint:
                raise DeclarationError(
                    f"{authority} gives {machine_id} a footprint of "
                    f"{from_simulation[0]}x{from_simulation[1]} tiles but "
                    f"{bodies_path} line {row['__line__']} says "
                    f"{footprint[0]}x{footprint[1]}. {authority} is the "
                    f"authority: either correct this row or blank its footprint "
                    f"columns to defer to it.")
                # Deferring is the better fix, and deletes the duplicate.
            if from_simulation is not None:
                footprint = from_simulation

        for axis, size in (("footprint_x", footprint[0]), ("footprint_z", footprint[1])):
            if not 1 <= size <= 4:
                raise DeclarationError(
                    f"{bodies_path} line {row['__line__']}: {machine_id} has "
                    f"{axis} of {size} tiles; the grid allows 1 to 4")
        # The housing height follows exactly the footprint's rule, one column later:
        # `machines.csv` owns it where it declares the Machine, this table's column is
        # then a cross-check, and blanking the column defers to it outright. The
        # Simulation collides a player against that number, so a mesh and a roof that
        # disagreed would be a surface you fall through rather than a cosmetic drift.
        own_height = row.get("body_height_mm", "")
        if own_height == "":
            if height_from_simulation is None:
                raise DeclarationError(
                    f"{bodies_path} line {row['__line__']}: {machine_id} leaves its "
                    f"body_height_mm blank, which means {machines_path} owns it, but "
                    f"{machines_path} does not declare {machine_id!r}")
            height_mm = height_from_simulation
        else:
            height_mm = _require_int(row, "body_height_mm", bodies_path)
            if height_from_simulation is not None and height_from_simulation != height_mm:
                raise DeclarationError(
                    f"{machines_path} gives {machine_id} a height of "
                    f"{height_from_simulation} mm but {bodies_path} line "
                    f"{row['__line__']} says {height_mm} mm. {machines_path} is the "
                    f"authority: either correct this row or blank its body_height_mm "
                    f"column to defer to it.")
        if height_mm <= 0:
            raise DeclarationError(
                f"{bodies_path} line {row['__line__']}: {machine_id} has a housing "
                f"height of {height_mm} mm; a body has to stand off the ground")
        bare[machine_id] = Machine(
            machine_id=machine_id,
            body=row.get("body", ""),
            footprint_x=footprint[0],
            footprint_z=footprint[1],
            body_height_mm=height_mm,
            footprint_from_simulation=from_simulation is not None,
            footprint_authority=authority if from_simulation is not None
            else "content/machine_bodies.csv",
        )

    ports: dict[str, list[Port]] = {machine_id: [] for machine_id in bare}
    occupied: dict[tuple[str, str, int], str] = {}
    for row in parse_table(ports_source, ports_path):
        machine_id = row.get("machine_id", "")
        if machine_id not in bare:
            # **A port declared for a Machine with no generated body is legal and is skipped
            # here.** Since #47 this table is what the Simulation docks a Belt against, so every
            # Machine that needs a Belt must declare its ports — including the ones art has not
            # reached yet, which `machines.csv` defines and this file's bodies do not. There is
            # no mesh to put a marker on, so there is nothing for the generator to do; a typo
            # is still caught, because an id in neither table is refused below.
            if machine_id in declared_by_simulation:
                continue
            raise DeclarationError(
                f"{ports_path} line {row['__line__']}: machine_id {machine_id!r} "
                f"is not a row in {bodies_path} or {machines_path}")
        machine = bare[machine_id]
        port = Port(
            port_id=row.get("port_id", ""),
            direction=_require_one_of(row, "direction", DIRECTIONS, ports_path),
            edge=_require_one_of(row, "edge", EDGE_NORMALS, ports_path),
            tile=_require_int(row, "tile", ports_path),
            height_mm=_require_int(row, "height_mm", ports_path),
        )
        if not port.port_id:
            raise DeclarationError(f"{ports_path} line {row['__line__']}: empty port_id")
        if any(p.port_id == port.port_id for p in ports[machine_id]):
            raise DeclarationError(
                f"{ports_path} line {row['__line__']}: {machine_id} already has a "
                f"port called {port.port_id!r}")
        edge_tiles = machine.tiles_along(port.edge)
        if not 0 <= port.tile < edge_tiles:
            raise DeclarationError(
                f"{ports_path} line {row['__line__']}: {machine_id}.{port.port_id} "
                f"is on tile {port.tile} of the {port.edge} edge, which is only "
                f"{edge_tiles} tile(s) long")
        if port.height_mm < 0:
            raise DeclarationError(
                f"{ports_path} line {row['__line__']}: negative height_mm")
        key = (machine_id, port.edge, port.tile)
        if key in occupied:
            raise DeclarationError(
                f"{ports_path} line {row['__line__']}: {machine_id} already has "
                f"{occupied[key]!r} on {port.edge} tile {port.tile}; a port is one "
                f"tile wide and two cannot share one")
        occupied[key] = port.port_id
        ports[machine_id].append(port)

    return [
        Machine(
            machine_id=machine.machine_id,
            body=machine.body,
            footprint_x=machine.footprint_x,
            footprint_z=machine.footprint_z,
            body_height_mm=machine.body_height_mm,
            footprint_from_simulation=machine.footprint_from_simulation,
            footprint_authority=machine.footprint_authority,
            ports=tuple(sorted(ports[machine.machine_id], key=lambda p: p.port_id)),
        )
        for machine in sorted(bare.values(), key=lambda m: m.machine_id)
    ]


def by_id(machines: list[Machine], machine_id: str) -> Machine:
    for machine in machines:
        if machine.machine_id == machine_id:
            return machine
    raise KeyError(f"no Machine called {machine_id!r}")


def port_by_id(machine: Machine, port_id: str) -> Port:
    for port in machine.ports:
        if port.port_id == port_id:
            return port
    raise KeyError(f"{machine.machine_id} has no port called {port_id!r}")


#: Name of the marker node the generator leaves on the mesh for a port, and that
#: the verification reads back. One prefix, so Godot can find them all.
PORT_NODE_PREFIX = "Port_"


def port_node_name(port: Port) -> str:
    return f"{PORT_NODE_PREFIX}{port.direction}_{port.port_id}"


def resolved() -> dict:
    """The whole declaration with positions worked out — what the generator
    builds and what the Godot-side verification is handed as expectations."""
    return {
        "tile_size_mm": TILE_SIZE_MM,
        "machines": [
            {
                "id": m.machine_id,
                "body": m.body,
                "footprint_tiles": [m.footprint_x, m.footprint_z],
                "footprint_mm": list(m.footprint_mm()),
                "footprint_from_simulation": m.footprint_from_simulation,
                "footprint_authority": m.footprint_authority,
                "body_height_mm": m.body_height_mm,
                "ports": [
                    {
                        "id": p.port_id,
                        "node": port_node_name(p),
                        "direction": p.direction,
                        "edge": p.edge,
                        "tile": p.tile,
                        "position_mm": list(port_position_mm(m, p)),
                    }
                    for p in m.ports
                ],
            }
            for m in load()
        ],
    }


if __name__ == "__main__":
    json.dump(resolved(), sys.stdout, indent=2)
    print()
