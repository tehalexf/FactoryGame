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

# And in jj's terms too, when this checkout is colocated. The question above is
# asked of git's tree; this one is asked of jj's working-copy commit, which jj
# fills in on its own with no `git add` in the way. They can disagree — that is
# the whole reason the jj half of the guard exists.
if [ -d .jj ] && command -v jj >/dev/null 2>&1; then
	echo "== licence guard, against the jj working copy =="
	python3 tools/assets/check_licensed_staged.py --jj
fi

echo "== asset pipeline tests =="
python3 -m unittest discover -s tools/assets/tests -t tools/assets/tests -v

# The release pipeline's tests live here rather than in their own runner because
# they are the same kind of thing — Python over the asset tree — and because the
# thing they guard is the far end of this very pipeline: whether the three
# converters' output actually reaches an exported build. See docs/RELEASING.md.
echo "== release pipeline tests =="
python3 -m unittest discover -s tools/release/tests -t tools/release/tests -v
