#!/usr/bin/env bash
# Prove animation is interchangeable across characters, headlessly.
#
#   bash tools/assets/verify_retarget_in_godot.sh <donor .glb> <animation> <recipient .glb>
#
# e.g.
#   bash tools/assets/verify_retarget_in_godot.sh \
#       assets/characters/skeleton/Skeleton.glb Skeleton_Running \
#       assets/characters/knight/KnightCharacter.glb
#
# Both characters are imported by Godot, the donor's animation is re-rooted onto
# the recipient's skeleton and played there. Exits non-zero if the animation
# cannot drive the other rig.
set -euo pipefail

donor="${1:?usage: verify_retarget_in_godot.sh <donor .glb> <animation> <recipient .glb>}"
animation="${2:?missing animation name}"
recipient="${3:?missing recipient .glb}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT:-godot}"

if ! command -v "$godot" >/dev/null; then
  echo "error: '$godot' is not on PATH. Set GODOT=/path/to/godot." >&2
  exit 127
fi

work="$(mktemp -d -t godot-retarget-verify-XXXXXX)"
trap 'rm -rf "$work"' EXIT

cat >"$work/project.godot" <<'PROJECT'
config_version=5

[application]
config/name="retarget verification"
config/features=PackedStringArray("4.3")
PROJECT

cp "$repo_root/tools/assets/godot_verify/verify_retarget.gd" "$work/verify_retarget.gd"
for asset in "$donor" "$recipient"; do
  path="$asset"
  [ -f "$path" ] || path="$repo_root/$asset"
  cp "$path" "$work/$(basename "$asset")"
done

"$godot" --headless --path "$work" --import >/dev/null 2>&1
"$godot" --headless --path "$work" --script verify_retarget.gd -- \
  "res://$(basename "$donor")" "$animation" "res://$(basename "$recipient")"
