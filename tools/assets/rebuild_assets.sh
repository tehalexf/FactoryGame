#!/usr/bin/env bash
# Re-run every committed conversion from its intake FBX.
#
#   bash tools/assets/rebuild_assets.sh
#
# This file *is* the record of how each shipping .glb was produced: the exact
# flags are here, not in someone's shell history. Add a block per asset, and
# record the asset's source and licence in the ledger in docs/ASSETS.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
convert="tools/assets/convert_fbx.sh"

# Quaternius "LowPoly Animated Monsters" — Skeleton. CC0.
# Authored ~5.1 units tall with arms named as duplicated leg chains, so it needs
# both height normalisation and a bone map onto the shared humanoid skeleton.
bash "$convert" \
  --input  assets/characters/skeleton/intake/Skeleton.fbx \
  --output assets/characters/skeleton/Skeleton.glb \
  --target-height 1.8 \
  --root-bone Root \
  --bone-map tools/assets/bone_maps/quaternius_monsters_skeleton.json

# Quaternius "LowPoly Animated Knight" — KnightCharacter. CC0.
# A humanoid rig whose bone names do not line up with the profile by name (see
# the bone map) and which is ~5.6 units tall.
bash "$convert" \
  --input  assets/characters/knight/intake/KnightCharacter.fbx \
  --output assets/characters/knight/KnightCharacter.glb \
  --target-height 1.8 \
  --root-bone Root \
  --bone-map tools/assets/bone_maps/quaternius_knight.json

# KayKit "Character Pack: Skeletons" 1.1 (SOURCE tier) — six characters and four
# animation libraries. CC0, Kay Lousberg.
#
# One scale factor, 0.830981, is shared by every file in the pack instead of
# per-file --target-height. The factor is the one --target-height 1.8 measures on
# Skeleton_Minion, the bare skeleton: normalising each file to 1.8 m separately
# would shrink the Mage by the height of its hat and the Golem from a giant to a
# human, and the animation libraries have to be scaled identically to the
# characters or borrowed root and hips translation lands in the wrong place.
#
# The Rig_Medium characters therefore stand ~1.8 m and Skeleton_Golem, on the
# larger rig, stands ~3.51 m, which is the size relationship the artist authored.
kaykit_scale=0.830981
kaykit_textures=assets/characters/kaykit_skeletons/intake_textures
kaykit_bones=tools/assets/bone_maps/kaykit_skeletons.json

for kaykit_character in minion:Skeleton_Minion warrior:Skeleton_Warrior \
    rogue:Skeleton_Rogue mage:Skeleton_Mage necromancer:Necromancer \
    golem:Skeleton_Golem; do
  kaykit_dir="assets/characters/kaykit_skeletons/${kaykit_character%%:*}"
  kaykit_name="${kaykit_character##*:}"
  bash "$convert" \
    --input  "$kaykit_dir/intake/$kaykit_name.fbx" \
    --output "$kaykit_dir/$kaykit_name.glb" \
    --scale "$kaykit_scale" \
    --root-bone Root \
    --bone-map "$kaykit_bones" \
    --texture-dir "$kaykit_textures"
done

# The pack ships animation separately from the characters, which is exactly the
# arrangement docs/ASSET_PIPELINE.md section 4 asks for: clips on the shared
# skeleton, in their own .glb, loaded into an AnimationLibrary rather than
# duplicated per character.
for kaykit_library in Rig_Medium_General Rig_Medium_MovementBasic \
    Rig_Large_General Rig_Large_MovementBasic; do
  bash "$convert" \
    --input  "assets/characters/kaykit_skeletons/animations/intake/$kaykit_library.fbx" \
    --output "assets/characters/kaykit_skeletons/animations/$kaykit_library.glb" \
    --scale "$kaykit_scale" \
    --root-bone Root \
    --bone-map "$kaykit_bones" \
    --texture-dir "$kaykit_textures"
done

# Machines are generated rather than converted: there is no intake file, the
# script *is* the asset. See docs/ASSET_PIPELINE.md section 7.
bash tools/assets/generate_machines.sh

echo
echo "rebuilt. Summary of each shipping asset:"
python3 tools/assets/gltf_info.py \
  assets/characters/skeleton/Skeleton.glb \
  assets/characters/knight/KnightCharacter.glb \
  assets/characters/kaykit_skeletons/*/[A-Z]*.glb
