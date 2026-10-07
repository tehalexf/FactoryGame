#!/usr/bin/env bash
#
# Play every balance scenario headless and print the measured table.
#
#   tools/balance/measure.sh                          # every scenario, three seeds
#   tools/balance/measure.sh --scenario competent --verbose
#   tools/balance/measure.sh --seeds 7,11,29 --cap-minutes 45
#
# This is the instrument #26 is about: the figures in CLAUDE.md come out of here, so a
# later balance change is checked rather than argued about.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "error: '$GODOT' not found on PATH. Set GODOT=/path/to/godot." >&2
	exit 127
fi

# The same reason tools/run_tests.sh does it: `class_name` globals resolve through
# .godot/global_script_class_cache.cfg, which only an import pass rebuilds.
"$GODOT" --headless --path "$PROJECT_ROOT" --import >/dev/null 2>&1 || true

exec "$GODOT" --headless --path "$PROJECT_ROOT" \
	--script res://tools/balance/measure.gd -- "$@"
