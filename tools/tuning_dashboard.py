#!/usr/bin/env python3
"""DEEP FOUNDRY — the live tuning dashboard.

    python3 tools/tuning_dashboard.py

Opens a browser on `content/tuning.toml`: every tuning value, grouped by section,
labelled with the file's own comment, sliders for the bounded feel values and
number boxes for the rest. Per-value and global reset to the shipped defaults. A
history of every write, each one restorable.

**The file is the API.** The dashboard reads and writes `content/tuning.toml` and
nothing else; `game/definition_watcher.gd` is already watching it and applies the
change on save, so an edit lands in the Run you are standing in. There is no
socket into the game, which is why this works identically whether the game is
running or not — and why two Runs, or none, make no difference to it.

**A malformed write would be worse than no dashboard.** `Definitions` carries no
definitions when any file has an error, so one bad value strands the Run on its
last good content. Three things stop that: the value is checked against the TOML
subset `sim/toml_document.gd` accepts and against the kind `sim/definitions.gd`
reads it as; the whole candidate file is then handed to the game's own loader in
a throwaway directory (about a quarter of a second — pass `--shallow` to skip it);
and the write itself is a temp file and a rename, after a snapshot.

Options:

    --port N            listen on N instead of 8765
    --no-browser        do not open a browser
    --shallow           skip the loader check; the subset gate still stands
    --adopt-defaults    make the current file the new "shipped default"
    --check             validate content/tuning.toml and exit
"""

from __future__ import annotations

import argparse
import shutil
import sys
import threading
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tuning import definitions_check, server, store, toml_subset  # noqa: E402

REPO = HERE.parent


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tuning_dashboard",
        description="Edit content/tuning.toml in a browser, with reset and rollback.",
    )
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument(
        "--shallow",
        action="store_true",
        help="skip the Godot loader check before each write",
    )
    parser.add_argument(
        "--adopt-defaults",
        action="store_true",
        help="make the current content/tuning.toml the shipped default and exit",
    )
    parser.add_argument(
        "--check", action="store_true", help="validate the tuning file and exit"
    )
    options = parser.parse_args(argv)

    opened = store.open_repository(REPO, deep=not options.shallow)

    if options.adopt_defaults:
        return _adopt_defaults(opened)
    if options.check:
        return _check(opened)

    drift = opened.unknown_defaults()
    if drift:
        print(
            "warning: the shipped defaults name %d keys content/tuning.toml does "
            "not: %s" % (len(drift), ", ".join(drift[:5])),
            file=sys.stderr,
        )

    http = server.serve(opened, host=options.host, port=options.port)
    url = "http://%s:%d/" % (options.host, options.port)

    deep = opened.deep_check
    print("DEEP FOUNDRY tuning dashboard")
    print("  file     %s" % opened.live_path)
    print("  defaults %s" % opened.defaults_path)
    print("  history  %s" % opened.history_dir)
    print(
        "  checks   TOML subset + value kind%s"
        % (
            ", and the game's own loader"
            if deep is not None and deep.available
            else " (no godot on PATH: loader check skipped)"
        )
    )
    print("  serving  %s   — ctrl-c to stop" % url)

    if not options.no_browser:
        # In a thread so a browser that blocks on launch does not hold the
        # server off the port it is being pointed at.
        threading.Thread(target=webbrowser.open, args=(url,), daemon=True).start()

    try:
        http.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        http.server_close()
    return 0


def _adopt_defaults(opened: store.TuningStore) -> int:
    """Re-baseline what "reset" goes back to.

    Deliberately a separate, explicit command. The whole value of the changed
    markers is that they measure against something that does not move while you
    are tuning, so adopting new defaults is something you say rather than
    something that happens.
    """
    source = opened.live_path.read_text(encoding="utf-8")
    errors = toml_subset.validate(source, str(opened.live_path))
    if errors:
        print("refusing: that file would not load", file=sys.stderr)
        for error in errors:
            print("  %s" % error, file=sys.stderr)
        return 1
    shutil.copyfile(opened.live_path, opened.defaults_path)
    print("adopted %s as the shipped defaults" % opened.live_path)
    return 0


def _check(opened: store.TuningStore) -> int:
    """What the dashboard would say about the file as it stands. Useful on its
    own, and the thing to run when the game refuses a reload and you want the
    reason without starting a browser."""
    source = opened.live_path.read_text(encoding="utf-8")
    errors = toml_subset.validate(source, str(opened.live_path))
    checker = definitions_check.Checker(REPO)
    if not errors and checker.available:
        errors = checker.errors(source)
    if errors:
        for error in errors:
            print(error)
        return 1
    changed = opened.changed_from_default()
    print("%s: loads" % opened.live_path)
    print("%d value(s) changed from the shipped defaults" % len(changed))
    for key in sorted(changed):
        now, default = changed[key]
        print("  %-56s %s  (default %s)" % (key, now, default))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
