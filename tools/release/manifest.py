"""Which runtime-loaded files a shippable build must contain, and what is missing.

Three asset classes are loaded at runtime from `assets_licensed/generated/` —
first-person weapon viewmodels, audio cues, set-dressing props. They are
derivatives of purchased, non-redistributable packs, so they are gitignored, are
absent from almost every clone, and **each one has a working fallback**:
`WeaponViewmodel` draws boxes, `SoundBank` plays committed CC0 Kenney sounds,
`SetDressing` builds the yard out of self-authored stand-ins. See
docs/ASSET_PIPELINE.md §7-9.

That graceful degradation is a feature for a clone and a trap for a release. A
build that dropped them **runs**, looks worse, sounds worse, and says nothing at
all about it. This module is the half of the answer that knows what *should* be
there; `verify_pck.py` is the half that checks what *is*.

## The expected set is derived, never written down

Each of the three converters is also its own recipe — which FBX becomes which
weapon, which recording becomes which cue, which prop comes from which pack — so
the converters are the authority on what they produce and this module reads them:

| Class | Authority | Read how |
|---|---|---|
| `weapons` | `tools/assets/convert_weapons.sh` | its `--output "$out_dir/…"` flags |
| `audio` | `tools/assets/convert_audio.sh` | its `cue <name> …` lines |
| `props` | `tools/assets/convert_props.py` | `CATALOGUE`, `SHARED_TEXTURES`, imported |

A hand-maintained list would go stale the first time somebody added a cue, and a
stale list is a build that passes its own check while shipping less than it should.
"""

from __future__ import annotations

import dataclasses
import importlib.util
import re
from pathlib import Path

#: Where the game looks, relative to the project root. These are the literal
#: prefixes of `WeaponViewmodel.WEAPON_BODY_DIRECTORY`, `SoundBank.HERO_DIRECTORY`
#: and `SetDressing.PROP_DIRECTORY` with `res://` stripped. If one of those
#: constants moves, `tests/cases/*` will say so and this must follow.
GEAR_DIRECTORY = "assets_licensed/generated/gear"
AUDIO_DIRECTORY = "assets_licensed/generated/audio"
PROP_DIRECTORY = "assets_licensed/generated/props"

#: The root of the quarantine, as a path prefix. Everything this module expects is
#: under it, which is the invariant that keeps the licence guard green.
QUARANTINE = "assets_licensed"


@dataclasses.dataclass(frozen=True)
class Group:
    """One asset class: what it is, what makes it, and every file it owes."""

    name: str
    converter: str
    files: list[str]


@dataclasses.dataclass(frozen=True)
class Problem:
    """An asset class that cannot be shipped, and the command that fixes it."""

    name: str
    converter: str
    expected: int
    present: int
    missing: list[str]

    def report(self) -> str:
        """One multi-line complaint, naming the converter to run.

        Deliberately loud and deliberately specific: the whole point is that the
        person reading it does not have to go and find out which script this was.
        """
        head = (
            f"  {self.name}: {self.present} of {self.expected} files present"
            f" — run:  {self.converter}"
        )
        shown = self.missing[:6]
        lines = [f"      missing {path}" for path in shown]
        if len(self.missing) > len(shown):
            lines.append(f"      … and {len(self.missing) - len(shown)} more")
        return "\n".join([head, *lines])


def weapon_files(repo_root: Path) -> list[str]:
    """The viewmodel GLBs `convert_weapons.sh` writes, read off its own flags."""
    recipe = repo_root / "tools/assets/convert_weapons.sh"
    names = set()
    for line in recipe.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for match in re.finditer(r'--output\s+"\$out_dir/([^"]+)"', stripped):
            names.add(match.group(1))
    return sorted(f"{GEAR_DIRECTORY}/{name}" for name in names)


def audio_files(repo_root: Path) -> list[str]:
    """The cues `convert_audio.sh` cuts, read off its own `cue` lines.

    `cue <name> <source fragment> [worker arguments...]` is the recipe's whole
    dialect. A continuation line, an indented flag or a comment is not a
    declaration, so only a line that *starts* with `cue ` and a non-blank name
    counts.
    """
    recipe = repo_root / "tools/assets/convert_audio.sh"
    names = set()
    for line in recipe.read_text().splitlines():
        match = re.match(r"^cue (\S+)", line)
        if match:
            names.add(match.group(1))
    return sorted(f"{AUDIO_DIRECTORY}/{name}.ogg" for name in names)


def prop_files(repo_root: Path) -> list[str]:
    """The props `convert_props.py` rewrites, plus the atlas they all wear.

    Imported rather than parsed, because that converter is Python and its
    `CATALOGUE` *is* a data structure — and it is the same object
    `tools/assets/tests/test_convert_props.py` asserts `set_dressing.gd` agrees
    with, so there is one catalogue in the project and not two.

    `props.json` is in the list on purpose: `SetDressing` reads each prop's
    measured bounds out of it to stand a pipe run at the pack's own datums, so a
    bundle without it is a bundle whose props are at the wrong height.
    """
    converter = _load_module(repo_root / "tools/assets/convert_props.py")
    files = [f"{PROP_DIRECTORY}/{prop_id}.glb" for prop_id in converter.CATALOGUE]
    for relative in sorted(
        {r for group in converter.SHARED_TEXTURES.values() for r in group}
    ):
        files.append(f"{PROP_DIRECTORY}/{Path(relative).name}")
    files.append(f"{PROP_DIRECTORY}/props.json")
    return sorted(files)


def expected_bundle(repo_root: Path) -> dict[str, Group]:
    """Every file the exported PCK must carry, by asset class."""
    repo_root = Path(repo_root)
    return {
        "weapons": Group(
            "weapons",
            "bash tools/assets/convert_weapons.sh",
            weapon_files(repo_root),
        ),
        "audio": Group(
            "audio",
            "bash tools/assets/convert_audio.sh",
            audio_files(repo_root),
        ),
        "props": Group(
            "props",
            "bash tools/assets/convert_props.sh",
            prop_files(repo_root),
        ),
    }


def audit(repo_root: Path, licensed_root: Path) -> list[Problem]:
    """Which asset classes are not ready to ship, in declaration order.

    An empty list means a build may proceed. Anything else is a build that must
    not: every entry names its converter, because the only useful thing to say
    about a missing cue is how to cut it.

    A zero-byte file counts as absent. An interrupted ffmpeg or Blender run leaves
    exactly that, and `FileAccess.file_exists` would be perfectly happy with it.
    """
    licensed_root = Path(licensed_root)
    problems = []
    for group in expected_bundle(repo_root).values():
        missing = [
            relative
            for relative in group.files
            if not _usable(licensed_root / Path(relative).relative_to(QUARANTINE))
        ]
        if missing:
            problems.append(
                Problem(
                    name=group.name,
                    converter=group.converter,
                    expected=len(group.files),
                    present=len(group.files) - len(missing),
                    missing=missing,
                )
            )
    return problems


def _usable(path: Path) -> bool:
    return path.is_file() and path.stat().st_size > 0


def _load_module(path: Path):
    spec = importlib.util.spec_from_file_location(f"_release_{path.stem}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
