#!/usr/bin/env bash
# The licence guard for jj. This is a template: `tools/git/install_hooks.sh`
# substitutes the real jj binary's path below and installs the result as the `jj`
# on your PATH.
#
# Why a PATH wrapper and not something tidier: jj does not run git hooks, has no
# hook system of its own, and refuses to let an alias shadow a built-in command
# ("Cannot define an alias that overrides the built-in command 'commit'"). A
# wrapper is the only interception point left. See the jj section of CLAUDE.md.
#
# It is deliberately generic: in any repository that is not this one — or that
# does not carry the guard — it hands straight over to the real jj and changes
# nothing.
set -uo pipefail

jj_real="@JJ_REAL@"

if [ -n "${JJ_GUARD_RUNNING:-}" ]; then
  # The guard itself shells out to jj. Never recurse.
  exec "$jj_real" "$@"
fi

# ── jj inside a git worktree drives the wrong working copy ───────────────────
#
# A git worktree has no .jj/ of its own, so jj walks *up* out of it, finds the
# main checkout's .jj/, and operates on that — from inside the worktree, with
# paths printed relative to where you are standing. `jj st` in an agent worktree
# reports the main checkout's changes as `../../../...`, and `jj commit` there
# would commit the main checkout's work under the worktree's ticket. Measured,
# not assumed. Refuse instead.
#
# The check is pure shell on purpose: asking jj anything would snapshot the main
# checkout, which is the thing being avoided.
if git_top="$(git rev-parse --show-toplevel 2>/dev/null)" && [ ! -d "$git_top/.jj" ]; then
  dir="$git_top"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    dir="$(dirname "$dir")"
    if [ -d "$dir/.jj" ]; then
      cat >&2 <<MSG
jj: refusing to run here.

  this git worktree:   $git_top
  the jj workspace:    $dir

A git worktree is not a jj workspace. jj would walk up to $dir and act on
*that* working copy, not this one — so a commit here would commit somebody
else's work. Use git in a worktree; every command you need is in CLAUDE.md's
"Version control" section. jj is for the main checkout.
MSG
      exit 1
    fi
  done
fi

# Commands that either turn the working-copy snapshot into something durable or
# publish it. Matched loosely against every argument: over-matching costs one
# extra check that passes, under-matching costs a purchased asset in a public
# repository, so the loose direction is the safe one.
guarded=" commit describe new squash split absorb push "

needs_guard=no
for arg in "$@"; do
  case "$guarded" in
    *" $arg "*) needs_guard=yes ;;
  esac
done

if [ "$needs_guard" = yes ]; then
  root="$("$jj_real" workspace root 2>/dev/null)" || root=""
  guard="$root/tools/assets/check_licensed_staged.py"
  if [ -n "$root" ] && [ -f "$guard" ]; then
    if ! JJ_GUARD_RUNNING=1 python3 "$guard" --jj; then
      echo "jj: refusing to run 'jj $*' — the licence guard failed (see above)." >&2
      exit 1
    fi
  fi
fi

exec "$jj_real" "$@"
