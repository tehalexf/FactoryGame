"""Checks the shipped binary actually contains what the build was supposed to put in it.

    python3 tools/release/verify_pck.py build/windows/DeepFoundry.exe

The first half of verifying a release. It reads the pack's own file index out of
the artefact (`pck.py`) and compares it against the set the three converters say
they produced (`manifest.py`), file by file. What it proves is that the bytes are
in there at the paths the game asks for — which is exactly what the first export
of this project failed at, silently, in two different directories at once:

* `assets_licensed/generated/**` — zero of 96 files, because `.gdignore` hides a
  tree from the exporter as thoroughly as from the importer, so a build that drew
  placeholder weapons, played Kenney fallbacks and built the yard out of boxes
  looked exactly like a build that had not;
* `content/**` — zero rows, so the build had no Machines, no Recipes and no tuning
  and could not have started at all.

The second half is `verify_bundled_assets.gd`, which runs *inside* the exported
binary and asks the game's own classes what they resolved. Both are needed: this
one cannot tell a file the loader will accept from one it will not, and that one
cannot tell you which file is missing.

Exits 0 when the pack is complete and 1 with a per-file report otherwise.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import manifest  # noqa: E402
import pck  # noqa: E402

#: Files that are not a converter's output but whose absence is equally fatal, and
#: equally quiet. `content/` is read with `FileAccess`, never `load()`, and carries
#: a `.gdignore` for the importer's sake — so it travels by the same unusual route
#: the quarantined assets do and can be lost the same way.
REQUIRED_PREFIXES = ("res://content/",)

#: And the one file in each that proves the directory is not merely present.
REQUIRED_FILES = (
    "res://project.binary",
    "res://content/machines.csv",
    "res://content/recipes.csv",
    "res://content/tuning.toml",
)


def report(binary: Path, repo_root: Path) -> tuple[bool, list[str]]:
    """Whether `binary` is complete, and everything wrong with it if not."""
    pack = pck.read(binary)
    lines: list[str] = []
    ok = True

    for required in REQUIRED_FILES:
        if required not in pack.files:
            ok = False
            lines.append(
                f"  MISSING {required}"
                + (
                    "  <- the exported build cannot even start without this"
                    if required.startswith("res://content/")
                    else ""
                )
            )

    for prefix in REQUIRED_PREFIXES:
        count = len(pack.under(prefix))
        lines.append(f"  {prefix}  {count} file(s)")
        if count == 0:
            ok = False

    for group in manifest.expected_bundle(repo_root).values():
        missing = [f"res://{f}" for f in group.files if f"res://{f}" not in pack.files]
        empty = [
            f"res://{f}"
            for f in group.files
            if f"res://{f}" in pack.files and pack.files[f"res://{f}"].size == 0
        ]
        lines.append(
            f"  {group.name}: {len(group.files) - len(missing)} of"
            f" {len(group.files)} bundled"
        )
        if missing or empty:
            ok = False
            lines.append(f"      run:  {group.converter}")
            lines.append(
                "      then rebuild. Every one of these has a graceful fallback,"
                " so the build you"
            )
            lines.append(
                "      have runs and is quietly worse — which is why this is an"
                " error and not a warning."
            )
            for path in (missing + empty)[:8]:
                lines.append(f"      missing from the pack: {path}")
            if len(missing) + len(empty) > 8:
                lines.append(f"      … and {len(missing) + len(empty) - 8} more")

    lines.append(f"  {len(pack.files)} files in the pack, embedded={pack.embedded}")
    return ok, lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="the exported .exe or .pck")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    arguments = parser.parse_args(argv)

    try:
        ok, lines = report(arguments.binary, arguments.repo_root.resolve())
    except pck.NotAPack as problem:
        print(f"verify-pck: {problem}", file=sys.stderr)
        return 1

    stream = sys.stdout if ok else sys.stderr
    print("verify-pck: " + ("complete" if ok else "INCOMPLETE"), file=stream)
    for line in lines:
        print(line, file=stream)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
