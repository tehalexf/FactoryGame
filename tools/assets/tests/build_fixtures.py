"""Build small FBX fixtures that reproduce the known FBX intake breakages.

Run under Blender, not CPython:

    blender --background --factory-startup --python tools/assets/tests/build_fixtures.py \
        -- --out-dir /tmp/fixtures

Each fixture isolates one breakage the pipeline has to correct, modelled on what
real exported FBX actually looks like:

  multi_root.fbx          three bones with no parent (weapon and prop bones left
                          beside the skeleton root)
  unity_conventions.fbx   authored at 100x with a 180-degree Z rotation left on
                          the armature, as Unity-targeted exports arrive
  duplicate_textures.fbx  two materials pointing at byte-identical copies of one
                          texture in different folders, which the FBX importer
                          turns into two image datablocks
  orphan_weights.fbx      a skinned mesh with unweighted vertices, which makes
                          Blender's glTF exporter invent a `neutral_bone` joint
                          and so a second skeleton root
  prefixed_actions.fbx    actions named "Armature|Armature|Walk", the FBX
                          take-name mangling Godot then shows in its
                          AnimationPlayer
"""

import argparse
import math
import os
import shutil
import struct
import sys
import zlib

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    return parser.parse_args(argv)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def write_png(path, rgb=(200, 80, 40), size=8):
    """A tiny valid PNG, written without any image library."""
    raw = b"".join(b"\x00" + bytes(rgb) * size for _ in range(size))

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def add_cube_mesh(name="Body", size=1.0, location=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=size, location=location)
    obj = bpy.context.object
    obj.name = name
    return obj


def new_armature(bone_specs, name="Armature"):
    """bone_specs: list of (bone_name, parent_name_or_None, head, tail)."""
    armature_data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, armature_data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bone_name, parent, head, tail in bone_specs:
        bone = armature_data.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = made[parent]
        made[bone_name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def skin(mesh_obj, armature_obj, bone_name):
    group = mesh_obj.vertex_groups.new(name=bone_name)
    group.add([v.index for v in mesh_obj.data.vertices], 1.0, "REPLACE")
    mesh_obj.parent = armature_obj
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature_obj


def export_fbx(path):
    bpy.ops.export_scene.fbx(filepath=path, path_mode="ABSOLUTE", add_leaf_bones=False,
                             bake_anim=True, bake_anim_use_all_actions=True)


def fixture_multi_root(out_dir):
    reset()
    armature = new_armature([
        ("Hips", None, (0, 0, 1.0), (0, 0, 1.3)),
        ("Spine", "Hips", (0, 0, 1.3), (0, 0, 1.6)),
        # Two extra roots: the classic breakage.
        ("WeaponSocket", None, (0.4, 0, 1.2), (0.4, 0, 1.4)),
        ("PropHandle", None, (-0.4, 0, 1.2), (-0.4, 0, 1.4)),
    ])
    mesh = add_cube_mesh(size=0.5, location=(0, 0, 1.2))
    skin(mesh, armature, "Hips")
    export_fbx(os.path.join(out_dir, "multi_root.fbx"))


def fixture_unity_conventions(out_dir):
    """Authored at 100x with a leftover 180-degree Z rotation on the armature."""
    reset()
    armature = new_armature([
        ("Hips", None, (0, 0, 100.0), (0, 0, 130.0)),
        ("Spine", "Hips", (0, 0, 130.0), (0, 0, 180.0)),
    ])
    armature.rotation_euler = (0.0, 0.0, math.pi)
    mesh = add_cube_mesh(size=100.0, location=(0, 0, 90.0))
    skin(mesh, armature, "Hips")
    export_fbx(os.path.join(out_dir, "unity_conventions.fbx"))


def fixture_duplicate_textures(out_dir):
    reset()
    tex_a = os.path.join(out_dir, "tex_a", "skin.png")
    tex_b = os.path.join(out_dir, "tex_b", "skin.png")
    write_png(tex_a)
    os.makedirs(os.path.dirname(tex_b), exist_ok=True)
    shutil.copyfile(tex_a, tex_b)

    mesh = add_cube_mesh(size=1.0)
    for index, tex in enumerate((tex_a, tex_b)):
        material = bpy.data.materials.new(f"Skin_{index}")
        material.use_nodes = True
        bsdf = material.node_tree.nodes["Principled BSDF"]
        node = material.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(tex, check_existing=False)
        material.node_tree.links.new(bsdf.inputs["Base Color"], node.outputs["Color"])
        mesh.data.materials.append(material)
    # Give the second material some faces so it is not dropped as unused.
    for polygon in mesh.data.polygons[3:]:
        polygon.material_index = 1
    export_fbx(os.path.join(out_dir, "duplicate_textures.fbx"))


def fixture_relocated_textures(out_dir):
    """Textures referenced at an authoring path that does not exist any more.

    Real FBX routinely carries absolute Windows paths such as
    `C:/Dropbox/.../textures/T_Skin.png`, while the pack ships the textures in a
    sibling folder. The fixture reproduces that: the FBX points at a path that is
    then removed, and the real file lives somewhere else.
    """
    reset()
    # A filename no other fixture uses: Blender's importer searches nearby
    # directories by basename and would otherwise find a different fixture's file.
    authored = os.path.join(out_dir, "authoring_only", "relocated_only_skin.png")
    # Outside out_dir on purpose: Blender's FBX importer searches directories
    # near the .fbx, so a texture it could find by itself would not test
    # anything.
    relocated = os.path.join(out_dir.rstrip("/") + "-textures", "relocated_only_skin.png")
    write_png(authored, rgb=(30, 160, 90))
    mesh = add_cube_mesh(size=1.0)
    material = bpy.data.materials.new("Skin")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    node = material.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(authored)
    material.node_tree.links.new(bsdf.inputs["Base Color"], node.outputs["Color"])
    mesh.data.materials.append(material)
    export_fbx(os.path.join(out_dir, "relocated_textures.fbx"))
    os.makedirs(os.path.dirname(relocated), exist_ok=True)
    shutil.move(authored, relocated)
    os.rmdir(os.path.dirname(authored))


def fixture_orphan_weights(out_dir):
    """A skinned mesh where some vertices carry no bone weight at all.

    Blender's glTF exporter answers this by inventing an extra joint called
    `neutral_bone` and binding the orphans to it — which quietly gives the
    exported file a second skeleton root.
    """
    reset()
    armature = new_armature([
        ("Hips", None, (0, 0, 1.0), (0, 0, 1.3)),
        ("Spine", "Hips", (0, 0, 1.3), (0, 0, 1.6)),
    ])
    mesh = add_cube_mesh(size=0.5, location=(0, 0, 1.2))
    group = mesh.vertex_groups.new(name="Hips")
    # Only half the vertices are weighted; the rest are orphans.
    group.add([v.index for v in mesh.data.vertices][:4], 1.0, "REPLACE")
    mesh.parent = armature
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    export_fbx(os.path.join(out_dir, "orphan_weights.fbx"))


def fixture_prefixed_actions(out_dir):
    reset()
    armature = new_armature([
        ("Hips", None, (0, 0, 1.0), (0, 0, 1.3)),
        ("Spine", "Hips", (0, 0, 1.3), (0, 0, 1.6)),
    ])
    mesh = add_cube_mesh(size=0.5, location=(0, 0, 1.2))
    skin(mesh, armature, "Hips")

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for action_name, lift in (("Walk", 0.1), ("Attack", 0.3)):
        action = bpy.data.actions.new(action_name)
        armature.animation_data_create()
        armature.animation_data.action = action
        pose_bone = armature.pose.bones["Spine"]
        for frame, value in ((1, 0.0), (10, lift)):
            pose_bone.location = (0.0, 0.0, value)
            pose_bone.keyframe_insert("location", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")
    export_fbx(os.path.join(out_dir, "prefixed_actions.fbx"))


def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    fixture_multi_root(args.out_dir)
    fixture_unity_conventions(args.out_dir)
    fixture_duplicate_textures(args.out_dir)
    fixture_relocated_textures(args.out_dir)
    fixture_orphan_weights(args.out_dir)
    fixture_prefixed_actions(args.out_dir)
    print("fixtures written to", args.out_dir)


main()
