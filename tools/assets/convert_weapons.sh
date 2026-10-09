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

# The Weapon pack references textures it does not ship — the FBX carries the
# authoring machine's paths and the zip's own files are named differently — so
# every surface arrives white. These are `tools/assets/dieselpunk_palette.json`
# values, the same ones the generated Machines wear, so the thing in the player's
# hands belongs to the same world as the thing they built it with.
sleeve=(--material-colour "Military_arms_mat=40442F,0,0.58")   # OliveDrab

if [ -d "$weapon_pack" ]; then
  convert \
    --input "$weapon_pack/L96_animation.fbx" \
    --output "$out_dir/bolt_rifle.glb" \
    --origin-object Camera001 "${pack_drops[@]}" \
    --rotate=0,0,180 \
    --parent L96_mesh=Main_Bone \
    "${sleeve[@]}" \
    --material-colour "Body_mt=555557,1,0.18" \
    --material-colour "Scope_mt=424447,1,0.62" \
    --material-colour "Lense_mt=C4C4BF,0,0.12" \
    --texture-dir "$weapon_pack/L96_textures"

  convert \
    --input "$weapon_pack/Akm_animation.fbx" \
    --output "$out_dir/drum_autocannon.glb" \
    --origin-object Camera001 "${pack_drops[@]}" \
    --rotate=0,0,180 \
    --parent AK_mesh=ak_main_bn \
    "${sleeve[@]}" \
    --material-colour "AK_mat=424447,1,0.55" \
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
if [ -d "$rgsdev" ]; then
  convert \
    --input "$rgsdev/Arms_Combat_Knife.fbx" \
    --output "$out_dir/pneumatic_wrench.glb" \
    --scale 1.0 \
    --rotate=0,0,180 \
    --offset=0.0,0.30,-0.24 \
    --material-colour "Skin=40442F,0,0.58" \
    --material-colour "Gloves=211F1E,0,0.8" \
    --material-colour "Fingers=211F1E,0,0.8" \
    --material-colour "Blade=696A6C,1,0.45" \
    --material-colour "Guard=424447,1,0.62" \
    --material-colour "Handle=211F1E,0,0.9"
else
  echo "note: $rgsdev is absent; the Pneumatic Wrench keeps its placeholder." >&2
fi

echo
echo "Wrote to $out_dir:"
ls -la "$out_dir"
echo
echo "Nothing in that directory may be committed. It is gitignored and the licence"
echo "guard blocks it; the game loads it at runtime and runs without it."
