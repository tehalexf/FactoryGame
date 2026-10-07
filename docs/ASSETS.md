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
| _(none yet)_ | | | |

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
