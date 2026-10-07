#!/usr/bin/env bash
#
# Run the DEEP FOUNDRY test suite headless. This is the one-line CI command.
#
#   tools/run_tests.sh              # whole suite
#   tools/run_tests.sh determinism  # only tests whose case.method contains it
#
# Exits 0 when green, non-zero otherwise.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: '$GODOT' not found on PATH. Set GODOT=/path/to/godot." >&2
	exit 127
fi

# Always rescan before running. `class_name` globals resolve through
# .godot/global_script_class_cache.cfg, which only an import pass rebuilds — so a
# newly added class would otherwise fail with a baffling "Identifier not declared
# in the current scope" instead of running. One extra engine start is cheap
# insurance against that.
#
# Twice on a cold cache, and this is not superstition. One pass imports the glTF
# files; the scenes Godot *derives* from them are not necessarily resolvable
# until a pass that starts with those imports already in place. With a single
# pass the Machine-mesh tests failed roughly one cold run in four — green on a
# warm cache, red on a fresh clone, which is the worst shape a test failure can
# have. The second pass is a no-op when the cache is warm.
IMPORT_PASSES=1
if [ ! -d "$PROJECT_ROOT/.godot" ]; then
	IMPORT_PASSES=2
fi
for _pass in $(seq "$IMPORT_PASSES"); do
	"$GODOT" --headless --path "$PROJECT_ROOT" --import >/dev/null 2>&1 || true
done

exec "$GODOT" --headless --path "$PROJECT_ROOT" --script res://tests/run_tests.gd -- "$@"
