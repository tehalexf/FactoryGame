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

echo
echo "rebuilt. Summary of each shipping asset:"
python3 tools/assets/gltf_info.py \
  assets/characters/skeleton/Skeleton.glb \
  assets/characters/knight/KnightCharacter.glb
