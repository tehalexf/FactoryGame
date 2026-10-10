#!/usr/bin/env python3
"""Render every committed Machine as a contact sheet, so readability is checkable.

Run through `tools/assets/render_machines.sh`. Two sheets, and the first one is
the gate:

* **silhouette** — every Machine as flat black on white, orthographic, side by
  side, with a 1.8 m figure for scale. This is the hard way to judge a Machine:
  if two of them are ambiguous in black, no amount of surface detail will tell
  them apart across a Factory floor. The committed sheet is what makes the
  readability claim re-checkable after any later change to the generator.
* **lit** — the same row with a sun and the real materials, which is what the
  player sees. A Machine whose textures are applied shows them here; one whose
  mesh carries no UVs falls back to flat palette colour, which is exactly how
  the flat-shaded "before" state looks.

It reads the committed `.glb` files rather than calling the generator, so the
sheet is a picture of the shipped artifact.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy  # type: ignore

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import machine_materials  # noqa: E402

#: Clear space between two Machines on the sheet, in metres. Wide enough that two
#: neighbouring silhouettes never touch and get read as one object.
GAP_M = 2.0

#: How tall a slice of the world the sheet shows, in metres. The tallest Machine
#: plus headroom plus the strip the labels are written in.
VIEW_TOP_M = 11.5
LABEL_BAND_M = 2.2

#: Pixels per metre on the sheet. 34 puts a 4 m Machine at 136 px across, which
#: is about what it subtends on screen at the distance this judgement is about.
PIXELS_PER_METRE = 34


def parse_args(argv: list[str]) -> argparse.Namespace:
    after = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_machines.py",
                                     description=__doc__.splitlines()[0])
    parser.add_argument("--machine-dir", default="assets/machines")
    parser.add_argument("--output", required=True, help="the .png to write")
    parser.add_argument("--mode", choices=("silhouette", "lit"), default="silhouette")
    parser.add_argument("--view", choices=("front", "side"), default="front",
                        help="front looks along the Belt line, side looks across it")
    parser.add_argument("--only", action="append", default=None, metavar="MACHINE_ID")
    parser.add_argument("--pixels-per-metre", type=int, default=PIXELS_PER_METRE,
                        help="raise it with --only to inspect one Machine close up")
    return parser.parse_args(after)


def clear_scene() -> None:
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                       bpy.data.images, bpy.data.curves):
        for item in list(collection):
            collection.remove(item, do_unlink=True)


def import_machine(path: Path) -> list[bpy.types.Object]:
    """Every mesh object out of one `.glb`, joined into one list.

    glTF import gives +Y up already, which is Blender's +Z up after the
    importer's own conversion, so the objects arrive standing on z=0 exactly as
    the generator built them.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    fresh = [o for o in bpy.data.objects if o not in before]
    for obj in fresh:
        obj.select_set(False)
    return fresh


def reference_figure() -> bpy.types.Object:
    """A 1.8 m blockout of a person. Not a character — a ruler.

    Scale is the mistake procedural geometry makes silently, so every sheet
    carries the thing the sizes are supposed to be judged against.
    """
    import bmesh  # type: ignore
    mesh = bmesh.new()

    def slab(size, center):
        cube = bmesh.new()
        bmesh.ops.create_cube(cube, size=1.0)
        bmesh.ops.scale(cube, vec=size, verts=cube.verts)
        bmesh.ops.translate(cube, vec=center, verts=cube.verts)
        scratch = bpy.data.meshes.new("__ref__")
        cube.to_mesh(scratch)
        cube.free()
        mesh.from_mesh(scratch)
        bpy.data.meshes.remove(scratch)

    slab((0.42, 0.24, 0.80), (0.0, 0.0, 1.22))      # torso
    slab((0.22, 0.20, 0.24), (0.0, 0.0, 1.74))      # head
    slab((0.16, 0.16, 0.84), (-0.11, 0.0, 0.42))    # legs
    slab((0.16, 0.16, 0.84), (0.11, 0.0, 0.42))
    slab((0.10, 0.10, 0.62), (-0.26, 0.0, 1.25))    # arms
    slab((0.10, 0.10, 0.62), (0.26, 0.0, 1.25))
    data = bpy.data.meshes.new("ScaleFigure")
    mesh.to_mesh(data)
    mesh.free()
    obj = bpy.data.objects.new("ScaleFigure", data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ground_strip(width: float, center_x: float) -> bpy.types.Object:
    """A hairline at z=0, so a Machine reads as standing rather than floating."""
    import bmesh  # type: ignore
    mesh = bmesh.new()
    bmesh.ops.create_cube(mesh, size=1.0)
    bmesh.ops.scale(mesh, vec=(width, 0.6, 0.05), verts=mesh.verts)
    bmesh.ops.translate(mesh, vec=(center_x, 0.0, -0.025), verts=mesh.verts)
    data = bpy.data.meshes.new("Ground")
    mesh.to_mesh(data)
    mesh.free()
    obj = bpy.data.objects.new("Ground", data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def label(text: str, center_x: float, top_z: float) -> bpy.types.Object:
    """A Machine's id under its silhouette, so the sheet needs no key."""
    curve = bpy.data.curves.new(type="FONT", name=f"label_{text}")
    curve.body = text
    curve.size = 0.62
    curve.align_x = 'CENTER'
    curve.align_y = 'TOP'
    obj = bpy.data.objects.new(f"label_{text}", curve)
    obj.location = (center_x, 0.0, top_z)
    obj.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def configure_silhouette(scene, width: float, height: float) -> None:
    """Workbench, flat, one colour: a true silhouette with no sampling noise.

    Deliberately not a lit render with a black material — Workbench's flat single
    colour cannot be rescued by a rim light or a bounce, so what comes out is the
    outline and nothing else.
    """
    scene.render.engine = 'BLENDER_WORKBENCH'
    shading = scene.display.shading
    shading.light = 'FLAT'
    shading.color_type = 'SINGLE'
    shading.single_color = (0.0, 0.0, 0.0)
    shading.show_specular_highlight = False
    shading.background_type = 'VIEWPORT'
    shading.background_color = (1.0, 1.0, 1.0)
    scene.display.render_aa = '8'
    scene.view_settings.view_transform = 'Standard'


def configure_lit(scene) -> None:
    """A single hard sun and a dim sky: the Factory's own lighting, roughly.

    Hard because the chamfers on these meshes are the whole highlight scheme and
    a soft studio light flattens them into the box they are trying not to be.
    """
    for candidate in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            scene.render.engine = candidate
            break
        except TypeError:
            continue
    world = bpy.data.worlds.new("Sheet")
    scene.world = world
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.32, 0.36, 0.42, 1.0)
    background.inputs["Strength"].default_value = 0.55
    sun_data = bpy.data.lights.new("Sun", type='SUN')
    sun_data.energy = 2.6
    sun_data.angle = 0.03
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(58.0), math.radians(8.0), math.radians(-36.0))
    scene.collection.objects.link(sun)
    # Standard rather than a filmic transform: Godot's default tonemapper is
    # linear, and the point of this sheet is to show what the engine will show.
    scene.view_settings.view_transform = 'Standard'


def main() -> int:
    args = parse_args(sys.argv)
    machine_dir = Path(args.machine_dir)
    paths = sorted(machine_dir.glob("*.glb"))
    if args.only:
        wanted = set(args.only)
        paths = [p for p in paths if p.stem in wanted]
    if not paths:
        raise SystemExit(f"error: no .glb files in {machine_dir}")

    clear_scene()
    from mathutils import Vector  # type: ignore

    textured = args.mode == "lit"
    materials = machine_materials.build_blender_materials(textured=textured)

    # Start inside the frame: the label under the first Machine is wider than the
    # Machine, and a clipped caption is a sheet nobody can read the ends of.
    cursor = GAP_M
    centres: list[tuple[str, float]] = []
    for path in paths:
        objects = import_machine(path)
        meshes = [o for o in objects if o.type == 'MESH']
        # The `side` view is had by spinning each Machine a quarter turn rather
        # than by moving the camera, so one row shows whichever profile is being
        # judged without the layout changing. Measured after the turn, because a
        # Machine that is 4 m by 6 m is a different width once it is round.
        if args.view == "side":
            for obj in objects:
                # The glTF importer leaves objects in quaternion rotation mode,
                # where `rotation_euler` is stored and silently ignored — which
                # renders a "side" sheet that is identical to the front one and
                # looks like the Machines really are that symmetrical.
                obj.rotation_mode = 'XYZ'
                obj.rotation_euler = (0.0, 0.0, math.pi / 2.0)
            bpy.context.view_layer.update()
        lo_x, hi_x = math.inf, -math.inf
        for obj in meshes:
            for corner in obj.bound_box:
                world = obj.matrix_world @ Vector(corner)
                lo_x = min(lo_x, world.x)
                hi_x = max(hi_x, world.x)
        shift = cursor - lo_x
        for obj in objects:
            obj.location.x += shift
        centre = shift + (lo_x + hi_x) / 2.0
        centres.append((path.stem, centre))
        for obj in meshes:
            obj.data.materials.clear()
            name = obj.name.rsplit("_", 1)[-1]
            obj.data.materials.append(materials.get(name, materials["CastIron"]))
        cursor += (hi_x - lo_x) + GAP_M

    figure = reference_figure()
    figure.location.x = cursor
    cursor += 0.9 + GAP_M

    total = cursor
    centre_x = total / 2.0
    furniture = [ground_strip(total, centre_x)]
    for machine_id, at in centres:
        furniture.append(label(machine_id, at, -0.5))
    furniture.append(label("1.8 m", figure.location.x, -0.5))

    scene = bpy.context.scene
    if args.mode == "silhouette":
        configure_silhouette(scene, total, VIEW_TOP_M + LABEL_BAND_M)
    else:
        configure_lit(scene)
        # The sheet's own furniture is not part of the Factory, so it is lit by
        # nothing and reads the same whatever the sun is doing.
        caption = bpy.data.materials.new("Caption")
        emission = caption.node_tree.nodes["Principled BSDF"]
        emission.inputs["Emission Color"].default_value = (0.92, 0.93, 0.95, 1.0)
        emission.inputs["Emission Strength"].default_value = 1.0
        emission.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        for obj in furniture:
            obj.data.materials.clear()
            obj.data.materials.append(caption)

    camera_data = bpy.data.cameras.new("Sheet")
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = total
    camera = bpy.data.objects.new("Sheet", camera_data)
    camera.location = (centre_x, -60.0, (VIEW_TOP_M - LABEL_BAND_M) / 2.0)
    camera.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    scene.collection.objects.link(camera)
    scene.camera = camera

    height_m = VIEW_TOP_M + LABEL_BAND_M
    scene.render.resolution_x = int(total * args.pixels_per_metre)
    scene.render.resolution_y = int(height_m * args.pixels_per_metre)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.compression = 90
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print(f"rendered {len(paths)} Machine(s) ({args.mode}, {args.view}) -> {out} "
          f"at {scene.render.resolution_x}x{scene.render.resolution_y}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
