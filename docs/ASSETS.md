# Assets: sources, licences, and the hard rule

## The hard rule

**This repository is public. Anything that forbids redistribution must never be
committed.** Purchased assets (Synty, paid itch.io packs, ArtStation packs) and
royalty-free-but-not-redistributable libraries (Sonniss) are licensed for *use
in a shipped game*, not for republication in a public repo.

Those live in `assets_licensed/`, which `.gitignore` excludes. The game reads
that path; the repo never contains it. Keep a local backup — it is not in git.

## What may be committed

- CC0 assets (Quaternius, KayKit, Kenney)
- MIT / permissive code templates
- AI-generated textures and 2D art produced locally
- Blender-scripted meshes and the scripts that generate them
- Anything authored for this project

## Ledger

Every asset records its origin and licence here as it arrives. No exceptions —
reconstructing provenance later is far harder than logging it now.

| Asset | Source | Licence | Committed? |
|---|---|---|---|
| `assets/generated/textures/` (8 tiling textures) | Generated locally, SDXL base 1.0 via `tools/aigen` | Authored for this project; model CreativeML Open RAIL++-M | Yes |
| `assets/generated/icons/` (10 Item icons) | Generated locally, SDXL base 1.0 via `tools/aigen` | Authored for this project; model CreativeML Open RAIL++-M | Yes |
| SDXL base 1.0 weights | `stabilityai/stable-diffusion-xl-base-1.0` @ `4621659` | CreativeML Open RAIL++-M | **No** — gitignored under `tools/aigen/models/`, re-downloaded by `setup.sh` |

Generated art carries its full provenance in a manifest beside it
(`assets/generated/*/manifest.json`): model id and revision, licence, every
sampler setting, the image hash and the versions used. `generate.py --check`
re-verifies that record against the files on disk without needing a GPU.

The model licence covers the *weights*, which are not redistributed here; the
OpenRAIL++-M terms place no ownership claim on generated output. The images
themselves are ours and are safe to commit to a public repo.

## Known licence constraints

- **Sonniss GDC bundles** — royalty-free, no attribution, perpetual, unlimited
  projects. **Prohibits AI/ML training use**: never feed these files to an audio
  model. Not redistributable → `assets_licensed/`.
- **Synty** — no redistribution. Godot is officially unsupported; FBX source
  requires conversion. → `assets_licensed/`.
- **Quaternius, KayKit, Kenney** — CC0. Safe to commit, no attribution required.
- **Mixamo** — royalty-free commercial use, but must be integrated into the
  project and never redistributed standalone. → `assets_licensed/`.
- **Freesound** — per-file licences. Filter to CC0. **CC-BY-NC cannot ship in a
  commercial game.** Log every file's licence at download time.
- **FAB / Epic Standard Licence** — permits use in any engine, but Epic-owned
  content (Megascans legacy, MetaHumans, Paragon) is Unreal-only. Verify the
  EULA directly before any significant purchase.

## Format standard

**glTF 2.0 (`.glb`) is the shipping format.** FBX is an intake format only:
import to Blender, clean the rig, export `.glb`. Godot 4.3+ has the `ufbx`
importer so direct FBX works, but glTF behaves more predictably.

Single shared humanoid skeleton for all characters: the Quaternius Universal
Animation Library rig. Everything humanoid retargets onto it.
