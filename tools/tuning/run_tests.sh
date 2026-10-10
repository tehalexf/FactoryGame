#!/usr/bin/env bash
# Every test for the tuning dashboard, one command:
#
#   bash tools/tuning/run_tests.sh
#
# Separate from tools/run_tests.sh because this is Python rather than the
# engine's test runner, exactly as the asset-pipeline suite is.
#
# The tests that ask the game's own loader whether a file would load skip
# themselves when `godot` is not on PATH, so this is safe to run anywhere.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "== the tuning file, as it stands =="
python3 tools/tuning_dashboard.py --check

echo "== tuning dashboard tests =="
python3 -m unittest discover -s tools/tuning/tests -t tools/tuning/tests -v
