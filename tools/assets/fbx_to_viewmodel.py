#!/usr/bin/env python3
"""Convert a first-person arms-and-weapon FBX into a `.glb` the game loads at runtime.

This is the sibling of `fbx_to_gltf.py` and reuses its corrections wholesale —
duplicate images, missing textures, exporter leaf bones, orphan vertices, surplus
UV layers, mangled take names. What it adds is the three things a *viewmodel*
needs and a character does not:

  Takes, not one clip  A `Weapon pack` FBX holds nine to eleven named FBX takes
                       (`Shoot`, `reload`, `Draw`, `PutAway`, `walk`, `run`,
                       `idle`, plus `Pump` and `Chamber`) **plus** a `default`
                       take spanning the whole timeline end to end
                       (docs/LICENSED_ASSETS.md). Each take imports as one action
                       per animated object, named `<object>|<take>|BaseLayer`, and
                       the weapon's own parts — the magazine, the bolt, the
                       trigger — are animated as *objects* rather than as bones.
                       So a take is a group of actions, not one action: each is
                       put on an NLA track named for the take, and the glTF
                       exporter merges same-named tracks into one animation. That
                       is what lands in Godot as an `AnimationPlayer` with
                       `Shoot`, `reload` and the rest on it. `--drop-take` throws
                       `default` away.

  Camera space         A viewmodel is only ever seen from one place: the authoring
                       camera the vendor framed the arms against. `--origin-object
                       Camera001` transforms the whole scene into that camera's
                       space, so the exported model is already in frame when it is
                       parented to Godot's camera at identity. Guessing an offset
                       by hand instead is hours of nudging numbers.

  Weight               `--max-texture` downscales on the way in (the Deagle's
                       three normal maps alone are 180 MB), and `--drop-object`
                       discards what a game does not need — the authoring camera,
                       its controller, and the two of three skin-tone arm meshes
                       that are not being used.

Nothing it reads may be committed and nothing it writes may be either: the packs
forbid redistribution and this repository is public (docs/ASSETS.md). Write the
output somewhere gitignored. `tools/assets/convert_weapons.sh` is the recipe, and
it defaults to the directory `WeaponViewmodel` loads from.

    blender --background --factory-startup --python tools/assets/fbx_to_viewmodel.py -- \
        --input "Weapon pack/L96_animation.fbx" --output /tmp/gear/bolt_rifle.glb \
        --origin-object Camera001 --drop-object Male_mesh --drop-object Female_mesh
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_to_gltf as base  # noqa: E402

REPORT_PREFIX = "[fbx_to_viewmodel]"

## Parts of a take name that name the authoring layer rather than the take.
NOISE = base.ACTION_NAME_NOISE


def log(message):
    print(f"{REPORT_PREFIX} {message}")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(
        prog="fbx_to_viewmodel",
        description="Convert a first-person arms-and-weapon FBX to a runtime .glb.")
    parser.add_argument("--input", required=True, help="source .fbx")
    parser.add_argument("--output", required=True, help="destination .glb")
    parser.add_argument("--scale", type=float, default=1.0,
                        help="uniform scale applied to the result (default 1.0)")
    parser.add_argument("--origin-object", default=None,
                        help="transform the scene into this object's space — the "
                             "authoring camera, so the model arrives in frame")
    parser.add_argument("--origin-frame", type=int, default=1,
                        help="frame at which the origin object's transform is read "
                             "(default 1), because it may itself be animated")
    parser.add_argument("--offset", default="0,0,0",
                        help="x,y,z in metres, applied after --origin-object, in "
                             "Blender world axes: +x right, +y forward, +z up")
    parser.add_argument("--rotate", default="0,0,0",
                        help="x,y,z in degrees, applied after --origin-object")
    parser.add_argument("--drop-object", action="append", default=None,
                        help="delete this object (repeatable). Cameras are dropped "
                             "whether named or not")
    parser.add_argument("--drop-take", action="append", default=None,
                        help="discard this take (repeatable; default: default)")
    parser.add_argument("--parent", action="append", default=None,
                        help="CHILD=PARENT — attach a weapon mesh the FBX left "
                             "loose to the part bone that moves it (repeatable)")
    parser.add_argument("--material-colour", action="append", default=None,
                        help="NAME=RRGGBB[,metallic[,roughness]] — repaint one of "
                             "the model's materials (repeatable). For a pack whose "
                             "textures do not ship, which renders everything white")
    parser.add_argument("--max-texture", type=int, default=1024,
                        help="downscale any texture larger than this, in pixels "
                             "(default 1024); 0 keeps them at source size")
    parser.add_argument("--texture-dir", action="append", default=None,
                        help="directory to search, by file name, for textures the "
                             "FBX references at a path that does not exist")
    parser.add_argument("--keep-uv-layers", type=int, default=1,
                        help="number of UV layers to keep per mesh (default 1)")
    parser.add_argument("--root-bone", default="Root",
                        help="name of the single root bone every root is parented "
                             "under (default Root)")
    parser.add_argument("--no-single-root", action="store_true",
                        help="leave the rig's root bones alone")
    return parser.parse_args(argv)


def vector_arg(text):
    parts = [p for p in text.replace(" ", "").split(",") if p]
    if len(parts) != 3:
        sys.exit(f"{REPORT_PREFIX} expected three comma-separated numbers, got {text!r}")
    return Vector([float(p) for p in parts])


# ---------------------------------------------------------------- takes


def take_of(action_name, object_names):
    """`Bolt|Chamber|BaseLayer` -> `('Bolt', 'Chamber')`.

    The owner is the part naming an object in this scene; the take is the last
    part that names neither an object nor an authoring layer.
    """
    parts = [p.strip() for p in action_name.split("|") if p.strip()]
    owner = next((p for p in parts if p in object_names), None)
    named = [p for p in parts if p not in object_names and p.lower() not in NOISE]
    return owner, (named[-1] if named else None)


def attach_loose_meshes(pairs):
    """Parent a weapon mesh to the part that is supposed to carry it.

    The weapon's body arrives **unparented and unanimated**: the vendor skinned it
    to the weapon part helpers (`Main_Bone`, `ak_main_bn`) rather than to the
    character rig, and an FBX skin cluster over plain helpers is not something
    Blender's importer can reconstruct — so the hands animate, the magazine and
    the bolt animate, and the rifle itself sits on the floor at the world origin.
    Parenting it to the helper that *is* animated puts it back in the hands, and
    the attachment is measured in the rest pose so the offset is the one the
    artist modelled.

    The child's own actions are dropped by the caller: it is rigidly attached now,
    and a leftover take would tear it back off.
    """
    if not pairs:
        return set()
    # No action on anything, so every object sits at the transform the FBX records
    # as its default — which is the bind pose the skin cluster was authored
    # against, and the one frame in which the weapon and its helper agree.
    for obj in bpy.data.objects:
        if obj.animation_data is not None:
            obj.animation_data.action = None
    bpy.context.view_layer.update()
    attached = set()
    for pair in pairs:
        if "=" not in pair:
            sys.exit(f"{REPORT_PREFIX} --parent wants CHILD=PARENT, got {pair!r}")
        child_name, parent_name = pair.split("=", 1)
        child = bpy.data.objects.get(child_name)
        parent = bpy.data.objects.get(parent_name)
        if child is None or parent is None:
            sys.exit(f"{REPORT_PREFIX} --parent {pair!r}: no such object")
        child.parent = parent
        child.matrix_parent_inverse = parent.matrix_world.inverted()
        attached.add(child_name)
        log(f"attached {child_name!r} to {parent_name!r} in the bind pose")
    return attached


def gather_takes(dropped):
    """Group every imported action into `{take: {object name: action}}`."""
    object_names = {o.name for o in bpy.data.objects}
    takes = {}
    for action in bpy.data.actions:
        owner, take = take_of(action.name, object_names)
        if owner is None or take is None:
            log(f"action {action.name!r} names no object of this scene; ignored")
            continue
        if take.lower() in dropped:
            continue
        takes.setdefault(take, {})[owner] = action
    return takes


def action_frame_start(action):
    """The first keyframe in an action, across Blender's action layouts."""
    first = None
    for curve in base.action_fcurves(action):
        for point in curve.keyframe_points:
            if first is None or point.co.x < first:
                first = point.co.x
    return first


def shift_to_frame_one(actions):
    """Slide a take's keyframes so it starts at frame 1.

    A take occupies its own window of one long shared timeline — the AKM's
    `reload` is frames 171 to 249 — and an animation that begins 170 frames in is
    170 frames of nothing in Godot. Every action of the take is shifted by the
    *same* amount, which is the take's own earliest keyframe, so the parts of the
    weapon stay in step with the hands holding it.
    """
    starts = [action_frame_start(a) for a in actions]
    starts = [s for s in starts if s is not None]
    if not starts:
        return 0.0
    delta = min(starts) - 1.0
    if delta == 0.0:
        return 0.0
    for action in actions:
        for curve in base.action_fcurves(action):
            for point in curve.keyframe_points:
                point.co.x -= delta
                point.handle_left.x -= delta
                point.handle_right.x -= delta
            curve.update()
    return delta


def lay_out_nla(takes):
    """Put each take on an NLA track named for it, on every object it animates.

    The glTF exporter's `NLA_TRACKS` mode writes one animation per track and
    merges tracks of the same name across objects, which is the only export mode
    that can express "one animation that moves the hands, the magazine and the
    bolt together".
    """
    for name in sorted(takes):
        by_object = takes[name]
        delta = shift_to_frame_one(list(by_object.values()))
        for object_name in sorted(by_object):
            obj = bpy.data.objects.get(object_name)
            if obj is None:
                continue
            if obj.animation_data is None:
                obj.animation_data_create()
            obj.animation_data.action = None
            track = obj.animation_data.nla_tracks.new()
            track.name = name
            strip = track.strips.new(name, 1, by_object[object_name])
            strip.name = name
        log(f"take {name!r}: {len(by_object)} object(s), shifted by {delta:.0f} frame(s)")


# ---------------------------------------------------------------- scene


def drop_objects(names):
    """Delete objects by name, and every camera whether named or not.

    A camera in the export becomes a `Camera3D` inside the viewmodel, which in
    Godot is a second camera in the scene fighting the first one for the viewport.
    """
    doomed = [o for o in bpy.data.objects if o.name in names or o.type == "CAMERA"]
    for obj in doomed:
        bpy.data.objects.remove(obj, do_unlink=True)
    if doomed:
        log(f"dropped {len(doomed)} object(s)")


def reframe(origin_object, origin_frame, scale, offset, rotate_degrees):
    """Parent everything under one root and put that root in the camera's space.

    A root transform rather than baked object transforms, because every object
    here is *animated*: applying a transform to animated object data moves the
    object and leaves its keyframes where they were.
    """
    inverse = Matrix.Identity(4)
    if origin_object is not None:
        obj = bpy.data.objects.get(origin_object)
        if obj is None:
            sys.exit(f"{REPORT_PREFIX} --origin-object {origin_object!r} is not in this file")
        bpy.context.scene.frame_set(origin_frame)
        bpy.context.view_layer.update()
        # **Position only, deliberately.** The authoring camera's own axes are the
        # FBX's, and which way an FBX camera faces is a convention Blender's
        # importer does not normalise — taking its orientation produced a weapon
        # lying across the view. Its *position* is unambiguous, and the scene
        # around it is already in Blender's world convention (the arms sit at -Y,
        # in front, and +Z is up), which is exactly the frame the glTF exporter's
        # Y-up conversion expects. So: move the camera to the origin, leave the
        # axes alone, and let `--rotate` handle a pack that is not square to its
        # own world.
        inverse = Matrix.Translation(-obj.matrix_world.translation)
        log(f"putting {origin_object!r} at the origin, "
            f"from {tuple(round(v, 3) for v in obj.matrix_world.translation)}")

    transform = (
        Matrix.Translation(offset)
        @ Euler([math.radians(d) for d in rotate_degrees], "XYZ").to_matrix().to_4x4()
        @ Matrix.Diagonal((scale, scale, scale, 1.0))
        @ inverse
    )

    root = bpy.data.objects.new("Viewmodel", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in list(bpy.data.objects):
        if obj is root or obj.parent is not None:
            continue
        # No parent inverse: the root's transform is meant to *apply*, not to be
        # compensated for.
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)
    root.matrix_world = transform
    bpy.context.view_layer.update()
    return root


def repaint_materials(specs):
    """Give a material a base colour, metallic and roughness.

    Several of these packs reference textures they do not ship — the FBX carries
    the authoring machine's paths and the zip carries differently-named files, or
    no files at all — so the arms and the weapon arrive white. A white rifle in
    frame for a whole Run is worse than a tinted one, and a tint is a number in
    this recipe rather than a texture that could never be committed anyway.
    """
    for spec in specs or []:
        if "=" not in spec:
            sys.exit(f"{REPORT_PREFIX} --material-colour wants NAME=RRGGBB, got {spec!r}")
        name, value = spec.split("=", 1)
        parts = value.split(",")
        hexcolour = parts[0].lstrip("#")
        if len(hexcolour) != 6:
            sys.exit(f"{REPORT_PREFIX} --material-colour {spec!r}: want six hex digits")
        # sRGB to linear, the conversion Blender does on a colour picked by eye.
        channels = []
        for i in range(3):
            c = int(hexcolour[i * 2:i * 2 + 2], 16) / 255.0
            channels.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
        metallic = float(parts[1]) if len(parts) > 1 and parts[1] else 0.0
        roughness = float(parts[2]) if len(parts) > 2 and parts[2] else 0.5
        material = bpy.data.materials.get(name)
        if material is None:
            log(f"--material-colour {name!r}: no such material; "
                f"this model has {sorted(m.name for m in bpy.data.materials)}")
            continue
        material.use_nodes = True
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            node.inputs["Base Color"].default_value = (*channels, 1.0)
            node.inputs["Metallic"].default_value = metallic
            node.inputs["Roughness"].default_value = roughness
        log(f"repainted {name!r} #{hexcolour} metallic {metallic} roughness {roughness}")


def downscale_images(limit):
    """Shrink oversized textures. A 17 MB base colour on a weapon held 40 cm from
    the camera is not more detail, it is a longer load."""
    if limit <= 0:
        return
    for image in bpy.data.images:
        width, height = image.size
        if width <= limit and height <= limit:
            continue
        factor = min(limit / float(width), limit / float(height))
        image.scale(max(1, int(width * factor)), max(1, int(height * factor)))
        log(f"downscaled {image.name} from {width}x{height} to {image.size[0]}x{image.size[1]}")


def export_glb(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_force_sampling=True,
        export_def_bones=False,
        export_image_format="AUTO",
        export_materials="EXPORT",
        export_skins=True,
        export_morph=True,
        export_cameras=False,
        export_lights=False,
        use_selection=False,
    )
    log(f"wrote {path}")


def main():
    args = parse_args()
    dropped_takes = {t.lower() for t in (args.drop_take or ["default"])}

    base.import_fbx(args.input, 1.0)

    attached = attach_loose_meshes(args.parent or [])

    takes = gather_takes(dropped_takes)
    for take in takes:
        for name in attached:
            takes[take].pop(name, None)
    if not takes:
        sys.exit(f"{REPORT_PREFIX} {args.input} carried no named takes")
    log(f"takes kept: {sorted(takes)}")
    lay_out_nla(takes)

    root = reframe(args.origin_object, args.origin_frame, args.scale,
                   vector_arg(args.offset), vector_arg(args.rotate))
    drop_objects(set(args.drop_object or []))

    for armature_obj in base.armatures():
        base.strip_exporter_leaf_bones(armature_obj, ("_end",))
        if not args.no_single_root:
            base.unify_root_bones(armature_obj, args.root_bone)
        base.weight_orphan_vertices(armature_obj, args.root_bone)

    base.relocate_missing_images(args.texture_dir or [])
    base.drop_missing_images()
    base.merge_duplicate_images()
    downscale_images(args.max_texture)
    base.pack_images()
    base.prune_uv_layers(args.keep_uv_layers)
    repaint_materials(args.material_colour)

    bounds = [obj.matrix_world @ Vector(corner)
              for obj in base.meshes() for corner in obj.bound_box]
    if bounds:
        lows = Vector([min(b[i] for b in bounds) for i in range(3)])
        highs = Vector([max(b[i] for b in bounds) for i in range(3)])
        log(f"bounds in camera space: {tuple(round(v, 3) for v in lows)} .. "
            f"{tuple(round(v, 3) for v in highs)}")

    export_glb(args.output)


if __name__ == "__main__":
    main()
