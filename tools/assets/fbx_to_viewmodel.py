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
from array import array

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fbx_to_gltf as base  # noqa: E402
import machine_parts  # noqa: E402
import viewmodel_surface  # noqa: E402

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
    parser.add_argument("--material-map", action="append", default=None,
                        help="NAME=CHANNEL:FILE[,CHANNEL:FILE...] — bind the pack's "
                             "own maps to a material's channels (repeatable). "
                             "Channels: " + ", ".join(viewmodel_surface.CHANNELS) +
                             ", normal_dx. A file that is not found is fatal")
    parser.add_argument("--material-surface", action="append", default=None,
                        help="NAME=PALETTE_ENTRY[,METRES_PER_TILE] — dress a material "
                             "in one of dieselpunk_palette.json's generated surfaces, "
                             "with world-scale UVs (repeatable). For the arms and the "
                             "RgsDev rig, which ship no maps at all. The length "
                             "overrides the palette's `texture_scale_m`, which is "
                             "tuned for a Machine read from metres away")
    parser.add_argument("--derived-normal-degrees", type=float, default=9.0,
                        help="mean slope of the normal map derived from a palette "
                             "surface's albedo, in degrees; 0 turns the relief off. "
                             "The slope rather than a multiplier, because the same "
                             "multiplier means five different things across the "
                             "palette's own maps")
    parser.add_argument("--surface-max-texture", type=int, default=512,
                        help="downscale a *palette surface*'s maps to this, in "
                             "pixels (default 512). Lower than --max-texture on "
                             "purpose: see `dress_palette_surfaces`")
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


# ---------------------------------------------------------------- surfaces
#
# #65. Two flags, for the two halves of what the packs actually ship. See
# `viewmodel_surface.py`'s header for the measurement that separates them — the
# short version is that the `Weapon pack` ships a full PBR set for both rifles
# under names the FBX does not reference, and the arms ship nothing at all.


def _principled(material):
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return None


def _material_or_exit(name, flag):
    material = bpy.data.materials.get(name)
    if material is None:
        sys.exit(f"{REPORT_PREFIX} {flag} {name!r}: no such material. This model has "
                 f"{sorted(m.name for m in bpy.data.materials)}")
    return material


def _texture_index(directories):
    """Every file under the search directories, by lower-cased base name."""
    index = {}
    for directory in directories or []:
        for root, _dirs, files in os.walk(directory):
            for name in files:
                index.setdefault(name.lower(), os.path.join(root, name))
    return index


def _resolve_texture(filename, index, directories, material, channel):
    """A path that exists, or exit naming the material, the channel and the file.

    **Fatal rather than reported**, unlike `--material-colour`'s missing material,
    and the asymmetry is deliberate. A colour for a material that is not there
    leaves a surface the recipe was never going to improve. A *map* names a file
    the recipe's author went and found in the pack, so a name that resolves to
    nothing means the recipe and the pack have come apart — and a flat repaint
    quietly standing in for that is the silence this ticket exists to remove
    (#57, #59).
    """
    if os.path.isfile(filename):
        return filename
    found = index.get(os.path.basename(filename).lower())
    if found is not None:
        return found
    where = ", ".join(directories or []) or "(no --texture-dir was given)"
    sys.exit(f"{REPORT_PREFIX} --material-map {material}={channel}:{filename}: "
             f"no such file. Searched: {where}")


def _pixels(image):
    """An image's texels as a flat `array('f')`.

    `foreach_get` rather than `list(image.pixels)`, because these are up to
    2048-square maps: four bytes a channel against a Python float's thirty-two,
    and no second copy. **The values are the file's own** — sRGB-encoded for a
    colour map — which is the measurement `viewmodel_surface`'s header records.
    """
    buffer = array("f", bytes(4 * image.size[0] * image.size[1] * 4))
    image.pixels.foreach_get(buffer)
    return buffer


def _write_pixels(image, values):
    image.pixels.foreach_set(values if isinstance(values, array)
                             else array("f", values))
    image.update()


def _load_map(path, non_colour, limit):
    """Load a map, set its colour space, and cap its size before any pixel maths.

    The cap is applied **here** rather than left to `downscale_images`, because
    everything below reads and rewrites whole images and a 2048-square map is
    four million texels of arithmetic to throw most of away afterwards.
    """
    image = bpy.data.images.load(path, check_existing=False)
    image.colorspace_settings.name = "Non-Color" if non_colour else "sRGB"
    if limit > 0 and (image.size[0] > limit or image.size[1] > limit):
        factor = min(limit / float(image.size[0]), limit / float(image.size[1]))
        image.scale(max(1, int(image.size[0] * factor)),
                    max(1, int(image.size[1] * factor)))
    return image


def _match_size(image, like):
    """Scale one map onto another's grid. The packs ship occlusion at half the
    albedo's resolution, and the pixel maths is per texel."""
    if tuple(image.size) != tuple(like.size):
        image.scale(like.size[0], like.size[1])
    return image


def _new_map(name, width, height, values, non_colour):
    image = bpy.data.images.new(name, width, height, alpha=True)
    image.colorspace_settings.name = "Non-Color" if non_colour else "sRGB"
    _write_pixels(image, values)
    return image


def _texture_node(tree, image, location):
    node = tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    node.location = location
    return node


def _wire_albedo(tree, principled, image):
    tree.links.new(_texture_node(tree, image, (-600, 300)).outputs["Color"],
                   principled.inputs["Base Color"])


def _wire_metallic_roughness(tree, principled, image):
    """One image into both inputs through a `Separate Color`.

    That is the graph Blender's glTF exporter recognises as a
    `metallicRoughnessTexture`, which is the only slot glTF has for either — so
    the combining is done in pixels by `viewmodel_surface` and this is just the
    shape the exporter reads it back out of.
    """
    node = _texture_node(tree, image, (-800, 0))
    separate = tree.nodes.new("ShaderNodeSeparateColor")
    separate.location = (-500, 0)
    tree.links.new(node.outputs["Color"], separate.inputs["Color"])
    tree.links.new(separate.outputs["Green"], principled.inputs["Roughness"])
    tree.links.new(separate.outputs["Blue"], principled.inputs["Metallic"])


def _wire_normal(tree, principled, image):
    node = _texture_node(tree, image, (-800, -300))
    normal_map = tree.nodes.new("ShaderNodeNormalMap")
    normal_map.location = (-500, -300)
    tree.links.new(node.outputs["Color"], normal_map.inputs["Color"])
    tree.links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])


def parse_material_maps(specs):
    """`NAME=CHANNEL:FILE[,CHANNEL:FILE...]` -> `{name: {channel: file}}`."""
    allowed = set(viewmodel_surface.CHANNELS) | {"normal_dx"}
    bindings = {}
    for spec in specs or []:
        if "=" not in spec:
            sys.exit(f"{REPORT_PREFIX} --material-map wants NAME=CHANNEL:FILE, "
                     f"got {spec!r}")
        name, rest = spec.split("=", 1)
        for pair in rest.split(","):
            if ":" not in pair:
                sys.exit(f"{REPORT_PREFIX} --material-map {spec!r}: {pair!r} is not "
                         f"CHANNEL:FILE")
            channel, filename = pair.split(":", 1)
            if channel not in allowed:
                sys.exit(f"{REPORT_PREFIX} --material-map {name}: {channel!r} is not a "
                         f"channel. Try one of {', '.join(sorted(allowed))}")
            bindings.setdefault(name, {})[channel] = filename
    return bindings


def bind_material_maps(specs, texture_dirs, limit):
    """Wire the pack's own maps onto the materials the recipe names."""
    bindings = parse_material_maps(specs)
    if not bindings:
        return set()
    index = _texture_index(texture_dirs)
    for name in sorted(bindings):
        channels = bindings[name]
        material = _material_or_exit(name, "--material-map")
        paths = {channel: _resolve_texture(filename, index, texture_dirs, name, channel)
                 for channel, filename in channels.items()}
        tree = material.node_tree
        principled = _principled(material)
        if principled is None:
            sys.exit(f"{REPORT_PREFIX} --material-map {name!r}: no Principled BSDF to "
                     f"wire a map into")

        if "albedo" in paths:
            albedo = _load_map(paths["albedo"], False, limit)
            if "ao" in paths:
                occlusion = _match_size(
                    _load_map(paths["ao"], True, limit), albedo)
                _write_pixels(albedo, viewmodel_surface.multiply_occlusion(
                    _pixels(albedo), _pixels(occlusion)))
                bpy.data.images.remove(occlusion)
                log(f"{name}: folded {os.path.basename(paths['ao'])} into the albedo")
            _wire_albedo(tree, principled, albedo)

        roughness = (_load_map(paths["roughness"], True, limit)
                     if "roughness" in paths else None)
        metallic = (_load_map(paths["metallic"], True, limit)
                    if "metallic" in paths else None)
        if roughness is not None and metallic is not None:
            _match_size(metallic, roughness)
        if roughness is not None or metallic is not None:
            reference = roughness if roughness is not None else metallic
            combined = _new_map(
                f"{name}_orm", reference.size[0], reference.size[1],
                viewmodel_surface.combine_metallic_roughness(
                    _pixels(roughness) if roughness is not None else None,
                    _pixels(metallic) if metallic is not None else None),
                True)
            for spent in (roughness, metallic):
                if spent is not None:
                    bpy.data.images.remove(spent)
            _wire_metallic_roughness(tree, principled, combined)

        for channel in ("normal", "normal_dx"):
            if channel not in paths:
                continue
            normal = _load_map(paths[channel], True, limit)
            if channel == "normal_dx":
                # The pack says which convention it is in, in the file name.
                _write_pixels(normal, viewmodel_surface.flip_normal_green(
                    _pixels(normal)))
                log(f"{name}: turned {os.path.basename(paths[channel])} from DirectX "
                    f"into glTF's convention")
            _wire_normal(tree, principled, normal)

        log(f"bound {name!r}: {', '.join(sorted(channels))}")
    return set(bindings)


def _world_scale_uvs(obj):
    """Box-project a mesh's UVs at world scale, replacing whatever it had.

    `machine_parts.box_project_uvs`, which is the answer #64 gave the Build Gun
    and every Machine mesh: one UV unit to the metre, projected along each face's
    dominant normal, so a material's `texture_scale_m` is the only thing that sets
    density and there is no layout to maintain.

    **Replacing** rather than adding, because the layouts it replaces are
    unusable: the arms' own unwrap addresses a texture that is in neither pack,
    and the RgsDev knife's has 8280x between its tightest and loosest triangle
    because it was never meant to carry a map. It adds a UV layer and **moves no
    vertex**, which is the line this project draws about an artist's mesh.
    """
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    for layer in list(mesh.loops.layers.uv.keys()):
        mesh.loops.layers.uv.remove(mesh.loops.layers.uv[layer])
    machine_parts.box_project_uvs(mesh)
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()


def dress_palette_surfaces(specs, limit, normal_degrees):
    """Dress a material in one of the palette's generated surfaces.

    The textures are **embedded**, unlike a Machine's, and that is the one
    decision here. A Machine's `.glb` carries its palette flat because Godot's
    importer substitutes a shared `StandardMaterial3D` on import; a viewmodel is
    read at runtime with `GLTFDocument.append_from_file`, so **what is in the
    file is what renders** (#64) and there is no import step to hang a texture on.
    Embedding costs a clone nothing either, because unlike the Build Gun's
    committed model these `.glb`s are gitignored derivatives of a purchased pack.

    **A palette surface is capped smaller than a recovered map, and the two
    numbers are a density measurement rather than a preference.** A palette map
    tiles: at the 0.12 m a glove is given, a 1024-square map is 8,500 texels to
    the metre, where the arms span about 600 pixels of a 1920-wide frame for
    0.4 m of forearm — call it 1,500 pixels to the metre on screen. So 1024 is
    nearly six times oversampled and 512 is still three times. A **recovered**
    map is the opposite case: it is one atlas over the whole weapon, so a
    1024-square map is about 1,100 texels along a 0.9 m rifle, which is already
    *under* what the screen resolves — halving it would be visibly soft. Hence
    `--surface-max-texture` at 512 beside `--max-texture` at 1024, and the
    saving is most of the file: the palette's eight images on the Pneumatic
    Wrench are a quarter of the data at 512.
    """
    dressed = set()
    # One pair of images per palette entry, however many materials wear it. The
    # density lives in each material's own Mapping node, so the *image* depends
    # on nothing but the entry — and the RgsDev rig wears `BeltRubber` on three
    # of its six materials, which was three copies of a 1024-square albedo and
    # three of its derived normal inside one `.glb` before this cache existed.
    built: dict[str, tuple] = {}
    for spec in specs or []:
        if "=" not in spec:
            sys.exit(f"{REPORT_PREFIX} --material-surface wants NAME=PALETTE_ENTRY, "
                     f"got {spec!r}")
        name, rest = spec.split("=", 1)
        entry, _, override = rest.partition(",")
        material = _material_or_exit(name, "--material-surface")
        try:
            surface = viewmodel_surface.palette_surface(entry)
        except KeyError as error:
            sys.exit(f"{REPORT_PREFIX} --material-surface {spec!r}: {error.args[0]}")
        if override:
            # The palette's own figure is "metres across one tile **on a Machine**",
            # which is an object read from metres away. A viewmodel is 40 cm from
            # the eye, so the recipe may restate the density for this distance —
            # and only the density: the colour, the metallic, the roughness and
            # which map it is all stay the palette's.
            try:
                metres = float(override)
            except ValueError:
                sys.exit(f"{REPORT_PREFIX} --material-surface {spec!r}: {override!r} is "
                         f"not a length in metres")
            if metres <= 0.0:
                sys.exit(f"{REPORT_PREFIX} --material-surface {spec!r}: a tile cannot "
                         f"be {metres} m across")
            surface = dict(surface, texture_scale_m=metres)
        if not surface["texture"].exists():
            sys.exit(f"{REPORT_PREFIX} --material-surface {spec!r}: the palette names "
                     f"{surface['texture']}, which is not there. Run tools/aigen.")

        for obj in base.meshes():
            if any(slot.material is material for slot in obj.material_slots):
                _world_scale_uvs(obj)

        if entry in built:
            albedo, derived_normal = built[entry]
        else:
            albedo = _load_map(str(surface["texture"]), False, limit)
            # **The relief comes off the map as shipped, before it is levelled**,
            # and the order is load-bearing: levelling scales the whole map down
            # towards a dark `base_color`, which scales its gradients down with
            # it. Measured on `olive_drab_paint`, deriving after costs 40% of the
            # slope — 0.73 degrees against 1.25 at the same setting, both of
            # which are invisible, which is how the ordering went unnoticed until
            # the slope was measured in degrees rather than eyeballed.
            relief = (None if normal_degrees <= 0.0 else
                      viewmodel_surface.normal_from_albedo(
                          _pixels(albedo), albedo.size[0], albedo.size[1],
                          normal_degrees))
            # Levelled to the palette's `base_color`, **not** multiplied by its
            # `texture_tint`. The tint is the knob for a Machine read from
            # metres away; dressed at it, the gloves measured 129 against a
            # ground of 81, which is #64's brightened tool again. The level that
            # is known to read in the hand is the flat one the Build Gun and the
            # Wall wear, so the map keeps its grain and goes back to that.
            #
            # Baked into the texels rather than left as a `baseColorFactor`,
            # which was tried: Blender's glTF exporter writes [1,1,1,1] for a
            # linked Base Color whatever node stands in front of it.
            _write_pixels(albedo, viewmodel_surface.level_albedo(
                _pixels(albedo), surface["base_color"][:3]))
            albedo.name = f"{entry}_albedo"
            # The generated set is albedo-only, so the relief is derived rather
            # than loaded — #42's answer on the ground, with the height field
            # already in hand.
            derived_normal = (None if relief is None else _new_map(
                f"{entry}_normal", albedo.size[0], albedo.size[1], relief, True))
            built[entry] = (albedo, derived_normal)

        tree = material.node_tree
        principled = _principled(material)
        if principled is None:
            sys.exit(f"{REPORT_PREFIX} --material-surface {name!r}: no Principled BSDF")
        principled.inputs["Metallic"].default_value = surface["metallic"]
        principled.inputs["Roughness"].default_value = surface["roughness"]

        node = _texture_node(tree, albedo, (-600, 300))
        # The UVs are in metres and the density is per material, so the scale has
        # to live here: two materials of different `texture_scale_m` share one UV
        # layer on the RgsDev meshes, which a baked-in scale could not express.
        mapping = tree.nodes.new("ShaderNodeMapping")
        mapping.location = (-900, 300)
        scale = 1.0 / surface["texture_scale_m"]
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        coords = tree.nodes.new("ShaderNodeUVMap")
        coords.uv_map = machine_parts.UV_LAYER
        coords.location = (-1100, 300)
        tree.links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        tree.links.new(mapping.outputs["Vector"], node.inputs["Vector"])

        tree.links.new(node.outputs["Color"], principled.inputs["Base Color"])

        if derived_normal is not None:
            normal_node = _texture_node(tree, derived_normal, (-800, -300))
            tree.links.new(mapping.outputs["Vector"], normal_node.inputs["Vector"])
            normal_map = tree.nodes.new("ShaderNodeNormalMap")
            normal_map.location = (-500, -300)
            tree.links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
            tree.links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])

        dressed.add(name)
        log(f"dressed {name!r} in {entry} at {surface['texture_scale_m']} m a tile")
    return dressed


def refuse_two_authorities(maps, surfaces, colours):
    """A material gets one surface, from one flag.

    The texture wins in Blender and the factor is what a glTF reader sees, so two
    flags on one material can disagree silently — which is exactly the
    disagreement `query_build_refusal` exists to prevent everywhere else in this
    project. A recipe that says both has not decided.
    """
    named = {}
    for flag, group in (("--material-map", maps),
                        ("--material-surface", surfaces),
                        ("--material-colour", colours)):
        for name in group:
            named.setdefault(name, []).append(flag)
    for name in sorted(named):
        if len(named[name]) > 1:
            sys.exit(f"{REPORT_PREFIX} {name!r} is given a surface by "
                     f"{' and '.join(named[name])}. Pick one: a texture wins in "
                     f"Blender and a factor is what a glTF reader sees, so the two "
                     f"can disagree without anything saying so.")


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

    # #65. The surfaces, before the pack and the pruning, and in this order for
    # two reasons. `prune_uv_layers` keeps the *first* layer, so the world-scale
    # one a palette surface projects has to be the only one by the time it runs;
    # and `--material-colour` is the fallback for a pack with neither a map nor a
    # palette entry, so it stays last and is refused outright on any material the
    # other two flags have already dressed.
    colours = {spec.split("=", 1)[0] for spec in (args.material_colour or [])
               if "=" in spec}
    refuse_two_authorities(parse_material_maps(args.material_map),
                           {spec.split("=", 1)[0]
                            for spec in (args.material_surface or []) if "=" in spec},
                           colours)
    bind_material_maps(args.material_map, args.texture_dir or [], args.max_texture)
    dress_palette_surfaces(args.material_surface, args.surface_max_texture,
                           args.derived_normal_degrees)

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
