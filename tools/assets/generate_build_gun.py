#!/usr/bin/env python3
"""Generate the Build Gun viewmodel from its recipe, and measure it against the
frustum before writing it.

Run through `tools/assets/generate_build_gun.sh`, which supplies the Blender
invocation. Directly:

    blender --background --factory-startup \
        --python tools/assets/generate_build_gun.py -- --output assets/gear/build_gun.glb

**The measurement is the reason this file is not three lines.** "Framing is
measured against the frustum, never argued about" is a rule this project paid
three bug reports for: the knife was reported as not working twice, fixed once
from a true fact into something worse, and the only instrument that could see the
defect was a render. A generated viewmodel can do better than a render, because
the geometry is in hand: every vertex of every part, at every keyframe of every
take, is projected into the camera's own half-angles and the worst margin is
printed. A model that leaves the frame is **refused** rather than written, so the
defect cannot reach a `.glb` at all, and the render is then confirming a claim
rather than discovering one.

`player.field_of_view_degrees` is 75 **vertical** — Godot's `Camera3D.fov` is the
vertical angle when `keep_aspect` is its default — so the horizontal half-angle
depends on the aspect ratio and the vertical one does not. Both are checked
separately, which is a stronger statement than `convert_weapons.sh`'s single
off-axis angle: a frustum is a rectangular pyramid, and a part can sit inside the
horizontal half-angle while hanging below the bottom edge.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh  # type: ignore
import bpy  # type: ignore
from mathutils import Matrix, Vector  # type: ignore

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import build_gun_recipe as recipe  # noqa: E402
import machine_materials  # noqa: E402
import machine_parts as parts  # noqa: E402

#: The one object every part is parented to, and the one the takes are keyframed
#: on. Named rather than anonymous because the glTF carries the name and a future
#: reader of the file should find the reason here.
ROOT_NAME = "BuildGun"

#: `player.field_of_view_degrees`, read from the shipped tuning rather than
#: written here — the whole point of the measurement is that it tracks the number
#: a player actually plays at, so a field of view tuned wider must re-measure.
FIELD_OF_VIEW_KEY = "field_of_view_degrees"

#: The aspect ratio the margin is quoted at. 16:9 is what `tools/visual/shot.sh`
#: renders and what `convert_weapons.sh`'s own table was read at; a narrower
#: window has a narrower horizontal half-angle, so this is the number to lower if
#: the game ever ships a 4:3 mode.
ASPECT = 16.0 / 9.0

#: How much of each half-angle the model must leave spare. 0.80 rather than 1.0
#: because the field of view is **tuned**, and a model that exactly fills the
#: frame at the shipped 75 degrees clips the moment somebody turns it down —
#: which is the failure mode `convert_weapons.sh` bracketed by hand and recorded
#: as "tolerates about 68 degrees". A fifth in hand is about that much room.
MARGIN = 0.80

#: Where the **business end** starts, as a fraction of the body's length forward
#: of the grip. Everything past it is what carries the silhouette and has to be
#: in frame; everything behind it is grip and hand and may run off the bottom
#: edge of the screen, which is where a viewmodel's grip belongs.
BUSINESS_END_FROM = 0.5

#: Blender frames per second for the exported takes. 24 is Blender's own default
#: and the number does not reach the game: `WeaponViewmodel` seeks the clip from
#: the tick count, so only the clip's *length in seconds* is read.
FPS = 24


def parse_args(argv: list[str]) -> argparse.Namespace:
    after = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="generate_build_gun.py",
                                     description=__doc__.splitlines()[0])
    parser.add_argument("--output", default="assets/gear/build_gun.glb",
                        help="where the .glb is written")
    parser.add_argument("--tuning", default="content/tuning.toml",
                        help="where the field of view is read from")
    parser.add_argument("--field-of-view", type=float, default=None,
                        help="measure against this vertical field of view in "
                             "degrees instead of the shipped one (used by the "
                             "tests to prove the refusal fires)")
    return parser.parse_args(after)


def field_of_view_degrees(tuning: Path) -> float:
    """The player's vertical field of view, out of `content/tuning.toml`.

    Parsed with a regex rather than by importing anything: nothing in the asset
    pipeline runs GDScript, and `sim/toml_document.gd` is the game's parser. The
    dependency runs one way — `tools/` reads the game's declarations and the game
    has never heard of the asset pipeline — which is the arrangement
    `machine_specs.footprint_authorities` already has with `sim/map_layout.gd`.

    A missing key is an error naming the file, because resolving it to a
    plausible default is exactly the silence #61 closed.
    """
    import re
    text = tuning.read_text()
    match = re.search(rf"^\s*{FIELD_OF_VIEW_KEY}\s*=\s*([0-9.]+)\s*$",
                      text, re.MULTILINE)
    if match is None:
        raise SystemExit(
            f"error: {tuning} declares no {FIELD_OF_VIEW_KEY}. The Build Gun's "
            f"framing is measured against it and cannot be guessed.")
    return float(match.group(1))


def clear_scene() -> None:
    """A genuinely empty scene. `--factory-startup` gives a clean Blender, not a
    clean scene, and a leaked object would be a part floating in frame."""
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.actions):
        for item in list(collection):
            collection.remove(item, do_unlink=True)


def viewmodel_materials() -> dict[str, bpy.types.Material]:
    """The palette as Blender materials, flat, for a model nothing will re-material.

    `machine_materials.build_blender_materials(textured=False)` in all but name,
    and it is spelled out here rather than called because the two are the same
    numbers for **different reasons** and only one of them is load-bearing. A
    Machine's `.glb` carries the palette flat because Godot's importer is about to
    throw that material away and substitute the textured one; this one carries it
    flat because it is read at runtime with `GLTFDocument.append_from_file` and
    **what is in the file is what renders**. The precedent that settles the value
    is the Wall: it is drawn with the palette's own `WeldedSteel` and nothing
    else, and it reads correctly in the world.

    Worth recording, because an hour was spent getting it wrong in both
    directions. The first render after the model was reframed showed a
    tool-shaped nothing, which read as "the palette is too dark to use flat" — the
    palette's own comment says *"Where a material has a texture, THE TEXTURE
    CARRIES THE COLOUR"*, so an argument was available for brightening every
    textured entry towards its `texture_tint`. That argument is wrong and the
    render that seemed to support it was showing a different bug: the model was
    sitting at its stowed pose, half a metre under the bottom of the frame, for
    the `remove_immutable_tracks` reason in `WeaponViewmodel._load`. Brightened,
    the tool measured **(212, 187, 146) against a ground of (24, 22, 18)** — eight
    times the brightness of anything else in frame, which is #42's Wall and
    Machine-placeholder mistake made a third time. **Measure a colour against what
    will be beside it, and fix the bug you have rather than the one the symptom
    suggests.**
    """
    built: dict[str, bpy.types.Material] = {}
    for entry in machine_materials.load():
        material = bpy.data.materials.new(entry["name"])
        principled = material.node_tree.nodes["Principled BSDF"]
        principled.inputs["Base Color"].default_value = tuple(entry["base_color"])
        principled.inputs["Metallic"].default_value = entry["metallic"]
        principled.inputs["Roughness"].default_value = entry["roughness"]
        built[entry["name"]] = material
    return built


def emissive_material() -> bpy.types.Material:
    """The projector lens and rail: a light rather than a palette surface.

    Unshaded is not expressible in glTF, so this is an emissive Principled BSDF —
    which is what `WeaponViewmodel` gets when it loads the file at runtime, and
    what the placeholder's `SHADING_MODE_UNSHADED` was standing in for. The
    strength is what keeps the rail reading as lit when the player faces away
    from the sun, which is the failure the placeholder's unshaded material was
    avoiding.
    """
    material = bpy.data.materials.new(recipe.EMISSIVE_MATERIAL)
    tree = material.node_tree
    principled = tree.nodes["Principled BSDF"]
    principled.inputs["Base Color"].default_value = recipe.EMISSIVE_COLOUR
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Roughness"].default_value = 0.35
    principled.inputs["Emission Color"].default_value = recipe.EMISSIVE_COLOUR
    principled.inputs["Emission Strength"].default_value = recipe.EMISSIVE_STRENGTH
    return material


def rest_pose() -> Matrix:
    """How the tool is held, about the grip. See `build_gun_recipe.REST_YAW_DEGREES`.

    Baked into the **geometry** rather than applied to the root object, because
    the root's own transform has to stay identity: it is what the two swap takes
    animate, and a rest rotation living there would be a second thing for them to
    fight over — and the frustum measurement reads the vertices, so baking it in
    is also what keeps the measurement honest about the pose that ships.
    """
    pivot = Vector(recipe.GRIP)
    turn = (Matrix.Rotation(math.radians(recipe.REST_YAW_DEGREES), 4, 'Z')
            @ Matrix.Rotation(math.radians(recipe.REST_PITCH_DEGREES), 4, 'X'))
    return Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot)


def build(palette: dict) -> bpy.types.Object:
    """Assemble the tool and return the root everything hangs off."""
    assembly = parts.Assembly()
    recipe.build(assembly)
    held = rest_pose()

    root = bpy.data.objects.new(ROOT_NAME, None)
    bpy.context.scene.collection.objects.link(root)

    # One object per material, in sorted order, so the glTF's node, mesh and
    # material arrays come out in the same order on every run. Byte
    # reproducibility is what makes re-running the generator a reviewable diff
    # rather than noise, and it is what `test_build_gun.py` proves.
    for name in assembly.materials():
        mesh_data = bpy.data.meshes.new(f"build_gun_{name}")
        mesh = assembly.take(name)
        bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
        # UVs before the pose, so the world-space projection is taken off the
        # tool's own axes rather than off the angle it happens to be held at.
        parts.box_project_uvs(mesh)
        bmesh.ops.transform(mesh, matrix=held, verts=mesh.verts)
        mesh.to_mesh(mesh_data)
        mesh.free()
        mesh_data.materials.append(palette[name])
        for polygon in mesh_data.polygons:
            # Flat-shaded, like every generated Machine: the chamfers are the
            # only highlight this geometry gets.
            polygon.use_smooth = False
        obj = bpy.data.objects.new(f"build_gun_{name}", mesh_data)
        obj.parent = root
        bpy.context.scene.collection.objects.link(obj)
    return root


def lay_out_takes(root: bpy.types.Object) -> dict[str, float]:
    """Keyframe each take onto the root and put it on an NLA track of its name.

    NLA tracks rather than bare actions, for the reason `fbx_to_viewmodel.py`
    uses them: the exporter's `NLA_TRACKS` mode writes one glTF animation per
    track named for the track, which is what `WeaponViewmodel.CLIP_NEEDLES`
    matches `draw` and `putaway` against. A single assigned action would export
    as one animation and the three takes would be one.

    **`ACTIONS` mode is the obvious alternative and it exports nothing**, which is
    worth knowing before somebody tries it: it walks the actions reachable from
    the objects, and these are built, keyed and then unassigned, so there is
    nothing for it to find. Fake users keep them in the file and do not put them
    back in its way.

    Two settings here are load-bearing and neither is obvious; both are about the
    same thing, which is that **a take that does not move is a take both ends of
    this pipeline will throw away.** `strip.extrapolation` is `NOTHING` so a strip
    does not hold its first frame over every frame outside it, and
    `export_optimize_animation_keep_anim_object` below keeps the `Idle` take,
    whose whole content is one pose. Godot has the identical optimisation on the
    way in and `WeaponViewmodel._load` turns it off for the identical reason.

    Returns each take's length in seconds, which is what the generator prints and
    what a swap on screen is actually timed by.
    """
    root.animation_data_create()
    lengths: dict[str, float] = {}
    frames = max(1, round(recipe.TAKE_SECONDS * FPS))
    for name, keys in recipe.TAKES:
        action = bpy.data.actions.new(name)
        # A fake user, or Blender drops an action with nothing assigned to it
        # before the exporter ever walks the list.
        action.use_fake_user = True
        # Blender 4.4+ puts keyframes in slotted layers; assigning the action to
        # the object first is what gives it a slot to write into, and it is the
        # one piece of this that is a Blender-version detail rather than a
        # decision.
        root.animation_data.action = action
        if hasattr(root.animation_data, "action_slot"):
            root.animation_data.action_slot = action.slots.new(id_type='OBJECT',
                                                               name=name)
        for fraction, offset, roll in keys:
            frame = 1 + fraction * (frames - 1 if frames > 1 else 0)
            root.location = Vector(offset)
            root.rotation_euler = Matrix.Rotation(
                math.radians(roll), 3, 'Y').to_euler()
            root.keyframe_insert("location", frame=frame)
            root.keyframe_insert("rotation_euler", frame=frame)
        root.animation_data.action = None
        track = root.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.extrapolation = 'NOTHING'
        lengths[name] = frames / float(FPS)

    # Leave nothing assigned and the root at rest, so the node's own transform in
    # the file is the pose the recipe declares rather than a frame of a take.
    root.animation_data.action = None
    root.location = Vector((0.0, 0.0, 0.0))
    root.rotation_euler = (0.0, 0.0, 0.0)
    return lengths


def half_angles(fov_degrees: float) -> tuple[float, float]:
    """The frustum's horizontal and vertical half-angles, in degrees.

    Godot's `Camera3D.fov` is the **vertical** angle under the default
    `KEEP_HEIGHT`, so the vertical half-angle is half of it outright and the
    horizontal one follows from the aspect ratio through the tangents.
    """
    vertical = fov_degrees / 2.0
    horizontal = math.degrees(math.atan(math.tan(math.radians(vertical)) * ASPECT))
    return horizontal, vertical


def _pose(offset, roll: float) -> Matrix:
    return Matrix.Translation(offset) @ Matrix.Rotation(math.radians(roll), 4, 'Y')


def _angles(root: bpy.types.Object, pose: Matrix,
            forward_of: float | None) -> dict:
    """The worst corner of the model in one pose, in the camera's own axes.

    Forward is Blender +Y here — the exporter sends it to glTF -Z, which is the
    way a Godot camera looks — so the angle off the view axis in each of the two
    frame axes is the arc-tangent of that axis over the forward distance.

    A vertex **behind** the eye is counted rather than turned into an angle,
    because `atan` of a negative forward distance is a perfectly
    reasonable-looking number and that is the failure that shipped once.
    """
    worst = {"horizontal": 0.0, "vertical": 0.0, "behind": 0,
             "nearest_forward": float("inf"), "counted": 0}
    for child in root.children:
        if child.type != 'MESH':
            continue
        for vertex in child.data.vertices:
            point = pose @ (child.matrix_local @ vertex.co)
            forward = point.y
            worst["nearest_forward"] = min(worst["nearest_forward"], forward)
            if forward <= 0.0:
                worst["behind"] += 1
                continue
            if forward_of is not None and forward < forward_of:
                continue
            worst["counted"] += 1
            worst["horizontal"] = max(
                worst["horizontal"], math.degrees(math.atan(abs(point.x) / forward)))
            worst["vertical"] = max(
                worst["vertical"], math.degrees(math.atan(abs(point.z) / forward)))
    return worst


def measure(root: bpy.types.Object, fov_degrees: float) -> dict:
    """Three measurements, and the second two point in opposite directions.

    The first attempt here measured every vertex of every keyframe against the
    frustum and refused the model, correctly, for a reason that turned out to be
    the measurement's own: **the stowed pose is supposed to be out of frame.**
    That is what being stowed means, and a check that forbade it would forbid the
    holster. So the rule had to say what it actually meant, and saying it split it
    in three:

    * **Nothing is behind the eye, in any pose.** The unconditional one, and the
      one defect that has actually shipped in this project
      (`convert_weapons.sh`'s `--offset=0.0,0.0,-0.10`). A part behind the camera
      is not merely off screen, it is inside out.
    * **The business end is inside the frame at rest.** Not the whole model: a
      viewmodel's grip and the hand around it run off the bottom edge of the
      screen in every first-person game ever shipped, and insisting otherwise
      would mean a tool held at arm's length in the middle of the view. What has
      to be visible is what carries the silhouette — the flared emitter, the
      hazard collar, the hopper and the rail — because the silhouette is the
      whole of what #64 is about. `BUSINESS_END_FROM` is where that starts.
    * **The business end is *outside* the frame when stowed.** The opposite
      direction, and it is what makes a `Draw` read as the tool coming up into
      frame rather than sliding about inside it. Without it the two takes are
      decoration.
    """
    horizontal_limit, vertical_limit = half_angles(fov_degrees)
    business_from = recipe.GRIP[1] + recipe.BODY_LENGTH * BUSINESS_END_FROM
    rest = _angles(root, _pose((0.0, 0.0, 0.0), 0.0), business_from)
    stowed = _angles(root, _pose(recipe.STOWED_OFFSET,
                                recipe.STOWED_ROLL_DEGREES), business_from)
    behind = 0
    whole = _angles(root, _pose((0.0, 0.0, 0.0), 0.0), None)
    for _name, keys in recipe.TAKES:
        for _fraction, offset, roll in keys:
            behind += _angles(root, _pose(offset, roll), None)["behind"]
    return {
        "horizontal_limit": horizontal_limit, "vertical_limit": vertical_limit,
        "business_from": business_from,
        "rest": rest, "stowed": stowed, "whole": whole, "behind": behind,
    }


def report(worst: dict, fov_degrees: float) -> bool:
    """Print the measurement and say whether the framing holds."""
    horizontal_allowed = worst["horizontal_limit"] * MARGIN
    vertical_allowed = worst["vertical_limit"] * MARGIN
    rest, stowed, whole = worst["rest"], worst["stowed"], worst["whole"]
    print(f"  field of view        {fov_degrees:.1f} deg vertical, "
          f"{ASPECT:.3f} aspect")
    print(f"  frustum half-angles  {worst['horizontal_limit']:.1f} deg "
          f"horizontal, {worst['vertical_limit']:.1f} deg vertical")
    print(f"  business end from    {worst['business_from'] * 100.0:.1f} cm "
          f"forward ({rest['counted']} vertices)")
    print(f"  at rest, business    {rest['horizontal']:.1f} deg horizontal "
          f"(allowed {horizontal_allowed:.1f}), "
          f"{rest['vertical']:.1f} deg vertical (allowed {vertical_allowed:.1f})")
    print(f"  at rest, whole tool  {whole['horizontal']:.1f} deg horizontal, "
          f"{whole['vertical']:.1f} deg vertical — the grip is allowed off the "
          f"bottom edge")
    print(f"  stowed, business     {stowed['vertical']:.1f} deg vertical "
          f"(must exceed {worst['vertical_limit']:.1f} to be out of frame)")
    print(f"  nearest vertex       {whole['nearest_forward'] * 100.0:.1f} cm "
          f"in front of the eye")
    ok = True
    if worst["behind"]:
        print(f"  ERROR: {worst['behind']} vertices are behind the camera in "
              f"some pose")
        ok = False
    if (rest["horizontal"] > horizontal_allowed
            or rest["vertical"] > vertical_allowed):
        print("  ERROR: the business end leaves the frame at rest")
        ok = False
    if stowed["vertical"] <= worst["vertical_limit"]:
        print("  ERROR: the stowed pose is still in frame, so a draw does not "
              "read as the tool coming up into it")
        ok = False
    return ok


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format='GLB',
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_nla_strips=True,
        export_force_sampling=True,
        # **Keep a take that does not move.** The exporter's size optimisation
        # drops a channel whose value never changes, and an animation left with
        # no channels is dropped with it — so the `Idle` take, which is one key
        # at rest *on purpose*, exported as nothing at all and the model came
        # back carrying only `Draw` and `PutAway`. That is the same defect as the
        # frozen rest pose above wearing a different hat, and it is silent in the
        # same way: the file is valid, it is smaller, and the thing in a player's
        # hands is wrong.
        export_optimize_animation_keep_anim_object=True,
        export_skins=False,
        export_morph=False,
        export_materials='EXPORT',
        # No image goes in the file, exactly as no Machine's does. Unlike a
        # Machine this is loaded at *runtime* through `GLTFDocument` rather than
        # imported, so Godot substitutes nothing and the glTF's own
        # baseColorFactor is what renders — which is why the palette's
        # `base_color` is the authority here and the generated textures are not
        # involved at all.
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
    fov = (args.field_of_view if args.field_of_view is not None
           else field_of_view_degrees(Path(args.tuning)))

    clear_scene()
    palette = viewmodel_materials()
    palette[recipe.EMISSIVE_MATERIAL] = emissive_material()
    root = build(palette)
    lengths = lay_out_takes(root)

    print("Build Gun:")
    worst = measure(root, fov)
    if not report(worst, fov):
        # Refused rather than written. A viewmodel that leaves the frame is the
        # one defect in this corner of the project that no test can see and only
        # a render can, so the generator declines to produce one at all.
        print("\nerror: the Build Gun was not written. Move "
              "`build_gun_recipe.GRIP` or shorten the body; the numbers above "
              "say which axis is the problem.", file=sys.stderr)
        return 1
    for name, seconds in sorted(lengths.items()):
        print(f"  take {name:<10} {seconds:.3f} s")

    destination = Path(args.output)
    export(destination)
    print(f"  wrote {destination} ({destination.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
