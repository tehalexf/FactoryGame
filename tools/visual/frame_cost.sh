#!/usr/bin/env bash
# What the yard costs, with a full Factory and a Wave.
#
#   bash tools/visual/frame_cost.sh
#
# Brings up an Xvfb if there is no display, the same way `shot.sh` does. Read the
# CPU figure and the draw-call count; ignore anything that looks like a frame
# time, because this is llvmpipe. See tools/visual/frame_cost.gd.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
godot="${GODOT:-godot}"
size="${SHOT_SIZE:-1600x900}"

"$godot" --headless --path . --import >/dev/null 2>&1 || true

display="${SHOT_DISPLAY:-}"
own_server=""
if [ -z "$display" ]; then
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
  --script tools/visual/frame_cost.gd
