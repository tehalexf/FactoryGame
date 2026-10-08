# Releasing: a Windows build, and handing it to testers

Per build, from WSL2:

```sh
bash tools/release/build_windows.sh            # build and verify
bash tools/release/build_windows.sh --push     # build, verify, publish to itch.io
```

That is the whole of it. The rest of this file is the one-time setup `--push`
needs, and the reasoning behind the parts that are not obvious.

---

## One-time setup, in order

Steps 1 and 2 are done. **Steps 3 and 4 need you** — they involve a browser and an
account, and nothing in this repository will create an account, spend money or
authenticate on your behalf. `tools/release/preflight.py` stops the build with
these instructions until they are done.

### 1. Export templates — done

Godot cannot export without the templates for its exact version, they are about
1.3 GB, and there is no headless installer. For the record, this is what was run:

```sh
curl -fLO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip Godot_v4.7.2-stable_export_templates.tpz        # yields templates/
mv templates ~/.local/share/godot/export_templates/4.7.2.stable
```

The directory name must be the version with `.stable` on it, and the
`version.txt` inside must agree. After a Godot upgrade this has to be redone, and
the preflight will say so by version number rather than letting the export fail
with "no export template found".

### 2. The export preset — done, and committed

`export_presets.cfg` is in git, which is the opposite of Godot's own template.
It is not a preference: its `include_filter` is the only thing that puts the
runtime-loaded assets and the whole of `content/` into the PCK. Read the comments
in it before changing a line.

### 3. Install butler and log in — **needs you**

[butler](https://itch.io/docs/butler/installing.html) is itch.io's upload tool and
is what gives testers automatic updates.

```sh
# install butler, put it on PATH, then:
butler -V
butler login          # opens a browser; only you can do this
```

For an unattended build instead, make a key at
<https://itch.io/user/settings/api-keys> and `export BUTLER_API_KEY=…`.

### 4. Create the itch project — **needs you**

At <https://itch.io/game/new>:

1. **Kind of project:** Downloadable.
2. **Visibility & access: Restricted**, and under it *"Anyone with a key or in a
   press list"*. Then add **one download key per tester**.
3. Save it as a draft. It does not need to be published.

Then tell the build where to push:

```sh
export ITCH_TARGET=<your-itch-username>/<project-url-slug>
```

> **Do not use the public-with-a-password option.** It looks interchangeable with
> Restricted from the itch dashboard and it is not: **the itch desktop app cannot
> open a password-protected page**, and that app's automatic updating is the entire
> reason to hand a tester an itch build rather than a zip. A password would reduce
> itch to a file host with extra steps. Per-tester download keys also mean you can
> revoke one person without disturbing anybody else.

---

## What a build does, and the four places it refuses

```
preflight → stage → import → export → verify the pack → run the binary → push
```

### Why it refuses at all

Three asset classes load at runtime out of `assets_licensed/generated/`:

| Class | Converter | What the game does without it |
|---|---|---|
| weapon viewmodels | `tools/assets/convert_weapons.sh` | two placeholder boxes in your hands |
| audio cues | `tools/assets/convert_audio.sh` | the committed CC0 Kenney sounds |
| set-dressing props | `tools/assets/convert_props.sh` | a yard of self-authored stand-ins |

Every one of those fallbacks is deliberate and good — a clone of this public
repository without the purchased packs builds, tests green and plays
(docs/ASSET_PIPELINE.md §7-9). **For a release it is a trap.** A build that lost
them starts, plays, looks worse, sounds worse and says nothing at all, and a
silently degraded tester build is worse than no build.

So the build stops in four places, and each says what to do:

1. **preflight** — compares the quarantine against what the three converters say
   they produce, file by file, and names the converter to run. One missing cue is
   as fatal as an empty directory, because a converter that ran before a cue was
   added to the recipe is exactly the case nobody notices.
2. **staging** — assembles the tree Godot can actually see (below). An absent
   quarantine is an error, never an empty build.
3. **`verify_pck.py`** — reads the shipped binary's own pack index and compares it
   to the same list. Proves the bytes are in there at the paths the game asks for.
4. **`verify_bundled_assets.gd`** — opens the shipped pack with `--main-pack` and
   asks the game's own classes what they *resolved*: how many cues play their hero
   take, how many viewmodels loaded, whether the yard is purchased props and
   whether its atlas came with them. Then the real Windows `.exe` is started
   through WSL interop for 240 frames of the real main scene and its log is read
   for errors.

Steps 3 and 4 are both needed. Step 3 cannot tell a file the loader accepts from
one it does not; step 4 cannot tell you which file is missing.

### Why it exports a staging tree rather than the working copy

`content/.gdignore` and `assets_licensed/.gdignore` exist to keep Godot's importer
out — out of seven gigabytes of purchased WAV, and off the `.csv` files it would
otherwise claim as translation tables. **A `.gdignore` hides a directory from the
*exporter* exactly as thoroughly as from the importer.** The first export of this
project therefore contained zero of the ninety-six licensed files *and* zero rows
of `content/`, and still produced a 130 MB executable that ran.

So `tools/release/stage.py` rsyncs the project to `build/stage/`, copies only
`generated/` out of the quarantine, deletes those two markers in the copy, and
writes an `importer="keep"` sidecar beside every affected file. "Keep File (No
Import)" is Godot's own way to say *ship this file as it is*: the exporter stores
the raw bytes at the raw path, and nothing is converted. The working copy is never
touched.

### Where the licensed assets end up

**Inside the PCK, which is embedded in the `.exe`.** One file, nothing loose beside
it. That is the line the licences draw: use in a shipped game is permitted,
redistribution as assets is not, and a loose folder anybody can open is the second
thing. They are never committed — `build/` is gitignored and
`python3 tools/assets/check_licensed_staged.py --all` stays green.

### The version

`git describe --tags --always --dirty`, with `0.0.0+` in front of it while there
are no tags. `--dirty` is in there on purpose: a build made over uncommitted edits
says so in its own version string, which is what you want when a tester reports
something odd. Tag a release and the version becomes the tag.

### The channel

`windows-x86_64`. The `windows-` prefix is not cosmetic — it is how itch detects
the platform, which is what makes the desktop app offer the build to Windows
testers and nobody else. Override with `ITCH_CHANNEL` if you ever need to.

---

## Icon and version metadata are deliberately skipped

`application/modify_resources=false` in the preset, so the `.exe` carries Godot's
default icon and no file-version resource.

Embedding them needs **rcedit under Wine**, because rcedit is a Windows program and
this builds on Linux. Neither Wine nor rcedit is installed here, and setting them
up means a Wine prefix, a `.ico` and a Godot *editor setting*
(`export/windows/rcedit`) — which is per-machine state the repository cannot carry,
so the build would work on one machine and not on a clone.

It is also not worth it yet: **there is no icon art.** The thing to embed does not
exist, and a default icon on a build going to a handful of named testers costs
nothing. When there is an icon:

1. `winetricks`/`wine` installed, and
   [rcedit](https://github.com/electron/rcedit/releases) downloaded;
2. point Godot's editor setting `export/windows/rcedit` at it, or set
   `GODOT_WINDOWS_RCEDIT` — note this has to be done on **every** machine that
   builds;
3. in `export_presets.cfg`, set `application/modify_resources=true`,
   `application/icon="res://assets/icon.ico"`, and fill in `file_version`,
   `product_version`, `product_name` and `company_name`.

Until then the honest statement is: skipped on purpose, and the reason is an
absent icon rather than an awkward toolchain.

---

## Things worth knowing if a build goes wrong

- **`--script` does nothing in a release template.** Pass it to the exported `.exe`
  and the engine starts the main scene instead and never returns. That is why the
  shipped pack is inspected with `godot --headless --main-pack <the .exe>` and the
  Windows binary itself is only ever run with `--quit-after`.
- **`DeepFoundry.console.exe` is shipped on purpose.** A GUI-subsystem binary does
  not attach to the console it was launched from, so that wrapper is how a tester
  gets a log: `DeepFoundry.console.exe --headless --quit-after 240`, or just run it
  normally and read what it prints.
- **A Godot upgrade breaks two things loudly.** The export templates (the preflight
  names the version) and `tools/release/pck.py`, which reads pack format version 4
  and refuses an unknown one by number rather than mis-parsing it. 4.7 already
  bumped that format once.
- **The staging tree is kept between builds** so its import cache stays warm. It is
  under `build/stage/`; delete it if you want a cold build.

## Out of scope

Steam. It has a thirty-day waiting period before anything can be distributed and
is a separate clock.
