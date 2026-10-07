#!/usr/bin/env bash
# Convert an intake FBX to a shipping .glb. A thin wrapper so nobody has to
# remember Blender's headless invocation:
#
#   tools/assets/convert_fbx.sh --input Hero.fbx --output assets/x/Hero.glb \
#       --target-height 1.8 --bone-map tools/assets/bone_maps/....json
#
# Every flag is passed straight through to tools/assets/fbx_to_gltf.py; run it
# with --help for the full list.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
blender="${BLENDER:-blender}"

if ! command -v "$blender" >/dev/null; then
  echo "error: '$blender' is not on PATH. Set BLENDER=/path/to/blender." >&2
  exit 127
fi

exec "$blender" --background --factory-startup \
  --python "$repo_root/tools/assets/fbx_to_gltf.py" -- "$@"
