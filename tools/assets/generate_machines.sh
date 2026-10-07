#!/usr/bin/env bash
# Regenerate every Machine mesh from the declaration. Headless, no manual steps.
#
#   bash tools/assets/generate_machines.sh
#   bash tools/assets/generate_machines.sh --only smelter_mk1
#   bash tools/assets/generate_machines.sh --output-dir /tmp/try
#
# Inputs are content/machines.csv (footprints), content/machine_ports.csv (ports),
# tools/assets/dieselpunk_palette.json (the shared material palette) and
# tools/assets/machine_recipes.py (the geometry). Change any of them, re-run this,
# and the committed .glb files are the new truth. Then:
#
#   bash tools/assets/run_tests.sh      # proves the meshes still match the grid
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
"$blender" --background --factory-startup \
  --python tools/assets/generate_machines.py -- "$@"
