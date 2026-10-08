#!/usr/bin/env bash
# Point this checkout's `assets_licensed/` at the one that actually holds the packs.
#
#   bash tools/assets/link_licensed.sh                 # link from the main checkout
#   bash tools/assets/link_licensed.sh /path/to/repo   # link from somewhere else
#   bash tools/assets/link_licensed.sh --check         # say what is visible, change nothing
#
# ── Why this script exists, which is a mistake worth not repeating ────────────
#
# `assets_licensed/` is gitignored, because the repository is public and nothing in
# there may be redistributed (docs/ASSETS.md). A **git worktree therefore never has
# it**: a worktree is a fresh checkout of tracked files, and an ignored directory is
# not a tracked file. Every agent this project has spawned has worked in a worktree,
# so every one of them has looked at an empty `assets_licensed/` — and at least one
# concluded from that emptiness that the packs do not exist on this machine, which
# was wrong in a way that sent a whole playtest's worth of audio work into the
# fallbacks the player had never heard.
#
# **An empty `assets_licensed/` means "not linked", never "not purchased".** Run
# this, or `--check`, before concluding anything from it.
#
# A symlink per pack rather than one for the directory, deliberately:
# `assets_licensed/.gdignore` is **tracked** — it is the one thing in the quarantine
# that must be in git, because without it Godot's importer walks gigabytes of
# third-party Unity projects — so replacing the directory with a link would show up
# as deleting a tracked file. Per-pack links leave it alone, and `git status` stays
# clean because every path under `assets_licensed/` is ignored anyway.
#
# The licence guard is unaffected and was checked: git refuses to add a path "beyond
# a symbolic link", so no asset bytes can be staged through one, and staging a link
# itself is caught like any other quarantined path.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
quarantine="$repo_root/assets_licensed"

check_only=0
source_root=""
for argument in "$@"; do
  case "$argument" in
    --check) check_only=1 ;;
    -*) echo "error: unknown option '$argument'" >&2; exit 2 ;;
    *) source_root="$argument" ;;
  esac
done

# Where the packs live when nobody says otherwise: the main checkout this worktree
# was made from. `git rev-parse --git-common-dir` is the main repository's `.git`,
# which is the one fact a worktree knows about where it came from.
if [ -z "$source_root" ]; then
  common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
  source_root="$(dirname "$common_dir")"
fi
source_quarantine="$source_root/assets_licensed"

visible=0
for entry in "$quarantine"/*; do
  [ -e "$entry" ] || continue
  name="$(basename "$entry")"
  [ "$name" = ".gdignore" ] && continue
  visible=$((visible + 1))
done

if [ "$check_only" -eq 1 ]; then
  echo "quarantine: $quarantine"
  if [ "$visible" -eq 0 ]; then
    echo "  EMPTY — this says nothing about whether the packs are on this machine."
    echo "  Run: bash tools/assets/link_licensed.sh"
    exit 1
  fi
  for entry in "$quarantine"/*; do
    name="$(basename "$entry")"
    [ "$name" = ".gdignore" ] && continue
    if [ -L "$entry" ]; then
      echo "  $name -> $(readlink "$entry")"
    else
      echo "  $name (in place, not a link)"
    fi
  done
  exit 0
fi

if [ "$source_quarantine" = "$quarantine" ]; then
  echo "note: this *is* the checkout that holds the packs; nothing to link." >&2
  exit 0
fi
if [ ! -d "$source_quarantine" ]; then
  echo "error: no quarantine at $source_quarantine." >&2
  echo "       Pass the checkout that holds the packs, or see docs/ASSETS.md for" >&2
  echo "       what goes in one. Every converter no-ops without them." >&2
  exit 1
fi

linked=0
for pack in "$source_quarantine"/*; do
  [ -d "$pack" ] || continue
  name="$(basename "$pack")"
  target="$quarantine/$name"
  # Never over a real directory: that would be somebody's actual assets, and this
  # script's job is to add a view of them rather than to replace them.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skip  $name — already here and not a link" >&2
    continue
  fi
  ln -sfn "$pack" "$target"
  linked=$((linked + 1))
done

echo "Linked $linked pack(s) into $quarantine from $source_quarantine."
echo "Nothing under there may be committed; the licence guard enforces that."
