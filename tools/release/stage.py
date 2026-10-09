"""Assembles the tree that gets exported, with the quarantined assets inside it.

## Why the build does not export the working copy

Godot only puts a file in the PCK if its `EditorFileSystem` scanned it, and
`assets_licensed/.gdignore` exists to stop it scanning the quarantine — without
that marker the importer walks gigabytes of third-party Unity projects and raw WAV
and was observed to abandon this project's own assets part-way through
(docs/ASSETS.md).

So the three runtime asset classes sit in a tree the exporter cannot see. The
first export attempt on this project proved it exactly: `include_filter` set to
`assets_licensed/generated/*` bundled **zero** files, and produced a 130 MB build
that started, ran, drew placeholder weapons, played Kenney fallbacks, built the
yard out of boxes, and reported nothing wrong. That is the failure this whole
directory exists to prevent.

## What this module does instead

A separate staging tree, under `build/stage/`:

1. the project, rsynced without `.git`, `.godot`, `build/`, the agent worktrees or
   the image-generation pipeline's gigabytes;
2. **no `assets_licensed/.gdignore`**, so the exporter can see what is under it;
3. only `generated/` copied out of the quarantine — never a purchased pack, so the
   staged `assets_licensed/` is nine megabytes rather than seven gigabytes and the
   importer has nothing to choke on;
4. an `importer="keep"` sidecar beside every staged file.

Step 4 is the one worth understanding. Without a sidecar Godot *imports* a `.ogg`
or a `.glb`, and an imported file reaches the PCK as a converted resource under
`.godot/imported/` — so `FileAccess.file_exists("res://assets_licensed/generated/
audio/silo_commit.ogg")`, which is the literal thing `SoundBank._load` asks, is
false in the exported build and every cue silently falls back. Godot's "Keep File
(No Import)" mode is the sanctioned way to say *ship this file as it is*: the
exporter stores the raw bytes at the raw path, which is what the game wants and
what the licence permits — inside the PCK, not loose beside it.

The working copy is never touched, which also means a build cannot invalidate the
developer's import cache or leave the repository in a state the licence guard
would object to.
"""

from __future__ import annotations

import dataclasses
import shutil
import subprocess
from pathlib import Path

#: What Godot writes for "Keep File (No Import)". The whole sidecar: no source
#: hash, no destination files, no parameters, because nothing is being imported.
KEEP_SIDECAR = '[remap]\n\nimporter="keep"\n'

#: Never staged. `.godot` is excluded so an existing staging cache survives a
#: build rather than being replaced by the working copy's; `build` so a release
#: does not contain the last one; `assets_licensed` because this module copies the
#: one directory inside it that may ship, by hand, and nothing else.
EXCLUDES = (
    ".git",
    ".gitignore",
    ".github",
    ".godot",
    ".claude",
    "build",
    "assets_licensed",
    "tools/aigen/.venv",
    "tools/aigen/models",
    "tools/aigen/output",
    "tools/comfyui",
    "__pycache__",
)

#: The subdirectories of the quarantine that may be bundled. Each is the output of
#: one converter and each is a derivative of a non-redistributable purchase: fine
#: inside a shipped game, never committed and never shipped loose.
BUNDLED = ("gear", "audio", "props")

#: Directories already in the repository whose files are read with `FileAccess` at
#: runtime and must therefore ship as raw bytes at their own paths.
#:
#: `content/` is here because the first export of this project did not contain a
#: single row of it. `content/.gdignore` keeps Godot's importer from claiming every
#: `.csv` as a translation table — which it does, noisily, and then **strips the
#: rows out of the export** — and the side effect is that nothing under it reaches
#: the PCK at all. So the exported build had no Machines, no Recipes and no tuning,
#: and `Definitions.load_from_directory` had nothing to load. A `keep` sidecar says
#: what the `.gdignore` was there to say, without hiding the file from the exporter.
#:
#: `assets/gear/` is #64's and is the same failure one asset along. It holds the
#: **committed** Build Gun viewmodel — the one held object this project authored
#: itself, so the one whose GLB is in git rather than in the quarantine — and
#: `WeaponViewmodel._load` reads it with `GLTFDocument.append_from_file` at a
#: `res://` path, exactly as it reads a converted weapon. Godot would otherwise
#: import a committed `.glb` as a `PackedScene` and the raw bytes would never
#: reach the PCK, so the model would draw in the editor and in every test and fall
#: back to placeholder boxes **only in the shipped build** — the release-only
#: silence this whole module exists to close. A Machine's `.glb` is not here
#: because `WorldView` resolves those through the importer, which is the other
#: half of the same rule: what is read with `FileAccess` ships raw, and what is
#: `load`ed does not.
RAW_TREES = ("content", "assets/gear")


class NothingToStage(Exception):
    """The quarantine has no converted assets in it at all.

    A hard error rather than an empty build, because an empty build is the one
    this project can produce without noticing.
    """


@dataclasses.dataclass(frozen=True)
class Staged:
    """What was assembled: the tree, and the files marked to ship unconverted."""

    root: Path
    kept: list[str]


def prepare(repo_root: Path, licensed_root: Path, stage_root: Path) -> Staged:
    """Assemble `stage_root` out of `repo_root` and `licensed_root/generated`."""
    repo_root = Path(repo_root)
    licensed_root = Path(licensed_root)
    stage_root = Path(stage_root)

    source = licensed_root / "generated"
    present = [name for name in BUNDLED if (source / name).is_dir()]
    if not present:
        raise NothingToStage(
            f"{source} holds none of {', '.join(BUNDLED)} — the converters have"
            " not been run. tools/release/preflight.py says which."
        )

    stage_root.mkdir(parents=True, exist_ok=True)
    _rsync(repo_root, stage_root, delete=True, excludes=EXCLUDES)

    kept: list[str] = []
    for tree in RAW_TREES:
        kept += _ship_raw(stage_root, stage_root / tree)

    for name in present:
        target = stage_root / "assets_licensed/generated" / name
        target.mkdir(parents=True, exist_ok=True)
        # `--delete`, and nothing excluded, so the directory becomes exactly what
        # the quarantine holds. The staging tree outlives a build — that is what
        # keeps Godot's import cache warm — so anything dropped from the quarantine
        # since the last build would otherwise ship from the last build for ever,
        # and an orphaned sidecar would be a file Godot complains about. The
        # sidecars are written back immediately below; they cost nothing to rewrite
        # because an `importer="keep"` file is never imported.
        _rsync(source / name, target, delete=True, excludes=())
        kept += _ship_raw(stage_root, target)

    # Belt and braces for the thing that silently empties the build: if a marker
    # ever reappears over the staged assets, nothing under it reaches the PCK.
    marker = stage_root / "assets_licensed/.gdignore"
    if marker.exists():
        marker.unlink()

    return Staged(root=stage_root, kept=sorted(kept))


def _ship_raw(stage_root: Path, tree: Path) -> list[str]:
    """Mark every file under `tree` to be exported as itself, and unhide the tree.

    Two steps and both are load-bearing. The `.gdignore` goes, or the exporter
    never walks in here and the PCK silently lacks the lot. Then every file gets a
    `keep` sidecar, or the exporter walks in and *imports* what it finds — a `.csv`
    becomes a translation table with its rows stripped, a `.ogg` becomes a stream
    under `.godot/imported/` — and the path the game asks `FileAccess` for is not in
    the pack either way.
    """
    if not tree.is_dir():
        return []
    marker = tree / ".gdignore"
    if marker.exists():
        marker.unlink()
    kept = []
    for path in sorted(tree.rglob("*")):
        if not path.is_file() or path.name.endswith(".import"):
            continue
        path.with_name(path.name + ".import").write_text(KEEP_SIDECAR)
        kept.append(str(path.relative_to(stage_root)))
    return kept


def _rsync(source: Path, target: Path, *, delete: bool, excludes: tuple[str, ...]) -> None:
    if shutil.which("rsync") is None:
        raise NothingToStage("rsync is not on PATH; it is what assembles the build")
    command = ["rsync", "-a"]
    if delete:
        command.append("--delete")
    for pattern in excludes:
        command += ["--exclude", pattern]
    command += [f"{source}/", f"{target}/"]
    subprocess.run(command, check=True)
