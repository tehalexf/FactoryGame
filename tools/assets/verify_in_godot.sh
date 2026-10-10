#!/usr/bin/env bash
# Prove a converted character works in Godot, headlessly.
#
#   bash tools/assets/verify_in_godot.sh <path to .glb> [expected-height] \
#       [min-animations] [core-bones-this-rig-cannot-have]
#
# e.g. bash tools/assets/verify_in_godot.sh assets/characters/skeleton/Skeleton.glb 1.8 5
#
# The fourth argument is a comma-separated list of core shared-skeleton bones the
# source rig genuinely does not author, so the check reports them instead of
# failing. Use it only when the artist did not model the joint — the KayKit
# skeletons parent `head` straight to `chest` and have no neck at all. It is an
# argument rather than a softening of the check so each exception is visible at
# the call site; inventing a joint to satisfy the gate would be worse.
#
# Builds a throwaway Godot project around the asset, lets Godot's own glTF
# importer run over it (`--import`), then loads the imported scene and checks the
# rig and every animation. Exits non-zero if any check fails, so it is usable as
# a gate and not just as a demo.
set -euo pipefail

asset="${1:?usage: verify_in_godot.sh <path to .glb> [expected height in metres]}"
expected_height="${2:-0}"
min_animations="${3:-1}"
allow_missing="${4:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot="${GODOT:-godot}"

if ! command -v "$godot" >/dev/null; then
  echo "error: '$godot' is not on PATH. Set GODOT=/path/to/godot." >&2
  exit 127
fi

work="$(mktemp -d -t godot-asset-verify-XXXXXX)"
trap 'rm -rf "$work"' EXIT

cat >"$work/project.godot" <<'PROJECT'
config_version=5

[application]
config/name="asset verification"
config/features=PackedStringArray("4.3")
PROJECT

cp "$repo_root/tools/assets/godot_verify/verify_character.gd" "$work/verify_character.gd"
asset_path="$asset"
[ -f "$asset_path" ] || asset_path="$repo_root/$asset"
cp "$asset_path" "$work/$(basename "$asset")"

echo "== importing $(basename "$asset") with Godot's own glTF importer =="
"$godot" --headless --path "$work" --import 2>&1 | sed 's/^/   /'

echo "== checking the imported scene =="
"$godot" --headless --path "$work" --script verify_character.gd -- \
  "res://$(basename "$asset")" "$expected_height" "$min_animations" "$allow_missing"
