#!/usr/bin/env python3
"""Assemble every Enemy body from `enemy_recipe.py` and export one `.glb` a kind.

Run through `generate_enemies.sh`, which supplies Blender. This file is the
assembler; the declaration is next door, and that split is `generate_machines.py`
against `machine_recipes.py` exactly.

Three things it has to get right that the Machine generator does not:

* **A rig, and a small one.** `game/enemy_bodies.gd` bakes *bone poses* into a
  texture — `bone_count * 3` texels across by one row a frame — and the whole
  architecture rests on that staying small. 19 bones for a six-legged body and 15
  for a four-legged one, against the 23 the KayKit characters used, so the pose
  texture does not grow.
* **One influence a vertex.** `EnemyBodies.INFLUENCES` is 4 and it keeps the four
  heaviest, so more would be silently dropped — but there is nothing to drop here,
  because a chitin plate is *rigid*. Every vertex belongs to exactly one bone at
  weight 1. That is not a shortcut: a smooth-skinned insect leg is a rubber tube,
  and plates that slide over one another at the joint is what an exoskeleton is.
* **Clips in the body's own file.** The KayKit cast resolved clip names against
  separate shared-rig libraries (`docs/ASSET_PIPELINE.md` section 4), which is the
  right arrangement for a pack of thirteen characters on one rig. These are three
  bodies with three different rigs, so a library shared between them could only
  carry the bones they have in common. Each `.glb` carries its own armature and its
  own four clips, and `EnemyBodies.Recipe.libraries` names the character itself.

**Byte reproducibility is a requirement, not a nicety** —
`tools/assets/tests/test_generated_enemies.py` regenerates and compares, which is
#57's rule for a committed output. So: `--factory-startup`, no randomness, parts
built in a fixed order, objects created in sorted palette order, and every float
that reaches the file derived from the declaration rather than from a measurement
of the host.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh  # type: ignore
import bpy  # type: ignore
from mathutils import Vector  # type: ignore

# **No bytecode cache, and this is a correctness requirement rather than hygiene.**
# `enemy_recipe` is an ordinary Python module, and CPython reuses a cached `.pyc`
# when the source's mtime *second* and byte count both match — which is exactly what
# bracketing a proportion does: `foot_out=0.66` for `foot_out=0.96` is the same
# length, and a developer trying three values does three of those in a few seconds.
# Measured: with a cache present the generator assembled the body the **previous**
# value describes, wrote it, and reported success — and
# `test_generated_enemies.test_follows_a_changed_proportion_without_a_manual_step`
# passed while measuring the wrong body. The env var does not work here because
# Blender has already started the interpreter, so it is set on `sys` before the
# declaration is imported.
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import enemy_recipe as recipe  # noqa: E402
import machine_materials  # noqa: E402
import machine_parts as parts  # noqa: E402

REPO = HERE.parent.parent
DEFAULT_OUTPUT = REPO / "assets" / "characters" / "insects"

#: Chamfer on a body plate, in body heights. Smaller than a Machine's 3 cm,
#: because a body is one metre of authored geometry rather than six, and the same
#: proportion of edge would read as melted.
CHAMFER = 0.012

#: Where the hip sits across the thorax, as a fraction of its half-width. Just
#: outside the body, so the coxa leaves it rather than starting inside it.
HIP_ACROSS = 0.92


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", action="append", default=None,
                        help="Generate just this kind (repeatable).")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT),
                        help="Where the .glb files go.")
    return parser.parse_args(argv[argv.index("--") + 1:] if "--" in argv else [])


# ───────────────────────────────────────────────────────────────────────────────
# Geometry
# ───────────────────────────────────────────────────────────────────────────────

class Rigged:
    """Geometry being accumulated, keyed by palette material **and** by bone.

    `machine_parts.Assembly` keys by material alone, which is all a Machine needs.
    A rigged body needs both: the material decides which glTF primitive a face
    lands in and the bone decides which vertex group its vertices join, and those
    two partitions cross. So parts are kept as a list in build order and the
    material grouping is done at the end, recording a vertex range a bone as it
    goes — which is also what makes the output a function of build order and
    therefore reproducible.
    """

    def __init__(self) -> None:
        self.parts: list[tuple[str, str, bmesh.types.BMesh]] = []

    def add(self, material: str, bone: str, mesh: bmesh.types.BMesh) -> None:
        self.parts.append((material, bone, mesh))

    def materials(self) -> list[str]:
        return sorted({material for material, _, _ in self.parts})


def limb(start, end, thickness_start: float, thickness_end: float) -> bmesh.types.BMesh:
    """One segment of a leg: a tapered box leaning from `start` to `end`.

    Boxes rather than cylinders, and that is the "not too detailed" instruction
    arriving as geometry. A 16-segment cylinder is 96 triangles a leg segment,
    which on six legs of two segments is 1,152 triangles of leg on a body a player
    sees twenty of at once; this is 12. It is also what a chitin leg looks like —
    faceted plate, not a tube.
    """
    mesh = bmesh.new()
    a = Vector(start)
    b = Vector(end)
    along = (b - a)
    if along.length <= 1e-9:
        along = Vector((0.0, 0.0, 1.0))
    along = along.normalized()
    # A frame across the limb. `up` is whichever world axis the limb is least
    # aligned with, so the cross product never degenerates — and it is chosen from
    # the limb's own direction rather than from a random seed, so it is the same on
    # every run.
    axis = min(range(3), key=lambda i: abs(along[i]))
    reference = Vector((1.0 if axis == 0 else 0.0,
                        1.0 if axis == 1 else 0.0,
                        1.0 if axis == 2 else 0.0))
    side = along.cross(reference).normalized()
    other = along.cross(side).normalized()

    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    lower = [mesh.verts.new(a + side * (sx * thickness_start / 2.0)
                            + other * (sy * thickness_start / 2.0))
             for sx, sy in corners]
    upper = [mesh.verts.new(b + side * (sx * thickness_end / 2.0)
                            + other * (sy * thickness_end / 2.0))
             for sx, sy in corners]
    mesh.faces.new(list(reversed(lower)))
    mesh.faces.new(upper)
    for i in range(4):
        j = (i + 1) % 4
        mesh.faces.new((lower[i], lower[j], upper[j], upper[i]))
    mesh.normal_update()
    return mesh


def hip(insect: recipe.Insect) -> float:
    return insect.thorax_width / 2.0 * HIP_ACROSS


def knee_at(insect: recipe.Insect, leg: recipe.Leg, sign: float):
    return (sign * leg.knee_out, leg.along, leg.knee_up)


def hip_at(insect: recipe.Insect, leg: recipe.Leg, sign: float):
    return (sign * hip(insect), leg.along, insect.thorax_centre)


def foot_at(insect: recipe.Insect, leg: recipe.Leg, sign: float):
    return (sign * leg.foot_out, leg.along + leg.foot_along, 0.0)


def head_at(insect: recipe.Insect):
    """The centre of the head, in body units."""
    return (
        0.0,
        -insect.thorax_length / 2.0 + insect.head_forward - insect.head_length / 2.0,
        insect.thorax_centre + insect.head_drop,
    )


def abdomen_root(insect: recipe.Insect):
    return (0.0, insect.thorax_length / 2.0, insect.thorax_centre)


def abdomen_tip(insect: recipe.Insect):
    root = abdomen_root(insect)
    return (0.0, root[1] + insect.abdomen_length, root[2] + insect.abdomen_rise)


def build(insect: recipe.Insect) -> Rigged:
    """One insect, in body units, facing -Y, feet on z = 0.

    The order the parts go in is the order the glTF's vertices come out in, so it
    is fixed and walked deepest-last: thorax, carapace, abdomen, head, mandibles,
    then the legs in declaration order, left side before right.
    """
    rig = Rigged()

    # ── thorax: a box with a domed back ───────────────────────────────────────
    # **The first version put a zero-depth `prism` here as a "taper" and the render
    # is what caught it**: `prism` interpolates between two rectangles in XY at two
    # heights, so a size of `(width, 0.0)` is a flat plate standing inside the body.
    # It read as a bright slab with legs, which is nothing like an insect — and no
    # test could have seen it, because the mesh was watertight, correctly named and
    # the right number of triangles.
    rig.add(insect.material("thorax"), "Thorax", parts.box(
        (insect.thorax_width, insect.thorax_length, insect.thorax_depth),
        (0.0, 0.0, insect.thorax_centre),
        chamfer=CHAMFER,
    ))
    # The dome is what says which way up a thorax is, and the shoulder it puts on the
    # silhouette is what stops a body reading as a crate on legs.
    rig.add(insect.material("thorax"), "Thorax", parts.frustum(
        (insect.thorax_width * 0.94, insect.thorax_length * 0.94),
        (insect.thorax_width * 0.52, insect.thorax_length * 0.56),
        insect.thorax_depth * 0.42,
        (0.0, -insect.thorax_length * 0.04, insect.thorax_centre + insect.thorax_depth * 0.44),
    ))

    # ── carapace: the plate over the back, or nothing ─────────────────────────
    if insect.carapace_rise > 0.0:
        top = insect.carapace_rise
        base = insect.thorax_centre + insect.thorax_depth * 0.25
        rig.add(insect.material("carapace"), "Thorax", parts.prism(
            (0.0, 0.0, base),
            (insect.carapace_width, insect.carapace_length),
            (0.0, insect.carapace_length * 0.12, top),
            (insect.carapace_width * 0.48, insect.carapace_length * 0.42),
        ))
        # A ridge down the crest. One part, and it is silhouette work: it breaks the
        # plate's top edge so a Breaker head-on is not a rectangle.
        rig.add(insect.material("carapace"), "Thorax", parts.prism(
            (0.0, insect.carapace_length * 0.12, top - 0.02),
            (insect.carapace_width * 0.20, insect.carapace_length * 0.42),
            (0.0, insect.carapace_length * 0.18, top + insect.carapace_width * 0.14),
            (insect.carapace_width * 0.06, insect.carapace_length * 0.16),
        ))

    # ── abdomen: segments, each a little smaller than the last ───────────────
    root = Vector(abdomen_root(insect))
    tip = Vector(abdomen_tip(insect))
    segments = max(insect.abdomen_segments, 1)
    for segment in range(segments):
        low = segment / segments
        high = (segment + 1) / segments
        at_low = root.lerp(tip, low)
        at_high = root.lerp(tip, high)
        width_low = insect.abdomen_width * (1.0 - insect.abdomen_taper * low)
        width_high = insect.abdomen_width * (1.0 - insect.abdomen_taper * high)
        depth_low = insect.abdomen_depth * (1.0 - insect.abdomen_taper * low)
        depth_high = insect.abdomen_depth * (1.0 - insect.abdomen_taper * high)
        bone = "Abdomen" if segment * 2 < segments else "AbdomenTip"
        # One box a segment, each a little smaller than the last. The taper is what
        # makes a segmented body read as segmented at ten metres, and it has to be
        # in the **boxes** rather than in a cross-section plate between them — see
        # the thorax above for what a zero-depth `prism` actually draws.
        rig.add(insect.material("abdomen"), bone, parts.box(
            (
                (width_low + width_high) / 2.0,
                (at_high - at_low).length + 0.02,
                (depth_low + depth_high) / 2.0,
            ),
            tuple((at_low + at_high) / 2.0),
            chamfer=CHAMFER,
        ))
        # The joint between two segments: a narrow dark collar, which is what makes
        # a segmented body read as segmented rather than as a lumpy one.
        if segment + 1 < segments:
            rig.add(insect.material("joint"), bone, parts.box(
                (width_high * 1.06, 0.030, depth_high * 1.06),
                tuple(at_high),
                chamfer=CHAMFER * 0.5,
            ))

    # ── head and mandibles: no face, a bite ──────────────────────────────────
    centre = Vector(head_at(insect))
    rig.add(insect.material("joint"), "Head", parts.box(
        (insect.head_width * 0.52, 0.055, insect.head_depth * 0.60),
        tuple(Vector((0.0, -insect.thorax_length / 2.0, insect.thorax_centre))
              .lerp(centre, 0.45)),
        chamfer=CHAMFER * 0.5,
    ))
    # Wedge-shaped, widest and deepest at the back, so the front is a blunt point
    # between the mandibles rather than a cube with a cube on it.
    rig.add(insect.material("head"), "Head", parts.prism(
        tuple(centre + Vector((0.0, insect.head_length / 2.0,
                               -insect.head_depth / 2.0))),
        (insect.head_width, insect.head_length),
        tuple(centre + Vector((0.0, -insect.head_length * 0.10,
                               insect.head_depth / 2.0))),
        (insect.head_width * 0.56, insect.head_length * 0.52),
    ))
    nose = centre + Vector((0.0, -insect.head_length / 2.0, 0.0))
    for side, sign in (("L", 1.0), ("R", -1.0)):
        base = nose + Vector((sign * insect.head_width * 0.34, 0.0, 0.0))
        point = nose + Vector((
            sign * insect.mandible_spread,
            -insect.mandible_length,
            -insect.head_depth * 0.14,
        ))
        # Two parts a mandible: a thick root and a thin tip that curves inward, so
        # the pair reads as pincers and not as two spikes.
        middle = base.lerp(point, 0.55) + Vector((sign * insect.mandible_spread * 0.5, 0.0, 0.0))
        rig.add(insect.material("mandible"), f"Mandible{side}",
                limb(tuple(base), tuple(middle),
                     insect.mandible_thickness, insect.mandible_thickness * 0.72))
        rig.add(insect.material("mandible"), f"Mandible{side}",
                limb(tuple(middle), tuple(point),
                     insect.mandible_thickness * 0.72, insect.mandible_thickness * 0.22))

    # ── legs, left before right so the output order is fixed ─────────────────
    for index, leg in enumerate(insect.legs):
        for side, sign in (("L", 1.0), ("R", -1.0)):
            start = hip_at(insect, leg, sign)
            knee = knee_at(insect, leg, sign)
            foot = foot_at(insect, leg, sign)
            rig.add(insect.material("joint"), f"Leg{index}{side}Coxa", parts.box(
                (leg.thickness * 1.5, leg.thickness * 1.5, leg.thickness * 1.5),
                start, chamfer=CHAMFER * 0.5,
            ))
            rig.add(insect.material("leg"), f"Leg{index}{side}Coxa",
                    limb(start, knee, leg.thickness * 1.15, leg.thickness * 0.85))
            rig.add(insect.material("leg"), f"Leg{index}{side}Tibia",
                    limb(knee, foot, leg.thickness * 0.85, leg.thickness * 0.30))
    return rig


# ───────────────────────────────────────────────────────────────────────────────
# The rig
# ───────────────────────────────────────────────────────────────────────────────

def bone_specs(insect: recipe.Insect) -> list[tuple[str, tuple, tuple, str | None]]:
    """Every bone, as `(name, head, tail, parent)`, parents before children.

    Order matters twice over. `EnemyBodies._compose` walks bones in index order and
    relies on Godot putting a parent before its child, and `EnemyBodies._pose`
    treats **bone 0** as the root whose horizontal travel is replaced by its rest —
    so `Root` is first and is the only parentless bone.
    """
    out: list[tuple[str, tuple, tuple, str | None]] = [
        ("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.06), None),
    ]
    thorax = insect.thorax_centre
    out.append(("Thorax", (0.0, insect.thorax_length / 2.0, thorax),
                (0.0, -insect.thorax_length / 2.0, thorax), "Root"))

    root = Vector(abdomen_root(insect))
    tip = Vector(abdomen_tip(insect))
    middle = root.lerp(tip, 0.5)
    out.append(("Abdomen", tuple(root), tuple(middle), "Thorax"))
    out.append(("AbdomenTip", tuple(middle), tuple(tip), "Abdomen"))

    nose_root = Vector((0.0, -insect.thorax_length / 2.0, thorax))
    centre = Vector(head_at(insect))
    out.append(("Head", tuple(nose_root), tuple(centre), "Thorax"))
    nose = centre + Vector((0.0, -insect.head_length / 2.0, 0.0))
    for side, sign in (("L", 1.0), ("R", -1.0)):
        base = nose + Vector((sign * insect.head_width * 0.34, 0.0, 0.0))
        point = nose + Vector((sign * insect.mandible_spread, -insect.mandible_length,
                               -insect.head_depth * 0.14))
        out.append((f"Mandible{side}", tuple(base), tuple(point), "Head"))

    for index, leg in enumerate(insect.legs):
        for side, sign in (("L", 1.0), ("R", -1.0)):
            start = hip_at(insect, leg, sign)
            knee = knee_at(insect, leg, sign)
            foot = foot_at(insect, leg, sign)
            out.append((f"Leg{index}{side}Coxa", start, knee, "Thorax"))
            out.append((f"Leg{index}{side}Tibia", knee, foot, f"Leg{index}{side}Coxa"))
    return out


def build_armature(insect: recipe.Insect, scale: float, lift: float):
    data = bpy.data.armatures.new(f"{insect.kind_id}_rig")
    obj = bpy.data.objects.new(f"{insect.kind_id}_rig", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent in bone_specs(insect):
        bone = data.edit_bones.new(name)
        bone.head = Vector((head[0] * scale, head[1] * scale, head[2] * scale + lift))
        bone.tail = Vector((tail[0] * scale, tail[1] * scale, tail[2] * scale + lift))
        # A zero-length bone is dropped by Blender outright, which would take the
        # vertex group with it and skin a plate to its parent. Nudge rather than
        # fail silently: a degenerate bone means a declaration where two joints
        # coincide, and the body is still correct with the bone one millimetre long.
        if (bone.tail - bone.head).length < 1e-5:
            bone.tail = bone.head + Vector((0.0, 0.0, 1e-3))
        if parent is not None:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


# ───────────────────────────────────────────────────────────────────────────────
# Clips
# ───────────────────────────────────────────────────────────────────────────────

def author_clips(insect: recipe.Insect, armature) -> None:
    """Every clip in `enemy_recipe.CLIPS`, as one NLA track each.

    **A key on every frame, with linear interpolation.** An animator would author
    eight keys and let the curve do the rest; here the pose is a function of phase,
    so sampling it on every frame is both exact and free — and it means what Godot
    imports is what `enemy_recipe.pose_at` says rather than what a Bezier handle
    did to it. `EnemyBodies._bake` then samples the imported `Animation` at
    `length * frame / frames`, which lands on those keys.

    One NLA track a clip, named for the clip, because `export_animation_mode =
    'NLA_TRACKS'` names each glTF animation after its track — and that name is what
    `EnemyBodies.Recipe.clips` resolves against.
    """
    armature.animation_data_create()
    for bone in armature.pose.bones:
        bone.rotation_mode = 'XYZ'

    for clip in recipe.CLIPS:
        action = bpy.data.actions.new(clip.name)
        armature.animation_data.action = action
        slot = action.slots.new(id_type='OBJECT', name=armature.name)
        armature.animation_data.action_slot = slot
        for frame in range(clip.frames + 1):
            # The last frame repeats the first, so the cycle closes. The bake samples
            # `[0, length)` exclusively, so that repeat is never sampled twice — it
            # is there to make the clip's *length* a whole number of frames.
            phase = (frame % clip.frames) / float(clip.frames)
            pose = recipe.pose_at(insect, clip.name, phase)
            for bone in armature.pose.bones:
                angles = pose.get(bone.name, (0.0, 0.0, 0.0))
                bone.rotation_euler = angles
                bone.keyframe_insert('rotation_euler', frame=frame + 1)
        for curve in _fcurves(action):
            for key in curve.keyframe_points:
                key.interpolation = 'LINEAR'
        track = armature.animation_data.nla_tracks.new()
        track.name = clip.name
        track.strips.new(clip.name, 1, action)
        armature.animation_data.action = None


def _fcurves(action):
    """Every f-curve of an action, across Blender's slotted-action layers.

    Blender 4.4 moved an action's curves behind slots, layers and strips, and the
    flat `action.fcurves` is a compatibility view that is empty for a slotted
    action. Walking both is what makes this work on 5.2 without pinning an API.
    """
    seen = list(getattr(action, "fcurves", []) or [])
    for layer in getattr(action, "layers", []) or []:
        for strip in getattr(layer, "strips", []) or []:
            for bag in getattr(strip, "channelbags", []) or []:
                seen.extend(bag.fcurves)
    return seen


# ───────────────────────────────────────────────────────────────────────────────
# Assembly
# ───────────────────────────────────────────────────────────────────────────────

def clear_scene() -> None:
    """A genuinely empty scene between kinds, so one body cannot leak into the next.

    **Materials are deliberately not cleared**, which is `generate_machines.py`'s
    note and is load-bearing rather than tidy: Blender renames a second material
    called `CastIron` to `CastIron.001`, and `EnemyBodies._flatten` groups surfaces
    by `material.resource_name` — so a palette rebuilt per kind would give the
    Breaker a surface called `CastIron.001` and the renderer would resolve the
    palette entry for it by name and find nothing. The first run of this generator
    did exactly that.
    """
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures,
                       bpy.data.actions):
        for item in list(collection):
            collection.remove(item, do_unlink=True)


def extent(rig: Rigged) -> tuple[float, float]:
    low, high = math.inf, -math.inf
    for _, _, mesh in rig.parts:
        for vertex in mesh.verts:
            low = min(low, vertex.co.z)
            high = max(high, vertex.co.z)
    return low, high


def vent_offset(insect: recipe.Insect, scale: float, lift: float):
    """Where this kind's weak point is, in **Godot** axes and body heights.

    The far face of the tail, derived from the abdomen's own numbers rather than
    written down a second time — which is the whole reason it is exported as a
    marker and read back by `EnemyBodies` instead of being a constant in
    `world_view.gd`. Blender +Y is Godot -Z, so an abdomen trailing off towards +Y
    puts the vent behind the body, which is the end `_armoured` does not protect.
    """
    tip = Vector(abdomen_tip(insect))
    behind = insect.abdomen_depth * (1.0 - insect.abdomen_taper) * 0.5
    y = tip.z * scale + lift
    z = -((tip.y + behind) * scale)
    return (0.0, y, z)


def build_kind(insect: recipe.Insect, palette: dict) -> None:
    rig = build(insect)
    low, high = extent(rig)
    if not (high > low):
        raise SystemExit(f"error: {insect.kind_id} has no vertical extent")
    # **The body is normalised here, not in the engine.** `EnemyBodies._bake`
    # measures the skinned rest and folds a normalisation into the bone matrices
    # anyway, so a body that is already one metre tall makes that transform the
    # identity — which matters for more than tidiness: `enemy_skin.gdshader` reads
    # the *pre-skin* vertex for its grime field, so authored units are the units
    # `grime_metres` is a fraction of. Author at 1.0 and the two agree.
    scale = 1.0 / (high - low)
    lift = -low * scale

    armature = build_armature(insect, scale, lift)

    # One object a material, in sorted palette order, so the glTF's mesh, node and
    # material arrays come out in the same order on every run.
    for name in rig.materials():
        combined = bmesh.new()
        ranges: list[tuple[str, int, int]] = []
        for material, bone, mesh in rig.parts:
            if material != name:
                continue
            bmesh.ops.scale(mesh, vec=Vector((scale, scale, scale)), verts=mesh.verts)
            bmesh.ops.translate(mesh, vec=Vector((0.0, 0.0, lift)), verts=mesh.verts)
            bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
            scratch = bpy.data.meshes.new("__part__")
            mesh.to_mesh(scratch)
            mesh.free()
            start = len(combined.verts)
            combined.from_mesh(scratch)
            bpy.data.meshes.remove(scratch)
            ranges.append((bone, start, len(combined.verts)))

        # UVs last, after the normals are settled, exactly as the Machines do it:
        # the projection picks an axis per face from its normal.
        parts.box_project_uvs(combined)
        data = bpy.data.meshes.new(f"{insect.kind_id}_{name}")
        combined.to_mesh(data)
        combined.free()
        data.materials.append(palette[name])
        for polygon in data.polygons:
            polygon.use_smooth = False
        obj = bpy.data.objects.new(f"{insect.kind_id}_{name}", data)
        bpy.context.scene.collection.objects.link(obj)

        # Rigid skinning: one group a bone, every vertex of a part at weight 1 in
        # its own bone's group and nowhere else.
        groups = {}
        for bone, start, stop in ranges:
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
            groups[bone].add(list(range(start, stop)), 1.0, 'REPLACE')

        obj.parent = armature
        modifier = obj.modifiers.new("Armature", 'ARMATURE')
        modifier.object = armature

    author_clips(insect, armature)

    if insect.has_vent:
        marker = bpy.data.objects.new("Vent", None)
        marker.empty_display_type = 'ARROWS'
        marker.empty_display_size = 0.1
        # The marker is placed in **Blender** space; the exporter's Y-up conversion
        # is what turns it into the Godot offset `EnemyBodies` reads back.
        godot = vent_offset(insect, scale, lift)
        marker.location = Vector((godot[0], -godot[2], godot[1]))
        bpy.context.scene.collection.objects.link(marker)


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format='GLB',
        export_yup=True,
        # **Not applied.** `export_apply` evaluates modifiers, and the modifier on
        # every one of these objects is the Armature — applying it would bake the
        # rest pose into the vertices and throw the skin away.
        export_apply=False,
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_bake_animation=False,
        export_skins=True,
        export_morph=False,
        export_materials='EXPORT',
        # No image in the file, for `generate_machines.py`'s reason: the palette's
        # generated texture set is eight 1024-square PNGs and embedding them in
        # three committed bodies would put megabytes of duplicated pixels in a
        # public repository to say something `world_view.gd` says once. The glTF
        # material is a palette *name*, and the surface is resolved from it.
        export_image_format='NONE',
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_extras=False,
        use_visible=False,
        use_selection=False,
    )


def main() -> int:
    args = parse_args(sys.argv)
    kinds = list(recipe.KINDS)
    if args.only:
        wanted = set(args.only)
        unknown = wanted - set(recipe.kind_ids())
        if unknown:
            raise SystemExit(f"error: no such Enemy kind: {', '.join(sorted(unknown))}")
        kinds = [insect for insect in kinds if insect.kind_id in wanted]

    bpy.context.scene.render.fps = recipe.FPS
    # Built once for the whole run, for `clear_scene`'s reason: a palette whose
    # names drift per file is not a shared palette.
    palette = machine_materials.build_blender_materials(textured=False)
    output = Path(args.output_dir)
    for insect in kinds:
        clear_scene()
        build_kind(insect, palette)
        destination = output / f"{insect.kind_id}.glb"
        export(destination)
        bones = len(bone_specs(insect))
        frames = sum(clip.frames for clip in recipe.CLIPS)
        print(f"  {insect.kind_id:<12} {len(insect.legs) * 2} legs, {bones} bones, "
              f"{len(recipe.CLIPS)} clips / {frames} frames, "
              f"for {insect.hit_height_metres:g} m -> {destination}")
    print(f"generated {len(kinds)} Enemy body(ies) into {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
