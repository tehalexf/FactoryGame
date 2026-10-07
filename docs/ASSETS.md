# Assets: sources, licences, and the hard rule

## The hard rule

**This repository is public. Anything that forbids redistribution must never be
committed.** Purchased assets (Synty, paid itch.io packs, ArtStation packs) and
royalty-free-but-not-redistributable libraries (Sonniss) are licensed for *use
in a shipped game*, not for republication in a public repo.

Those live in `assets_licensed/`, which `.gitignore` excludes. The game reads
that path; the repo never contains it. Keep a local backup — it is not in git.

**The rule is enforced, not merely stated.** `tools/assets/check_licensed_staged.py`
fails loudly if anything licensed is staged or already committed. Install it as a
pre-commit hook once per clone:

```sh
bash tools/git/install_hooks.sh
```

CI (`.github/workflows/assets.yml`) runs the same guard on every push, so
forgetting the installer is caught rather than silently tolerated. See
[ASSET_PIPELINE.md](ASSET_PIPELINE.md) for the whole mechanism.

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
| `assets/characters/skeleton/` — Skeleton character, 5 animations (Attack, Death, Idle, Running, Spawn) | Quaternius, "LowPoly Animated Monsters" pack, <https://quaternius.itch.io/lowpoly-animated-monsters> (official itch.io release; <https://quaternius.com/packs/ultimatemonsters.html> hosts the same work) | **CC0 1.0** — public domain, no attribution required | Yes: intake `intake/Skeleton.fbx` and shipping `Skeleton.glb` |
| `assets/characters/knight/` — Knight character, 12 animations (Idle, Walking, Run, Jump, Roll, Death, sword variants) | Quaternius, "LowPoly Animated Knight" pack, <https://quaternius.itch.io/lowpoly-animated-knight> | **CC0 1.0** | Yes: intake `intake/KnightCharacter.fbx` and shipping `KnightCharacter.glb` |
| Reference humanoid rig — bone map only, no mesh committed | Quaternius, "Universal Base Characters" / "Universal Animation Library", <https://quaternius.itch.io/universal-base-characters> | **CC0 1.0** | Bone map only (`tools/assets/bone_maps/quaternius_universal_humanoid.json`); the 14 MB character itself is not committed |

Both committed characters were converted with
`tools/assets/rebuild_assets.sh`, which records the exact flags used. Each
asset's intake FBX is committed alongside its `.glb` so the conversion can be
re-derived rather than trusted.

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

Single shared humanoid skeleton for all characters: **Godot's
`SkeletonProfileHumanoid` bone names**, with the Quaternius Universal Animation
Library rig as the reference humanoid source mapped onto them. Everything
humanoid retargets onto that naming, at conversion time.

The conversion path, the bone maps, the retarget path and the verification
commands are all in [ASSET_PIPELINE.md](ASSET_PIPELINE.md).
