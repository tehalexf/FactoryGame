#!/usr/bin/env bash
# Every asset-pipeline test, headless, one command:
#
#   bash tools/assets/run_tests.sh
#
# Tests that need Blender skip themselves when `blender` is not on PATH, so this
# is safe to run in CI without a Blender install.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "== licence guard, against this repository =="
python3 tools/assets/check_licensed_staged.py --all

echo "== asset pipeline tests =="
python3 -m unittest discover -s tools/assets/tests -t tools/assets/tests -v
