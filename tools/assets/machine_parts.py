#!/usr/bin/env python3
"""The dieselpunk parts kit: the vocabulary every Machine is assembled from.

Imported inside Blender by `generate_machines.py`. Kept separate from the recipes
so the kit can grow without the recipes moving, and so the recipes read as a
description of a Machine rather than as geometry code.

Boxes, bevels, arrays and chamfered frustums — deliberately. These are what
procedural geometry is good at and they are what 1920s-40s heavy industry
actually looks like: welded plate, bolted flanges, cast housings, riveted
seams. Nothing here makes a curve it does not need.

**Axes.** Everything in this file is in Blender's space: +X east, +Y *north*,
+Z up, metres, with the origin at the centre of the Machine's footprint on the
ground. The glTF exporter converts to Godot's +Y-up, -Z-forward on the way out,
which is the only axis change in the whole pipeline. `machine_specs` speaks
Godot's axes, so `godot_mm_to_blender` is the one place the two meet.

**The footprint envelope is hard.** A Machine may be as tall as it likes but must
never overhang its tiles, or it will clip the Machine on the next tile. Parts
take positions in metres and the recipes keep them inside; the asset suite checks
the result rather than trusting it.
"""

from __future__ import annotations

import bmesh  # type: ignore
from mathutils import Matrix, Vector  # type: ignore

#: Default bevel width, in metres. Small, because a 2 cm chamfer on a 6 m casting
#: is what reads as "cast iron" rather than "untextured cube" — a larger one
#: reads as soft plastic.
CHAMFER = 0.03


def godot_mm_to_blender(position_mm) -> Vector:
    """A `machine_specs` position (Godot axes, millimetres) in Blender's space."""
    x, y, z = position_mm
    return Vector((x / 1000.0, -z / 1000.0, y / 1000.0))


class Assembly:
    """Geometry being accumulated, one bmesh per palette material.

    One mesh per material means one glTF primitive per material, which keeps the
    exported file small and the material assignment impossible to get wrong — a
    face is in the CastIron mesh or it is not.
    """

    def __init__(self) -> None:
        self._by_material: dict[str, bmesh.types.BMesh] = {}

    def mesh_for(self, material: str) -> bmesh.types.BMesh:
        if material not in self._by_material:
            self._by_material[material] = bmesh.new()
        return self._by_material[material]

    def add(self, material: str, part: bmesh.types.BMesh) -> None:
        """Merge a finished part into its material's mesh, then discard it."""
        import bpy  # type: ignore
        scratch = bpy.data.meshes.new("__part__")
        part.to_mesh(scratch)
        part.free()
        self.mesh_for(material).from_mesh(scratch)
        bpy.data.meshes.remove(scratch)

    def materials(self) -> list[str]:
        return sorted(self._by_material)

    def take(self, material: str) -> bmesh.types.BMesh:
        return self._by_material[material]


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

def box(size, center=(0.0, 0.0, 0.0), chamfer: float = CHAMFER,
        segments: int = 1) -> bmesh.types.BMesh:
    """An axis-aligned box of the given full size, chamfered on every edge.

    The chamfer never changes the box's extents: it cuts the corners off, and the
    six faces stay on the planes they were on. That is why heavy chamfering is
    safe inside the footprint envelope.
    """
    mesh = bmesh.new()
    bmesh.ops.create_cube(mesh, size=1.0)
    bmesh.ops.scale(mesh, vec=Vector(size), verts=mesh.verts)
    bmesh.ops.translate(mesh, vec=Vector(center), verts=mesh.verts)
    if chamfer > 0.0:
        limit = min(size) / 2.0 * 0.49
        bmesh.ops.bevel(mesh, geom=list(mesh.verts) + list(mesh.edges),
                        offset=min(chamfer, limit), segments=segments,
                        affect='EDGES', profile=0.5, clamp_overlap=True)
    return mesh


def cylinder(radius: float, length: float, center=(0.0, 0.0, 0.0),
             axis: str = "z", segments: int = 16,
             radius_top: float | None = None) -> bmesh.types.BMesh:
    """A capped cylinder, or a truncated cone when `radius_top` differs.

    16 segments by default: enough that a boiler drum reads as round at the
    distances this game is played at, few enough that a Factory of two hundred
    Machines is not made of cylinders.
    """
    mesh = bmesh.new()
    bmesh.ops.create_cone(mesh, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius,
                          radius2=radius if radius_top is None else radius_top,
                          depth=length)
    if axis == "x":
        bmesh.ops.rotate(mesh, verts=mesh.verts, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(1.5707963267948966, 3, 'Y'))
    elif axis == "y":
        bmesh.ops.rotate(mesh, verts=mesh.verts, cent=(0, 0, 0),
                         matrix=Matrix.Rotation(1.5707963267948966, 3, 'X'))
    bmesh.ops.translate(mesh, vec=Vector(center), verts=mesh.verts)
    return mesh


def frustum(bottom_size, top_size, height: float,
            center_bottom=(0.0, 0.0, 0.0)) -> bmesh.types.BMesh:
    """A rectangular truncated pyramid: hoppers, chutes, tapered drill towers.

    Built from explicit vertices rather than by extruding a face, so the winding
    is fixed and the result is identical on every run.
    """
    mesh = bmesh.new()
    bx, by = bottom_size[0] / 2.0, bottom_size[1] / 2.0
    tx, ty = top_size[0] / 2.0, top_size[1] / 2.0
    ox, oy, oz = center_bottom
    lower = [mesh.verts.new((ox + sx * bx, oy + sy * by, oz))
             for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    upper = [mesh.verts.new((ox + sx * tx, oy + sy * ty, oz + height))
             for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    mesh.faces.new(list(reversed(lower)))
    mesh.faces.new(upper)
    for i in range(4):
        j = (i + 1) % 4
        mesh.faces.new((lower[i], lower[j], upper[j], upper[i]))
    mesh.normal_update()
    return mesh


# ---------------------------------------------------------------------------
# Detail arrays — the things that make a box read as machinery
# ---------------------------------------------------------------------------

def rivet_run(assembly: Assembly, material: str, start, end, count: int,
              radius: float = 0.05, depth: float = 0.04, axis: str = "z") -> None:
    """A line of rivet heads between two points. Flush-ish, shallow, many.

    Rivets are the cheapest dieselpunk signal there is, and an array is exactly
    the operation procedural geometry wants. `count` heads are spaced evenly
    including both endpoints.
    """
    start, end = Vector(start), Vector(end)
    for index in range(count):
        t = 0.0 if count == 1 else index / (count - 1)
        assembly.add(material, cylinder(radius, depth, center=start.lerp(end, t),
                                        axis=axis, segments=6))


def rib_run(assembly: Assembly, material: str, start, end, count: int,
            size) -> None:
    """Evenly spaced stiffening ribs: a box array along a line."""
    start, end = Vector(start), Vector(end)
    for index in range(count):
        t = 0.0 if count == 1 else index / (count - 1)
        assembly.add(material, box(size, center=start.lerp(end, t), chamfer=0.01))


def corner_posts(assembly: Assembly, material: str, half_x: float, half_y: float,
                 height: float, thickness: float = 0.32) -> None:
    """Four riveted corner posts standing on the footprint's exact corners.

    These, with the plinth, are what fix the mesh's extents to the declared
    footprint: the outer faces of the posts sit on the footprint boundary.
    """
    inset = thickness / 2.0
    for sx in (-1, 1):
        for sy in (-1, 1):
            center = (sx * (half_x - inset), sy * (half_y - inset), height / 2.0)
            assembly.add(material, box((thickness, thickness, height), center=center))
            rivet_run(assembly, "WeldedSteel",
                      (center[0], sy * (half_y - thickness + 0.005), 0.35),
                      (center[0], sy * (half_y - thickness + 0.005), height - 0.35),
                      max(2, int(height / 0.75)), radius=0.045, depth=0.05, axis="y")


def plinth(assembly: Assembly, half_x: float, half_y: float,
           height: float = 0.26) -> None:
    """The cast base skirt, filling the footprint exactly.

    Every Machine stands on one. It is the part that makes a Machine look bolted
    to the floor instead of resting on it, and it is where the footprint's X and
    Z extents come from.
    """
    assembly.add("CastIron", box((half_x * 2, half_y * 2, height),
                                 center=(0.0, 0.0, height / 2.0), chamfer=0.05))
    # Seated 0.04 m inside the boundary so the 0.05 m rivet heads stay strictly
    # within the footprint envelope. Breaking that by 5 mm would be invisible on
    # screen and would still be a footprint the Simulation does not believe in.
    for sy in (-1, 1):
        rivet_run(assembly, "WeldedSteel",
                  (-half_x + 0.3, sy * (half_y - 0.04), height * 0.55),
                  (half_x - 0.3, sy * (half_y - 0.04), height * 0.55),
                  max(2, int((half_x * 2 - 0.6) / 0.42) + 1), axis="y")
    for sx in (-1, 1):
        rivet_run(assembly, "WeldedSteel",
                  (sx * (half_x - 0.04), -half_y + 0.3, height * 0.55),
                  (sx * (half_x - 0.04), half_y - 0.3, height * 0.55),
                  max(2, int((half_y * 2 - 0.6) / 0.42) + 1), axis="x")


def painted_housing(assembly: Assembly, half_x: float, half_y: float,
                    base: float, top: float, inset: float = 0.16,
                    material: str = "OliveDrab") -> None:
    """The painted cowling that carries a Machine's silhouette colour.

    Inset from the footprint so the frame posts read as structure in front of it,
    with a strip of primer showing at the bottom seam — a painted machine that
    has never been scuffed does not look like it has worked.
    """
    height = top - base
    assembly.add(material, box((half_x * 2 - inset * 2, half_y * 2 - inset * 2, height),
                               center=(0.0, 0.0, base + height / 2.0), chamfer=0.06))
    assembly.add("OxideRed", box((half_x * 2 - inset * 2 + 0.03,
                                  half_y * 2 - inset * 2 + 0.03, 0.09),
                                 center=(0.0, 0.0, base + 0.045), chamfer=0.02))


def gauge_cluster(assembly: Assembly, center, count: int = 3,
                  spacing: float = 0.26, normal: str = "y") -> None:
    """A row of pressure gauges: brass bezel, glass face, on a steel plate.

    The only place brass is allowed. Dieselpunk reads brass as a *fitting*; a
    brass-coloured machine reads as steampunk, which is the wrong century.
    """
    center = Vector(center)
    offset = Vector((spacing, 0.0, 0.0)) if normal == "y" else Vector((0.0, spacing, 0.0))
    for index in range(count):
        at = center + offset * (index - (count - 1) / 2.0)
        assembly.add("DullBrass", cylinder(0.11, 0.07, center=at, axis=normal, segments=12))
        face = at + (Vector((0.0, -0.04, 0.0)) if normal == "y" else Vector((-0.04, 0.0, 0.0)))
        assembly.add("GaugeGlass", cylinder(0.075, 0.03, center=face, axis=normal, segments=12))


def chimney(assembly: Assembly, center_base, height: float, radius: float = 0.3,
            material: str = "CastIron") -> None:
    """A stack with a bolted collar and a sooted mouth. Vents upward, so it is
    free to exceed the footprint in height — and nothing else."""
    x, y, z = center_base
    assembly.add(material, cylinder(radius, height, center=(x, y, z + height / 2.0)))
    assembly.add("WeldedSteel", cylinder(radius * 1.22, 0.1,
                                         center=(x, y, z + height * 0.35)))
    assembly.add("WeldedSteel", cylinder(radius * 1.3, 0.12,
                                         center=(x, y, z + height - 0.06)))
    assembly.add("Soot", cylinder(radius * 0.86, 0.14,
                                  center=(x, y, z + height - 0.02)))


def hydraulic_ram(assembly: Assembly, center_base, body_length: float,
                  rod_length: float, body_radius: float = 0.17) -> None:
    """A vertical hydraulic cylinder with its rod extended and a copper feed.

    Hydraulics over clockwork: this machinery is powered by pressure, not by
    springs, and that is the single clearest line between dieselpunk and
    steampunk.
    """
    x, y, z = center_base
    assembly.add("CastIron", cylinder(body_radius, body_length,
                                      center=(x, y, z + body_length / 2.0), segments=12))
    assembly.add("WeldedSteel", cylinder(body_radius * 1.2, 0.08,
                                         center=(x, y, z + body_length)))
    assembly.add("OiledSteel", cylinder(body_radius * 0.45, rod_length,
                                        center=(x, y, z + body_length + rod_length / 2.0),
                                        segments=12))
    assembly.add("Copper", cylinder(0.045, body_radius * 2.4,
                                    center=(x, y, z + body_length * 0.22), axis="x",
                                    segments=8))


def pipe_run(assembly: Assembly, points, radius: float = 0.07,
             material: str = "Copper") -> None:
    """Axis-aligned pipework through a list of corner points, with an elbow boss
    at each corner. Steam and coolant plumbing, visible on purpose."""
    points = [Vector(p) for p in points]
    for index in range(len(points) - 1):
        a, b = points[index], points[index + 1]
        delta = b - a
        axis = "xyz"[max(range(3), key=lambda i: abs(delta[i]))]
        length = abs(delta["xyz".index(axis)])
        if length <= 1e-6:
            continue
        assembly.add(material, cylinder(radius, length, center=(a + b) / 2.0,
                                        axis=axis, segments=8))
    for point in points[1:-1]:
        assembly.add(material, cylinder(radius * 1.25, radius * 2.4, center=point,
                                        segments=8))


def access_door(assembly: Assembly, center, size, normal_sign: int = -1,
                face: str = "y") -> None:
    """A bolted inspection hatch with a handle. Human-sized, which is how a
    player reads the scale of everything else on the Machine."""
    width, height = size
    thickness = 0.07
    if face == "y":
        extent = (width, thickness, height)
        handle_axis = "x"
    else:
        extent = (thickness, width, height)
        handle_axis = "y"
    assembly.add("OxideRed", box(extent, center=center, chamfer=0.02))
    nudge = Vector((0.0, normal_sign * thickness * 0.9, 0.0)) if face == "y" \
        else Vector((normal_sign * thickness * 0.9, 0.0, 0.0))
    assembly.add("WeldedSteel", cylinder(0.035, 0.3, center=Vector(center) + nudge,
                                         axis=handle_axis, segments=6))


def catwalk(assembly: Assembly, half_x: float, half_y: float, height: float,
            width: float = 0.5) -> None:
    """A grated walkway and handrail around the top of a tall Machine.

    Tall Machines lose their scale without one. A railing is a human-sized
    object, so it tells the eye how big the rest of the thing is.
    """
    deck = 0.07
    for sy in (-1, 1):
        assembly.add("WeldedSteel",
                     box((half_x * 2 - 0.1, width, deck),
                         center=(0.0, sy * (half_y - width / 2.0 - 0.05), height),
                         chamfer=0.01))
        for sx in (-1, 1):
            assembly.add("WeldedSteel",
                         cylinder(0.035, 0.95,
                                  center=(sx * (half_x - 0.22),
                                          sy * (half_y - 0.1), height + 0.48),
                                  segments=6))
        assembly.add("HazardYellow",
                     box((half_x * 2 - 0.3, 0.05, 0.05),
                         center=(0.0, sy * (half_y - 0.1), height + 0.92),
                         chamfer=0.0))


def port_fitting(assembly: Assembly, port, position_mm, machine) -> None:
    """The visible fitting at a declared port: a hazard-striped collar around a
    sooted throat, recessed into the Machine's flank.

    Recessed, not protruding, because the footprint envelope is hard — a chute
    sticking out over the next tile is exactly the overlap this whole ticket
    exists to prevent. The collar is 1.2 m across inside a 2 m tile, so a Belt
    one tile wide meets it with margin on both sides.
    """
    at = godot_mm_to_blender(position_mm)
    along_x = port.edge in ("north", "south")
    collar, depth, height = 1.2, 0.22, 0.62 if port.direction == "input" else 0.5
    inward = Vector((0.0, -1.0 if port.edge == "north" else 1.0, 0.0)) if along_x \
        else Vector((-1.0 if port.edge == "east" else 1.0, 0.0, 0.0))
    size = (collar, depth, height) if along_x else (depth, collar, height)
    throat = (collar * 0.62, depth, height * 0.6) if along_x \
        else (depth, collar * 0.62, height * 0.6)

    assembly.add("HazardYellow", box(size, center=at + inward * (depth / 2.0),
                                     chamfer=0.03))
    assembly.add("Soot", box(throat, center=at + inward * (depth * 0.95),
                             chamfer=0.02))
    # A short apron under the mouth, so the port reads as a place a Belt docks
    # rather than as a painted rectangle.
    apron = (collar * 0.9, depth * 0.7, 0.07) if along_x else (depth * 0.7, collar * 0.9, 0.07)
    assembly.add("WeldedSteel", box(apron,
                                     center=at + inward * (depth * 0.4) - Vector((0, 0, height / 2.0)),
                                     chamfer=0.02))
    rivets = at + inward * (depth * 0.45)
    if along_x:
        rivet_run(assembly, "WeldedSteel",
                  (rivets.x - collar / 2.0 + 0.07, rivets.y, rivets.z + height / 2.0 - 0.06),
                  (rivets.x + collar / 2.0 - 0.07, rivets.y, rivets.z + height / 2.0 - 0.06),
                  5, radius=0.04, depth=0.05, axis="y")
    else:
        rivet_run(assembly, "WeldedSteel",
                  (rivets.x, rivets.y - collar / 2.0 + 0.07, rivets.z + height / 2.0 - 0.06),
                  (rivets.x, rivets.y + collar / 2.0 - 0.07, rivets.z + height / 2.0 - 0.06),
                  5, radius=0.04, depth=0.05, axis="x")
