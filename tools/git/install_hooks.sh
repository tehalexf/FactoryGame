#!/usr/bin/env bash
# One-time per-clone setup: point git at the repo's version-controlled hooks, and
# — if jj is installed — put the same licence guard in front of jj.
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

# ── jj ────────────────────────────────────────────────────────────────────────
# jj does not run git hooks, has no hook system, and will not let an alias shadow
# a built-in command, so the hook above protects nothing when the commit is made
# through jj. The interception point that is left is the `jj` on PATH. See the jj
# section of CLAUDE.md.
#
# Set JJ_REAL to the real jj binary if it is not where this expects, or
# SKIP_JJ_WRAPPER=1 to leave jj alone.
if [ -n "${SKIP_JJ_WRAPPER:-}" ]; then
  echo "jj wrapper skipped (SKIP_JJ_WRAPPER is set)"
  exit 0
fi

bin_dir="${JJ_WRAPPER_BIN:-$HOME/.local/bin}"
wrapper="$bin_dir/jj"
template="$repo_root/tools/git/jj-wrapper.sh"

jj_real="${JJ_REAL:-}"
if [ -z "$jj_real" ]; then
  # Newest ~/.local/opt/jj-*/jj, the way the other tools here are installed.
  for candidate in $(ls -d "$HOME"/.local/opt/jj-*/jj 2>/dev/null | sort -V -r); do
    jj_real="$candidate"
    break
  done
fi

if [ -z "$jj_real" ] || [ ! -x "$jj_real" ]; then
  echo "jj wrapper not installed: no jj binary found under ~/.local/opt/jj-*/jj."
  echo "  jj is optional here. If you use it, install it there (or set JJ_REAL)"
  echo "  and re-run this script — otherwise the licence guard does not cover jj."
  exit 0
fi

# Refuse to make the wrapper call itself.
if [ "$(readlink -f "$jj_real")" = "$(readlink -f "$wrapper" 2>/dev/null || echo none)" ]; then
  echo "jj wrapper not installed: JJ_REAL points at the wrapper itself." >&2
  exit 1
fi

mkdir -p "$bin_dir"
rm -f "$wrapper"
sed "s|@JJ_REAL@|$jj_real|" "$template" > "$wrapper"
chmod +x "$wrapper"

echo "jj guard installed: $wrapper -> $jj_real"
echo "  commit/describe/new/squash/split/absorb/push ->"
echo "    tools/assets/check_licensed_staged.py --jj (licence guard)"
