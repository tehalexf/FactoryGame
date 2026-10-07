#!/usr/bin/env bash
# Render the Machine contact sheets. Headless, no manual steps.
#
#   bash tools/assets/render_machines.sh                     # the committed sheets
#   bash tools/assets/render_machines.sh --mode lit --output /tmp/try.png
#
# With no arguments it rewrites the three committed sheets under
# docs/images/, which are what makes the readability claim re-checkable:
#
#   machine_silhouettes_front.png   flat black, looking down the Belt line
#   machine_silhouettes_side.png    flat black, looking across it
#   machines_lit.png                the same row with a sun and the real surfaces
#
# Judge the silhouette sheet first. If two Machines are ambiguous in black, no
# amount of texture will tell them apart across a Factory floor.
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

render() {
  # --factory-startup for the same reason the generator uses it: a developer's
  # own colour management or add-ons must not change what the sheet shows.
  "$blender" --background --factory-startup \
    --python tools/assets/render_machines.py -- "$@"
}

if [ "$#" -gt 0 ]; then
  render "$@"
  exit 0
fi

render --mode silhouette --view front --output docs/images/machine_silhouettes_front.png
render --mode silhouette --view side  --output docs/images/machine_silhouettes_side.png
render --mode lit        --view front --output docs/images/machines_lit.png
