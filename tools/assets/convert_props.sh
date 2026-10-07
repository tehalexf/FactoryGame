#!/usr/bin/env bash
# Convert the purchased set-dressing props into the GLBs the game loads at runtime.
#
#   bash tools/assets/convert_props.sh
#
# The sibling of `convert_weapons.sh`, and the same shape for the same reason:
# the packs it reads permit commercial use in a shipped game and **forbid
# redistribution** (docs/ASSETS.md, docs/LICENSED_ASSETS.md), this repository is
# public, so the input is quarantined, **the output is gitignored too**, and the
# game loads the result at runtime from a path that may legitimately not exist.
# `game/set_dressing.gd` draws self-authored stand-ins when it does not, which on
# most clones is always. Do not work around the licence guard.
#
# Which pack supplies what, and why, is `tools/assets/convert_props.py` — it is
# the catalogue as well as the converter, because the selection is the decision
# and the rewriting is mechanical. The short version:
#
#   heyheythere   Everything near the player. It is on a **2 m grid at 1 unit to
#                 the metre, which is our grid**, so its props sit on our tiles
#                 with no scale factor, and all 213 share one atlas.
#   lukami-ch     A free-standing floodlight mast, a silo and a water tank.
#                 heyheythere's lights are all wall and ceiling fittings.
#   shapita       A shipping container and a yard light, for the skyline only.
#
# Needs nothing but python3: it is a glTF chunk rewriter, not a Blender recipe.
#
# Set LICENSED_ROOT if your quarantine is somewhere else, and PROP_OUT to write
# the GLBs somewhere other than where the game looks for them.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
licensed_root="${LICENSED_ROOT:-$repo_root/assets_licensed}"
out_dir="${PROP_OUT:-$repo_root/assets_licensed/generated/props}"

if [ ! -d "$licensed_root" ]; then
  echo "note: no quarantine at $licensed_root — nothing to convert." >&2
  echo "      The game runs with self-authored set dressing; see docs/ASSET_PIPELINE.md." >&2
  exit 0
fi

python3 "$repo_root/tools/assets/convert_props.py" \
  --licensed-root "$licensed_root" --out "$out_dir"

echo
echo "Nothing in $out_dir may be committed. It is gitignored and the licence"
echo "guard blocks it; the game loads it at runtime and runs without it."
