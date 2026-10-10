#!/usr/bin/env bash
# Convert the purchased first-person arms into the GLBs the game loads at runtime.
#
#   bash tools/assets/convert_weapons.sh
#
# This file *is* the recipe — which FBX becomes which weapon, and the flags that
# frame it — in the same sense `rebuild_assets.sh` is the recipe for the committed
# characters. The difference is where the output goes and why.
#
# ── The licence, which is the whole shape of this script ──────────────────────
#
# The two packs it reads permit commercial use in a shipped game and **forbid
# redistribution** (docs/ASSETS.md, docs/LICENSED_ASSETS.md). This repository is
# public. So:
#
#   * The input is in `assets_licensed/`, which is gitignored and carries a
#     `.gdignore` so Godot's importer never walks it.
#   * **The output is gitignored too, and that is not an accident.** A converted
#     GLB is a derivative of a non-redistributable asset and is exactly as
#     forbidden as the FBX it came from. `tools/assets/check_licensed_staged.py`
#     blocks it, and that guard is correct: do not work around it.
#   * Therefore the game loads the result **at runtime, from a path that may
#     legitimately not exist**, and draws placeholder boxes when it does not. See
#     `game/weapon_viewmodel.gd`. Anyone cloning this repository without the packs
#     gets a building, testable, playable game — that is the rule, and it is
#     asserted in `tests/cases/test_weapon_viewmodel.gd`.
#
# Which weapon gets which pack, and why:
#
#   bolt_rifle        `L96_animation.fbx`  — the only one with a `Chamber` take,
#                     which is what a bolt-action wants between shots.
#   drum_autocannon   `Akm_animation.fbx`  — the pack's automatic weapon, and it
#                     ships two shot takes.
#   pneumatic_wrench  RgsDev `Arms_Combat_Knife.fbx` — the only rigged arms in the
#                     collection that swing rather than shoot.
#
# Set LICENSED_ROOT if your quarantine is somewhere else, and WEAPON_OUT to write
# the GLBs somewhere other than where the game looks for them.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
blender="${BLENDER:-blender}"
licensed_root="${LICENSED_ROOT:-$repo_root/assets_licensed}"
out_dir="${WEAPON_OUT:-$repo_root/assets_licensed/generated/gear}"

weapon_pack="$licensed_root/fps-weapon-pack-unknown-vendor/Weapon pack"
rgsdev="$licensed_root/rgsdev/_RgsDev Low Poly FPS Starter Kit v1.1/Assets/_RgsDev_FPS/Meshes/Weapons"

if ! command -v "$blender" >/dev/null; then
  echo "error: '$blender' is not on PATH. Set BLENDER=/path/to/blender." >&2
  exit 127
fi
if [ ! -d "$weapon_pack" ] && [ ! -d "$rgsdev" ]; then
  echo "note: no purchased weapon packs under $licensed_root — nothing to convert." >&2
  echo "      The game runs with placeholder weapons; see docs/ASSET_PIPELINE.md §7." >&2
  exit 0
fi

mkdir -p "$out_dir"
convert() {
  "$blender" --background --factory-startup \
    --python "$repo_root/tools/assets/fbx_to_viewmodel.py" -- "$@"
}

# The three skin-tone arm meshes are alternatives, not layers: keep the military
# sleeve and drop the two bare ones. `Camera point controller` and `Character001`
# are authoring rigging with no geometry on them.
pack_drops=(
  --drop-object Male_mesh
  --drop-object Female_mesh
  --drop-object "Camera point controller"
  --drop-object Character001
)

# ── The surfaces, which is #65 ───────────────────────────────────────────────
#
# This recipe used to repaint every material a flat palette colour, on the note
# that "the Weapon pack references textures it does not ship". That is half right
# and the wrong half mattered: **the pack ships a complete PBR set for both
# rifles** — albedo, normal, roughness, metallic and occlusion, for the L96's
# body, its scope and its lens, and for the AKM — and two separate things kept it
# off the model. The basenames in the FBX are not the basenames in the zip
# (`T_S96_ALB.tga.png` against the shipped `L96_ALB.png`, which no normalisation
# rule bridges — it is a vendor typo), and these were authored as 3ds Max
# ShaderFX materials, which Blender's importer drops on the way in with
# `material link b'3dsMax|HwShaderParams|TEX_color_map' ignored` — so the
# materials arrive as bare Principled BSDFs with **nothing connected** and
# recovering the files alone would have changed nothing.
#
# So the maps are bound to channels **by path**, here, where the rest of the
# recipe is. There is no name to guess at and a file that is not there is an
# error naming the material, the channel and the path. See
# `tools/assets/viewmodel_surface.py` for the full measurement.
#
# **The arms are the one thing that genuinely has nothing to recover.** All three
# arm meshes reference `fpArms_Military_D.tga`, `fpArms_AO.tga` and
# `fpArms_NRM.tga` from a `FPS Generic Arms/` folder that is in **neither pack** —
# checked by name across the whole quarantine, which holds not one `fpArms_*`
# file and not one `.tga` at all. (The pack does ship `FPS Arms/Textures/`, but
# those belong to a separate 346-vertex asset with its own unwrap; putting its map
# on the 1422-vertex sleeve would be reading a texture through unrelated UVs.) So
# the sleeve wears the palette's own `OliveDrab` map — literally the surface the
# Machines wear — over world-scale box-projected UVs.
#
# **The metres-per-tile is restated for this viewing distance and only that.**
# The palette's `texture_scale_m` is how many metres one tile covers *on a
# Machine*, which is an object read from metres away; a sleeve is a third of a
# metre long and 40 cm from the eye, so `OliveDrab`'s own 2.4 m would show a
# seventh of one tile and the wear on it would be far too coarse to read as
# fabric. The colour, the metallic, the roughness and which map it is all stay
# the palette's.
sleeve=(--material-surface "Military_arms_mat=OliveDrab,0.25")

if [ -d "$weapon_pack" ]; then
  # Three materials, three map sets. `Lense_mt` is given no metallic map because
  # the pack ships none for it, which is glass being a dielectric rather than the
  # pack being incomplete, and no normal for the same reason.
  convert \
    --input "$weapon_pack/L96_animation.fbx" \
    --output "$out_dir/bolt_rifle.glb" \
    --origin-object Camera001 "${pack_drops[@]}" \
    --rotate=0,0,180 \
    --parent L96_mesh=Main_Bone \
    "${sleeve[@]}" \
    --material-map "Body_mt=albedo:L96_ALB.png,normal:L96_NRM.png,roughness:L96_Roughness.png,metallic:L96_Metallic.png,ao:L96_AO.png" \
    --material-map "Scope_mt=albedo:Scope_ALB.png,normal:Scope_NRM.png,roughness:Scope_Roughness.png,metallic:Scope_Metallic.png,ao:Scope_AO.png" \
    --material-map "Lense_mt=albedo:Lens_ALB.png,roughness:Lens_Roughness.png" \
    --texture-dir "$weapon_pack/L96_textures"

  # `normal_dx` rather than `normal`, because the pack says which convention its
  # map is in and it says DirectX — whose green channel is inverted against the
  # one glTF reads. Left alone it lights every slope on the receiver from the
  # opposite side, which reads as the sun being in the wrong place rather than as
  # a texture being upside down.
  convert \
    --input "$weapon_pack/Akm_animation.fbx" \
    --output "$out_dir/drum_autocannon.glb" \
    --origin-object Camera001 "${pack_drops[@]}" \
    --rotate=0,0,180 \
    --parent AK_mesh=ak_main_bn \
    "${sleeve[@]}" \
    --material-map "AK_mat=albedo:Base_Color.png,normal_dx:Normal.png,roughness:Roughness.png,metallic:Metallic.png,ao:AO.png" \
    --texture-dir "$weapon_pack/Akm_textures"
else
  echo "note: $weapon_pack is absent; the two ranged weapons keep their placeholders." >&2
fi

# RgsDev ships no authoring camera, so there is no `--origin-object` to frame
# against and the eye has to be placed by hand. Two mistakes have been made here
# and both of them cost a player the swing, so the reasoning is written down.
#
# **`Prefabs/FPSController.prefab` parents these arms to a `WeaponHolder` at
# (0, 0, 0) under the camera, so the model's own origin is the eye** — which is
# true and is not the framing. A first-person rig authored that way is posed
# around a camera that is also carrying a near plane and a field of view, and the
# hands sit about 21 cm in front of the origin and 20 cm to the right of it. At
# that distance the knife hand is 44 degrees off the axis at rest and the swing
# throws it *behind* the camera. So the origin being the eye is the reason this
# recipe needs an offset, not the reason it does not.
#
# **The middle number is forward, and forward is away from the viewer.** An
# offset is written in Blender's axes, where +Y is the horizontal depth axis the
# exporter's Y-up conversion sends to glTF -Z — which is the way a Godot camera
# looks, so a positive middle number pushes the model *out in front of the eye*.
# `tools/assets/tests/test_fbx_to_viewmodel.py` pins that axis. Reading it as
# "into the camera" is how `--offset=0.0,0.0,-0.10` came to ship, and that build
# is the one a player described as the knife animation still not playing: the
# arms filled the frame and the strike left it altogether.
#
# **The number is bracketed by measuring the swing against the frustum**, not by
# taste. `player.field_of_view_degrees` is 75 vertical, which at 16:9 is 53.8
# degrees of horizontal half-angle, and the worst the `Knife_Attack_1_Anim` take
# asks for is the Hand_R bone a third of a second in:
#
#     offset (forward, down)   at rest   worst of the swing
#     0.00, 0.10  (shipped)    43.6 deg  89.7 deg — behind the camera
#     0.16, 0.18  (before it)  28.5 deg  59.2 deg — the strike is off screen
#     0.26, 0.22               23.2 deg  50.6 deg
#     0.30, 0.24               21.5 deg  47.7 deg  <- this
#     0.36, 0.26               19.4 deg  43.8 deg — reads small and low
#
# 0.30 is the nearest framing that keeps the whole swing in frame with room to
# spare: it tolerates the field of view being tuned down to about 68 degrees
# before the strike clips again. `SHOT_SCRIPT=tools/visual/compose_swing_shot.gd
# bash tools/visual/shot.sh out.png` is what renders the strip these were read
# off, and it is the only instrument in the project that can see this defect.
#
# The rig still needs the half turn the Weapon pack does: it reaches along -Y,
# which the conversion would otherwise put behind the camera.
#
# **Every one of its six materials is a palette surface, because this pack ships
# no maps at all** — and that is the asset being what it is rather than an
# omission: a low-poly kit whose Unity materials are flat colours. Its UVs say so
# too, the knife's having 8280x between its tightest and loosest triangle's
# metres-per-UV-unit, which is why they are replaced by a world-scale box
# projection rather than textured through.
#
# The entries are not a re-art-direction: each is the palette material the flat
# colour this recipe used to paint was already approximating, and two of them
# match on every number. `Blade` was `696A6C` at metallic 1 and roughness 0.45,
# which is `WeldedSteel` exactly; `Guard` was `424447` at metallic 1 and 0.62,
# which is `CastIron` exactly. `Gloves`, `Fingers` and `Handle` were all `211F1E`
# at roughness 0.8-0.9, which is `BeltRubber`. And `Skin` was painted `40442F` —
# OliveDrab — by whoever wrote this first, because that mesh is being used as a
# sleeve rather than as a bare forearm; keeping it a sleeve is deliberate.
if [ -d "$rgsdev" ]; then
  convert \
    --input "$rgsdev/Arms_Combat_Knife.fbx" \
    --output "$out_dir/pneumatic_wrench.glb" \
    --scale 1.0 \
    --rotate=0,0,180 \
    --offset=0.0,0.30,-0.24 \
    --material-surface "Skin=OliveDrab,0.25" \
    --material-surface "Gloves=BeltRubber,0.12" \
    --material-surface "Fingers=BeltRubber,0.12" \
    --material-surface "Blade=WeldedSteel,0.5" \
    --material-surface "Guard=CastIron,0.5" \
    --material-surface "Handle=BeltRubber,0.12"
else
  echo "note: $rgsdev is absent; the Pneumatic Wrench keeps its placeholder." >&2
fi

echo
echo "Wrote to $out_dir:"
ls -la "$out_dir"
echo
echo "Nothing in that directory may be committed. It is gitignored and the licence"
echo "guard blocks it; the game loads it at runtime and runs without it."
