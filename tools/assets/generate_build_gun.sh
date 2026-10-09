#!/usr/bin/env bash
# Regenerate the Build Gun viewmodel from its recipe. Headless, no manual steps.
#
#   bash tools/assets/generate_build_gun.sh
#   bash tools/assets/generate_build_gun.sh --output /tmp/try.glb
#
# Inputs are tools/assets/build_gun_recipe.py (the geometry and the two takes),
# tools/assets/dieselpunk_palette.json (the shared palette) and
# content/tuning.toml (the field of view the framing is measured against).
#
# **This is the one viewmodel in the game whose output is committed**, and the
# difference is the licence rather than the art. Every weapon frame is converted
# out of a purchased pack by `convert_weapons.sh`, so its `.glb` is a derivative
# of something non-redistributable and is gitignored; the Build Gun is assembled
# from `machine_parts` and a palette of numbers, so it is this project's own work
# and `assets/gear/build_gun.glb` is in git like a Machine mesh. A clone with no
# packs at all therefore has the real tool in hand.
#
# Because it is committed, #57's rule applies in its stronger form: where the
# output is committed you **prove** it rather than dating it, and
# `tools/assets/tests/test_build_gun.py` regenerates this file and compares the
# bytes. Re-run this after any edit to the recipe, then:
#
#   bash tools/assets/run_tests.sh      # proves the bytes and the framing
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
  --python tools/assets/generate_build_gun.py -- "$@"
