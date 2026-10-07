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

# RgsDev has no authoring camera at all, so the arms are framed by hand. The rig
# is in metres with its origin at the neck and the arms reaching along -Y, so it
# needs the same half turn the Weapon pack does and a drop to put the eye above
# the shoulders rather than between them. These numbers came from looking at the
# render, which is the only way to find them.
if [ -d "$rgsdev" ]; then
  convert \
    --input "$rgsdev/Arms_Combat_Knife.fbx" \
    --output "$out_dir/pneumatic_wrench.glb" \
    --scale 1.0 \
    --rotate=0,0,180 \
    --offset=0.0,0.16,-0.18 \
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
