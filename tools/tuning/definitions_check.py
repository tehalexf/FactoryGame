"""Ask the game's own loader whether a candidate tuning file would load.

`toml_subset` refuses anything outside the TOML subset, which is the syntax half.
`Definitions` has a second half the subset cannot see: a page of cross-checks
saying that `bob_stride_metres` may not be 0 because it is a divisor, that Survey
View has to be above eye level, that a Siege Hulk has to outrange every Turret.
Restating those in Python would be a second source of truth, and a second source
of truth drifts — which is the same argument the tuning file's comments make for
being the dashboard's only help copy.

So the dashboard asks the loader. It writes the candidate into a throwaway
directory alongside copies of the other six content files and runs
`check_definitions.gd` against that, which takes about a quarter of a second. The
live `content/` is never the thing under test, so a value the game would refuse
never reaches the file the game reads.

This is not a second channel into a running game. It is a second *reader of
files*, in a separate process, that cannot see or touch a Run. The file is still
the only API, and the dashboard still works with the game closed — and with no
Godot on PATH at all, in which case this check is skipped and the subset gate
stands alone.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

## The other six files `Definitions.load_from_directory` insists on. Named rather
## than globbed so a stray file in `content/` cannot change what is checked.
COMPANION_FILES = (
    "machines.csv",
    "recipes.csv",
    "waves.csv",
    "deliveries.csv",
    "gear.csv",
    "stratagems.csv",
)

TUNING_FILE = "tuning.toml"

_PREFIX = "DEFINITION-ERROR: "


class Checker:
    """Runs the loader out of process. Call it with the candidate file's text."""

    def __init__(self, repo: Path, godot: str | None = None, timeout: float = 60.0):
        self.repo = Path(repo)
        self.godot = godot or os.environ.get("GODOT") or shutil.which("godot")
        self.timeout = timeout
        self.script = Path(__file__).resolve().parent / "check_definitions.gd"

    @property
    def available(self) -> bool:
        """False when there is no Godot to ask. The dashboard says so on the
        page rather than pretending the deep check happened."""
        return bool(self.godot) and self.script.is_file()

    def errors(self, candidate: str) -> list[str]:
        """Every error `Definitions` would report for this tuning file, or an
        empty list. An empty list from an unavailable checker means "not asked",
        which is why `available` is reported separately."""
        if not self.available:
            return []

        content = self.repo / "content"
        with tempfile.TemporaryDirectory(prefix="tuning-check-") as work:
            staged = Path(work)
            for name in COMPANION_FILES:
                source = content / name
                if not source.is_file():
                    return ["%s: no such file" % source]
                shutil.copyfile(source, staged / name)
            (staged / TUNING_FILE).write_text(candidate, encoding="utf-8")

            try:
                finished = subprocess.run(
                    [
                        self.godot,
                        "--headless",
                        "--path",
                        str(self.repo),
                        "--script",
                        "tools/tuning/check_definitions.gd",
                        "--",
                        str(staged),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=self.timeout,
                )
            except (OSError, subprocess.TimeoutExpired) as problem:
                # A checker that cannot run must not block tuning: the subset
                # gate has already passed, so say so and let the write through.
                return ["the deep check could not run (%s)" % problem]

        reported = [
            line[len(_PREFIX) :].strip()
            for line in finished.stdout.splitlines()
            if line.startswith(_PREFIX)
        ]
        if reported:
            return [_without_the_staging_path(line, staged) for line in reported]
        if "DEFINITIONS-OK" in finished.stdout:
            return []
        return ["the deep check reported nothing (exit %d)" % finished.returncode]


def _without_the_staging_path(line: str, staged: Path) -> str:
    """The loader names the file it read, which was a temporary copy. Say the
    name the player recognises instead."""
    return line.replace("%s/%s" % (staged, TUNING_FILE), "content/%s" % TUNING_FILE)
