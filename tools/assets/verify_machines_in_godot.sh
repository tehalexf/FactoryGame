#!/usr/bin/env bash
# Prove the generated Machine meshes work in Godot, headlessly.
#
#   bash tools/assets/verify_machines_in_godot.sh
#
# Builds a throwaway Godot project around assets/machines/, lets Godot's own glTF
# importer run over it (`--import`), then loads every imported scene and checks
# that each Machine's footprint and port marker positions match the declaration
# in content/machine_bodies.csv, content/machine_ports.csv and content/machines.csv.
#
# Exits non-zero if any check fails, so it is a gate and not a demo. Set
# GODOT=/path/to/godot to use a specific binary.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
godot="${GODOT:-godot}"

if ! command -v "$godot" >/dev/null 2>&1; then
  echo "error: '$godot' is not on PATH. Set GODOT=/path/to/godot." >&2
  exit 127
fi

work="$(mktemp -d -t godot-machine-verify-XXXXXX)"
trap 'rm -rf "$work"' EXIT

cat >"$work/project.godot" <<'PROJECT'
config_version=5

[application]
config/name="machine mesh verification"
config/features=PackedStringArray("4.3")
PROJECT

cp tools/assets/godot_verify/verify_machine.gd "$work/verify_machine.gd"
cp tools/assets/dieselpunk_palette.json "$work/palette.json"
cp assets/machines/*.glb "$work/"

# The expectations come from the same reader the generator used, so this script
# cannot be checking the meshes against a stale second copy of the declaration.
python3 tools/assets/machine_specs.py >"$work/declaration.json"

echo "== importing $(ls assets/machines/*.glb | wc -l) Machine mesh(es) with Godot's own glTF importer =="
"$godot" --headless --path "$work" --import 2>&1 | sed 's/^/   /'

echo "== checking footprints and port positions in-engine =="
"$godot" --headless --path "$work" --script verify_machine.gd -- \
  "$work/declaration.json" "$work/palette.json"
