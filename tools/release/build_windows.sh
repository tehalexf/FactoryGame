#!/usr/bin/env bash
# One command: a verified Windows build of DEEP FOUNDRY, from WSL2, optionally
# pushed to itch.io.
#
#   bash tools/release/build_windows.sh            # build and verify
#   bash tools/release/build_windows.sh --push     # build, verify, publish
#   bash tools/release/build_windows.sh --no-run   # skip running the .exe
#
# Read docs/RELEASING.md once before the first build: two steps need you — a
# `butler login` and the itch project itself — and this script stops with those
# instructions rather than guessing.
#
# ── The thing this script exists to prevent ───────────────────────────────────
#
# Three asset classes load at runtime out of `assets_licensed/generated/`: weapon
# viewmodels, audio cues and set-dressing props (docs/ASSET_PIPELINE.md §7-9).
# They are derivatives of purchased packs whose licences permit use in a shipped
# game and forbid redistribution as assets, so they are gitignored and Godot's
# importer is kept out of the tree with a `.gdignore`.
#
# **Every one of them has a graceful fallback.** So a build that lost them starts,
# plays, looks worse, sounds worse and says absolutely nothing. That is not
# hypothetical: the first export of this project bundled zero of the ninety-six
# files, and zero rows of `content/` with them, and produced a 130 MB executable
# that ran. A silently degraded tester build is the failure mode here, so this
# script fails loudly in four places instead:
#
#   1. preflight     — a converter has not been run; it says which
#   2. staging       — the tree Godot can actually see is assembled, not assumed
#   3. verify_pck    — the shipped binary's own file index is compared to the list
#   4. verify in-engine — the exported binary is run and asked what it resolved
#
# ── Where the licensed assets go, and where they must not ─────────────────────
#
# Into the PCK, which `export_presets.cfg` embeds in the .exe. Not committed, and
# not loose beside the binary where anyone could lift them out: bundling is what
# the licence permits and redistribution as assets is what it forbids. The build
# directory is gitignored and `tools/assets/check_licensed_staged.py` stays green.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

godot="${GODOT:-godot}"
licensed_root="${LICENSED_ROOT:-$repo_root/assets_licensed}"
build_dir="${BUILD_DIR:-$repo_root/build}"
stage_dir="$build_dir/stage"
out_dir="$build_dir/windows"
binary="$out_dir/DeepFoundry.exe"
console_binary="$out_dir/DeepFoundry.console.exe"
preset="Windows Desktop"
channel="${ITCH_CHANNEL:-windows-x86_64}"

pushing=0
run_it=1
for argument in "$@"; do
  case "$argument" in
    --push) pushing=1 ;;
    --no-run) run_it=0 ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $argument" >&2; exit 2 ;;
  esac
done

say() { printf '\n== %s ==\n' "$1"; }

# ── 1. Preflight ─────────────────────────────────────────────────────────────
#
# Everything that has to be true before any of this is worth doing, including the
# two things only the human can do. See tools/release/preflight.py.
say "preflight"
preflight_args=(--repo-root "$repo_root" --licensed-root "$licensed_root")
[ "$pushing" -eq 1 ] && preflight_args+=(--push)
python3 tools/release/preflight.py "${preflight_args[@]}"

# ── The version, which comes from git and not from a file ────────────────────
#
# `git describe` so a build is traceable to a commit without anybody remembering
# to bump a number, and `--dirty` so a build made over uncommitted edits says so
# in its own version string — which matters when a tester reports something.
# butler takes any string; itch sorts by upload time, not by this.
version="$(git -C "$repo_root" describe --tags --always --dirty 2>/dev/null || echo unknown)"
case "$version" in
  [0-9]*) ;;                 # a real tag: v0.3.1-4-gdeadbee
  *) version="0.0.0+$version" ;;   # no tags yet: 0.0.0+e5539b2
esac
echo "version: $version"

# ── 2. Stage ─────────────────────────────────────────────────────────────────
#
# The working copy cannot be exported directly: `content/.gdignore` and
# `assets_licensed/.gdignore` hide from the *exporter* exactly as thoroughly as
# from the importer, and removing them in place would point Godot's importer at
# seven gigabytes of purchased WAV. tools/release/stage.py explains the whole trick.
say "staging"
python3 - "$repo_root" "$licensed_root" "$stage_dir" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "tools" / "release"))
import stage
staged = stage.prepare(sys.argv[1], sys.argv[2], sys.argv[3])
print(f"{len(staged.kept)} file(s) staged to ship as themselves, under {staged.root}")
PY

# ── 3. Import, then export ───────────────────────────────────────────────────
#
# Twice on a cold cache, for the reason tools/run_tests.sh gives: one pass imports
# the glTF files and the scenes Godot derives from them are not necessarily
# resolvable until a pass that starts with those imports already in place.
say "importing"
passes=1
[ -d "$stage_dir/.godot" ] || passes=2
for _pass in $(seq "$passes"); do
  "$godot" --headless --path "$stage_dir" --import >/dev/null 2>&1 || true
done

say "exporting"
mkdir -p "$out_dir"
# `--export-release`, not `--export-debug`: a debug build ships the debug template,
# runs the remote-debugger listener and prints to a console a tester has not got.
"$godot" --headless --path "$stage_dir" --export-release "$preset" "$binary"
if [ ! -f "$binary" ]; then
  echo "error: the exporter reported success and produced no $binary" >&2
  exit 1
fi

# ── 4. Verify the artefact, twice over ───────────────────────────────────────
say "verifying the pack"
python3 tools/release/verify_pck.py "$binary" --repo-root "$repo_root"

# ── Did the shipped pack's assets actually resolve? ──────────────────────────
#
# The check above proves the bytes are in the pack. It cannot prove the game's own
# loaders accept them at the paths it asks for, and that gap is not theoretical:
# `SetDressing._runtime_texture` reached its atlas through
# `ProjectSettings.globalize_path`, which names a file on disk and there is no disk
# inside a PCK — so the props loaded, the atlas did not, and every purchased prop
# in the exported build rendered untextured with nothing said about it.
#
# So the **shipped pack** is opened with `--main-pack` and the real classes are
# asked what they resolved. `--main-pack` reads the pack embedded in the .exe, so
# this is the artefact that is about to be uploaded and not a Linux rehearsal of
# it; what the local engine supplies is only the ability to run a script, which a
# release template deliberately does not have (see below).
if [ "$run_it" -eq 1 ]; then
  say "asking the shipped pack what it resolved"
  report="$out_dir/bundled_assets.json"
  rm -f "$report"
  "$godot" --headless --main-pack "$binary" \
    --script res://tools/release/verify_bundled_assets.gd -- --out "$report" \
    || { echo "error: the shipped pack reported degraded assets (above)." >&2; exit 1; }
  if [ ! -f "$report" ]; then
    echo "error: nothing wrote a report to $report" >&2
    exit 1
  fi
  python3 - "$report" <<'PY'
import json, sys
found = json.load(open(sys.argv[1]))
print(f"  content:    {found['machine_definitions']} Machines,"
      f" {found['recipe_definitions']} Recipes, {found['item_definitions']} Items")
print(f"  audio:      {found['audio_hero_cues']} of {found['audio_cues']} cues"
      " playing their hero take")
print(f"  viewmodels: {len(found['viewmodels_loaded'])} of"
      f" {found['viewmodels_bundled']} loaded"
      f" — {', '.join(found['viewmodels_loaded'])}")
print(f"  set dress:  {found['set_dressing_instances']} props in"
      f" {found['set_dressing_groups']} meshes,"
      f" purchased={found['set_dressing_uses_purchased_props']},"
      f" atlas={found['set_dressing_uses_purchased_atlas']}")
sys.exit(0 if found["ok"] else 1)
PY

  # ── And does the Windows binary itself start? ───────────────────────────────
  #
  # The half the step above cannot answer, because it ran a Linux engine over the
  # pack. WSL2 hands a Windows executable to Windows through interop, so this runs
  # the actual shipped .exe — the real template, the real embedded pack — through
  # four seconds of the real main scene and reads its own log for complaints.
  #
  # `--quit-after`, not `--script`: **a release template does not implement
  # `--script`.** Pass it one and the engine starts the main scene instead and never
  # returns, which is a twenty-minute way to find out. `--quit-after` works, and
  # running the main scene is the better test anyway: it is what a tester does.
  #
  # `--log-file` because a GUI-subsystem binary does not attach to the console it
  # was launched from, so there is no other way to hear from it.
  if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] || [ -x /mnt/c/Windows/System32/cmd.exe ]; then
    say "starting the Windows binary"
    start_log="$out_dir/start.log"
    rm -f "$start_log"
    # Godot writes the .exe without the execute bit and interop needs it. Nothing
    # to do with the shipped file: butler carries no unix mode and NTFS has no
    # opinion about one.
    chmod +x "$binary" "$console_binary" 2>/dev/null || true
    "$binary" --headless --quit-after "${VERIFY_FRAMES:-240}" \
      --log-file "$(wslpath -w "$start_log" 2>/dev/null || echo "$start_log")"
    if [ ! -f "$start_log" ]; then
      echo "error: the Windows binary ran but wrote no log to $start_log" >&2
      exit 1
    fi
    # `ERROR:` and `SCRIPT ERROR:` are the engine's own prefixes — the same ones
    # tests/engine_log.gd reads, for the same reason: a GDScript runtime error
    # aborts a frame and reports itself here and nowhere else.
    if grep -qE '(SCRIPT )?ERROR:' "$start_log"; then
      echo "error: the exported build did not start clean:" >&2
      grep -nE '(SCRIPT )?ERROR:' "$start_log" >&2
      exit 1
    fi
    echo "  ran ${VERIFY_FRAMES:-240} frames of the real main scene, exit 0, no errors logged"
  else
    echo "note: no WSL interop, so the Windows binary itself was not started." >&2
    echo "      The pack checks above still hold. On Windows, run:" >&2
    echo "        DeepFoundry.console.exe --headless --quit-after 240" >&2
  fi
fi

say "built"
du -h "$binary" | awk '{print "  " $1 "  " $2}'
[ -f "$console_binary" ] && du -h "$console_binary" | awk '{print "  " $1 "  " $2}'

# ── 5. Push ──────────────────────────────────────────────────────────────────
#
# One channel, named `windows-…` so itch tags the platform and its desktop app
# offers the build to Windows testers and nobody else. The whole directory goes
# up — the game and its console wrapper — so a tester gets both.
if [ "$pushing" -eq 1 ]; then
  say "pushing to itch.io"
  # The verification leavings are not part of the game.
  rm -f "$out_dir/bundled_assets.json" "$out_dir/start.log"
  echo "butler push $out_dir ${ITCH_TARGET}:$channel --userversion $version"
  butler push "$out_dir" "${ITCH_TARGET}:$channel" --userversion "$version"
  butler status "${ITCH_TARGET}:$channel" || true
  cat <<EOF

Pushed. Testers get it through the itch desktop app, which updates itself.
Remember: the project must be **Restricted** with a download key per tester, not
public-with-a-password — the app cannot open a protected page, and its automatic
updating is the only reason to do this rather than send a zip.
EOF
else
  echo
  echo "Not pushed. Add --push once docs/RELEASING.md's one-time setup is done."
fi
