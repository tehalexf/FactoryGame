#!/usr/bin/env python3
"""Fail loudly if a non-redistributable asset is about to enter this public repo.

This repository is public (see docs/ASSETS.md). Purchased and licence-restricted
assets are licensed for use in a shipped game, not for republication. They live
in `assets_licensed/`, which .gitignore excludes — but .gitignore is advisory:
`git add -f`, a stale index, or a wildcard add defeats it. This guard is the
enforcement.

It fails on:
  * anything staged under a quarantined directory (assets_licensed/),
  * anything already committed under a quarantined directory (a past mistake
    must keep failing until it is removed, not pass because nothing is staged),
  * anything staged whose path names a vendor that forbids redistribution, even
    outside the quarantine — renaming a purchased file does not launder it.

There is one exception, and it holds no asset data: an *empty*
`assets_licensed/.gdignore`, the marker that keeps Godot's importer out of the
quarantine. Put a single byte in it and it is a violation again.

Usage:
    python3 tools/assets/check_licensed_staged.py            # staged + history
    python3 tools/assets/check_licensed_staged.py --all      # every tracked file
    python3 tools/assets/check_licensed_staged.py --jj       # the jj working copy

Exit status 0 means nothing licensed is in or entering the repo. Non-zero means
the commit must not happen.

`--jj` asks the same two questions of jj that the default mode asks of git's
index, because jj has no index and no hooks (see the jj section of CLAUDE.md):

  * what is in the working-copy commit's tree — jj snapshots the working copy
    automatically, so this is the "staged" question and the "already committed"
    question at once, and
  * what every commit not yet on a remote bookmark touched — so a file that was
    committed and then deleted still fails, exactly as the git mode's history
    check does.

It is the wrapper installed at `~/.local/bin/jj` by `tools/git/install_hooks.sh`
that runs this, because jj will neither run a git hook nor let an alias shadow a
built-in command.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

# Directories whose entire contents are non-redistributable.
QUARANTINE_DIRS = ("assets_licensed/",)

# The single exception, and it carries no asset data at all: Godot's marker file
# telling the engine not to scan the quarantine. Without it in git, every fresh
# clone points Godot's importer at gigabytes of third-party Unity projects and
# raw WAV libraries, which is slow and was observed to stop the engine importing
# the repository's own assets. It is allowed only while it is empty, so the
# exception cannot be used to smuggle anything through.
QUARANTINE_MARKER = "assets_licensed/.gdignore"

# Vendors and marketplaces whose licences forbid redistribution. Matched against
# the whole path, case-insensitively, on word-ish boundaries so that ordinary
# words are not caught. Keep in step with the "Known licence constraints"
# section of docs/ASSETS.md.
LICENSED_VENDOR_PATTERN = re.compile(
    r"(?<![a-z0-9])(synty|polygon_?city|sonniss|mixamo|humble_?bundle|"
    r"gamedev_?market|artstation_?marketplace|megascans|metahuman|quixel|"
    r"paragon|unity_?asset_?store|fab_?marketplace)(?![a-z0-9])",
    re.IGNORECASE,
)

ADVICE = """
A non-redistributable asset must never be committed to this public repository.

  * Move the file under assets_licensed/ (gitignored) and reference it there.
  * Then unstage it:        git restore --staged <path>
  * If it is already committed, remove it from history before pushing:
                            git rm --cached <path>
  * Record provenance in the ledger in docs/ASSETS.md.

Only CC0 / permissive / self-authored assets may be committed. If this guard is
wrong about a path, fix the path — do not bypass the guard.
"""

JJ_ADVICE = """
A non-redistributable asset must never be committed to this public repository.

jj has no index, so there is nothing to unstage: the file is already in the
working-copy commit. To get it out:

  * Move the file under assets_licensed/ (gitignored, and jj honours .gitignore).
  * Then stop jj tracking it:   jj file untrack <path>
    That only works once the path is ignored — jj refuses to untrack a file it
    would immediately re-snapshot.
  * If an earlier jj commit carries it:
                                jj abandon <rev>     (drop the commit), or
                                jj squash --into <rev> after removing the file
  * To undo the whole thing:    jj op log && jj op restore <operation>
  * Record provenance in the ledger in docs/ASSETS.md.

Only CC0 / permissive / self-authored assets may be committed. If this guard is
wrong about a path, fix the path — do not bypass the guard.
"""


def git_lines(*args: str) -> list[str]:
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"licence guard: git {' '.join(args)} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(2)
    return [line for line in result.stdout.splitlines() if line]


def staged_paths() -> list[str]:
    return git_lines("diff", "--cached", "--name-only", "--diff-filter=ACMR")


def committed_paths() -> list[str]:
    """Files in the current commit. Deliberately not `git ls-files`, which also
    reports what is merely staged and would describe it as committed."""
    if subprocess.run(["git", "rev-parse", "--verify", "HEAD"],
                      capture_output=True).returncode != 0:
        return []  # a repository with no commits yet
    return git_lines("ls-tree", "-r", "--name-only", "HEAD")


def jj_lines(*args: str) -> list[str]:
    result = subprocess.run(["jj", "--no-pager", *args], capture_output=True, text=True,
                            env=dict(os.environ, JJ_GUARD_RUNNING="1"))
    if result.returncode != 0:
        print(f"licence guard: jj {' '.join(args)} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(2)
    return [line for line in result.stdout.splitlines() if line]


def jj_working_copy_paths() -> list[str]:
    """Every file in the working-copy commit's tree. jj snapshots the working
    copy on its own, so this answers both "about to be committed" and "already
    committed" in one question."""
    return jj_lines("file", "list", "-r", "@")


def jj_unpushed_paths() -> list[str]:
    """Every path touched by a commit that is not yet on a remote bookmark — so a
    file added and later deleted still fails until the history stops carrying
    it, which is what the git mode's history check is for."""
    revs = jj_lines("log", "--no-graph", "-r", "::@ ~ ::remote_bookmarks() ~ root()",
                    "-T", 'commit_id ++ "\\n"')
    paths: set[str] = set()
    for rev in revs:
        for line in jj_lines("diff", "--summary", "-r", rev):
            # "A path", "M path", "D path", "R old{ => new}" — the status letter
            # and one space, then the path.
            paths.add(line[2:])
    return sorted(paths)


def quarantined(paths: list[str], *, jj: bool = False) -> list[str]:
    return [p for p in paths
            if any(p.startswith(d) or f"/{d}" in p for d in QUARANTINE_DIRS)
            and not is_empty_quarantine_marker(p, jj=jj)]


def is_empty_quarantine_marker(path: str, *, jj: bool = False) -> bool:
    """The one path inside the quarantine that may be committed — see
    QUARANTINE_MARKER. Only while it is empty: a `.gdignore` with bytes in it is
    a file smuggling data out of the quarantine, and is treated as a violation
    like anything else."""
    if path != QUARANTINE_MARKER:
        return False
    if jj:
        result = subprocess.run(["jj", "--no-pager", "file", "show", "-r", "@", path],
                                capture_output=True, env=dict(os.environ, JJ_GUARD_RUNNING="1"))
        return result.returncode == 0 and result.stdout == b""
    result = subprocess.run(["git", "cat-file", "-s", f":{path}"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        # Not in the index; ask the commit instead.
        result = subprocess.run(["git", "cat-file", "-s", f"HEAD:{path}"],
                                capture_output=True, text=True)
    if result.returncode != 0:
        return False
    return result.stdout.strip() == "0"


def vendor_named(paths: list[str]) -> list[tuple[str, str]]:
    hits = []
    for p in paths:
        match = LICENSED_VENDOR_PATTERN.search(p)
        if match:
            hits.append((p, match.group(1)))
    return hits


def report(violations: list[str], *, jj: bool = False) -> int:
    if not violations:
        return 0

    print("=" * 72, file=sys.stderr)
    print("LICENCE GUARD FAILED — refusing to let licensed assets into a public repo",
          file=sys.stderr)
    print("=" * 72, file=sys.stderr)
    for violation in sorted(set(violations)):
        print(f"  {violation}", file=sys.stderr)
    print(JJ_ADVICE if jj else ADVICE, file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true",
                        help="check every tracked file, not just the staged ones")
    parser.add_argument("--jj", action="store_true",
                        help="check the jj working-copy commit and every unpushed commit")
    args = parser.parse_args()

    violations: list[str] = []

    if args.jj:
        tree = jj_working_copy_paths()
        for path in quarantined(tree, jj=True):
            violations.append(f"in the jj working-copy commit, inside a quarantined "
                              f"directory: {path}")
        for path, vendor in vendor_named(tree):
            violations.append(f"in the jj working-copy commit, path names a "
                              f"non-redistributable vendor ({vendor}): {path}")

        touched = jj_unpushed_paths()
        for path in quarantined(touched, jj=True):
            violations.append(f"touched by an unpushed jj commit, inside a quarantined "
                              f"directory: {path}")
        for path, vendor in vendor_named(touched):
            violations.append(f"touched by an unpushed jj commit, path names a "
                              f"non-redistributable vendor ({vendor}): {path}")

        return report(violations, jj=True)

    staged = staged_paths()
    for path in quarantined(staged):
        violations.append(f"staged, inside a quarantined directory: {path}")
    for path, vendor in vendor_named(staged):
        violations.append(f"staged, path names a non-redistributable vendor ({vendor}): {path}")

    committed = committed_paths()
    for path in quarantined(committed):
        violations.append(f"already committed, inside a quarantined directory: {path}")
    if args.all:
        for path, vendor in vendor_named(committed):
            violations.append(
                f"already committed, path names a non-redistributable vendor ({vendor}): {path}")

    return report(violations)


if __name__ == "__main__":
    sys.exit(main())
