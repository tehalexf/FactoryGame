#!/usr/bin/env bash
# Regenerate every Enemy body from the declaration. Headless, no manual steps.
#
#   bash tools/assets/generate_enemies.sh
#   bash tools/assets/generate_enemies.sh --only crawler
#   bash tools/assets/generate_enemies.sh --output-dir /tmp/try
#
# Inputs are tools/assets/enemy_recipe.py (the proportions and the gaits) and
# tools/assets/dieselpunk_palette.json (the shared material palette). Change
# either, re-run this, and the committed .glb files under assets/characters/insects/
# are the new truth. Then:
#
#   bash tools/assets/run_tests.sh   # proves regeneration is byte-for-byte
#   tools/run_tests.sh               # proves the three silhouettes still separate
#
# Set BLENDER=/path/to/blender if it is not on PATH.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
blender="${BLENDER:-blender}"

if ! command -v "$blender" >/dev/null 2>&1; then
  echo "error: '$blender' is not on PATH. Set BLENDER=/path/to/blender." >&2
  exit 127
fi

# --factory-startup so a developer's own add-ons and unit settings cannot change
# what comes out; the generator must produce the same bytes on every machine.
# generate_enemies.py refuses to write a bytecode cache, for the reason written
# there: a stale .pyc generates the wrong body and says nothing.
"$blender" --background --factory-startup \
  --python tools/assets/generate_enemies.py -- "$@"
