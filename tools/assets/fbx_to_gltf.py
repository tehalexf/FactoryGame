#!/usr/bin/env python3
"""Convert an intake FBX into a shipping glTF 2.0 `.glb`, correcting the known
breakages on the way.

FBX is an intake format only (docs/ASSETS.md). This script is the whole
conversion path: it runs inside Blender, headless, and is the only sanctioned way
an FBX becomes something the game loads.

    blender --background --factory-startup --python tools/assets/fbx_to_gltf.py -- \
        --input Skeleton.fbx --output assets/characters/skeleton/Skeleton.glb \
        --target-height 1.8 --root-bone Root \
        --bone-map tools/assets/bone_maps/quaternius_monsters.json

Or, more conveniently, `tools/assets/convert_fbx.sh --input ... --output ...`.

What it corrects, and why each one bites:

  Multiple root bones   Exported rigs often leave weapon sockets, prop handles
                        or an extra "Armature" bone unparented. Godot's
                        retargeting and most animation tooling assume a single
                        root, so every stray root is reparented under one root
                        bone.

  Scale conventions     Unity-targeted FBX is commonly authored in centimetres
                        (100x) and arrives either 100x too large or 0.01x too
                        small. `--scale` applies a known factor; `--target-height`
                        normalises to a measured height when the factor is not
                        known. Scale is then *applied*, not left on the object,
                        so nothing downstream inherits it.

  Axis conventions      Unity and Unreal exports leave a residual rotation (very
                        often 180 degrees about Z, the Z-up/Y-up and
                        forward-axis mismatch) on the armature. Transforms are
                        baked so every exported object transform is identity and
                        the glTF exporter's +Y-up conversion is the only axis
                        change that happens.

  Duplicated textures   The FBX importer creates one image datablock per texture
                        reference, so the same PNG arrives two or three times
                        (`skin.png`, `skin.png.001`). Images are merged by
                        resolved path and by content hash, and identical
                        materials are merged, so the `.glb` embeds each texture
                        once. FBX routinely carries absolute authoring paths such
                        as `C:/Dropbox/.../T_Skin.png`: `--texture-dir` finds
                        those files by name, and anything still missing is
                        dropped rather than exported as a broken reference.

  Invented joints       Blender's glTF exporter answers unweighted vertices by
                        inventing a joint called `neutral_bone`, which quietly
                        gives the rig a second skeleton root. Orphan vertices are
                        weighted to the root bone instead.

  Mangled take names    FBX takes import as `Armature|Armature|Walk`, which is
                        what Godot then shows in the AnimationPlayer. Prefixes
                        are stripped so animation names are the names artists
                        used.

  Rig divergence        `--bone-map` renames bones onto the shared humanoid
                        skeleton (Godot's SkeletonProfileHumanoid names; see
                        docs/ASSET_PIPELINE.md) so animation is interchangeable
                        between characters. Bones the map does not mention are
                        kept and reported, never silently renamed.
"""

import argparse
import hashlib
import json
import os
import sys

import bpy
from mathutils import Vector

REPORT_PREFIX = "[fbx_to_gltf]"


def log(message):
    print(f"{REPORT_PREFIX} {message}")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(
        prog="fbx_to_gltf",
        description="Convert an intake FBX to a shipping glTF 2.0 .glb.")
    parser.add_argument("--input", required=True, help="source .fbx")
    parser.add_argument("--output", required=True, help="destination .glb")
    parser.add_argument("--scale", type=float, default=1.0,
                        help="uniform scale applied on import (Unity centimetres: 0.01)")
    parser.add_argument("--target-height", type=float, default=None,
                        help="normalise the model to this height in metres, "
                             "overriding --scale")
    parser.add_argument("--root-bone", default="Root",
                        help="name of the single root bone all roots are parented "
                             "under (default: Root, matching SkeletonProfileHumanoid)")
    parser.add_argument("--bone-map", default=None,
                        help="JSON object mapping source bone names to shared "
                             "humanoid skeleton bone names")
    parser.add_argument("--keep-uv-layers", type=int, default=1,
                        help="number of UV layers to keep per mesh (default 1); "
                             "0 keeps all of them")
    parser.add_argument("--texture-dir", action="append", default=None,
                        help="directory to search, by file name, for textures the "
                             "FBX references at a path that does not exist "
                             "(repeatable)")
    parser.add_argument("--leaf-bone-suffix", action="append", default=None,
                        help="delete childless bones with this suffix (exporter "
                             "padding; default: _end). Repeatable; pass "
                             "--leaf-bone-suffix '' to keep them all")
    parser.add_argument("--no-single-root", action="store_true",
                        help="leave root bones alone (for non-skeletal props)")
    return parser.parse_args(argv)


# ---------------------------------------------------------------- import


def import_fbx(path, scale):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path, global_scale=scale,
                             automatic_bone_orientation=False,
                             use_anim=True,
                             # Keep every bone: Blender's leaf-bone filter also
                             # discards genuine end-of-chain bones. Exporter
                             # padding is removed by name instead, below.
                             ignore_leaf_bones=False)
    log(f"imported {path} with global_scale={scale}")


def armatures():
    return [o for o in bpy.data.objects if o.type == "ARMATURE"]


def meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


# ---------------------------------------------------------------- scale / axis


def model_height():
    """World-space height (Blender Z) of every mesh together."""
    lowest, highest = float("inf"), float("-inf")
    for obj in meshes():
        for corner in obj.bound_box:
            z = (obj.matrix_world @ Vector(corner)).z
            lowest, highest = min(lowest, z), max(highest, z)
    return 0.0 if lowest == float("inf") else highest - lowest


def scale_scene(factor):
    for obj in bpy.data.objects:
        if obj.parent is None:
            obj.scale = [component * factor for component in obj.scale]
            obj.location = obj.location * factor
    bpy.context.view_layer.update()


def bake_transforms():
    """Apply every object's rotation and scale so exported transforms are identity.

    This is what removes the residual 180-degree Z rotation and the 100x/0.01x
    scale that Unity- and Unreal-targeted FBX leave on the armature. Scale and
    rotation are applied; location is left alone so a character keeps its origin.
    """
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    if not bpy.context.selected_objects:
        return
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True,
                                   isolate_users=True)
    log("baked rotation and scale into mesh and armature data")


# ---------------------------------------------------------------- rig


def unify_root_bones(armature_obj, root_name):
    """Parent every root bone under one root bone, creating it if necessary."""
    data = armature_obj.data
    roots = [bone.name for bone in data.bones if bone.parent is None]
    if roots == [root_name]:
        log(f"single root bone already: {root_name!r}")
        return
    log(f"root bones found: {roots}")

    bpy.context.view_layer.objects.active = armature_obj
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = data.edit_bones

    if root_name in edit_bones:
        root = edit_bones[root_name]
    else:
        root = edit_bones.new(root_name)
        # A short bone at the armature origin, pointing up: a neutral parent that
        # does not move anything, because no vertex is weighted to it.
        root.head = (0.0, 0.0, 0.0)
        root.tail = (0.0, 0.0, 0.1)
        root.use_connect = False
    for name in roots:
        if name == root_name:
            continue
        bone = edit_bones[name]
        bone.parent = root
        bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    remaining = [bone.name for bone in data.bones if bone.parent is None]
    log(f"root bones after unification: {remaining}")


def action_fcurves(action):
    """Every fcurve in an action, across Blender's action layouts.

    Blender 4.4 moved actions to layers/strips/channelbags (slotted actions) and
    dropped `Action.fcurves`. Supporting both keeps this script working on the
    Blender an artist happens to have.
    """
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                curves.extend(bag.fcurves)
    return curves


def strip_exporter_leaf_bones(armature_obj, suffixes):
    """Delete childless bones that are exporter padding, e.g. `Head_end`.

    FBX exporters append a terminal bone to every chain so the chain has a
    length. They weight nothing, and Godot shows them as extra skeleton bones.
    Only childless bones whose names end with one of `suffixes` are removed, so
    real end-of-chain bones survive.
    """
    data = armature_obj.data
    doomed = [bone.name for bone in data.bones
              if not bone.children and any(bone.name.endswith(s) for s in suffixes)]
    if not doomed:
        return []
    bpy.context.view_layer.objects.active = armature_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name in doomed:
        bone = data.edit_bones.get(name)
        if bone is not None:
            data.edit_bones.remove(bone)
    bpy.ops.object.mode_set(mode="OBJECT")
    log(f"removed {len(doomed)} exporter leaf bone(s): {sorted(doomed)}")
    return doomed


def weight_orphan_vertices(armature_obj, fallback_bone=None):
    """Give every vertex of a skinned mesh at least one bone weight.

    Blender's glTF exporter handles unweighted vertices by inventing a joint
    called `neutral_bone`, which silently gives the exported rig a second
    skeleton root. Binding the orphans to a real bone — the first root bone
    unless told otherwise — keeps the rig single-rooted and the mesh attached.
    """
    bone_names = {bone.name for bone in armature_obj.data.bones}
    if not bone_names:
        return 0
    target = fallback_bone
    if target not in bone_names:
        roots = [b.name for b in armature_obj.data.bones if b.parent is None]
        target = roots[0] if roots else next(iter(bone_names))

    adopted = 0
    for mesh_obj in meshes():
        if not any(m.type == "ARMATURE" and m.object is armature_obj
                   for m in mesh_obj.modifiers):
            continue
        bone_group_indices = {g.index for g in mesh_obj.vertex_groups
                              if g.name in bone_names}
        group = mesh_obj.vertex_groups.get(target) or mesh_obj.vertex_groups.new(name=target)
        orphans = [v.index for v in mesh_obj.data.vertices
                   if not any(g.group in bone_group_indices and g.weight > 0.0
                              for g in v.groups)]
        if orphans:
            group.add(orphans, 1.0, "REPLACE")
            adopted += len(orphans)
    if adopted:
        log(f"weighted {adopted} orphan vertex(es) to {target!r} so no "
            f"`neutral_bone` is invented")
    return adopted


def rename_bones(armature_obj, mapping):
    """Rename bones onto the shared humanoid skeleton; report what is unmapped."""
    data = armature_obj.data
    present = [bone.name for bone in data.bones]
    targets = set(mapping.values())
    unmapped = [name for name in present
                if name not in mapping and name not in targets]
    # Rename in two passes through unique temporary names. Maps routinely shift
    # names along a chain (Hips -> Spine while another bone becomes Hips), and a
    # direct rename onto a name still in use makes Blender append ".001".
    staged = {}
    for index, (source, target) in enumerate(mapping.items()):
        bone = data.bones.get(source)
        if bone is None:
            log(f"bone map: {source!r} is not in this rig")
            continue
        placeholder = f"__bonemap_{index}__"
        bone.name = placeholder
        staged[placeholder] = target
    for placeholder, target in staged.items():
        data.bones[placeholder].name = target
    # Vertex groups follow bone names automatically in Blender; animation curves
    # do not, so their data paths have to be rewritten or the animation stops
    # driving the bone it was authored for.
    renames = {source: target for source, target in mapping.items()
               if source in present}
    for action in bpy.data.actions:
        for curve in action_fcurves(action):
            for source, target in renames.items():
                needle = f'pose.bones["{source}"]'
                if curve.data_path.startswith(needle):
                    curve.data_path = curve.data_path.replace(
                        needle, f'pose.bones["{target}"]', 1)
                    break
    if unmapped:
        log(f"bones not named in the bone map, kept as-is: {sorted(unmapped)}")
    return unmapped


# ---------------------------------------------------------------- materials


def _image_identity(image):
    """Something two duplicates of one texture share: file content, else path."""
    path = bpy.path.abspath(image.filepath) if image.filepath else ""
    if path and os.path.isfile(path):
        with open(path, "rb") as handle:
            return ("sha256", hashlib.sha256(handle.read()).hexdigest())
    if image.packed_file is not None:
        return ("packed", hashlib.sha256(image.packed_file.data).hexdigest())
    return ("path", os.path.normcase(path))


def merge_duplicate_images():
    """Point every texture node at one image datablock per distinct texture."""
    canonical = {}
    merged = 0
    for image in list(bpy.data.images):
        identity = _image_identity(image)
        keeper = canonical.setdefault(identity, image)
        if keeper is image:
            continue
        for material in bpy.data.materials:
            if not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is image:
                    node.image = keeper
        merged += 1
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)
    if merged:
        log(f"merged {merged} duplicate image datablock(s)")
    return merged


def relocate_missing_images(search_dirs):
    """Repoint images whose referenced path is gone at a file that exists.

    FBX stores the authoring machine's path (`C:/Dropbox/.../T_Skin.png`) while
    the pack ships the textures somewhere else entirely. Matching is by file name
    within the given directories, searched recursively.
    """
    if not search_dirs:
        return []
    index = {}
    for directory in search_dirs:
        for root, _dirs, files in os.walk(directory):
            for name in files:
                index.setdefault(name.lower(), os.path.join(root, name))
    recovered = []
    for image in bpy.data.images:
        path = bpy.path.abspath(image.filepath) if image.filepath else ""
        if path and os.path.isfile(path):
            continue
        candidate = index.get(os.path.basename(path).lower())
        if candidate:
            image.filepath = candidate
            image.reload()
            recovered.append(candidate)
    if recovered:
        log(f"recovered {len(recovered)} texture(s) from --texture-dir: {recovered}")
    return recovered


def drop_missing_images():
    """Remove images whose files are absent — FBX often carries authoring paths."""
    dropped = []
    for image in list(bpy.data.images):
        path = bpy.path.abspath(image.filepath) if image.filepath else ""
        if image.packed_file is not None or image.has_data:
            continue
        if path and os.path.isfile(path):
            continue
        for material in bpy.data.materials:
            if not material.use_nodes:
                continue
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is image:
                    node.image = None
        dropped.append(image.filepath or image.name)
        bpy.data.images.remove(image)
    if dropped:
        log(f"dropped {len(dropped)} image(s) whose files are missing: {dropped}")
    return dropped


def pack_images():
    for image in bpy.data.images:
        if image.packed_file is None and image.has_data:
            try:
                image.pack()
            except RuntimeError as error:
                log(f"could not pack {image.name}: {error}")


def prune_uv_layers(keep):
    """Drop surplus UV layers. Unity-targeted meshes often carry four."""
    if keep <= 0:
        return
    for obj in meshes():
        layers = obj.data.uv_layers
        while len(layers) > keep:
            layers.remove(layers[len(layers) - 1])


# ---------------------------------------------------------------- animation


# Parts of a mangled FBX take name that name the authoring layer rather than the
# take: 3ds Max writes `<object>|<take>|BaseLayer`.
ACTION_NAME_NOISE = {"baselayer", "baseanimation", "animlayer"}


def clean_action_names():
    """`Armature|Armature|Walk` -> `Walk`, and `Bolt|Chamber|BaseLayer` -> `Chamber`.

    FBX takes import one action per animated object, each named for the object, the
    take and — from 3ds Max — the authoring animation layer. What a Godot
    AnimationPlayer should show is the name the artist gave the take, so every part
    that names an object in this scene or an authoring layer is dropped and the
    last of what remains is the take.
    """
    objects = {o.name for o in bpy.data.objects}
    for action in bpy.data.actions:
        parts = [p.strip() for p in action.name.split("|") if p.strip()]
        kept = [p for p in parts
                if p not in objects and p.lower() not in ACTION_NAME_NOISE]
        cleaned = kept[-1] if kept else (parts[-1] if parts else action.name)
        if cleaned and cleaned != action.name:
            log(f"renamed action {action.name!r} -> {cleaned!r}")
            action.name = cleaned


# ---------------------------------------------------------------- export


def export_glb(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,                  # glTF is +Y up; Blender is +Z up
        export_apply=False,               # transforms are already baked
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_nla_strips=False,
        export_force_sampling=True,
        export_def_bones=False,
        export_image_format="AUTO",
        export_materials="EXPORT",
        export_skins=True,
        export_morph=True,
        use_selection=False,
    )
    log(f"wrote {path}")


def main():
    args = parse_args()

    scale = args.scale
    import_fbx(args.input, 1.0 if args.target_height else scale)

    if args.target_height:
        height = model_height()
        if height <= 0:
            sys.exit(f"{REPORT_PREFIX} cannot normalise height: the model has no mesh")
        scale = args.target_height / height
        log(f"measured height {height:.4f}, scaling by {scale:.6f} "
            f"to reach {args.target_height}")
        scale_scene(scale)

    bake_transforms()

    mapping = {}
    if args.bone_map:
        with open(args.bone_map) as handle:
            # Keys beginning with "_" are commentary, not bones.
            mapping = {k: v for k, v in json.load(handle).items() if not k.startswith("_")}
    leaf_suffixes = tuple(s for s in (args.leaf_bone_suffix or ["_end"]) if s)
    for armature_obj in armatures():
        if leaf_suffixes:
            strip_exporter_leaf_bones(armature_obj, leaf_suffixes)
        # Rename before unifying roots: a rig whose own root is `root` maps to
        # `Root`, and creating `Root` first would leave the rename colliding with
        # it as `Root.001`.
        if mapping:
            rename_bones(armature_obj, mapping)
        if not args.no_single_root:
            unify_root_bones(armature_obj, args.root_bone)
        weight_orphan_vertices(armature_obj, args.root_bone)

    relocate_missing_images(args.texture_dir or [])
    drop_missing_images()
    merge_duplicate_images()
    pack_images()
    prune_uv_layers(args.keep_uv_layers)
    clean_action_names()

    export_glb(args.output)


# Guarded so this file can be imported as a module by another Blender script and
# have its corrections reused: `tools/assets/fbx_to_viewmodel.py` does exactly
# that. Blender's `--python` runs a file as `__main__`, so the command line is
# unaffected.
if __name__ == "__main__":
    main()
