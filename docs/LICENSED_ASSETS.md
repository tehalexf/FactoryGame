# Licensed assets: what is in the quarantine, and what it is for

Everything described here lives under `assets_licensed/`, which is gitignored and
**must never be committed** — this repository is public and none of these packs
may be redistributed. See [ASSETS.md](ASSETS.md) for the rule and the ledger, and
[ASSET_PIPELINE.md](ASSET_PIPELINE.md) for the guard that enforces it.

**The files are not in git, so this document is.** It is the only record of what
was bought, what each pack contains, where it sits and what it is good for. If
the local copy is lost, this tells you what to download again. Keep a backup of
`assets_licensed/`; git will not do it for you.

## Two prohibitions that bind this project specifically

This project runs a local image-generation pipeline in `tools/aigen/`. Two of
these licences forbid machine-learning use of their assets outright:

* **Sonniss** — the `#GameAudioGDC` EULA has a clause headed **NO AI TRAINING OR
  USAGE**: the licensee is "expressly prohibited from using any sound effects
  licensed under this Agreement for the purpose of training artificial
  intelligence technologies", including anything that generates work in a similar
  style, and may not "use, reproduce, or otherwise leverage" them for developing,
  training or enhancing AI.
* **Lukami Ch. Low Poly Industrial Pack 60** — may not be used "to train,
  fine-tune, or as input to machine-learning or generative-AI models or
  datasets", and may not be minted as NFTs or registered on any blockchain.

**Never feed any file under `assets_licensed/` into `tools/aigen/`** — not as a
training input, not as an img2img or ControlNet input, not as a reference image,
and not into any other model. The prohibition covers "input to", not merely
"training on", so using one of these meshes as a render reference for a generated
texture is also out. `tools/aigen` reads its own prompts and its own output
directory; keep it that way.

The same restriction is recorded in [ASSETS.md](ASSETS.md) under "Known licence
constraints", because that is the file anyone checks before adding an asset.

## Why Godot does not scan this directory

`assets_licensed/.gdignore` — an empty marker, and the one path inside the
quarantine that is committed — keeps Godot's importer out. Without it the engine
walks several gigabytes of third-party Unity projects and raw WAV libraries on
every scan, and was observed to stop importing this repository's *own* assets
part-way through. The licence guard permits that one file only while it is empty.

The practical consequence: **nothing here is loaded directly by the game.** To
use a licensed asset, convert it out of the quarantine into the shipping tree —
and only if its licence permits that output to be committed, which for every pack
below it does not. In practice that means a licensed mesh can inform a
self-authored one, or be loaded at runtime from a path outside the repository,
but it cannot become a committed `.glb`.

## The packs

### `rgsdev/` — RgsDev "Low Poly FPS Starter Kit" v1.1

| | |
|---|---|
| Path | `assets_licensed/rgsdev/_RgsDev Low Poly FPS Starter Kit v1.1/` |
| Source zip | `_RgsDev Low Poly FPS Starter Kit v1.1.zip`, 149 MB |
| On disk | 381 MB — of which 357 MB is Unity's regenerable `Library/` cache |
| Shape | A complete **Unity 2019.4.40f1 project**, not a loose asset folder |
| Licence | Purchased. Non-redistributable. |

What is actually useful is `Assets/_RgsDev_FPS/`:

* **5 rigged first-person arms meshes**, each with its weapon, in
  `Meshes/Weapons/`: `Arms_M416_Assault_Rifle.fbx` (27 bones),
  `Arms_Glock_G48.fbx` (26), `Arms_AWM_Sniper_Rifle.fbx` (31),
  `Arms_Combat_Knife.fbx` (25), `Arms_Grenade.fbx` (26). The arms mesh
  (`Arms_Mesh`) and the weapon mesh are separate objects on one armature.
* **43 animation clips**, all already split — see
  "The FP weapon animations" below.
* 6 prop meshes in `Meshes/Props/`: barrel, wall, their shattered variants,
  brick, smoke.
* 39 WAV sound effects in `Sounds/` — shots, reloads, mag in/out, footsteps,
  shell casings, grenade pin and explosions, melee, jump, land, destruction.
* 27 materials, 3 textures, 27 prefabs, 1 scene, 7 Unity animator controllers.
* **14 C# scripts** — `FPSController`, `WeaponRanged`, `WeaponMelee`,
  `WeaponManager`, `WeaponSway`, `ThrowGrenadeManager`, `Grenade`,
  `DestructibleObject`, `Explosion`, `CameraShake`, `GameManager`,
  `TimeManager`, `TimedObjectDestroyer`. **C# and Unity-only**: this project is
  GDScript with no dotnet, and ADR 0001 puts all logic in the Simulation
  outside the node tree, so these are *documentation of tuned values* (fire
  rate, damage, spread, ADS zoom, reload time, magazine size) and nothing more.
  `Low Poly FPS Starter Kit Docs.pdf` in the same folder documents every
  script's parameters, which is the quickest way to read those numbers.

What it is for: the only rigged first-person arms in the collection, and a
reference set of FPS feel values.

### `fps-weapon-pack-unknown-vendor/` — "Weapon pack", "FPS Arms", "Animation UE FIX"

| | |
|---|---|
| Path | `assets_licensed/fps-weapon-pack-unknown-vendor/` |
| Source zips | `Weapon pack.zip` (332 MB), `FPS Arms.zip` (7.6 MB), `Animation UE FIX.zip` (14 MB) |
| On disk | 431 MB |
| Licence | Purchased. Non-redistributable. |

**The vendor is not recorded anywhere inside these three zips** — no licence
file, no readme, no attribution. The directory is named for what it is rather
than who made it. If anyone can identify the seller, rename the directory and
record it in [ASSETS.md](ASSETS.md); until then this is the gap in the ledger.
"Weapon pack" and "Animation UE FIX" are certainly the same product: the fix
covers exactly the six weapons the pack ships.

`Weapon pack/` — **6 animated weapons with first-person arms**, one FBX each,
with PBR texture sets beside them:

| FBX | Weapon mesh | Timeline | Clips |
|---|---|---|---|
| `Akm_animation.fbx` | `AK_mesh` | 1–361 | Shoot, Shoot2, walk, run, PutAway, Draw, reload, idle |
| `Aug_animation.fbx` | `Aug_A1` | 1–301 | Shoot, walk, run, PutAway, Draw, reload, idle |
| `Deagle_Animation.fbx` | `Frame_low` | 1–301 | Shoot, Shoot_2, walk, run, PutAway, Draw, reload, idle |
| `L96_animation.fbx` | `L96_mesh`, `Scope_mesh` | 1–361 | Shoot, **Chamber**, walk, run, PutAway, Draw, reload, idle |
| `MP7_animation.fbx` | `mp7_mesh` | 1–306 | Shoot, walk, run, Putaway, Draw, reload, idle |
| `Shotgun_animation.fbx` | `KSG_mesh`, 2 shells | 1–406 | Shoot, **Pump**, walk, run, PutAway, Draw, **Reload_Start**, reload, **Reload_End**, idle |

Each carries a 41-bone armature with full finger chains (`L_Thumb1..3`,
`L_Index1..3`, `L_Middle1..3`, `L_Ring1..3`, `L_Pinky0..3`, both hands, plus
`*_ForearmTwist`), three skin-tone arm meshes (`Male_mesh`, `Female_mesh`,
`Military_mesh` — pick one), weapon part bones (`mag_bn`, `bolt_bn`, `trg_bn`,
`rls_bn`, `sfti_bn`, `blt_bn`), a `Camera001` and a `Camera point controller`.
Textures are large: the Deagle alone ships three `.tif` normal maps totalling
180 MB, and the AKM's base colour is a 17 MB PNG. Downscale on the way in.

`FPS Arms/` — a separate, simpler arms-only asset: `Export/FPS_Arms.fbx`
(113 KB), the authoring `_RAW Files/Arms.blend` and `FPS_Arms.psd`, and **8
hand textures** in two skin tones × four states (plain, cuts, bloody,
tattooed). macOS `.DS_Store` and `__MACOSX` cruft throughout; ignore it.

`Animation UE FIX/` — six `*_UE.fbx` reworked for Unreal. **Do not use these.**
See below.

### The FP weapon animations — investigated, and there is nothing to split

The concern was that the animations arrive as one long clip needing manual
splitting in Blender, with "Animation UE FIX" as an Unreal-only workaround.
Both source packs were imported in Blender 5.2.2 and their actions enumerated.
**The premise is wrong, and it is wrong in the opposite direction from the
worry.**

* **RgsDev** — every clip is already its own FBX take, each starting at frame 1.
  43 clips across the five arms FBX: M416 has 11 (ADS, ADS_Fire, Draw, Fire,
  Holster, Idle, Jump, Melee, Reload, Run, Walk), Glock 12 (the same plus
  Empty_Mag and Reload_Empty), AWM 10, Knife 9 (three attacks, Draw, Holster,
  Idle, Jump, Run, Walk), Grenade 1 (Throw). Blender imports them as named
  actions directly. Nothing to do.

* **Weapon pack** — each FBX holds **9 to 11 named FBX takes with exact frame
  ranges**, *plus* a take called `default` spanning the whole timeline. The
  `default` take is the "one long clip": it is a convenience take that contains
  every action end to end, and it sits alongside the split ones rather than
  instead of them. For the AKM, for instance: `Shoot` 6–25, `Shoot2` 31–50,
  `walk` 56–80, `run` 91–111, `PutAway` 121–140, `Draw` 146–166, `reload`
  171–249, `idle` 261–361, and `default` 1–361. Import the named takes and
  ignore `default`.

* **`Animation UE FIX`** — *this* is the file with one long clip. Each `*_UE.fbx`
  has exactly one take, `Take 001`, spanning the whole timeline, on a single
  merged 44–50 bone armature that absorbs the weapon part bones into the
  character skeleton. It is the Unreal-oriented repackaging: Unreal imports a
  take per animation sequence and prefers one skeleton, so the vendor flattened
  the takes and merged the rigs. For us that is a strict downgrade — it throws
  away exactly the clip boundaries we want. **Use `Weapon pack/` and ignore
  `Animation UE FIX/`.**

  If the merged rig is ever wanted, note that `Take 001`'s length matches the
  corresponding `Weapon pack` timeline exactly (AK 361, KSG 406, Aug/Deagle 301,
  MP7 306), so the Weapon pack's own take ranges can be used as the cut list.

No splitting work was performed, because none is needed. The frame ranges above
are recorded so the finding does not have to be re-derived.

### Wired in: which pack is which weapon, and what the conversion has to fix

`tools/assets/convert_weapons.sh` is the recipe and **the only record of the
mapping**, since none of the files it reads are in git:

| Gear frame | Source | Why |
|---|---|---|
| `bolt_rifle` | `Weapon pack/L96_animation.fbx` | The only one with a `Chamber` take, which is what a bolt-action wants between shots — and the Bolt Rifle's 0.8 s interval is the only one with room to play it |
| `drum_autocannon` | `Weapon pack/Akm_animation.fbx` | The pack's automatic weapon, and it ships two shot takes |
| `pneumatic_wrench` | `rgsdev/.../Arms_Combat_Knife.fbx` | The only rigged arms in the collection that swing rather than shoot |

Run it with `bash tools/assets/convert_weapons.sh`; it writes
`assets_licensed/generated/gear/<weapon id>.glb`, which is **gitignored and must
stay that way** — a converted GLB is a derivative of a non-redistributable asset
and is exactly as forbidden as the FBX. `game/weapon_viewmodel.gd` loads it at
runtime and draws placeholder boxes when it is absent, which on most clones it
is.

Four things about these files bite, and all four are now handled by
`tools/assets/fbx_to_viewmodel.py` rather than by anyone's shell history. They
are written up with the flags that answer them in
[ASSET_PIPELINE.md](ASSET_PIPELINE.md) section 7; what belongs *here*, because it
is a fact about the packs, is what they are:

* **A take is a group of actions, not one action.** The hands are animated as
  bones on the 41-bone armature, and the weapon's own magazine, bolt, trigger and
  safety are animated as **objects** (`mag_bn`, `bolt_bn`, `trg_bn`, `rls_bn`,
  `sfti_bn`, or `Mag`/`Bolt`/`Striker`/`Bold_Handle` on the L96). One take
  therefore imports as a dozen separate actions, each named
  `<object>|<take>|BaseLayer` — 3ds Max's three-part naming, where the last part
  is the authoring animation layer rather than the take.
* **The weapon body arrives loose.** `L96_mesh` and `AK_mesh` have no parent and
  no usable animation: the vendor skinned them to the weapon part helpers rather
  than to the character rig, and an FBX skin cluster over plain helpers is not
  something Blender's importer can reconstruct. Imported as-is, the hands animate
  and the rifle sits on the floor at the world origin. They have to be parented
  to `Main_Bone` / `ak_main_bn` in the bind pose.
* **`Camera001` gives the framing, but only its position.** An FBX camera's own
  axes are a convention Blender's importer does not normalise, and using its
  orientation puts the weapon across the view. Its *position* is unambiguous —
  1.72 m up — and the scene around it is in Blender's world convention with the
  arms reaching along -Y, so the model needs a half turn and nothing else.
* **The textures do not resolve, and for the AKM there are none to resolve.** The
  FBX carries the authoring machine's paths (`C:/.../AppData/.../3dsMax/...`,
  `l96a1/textures/T_S96_ALB.tga.png`) while the zip ships
  `L96_textures/L96_ALB.png` — different names, so matching by file name finds
  nothing — and the AKM FBX references no images at all. Every surface therefore
  arrives white. The recipe repaints them from
  `tools/assets/dieselpunk_palette.json`, which is a number rather than an asset
  and so can be committed; a texture pass that recovers the real maps would be a
  nicer-looking ticket of its own.

The RgsDev knife is the simple case by comparison: one armature, both meshes
skinned to it, nine takes already named `Knife_*_Anim`, and metres rather than
centimetres. What it has not got is an authoring camera, so its framing is three
numbers found by looking at the render.

### `shapita/` — Factory Line 86

| | |
|---|---|
| Paths | `assets_licensed/shapita/factory-line-86-assets-v1.5/` and `assets_licensed/shapita/Factory-Line-Godot86/` |
| Source zips | `Factory-Line-86-Assets-v1.5.zip` (43 MB), `Factory-Line-Godot86-Static-Prefabs-v1.0.zip` (2.4 MB) |
| On disk | 109 MB |
| Vendor | Shapita, <https://shapita.itch.io> |
| Licence | "FACTORY LINE — COMMERCIAL ASSET LICENSE v1.0". Use and modify in unlimited personal or commercial projects, attribution optional. **"You may not sell, redistribute, sublicense or give away the source models or modified models as standalone assets, asset packs, templates or downloadable libraries."** Also: "Finished projects must not offer the source assets for extraction or reuse as a product feature." |

86 distinct **static** low-poly factory models, each as GLB *and* FBX: 77 base
(`GLB/01_Belt_Straight_1m.glb` … `77_Pallet_Truck.glb`), 6 in
`Service_Area_Bonus/` (78–83: cable reel, double locker, service sink, tripod
worklight, service trolley, water dispenser) and 3 in `Utilities_Bonus/` (84–86:
coolant pump skid, air treatment skid, welding trolley). Plus
`Factory_Line_Library.blend` and `Factory_Line_Demo.blend` (editable),
`INVENTORY.txt`, `manifest.json` (per-model triangle counts and bounding boxes),
`validation.json`, `OPEN_3D_CATALOG.html` (offline Three.js viewer — MIT, see
`THIRD_PARTY_NOTICES.txt`), preview renders, and the 8-model `Godot_Example/`.

`Factory-Line-Godot86/` is the companion release: the same 86 meshes wrapped as
Godot scenes in `prefabs/` over `models/`, each with a static concave
triangle-mesh collision shape, plus a `generate.gd` that builds them and QA
JSON. Not 86 new meshes — the same ones.

#### What affects integration, from `START_HERE_V1_5_EN_ES.txt`, `LICENSE.txt` and `Godot_Example/README.md`

Read these before using the pack; several of them collide with decisions this
project has already made.

* **The grid is 1 m, ours is 2 m.** The pack's modular cell is 1.000 m in X and
  Y; `docs/DESIGN.md` and the Machine generator use 2 m tiles. Every Factory
  Line module therefore covers a quarter of one of our tiles, and its 2 m and 3 m
  in-line machines are 1×2 and 1×3 of *its* cells, not of ours. Nothing lines up
  by accident; a Belt built from these parts needs the mapping decided
  explicitly.
* **Its own vertical datums**, all measured rather than assumed: carrying surface
  0.900 m, belt width 0.600 m centred, frame seat 0.760 m, one ramp module lifts
  exactly 1.000 m over a 2 m footprint, elevated belt 1.900 m with high-leg seat
  1.760 m, mezzanine deck 1.000 m, bench top 0.900 m, pipe axis 1.500 m,
  overhead services 2.300 m, wall module 2.000 × 2.500 m with the panel plane on
  y = 0, gantry crane 3.000 m clear under the girder and 4.000 m between leg
  lines, roof truss 4.000 m span bearing on its own z = 0.
* **Units are metres, every export is centred on the world origin, GLB uses the
  standard Y-up conversion.** That matches our convention. But ten models have a
  deliberately offset origin — `60_High_Bay_Light` hangs from its fixing plane
  with the fitting *below* the origin, and `58_Roof_Truss_4m` bears on its own
  z = 0 — so "place at the tile centre on the ground" is not universally true
  here, unlike our generated Machines.
* **No animation at all, and the belts do not move.** The readme is explicit:
  "Not included: rigs, animations, moving belt surfaces, colliders, LODs, texture
  atlases, curated UV unwraps, native engine projects, shaders." A moving Belt
  surface is ours to write. The `Factory-Line-Godot86` prefabs add *static*
  concave collision only — "for stationary environments only", explicitly not
  dynamic rigid-body shapes.
* **Materials are embedded flat colours with no external textures.** Nothing to
  relink, and nothing to atlas. This will not match
  `tools/assets/dieselpunk_palette.json` — the pack is clean modern industrial,
  not 1920s-40s dieselpunk — so dropping these in beside our generated Machines
  would read as two art directions. Recolouring is permitted (select a material
  slot, change its base colour) and would be the minimum work needed.
* **Each model is one static mesh of several islands.** Use Blender's Separate By
  Loose Parts to split one.
* **`03_Belt_Curve_90` is a transfer table, not a curved belt** — in on its −X
  face, out on its +Y face, within one cell. There is no curved belt in the pack
  at this radius.
* **`09_Belt_Deck_1m` has no legs**; it is the elevated-run piece, to be placed at
  +1.000 m on top of `10_Belt_Leg_High`.
* **Engine testing is narrow.** The Godot example was tested on Godot 4.6 /
  4.6.3, Windows, Compatibility (OpenGL) renderer; "the other 75 models were not
  runtime-tested there". We are on Godot 4.7.2 with no renderer assumption, so
  any model used has to be verified here. The vendor claims no Unity or Unreal
  test either.
* **Four wall pieces share a module with the vendor's unrelated "Corner Cafe"
  kit** (`45_Wall_Panel_2m`, `46_Roller_Shutter_Door`, `55_Wall_Door_2m`,
  `56_Wall_Window_2m`). Harmless, but it explains the 2.0 × 2.5 m wall module.
* **AI disclosure, which matters for our own provenance records.** The geometry
  is generated by the vendor's Blender Python scripts; no generative-AI image,
  audio, video or 3D generator was used and no third-party model was imported.
  The design decisions, scripts and documentation were produced with AI
  assistance. So the *meshes* are script-authored, same approach as our
  `tools/assets/generate_machines.py`.
* v1.3 fixed two real defects worth knowing about in case an older copy turns up:
  the 17 base materials stored hex colours without sRGB-to-linear conversion so
  everything rendered washed out, and 31 models had parts floating 5 mm–15 cm
  off their supports. v1.5 is post-fix; the geometry is unchanged from v1.4.

**Wired in, sparingly and only past the Map's edge.** Its 1 m module lines up
with nothing we have, and its clean modern palette beside our generated Machines
would read as two art directions — so `tools/assets/convert_props.sh` takes
exactly two of its models, `72_Shipping_Container` and `75_Yard_Light`, as
skyline silhouettes beyond the buildable area, retinted and seen through the
depth fog. Everything nearer the player comes from heyheythere, which is on our
grid.

### `lukami-ch/` — Lukami Ch. "Low Poly Industrial Pack" (60 models)

| | |
|---|---|
| Path | `assets_licensed/lukami-ch/low-poly-industrial-pack-60/` |
| Source zip | `LowPolyIndustrialPack60_Smooth_LukamiCh.zip`, 21 MB |
| On disk | 48 MB |
| Licence | Non-exclusive royalty-free use in unlimited personal and commercial projects; modify, remesh, retexture, rescale freely; sell finished projects. **May not resell, redistribute, sublicense or give away the assets or any subset in any format. May not be used to train, fine-tune, or as input to machine-learning or generative-AI models or datasets. May not be minted as NFTs or registered on any blockchain.** |

60 industrial props plus one `_BUNDLE_Industrial_Pack` containing all of them, in
**two shading styles** — `Faceted/` (flat-shaded classic low-poly; FBX + GLB +
OBJ) and `Smooth/` (auto-smooth, so curves smooth and hard edges stay crisp; FBX
+ GLB). Same models, same UVs, same texture in both. 122 FBX and 122 GLB (61 per
style), 61 OBJ.

Technical facts from its readme: ~1,936 triangles per model, ~116,172 total, one
mesh per model, 1 unit = 1 metre, clean UVs, textures embedded in both FBX and
GLB. **Most models share one texture atlas** (`Textures/palette_atlas.png`) which
is good for draw-call batching; one model carries its own texture. The vendor's
own engine note recommends importing the GLB directly for Godot.

Contents, which overlap our Machine list usefully: Conveyor_Belt,
Conveyor_Incline, Hydraulic_Press, Robot_Arm, Generator, Storage_Silo,
Water_Tank, Hopper_Bin, Air_Compressor, Control_Panel, Electrical_Cabinet,
Welding_Set, Industrial_Fan, Vent_Duct, Pipe_Straight/Elbow/Valve, Large_Valve,
Cable_Tray, Cable_Spool, Catwalk, Guard_Rail, Industrial_Ladder, Steel_Frame,
I_Beam, Pallet_Racking, Storage_Shelf, Pegboard, Workbench, Bench_Vise, Anvil,
Rolling_Toolbox, Hand_Truck, Pallet_Jack, Utility_Cart, Forklift,
Shipping_Container, Dumpster, Wire_Cage, Cylinder_Cage, Drum_Stack, Oil_Drum,
Plastic_Barrel, Gas_Cylinder, Jerry_Can, Bulk_Bag, Sack_Pile, Box_Stack,
Cardboard_Box, Wooden_Crate, Wooden_Pallet, Loaded_Pallet, Stackable_Tote,
Tote_Stack, Floodlight, Pendant_Lamp, Caution_Barrier, Safety_Cone,
Fire_Extinguisher, First_Aid_Box.

**Wired in, sparingly.** `tools/assets/convert_props.sh` takes three:
`Floodlight` — a free-standing mast, which heyheythere has no equivalent of
because its lights are all wall and ceiling fittings — and `Storage_Silo` and
`Water_Tank` as skyline past the Map's edge. The `Smooth/GLB/` set, textures
embedded, nothing to relink.

### `sonniss/` — Sonniss `#GameAudioGDC` Bundle (GDC 2026)

| | |
|---|---|
| Path | `assets_licensed/sonniss/gdc2026-game-audio-bundle/bundle-{1,2,3,4,5}of5/` |
| Source zips | `Sonniss.com-GDC2026-GameAudioBundle{1..5}of5.zip`, 6.5 GB total |
| On disk | **7.5 GB** — by far the largest thing in the quarantine |
| Licence | Royalty-free, worldwide, non-exclusive, perpetual, unlimited projects, no attribution. May not be sold as they come. **NO AI TRAINING OR USAGE** — see the top of this document. `License - GDC Game Audio.pdf` is in every bundle. |

**347 WAV files** across **122 supplier libraries**, each library its own
directory named `<Supplier> - <Library>`:

| Bundle | Libraries | WAV | On disk |
|---|---|---|---|
| 1of5 | 31 | 82 | 1.7 GB |
| 2of5 | 37 | 130 | 1.5 GB |
| 3of5 | 28 | 65 | 1.6 GB |
| 4of5 | 11 | 24 | 2.0 GB |
| 5of5 | 15 | 46 | 897 MB |

Suppliers: 344 Audio, Alexander Kopeikin, CB_Sounddesign, Cinematic Sound
Design, David Dumais Audio, Epic Stock Media, Federico Soler, InMotionAudio, Ivo
Vicic, Jake Fielding, Just Sound Effects, Sonic Bat, Sonik Sound Library,
SoundBits, The Noisery, TheWorkRoom, Victor Ermakov. Each `Readme.txt` notes
that every library here is a sample of that supplier's full commercial
collection, and the tracklist points at the paid versions.

These are long, high-bit-depth source recordings for sound design, not
drop-in game SFX: single files run to hundreds of megabytes. Expect to cut,
pitch, layer and resample and ship the result, not to load a bundle file at
runtime.

Directly relevant to a Dieselpunk factory, by way of example: factory hall
ambiences with alarms and machines, crane onboard rides with squeaks and motors,
industrial machine libraries, colossal impacts, UI and interface element sets,
melee weapons, creature vocalisations, crowd walla, radio chatter. Search the
tree by name — the file names are descriptive and long.

**One thing the bundle does not contain, and it is worth recording so nobody
hunts for it twice: firearms.** There is no gunshot library in GDC 2026. The
weapons' fire is therefore built by layering — a trailer boom for the pressure, a
metal impact for the mechanism, a debris wash for the tail — which is how a gun
is built anyway, but it means there is no single file to go and find.

#### Wired in: which recording is which cue, and why that one

`tools/assets/convert_audio.sh` is the recipe and **the only record of the
mapping**, since none of the files it reads are in git. It writes 37 cues to
`assets_licensed/generated/audio/*.ogg` — about 1.7 MB in total — which is
**gitignored and must stay that way**: a cut from a non-redistributable recording
is a derivative of it and is exactly as forbidden as the WAV.

Two choices recur across the whole set and are the reason the picks look odd
written down:

* **Real mechanisms, not synthesised ones.** The setting is Dieselpunk
  (GLOSSARY.md) — 1920s-40s industry — and a 1930s object recorded closely sounds
  like that era in a way a designed UI click never does. So the Silo's shell
  selector is an **antique telephone's rotary dial** (a wound spring, a detent and
  a return — a thing with stops, which is exactly what the Simulation models), its
  charge counter is a **mechanical counting machine**, and the call-Wave-early
  lever is a **barber's chair foot pump**, which is the heaviest pneumatic throw in
  the bundle.
* **Transposed down rather than time-stretched.** `--semitones` resamples, so a
  cue drops in pitch *and* slows down together. A Boiler is not a motorcycle at a
  lower pitch; it is a bigger thing turning more slowly, and resampling gives both
  at once. That is what turns a Kawasaki's engine start into a boiler catching, a
  barber's foot pump into a lever, and a church bell into the Nest.

The five diegetic controls `docs/DESIGN.md` names, in its order:

| Control | Recording | Why that one |
|---|---|---|
| Silo dial — shell selector | `344 Audio - Antique Telephone` / rotary dial | A thing with stops and a return |
| Silo dial — charge counter | `Epic Stock Media - HD Lock And Mechanism` / counting machine | The one recording in the bundle that *is* a number being wound on. 0.3 s long in total, so the cue is the whole of it |
| Silo commit | `… HD Lock And Mechanism` / deep latch thunk, down a fourth, **layered** with `Federico Soler - Effective Trailer Booms` | The one act a player cannot take back, so it is two cues played together: the latch for the mechanism, the boom for the mass a 0.38 s latch has not got |
| Painting | `InMotionAudio - Arc` / arc power-up, then its buzz as a **loop** | A channel has a beginning and a held layer. It ends on `Cinematic Sound Design - Colossal Impacts` when it lands and on `The Noisery - Rich Glitch` when it does not — the most expensive sound in the game, deliberately ugly |
| Boiler startup | `SoundBits - Motorcycles - Kawasaki` / engine start, down a fifth | Slower, lower, much larger |
| Boiler pressure relief | `344 Audio - Air Designed` / clean blast, down a third | A vent opening under pressure |
| Delivery intake | `Victor Ermakov - Industrial Ambiences` / crane onboard ride | What the Nest does with a Delivery is haul it in. Progression is physical, and this is the sound of it being physical |
| Delivery tier complete | `Ivo Vicic - Church Bells`, down a minor third | The Nest announcing to the whole Map that something new is possible |
| Call-Wave-early lever | `344 Audio - Barbershop` / chair foot pump, down a major sixth | A pneumatic lever thrown by a whole leg |

And the rest, by what it is for:

| Cue group | Recordings |
|---|---|
| Telegraph klaxon | `Victor Ermakov - Industrial Ambiences` / the alarm in the busy factory hall, down a fifth, as a **loop** that runs for exactly as long as the Telegraph does. **Repicked for #35**, whose playtest said the klaxon was "too STUPID": it was `Federico Soler - Effective Trailer Alarms` in quarter notes, which is a designed cinematic sting and fails this table's own standard of real mechanisms. A klaxon has to mean *get to your gun*; a trailer alarm means a film is starting. The in-point has **not been auditioned** — nobody with the bundle has heard the cut |
| Wave arriving, Breach opening | `Jake Fielding - Cinematic Horn Braams`; `Epic Stock Media - Halloween Game` heavy smash, down a fourth |
| Weapon fire (three layers), reload, impact | `Effective Trailer Booms` + `Epic Stock Media - HD Game Materials` metal hit + `Colossal Impacts` debris wash; `HD Lock And Mechanism` spring clatter; `The Noisery - Moaning Metal` geophone thud |
| Melee — the Pneumatic Wrench | `David Dumais Audio - Melee Weapons Pack 2`, swing and metallic body hit |
| Factory ambience, two beds | `Epic Stock Media - Strange Game Ambient Loops 3` machinery roomtone (the quiet one) and `Victor Ermakov - Industrial Ambiences` busy factory hall (the loud one), crossfaded by how much Factory is **working** |
| Machines built, damaged, destroyed; Turret fire | `344 Audio - Extreme Winds` large metal box on a geophone; `Moaning Metal` low scrape; `Epic Stock Media - Anime Game` blast; `344 Audio - Haunting Ambiences Vol 3` metal bangs |
| The Nest taking a hit | `Moaning Metal` bowed screech with a long reverb — the structure itself complaining |
| Enemies, the player | `SoundBits - Vox Bestiae` insectoid tremble-attack, and a longer cut of the same recording a fourth down for the death; `Epic Stock Media - AAA Game Character Police Officer` gasp; `Humanoid Creatures Vol 4` death vocal. **Repicked for #35**: the Crawler's death was `Vox Bestiae`'s *ethereal entity* in grim pain, which is a ghost rather than a thing with a carapace, and the playtest's word for it was "too weird". The same animal at both ends of its life is the fix; the death's cut is **not auditioned** |

Four of the recipe's cues had to have their durations cut to the length of the
source — the counting machine (0.3 s), the light switch (0.26 s), the officer's
gasp (0.46 s) and the latch (0.38 s). The script refuses by name and length
rather than silently truncating, which is how those four were found.

### `heyheythere/` — Low Poly Industrial Facility

| | |
|---|---|
| Path | `assets_licensed/heyheythere/low-poly-industrial-facility/` |
| On disk | 66 MB |
| Vendor | heyheythere, <https://heyheythere.itch.io/low-poly-industrial-facility> (paid) |
| Licence | Use in any number of commercial and non-commercial games, **no attribution required**. "You may not sell, share or redistribute the models, textures or scripts themselves." |

**The most useful pack in the quarantine, and the reason is the grid.** Its
`README.txt` says it in as many words: *"real-world scale (1 unit = 1 metre)"*,
*"everything snaps to a 2 m grid with 4 m storeys"*. `WorldGrid.TILE_SIZE_METRES`
is 2 and `STOREY_HEIGHT_METRES` is 4. Nothing has to be scaled, and a prop placed
at a tile centre is where the pack expects it to be. Contrast Shapita below,
whose 1 m module lines up with nothing we have.

213 props, in four parallel formats plus a native Godot addon:

* `glb/` — 213 `.glb`, 8.9 MB. **This is the set to convert.** Khronos glTF
  Blender I/O output, one material named `props`, attributes
  `POSITION, NORMAL, TEXCOORD_0, COLOR_0` — occlusion is baked into the vertex
  colours and must be multiplied into the albedo. Each file declares two images
  by **relative URI**, `../textures/atlas.png` and `../textures/atlas_glow.png`,
  so a converter has to resolve them relative to the `.glb`'s own directory.
* `fbx/`, `obj/` — the same 213, which we do not use.
* `addons/low_poly_industrial_facility/` — a folder of 213 `.tscn` prop scenes
  over `models/<prop>_model.glb`, plus `props.tres` (a `StandardMaterial3D` over
  the atlas), `machine.gd`, `icons/` and a `demo/gallery.tscn`. **Not an
  `EditorPlugin`** — there is no `plugin.cfg` — and the models in it carry *no*
  `images` array at all, relying on Godot's importer to bind `props` by name on
  first import, which nothing in the addon actually references. So the addon is a
  convenient browser rather than the integration path; `glb/` has the real URIs
  and is what `tools/assets/convert_props.sh` reads.
* `textures/` — `atlas.png` and `atlas_glow.png`, both 2048², plus 24 seamless
  128² tiling sources (floors, walls, roof decking, hazard striping).
* `props.json` — **the picking index**, and the best thing in the pack. Per prop:
  `name, title, group, place, note, tris, size[3], min[3], max[3]`, the part tree
  with pivots, and `anims`. 30 props are animated.
* `icons/` — a 256² PNG per prop. `blender/` — the authoring `.blend`.
* Its own `project.godot` (Godot 4.3, main scene = the gallery), which is why
  Godot skipped this directory even before `assets_licensed/.gdignore` existed.

Datums, from `README.txt`, all of which the set dressing relies on rather than
guessing: a floor or roof piece covers one 2 x 2 m cell with its pivot at the
cell centre on the floor; a wall is 2 m long and 0.25 m thick, centred on a
cell edge, facing **+Z in Godot**; a wall-mounted prop sits 0.125 m off the
wall's line; second-storey pieces go 4 m up at the same points; a workbench top
is 0.9 m. Measured from the GLBs themselves: pipe sections sit at 3.03 m, pipe
racks stand 3.37 m, catwalk supports 3.80 m, high-bay lamps hang from 2.83 m.

The 213 by group: 22 walls, 15 openings, 22 animated machines (conveyor, blast
door, freight lift, roller shutter, fans, levers, valves, breaker boxes, card
readers), 21 storage (crates, drums, totes, racking, pallets, tyres), 20 pipes,
19 access (catwalks, railings, ladders, platforms, stairs), 11 floors, 4 roofs,
11 loading dock, 11 workshop, 9 ducts and cable tray, 9 safety and barriers,
8 vehicles, 6 frame and structure, 5 office, 5 lights, 5 signs, 5 debris,
4 tanks.

**Wired in:** `tools/assets/convert_props.sh` takes about fifty of them for the
yard the Factory stands in — see
[ASSET_PIPELINE.md](ASSET_PIPELINE.md) section 8 and `game/set_dressing.gd`. The
output is `assets_licensed/generated/props/`, which is **gitignored and must stay
that way** for the reason the converted weapons are, and the game runs without
it.

## Total

| Pack | On disk |
|---|---|
| `sonniss/` | 7.5 GB |
| `fps-weapon-pack-unknown-vendor/` | 431 MB |
| `rgsdev/` | 381 MB |
| `shapita/` | 109 MB |
| `heyheythere/` | 66 MB |
| `lukami-ch/` | 48 MB |
| **Total** | **~8.5 GB** |
