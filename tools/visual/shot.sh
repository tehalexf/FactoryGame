#!/usr/bin/env bash
# Render a screenshot of a working Factory.
#
#   bash tools/visual/shot.sh out.png [eye|survey|ground]
#
# Needs a display. Under WSL or CI there is none, so it brings up an Xvfb on a
# free number and tears it down again. That gives **software rendering**: judge
# composition, materials and placement from these images, not framerate. Frame
# cost is `tools/visual/frame_cost.sh`'s job.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
godot="${GODOT:-godot}"
out="${1:-shot.png}"
preset="${2:-eye}"
size="${SHOT_SIZE:-1600x900}"

if ! command -v "$godot" >/dev/null 2>&1; then
  echo "error: '$godot' is not on PATH. Set GODOT=/path/to/godot." >&2
  exit 127
fi

"$godot" --headless --path . --import >/dev/null 2>&1 || true

display="${SHOT_DISPLAY:-}"
own_server=""
if [ -z "$display" ]; then
  if ! command -v Xvfb >/dev/null 2>&1; then
    echo "error: no DISPLAY and no Xvfb. Set SHOT_DISPLAY=:0 to use a real one." >&2
    exit 127
  fi
  for number in 93 94 95 96 97 98; do
    if [ ! -e "/tmp/.X11-unix/X$number" ]; then
      display=":$number"
      break
    fi
  done
  [ -n "$display" ] || { echo "error: no free X display number" >&2; exit 1; }
  Xvfb "$display" -screen "0" "${size}x24" >/dev/null 2>&1 &
  own_server=$!
  trap 'kill ${own_server} 2>/dev/null || true' EXIT
  sleep 2
fi

DISPLAY="$display" "$godot" --path . \
  --resolution "${size%x*}x${size#*x}" \
  --script tools/visual/compose_shot.gd -- "$out" "$preset"
