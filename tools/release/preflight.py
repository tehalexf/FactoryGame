"""Everything that has to be true before a build is worth starting.

Run on its own to find out where you stand:

    python3 tools/release/preflight.py            # can I build?
    python3 tools/release/preflight.py --push     # can I build and publish?

`tools/release/build_windows.sh` runs it first and stops on any complaint, because
the two failures this guards against are both quiet:

* **A build missing its runtime-loaded assets still runs.** Weapon viewmodels,
  audio cues and set-dressing props each have a working fallback, so an export
  that lost them produces a tester build that looks worse, sounds worse and says
  nothing at all (docs/ASSET_PIPELINE.md §7-9). Every complaint about them names
  the converter to run.
* **`butler login` and the itch project itself need a human.** Nothing here will
  create an account, spend money or authenticate on anybody's behalf; it says
  exactly what to go and do, in order, and refuses to proceed until it is done.
  docs/RELEASING.md is the long form of the same list.

`problems()` takes the facts about the machine as arguments rather than going and
finding them, so the judgement is testable and `main()` is the only part that has
to touch the environment.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import manifest  # noqa: E402

#: Where Godot keeps export templates on Linux, one directory per engine version.
TEMPLATES_ROOT = Path.home() / ".local/share/godot/export_templates"

#: Where butler keeps the credentials `butler login` writes.
BUTLER_CREDENTIALS = Path.home() / ".config/itch/butler_creds"

#: The preset in `export_presets.cfg` this project builds.
PRESET = "Windows Desktop"


def problems(
    *,
    repo_root: Path,
    licensed_root: Path,
    godot_version: str,
    templates_root: Path,
    butler_on_path: bool = False,
    butler_credentials: Path | None = None,
    butler_api_key: str = "",
    itch_target: str = "",
    pushing: bool = False,
) -> list[str]:
    """Every reason not to build, in the order they are worth fixing in.

    An empty list means go. The toolchain comes first because there is no point
    cutting thirty-seven audio cues for a build that cannot run the exporter, and
    the itch setup comes last because it only matters once there is a build.
    """
    found: list[str] = []
    found += _toolchain(godot_version, templates_root, Path(repo_root))
    found += _assets(Path(repo_root), Path(licensed_root))
    if pushing:
        found += _publishing(
            butler_on_path, butler_credentials, butler_api_key, itch_target
        )
    return found


def _toolchain(godot_version: str, templates_root: Path, repo_root: Path) -> list[str]:
    found = []
    if not godot_version:
        found.append(
            "godot is not on PATH, or did not answer --version. The build needs"
            " the same 4.7.x binary the suite runs on; set GODOT=/path/to/godot."
        )
        return found

    engine = _template_directory_name(godot_version)
    installed = Path(templates_root) / engine
    if not installed.is_dir() or not any(installed.glob("windows_release_x86_64.exe")):
        # There is no headless way to install these, so the message has to be the
        # whole instruction. They are about 1.3 GB compressed and this project has
        # never had them: an export without them fails with "no export template
        # found", which does not say where to get one.
        found.append(
            f"Godot export templates for {engine} are not installed."
            f"\n      They are not optional and there is no headless installer."
            f"\n      Download:"
            f"\n        curl -fLO https://github.com/godotengine/godot/releases/download/"
            f"{engine.replace('.stable', '-stable')}/"
            f"Godot_v{engine.replace('.stable', '-stable')}_export_templates.tpz"
            f"\n      then unzip it and move the `templates/` directory it contains to:"
            f"\n        {installed}"
            f"\n      (the .tpz is a zip; the directory inside carries a version.txt"
            f" that must read {engine})"
        )

    presets = Path(repo_root) / "export_presets.cfg"
    if not presets.is_file():
        found.append(
            f"{presets} is missing. It is committed in this project — see"
            " docs/RELEASING.md — because the include_filter in it is what"
            " bundles the runtime-loaded assets."
        )
    elif f'name="{PRESET}"' not in presets.read_text():
        found.append(f'export_presets.cfg carries no preset named "{PRESET}".')

    if shutil.which("rsync") is None:
        found.append("rsync is not on PATH; it is what assembles the staging tree.")
    return found


def _assets(repo_root: Path, licensed_root: Path) -> list[str]:
    """The ticket's whole point: a missing converter output is a hard stop."""
    faults = manifest.audit(repo_root, licensed_root)
    if not faults:
        return []
    header = (
        "The runtime-loaded assets are not complete, so this build would ship"
        " degraded.\n    Every one of these has a graceful fallback, which is"
        " why a build without them\n    runs, looks worse, sounds worse and"
        f" reports nothing. Quarantine: {licensed_root}"
    )
    return [header] + [fault.report() for fault in faults]


def _publishing(
    butler_on_path: bool,
    credentials: Path | None,
    api_key: str,
    itch_target: str,
) -> list[str]:
    found = []
    if not butler_on_path:
        found.append(
            "butler is not on PATH. It is itch.io's upload tool and it is what"
            " gives testers automatic updates."
            "\n      Install: https://itch.io/docs/butler/installing.html"
            "\n      then put it on PATH and run `butler -V` to check."
        )
    logged_in = bool(api_key) or (credentials is not None and Path(credentials).is_file())
    if not logged_in:
        found.append(
            "butler is not logged in. **This step needs you** — it opens a browser"
            " and nothing here will authenticate on your behalf."
            "\n      Run:  butler login"
            "\n      (or export BUTLER_API_KEY=… from"
            " https://itch.io/user/settings/api-keys for an unattended build)"
        )
    if not itch_target:
        found.append(
            "ITCH_TARGET is not set, so there is nowhere to push to."
            "\n      **This step needs you.** Create the project yourself at"
            " https://itch.io/game/new:"
            "\n        1. Kind of project: Downloadable."
            "\n        2. Visibility & access: **Restricted**, and under it"
            ' "Anyone with a key or in a press list".'
            "\n           Then add one download key per tester."
            "\n           Do NOT use the public-with-a-password option: the itch"
            " desktop app"
            "\n           cannot open a protected page, and its automatic updating"
            " is the whole"
            "\n           reason to hand a tester an itch build rather than a zip."
            "\n        3. Save it as a draft; it does not have to be published."
            "\n      Then:  export ITCH_TARGET=<your-itch-username>/<project-url>"
        )
    elif itch_target.count("/") != 1 or not all(itch_target.split("/")):
        found.append(
            f"ITCH_TARGET={itch_target!r} is not of the form user/game."
            " butler needs both halves, and the second is the project's URL slug."
        )
    return found


def _template_directory_name(version: str) -> str:
    """`4.7.2.stable.official.ed1daf0bf` -> `4.7.2.stable`, which names the directory."""
    parts = version.strip().split(".")
    for index, part in enumerate(parts):
        if not part.isdigit():
            return ".".join(parts[: index + 1])
    return ".".join(parts)


def godot_version(binary: str) -> str:
    """What `--version` says, or "" if the binary is not there or will not answer."""
    if shutil.which(binary) is None:
        return ""
    try:
        done = subprocess.run(
            [binary, "--version"], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip().splitlines()[-1] if done.stdout.strip() else ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--push",
        action="store_true",
        help="also check the itch.io setup, which needs a human to have done two things",
    )
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--licensed-root",
        type=Path,
        default=None,
        help="the quarantine; defaults to <repo>/assets_licensed",
    )
    arguments = parser.parse_args(argv)

    repo_root = arguments.repo_root.resolve()
    licensed_root = arguments.licensed_root or (repo_root / "assets_licensed")

    found = problems(
        repo_root=repo_root,
        licensed_root=licensed_root,
        godot_version=godot_version(os.environ.get("GODOT", "godot")),
        templates_root=Path(os.environ.get("GODOT_TEMPLATES", TEMPLATES_ROOT)),
        butler_on_path=shutil.which("butler") is not None,
        butler_credentials=BUTLER_CREDENTIALS,
        butler_api_key=os.environ.get("BUTLER_API_KEY", ""),
        itch_target=os.environ.get("ITCH_TARGET", ""),
        pushing=arguments.push,
    )
    if not found:
        print("preflight: ready to build" + (" and push" if arguments.push else ""))
        return 0
    print("preflight: this build would not be worth handing to anyone.\n", file=sys.stderr)
    for problem in found:
        print(f"  - {problem}\n", file=sys.stderr)
    print("See docs/RELEASING.md.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
