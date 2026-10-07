#!/usr/bin/env bash
# One-time per-clone setup: point git at the repo's version-controlled hooks.
#
#   bash tools/git/install_hooks.sh
#
# This installs the licence guard as a pre-commit hook, so a non-redistributable
# asset cannot be committed by accident. CI runs the same guard, so forgetting to
# run this is caught — late — rather than silently.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hooks_dir="tools/git/githooks"

chmod +x "$repo_root/$hooks_dir"/* 2>/dev/null || true
git -C "$repo_root" config core.hooksPath "$hooks_dir"

echo "hooks installed: core.hooksPath=$hooks_dir"
echo "  pre-commit -> tools/assets/check_licensed_staged.py (licence guard)"
