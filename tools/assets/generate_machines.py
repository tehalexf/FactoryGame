#!/usr/bin/env python3
"""Generate every Machine mesh from the declaration, headless, in Blender.

Run through `tools/assets/generate_machines.sh`, which supplies the Blender
invocation. Directly:

    blender --background --factory-startup \
        --python tools/assets/generate_machines.py -- --output-dir assets/machines

There is no interactive step anywhere in here, and nothing is read from a saved
`.blend`. The inputs are `content/machines.csv`, `content/machine_ports.csv`,
`dieselpunk_palette.json` and the recipes — so changing a footprint and re-running
is the entire workflow for changing a Machine's size.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bmesh  # type: ignore
import bpy  # type: ignore

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import machine_parts as parts  # noqa: E402
import machine_recipes as recipes  # noqa: E402
import machine_specs  # noqa: E402

PALETTE_JSON = HERE / "dieselpunk_palette.json"


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Arguments after Blender's `--` separator."""
    after = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="generate_machines.py",
                                     description=__doc__.splitlines()[0])
    parser.add_argument("--output-dir", default="assets/machines",
                        help="where the .glb files are written")
    parser.add_argument("--bodies-csv", default=None,
                        help="override content/machine_bodies.csv (used by the "
                             "tests to prove a changed parameter re-runs cleanly)")
    parser.add_argument("--ports-csv", default=None,
                        help="override content/machine_ports.csv")
    parser.add_argument("--machines-csv", default=None,
                        help="override content/machines.csv, the Simulation's own "
                             "Machine table and the authority on footprints")
    parser.add_argument("--only", action="append", default=None, metavar="MACHINE_ID",
                        help="generate just these Machines; repeatable")
    return parser.parse_args(after)


def load_palette() -> dict[str, bpy.types.Material]:
    """Build the shared palette as real Blender materials, once per run.

    Flat Principled BSDF with no texture nodes: these are procedural meshes and
    texturing is a separate ticket. The numbers come from the palette file so the
    same values reach every Machine, which is the only way a palette stays shared.
    """
    declared = json.loads(PALETTE_JSON.read_text())["materials"]
    built: dict[str, bpy.types.Material] = {}
    for entry in declared:
        material = bpy.data.materials.new(entry["name"])
        # New materials arrive node-backed in Blender 4.x and later, and
        # `use_nodes` is slated for removal in 6.0, so it is not set here.
        principled = material.node_tree.nodes["Principled BSDF"]
        principled.inputs["Base Color"].default_value = tuple(entry["base_color"])
        principled.inputs["Metallic"].default_value = entry["metallic"]
        principled.inputs["Roughness"].default_value = entry["roughness"]
        built[entry["name"]] = material
    return built


def clear_scene() -> None:
    """A genuinely empty scene, so one Machine cannot leak into the next.

    `--factory-startup` gives a clean Blender, not a clean scene between
    Machines, and a leaked object would show up as a footprint that is subtly too
    big — which the suite would catch, but after a confusing hour.

    Materials are deliberately *not* cleared: they are the shared palette and
    outlive every Machine.
    """
    for collection in (bpy.data.objects, bpy.data.meshes):
        for item in list(collection):
            collection.remove(item, do_unlink=True)


def build_machine(machine, palette: dict[str, bpy.types.Material]) -> None:
    """Assemble one Machine into the current scene, origin at footprint centre.

    The shared shell — plinth, corner posts, port fittings — is added here rather
    than in each recipe, because it is what makes every Machine look like it came
    out of the same factory, and because the plinth and posts are what pin the
    mesh's extents to the declared footprint.
    """
    half_x_mm, half_z_mm = machine.half_extent_mm()
    half_x, half_y = half_x_mm / 1000.0, half_z_mm / 1000.0
    assembly = parts.Assembly()

    if recipes.needs_standard_shell(machine):
        parts.plinth(assembly, half_x, half_y)
        parts.corner_posts(assembly, "CastIron", half_x, half_y,
                           recipes.housing_height(machine) + 0.15)

    recipes.build(machine, assembly)

    if recipes.needs_port_fittings(machine):
        for port in machine.ports:
            parts.port_fitting(assembly, port,
                               machine_specs.port_position_mm(machine, port), machine)

    # One object per material, created in palette order so the glTF's node,
    # mesh and material arrays come out in the same order on every run. Byte
    # reproducibility is what makes re-running the generator a reviewable diff
    # rather than noise.
    for name in assembly.materials():
        mesh_data = bpy.data.meshes.new(f"{machine.machine_id}_{name}")
        mesh = assembly.take(name)
        bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
        mesh.to_mesh(mesh_data)
        mesh.free()
        mesh_data.materials.append(palette[name])
        # Flat-shaded: the chamfers are the only highlight these meshes get, and
        # smooth shading would round off the cast-iron edges that carry the look.
        for polygon in mesh_data.polygons:
            polygon.use_smooth = False
        obj = bpy.data.objects.new(f"{machine.machine_id}_{name}", mesh_data)
        bpy.context.scene.collection.objects.link(obj)

    # Port markers last, so they sort after the geometry nodes deterministically.
    for port in machine.ports:
        marker = bpy.data.objects.new(machine_specs.port_node_name(port), None)
        marker.empty_display_type = 'ARROWS'
        marker.empty_display_size = 0.5
        marker.location = parts.godot_mm_to_blender(
            machine_specs.port_position_mm(machine, port))
        bpy.context.scene.collection.objects.link(marker)


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format='GLB',
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_materials='EXPORT',
        export_image_format='NONE',
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_extras=False,
        use_visible=False,
        use_selection=False,
    )


def main() -> int:
    args = parse_args(sys.argv)
    machines = machine_specs.load(
        bodies_source=Path(args.bodies_csv).read_text() if args.bodies_csv else None,
        ports_source=Path(args.ports_csv).read_text() if args.ports_csv else None,
        machines_source=Path(args.machines_csv).read_text() if args.machines_csv else None,
    )
    if args.only:
        wanted = set(args.only)
        unknown = wanted - {m.machine_id for m in machines}
        if unknown:
            raise SystemExit(f"error: no such Machine: {', '.join(sorted(unknown))}")
        machines = [m for m in machines if m.machine_id in wanted]

    missing = sorted({m.body for m in machines} - recipes.KNOWN_BODIES)
    if missing:
        raise SystemExit(
            f"error: content/machine_bodies.csv names bodies with no mesh recipe: "
            f"{', '.join(missing)}. Add one to tools/assets/machine_recipes.py.")

    # Built once for the whole run, not once per Machine: Blender renames a
    # second material called CastIron to CastIron.001, and a palette whose names
    # drift per file is not a shared palette.
    palette = load_palette()

    output_dir = Path(args.output_dir)
    for machine in machines:
        clear_scene()
        build_machine(machine, palette)
        destination = output_dir / f"{machine.machine_id}.glb"
        export(destination)
        width, depth = machine.footprint_mm()
        authority = "machines.csv" if machine.footprint_from_simulation \
            else "machine_bodies.csv"
        print(f"  {machine.machine_id:<18} {machine.footprint_x}x{machine.footprint_z} "
              f"tiles ({width/1000:g} m x {depth/1000:g} m) per {authority}, "
              f"{len(machine.ports)} port(s) -> {destination}")
    print(f"generated {len(machines)} Machine mesh(es) into {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
