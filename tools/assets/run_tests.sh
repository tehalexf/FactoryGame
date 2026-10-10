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

# Are the generated assets older than the scripts that generate them? They live
# in gitignored directories, so no commit, no diff and no test in any of the three
# suites can see one — which is how a corrected `convert_weapons.sh` came to be
# merged while the shipped .glb stayed eleven hours older than it, with every suite
# green (#57).
#
# **A warning here rather than a failure, deliberately.** A suite answers "is this
# code correct", which is a property of the tree and is the same answer for
# everybody who checks it out; staleness is a property of *this machine's* build
# products, so two developers on the same commit can honestly disagree about it.
# The place it is a hard stop is `tools/release/preflight.py`, because a release is
# exactly where machine-local build products become the thing in somebody's hands —
# and that is the failure #57 was opened about.
#
# A clone with no purchased packs sees nothing at all: absence is not staleness.
# What *is* a failure is this check not running, because a check nobody has seen
# fire is indistinguishable from one that has quietly become a no-op.
echo "== generated assets against their recipes =="
# `|| staleness=$?` rather than `if !`, because `!` would invert the status and
# this has to tell 1 (something is stale) apart from anything else (the check
# broke), and exit on the second.
staleness=0
python3 tools/assets/asset_staleness.py || staleness=$?
if [ "$staleness" -gt 1 ]; then
	echo "error: the staleness check itself failed to run (exit $staleness)." >&2
	exit "$staleness"
fi
if [ "$staleness" -eq 1 ]; then
	echo
	echo "  ^ a warning, not a suite failure — see tools/assets/asset_staleness.py."
	echo "    Re-run the converter named above; it is cheap and idempotent."
	echo
fi

echo "== asset pipeline tests =="
python3 -m unittest discover -s tools/assets/tests -t tools/assets/tests -v

# The release pipeline's tests live here rather than in their own runner because
# they are the same kind of thing — Python over the asset tree — and because the
# thing they guard is the far end of this very pipeline: whether the three
# converters' output actually reaches an exported build. See docs/RELEASING.md.
echo "== release pipeline tests =="
python3 -m unittest discover -s tools/release/tests -t tools/release/tests -v
