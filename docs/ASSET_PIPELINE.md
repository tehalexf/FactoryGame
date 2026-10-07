# Asset pipeline: FBX in, glTF out, one shared skeleton

This is the repeatable path from a purchased or CC0 asset to something the game
loads, and the enforcement that keeps non-redistributable assets out of a public
repository. Licence rules live in [ASSETS.md](ASSETS.md); this document is the
mechanism.

Everything here runs headless and is covered by tests:

    bash tools/assets/run_tests.sh      # the licence guard plus 42 pipeline tests

## 1. The licence guard

The repository is public. `assets_licensed/` is gitignored, but `.gitignore` is
advisory — `git add -f`, a wildcard add or a stale index all defeat it. The guard
is the enforcement:

    python3 tools/assets/check_licensed_staged.py          # staged + history
    python3 tools/assets/check_licensed_staged.py --all     # every tracked file

It fails, loudly and non-zero, when

* anything staged lives under `assets_licensed/`,
* anything **already committed** lives under `assets_licensed/` — a past mistake
  keeps failing until it is removed, rather than passing because nothing is
  staged today,
* a staged path names a vendor whose licence forbids redistribution (Synty,
  Sonniss, Mixamo, Megascans, MetaHuman, …) even outside the quarantine
  directory, because renaming a purchased file does not launder it.

It is wired in two places so it cannot be forgotten:

    bash tools/git/install_hooks.sh     # once per clone: pre-commit hook

sets `core.hooksPath` to `tools/git/githooks`, so the hook is version-controlled
and shared rather than living in one developer's `.git/hooks`. And
`.github/workflows/assets.yml` runs the same guard with `--all` on every push and
pull request, which catches anyone who never ran the installer.

Do not bypass the guard. If it objects to a path, the path is wrong.

## 2. FBX to glTF

FBX is an intake format only. The conversion is one command:

    tools/assets/convert_fbx.sh \
        --input  assets/characters/knight/intake/KnightCharacter.fbx \
        --output assets/characters/knight/KnightCharacter.glb \
        --target-height 1.8 \
        --root-bone Root \
        --bone-map tools/assets/bone_maps/quaternius_knight.json

That wraps `blender --background --factory-startup --python
tools/assets/fbx_to_gltf.py`; run it with `--help` for every flag. Set
`BLENDER=/path/to/blender` if it is not on `PATH`.

Every committed asset's exact conversion command lives in
`tools/assets/rebuild_assets.sh`, which re-derives every shipping `.glb` from its
intake FBX. That file *is* the recipe — not someone's shell history:

    bash tools/assets/rebuild_assets.sh

### What the converter corrects, and why each one bites

| Breakage | What arrives | What the pipeline does |
|---|---|---|
| Multiple root bones | Weapon sockets, prop handles and stray armature bones left unparented | Reparents every root under one root bone (`--root-bone`, default `Root`) |
| Unity/Unreal scale | Characters authored in centimetres, so 100x or 0.01x out | `--scale` for a known factor, `--target-height` to normalise by measurement; the scale is then *applied*, not left on the object |
| Axis conventions | A residual rotation on the armature, very often 180° about Z | Bakes rotation and scale so every exported transform is identity, leaving the glTF exporter's +Y-up conversion as the only axis change |
| Duplicated textures | The same PNG imported two or three times (`skin.png`, `skin.png.001`) | Merges images by content hash and by resolved path, so each texture is embedded once |
| Broken texture paths | Absolute authoring paths such as `C:/Dropbox/.../T_Skin.png` | `--texture-dir` finds the file by name in the directories you name; anything still missing is dropped rather than exported as a broken reference |
| Surplus UV layers | Unity-targeted meshes carrying four | `--keep-uv-layers` (default 1) |
| Exporter leaf bones | `Head_end`, `ball_leaf_l` padding every chain | Deletes childless bones with those suffixes (`--leaf-bone-suffix`, default `_end`) |
| Unweighted vertices | Blender's glTF exporter invents a `neutral_bone` joint, giving the rig a *second* skeleton root | Weights orphan vertices to the root bone so no `neutral_bone` is created |
| Mangled take names | Actions named `Armature\|Armature\|Walk`, which is what Godot then shows in the AnimationPlayer | Strips the prefixes |
| Divergent rigs | Every pack names its bones differently | `--bone-map` renames onto the shared humanoid skeleton (below) |

## 3. The shared humanoid skeleton

**Every humanoid character uses Godot's `SkeletonProfileHumanoid` bone names.**

That is the convention, in full: `Root`, `Hips`, `Spine`, `Chest`, `UpperChest`,
`Neck`, `Head`, `Left`/`RightShoulder`, `UpperArm`, `LowerArm`, `Hand`, the
finger chains, `Left`/`RightUpperLeg`, `LowerLeg`, `Foot`, `Toes` — 56 names in
Godot 4.7. Dump the authoritative list from the engine rather than copying it:

    godot --headless --script - <<'GD'
    extends SceneTree
    func _init() -> void:
        var p := SkeletonProfileHumanoid.new()
        for i in p.bone_size:
            print(p.get_bone_name(i), " <- ", p.get_bone_parent(i))
        quit()
    GD

Why this profile rather than one pack's rig: it is what Godot's own retargeting
(`BoneMap`, the importer's retarget options, `SkeletonProfileHumanoid`) is built
around, so a rig named this way needs no translation layer at runtime. The
Quaternius Universal Base Characters / Universal Animation Library rig is the
reference humanoid *source*, and
`tools/assets/bone_maps/quaternius_universal_humanoid.json` maps it onto the
profile.

Conventions that go with the names:

* **Metres.** Characters are normalised to human scale (1.8 m) with
  `--target-height`.
* **One root bone**, named `Root`.
* **Identity transforms** on the exported armature and meshes.
* **+Y up**, from the glTF exporter — no manual axis juggling anywhere else.

### Bone maps

A bone map is a JSON object of source bone name → shared skeleton bone name.
Keys starting with `_` are commentary. The committed maps are worked examples of
the three things that go wrong:

| Map | What it teaches |
|---|---|
| `quaternius_universal_humanoid.json` | The reference rig: Unreal-style names (`pelvis`, `spine_01`, `clavicle_l`) onto the profile |
| `quaternius_monsters_skeleton.json` | The artist built the arms by duplicating the leg chains, so they arrive as `L.UpperLeg.001`. Bone positions, not names, identify them |
| `quaternius_knight.json` | Names must be mapped by **position in the hierarchy**, not by name: the source `Body` is the parent of both spine and legs, so it is the profile's `Hips`, and the source `Hips` becomes `Spine` |

The converter renames in two passes through temporary names, so a map that
shifts names along a chain (`Hips` → `Spine` while another bone becomes `Hips`)
does not collide into `Hips.001`. Bones the map does not mention are kept and
reported — never silently renamed. Animation fcurve paths are rewritten with the
bones, so animation keeps driving the bone it was authored for.

## 4. The retarget path

Because every rig is converted onto the same names, retargeting is mostly
*already done* by the time an asset is in the repo. In practice:

1. **Convert with a bone map.** After this, the character's `Skeleton3D` bone
   names are shared-skeleton names. Verify with
   `tools/assets/verify_in_godot.sh`, which fails if the core chain (`Root`,
   `Hips`, `Spine`, `Neck`, `Head`, upper/lower arms and legs) is missing or if
   any bone is a near-miss variant such as `Hips.001`.
2. **Borrow animation directly.** An `Animation` resource from one character's
   `AnimationPlayer` drives another character's skeleton once its track paths are
   re-rooted at the recipient's `Skeleton3D`. No `BoneMap`, no per-frame
   conversion. Proven, headlessly, by:

       bash tools/assets/verify_retarget_in_godot.sh \
           assets/characters/skeleton/Skeleton.glb Skeleton_Running \
           assets/characters/knight/KnightCharacter.glb

   which reports how many of the donor's bone tracks the recipient can use and
   fails if the borrowed animation does not actually move the recipient's bones.
3. **Keep shared animation in one place.** Animation that is meant for every
   humanoid belongs in its own `.glb` of animation-only clips on the shared
   skeleton, loaded into an `AnimationLibrary`, rather than duplicated per
   character.
4. **When a rig cannot be renamed** — a licensed pack you must not modify, or a
   rig whose hierarchy differs structurally — fall back to Godot's `BoneMap`
   with `SkeletonProfileHumanoid` on the import, which is the same mapping
   expressed at import time instead of at conversion time.

Limits worth knowing. Name mapping gives interchange where the hierarchy agrees.
The knight's feet are parented to the rig root rather than the shin because its
legs are IK-driven, so its animation keys are local to that parent; the pipeline
maps the names but deliberately does not reparent, because reparenting would
break every animation in the pack. Sparse rigs are fine — the monster skeleton
has 13 bones and no shoulders, hands or feet — they simply cover a subset of the
profile, and a `BoneMap` leaves the missing entries empty.

## 5. Verifying

| Command | What it proves |
|---|---|
| `bash tools/assets/run_tests.sh` | Everything below, plus the converter's behaviour against FBX fixtures that reproduce each breakage |
| `python3 tools/assets/gltf_info.py <file.glb>` | What a glTF actually contains — skeleton roots, bones, animations, images, extents. Standard library only, so it can be trusted to check Blender's output |
| `bash tools/assets/verify_in_godot.sh <file.glb> [height] [min-animations]` | Godot's own importer accepts the file, the rig is single-rooted with shared-skeleton names, and every animation moves bones when played |
| `bash tools/assets/verify_retarget_in_godot.sh <donor> <animation> <recipient>` | Animation is interchangeable between characters |

The FBX fixtures are generated, not committed:
`tools/assets/tests/build_fixtures.py` builds a small FBX per breakage (multiple
roots, Unity scale and rotation, duplicated textures, relocated textures, orphan
weights, mangled take names) so each correction is tested against a file that
genuinely exhibits the fault.

## 6. Adding an asset

1. Check the licence. CC0 / permissive / self-authored → `assets/`. Anything
   else → `assets_licensed/`, which never enters git.
2. Put the intake FBX in `assets/<kind>/<name>/intake/` so the conversion stays
   reproducible, with an empty `.gdignore` beside it. Godot would otherwise
   import the FBX as a second, uncorrected copy of the character that someone
   could use by mistake; FBX is intake only.
3. Write or reuse a bone map if it is a humanoid.
4. Add the conversion to `tools/assets/rebuild_assets.sh` and run it.
5. Verify with `verify_in_godot.sh`, and with `verify_retarget_in_godot.sh` if it
   is a humanoid.
6. Record source and licence in the ledger in [ASSETS.md](ASSETS.md).
7. Commit. The pre-commit guard runs; CI runs it again.
