"""Which generated assets are older than the recipe that produces them.

    python3 tools/assets/asset_staleness.py          # is anything in my tree stale?
    python3 tools/assets/asset_staleness.py --quiet  # exit code only

`tools/assets/run_tests.sh` runs this on every invocation and prints the report;
`tools/release/preflight.py` makes it a **hard stop**. The split is which question
is being asked: a suite answers "is this code correct", which is a property of the
tree and the same answer for everybody who checks it out, where staleness is a
property of *this machine's* build products — and a release is exactly where those
become the thing in somebody's hands, which is the failure below. Living in the
**tools** rather than in a workflow file is `wav_to_cue.FFMPEG_MINIMUM_MAJOR`'s
precedent: a check that lives only in CI is one a developer runs straight past,
and here CI is the one machine that can never see these files at all.

## The hole this closes, measured

The generated assets — weapon viewmodels, audio cues, set-dressing props — are
written into `assets_licensed/generated/`, which is **gitignored**, because they
are derivatives of purchased packs and this repository is public
(docs/ASSETS.md). So no commit, no diff and no test has ever related a generated
file to the script that generated it. `tools/assets/convert_weapons.sh` was
corrected and merged and the shipped `.glb` stayed **eleven hours older than the
script**; three suites were green, because none of them can see a gitignored
file, and the fix was reported as landed while the thing in the user's hands had
not changed. It was found by reading a timestamp by hand, on the third report of
the same defect.

## The Machine meshes are deliberately not here, and that was measured

They look like the fourth member of this family — edit `machine_recipes.py`,
forget `generate_machines.sh`, and `assets/machines/*.glb` is a picture of a
Machine that no longer exists — and they are the one case where **staleness can
be proved instead of guessed at**, because both ends are committed and the
generator is deterministic.
`test_generated_machines.RegeneratingFromTheDeclaration.test_reproduces_the_committed_meshes_byte_for_byte`
already regenerates every mesh and compares the bytes, which is a strictly
stronger claim than any timestamp can make.

Including them anyway was tried, and it was worse than useless: five of the eleven
committed meshes carry an older commit date than `machine_specs.py`, so the group
reported them stale on a clean tree — and regenerating `press_mk1` produced a file
**byte-identical** to the committed one. The change that moved the script had not
moved the mesh. A check that is red on a tree with nothing wrong with it is a check
somebody switches off, which would take the three groups below down with it.

So the rule is: **where the output is committed, prove it; where the output is
gitignored, date it.** A timestamp is the only instrument available for a file no
commit has ever seen, and it is the wrong instrument for one that has.

## Absence is not staleness, and that rule is load-bearing

A clone without the packs must build, test green and play — `convert_weapons.sh`
prints a note and exits 0, `WeaponViewmodel` draws boxes, and
`tests/cases/test_weapon_viewmodel.gd` asserts the whole of it. So a file that is
**not there** is reported by nothing here. The only detectable case is a
generated file that **exists** and is **older than its own recipe**, which is
exactly the case that bit. On a clean clone every group is silent because every
group is empty, and this file therefore has no opinion at all on the machine that
runs CI.

## What a file's age is, which is the one subtle part

**A tracked file's mtime is when it was *checked out*, not when it was edited.**
Every tracked file in a fresh clone — and in every one of this project's agent
worktrees — carries the same timestamp, minutes old, while the generated output it
is being compared against was produced hours earlier in another checkout and
reached here through the symlinks `link_licensed.sh` makes. Comparing mtimes
would therefore report the entire pipeline stale in every worktree, on the first
run, with nothing having been edited. A check that cries wolf in the normal case
is a check somebody switches off.

So the age of a file is **when its content last changed**, and for anything git
tracks, git knows:

* a path git does not track — every generated output under the quarantine — is as
  old as its mtime, which is true of it, because the only thing that ever wrote it
  was a converter run on this machine;
* a tracked path with local modifications is as old as its mtime, because the
  edit in the working copy is the thing that has not been converted yet — this is
  the case that catches a developer mid-change, before any commit exists;
* a tracked path that is clean is **no newer than the commit that last carried
  it**, whatever the filesystem says: `min(mtime, commit date)`.

That last `min` is what makes the answer conservative in both directions. It
cannot be fooled into reporting staleness by a checkout, and because the same
rule is applied to the output side, it cannot be fooled into hiding staleness by
one either.

With no git at all — an exported tarball — the answer falls back to plain mtimes
and says so, which is the treatment `wav_to_cue` gives an ffmpeg build carrying no
release number: *cannot tell* is reported as cannot tell rather than guessed at.

## Timestamps are evidence, not proof

A recipe committed a minute after the converter was last run against its final
content reads as stale and is not. This file reports rather than refuses for that
reason: every finding names both files and the converter to run, and re-running a
converter is cheap and idempotent. The failure it exists to prevent — silence —
is the expensive one.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release"))
import manifest  # noqa: E402

#: The quarantine's path prefix, re-exported rather than re-spelt: `manifest` is
#: the authority on where the generated assets live, and two copies of that string
#: would be two answers to which files this module may be silent about.
QUARANTINE = manifest.QUARANTINE


@dataclasses.dataclass(frozen=True)
class Group:
    """One generated asset class: what makes it, and out of what.

    `recipes` is every input whose change invalidates the output. A converter's
    own shell script is the obvious one and is never the only one: the weapon
    viewmodels are framed by `fbx_to_viewmodel.py`, the cues are cut by
    `wav_to_cue.py`, and the props are recoloured by `prop_grade.py` against the
    shared palette. **#57's own eleven-hour defect was a correction to the
    framing rather than to the converter**, so a recipe set of one would have
    missed the very thing this file exists for — and a recipe left off a list is
    a recipe whose change goes unreported, in silence, which is the shape of the
    hole being closed.

    The purchased *input* packs are deliberately not recipes. They are read-only,
    nobody edits them, and a pack's own mtime is whenever it was unzipped.
    """

    name: str
    converter: str
    recipes: list[str]
    outputs: list[str]


@dataclasses.dataclass(frozen=True)
class Stale:
    """One asset class whose output predates its own recipe."""

    name: str
    converter: str
    recipe: str
    recipe_age: float
    oldest_output: str
    oldest_output_age: float
    behind: int
    total: int

    def report(self) -> str:
        """One multi-line complaint naming both files and the converter to run.

        `manifest.Problem.report`'s shape, for the same reason: the person reading
        it must not have to go and find out which script this was.
        """
        return "\n".join(
            [
                f"  {self.name}: {self.behind} of {self.total} generated file(s)"
                f" older than the recipe — run:  {self.converter}",
                f"      recipe  {self.recipe}  ({_when(self.recipe_age)})",
                f"      output  {self.oldest_output}  ({_when(self.oldest_output_age)})",
                f"      the output is {_gap(self.recipe_age - self.oldest_output_age)}"
                " behind the recipe.",
            ]
        )


def groups(repo_root: Path) -> dict[str, Group]:
    """Every generated asset class, its recipe set and the files it has produced.

    The three quarantined classes take their file lists from
    `tools/release/manifest.py`, which derives them from the converters
    themselves — so a cue added to `convert_audio.sh` is covered here the day it
    is added, and there is one authority on what a converter produces rather than
    two.

    Every group here writes into the quarantine, which is what makes a clone
    without the packs silent: the lists are full and every file in them is absent.
    See the header for why the committed Machine meshes are not a fourth group.
    """
    repo_root = Path(repo_root)
    bundle = manifest.expected_bundle(repo_root)
    return {
        "weapons": Group(
            name="weapons",
            converter=bundle["weapons"].converter,
            recipes=[
                "tools/assets/convert_weapons.sh",
                "tools/assets/fbx_to_viewmodel.py",
                "tools/assets/dieselpunk_palette.json",
            ],
            outputs=bundle["weapons"].files,
        ),
        "audio": Group(
            name="audio",
            converter=bundle["audio"].converter,
            recipes=[
                "tools/assets/convert_audio.sh",
                "tools/assets/wav_to_cue.py",
            ],
            outputs=bundle["audio"].files,
        ),
        "props": Group(
            name="props",
            converter=bundle["props"].converter,
            recipes=[
                "tools/assets/convert_props.sh",
                "tools/assets/convert_props.py",
                "tools/assets/prop_grade.py",
                "tools/assets/dieselpunk_palette.json",
            ],
            outputs=bundle["props"].files,
        ),
    }


def audit(repo_root: Path, licensed_root: Path | None = None) -> list[Stale]:
    """Every asset class whose output is older than its recipe, in group order.

    An empty list means nothing detectable is stale — which is also what a clone
    with no packs gets, and what a tree whose converters have all been re-run
    gets. The two are indistinguishable here on purpose: absence is not staleness.

    `licensed_root` is where the quarantine actually is, which
    `link_licensed.sh` may have put somewhere else. Outputs are resolved through
    it exactly as `manifest.audit` resolves them.
    """
    repo_root = Path(repo_root)
    licensed_root = Path(licensed_root) if licensed_root else repo_root / "assets_licensed"
    ages = _Ages(repo_root)

    found: list[Stale] = []
    for group in groups(repo_root).values():
        # The newest recipe, because any one of them being newer than the output
        # is enough — and naming the newest is naming the edit that did it.
        newest_recipe = ""
        newest_recipe_age = -1.0
        for relative in group.recipes:
            age = ages.of(_resolve(repo_root, licensed_root, relative))
            if age is not None and age > newest_recipe_age:
                newest_recipe, newest_recipe_age = relative, age
        if not newest_recipe:
            # No recipe of this group is on disk at all. Not a staleness finding;
            # `manifest` and the converters are what complain about a missing
            # recipe, and guessing here would be a second opinion about it.
            continue

        present: list[tuple[float, str]] = []
        for relative in group.outputs:
            path = _resolve(repo_root, licensed_root, relative)
            age = ages.of(path)
            if age is not None and path.stat().st_size > 0:
                present.append((age, relative))
        behind = [entry for entry in present if entry[0] < newest_recipe_age]
        if not behind:
            continue

        oldest_age, oldest = min(behind)
        found.append(
            Stale(
                name=group.name,
                converter=group.converter,
                recipe=newest_recipe,
                recipe_age=newest_recipe_age,
                oldest_output=oldest,
                oldest_output_age=oldest_age,
                behind=len(behind),
                total=len(present),
            )
        )
    return found


def _resolve(repo_root: Path, licensed_root: Path, relative: str) -> Path:
    """`relative` as a real path, sending quarantined ones through the link."""
    if relative.startswith(QUARANTINE + "/"):
        return licensed_root / Path(relative).relative_to(QUARANTINE)
    return repo_root / relative


class _Ages:
    """When each path's *content* last changed, by the rule in this file's header.

    git is asked once for the whole tree rather than once per file: `ls-files`
    says what is tracked and `diff` says which of those is modified, which is two
    subprocess calls instead of two per path. The commit date is then the only
    per-file question, and it is asked only of a file that is tracked and clean —
    so a tree with no packs pays two calls and nothing else.
    """

    def __init__(self, repo_root: Path) -> None:
        self._root = Path(repo_root)
        self._tracked = self._names("ls-files", "-z")
        # `git diff` rather than `diff-index` or `status --porcelain`, and the
        # reason is this module's own trap one level down: **`diff-index` is
        # stat-based and does not refresh the index**, so it reports a file whose
        # mtime was touched and whose content is identical — which is every
        # tracked file in a fresh checkout, and would put the false positive
        # straight back. Measured, not assumed. `git diff` compares content and
        # answers nothing for a touched file; `status --porcelain` is also
        # content-correct but prefixes two status columns and emits a rename as
        # *two* records, the second carrying no prefix, so its output needs
        # parsing where this needs none. An untracked file is not detected here
        # at all: it is simply absent from `_tracked`, and so already as old as
        # its mtime.
        self._modified = self._names(
            "diff", "--name-only", "--no-renames", "-z", "HEAD"
        )
        #: False when git could not answer at all, which is reported rather than
        #: hidden: with no history every tracked mtime is a checkout date and the
        #: answers are worth less. They are not worthless — in the checkout where
        #: the editing happens, which is the one that bit, mtime is the truth.
        self.git_answered = self._tracked is not None
        self._commit_dates: dict[Path, float | None] = {}

    def of(self, path: Path) -> float | None:
        """`path`'s content age in epoch seconds, or None if it is not there."""
        if not path.is_file():
            return None
        mtime = path.stat().st_mtime
        relative = self._relative(path)
        if relative is None or self._tracked is None:
            return mtime
        if relative not in self._tracked or relative in (self._modified or set()):
            return mtime
        committed = self._committed(relative, path)
        return mtime if committed is None else min(mtime, committed)

    def _relative(self, path: Path) -> str | None:
        try:
            return path.resolve().relative_to(self._root.resolve()).as_posix()
        except ValueError:
            # Outside the repository — a quarantine linked in from elsewhere, so
            # git has nothing to say about it and its mtime is the whole answer.
            return None

    def _committed(self, relative: str, path: Path) -> float | None:
        if path not in self._commit_dates:
            answer = self._git("log", "-1", "--format=%ct", "--", relative)
            self._commit_dates[path] = (
                float(answer.strip()) if answer and answer.strip() else None
            )
        return self._commit_dates[path]

    def _names(self, *arguments: str) -> set[str] | None:
        answer = self._git(*arguments)
        if answer is None:
            return None
        return {record for record in answer.split("\0") if record}

    def _git(self, *arguments: str) -> str | None:
        try:
            done = subprocess.run(
                ["git", "-C", str(self._root), *arguments],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        return done.stdout if done.returncode == 0 else None


def _when(age: float) -> str:
    return datetime.datetime.fromtimestamp(age).strftime("%Y-%m-%d %H:%M")


def _gap(seconds: float) -> str:
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes} minute(s)"
    hours = minutes // 60
    if hours < 48:
        return f"{hours} hour(s)"
    return f"{hours // 24} day(s)"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--licensed-root",
        type=Path,
        default=None,
        help="the quarantine; defaults to <repo>/assets_licensed",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="say nothing when nothing is stale",
    )
    arguments = parser.parse_args(argv)

    repo_root = arguments.repo_root.resolve()
    licensed_root = arguments.licensed_root or (repo_root / "assets_licensed")
    found = audit(repo_root, licensed_root)

    if not found:
        if not arguments.quiet:
            print(
                "asset staleness: nothing generated is older than its recipe."
                " (Absent output is not staleness and is not reported.)"
            )
        return 0

    print(
        "asset staleness: a generated asset is older than the script that"
        " produces it.\n"
        "  These files are gitignored, so no commit, no diff and no test can"
        " see them.\n",
        file=sys.stderr,
    )
    for stale in found:
        print(stale.report() + "\n", file=sys.stderr)
    if not _Ages(repo_root).git_answered:
        print(
            "  (No git history here, so every age above is a plain mtime and a"
            " fresh checkout\n   can read as stale. See this file's header.)",
            file=sys.stderr,
        )
    print("See docs/ASSET_PIPELINE.md.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
