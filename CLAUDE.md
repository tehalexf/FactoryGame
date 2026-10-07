# DEEP FOUNDRY — working notes

How to build, run and test this project, and the conventions the code follows.
Design lives in [docs/DESIGN.md](docs/DESIGN.md), vocabulary in
[GLOSSARY.md](GLOSSARY.md), architecture rationale in [docs/adr/](docs/adr/).

## Commands

```bash
tools/assets/run_tests.sh        # asset pipeline: licence guard, FBX conversion, Godot import
tools/assets/generate_machines.sh  # regenerate every Machine mesh from its declaration
tools/assets/convert_weapons.sh  # first-person viewmodels, OUT of the repo; no-op without the packs
tools/assets/convert_audio.sh    # hero sound cues, OUT of the repo; no-op without the bundle
tools/run_tests.sh              # the whole suite, headless. This is the CI command.
tools/run_tests.sh determinism   # only tests whose case.method contains "determinism"
python3 tools/tuning_dashboard.py  # edit content/tuning.toml in a browser, with reset and rollback
tools/tuning/run_tests.sh        # that dashboard's own tests, Python
godot --path .                   # run the game
godot --headless --path . --quit-after 120   # launch headless for 120 frames
```

The tuning dashboard is the usable surface over the ~70 numbers in
`content/tuning.toml`, every one of which is a guess until somebody plays with
it. It writes the file and nothing else — the hot-reload below is what carries
the change into a running Run — validates against the subset
`sim/toml_document.gd` accepts *and* against the game's own loader before it
writes, snapshots before every write, and marks what differs from the shipped
defaults. `python3 tools/tuning_dashboard.py --check` reports the same thing
without a browser.

`tools/run_tests.sh` exits 0 when green and non-zero on any failure, load error,
or an unfiltered run that executed no tests. Set `GODOT=/path/to/godot` to use a
specific binary.

The asset-pipeline suite is separate because it drives Blender and Python rather
than the engine's test runner; see
[docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md). Run
`bash tools/git/install_hooks.sh` once per clone to install its licence guard as
a pre-commit hook — the repository is public and purchased assets must never be
committed.

`tools/run_tests.sh` runs `--import` first on every invocation. That is not optional: `class_name`
globals resolve through `.godot/global_script_class_cache.cfg`, which only an
import pass rebuilds, so a newly added class otherwise fails with a confusing
"Identifier not declared in the current scope".

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Godot | 4.7.2 stable | On `PATH` as `godot`. ADR 0001 originally said 4.6; amended. |
| scons | 4.11.1 | For GDExtension builds. Not needed yet. |
| Blender | 5.2.2 LTS | Art pipeline. glTF 2.0 ships; FBX is intake only. |

GDScript, not C#. C++ via GDExtension only when profiling demands it.

## Layout

```
sim/      the Simulation. Pure GDScript, no Godot node types, no floats.
game/     the Godot layer. Input producers and state readers only.
content/  Machine, Recipe and tuning definitions. Data, not code.
tests/    test runner, TestCase base, and tests/cases/ for the cases themselves.
assets/   committed CC0 and self-authored assets. intake/ holds the source FBX.
tools/    developer scripts. tools/assets/ is the asset pipeline and its tests.
docs/     design, ADRs, asset licensing.
```

Machine meshes are scripted output, not modelled files: `content/` declares the
footprints and ports, `tools/assets/machine_recipes.py` declares the geometry,
and `generate_machines.sh` produces `assets/machines/*.glb`. Change a dimension
by editing the declaration and re-running, never by editing a `.glb`. The grid
facts have one authority each, and the asset suite fails if a mesh and the
Simulation disagree — see [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md)
section 6.

A Machine's **silhouette is a gameplay requirement, not polish**: the core skill
in a factory game is reading your own production line at a glance.
`tools/assets/machine_silhouette.py` measures how far apart every pair of
outlines is and the asset suite fails if any two converge, so changing a recipe
cannot quietly turn two Machines back into the same dark box. The committed
contact sheets in `docs/images/` are the same claim in a picture; rebuild them
with `tools/assets/render_machines.sh`.

`game/world_view.gd` is the only consumer of those `.glb`s, and it flattens each one
once on first use. The generator splits a body into a mesh per material so the glTF can
name a shared material without embedding its textures, which Godot imports as a dozen
`MeshInstance3D`s — the wrong shape to draw fifty of, and a shape a `MultiMesh` cannot
take at all. So a body becomes **one Mesh with a surface per material, cached by id**: a
Machine is one node, a Belt tile is one instance, and fifty Smelters share one buffer.
The port markers carry no mesh and fall out of that flattening by themselves.

Three rules the renderer holds to, each with a test:

- **A body is placed, never measured.** Every body is modelled about the centre of its
  footprint with its feet on the ground, so the renderer moves it to the footprint centre
  at the layer's height and turns it by the Machine's rotation, and that is all.
- **A Machine with no body draws a box.** Adding a row to `content/machines.csv` is never
  blocked on art, so a missing `.glb` is an ordinary state and not a warning.
- **Count decides node or instance.** Machines and the Nest are nodes, pooled. Belt
  tiles, Items and Enemies are `MultiMesh` instances, because those are the three that
  reach the thousands — `test_world_view` asserts the scene tree does not grow by a node
  for any of them.

The lighting is the other half of the art pipeline. The generated surfaces are physically
based and mostly metal, and a metal lit by an ambient *colour* has nothing to reflect, so
it renders as a dark smear whatever its albedo says. `_sync_scenery` therefore takes both
ambient and reflections off the sky, tonemaps filmic, and carries a shadowless cool fill
opposite the sun so the far side of a boiler still reads. The palette was tuned in Blender
renders; those numbers are the second half of that tuning, and they are not
interchangeable.

The split between `sim/` and `game/` is the project's load-bearing boundary, and
it runs one way only: `game/` depends on `sim/`, never the reverse. Nothing in
`sim/` may reference `Node`, the scene tree, or any Godot type whose state is
float-based.

## Sound

**No diegetic control ships silent.** DESIGN.md is explicit about why — IRON
NEST's most-praised quality is its sound design and its most-cited criticism is
that its loop reduces to data entry, and the line between satisfying friction and
tedium is whether the machine answers you. A lever that clunks is a reward; a
silent lever is a chore. Audio is load-bearing here, not polish.

Two files, and the same shape the renderer has:

- `game/audio_director.gd` decides **what** makes a noise, by diffing query
  results against what they said last frame — because a sound is a *change* and a
  query reports a *condition*. It holds no authoritative state, exactly as
  `WorldView` holds none; its snapshot is the same category of thing as
  `TickPump`'s leftover frame time. `cues_for_frame`, `ambience_db` and
  `sustained_cues` need no audio device, so the whole sound design is asserted
  headless in `tests/cases/test_game_audio.gd`; `sync` is the only part that
  touches a player node.
- `game/sound_bank.gd` decides **which file**, and owns the mix. Two sources: the
  hero takes cut from the Sonniss bundle into a gitignored directory outside the
  shipping tree, and the 203 committed CC0 Kenney sounds. **Every cue names both**,
  so a clone without the bundle gets a Kenney lever rather than a silent one.

Three rules, each with a test:

- **Listening changes nothing.** The director reads queries and writes nothing, so
  the same Input Action script leaves the same state hash whether anything was
  listening or not. Sound is presentation; it never reaches the Simulation.
- **Nothing is chosen at random and nothing is timed by a clock.** Variation is
  `tick % count`; the cooldowns that stop a Machine under attack buzzing are
  counted in ticks. Two Runs down the same script sound the same, which is the
  audio half of the rule `WeaponViewmodel` keeps for animation.
- **A cue resolves or it is a load error.** Cue names are constants, the catalogue
  is data, and the asset suite fails if `convert_audio.sh` cuts a cue the game
  never plays.

The recordings are long source material rather than game SFX, so
`tools/assets/convert_audio.sh` is the recipe — which recording becomes which cue
and why — over `tools/assets/wav_to_cue.py`, which measures the in-point rather
than remembering it. See [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md)
section 8.

## The Simulation façade is the only seam

`sim/simulation.gd` exposes exactly three things:

```
step(actions)    advance exactly one tick
hash()           reduce the whole state to one integer
query_*(...)     read-only projections
```

Everything behind it — grid, Belts, Machines, Power, Heat, Waves, Turrets, Silo,
Delivery — is tested *through* those three, never directly. A test that reaches
into a module's internals breaks when the module is refactored and tells you
nothing about whether the game works. The one exception is leaf utility libraries
with contracts of their own — `Fixed`, `DeterministicRng`, `StateHasher`, and the
definition loaders `CsvTable`, `TomlDocument` and `Definitions` — which are tested
directly because their rounding, bit-level behaviour and error messages cannot be
observed any other way. "line 7 of recipes.csv names a rate that is not a number"
is not something `step`, `hash` or a query can tell you.

Queries return copies, never references into state. The Godot layer holds no
authoritative state whatsoever.

## Content definitions

Machines, Recipes and tuning values are **data**, in `content/`:

```
content/machines.csv    one row per Machine
content/recipes.csv     one row per Recipe
content/waves.csv       one row per tier of Wave composition
content/deliveries.csv  one row per tier of Delivery progression
content/gear.csv        one row per weapon frame and per component that fits one
content/stratagems.csv  one row per Stratagem a Silo's Charges pay for
content/tuning.toml     balance numbers that are not per-Machine or per-Recipe
```

**Adding a Machine, a Recipe, an Enemy tier to the Waves, a Delivery tier, a weapon, a
Gear component or a Stratagem is a row. It is never a code change.** There is no
registry, no enum and no Item table — the set of Items is exactly the set the
Recipes mention, interned in sorted order. Every column is documented in the
header comment of the file it belongs to; read that before adding a row.

`content/.gdignore` is load-bearing. Without it Godot's importer claims every
`.csv` in the directory as a translation table, warns on each import, and strips
the rows from an export. These files are read with `FileAccess`, not `load()`.

`Definitions.load_from_directory` returns a set that either loaded or did not:

- Machines, Recipes and Items are **sorted by id**, and tuning keys are sorted
  too, so the index space is a function of the content and not of the order rows
  happen to be written in. Row order, comments and blank lines cannot reach the
  state hash.
- A malformed value is an **error naming the file, the row and the column**.
  There are no defaults anywhere: a typo'd rate does not become 0, a missing
  tuning key does not become 0, a Machine pointing at a Recipe that does not
  exist is not quietly Recipe-less.
- A set with any error at all carries **no definitions**. Half a definition set
  is more dangerous than none, because it looks usable.
- A tuning key nothing reads is a **warning**, because a file carrying a number
  that does nothing lies to whoever is tuning it.

`Definitions.load_from_directory` reads all seven files and `Definitions.parse` takes all
seven sources, in that order. A missing one is an error naming the path, never an empty
table — and `game/definition_watcher.gd` digests all seven, so editing any of them
hot-reloads.

The **order they are read in** is not the order they are listed in, and it is load-bearing:
Recipes first (the Items are interned from them), then Machines, then Gear, then the
**Stratagems** — a `sentry` row has to name a Turret in `machines.csv` — then the Waves, then
the Deliveries, whose three unlock columns each have to name a row in one of the tables above
— and **tuning last**, because `player.starting_weapon` has to name a weapon frame that no
Delivery tier locks, which is a question only the Gear table and the Delivery table together
can answer. Errors are still gathered in *file* order, so the report reads like a list of
things to go and fix.

`sim/csv_table.gd` and `sim/toml_document.gd` are the only parsers. Both are
hand-rolled: Godot ships no TOML parser, and vendoring one into a public repo is
out (`docs/ASSETS.md`). The TOML subset is sections, `key = value`, comments,
integers, decimals, quoted strings, `true`/`false` — and nothing else. Arrays,
inline tables and dates are valid TOML and are refused by name and line number.
If you need another data file, reuse `CsvTable` rather than writing a parser —
`content/waves.csv`, `content/deliveries.csv`, `content/gear.csv` and
`content/stratagems.csv` are four worked examples of doing exactly that, and none of them
cost `CsvTable` a line.

Rates are written in decimal because that is how a human reasons about them, and
cross into fixed point exactly once, through `Fixed.from_decimal_string`, which
floors like every other lossy operation. No float exists at any point.

## Hot-reload

Editing a content file while the game runs applies the change when you save it.

`game/definition_watcher.gd` owns the filesystem and clock half — both are
forbidden inside `sim/`, which is why it lives in `game/` next to `TickPump`. It
detects change by **content digest**, not modification time, so two saves in the
same second are not mistaken for one. `Main` polls it and queues the result.

**The reload is an Input Action**, `InputAction.Kind.RELOAD_DEFINITIONS`, not a
method on the façade. It therefore goes through `step`, is ordered with every
other intent, lands in a recorded script, and replays exactly. The façade is
still three things.

What that buys, and what every later ticket may rely on:

- A reload **changes the state hash** at the tick it is applied. The definition
  digest and a reload generation counter are both hashed.
- A reload is **not undoable**. Reloading the original files does not restore the
  earlier hash, because the Run did change.
- A reload that **failed to load is refused** — so is one with no payload, and
  one whose declared digest disagrees with the set it carries. A refusal leaves
  the definitions and the generation counter untouched and the Run running. A
  typo mid-edit must never take a Run down.
- A `ReplayRecording` carries the **digest of the definitions it was made under**.
  `verify` compares that before it compares a single tick and reports
  `definitions_mismatch` — so a fixture cannot quietly pass against content that
  has since changed, and a content change is never misreported as a tick
  divergence. Leave `definitions` null in a fixture and the replay re-reads
  `content/`, which is what makes that check bite.

In co-op this is the Host's intent broadcast like any other, and the digest is
what lets a client whose own files hash differently refuse instead of desyncing.

## The grid, the Map and Machines

`sim/world_grid.gd` owns what the grid *is*; the Simulation owns what is on it.

- Tiles are `Vector3i` and 2 m across, per `docs/DESIGN.md`. Building is flat, so
  only layer 0 is buildable — that is `VERTICAL_BUILDING_ENABLED` and the layer
  range it governs, in one place, so discrete floors are a flag rather than a
  rewrite. A 4 m storey height is already reserved above the ground.
- A footprint is anchored at a tile and grows along +x and +z. **Its size comes
  from `content/machines.csv` and from nowhere else** — the Simulation, the
  renderer and the Blender mesh generator all read those same two columns, and a
  second copy would drift on the first balance change.
- `sim/map_layout.gd` is the Map's **starting** geography: where the Nodes are, what
  Resource each yields, what Depth tier it sits at, where the Nest stands, where the
  Breaches a Run *opens* with are, and where the Hives stand. Where the Breaches are **now** is Simulation state,
  because deep mining opens more — see the Depth section. Deliberately *not* in `content/` —
  those files are definitions and hot-reloadable, and moving a Node under a
  Factory that is standing on it is a different Map, not a balance change.
- **Nodes never deplete.** There is no quantity on a Node and nothing subtracts
  from one. DESIGN.md decided that: a 40-hour Factory must never need relocating,
  so Depth gates value instead.
- A Miner's input is the ground under it. It produces only while its footprint
  covers a Node whose Resource its Recipe produces, and otherwise accumulates no
  progress at all — a Miner on bare rock is visibly idle rather than invisibly
  banking time.
- A Machine is placed by an Input Action, `InputAction.Kind.BUILD_MACHINE`, which
  carries the Machine's definition *index* because an intent on the wire is
  integers. The Simulation stores the resolved *id*, so a hot-reload that resorts
  the table cannot renumber a Factory that is already standing. A build onto an
  unbuildable tile or an occupied footprint is refused as a silent no-op: a
  misaimed Build Gun is an ordinary thing for a player to do, and the hash does
  not move.
- A Machine does not run on the tick it was built, because it was placed during
  that tick. One craft takes a whole number of ticks, floored from the Recipe's
  seconds, minimum one, and progress is counted in ticks so nothing rounds away
  over a long Run.

## Belts and the Items on them

The most performance-critical system in the project, and the one whose data layout is
hardest to change later. The reference implementations of this genre spend the large
majority of a late-game frame on Belts and their Items, so this is built as integers in
arrays, never as an object per Item.

- **An Item is a position and an id.** Per Belt: one `PackedStringArray` of Item ids and
  one `PackedInt64Array` of positions, ordered front first. There is no Item class, no
  Item instance and — per ADR 0002 — no node: Items are derived state, recomputed
  identically on every client rather than replicated, which is why they cost no
  bandwidth. They are still **hashed**, because "identical everywhere" is worth nothing
  unchecked.
- **Positions are sub-units, not metres.** A sub-unit is sized so an Item advances
  exactly one per tick, so a saturated Belt delivers one Item every
  `ticks_per_item` ticks *exactly*, with no rounding anywhere and nothing emergent from
  frame timing. Metres appear only in `query_belt_item_position_metres`, which divides
  once at the end — that is what keeps a 500-tile Belt's far end at 1000 m rather than
  999.98 m.
- **A Belt's rating is data**: `belt.items_per_second` and `belt.items_per_tile` in
  `content/tuning.toml`. Speed and spacing are *derived* from those two, so there is no
  second number to disagree with them. Pick a rate that divides 60; one that does not is
  floored to whole ticks.
- **Back-pressure is not a special case.** Each Item advances one sub-unit unless the
  Item ahead — or the end of the run — is in the way. A full destination refuses a
  hand-off, the leading Item stops, and the queue packs at its spacing behind it. The
  queue a player sees is literally the state.
- **Belts connect by adjacency, and nothing else.** A Belt's run starts on the tile past
  a Machine's footprint edge (its output port) and ends pointing at another footprint
  edge (an input port) or at the *entry tile* of another Belt. No inserter entity exists
  (DESIGN.md), there is no stored connection to go stale, and side-loading onto the
  middle of a Belt is deliberately not a connection.
- **Open: `content/machine_ports.csv` is still not the Simulation's authority.** #19 added
  that file and the mesh markers that match it, declaring an exact edge and tile for each
  port. The Simulation accepts a Belt against *any* footprint edge tile, which is looser.
  It still cannot adopt the file: the table describes eleven Machine bodies and
  `content/machines.csv` defines ten — #10 added the Ammo Press and the MG Turret and #17
  added the Silo, leaving `press_mk1`, `assembler_mk1` and `generator_mk1` undeclared — so loading it
  under its own documented rule ("machine_id must name a row in machines.csv") would still
  fail the whole content load. The Turret also has no row *there*, so the Belt that feeds
  it docks against any footprint edge for now. The ticket that brings the remaining
  Machines into `machines.csv` should make
  `Definitions` read the ports table and tighten `_load_from_port` and `_hand_off` to the
  declared edge, tile and direction — one declaration, not two.
- **A Belt is not a Machine.** No row in `content/machines.csv`, no Recipe, no `role`.
  GLOSSARY.md keeps the two apart and so does the code; `InputAction.Kind.BUILD_BELT`
  carries two tiles rather than a definition index.

### The update order, and the bias it avoids

Advancing Belts in index order would make a line's throughput depend on the order it was
built in: a Belt advanced before the Belt it feeds sees an occupied entry slot, one
advanced after sees a vacated one. That is a real desync risk and a real gameplay
inconsistency, so index order is not used.

Each tick walks the Belts **downstream first** — a Belt is advanced only after the Belt
it hands Items to. Each Belt feeds at most one other, so the order is found by chasing
each chain to its end and recording it backwards, starting chains in **canonical tile
order** (the tile a run starts at), which is geography rather than history. A Belt loop
has no downstream-most member, so the cycle is cut at its canonically first Belt and that
one join carries a tick of latency. Where two Belts merge, priority goes to the lower
tile, not the earlier build.

The order is derived, so it is rebuilt rather than hashed, and only when a Belt is laid.
`tests/cases/test_belts.gd` asserts the absence of the bias directly, by building the
same Factory in two orders and comparing every Item position tick by tick.

### Machines, ports and starvation

- A crafter's inputs live in an **input buffer** separate from its output buffer, with a
  capacity of `machine.input_buffer_crafts` crafts' worth of each input. That capacity is
  the thing back-pressure pushes against.
- A Machine **banks no progress while starved**. It accumulates ticks only while holding
  a whole Recipe's worth of inputs, and consumes them when the craft completes.
  `query_machine_is_starved` answers the question for both roles — a Miner is starved
  over the wrong ground, a crafter over an incomplete buffer — so the renderer never has
  to infer it from a count that stopped moving.
- A tick runs **Belts before Machines**: an Item delivered this tick is usable this
  tick, and an Item produced this tick is collected on the next, which is the same rule a
  freshly built Machine follows.

## The one Power grid

One grid, no topology. Total supply against total demand, globally — no wires, no
sub-networks, no distance, and nothing in `sim/` that looks like a graph. That is
GLOSSARY.md and DESIGN.md, and it is the whole model.

- **A shortfall throttles every Machine by the same proportion.** Nothing is halted
  and nothing is singled out, which is what makes a brownout read as the Factory
  sagging together rather than as one Machine mysteriously dead. A Belt running out
  of a throttled Miner visibly thins, and that is the gauge a player reads first.
- **The throttle is a duty cycle over whole ticks, not a fraction of one.** Every
  tick the grid banks `min(supply, demand)` kilowatt-ticks and spends `demand` to buy
  the whole Factory one tick of work. On a grid supplying 1 against a demand of 3
  that buys a tick every third tick — exactly a third rate, with the remainder
  carried in an integer rather than thrown away. Over any window a Machine has
  advanced exactly `floor(ticks * supply / demand)` ticks: **one floor, applied once
  to the total, never once per tick.** A fixed-point ratio added up every tick would
  lose up to 2⁻¹⁶ of a tick each time and leave a 40-hour Factory quietly
  under-producing, so there is no fixed point in the mechanism at all.
- **`query_power_ratio` is for the gauge and the Simulation never reads it back.**
  It is the one place Power touches fixed point and it floors, so a third reads as
  0.33332…. Because the throttle is driven by the two integers instead, that rounding
  cannot reach the state hash or move a single Item.
- **Demand counts a Machine only while it would actually work.** A starved Smelter is
  not consuming, so it is not on the grid: cutting a Belt lightens the load rather
  than browning out the Machines that are still fed. `_machine_would_work` is the one
  predicate behind what the grid charges for, what advances, and what a query calls
  starved — three answers that must never disagree.
- **A Machine either feeds the grid or draws from it, never both.** `role=generator`
  supplies `power_supply_kw` and must draw nothing; everything else draws and must
  supply nothing. A Machine drawing nothing is never throttled, which is what stops a
  brownout from throttling the very Boiler that would end it.
- **A generator is a crafter that makes nothing.** Its Recipe is its fuel and its
  burn time, and it has no outputs, because Power is not an Item and never will be —
  there are no fluids and no steam on a Belt (DESIGN.md). Which of `inputs` and
  `outputs` a Recipe must fill therefore depends on the role of the Machine running
  it, so that pairing is checked in `_check_machines_against_recipes` and the error
  names the Machine's row. All three generator classes GLOSSARY.md names — Steam,
  Electric, Exotic — are this one role, differing in fuel chain and failure mode,
  which are rows rather than code.
- **`power.baseline_supply_kw` exists because the Factory would otherwise deadlock.**
  Machines are throttled by the grid, a Steam Boiler burns Belt-delivered coal, and
  coal needs a Miner: a Factory starting on nothing but its own generators could
  never turn the first wheel. The baseline is the Nest's own small plant, tuned to
  exactly one Miner and one Smelter, so the first Machine beyond the opening line is
  the moment Power becomes the player's problem.

## The Nest, the Breaches, the Waves and the Enemies

The threat, and the thing that makes a Run losable. `MapLayout` owns where all of it
is, because it is geography; `content/tuning.toml` owns the numbers, because they are
balance.

- **The Nest is not a Machine.** DESIGN.md lists it alongside Belt and Wall, outside
  the eight Machines: no row in `content/machines.csv`, no Recipe, no Power, and it
  cannot be built or demolished. It is a 4x4 footprint on the Map that obstructs
  building and Belts, with hit points from `nest.health`. **Its destruction ends the
  Run and nothing else does** (GLOSSARY.md).
- **A Run that ended stays ended.** `_run_over_tick` is set on the tick the Nest fell
  and never cleared, so `query_wave_number` freezes at the Wave that did it — which is
  what the Run-over report names — and a later ticket that lets a Nest be repaired
  cannot un-end a Run. Waves stop and Enemies stop; the Factory is deliberately not
  gated, because there is no build mode anywhere in this project.
- **A Breach never moves, and every Breach is known in advance**, which is the whole deal
  GLOSSARY.md strikes: it is fortifiable, and it could not be if it moved. The *set* does
  grow — deep mining opens more, telegraphed first, see the Depth section — but a Breach
  that exists is a Breach that stays where it is. `MapLayout.tile_precedes` is the one
  definition of the order they are held in, and Enemies are released in that order, so which
  Breach goes first is geography rather than the order somebody typed the rows in *or the
  order a player happened to dig in*. A Map with **no** Breach has no Waves at all — which
  is the geography `MapLayout.empty()` gives a test that is studying the Factory and not the
  threat.
- **The Wave schedule is derived from Heat, not counted down.** See the Heat section
  below. `content/waves.csv` owns what a Wave is made of, `[heat]` owns when it comes,
  and `[wave]` owns the three things that are not about Heat — the Telegraph, the spawn
  trickle, and what the lever pays.

### Enemies are array entries, never nodes

Per ADR 0001, and this is the decision the whole Enemy scale target rests on.
Idiomatic engine agents cap out around 150-250 before frame times collapse; instanced
array entries reach thousands. Milestone 1 ships twenty Crawlers **on the final
architecture** so that the Chaff tier switching on later is more array entries rather
than a rewrite. #11 added the Breaker and the claim held: a second kind is a constant in
`sim/enemy_kind.gd`, four tuning keys, a row in `content/waves.csv` and two `match` arms —
no second array, no second loop, and no node. **#16 added the Siege Hulk — a boss — and it held
again**, at the price the note promised: one more `if` in `_enemies`, one function, and the one
piece of state the other kinds do not have (which way it is facing) as **two more parallel
arrays rather than a class**. See the Siege Hulk section.

- An Enemy is an index into parallel `PackedInt64Array`s — serial, kind, position in
  fixed-point metres, health, spawn tick, bite cooldown, and the point it is facing. There is no Enemy class, no
  Enemy instance and no node. `WorldView` draws the whole swarm through one
  `MultiMeshInstance3D`, and `test_world_view` asserts that the scene tree does not
  grow by a single node when a Wave arrives.
- **Index order is ascending spawn serial, always.** Spawns append; `_enemy_serial`
  rises strictly with index. Every loop over Enemies therefore walks them in the one
  order every client agrees on. The purity lint catches a float; it would never catch
  an ordering bug, so `test_enemies` asserts the invariant directly on every tick of a
  Wave.
- A **serial** is issued once and never reused. That is the handle to hold rather than
  an index, because indices shift as Enemies die — which is what a Turret needs to
  keep shooting at the thing it was shooting at.
- Enemies do not collide with one another, by design. A swarm is a swarm, and the
  alternative is an O(n²) separation pass the Chaff tier could not afford. Nothing in
  an Enemy's tick reads another Enemy, so index order carries none of the bias Belts
  have to avoid.
- An Enemy does not act on the tick it came through its Breach, for the reason a
  Machine does not run on the tick it was built.

### Shared flowfields, not a path per agent

DESIGN.md calls this not a close call: rebuilding one field is O(map) once and is then
amortised across every Enemy alive, where per-agent A* is O(agents × path) every time
anything moves — and every Enemy converges on the same destination.

- `_flow_direction` holds a `WorldGrid` direction per ground tile, `_flow_distance` the
  exact tile count to the Nest, both as flat arrays indexed by tile. One breadth-first
  sweep outward from the **whole Nest footprint**, four-connected, so no heuristic is
  involved and an Enemy heading for the Nest's near edge is not routed to its anchor.
- **There are two fields, not one**, since #11: `_machine_flow_*` is the same sweep seeded on
  every Machine's footprint instead, and it is what a Breaker steers by. Two destinations,
  two fields, one `_sweep` and one `_mark_obstructions` pass shared between them — because a
  field is the right structure for the second destination for exactly the reason it was right
  for the first. "Walk at the nearest Machine" is O(Breakers x Machines) every tick and a path
  to re-find every time one falls; a second O(map) sweep is paid only when the obstructions
  move. The seeds are themselves obstructions, so the sweep starts *on* them at distance 0 and
  only the expansion checks for a block, which is how a tile beside a Machine comes to point at
  it while nothing routes through it. An empty Factory leaves that field empty and
  `_enemy_direction` falls the Breaker back onto the Nest's, which is why a Breaker with
  nothing to break is still an Enemy at the gate.
- **Derived, so it is rebuilt rather than hashed**, exactly like `_belt_update_order`.
  It is a pure function of the Map and the obstructions standing on it, both of which
  are hashed. Rebuilt when a Machine is built or demolished or a reload could have
  resized a footprint — never on a tick that changed neither, and never at all while
  no Enemy is on the Map.
- **`_mark_obstructions` is the single definition of what obstructs**, and
  `query_tile_obstructs_enemies` reads what it painted rather than asking the question
  a second way. Machines obstruct; Belts and Nodes do not — a Crawler crawls over a
  conveyor. **Walls joined it in #11, as one more loop** and nothing else, which is what that
  promise was worth.
- It paints by walking the **Machines**, not by asking each of the 16641 tiles what is
  standing on it. That is O(Machines) against O(tiles × Machines), and it is the
  difference between a 2.5 ms rebuild and a 55 ms one — a three-frame hitch every time
  a player places something.
- The sweep walks **flat index space** rather than `Vector3i`, for the same reason:
  `FIELD_STEPS` mirrors `WorldGrid.DIRECTION_STEPS` so the recorded direction still
  means what `direction_step` says it means, and `test_flowfield` walks a 60x60 region
  of the field a tile at a time to prove the two orders agree.
- An Enemy on a tile the field cannot route **because it is standing inside an
  obstruction** — a Machine a player dropped on top of it — walks straight at the Nest
  instead. Without that, pinning a Crawler under a Machine would be a cheese rather than a
  defence. An Enemy on *open* ground with no route is a different case and gets a different
  answer: it chews what is in contact (see Mortality below), because a beeline there would
  send a swarm drifting through solid Walls.
- Measured: 0.10 ms a tick at 20 Enemies and 0.84 ms at 200, against a 16.67 ms frame.

### Open: the Nest's footprint has two authorities

`MapLayout.NEST_FOOTPRINT_TILES` and the `nest` row of `content/machine_bodies.csv`
both say 4x4, and the asset suite's cross-check only covers rows that
`content/machines.csv` declares — which the Nest never will, because it is not a
Machine. The art pass should teach the mesh generator to read the footprint from the
Simulation's constant, the way it reads a Machine's from `machines.csv`.

## Turrets, and the keystone loop

The ticket where the game acquires a point. Production and threat existed separately
before it; a Turret is what joins them, and DESIGN.md's whole thesis rests on it —
**production is combat power, mechanically rather than thematically.**

- **A Turret is a Machine whose output is damage rather than an Item**, and that is the
  entire design. `role=turret` in `content/machines.csv`, a Recipe whose input is
  Ammunition and whose outputs are empty, and `_craft` advances it exactly as it advances
  a Smelter. The only thing the Simulation adds is *what happens instead of depositing an
  output*: `_fire`. **The Steam Boiler is the precedent** — `role=generator` is a crafter
  whose Recipe has no outputs because Power is not an Item, and a Turret is the same trick
  in the other direction because damage is not either. `produces_no_items()` is the one
  predicate both roles share, so the next role whose product is not an Item joins the rule
  rather than forgetting it.
- **There is no combat subsystem, and there is no Turret table.** The target serial and the
  last-shot tick are two more per-Machine arrays indexed exactly like `_machine_progress_ticks`.
  Giving a Turret its own index space is how a Turret stops being a Machine.
- **A Turret with no Ammunition does not fire.** Defence therefore costs *continuous*
  production and there is no build-once-and-walk-away. An empty magazine reads as
  `query_machine_is_starved`, because that is what it is.
- **A Turret with nothing in reach does not work**, so it is not on the Power grid, banks no
  progress and spends no round. That is one more clause in `_machine_would_work`, the single
  predicate behind what the grid bills, what advances and what fires. Deliberately *not*
  starvation: it has its Ammunition, it has no target.
- **A Repair Pylon is the same role with the other column filled in.** `content/machines.csv`
  gained a `repair` column in #11, and the rule the loader enforces is that a Turret carries
  **exactly one of `damage` and `repair`** — its output is damage or it is repair, never both
  and never neither. `MachineDefinition.heals()` is the predicate, `_mend` is what happens
  instead of `_fire`, and `_turret_has_work` is the one clause `_machine_would_work` consults
  for both, so a Pylon over a whole Factory is idle and off the grid by the same rule that
  keeps an MG Turret with nothing in reach off it. Two things make a Pylon's target selection
  different from a Turret's, and both follow from what it is aimed at: it holds **no target at
  all**, because a Machine is an *index* and indices shift the moment anything is destroyed
  where an Enemy serial never does — so `_mend_target` is a pure read, re-decided every tick,
  which is also the right behaviour because there is no reason to finish mending the thing you
  started on rather than the thing nearest death. And it mends **the most damaged thing in
  reach**, measured in hit points missing rather than as a fraction of health, because a
  fraction is a division and a division needs a rounding rule.
- **`range_tiles` and `damage` are columns in `content/machines.csv`**, not tuning, because
  that is what makes a **Cannon Turret a row**: it differs from the MG in those two numbers
  and its Recipe, and neither is named anywhere in `sim/`. `tests/cases/test_turrets.gd`
  adds one to the shipped files and asserts it reaches further, hits harder and spends two
  rounds a shot, with no code change at all.
- **A reach is compared squared.** `Fixed.sqrt` floors, which would put a Crawler exactly on
  the boundary in or out of reach depending on a rounding rule; multiplying both sides
  instead is exact integer arithmetic. The products stay far inside 64 bits — the Map is 129
  tiles across, so the largest squared distance is about 1.4e14 against a 9.2e18 ceiling.
- **A Turret measures from its footprint centre**, so turning a 2x3 Turret does not move the
  circle it covers.

### Target selection, and the one determinism bug this ticket could have shipped

**A Turret holds a serial, never an index.** Enemy indices shift the moment anything dies —
`_remove_enemy` closes the gap — so a Turret holding an index would silently switch targets
on another Turret's kill, and two clients whose kills landed in a different order would
diverge. A serial is issued once and never reused (#9), so it either names the Crawler it
was aimed at or names nothing. `_enemy_of_serial` resolves it with a **binary search**, which
is exact rather than approximate because `_enemy_serial` is strictly ascending with index.

Four rules make the rest of it reproducible:

1. **`_aim` is the only thing that acquires**, once a tick, before the grid is read.
   `_turret_target_index` is a pure read, because `_machine_would_work` consults it and
   `query_machine_is_throttled` consults that — a query that re-aimed a Turret would move
   the state hash by being asked a question.
2. **Acquisition walks Enemies in index order and keeps a strict improvement.** Index order
   is ascending spawn serial by construction, so two Crawlers exactly as far away hand the
   shot to the earlier spawn, on every client.
3. **A Turret keeps a live target in reach**, rather than re-deciding every tick and drifting
   between two Crawlers a metre apart.
4. **A kill removes its Enemy immediately**, inside the same `_craft` loop, and clears that
   serial off every Turret holding it. So a second Turret later in the loop finds its serial
   unresolvable, reports itself idle, and keeps its round for the next tick rather than
   spending it on a corpse — and `query_turret_target_serial` either names something alive or
   names nothing, which is what stops a save restoring the ghost of a Crawler.

### Readable at a distance

An acceptance criterion of its own, and the reason is triage: mid-Wave a player is looking at
the whole Factory from thirty metres and needs to know which Turret is about to stop. So
`WorldView` hangs a **gauge in the world over every Turret** — a dark backing bar at full
width and a coloured fill scaled to the fraction held, green above half and amber below.
Two meshes rather than one because an empty magazine must not be indistinguishable from a
Turret with no gauge: the **backing goes red when the magazine is empty**, so absence of a bar
means there is no Turret there. The bars are unshaded, because a gauge a directional light can
darken is a gauge a player misreads at the worst moment. The HUD says `ammo n/m` and `DRY`
alongside, for the post-mortem rather than the fight.

### Where the balance stands, and what it is waiting for

Measured on the starter Map, shipped content, seed 7. **No Turret:** the first Wave alone takes
the Nest at tick 12,132 — 3 minutes 22 seconds, zero Crawlers killed. **One MG Turret behind
one production chain** (a Miner, a Smelter, an Ammo Press, a coal Miner and a Boiler to pay for
them, joined by six Belts — `_competent_factory` in `tests/cases/test_turrets.gd` builds exactly
this): the Nest falls at tick 130,293, **36 minutes in, on Wave 18, after killing 670 Crawlers**.
Eleven times the Run, and still lost.

**It loses because it runs dry, which is the point.** At the end it had spent 105 seconds with
an empty magazine and the whole Factory was holding 16 rounds. The arithmetic: the Turret fires
four rounds a second and a Crawler takes two of them, so it kills at exactly the two a second
the single Breach releases — while one Ammo Press makes two rounds every three seconds. Each
Wave therefore spends a stockpile the preceding gap built, and since a Wave's count grows by
four and the gap does not, somewhere around Wave 16 the cumulative demand overtakes the
cumulative supply. **The way to survive Wave 20 is a second Ammo Press and the Smelter and
Miner behind it** — production is the defence, in the most literal arithmetic available.

Which a Run can now actually buy: the opening bill of 80 plate pays for the first line and
nothing more, so the second Press comes out of the Nest's store. `test_nest_store.gd` proves
that end to end against the shipped numbers; see the Nest's store, below.

One thing a later ticket should know: **a Machine's output buffer is uncapped**, so a Belt
that fills up banks the surplus in the Ammo Press indefinitely. The stockpile a player
builds between Waves is real and unbounded, and it is what carries the early Waves.

**Open: the two systems have not had a joint balance pass.** #10's arithmetic above was
worked against #9's scaffolded schedule, which grew a Wave's count but never its arrival
rate — so the pressure was Wave *length* against a fixed production rate. #12 replaced that
with a schedule where Heat shortens the gap as well as lengthening the Wave, and where the
Ammo Press and the Smelter behind it are themselves what raise the Heat. The qualitative
claim is unchanged and is the better version of itself — production is still the defence,
and now producing is also what summons the thing you are defending against. But the
crossover Wave number above is a figure from the old schedule, and `fire_mg`,
`make_ammunition`, `range_tiles` and the `[heat]` section want tuning against each other by
somebody playing it. Neither ticket claims that was done.

## Mortality: what can be taken from you

The ticket that makes a Factory's layout a **defensive** decision rather than a logistics one.
Before it a Crawler walked past a Smelter; after it, where the Smelter stands decides whether
it survives the Wave. Three integer arrays carry the whole of it — `_machine_health`,
`_wall_health` and `_player_repair_credit` — in whole hit points with no fixed point anywhere,
which is what makes damage and repair replay identically.

### A destroyed Machine is gone, and nothing comes back

The one decision here worth arguing, and the asymmetry the whole mechanic rests on.
`_refund_machine` hands back a build cost, both buffers and the Items riding a Belt.
`_destroy_machine` hands back **nothing**, and removes the Machine rather than leaving a wreck.

- **A demolition is a player taking their own Factory apart; a destruction is the Enemy taking
  it.** If destruction paid out, a Machine about to fall would be better watched — or
  demolished for the refund — than rescued, and the repair mechanic this ticket is about would
  be strictly worse than doing nothing.
- **There is no player to pay.** A Machine ten tiles from anybody falls with nobody standing
  there, and "the nearest player" is not a rule a lockstep Simulation should want: it would
  make a refund depend on where four people happened to be.
- **The Items in it were real throughput.** A Smelter holding eight plates when it falls is a
  loss a player can feel and attribute, which is exactly what Heat asks of a mechanic.

Removal rather than rubble, for the same reason: a hole in a Factory's wall is a *hole*. The
Belt chain through it breaks because the Machine its run pointed at is not there, the
obstruction is gone so the next field rebuild routes Enemies straight through the gap, and
`test_machine_mortality` asserts both. **You repair the living and rebuild the dead** — repair
cannot touch a Machine that is already gone, and the Build Gun is how one comes back.

### The destruction happens mid-tick, and the fields do not

A Machine destroyed part-way through the Enemy loop invalidates both flowfields — it is one
fewer obstruction and one fewer seed. Rebuilding there would make the tick **O(Enemies x map)**,
which is the quadratic the Chaff tier could never pay, so `_enemies` resolves both fields
**once** for the whole tick and `_destroy_machine` only sets `_flowfield_stale`. The survivors
finish the tick on the field they started it on and inherit the gap on the next one. A tick of
latency on a route is invisible; a 50 ms hitch mid-Wave is not. `_tile_is_blocked` exists as the
half of `_tile_obstructs_enemies` that does *not* force a rebuild, for exactly that reason.

### What an Enemy bites, in three clauses

`_enemy_contact_target` answers it, and the order is the design:

1. **A Breaker takes a Machine over anything else.** That is the whole of what a Breaker is
   (GLOSSARY.md: it preferentially attacks Machines rather than players) and it is what makes
   mortality *felt* rather than merely true — a Crawler walking past a Smelter proves nothing
   about whether the Smelter was ever at risk. It steers by the Factory's field too, so it is
   hunting rather than bumping into things. The sentence was read as "rather than the Nest"
   until #15 gave a player health, and it cost exactly what this note promised: **one more
   clause in `_enemy_contact_target`, ranked below a Machine**, and nothing else changed. A
   Breaker with a Smelter in reach still chews the Smelter with somebody standing next to it,
   which is what makes GLOSSARY.md's sentence literal rather than aspirational.
2. **Either kind bites a player it can reach.** #15's clause, ranked below a Machine and above
   the Nest — so standing in a doorway is a real way to buy the Nest time, at the price of your
   own skin. See the Gear section.
3. **Either kind bites the Nest it is standing at.** A Breaker out of Factory is still an Enemy
   at the gate, and the Nest is still the only loss that ends the Run.
4. **Either kind chews out of a pocket it cannot route out of**, Machines before Walls. Without
   it, sealing a Breach behind a ring of Walls would be a cheese rather than a defence. With it,
   sealing buys exactly as much time as the Walls have hit points — which is what a Wall is for,
   and what `test_sealing_a_breach_buys_time_rather_than_stopping_a_wave` asserts. An Enemy
   standing *inside* an obstruction is excluded and still beelines, which is #9's rule kept.

A Crawler with a route therefore still walks past a Machine untouched. Chaff is the sense of
threat; the Breaker is the threat. One consequence for later Enemy kinds: `_enemy_damage` is one
number per kind whatever it is biting — the Nest, a Machine or a Wall all just have hit points —
so adding an Enemy is four tuning keys and a `match` arm, never a table of multipliers.

### A Wall is not a Machine

DESIGN.md lists it alongside the Nest and the Belt, so: no row in `content/machines.csv`, no
Recipe, no Power, no ports, no buffers. `wall.health` in `content/tuning.toml` is its hit
points, tuning rather than a row for the reason a Belt's rating is.

- **One tile per intent**, unlike a Belt's run. A Belt is a run because Items travel along it
  and the run is the thing; a Wall is a tile because the only question it answers is whether
  *this* tile is walkable, and because a Wall chewed through in the middle of a line has to
  leave the rest of the line standing.
- **A Wall costs nothing to build, and there is deliberately no tuning key for a cost.** A
  build cost names an Item, the Items that exist are exactly the ones the Recipes mention, and
  `machines.csv` is where a cost sits *next to* that check. Naming one in tuning would couple
  the tuning file to the Recipe table from the other side of the content directory, and it
  broke every test that supplies its own Recipes when it was tried. The ticket that gives Belts
  a cost should give Walls one at the same time, in whatever table ends up owning both.
- `WorldView` draws them through **one MultiMesh**, with per-instance colour for health,
  because a Wall is the cheapest thing a player builds and a late-game maze is hundreds of
  them. `test_world_view` asserts the scene tree does not grow by a node for thirty of them.

### Repairing: a wrench costs attention, a Pylon costs material

The two halves of one trade, and they are deliberately priced in different currencies.

- **`InputAction.Kind.REPAIR` is held, not an edge**, and carries a tile. `_repair` consumes
  and clears the intent every tick, so a player who stops sending it stops repairing and the
  per-tick arrays are zero at every point a hash is taken — the same arrangement the walking
  throttle has. Hand repair spends **no materials at all**: what it costs is a player standing
  next to the Machine, in the open, during a Wave, doing nothing else. That is what makes melee
  useful rather than a last resort (DESIGN.md: the Pneumatic Wrench is the melee weapon and it
  is also what repairs). Nothing gates it on a Wave in either direction, exactly as nothing
  gates building.
- **The rate is an integer credit against `TICKS_PER_SECOND`**, carried in
  `_player_repair_credit`, so over any window a Machine has gained exactly
  `floor(ticks * points_per_second / TICKS_PER_SECOND)` — one floor applied to the total, never
  one per tick. #7's lesson, applied again. Credit does not survive letting go or walking out of
  reach, the same rule Power credit and Heat credit obey.
- **Reach is compared squared**, like a Turret's, because `Fixed.sqrt` floors and a player
  exactly on the boundary must not be in or out by a rounding rule.
- **`query_repair_refusal` is a projection about a repair that has not happened**, the same
  arrangement `query_build_refusal` has: the HUD says "out of reach" or "already whole" while
  the player is still walking over, and a refusal leaves the hash alone. `Refusal.OUT_OF_REACH`
  and `Refusal.NOT_DAMAGED` are the two new reasons.
- **A Repair Pylon is a Turret** — see the Turrets section above for the `repair` column, the
  exactly-one-of rule, and why it holds no target.

### Where the mortality balance stands, and what nobody has played

Shipped numbers, not a measured Run: `enemy.breaker_damage` is 60 a second against a Smelter's
500, so a Smelter under one Breaker has nine seconds to live. `wrench.repair_points_per_second`
is 60, so **one player with a wrench exactly holds one Breaker off** — `test_machine_mortality` asserts it, and it is a coincidence of two tuning values
rather than a designed identity. A Repair Pylon pulses 40 a second and spends a plate doing it,
so it loses to a Breaker on its own and beats a Crawler comfortably. **Nobody has played this.**
The joint pass #10 and #12 are both waiting for should take `breaker_*`, `wall.health`,
`wrench.repair_points_per_second` and the Pylon's `repair` column together, because every one of
them is priced against the others. `content/waves.csv` holds the Breaker tier behind 500 Heat,
which means the first few Waves of a Run are unchanged and the Breaker arrives once a Factory is
worth hunting — that threshold is the single number most likely to be wrong.

## Heat, the Wave schedule, the Telegraph and the lever

The mechanic that makes the game a game rather than a sandbox. Without it "infinitely
scaling" is an idle game — more production is self-justifying and costless. With it every
new Machine is a bet, because scaling up is simultaneously how a player gets strong and how
they get hunted (DESIGN.md).

- **Heat is made of completed crafts**, plus a term for the Depth of the Node a Miner is
  working. Deliberately not Power drawn and not Machines running. Heat has to be something
  a player can watch themselves cause, or the Waves read as bad luck and the mechanic
  teaches nothing: a craft is the one event in the Factory that is unambiguously
  throughput, that a player built the Machine in order to get, and that stops the moment
  the line starves. Power drawn would have made Heat a second reading of a gauge that
  already exists and would have charged a slow Recipe with a big draw more than a fast line
  that produces. A count of Machines running would have punished building rather than
  producing, and made a starved line exactly as hot as a fed one.
- **Heat is a whole number of units and there is no fixed point anywhere in it.** This is
  #7's lesson applied to the one quantity that accumulates for forty hours. The
  accumulator has two halves: **in**, a craft adds whole units at a discrete event, so
  there is nothing to round; **out**, the decay is quoted per minute and carried as an
  integer credit against `TICKS_PER_MINUTE`, exactly as the Power grid carries
  kilowatt-ticks. Over any window the Factory has shed exactly
  `floor(ticks * decay_per_minute / TICKS_PER_MINUTE)` — **one floor applied to the total,
  never one per tick.** `test_heat` asserts that with a decay of one unit a minute, which
  is 18 of 65536 in 16.16 fixed point and would lose 1% an hour if it were done that way.
- **The decay is flat, not proportional**, which is a design decision as much as a
  determinism one. A proportional decay is a per-tick ratio — the shape that drifts — and
  it would give the Factory an equilibrium Heat, which is the opposite of the point. Flat
  means Heat measures throughput *in excess of what the Nest can hide*, and that rises
  without bound as the Factory does. `heat.decay_per_minute = 0` is a legal value: a Map
  where Heat only climbs is balance, not a broken file.
- **The interval is derived every tick rather than stored**, so a hot Factory is hunted
  *sooner* and not merely harder — and sooner *now*. `_wave_elapsed_ticks` counts up and
  `_wave_interval_ticks()` is a function of current Heat, so switching a line on pulls the
  countdown towards the player on the tick they switch it on. A stored countdown could only
  ever have shortened the Wave after next, which teaches nothing. It moves both ways: a
  Factory that cools gets its breathing room back, which is what makes tearing a line down
  a real decision.
- **Every Wave passes through a full Telegraph, and that is a gate rather than a
  convention.** `_a_wave_is_due` checks `_telegraph_ticks_served` first and
  unconditionally, so a Wave cannot arrive until the warning has run its tuned length —
  including one a player called, and including one a sudden Heat spike left *overdue*. That
  last case is the hard one and the reason the gate is not a courtesy: Heat shortening the
  interval can put the arrival in the past, and without the gate that would be exactly the
  ambush DESIGN.md forbids. There is no audio yet, so the klaxon is a capitalised HUD line
  with a countdown and a gauge that fills.
- **The lever waives the interval and nothing else.** What it buys the Enemy is nothing at
  all: a Wave is composed from the Heat the Factory is carrying when it *arrives*, so
  calling early means it arrives while that Heat is lower than it would have been. What it
  costs is the breathing room given up. One trade, no second number to tune. It pays
  `wave.call_early_bounty_per_item` out of the same stock the Build Gun spends, in the
  Items `player.starting_stock` names rather than in a count of every Item in the game. That
  changed with #14 for two reasons: the lever buys the means to *defend*, so what it pays is
  build materials; and a bounty paid in every Item would have conjured exactly the goods
  `content/deliveries.csv` asks for, so a player could have bought a Delivery tier off the
  lever without a Factory.
- **A refused pull is a silent no-op whose hash does not move**, and
  `query_call_wave_early_refusal` is a projection about a pull that has not happened — the
  same arrangement `query_build_refusal` has, and for the same reason: the reason is on
  screen before the player commits, which is the only version that leaves the hash alone.
- **Composition is `content/waves.csv`, and a Wave is every tier the Heat has reached** —
  not a choice between them. A hot Factory is sent the Chaff it was always getting *and*
  whatever its Heat has newly unlocked. Each row scales with how far past its threshold the
  Factory is, up to a `max_per_breach` that is a performance ceiling as much as a balance
  one: a Run left to cook for forty hours must not try to put a hundred thousand Enemies on
  the Map. Adding an Enemy to the Waves is a row.
- **`sim/enemy_kind.gd` is the one place a kind's name and its integer meet.** The table
  names kinds in words because a table a designer edits cannot be written in enum ordinals;
  `Simulation.ENEMY_KIND_*` are aliases of those constants rather than a second copy, so
  the file and the code cannot drift. A name no kind answers to is an error naming the row.
- **A Wave is composed once, when it arrives**, and the queue is then fixed. Otherwise a
  player who switched a line off mid-Wave would watch Enemies vanish from the queue.
- **Heat and its contributors are visible or the mechanic collapses into bad luck.**
  `query_heat` is the total; `query_machine_heat_units` is each Machine's lifetime
  contribution, which is hashed state rather than an estimate, and is what a player reads
  off the Machine they built. `query_heat_per_minute` and
  `query_machine_heat_per_minute` are **projections** and the Simulation never reads them
  back — that is where the division lives, in the same sense `query_power_ratio` is where
  Power's does. Power's duty cycle is deliberately not folded into the rate: the Heat line
  says what a Machine's Recipe is worth while it runs and the Power line says how often it
  runs, so each reading stays one fact.
- **A Map with no Breach freezes the whole Wave clock.** Enemies enter at Breaches and
  nowhere else, so a countdown that kept running would report a Wave that is never coming.
  Heat still accumulates, which is what lets a test study Heat without a Wave interrupting.
- **Building is still never gated**, mid-Wave or otherwise, and `test_heat` asserts it
  directly so that nobody adds a flag.

## Depth, and the Breach greed opens

The mechanic that makes growth a *decision about the Map* rather than a decision about a
number. Deeper ore is richer, needs a better Miner, draws more Power and raises more Heat —
all of which a player could read as an upgrade with a price tag. What makes Depth different
is that extracting at it **rearranges the geography they have to defend**: a new Breach opens
near the mine. Reaching for better ore buys ground it did not ask for.

- **A Node's Depth is geography and a Miner's reach is data.** `MapLayout` carries the tier
  each Node sits at; `max_depth` in `content/machines.csv` is the whole of a Miner's tier, so
  `miner_mk2` and `miner_mk3` differ from `miner_mk1` in that column, their draw, their
  Recipe and their build cost — **and in nothing named anywhere in `sim/`**. A Mk4 is a row,
  exactly as a Cannon Turret is.
- **A Miner over ore it cannot reach is starved**, not halted and not throttled. One clause
  in `_machine_has_its_inputs` buys all three consequences at once, because
  `_machine_would_work` is the single predicate behind what the grid bills, what advances and
  what a query calls starved: the Miner draws nothing, banks nothing, and the HUD already
  says why. The same treatment a Miner on bare rock gets, for the same reason — a Machine
  doing nothing must be visibly doing nothing.
- **Power scales with the Machine, not with a flat surcharge.** `depth.draw_percent_per_depth`
  adds that percentage of a Miner's own quoted draw per tier past the first, so the cost of
  depth lands proportionally on a small Mk1 and a big Mk3 alike. Recomputed every tick from
  two integers in `_depth_adjusted_draw_kw` with **one floor applied to the result** — there
  is no accumulator here, so unlike the Power credit and the Heat decay there is nothing to
  drift. `query_machine_power_draw_kw` reports the very figure `_read_the_grid` totals, so a
  deep mine's brownout and the number explaining it are one fact.
- **Heat's Depth term is #12's and there is exactly one of it.** `heat.per_craft_per_depth`
  already charges a craft for the tier it came out of. A second surcharge added here would
  have made the gauge disagree with the arithmetic a player can do in their head, which is
  the entire value of Heat being made of countable crafts. `test_depth` asserts the existing
  term rather than duplicating it.
- **Sustained extraction opens the Breach, counted per Node.** `_node_deep_crafts` counts
  crafts at `depth.breach_tier` or deeper against the *Node*, not the Miner — the hole in the
  ground is what did it, so demolishing the Miner and rebuilding is not a way to reset the
  count, and the Breach is attributable to the mine a player chose to open. One Node opens at
  most **one** Breach ever (`_node_breach_opened`), which is what bounds the mechanic: a
  forty-hour Run cannot ring itself with a hundred holes. The cap being per Node rather than
  per Run is what keeps the *second* deep mine a real decision too.
- **A new Breach is telegraphed before it first spawns, and that is a gate.** It is announced
  into `_pending_breach_*` and only joins the Map once `depth.breach_telegraph_seconds` have
  been served — longer than a Wave's Telegraph, because the answer to a new Breach is a
  Turret and a Belt rather than standing somewhere different. A pending Breach does not spend
  its first tick of warning on the tick it was announced, which is why
  `_pending_breach_announced_tick` is held: the rule is explicit rather than an artefact of
  where `_breaches_open` sits in `step`. `WorldView` marks the tile on the ground in a
  *different* colour and shape from a real Breach — "a hole is about to appear here" and
  "there is a hole here" ask for different things — and the HUD raises a klaxon that names
  the tile, because unlike a Wave the only useful response is to go and look somewhere new.
- **Where it opens is arithmetic, never an RNG draw.** The first valid tile on the ring
  `depth.breach_offset_tiles` out from the Node, walked in canonical tile order, which in
  practice is the ring's north-west corner. Predictable twice over: a Breach is only
  fortifiable if a player can plan for it, and geography that consumed an RNG draw would make
  *which* Breach you got depend on how many draws the Run had spent. The ring widens by up to
  `RING_SEARCH_WIDENING` if every tile is taken, and a Map with nowhere to put one simply
  does not get one — that is geography, not an error.
- **The flowfield is not rebuilt, and that is the point rather than an omission.** The field
  is a pure function of the Map's ground and the Machines on it; a Breach is neither, because
  it does not obstruct and is not a destination. Every ground tile already has a direction and
  a distance, so the tile a new Breach opens on is already routed and an Enemy out of it
  steers by the same shared field. `_breaches_open` therefore never touches
  `_flowfield_stale`, and `test_depth` asserts that every tile sampled routes exactly as it
  did before the opening.

### The determinism trap, and where the line between Map and Simulation sits

`MapLayout` sorts Breaches into tile order and `_release_from_the_breaches` walks them in
index order, so Enemy release order — and therefore which serial belongs to which Crawler —
is geography. **Appending a runtime Breach would quietly change that to "the order a player
dug in"**, and two clients whose Miners completed a craft in a different order would then
disagree about which Crawler is which. `_insert_breach` is the only way anything joins that
array and it inserts at the position `MapLayout.tile_precedes` names, so the invariant holds
by construction. `test_depth` asserts the array is still ascending afterwards, and that
digging two mines in the opposite order produces the same Map — both of those fail if the
insert is changed to an append.

The line between the two owners is drawn at *starting* versus *live*:

- **`MapLayout` owns the opening geography and the canonical order.** It is authored, it is
  not hot-reloadable, and it is identical for every Run on this Map. It gained a static
  `tile_precedes` — the single definition of tile order, now used by Node sorting, Breach
  sorting and the Simulation's insert, so there is one comparator rather than three.
- **The Simulation owns the live Breach set and everything that produced it.**
  `_breach_tile_*` was already copied out of `MapLayout` and hashed (#9 made it an array
  deliberately), so no state *moved* — what changed is that the array is no longer constant
  through a Run. `_node_deep_crafts`, `_node_breach_opened` and the five `_pending_breach_*`
  arrays joined it. All of them are hashed; none of them needed a line in `sim/run_save.gd`,
  which reflects over the property list.

## The player, the Build Gun and Survey View

A player is 1.8 m against 2 m tiles, and every single thing they do crosses into the
Simulation as an Input Action. The controller holds no authoritative state.

- **Position, facing, velocity and the camera are Simulation state**, in fixed point.
  `game/` asks `query_player_*` where to put the camera; it never decides. Yaw is in
  **turns**, not radians — radians need PI and PI is a float — and `Fixed.sin_turns` /
  `cos_turns` read a 65-sample quarter-wave table, exact at the quadrant boundaries and
  within `Fixed.SIN_TOLERANCE` everywhere else.
- **`MOVE` is a throttle in the player's own frame**: forward and strafe, which the
  Simulation rotates by the yaw it is holding. There is therefore no second copy of the
  facing angle for the controller to rotate WASD by. Intent is **per tick**; sending no
  `MOVE` is how a player stands still, so an idle tick is a tick spent slowing down.
- **`LOOK` carries pixels, not an angle.** The sensitivity that turns pixels into a turn
  is tuning the Simulation owns, exactly as it owns the walking speed, so a client cannot
  turn faster by sending a bigger number.
- **Walking has acceleration**, so a person has weight. Velocity is state and is hashed.
  See "Weight" below for what #29 made of that, which is most of it.
- **Survey View is held, not toggled**, and its transition is counted in ticks *inside*
  the Simulation, eased on the way out with `Fixed.smoothstep_fixed`. That is a decision
  about feel rather than about determinism: its height, duration and tilt are
  hot-reloadable tuning, and the only way to find out whether a lift feels good is to try
  several. **It is not a mode** — nothing consults it to decide whether an intent is
  allowed, and a player can walk and build while surveying.
- **Building is never gated.** There is **no check anywhere in the Simulation that asks
  whether building is currently permitted** (GLOSSARY.md: the Build Gun is available at all
  times, including mid-Wave). #29 added a `_player_build_mode` flag and did not weaken that
  sentence by one word — see "Build mode is a hand, not a gate" below, and note that no
  refusal, no build path and no `_fight` reads it.

### Weight: jumping, the four accelerations and the camera's response

#29's half of the player, and it came out of a play session rather than a spec. The
complaint, in the player's own words, was that movement felt like *"Minecraft creative
mode"* where it wanted to feel like survival mode, with Satisfactory as the reference —
and that there was no jump at all.

**The deliverable is the tunability as much as the motion.** Twenty-two keys went into
`[player]` and every one of them is expected to be wrong, because nobody can pick a feel
number without playing. Read the section comments in `content/tuning.toml` before changing
any of them; they say what raising each one does.

- **Jumping is Simulation state.** `_player_y` and `_player_velocity_y` in fixed-point
  metres, hashed, replaying. `player.jump_height_metres` is what is tuned and the impulse
  is *derived* from it with one `Fixed.sqrt` — a tuner thinks in how high they clear, and
  it means raising gravity makes a jump heavier rather than quietly making it too short to
  clear a Belt. **`JUMP` is held**, like `MOVE` and `FIRE`, and the *absence* of the intent
  is what re-arms it: `player.jump_repeats_while_held` is false, so holding the key through
  a landing does not bounce, and `_player_jump_armed` is the hashed fact that makes a jump
  a press.
- **There is no collision against anything but the ground**, and that is the honest limit
  of what shipped. A player jumping beside a Smelter passes through where its roof would
  be. Building is still flat (DESIGN.md), so this is a height above layer 0 and nothing
  else; standing on your own Factory is a different ticket from making movement feel like
  weight.
- **There are four accelerations, not one, and that is the central change.** Ground start
  (24 m/s²), ground stop (9), air start (6), air stop (1.5) — plus a fifth case, the
  landing settle, which takes `land_settle_acceleration_percent` of the ground figures away
  for `land_settle_seconds`. **A single figure for starting and stopping is the commonest
  cause of a first-person game feeling weightless**, because a body leans into a start and
  *slides* into a stop, and an instantaneous halt on key release is the loudest
  creative-mode tell there is. `_horizontal_acceleration` is the one function that decides
  which applies, from two facts: on the ground or not, asking to move or not.
- **The air-control decision is "nearer stiff", written as two small numbers rather than as
  a fraction.** Full air control feels floaty and arcade; none at all makes a jump
  unaimable. At 6 against the ground's 24 a jump commits you to roughly the trajectory you
  left on and gives you a quarter of the authority to argue with it, and the air
  deceleration of 1.5 means letting go in mid-air barely slows you — momentum is what a
  jump is made of. Set `air_acceleration_metres_per_second_squared = 0` for a ballistic
  jump.
- **Sprint is a gait, not a multiplier.** `_player_sprint_ticks` is one ramp, counted in
  ticks exactly as the Survey View lift is, and it drives the speed, the field of view and
  the bob *together* — which is what makes starting to run read as a change of gear.
- **Sprint is a toggle or a hold, and that choice is `game/player_controller.gd`'s.** The
  Simulation keeps knowing only whether a player *is* sprinting, which is the fact the
  movement code needs; `player.sprint_is_toggle` is read by the controller, which in toggle
  mode flips its own latch on the key's rising edge and sends the result. A replay
  reproduces either reading identically because what crossed the boundary is the intent and
  not the keypress. The latch is the same category of thing as the mouse buffer — a reading
  on its way in — and it is **cleared whenever the Simulation says the player is not on
  their feet**, so you respawn walking and the latch cannot drift from the flag.
  `sprint_is_toggle` is the one key in `tuning.toml` that is a *control preference* rather
  than a balance number; it is there because the project has no settings menu, and it is
  the key that moves out of content alongside `look_sensitivity_turns_per_1000_pixels` when
  one arrives.
- **The camera's response is in the Simulation and out of the aim**, which is the one
  genuinely arguable decision here and it went the way Survey View's transition already
  went. `_player_step_phase` is hashed state driven by **distance travelled rather than by a
  clock**, so a slow walk bobs slowly and a standing player does not bob at all; the
  landing dip hangs off `_player_landing_tick` and is scaled by the impact speed, so
  stepping off a kerb barely registers; the lean needs no state at all, because the
  sideways component of a velocity that is already hashed is exactly the quantity a body
  leans against. All five come out as their own `query_player_view_*` /
  `query_player_field_of_view_degrees` projections that **only the renderer reads** — folding
  a bob into `query_player_camera_height_metres` would mean a footfall moved where a round
  went and which tile the Build Gun was hovering. Contrast the recoil kick, which *is* in
  that query precisely because it does move the aim.
- **The jump is in the aim and the bob is not**, and that is the same split from the other
  side: how high a player is standing is a fact about the world, so `_player_y` is in
  `query_player_camera_height_metres` *and* in `_shot_target`'s eye height. A jumping player
  really is shooting down at the swarm.
- **The shipped camera values are deliberately barely perceptible**, on the player's own
  instruction — "only tiny minor bob please". 1.2 cm of vertical bob, 3.5 cm of landing dip,
  half a degree of roll at a walk: the kind of thing you notice when it is switched off
  rather than when it is on. Every one of them takes **0 as off**, which `Definitions`
  allows by name, because this is the easiest thing in the game to overdo into motion
  sickness and somebody prone to it is entitled to turn the lot off.

### Build mode is a hand, not a gate

`B` holsters the Build Gun and draws the weapon, or the other way round. **Left click
places in build mode and fires in combat mode**, which is what #15's note said the real
answer was — it put the trigger on left mouse and shoved placing onto `E`, which its own
author called ugly. `E` is gone and `B`'s old job, laying a Belt, moved to `C`, where it
is only read with the Build Gun out, because routing a Belt is a build act. `C` collided
with #17's Silo charge counter, which moved to `K` — "Where the controls went" has the
whole map.

**It is not a mode in the gating sense, and the criterion is written as the absence of
code.** Grep `_player_build_mode` and the only callers are its three queries. Not one
refusal consults it, `_apply_build_machine` has never heard of it, and neither has
`_fight` — so a player holding a rifle builds exactly as well as one holding the Build Gun,
and `test_movement_weight` asserts that directly so nobody adds a flag. What the mode
decides is **which Input Action `game/player_controller.gd` produces from one button** and
which object `WorldView` draws in the player's hands. Switching is instant, unlimited, and
works mid-Wave, mid-burst and in Survey View.

- **It is Simulation state anyway**, for three reasons that have nothing to do with
  permission: what somebody is holding is a fact about them in the same way their wallet
  is, a recorded replay has to reproduce a swap or every click after it means something
  different, and in co-op what the other three are holding is worth drawing.
- **`SET_BUILD_MODE` carries the resulting mode, not a flip.** A recorded script therefore
  describes what the player ended up holding without being replayed to find out, and two
  intents in one tick cannot cancel out. The controller reads the mode out of
  `query_player_is_in_build_mode` and sends the opposite — the arrangement the Machine wheel
  and the Gear slot ring already have.
- **Asking for the mode you are already in is a no-op whose hash does not move**, so
  leaning on the key does not restart the animation sixty times a second.
- **The mode flips on the tick the key is pressed and the model lags**, and **the lag is
  the renderer's, not the Simulation's.** #29 shipped `query_player_holster_blend` and
  `query_player_held_is_build_gun` before #28 landed, and they answer exactly the question
  `WeaponAnimator` answers from the clip lengths of the model on screen — so the renderer
  reads the mode and `WeaponViewmodel` plays the `holster`, swaps the model and plays the
  `draw`. The two queries stay here because `test_movement_weight.gd` pins them and they are
  the authoritative answer for anything that is not this renderer, but nothing in `game/`
  reads them. `player.holster_seconds` is likewise still tuning the Simulation holds and no
  longer what the swap you see is timed by. See "The weapon in frame", below.
- **The primary button is read both ways every tick.** `sample_devices` cannot know which
  mode anybody is in, so it samples the *edge* (one click is one Machine) and the *held
  state* (a trigger is not a click) and `actions_for_tick` picks. A player who presses `B`
  and clicks in the same tick gets the act of the mode they are swapping *to*, which is the
  rule that already makes a scroll-and-click place what the player scrolled to.

### Refusals are a query, not state

A refused build stays a **silent no-op whose hash does not move** — a misaimed Build Gun is
an ordinary thing for a player to do. The *reason* is therefore a pure projection:
`query_build_refusal(player, machine, tile, rotation)` answers about a placement that has
not happened, and the hologram asks it every frame about the tile it is hovering over. The
reason is on screen **before** the click rather than after it, which is both better UX and
the only version that leaves the hash alone. `_apply_build_machine` consults the same
function, so what a player is told and what the Simulation does are one rule and not two.
The wording lives in `game/build_gun.gd`, because a `Refusal` is a fact and a sentence
about it is presentation.

### Materials

`content/machines.csv` has a `build_cost` column in the same `item:count` form a Recipe's
inputs use; empty means free. Building spends it out of the player's own stock and
demolishing returns it **in full**, along with whatever the Machine was holding and the
Items riding a demolished Belt. Nothing is destroyed, so demolish-and-rebuild is not a way
to make Items disappear, and iterating on a layout costs only the ticks it takes (issue #1,
user story 7).

**Destruction is the exact opposite and that asymmetry is the point** — see Mortality below.
A Machine an Enemy chewed down returns nothing at all.

Where the stock comes from is `player.starting_stock`: an explicit `item:count` bill rather
than the count-of-everything scaffold it replaced. It is granted once at construction, so
raising it mid-Run is not a way to conjure materials. The shipped value is
`"iron_plate:80"` — the whole competent Factory costs 78 — so **a Run opens with the opening
line and two plates over**, and everything past that is unlocked at the Nest.

A tuning key rather than a per-Item key, and a quoted string rather than a table, because
naming an Item in `sim/` is the one thing this project does not do: the set of Items is
whatever the Recipes mention, and a key called `starting_iron_plate` would be a second Item
table. It is parsed by the same `item:count` function a Recipe's inputs and a Machine's
`build_cost` go through, so there is one answer to what well-formed means.

**What refills a player's pockets is the Nest's store**, which is the symmetric half of the
opening bill and the thing that makes the Run a loop rather than a one-way spend. Build
materials used to go only outwards — into Machines, back only from a demolish or the
call-early bounty — so nothing the Factory produced could reach the Build Gun and a Run could
not fund a *second* Ammo Press out of its own output, which is exactly what the balance note
above says you need. See the Nest's store, below.

**Open: the store is not yet what arms a player.** #15 made firing spend **Ammunition** out
of these same pockets, and `player.starting_stock` is deliberately still plate alone — so a
Run opens able to build its line and swing a wrench and unable to fire a shot. The faucet
exists now; what has not been done is the pass that checks a Run can actually keep a magazine
full out of it, which is a balance question and wants somebody playing it. See the Gear
section.

### Rotation

`WorldGrid.rotated_footprint` swaps a footprint's extents without moving its anchor, so a
2x3 Machine turned a quarter covers 3x2 tiles from the same origin. One convention, shared
by placement validation and the renderer. Rotation is per-Machine state and is hashed; a
turned Machine covers different ground and presents its ports to different tiles.

## Delivery progression at the Nest

Where a Run gets better at anything. Progression is **physical**: goods carried or
Belt-fed to the Nest unlock the next tier of Machines, Gear components and Stratagems, and
there is no research menu and no science resource (GLOSSARY.md, DESIGN.md). That makes the
Nest both the thing you defend and the place you progress, so one location carries the
Run's whole meaning.

- **The tiers are `content/deliveries.csv`**, and adding one is a row. The table has
  **no numeric column at all**, which is how "unlocks are Machines, Gear components and
  Stratagems, never stat increases" is enforced: there is nowhere to write "+10% mining
  speed" even if somebody wanted to. `test_delivery` asserts the consequence directly —
  completing a tier leaves `query_definition_digest` exactly where it was, so no number the
  Run is playing by moved.
- **A Machine is locked because a tier names it.** There is no `locked` column in
  `content/machines.csv`: the Machines a Run opens with are exactly the ones no tier's
  `unlocks_machines` mentions. One authority, so moving a Machine between tiers is an edit
  to one file. The keystone loop is deliberately *not* behind the chain — a game that made a
  player earn the right to defend themselves before the first Wave would be a different
  game — so what the shipped chain sells is **Depth**: `t02_deep_mining` unlocks Miner Mk2
  and `t03_deep_survey`, which only a Mk2 working the Depth 2 seam can reach, unlocks Mk3.
  Each tier pays for the tool that opens the gate on the tier after it, and the deep seam is
  the one that opens new Breaches (#13) — so the chain is also what talks a player into being
  hunted from a second direction.
- **Locked content is a refusal, not a second gate.** `Refusal.CONTENT_IS_LOCKED` comes out
  of `_build_refusal`, before the ground and before the wallet, because being locked is a
  fact about the Machine rather than about the tile. A locked Machine may still be put on
  the Build Gun: the hologram asks that one function every frame, so the reason is on screen
  before the click — which is both better UX and the only version that leaves the hash
  alone.
- **The chain is walked in id order and nothing is skipped.** The next Delivery is the first
  tier this Run has not completed. A tier whose Depth the Factory has not reached *blocks*
  the chain rather than being passed over, which is the whole of "Depth gates what is
  possible to deliver". `Definitions` refuses a file whose `min_depth` goes backwards down
  the chain, because such a tier could never be the thing holding the chain up.
- **Depth is derived from the Factory, never stored.** `query_depth_reached` is the deepest
  Node a Miner is *actually working*, and it asks through `_miner_reaches` and
  `_recipe_yields` — the same predicates `_machine_has_its_inputs` asks — so the Delivery
  gate and the extraction rule cannot disagree about what a Factory is mining. A Miner Mk1
  parked on a Depth 3 Node is starved, and it has reached Depth nothing. The gate therefore
  measures something a player can argue with, and it falls again when that Miner comes down.
- **Goods reach the counter two ways and settle in one place.** A Belt whose far end points
  into the Nest's footprint hands Items to the open Delivery; a player standing within
  `nest.delivery_reach_metres` of that footprint hands over what they are carrying, clamped
  to the bill. Both go through `_accept_delivery`, and `_deliveries()` — one tick phase,
  straight after `_transport` — is the only thing that completes a tier. A tier that
  completed on one path and not the other would be two rules.
- **Goods past the bill are banked rather than refused, and nothing is destroyed.** The open
  tier takes what it is still waiting for and the Nest's store takes the rest, up to its cap;
  past that an Item is refused and the Belt **backs up where a player can see it**, exactly
  as it does against a full input buffer. `_nest_accepts` is the one way anything enters the
  Nest, and it pays the bill before the store — a store that swallowed ore the open tier was
  waiting on would quietly stall the chain a player is trying to finish. See the Nest's
  store, below.
- **Everything about the next Delivery is a query, and the HUD reads all of it.** Which
  tier, what it wants, how much has arrived, the Depth it is gated at, and
  `query_delivery_refusal` — a projection about a hand-over that has not happened, the same
  arrangement `query_build_refusal` and `query_call_wave_early_refusal` have. A player
  aiming a Factory at a goal they cannot read is guessing.
- **Unlock state is resolved ids, sorted, and hashed.** `_completed_delivery_ids`,
  `_unlocked_machine_ids`, `_unlocked_gear_ids`, `_unlocked_stratagem_ids` and the part-paid
  counter. Ids rather than indices for the reason `_machine_id` holds an id: a hot-reload
  that resorts the Delivery table, or inserts a tier ahead of the one already earned, must
  not renumber what a Run has earned. Sorted, so iteration order is a property of what was
  unlocked rather than of the order it was earned in. `RunSave` persists all five without
  being told, because it reflects over the Simulation's properties.
- **A fixture that is not about progression replaces the chain rather than walking it.**
  Several suites build the deeper Miners or fill a Factory out of a player's pockets, and
  neither the chain nor the opening bill is what they assert — so they substitute a tier that
  locks nothing and a stock that pays for anything (`DELIVERIES` / `STOCKED` in
  `test_depth`, `test_turrets`, `test_world_view`, `test_heat`, `test_enemies`,
  `test_nest`). `test_delivery.gd` is the one place the shipped chain itself is asserted.
- **All three unlock columns are read, and all three name a real row.** #15 made
  `_unlocked_gear_ids` the gate on what a player may fit to their weapon frame and #17 made
  `_unlocked_stratagem_ids` the gate on what a Silo may be loaded with, each through its own
  `Definitions.locks_*` — exactly the arrangement `unlocks_machines` already had, and the
  reason there is no `locked` column in `gear.csv` or `stratagems.csv` either. So the table has
  no identifiers in it that nothing reads, and the half that could not have been retrofitted —
  recording, hashing and saving what a Run has earned from the day it earns it — was already
  there when the mechanics arrived to consult it.

## Gear, first-person combat, and what dying costs

The other half of the keystone loop. #10 proved that production is combat power through a
Turret; this is the same claim in the player's own hands — **you fight with what your
Factory made** — and it is the project's highest-risk pillar, because code is the easy
half. First-person combat lives or dies on animation and feel, which no test can assert.
So the mechanism is built to be *tuned by playing*: every number that decides how a weapon
feels is a row in `content/gear.csv` or a key in `[gear]`, and editing either applies to the
Run you are standing in.

### One frame, interchangeable components, and no tiers

- **`content/gear.csv` is the whole of it, and nothing in `sim/` names a weapon, a
  component or a slot.** A fourth weapon is a row, exactly as a Cannon Turret was —
  `test_gear.gd` adds a Rivet Cannon to the shipped table and shoots a Breaker dead with
  it, with no code change at all.
- **The slot a component occupies is its own `kind`, and the set of slots is exactly the
  set of kinds the table mentions** other than the reserved `weapon`. That is the Items'
  arrangement — the set of Items is exactly what the Recipes mention, and there is no Item
  table — and it buys the same thing: a fourth slot is a row. The shipped table names four
  (barrel, magazine, sight, plating), interned in sorted order, and that order is hashed
  because it is the index space a `FIT_COMPONENT` intent travels in.
- **A weapon row carries no modifiers and a component row carries nothing else.** The
  loader refuses either mistake by name, which is how "power comes from combination rather
  than from tiers" survives contact with a designer: there is nowhere to write a Rifle Mk2
  even if somebody wanted to. A component whose six modifiers are all zero is refused too
  — a Delivery a player paid for and cannot feel is worse than no tier at all.
- **Modifiers are whole percentages, summed once and applied with one floor.** Additive
  rather than multiplicative so two components can be reasoned about in either order, so
  nothing rounds at each link, and so the order they were fitted in cannot reach the state
  hash. `_scaled` is the one function, and it works unchanged on a count of hit points and
  on a fixed-point count of metres.
- **A piece of Gear is locked because a Delivery tier names it**, exactly as a Machine is.
  There is no `locked` column in `gear.csv` and there will not be one: the Gear a Run opens
  with is exactly the Gear no tier mentions. So all three weapons are open from tick 0 — a
  game that made a player deliver goods before it let them hold a wrench would be a
  different game — and every component is earned, which is the pillar's whole point: **a
  build goal translates into a Factory goal.**
- **What a player is holding is an id, and what is fitted is a sorted array of ids.**
  Indices would renumber under a hot-reload; `_player_component_ids` is the same shape a
  player's pockets are, for the same two reasons.

### Firing, and where the aim comes from

- **No aim crosses the float boundary for a shot, and that is the strongest version of the
  rule rather than an omission.** `InputAction.Kind.FIRE` carries nothing at all. A
  player's yaw and pitch are already authoritative fixed-point Simulation state, put there
  by the quantised `LOOK` intent (#6), so where a round goes is something the Simulation
  knows exactly; a tile or a direction in the intent would be a *second* opinion about the
  aim, derived from a float, and in lockstep the second opinion is the one that diverges.
- **What did gain a crossing is the hand tool's aim**, and it went where every crossing
  goes: `InputQuantiser.aimed_tile_at_height`. `aimed_tile` is the Build Gun's and only
  ever meets the *ground*, because building is flat and a hologram snaps to a floor tile. A
  wrench is held against a Machine's body several metres up, so aiming it down the ground
  plane means looking at your own feet to mend something at eye level. Same three rules —
  floors toward negative infinity, bounded by reach, NAN reduced rather than cast — and its
  own tests in `test_input_quantiser.gd`.
- **`FIRE` is held, like `REPAIR` and `MOVE`.** Automatic fire is the absence of letting go
  rather than a second intent, and `_fight` consumes and clears the flag every tick, so it
  is zero at every point a hash is taken. One intent for all three weapons, because there
  is one frame: whether it swings or shoots is the `attack` column.
- **Combat resolution is integer arithmetic, all of it.** An Enemy is a point (#9), so a
  round is resolved against a capsule standing on it — `gear.enemy_hit_radius_metres`
  across, `gear.enemy_hit_height_metres` tall — with three tests in the order that rejects
  most cheaply: distance along the line of aim (a dot product), distance off it (a cross
  product), then the height the round is at by then (eye height plus the tangent of the
  pitch). The third is what makes aiming up and down mean something rather than firing a
  vertical plane of lead. Walked in Enemy index order on a **strict** improvement, so two
  Enemies exactly as far away hand the hit to the earlier spawn on every client — the rule
  a Turret's acquisition already obeys.
- **Two RNG draws every shot, hit or miss.** The stream is a function of how many times the
  trigger was pulled rather than of what happened to be standing there, which is what keeps
  a replay identical when a Crawler dies a tick earlier on one client than another. Melee
  consumes none: a swing catches the nearest living Enemy in front of the player inside the
  weapon's reach, because a swing is a sweep and not a ray.
- **A shot leaves from eye height, never from the camera.** Survey View lifts the camera to
  twenty-six metres and is explicitly not a mode, so a player who raises it to read their
  Factory must not thereby be firing from a helicopter.
- **Recoil is Simulation state because it moves where the next round goes.** A kick the
  renderer applied on its own would be a lie about aiming, and the pitch it adds to is
  authoritative already. `query_player_camera_pitch_turns` includes it, so the view and the
  aim are one number. The recovery is **proportional to what is left** — the one place in
  this project where that is the right shape, because recoil converges on *zero* and so has
  nowhere to drift, where Heat and the Power credit accumulate for forty hours and would. A
  flat recovery was tried first and is unusable: a weapon firing eight times a second adds
  eight kicks and a flat rate sheds two, so the view climbs without bound and a held trigger
  ends up pointed at the sky.
- **Firing spends Ammunition out of the player's own pockets** — the same pockets the Build
  Gun spends from. That is the first-person half of the keystone loop, and
  `query_fire_refusal` is the projection that lets the HUD read `DRY` off the weapon rather
  than off a count a player has to do themselves.

### Downed, dead, and back at the Nest

- **A player has health now**, which is what #11 said was missing: it could only read
  GLOSSARY.md's "a Breaker prefers Machines rather than players" as "rather than the Nest".
  `_enemy_contact_target` gained exactly one clause and nothing else — ranked **below a
  Machine**, so a Breaker with a Smelter in reach still chews the Smelter with somebody
  standing next to it, and **above the Nest**, so putting yourself in a doorway buys the
  Nest time at the only price this game charges: your own skin.
- **A player is reached by distance and not by tile contact**, unlike everything else an
  Enemy bites. The Nest, a Machine and a Wall stand on tiles; a player is a position in
  fixed-point metres, and asking which tile they are on would make a bite land or miss
  depending on which side of a boundary they happened to be, which is not something a
  player could read off the screen.
- **Solo play has no Downed state** (GLOSSARY.md), and that is the whole of the rule: there
  is nobody to revive you, so a Downed state on a one-player Run would be a pause with no
  counterplay. A solo player dies outright and waits out `player.respawn_delay_seconds`.
- **`_player_life_state` and `_player_life_since_tick` are the whole clock.** The tick a
  state began rather than a countdown, so how long somebody has been bleeding out is
  arithmetic over two numbers that are hashed anyway — no second counter to keep in step,
  and the "does not act on the tick it arrived" rule falls out for free: a player Downed
  this tick has been Downed for zero ticks. `_lives()` runs **last** in the tick, after
  `_enemies()`, because `_enemies` is what put them down.
- **Reviving is hand repair pointed at a person**, down to the arithmetic: an integer credit
  against the revive's own length, one floor applied to the total, and credit that does not
  survive letting go or walking out of reach. What it costs the rescuer is what a wrench
  costs — standing still, in the open, during a Wave, doing nothing else.
- **Death costs tempo and nothing else** (GLOSSARY.md, DESIGN.md), and the criterion is
  written as the *absence* of code: `_respawn` touches position, health and the clock. Not
  a plate, not a round, not a Delivery, not the components on the frame. There is nowhere
  in that function for a death penalty to be added without somebody arguing for it first.
- **Being Downed is a refusal, not a mode.** `_player_can_act` is consulted by every
  refusal a player's intent goes through, so `Refusal.PLAYER_IS_DOWN` comes out of the same
  function that does the refusing and the HUD gets the real reason. Nothing anywhere asks
  whether acting is *currently permitted* — it asks whether this player is on their feet,
  which is a fact about them in the same way their wallet is. Building is still never gated.

### Where the controls went, and the one that had to move

- **Left mouse places with the Build Gun out and fires with the weapon out.** #15 put the
  trigger here and moved placing to `E`, called that binding unhappy and temporary, and said
  the real answer was a hand — a holster that puts either the Build Gun or a weapon in front
  of the player. #29 built it: `B` is the holster, `E` is gone, and the Belt moved from `B`
  to `C`. See "Build mode is a hand, not a gate" in the player section.
- **Two keys moved when #29 and #17 met, and one of them was a bug being fixed.** #29 took
  `C` for the Belt and #17 had already taken it for the Silo's charge counter; the Belt
  stays, because `X` `C` `V` `B` — demolish, Belt, Wall, holster — is the build cluster and
  pulling a key out of the middle of it is the worse trade, so `KEY_SILO_CHARGES` moved to
  `K`, next to `KEY_LOAD_SILO` (`L`), which is the pairing that actually gets used: wind
  the count, then load. Separately, `T` was bound to **both** revive and withdraw from the
  moment #27 landed — press it next to a Downed teammate and you did both — and #29
  retiring `E` left the right key free: `KEY_WITHDRAW` is now `E`, beside `KEY_DELIVER`
  (`F`), which is the same act in the opposite direction.
- **The whole map, and no key appears twice.** `W` `A` `S` `D` walk, Shift sprints, Space
  jumps, `Q` is Survey View, `B` holsters, `C` Belt, `V` Wall, `X` demolish, `R` wrench,
  `T` revive, `E` withdraw, `F` deliver, `G` calls the Wave, `Z` and `K` wind the Silo dial,
  `L` loads it, `P` paints, `1`–`3` weapons, `4`–`7` component slots, F5/F9 save and load.
- `KEY_JUMP` is **Space**, held.
- `KEY_1`–`KEY_3` are the weapon frames, in the sorted order the table interns them, so a
  fourth weapon becomes the fourth key without `player_controller.gd` changing. `KEY_4`
  onwards are the slots, each cycling the components that fit it with "nothing fitted" as
  one more position in the ring. The cycle holds no state: where it is comes out of
  `query_player_component` and what is in it comes out of the definition set.
- `KEY_REVIVE` (T) is held, like the wrench, and does nothing on a solo Run.

### The weapon in frame, and where it comes from

`game/weapon_viewmodel.gd` is the whole of it: the purchased first-person arms, their
weapon, and the clip that is playing on them, parented to the camera so the model and the
aim climb together. **Everything it moves by is read out of the Simulation** — the velocity,
the kick, the tick a shot fired on, the rounds left in the player's pockets — and the clip's
*time* is computed from the tick count and seeked explicitly rather than left to the
engine's clock, so what is on screen is a function of Simulation state and a replay looks
the same twice.

**The models are loaded at runtime from outside the repository, and are usually absent.**
The packs forbid redistribution and this repo is public, so a converted `.glb` is exactly as
forbidden as the FBX it came from (`docs/ASSETS.md`). `tools/assets/convert_weapons.sh`
writes one per weapon into a gitignored directory and `WeaponViewmodel` draws two
placeholder boxes for any weapon it does not find there. **A clone without the packs builds,
tests green and plays**, which is the rule, and `test_weapon_viewmodel.gd` asserts it rather
than trusting it. The conversion, and the four things about those FBX that bite, are
`docs/ASSET_PIPELINE.md` section 7.

- **`WeaponAnimator` is the state machine and it is a `RefCounted` with no nodes.** It takes
  a `Facts` — every field of which is a `query_*` — and returns a `Cue`: which role should be
  playing, how far into it, whether it loops, and **which weapon's model belongs on screen**.
  No assets, no scene tree, so every transition a player will ever see is a cheap assertion
  rather than something only a screenshot could catch. Clip lengths are *told* to it by
  whoever loaded the model, and anything it is not told falls back to `DEFAULT_SECONDS` — so
  absence of the packs changes what is **drawn** and not what **happens**.
- **A role is what the game asks for; a clip name is what a pack happens to call it.**
  `Shoot` against `Knife_Attack_1_Anim`, `PutAway` against `Holster`. `CLIP_NEEDLES` is the
  whole of the translation, resolved once when a model loads, and a weapon whose model lacks
  a take simply never plays that role — which is how the Bolt Rifle works a bolt and the
  Drum Autocannon does not.
- **A weapon change is two clips with a model swap between them**, and the holster belongs to
  the weapon *going away*. `Cue.weapon` lags `query_player_weapon` for exactly as long as the
  stow takes, because you cannot holster a rifle that has already been swapped for an
  autocannon. Neither clip can be fired through.
- **The bolt and the pump are only played by a weapon that has room for them.** A `Chamber`
  or `Pump` take runs after the shot clip and only when `query_player_weapon_interval_ticks`
  leaves time for both — otherwise the model would visibly cycle slower than the Simulation
  lets the player shoot. The Bolt Rifle's 48 ticks has room; the Autocannon's 7 does not.
- **A reload is not invented, because the Simulation has none.** A round leaves the player's
  pockets the tick the trigger goes, and the one moment that *is* a reload is the one a query
  can see: `query_player_shots_remaining` rising off zero — a player who was dry and now is
  not. A player who banks a second round while holding one has not reloaded, and a melee
  weapon has no magazine at all.
- **The trigger beats a reload outright**, which is what the Shotgun's
  `Reload_Start` / `reload` / `Reload_End` split is for: break out of the loop, shoot, and
  close the action afterwards rather than resuming it. A pack that ships one `reload` take
  plays one clip and the same code does both.
- **One model per weapon, built once.** A change hides one and shows another; the scene tree
  does not grow as a Run goes on, which is the rule every other thing in `WorldView` obeys.
- **The thing in a player's hands is an id, and nothing here knows it is a weapon.**
  `WeaponViewmodel.held_facts` and `show_held` are one struct and one call: change
  `Facts.weapon` to any id, hand it back, and the holster, the model swap and the draw
  happen by themselves — `draw` and `holster` are first-class roles here rather than a
  special case, because `Draw` and `PutAway` are first-class takes in the packs.
- **The Build Gun goes through that seam, and that is the whole of #29's holster in the
  renderer.** `WorldView._sync_weapon` reads `query_player_is_in_build_mode` and, when it is
  true, sets `Facts.weapon` to `BUILD_GUN_HELD_ID` with no reach and no magazine. Three
  lines. #29 landed before #28 and had built it as a second `Node3D` — its own meshes, its
  own sway, its own drop out of frame driven by `query_player_holster_blend` — and that is
  gone, because two answers to "what is in frame" is one too many. **The Simulation still
  owns which mode you are in**: `_player_build_mode` and `_player_mode_since_tick` are
  hashed, so a replay reproduces a swap and in co-op what the other three are holding is
  drawable. What it no longer owns is the *shape* of the swap, which `WeaponAnimator` was
  already timing off the clip lengths of the model actually on screen.
  `query_player_holster_blend` and `query_player_held_is_build_gun` stay in the Simulation —
  `test_movement_weight.gd` pins them, and they are the authoritative answer for anything
  that is not this renderer — but nothing in `game/` reads them any more.
- **A Build Gun model arrives the same way an arm does.** It is named `build_gun` in the
  gear directory, so the day somebody models one it loads, resolves its clips and draws
  without `world_view.gd` changing. Until then it is the same two placeholder boxes every
  unconverted weapon gets, sized stubby by a reach of zero — which is a real loss against
  what #29 shipped: its placeholder Build Gun had a flared nozzle and an emissive rail in
  the hologram's own colour, so the silhouette read as a tool rather than a gun at a glance,
  and that distinction is the point of a holster. **Modelling a Build Gun is the ticket that
  gets it back**, and it is art rather than code.

What is still placeholder-grade is the *surface*: the packs reference textures they do not
ship, so the arms and the weapons are repainted from `dieselpunk_palette.json` rather than
textured. Recovering the real maps is a nicer-looking ticket of its own.

### Where the balance stands, and what nobody has played

Shipped numbers, not a measured Run. The Bolt Rifle kills a 30 hp Crawler in one shot and a
240 hp Breaker in six, one round a shot, 0.8 s between them, 0.4° of scatter. The Drum
Autocannon needs three shots for a Crawler and twenty for a Breaker but puts out eight
shots a second at two rounds each — so it empties a magazine sixteen times faster for a
little over twice the damage, and 5° of scatter plus the recoil bloom means a long burst
sprays where a tapped one does not. The Pneumatic Wrench kills a Crawler in one swing at
0.6 s and cannot touch a Breaker before the Breaker touches it.

A player has 150 hit points against a Crawler's 10 a bite and a Breaker's 60 — fifteen
seconds of standing in Chaff, three bites from the thing that actually hunts you, which is
the same sentence DESIGN.md writes about Machines. Hardened Plating takes 30% off that.

**The Ammunition chain closes, and `test_gear.gd` walks every link of it.**
`player.starting_stock` is deliberately still plate alone — putting rounds in it would conjure
exactly the thing the keystone loop says the Factory must make — so a Run opens with a rifle
that is a stick.
`test_a_player_can_take_the_ammunition_the_factory_made_and_fire_it` builds a Miner, a
Smelter and an Ammo Press out of the opening eighty plates, runs a Belt into the Nest, waits
for the counter to bank a round, withdraws it (#27) and kills a Crawler with it. That is the
pillar's whole sentence as one test.

**What has not been done is the balance of it.** Nobody has checked a Run can keep a magazine
*full* that way against a Wave schedule that is simultaneously eating a Turret's rounds out of
the same Ammo Press — and the arithmetic in the Turrets section says one Press cannot even
feed the Turret. The honest reading is that a player who wants to shoot needs a second
production line, which is the right answer and an untested one. Until somebody plays it, the
Bolt Rifle and the Drum Autocannon are *tested* rather than *played*, and the rest of
`test_gear.gd` arms its own player because a test about what a weapon does should not have to
build a Factory first.

**Nobody has played any of this.** The joint balance pass #10, #12 and #11 are all waiting
for should now take `gear.csv`, `[gear]`, `player.health`, `enemy.player_bite_reach_metres`
and the Ammo Press's rate together, because every one of them is priced against the others.
The two numbers most likely to be wrong are `gear.view_kick_degrees_per_shot` — the whole
feel of automatic fire rides on it — and `gear.enemy_hit_radius_metres`, which decides
whether a swarm at twenty metres is a target or a lottery.

## The Siege Hulk, the Hives, and the sortie

The ticket that makes the first-person pillar justify itself. Everything else in this game is
solved by building; **a Siege Hulk cannot be**, and that is the whole reason it exists. If
killing one is not fun, that is the most important thing this project can learn, so the
mechanism is built to be *tuned by playing*: every number that decides how the fight feels is a
key in `[siege_hulk]` or `[hive]`, and editing either applies to the Run you are standing in.

### A boss is one more array entry

The claim ADR 0001's whole Enemy scale target rests on, tested again and held again. A Siege
Hulk is an entry in the same parallel arrays as a Crawler: a constant in `sim/enemy_kind.gd`, a
name in `KIND_NAMES`, a row in `content/waves.csv`, four `match` arms beside the Crawler's and
the Breaker's, and **one `if` in `_enemies`** that sends it to `_siege_hulk` instead of the
bite-and-walk path. No class, no second index space, no combat subsystem.

What it needed that no other kind does is **which way it is facing**, and that is *two more
parallel arrays* (`_enemy_face_x` / `_enemy_face_z`) rather than a class — the shape this file
has promised since #9. Held for every Enemy, including the ones it means nothing to, because a
parallel array is parallel.

- **A facing is a point, not an angle**, and that is the decision worth recording. An angle
  needs an arc-tangent, which fixed point does not have and which would mean a second table
  beside `Fixed.sin_turns`. A point reduces the weak-point test to **the sign of one dot
  product**: the hit came from behind exactly when the gap to the shooter points away from the
  gap to what the Hulk is facing. No normalisation, no rounding rule, no trigonometry, nothing
  for two clients to disagree about. `WorldView` turns it into a yaw with an `atan2`, which is
  `game/`'s business and a float it is allowed.
- **A Hive is deliberately *not* an Enemy entry.** It is a structure with hit points, so it is
  its own parallel arrays — the Enemy's half of the arrangement the Nest and the Walls already
  have on the players' side. Making it an Enemy was the other candidate and it is wrong twice
  over: it would put something that never moves through a movement loop and a flowfield on
  every tick of every Run, and it would make `query_enemy_count` — the number the HUD draws as
  "the swarm" and every Enemy test asserts on — permanently two higher on the shipped Map than
  the Wave that is actually arriving. A Hulk *is* an Enemy: it walks, it hunts and it dies. A
  Hive is furniture with hit points.

### Does it move? It arrives, holds, and backs off from Turrets

`_siege_hulk` is four clauses and the order is the design:

1. **A player at its feet is answered first, and a stomp spends the shell's cooldown.** One
   counter for both actions, so **a player standing there is a player whose Factory is not being
   shelled.** Closing the distance pays off from the first second rather than only at the end,
   which is the same trade standing in a doorway makes against a Crawler, at the same price.
2. **A Turret that could reach it makes it back off.** `_withdraw_enemy` is the only thing in
   the file that walks an Enemy *against* a field. This is "it cannot be defeated by Turrets
   alone" as behaviour: push a Turret line out and it withdraws and goes on shelling.
3. **Nothing in shelling reach means walk**, by the Crawlers' shared field — one more consumer
   of a field that is already built rather than a third sweep.
4. **Otherwise hold and bombard.**

So it is neither a chase nor a statue. A chase across a Map at 1 m/s would be tedium; a thing
that spawned already in position would have no legible arrival. It walks in, halts, and shells —
and `test_siege_hulk.gd` asserts it is still standing in the same place twenty seconds later.

**Where it halts is `siege_hulk.range_metres` and there is no second number.** It stops the
moment anything it can shell is inside its own reach, so the stand-off *is* the reach. And
`Definitions._check_siege_hulk_outranges_every_turret` refuses a content set in which any
Turret's `range_tiles` covers that distance — so **"it bombards from beyond Turret range" is a
property the content cannot be edited out of.** Adding a Cannon Turret that outranged the boss
is now an error naming the row rather than a quietly solvable boss. That check is why tuning is
read *last*, after `machines.csv`: it is exactly the cross-table question that ordering exists
for.

### A weak point, not a sponge

The decision this ticket turned on. **A damage sponge is a timer**: more hit points only ever
ask a player to hold the trigger for longer, and the answer to the boss would have been "bring
more Ammunition" rather than "move". So the front shrugs off `siege_hulk.frontal_armour_percent`
of a hit and the back does not, and a Hulk faces what it is shelling — which means flanking it
means going round **while it is busy with the Factory**. That is the decision this whole ticket
exists to put in front of a player, and it is made of movement rather than of inventory.

- `_armoured` is the one place it is applied, and **a Turret's round goes through it too**, from
  where the Turret stands. One rule, so a Hulk cannot be shrugging off a rifle and soaking an MG
  round in the same tick.
- A hit from exactly abreast counts as **behind**, generously and on purpose: the armour is the
  thing a player has to discover, and a boundary that punished a flank that was not quite far
  enough round would teach the wrong lesson.
- **Nothing tells the player where the weak point is.** The HUD says `ARMOURED FRONT 85%` and
  stops there; what carries the answer is the geometry — `WorldView` draws the hull in cast iron
  and an **unshaded glowing vent on the back**, offset along the Hulk's own facing. A player who
  empties half a magazine into the glacis and then walks round is the player that vent is for.
  This is the only place in the project where geometry carries a rule, and a HUD line naming the
  answer would spend the discovery.
- Per-kind hit volumes arrived with it: `_enemy_hit_radius` / `_enemy_hit_height`, because
  `gear.enemy_hit_*` is tuned for a low scuttling Crawler and a player who could miss four
  metres of armour by a metre would read the gun as broken.

### The bombardment, and why a shell is in the air

- **Targeting is deterministic and reads no unordered collection.** Machines in index order on a
  strict improvement in squared distance, then the Nest as one more candidate taken only on a
  strict improvement — so a Machine and the Nest at the same distance hand the shell to the
  Machine. The Factory is what a bombardment is for; the Nest is what is left when there is no
  Factory.
- **A shell takes `siege_hulk.shell_flight_seconds` to arrive, and that is the Telegraph rule
  rather than a flourish.** Nothing in this project may arrive unannounced (DESIGN.md), so the
  impact point is on the ground with a countdown for three seconds before anything happens
  there — long enough to walk out of six metres. `_shells()` runs *before* `_enemies()` so a
  shell fired this tick cannot land this tick, which is the same rule a Machine built this tick
  obeys.
- **A shell kills a player who stands in the marker**, at the same `shell_damage` it does a
  Smelter. That is deliberate: a telegraphed, avoidable, lethal thing is a mechanic, and death
  costs tempo and nothing else (GLOSSARY.md), so the punishment is affordable and the lesson is
  cheap.
- The blast is walked **from the highest index down** over Machines and Walls, because
  `_damage_machine` may destroy one and `_remove_machine` closes the gap. The damage is
  independent per target, so the direction cannot change the outcome — descending is what keeps
  the indices valid while it happens.
- `WorldView` draws the marker as a ring of ground scaled to `query_shell_blast_radius_metres`
  and brightening with `query_shell_ticks_remaining`, so **what a player dodges is literally
  where the damage will be** rather than an approximation of it.

### A Hive raises Heat; it does not open a second Breach

The other design question, and the answer is "raise Heat, not spawn", for a reason that is about
a promise rather than about cost. **GLOSSARY.md says Enemies enter at Breaches, which are "known
in advance and fortifiable".** A Hive that emitted its own Enemies would be a second entry point
nobody can fortify, and it would quietly take that promise back. So a Hive's pressure is routed
through the Breaches that already exist, by making the Factory louder than it is.

And it **subtracts from `heat.decay_per_minute` rather than adding to Heat**, which is the half
worth arguing about:

- Adding would hunt an idle Run for standing still, and DESIGN.md is explicit that Heat is
  throughput *in excess of what the Nest can hide* — a Factory producing nothing has nothing to
  hide and is owed its silence. `test_siege_hulk.gd` asserts exactly that: two minutes on a Map
  with a Hive and a Map without, both at Heat 0.
- Subtracting says the Nest hides **less** while these things are watching. So a Hive taxes
  *growth*: every craft counts for more while one stands, which is the same sentence pointed the
  right way.
- `_heat_decay_per_minute()` is the whole of the mechanic — one subtraction, derived every tick
  from the live set, nothing stored and nothing to adjust when a Hive dies. A Hive takes **no
  tick of its own**.
- And it lands on a gauge a player already reads. `query_heat_decay_per_minute` is on the HUD;
  killing a Hive moves it up, for ever, visibly. `query_hive_heat_shadow_per_minute` is the same
  fact stated as a bill, for the sortie panel.

**A destroyed Hive never comes back**, and that is structural rather than promised: nothing in
`sim/simulation.gd` appends to the Hive arrays after construction. Where they stand is geography
(`MapLayout`, sorted into canonical tile order like the Breaches); what is left of them is
Simulation state, because that is the half a Run changes.

**A Turret cannot touch a Hive, and that closes the obvious cheese by construction rather than
by a rule.** A Turret acquires *Enemies*; a Hive is a structure. So a player who runs a
fifty-tile Belt out to a Hive has built a Turret with nothing to shoot, and "requires leaving
the Factory" survives the most determined attempt to build its way out of it.

### What leaving costs, and making it visible first

The honest answer is that the cost is **diffuse**, and it is diffuse on purpose: this project
refuses to charge progress or resources for anything (GLOSSARY.md: death costs tempo, never
progress). What a sortie actually costs is the wrench you are not holding, the Machine you are
not rebuilding, the Wave clock that keeps running, and the shells that keep landing while you
walk. The work this ticket did was to make all of it **readable before the commitment** rather
than discovered on the way back — the arrangement every refusal in this file already has:

- `query_hive_heat_shadow_per_minute` — what the Hives are costing, per minute, right now.
- `query_player_metres_from_the_nest` — how far from a wrench you are, growing as you walk.
- `query_machines_damaged` — how much of the Factory is already hurt.
- plus `query_ticks_until_next_wave`, which was already there.

All four are projections the Simulation never reads back, so the panel cannot change the Run it
describes, and `test_the_bill_for_leaving_is_readable_before_the_player_commits` asserts the hash
does not move when it is asked. `WorldView._sortie_lines` puts them on screen the whole time
there is something out there worth leaving for.

**This is the weakest part of the ticket and it is worth saying so.** A visible bill is not the
same as a felt cost, and nobody has played it. The honest test is whether a player hesitates
before walking out; if they do not, the lever to reach for is `hive.heat_shadow_per_minute` and
`siege_hulk.shell_interval_seconds`, not a death penalty.

### Where the balance stands, and what nobody has played

Shipped numbers, not a measured Run.

- 1800 hit points against the Drum Autocannon's 96 damage a second is about **nineteen seconds
  of flanked, sustained fire** — and over two minutes through the frontal armour, which is the
  number that says "stop shooting it in the face" without a line of UI saying so. Roughly 270
  rounds out of the Factory either way, which is the pillar's whole point.
- The Bolt Rifle's 60 m reach is *exactly* the stand-off, deliberately: a player who will not
  leave the Nest **can** plink at it through its armour, for about five minutes of perfect fire.
  The sortie is strongly incentivised rather than enforced.
- 45 a stomp against a player's 150 is three stomps and a bit, and a 220-point shell kills
  outright.
- **The two Hives on the shipped Map changed the measured baseline, and the numbers in the
  Turrets section above are from before them.** `hive.heat_shadow_per_minute` was tried at 100
  first and that was wrong: it left the Nest hiding 40 a minute of 240, pushed #10's documented
  competent Factory past `waves.csv`'s 500-Heat Breaker threshold on its *first* Wave, and cost
  it five of its six Machines. At 30 the same Factory's first Wave lands at tick 7919 rather than
  8217 and is sent eight Crawlers rather than seven — pressure added to the measurement rather
  than thrown over it. It is still the number on this ticket most likely to be wrong.
- **Nobody has played any of this.** The joint pass #10, #11, #12 and #15 are all waiting for
  now also owes `[siege_hulk]`, `[hive]` and the Hulk's 1200-Heat row in `content/waves.csv` a
  look, because every one of them is priced against the others. The two most likely to be wrong
  after the Hive shadow are `siege_hulk.shell_interval_seconds` — the whole rhythm of the fight
  rides on it — and `siege_hulk.frontal_armour_percent`, which decides whether the weak point
  reads as a discovery or as a broken gun.

### Does the fight have a shape?

On paper, yes, and the shape is: *the shelling starts, you cannot answer it, you walk out, you
learn the front is wrong, you go round, and while you are round the back the Factory is quiet
because you are standing on its toes.* Three decisions in it that are not "hold the trigger" —
when to leave, which side to be on, and whether to melee it to buy the Nest time. That is more
shape than a sponge would have had.

What no test can tell us is whether the walk out there is dead time and whether the flank reads
as clever or as fiddly. Those are the two things to look for the first time somebody plays it.

## The Nest's store, and the faucet it is

Where Factory output becomes something a player can spend again. Progression put the Nest at
the centre of a Run; this is what makes it also the bank, so one location carries banking,
spending and the thing you defend.

- **A Belt into the Nest pays the open bill first and banks the rest.** `_nest_accepts` is
  the one way goods enter the Nest and `_nest_would_accept` is its pure twin, which is what
  lets `_hand_off_blocked` report a Belt backed up against a Nest with no bill and no room.
  Two paths into one function, for the reason `_accept_delivery` already was one: a surplus
  that banked off a Belt but not out of a hand would be two rules.
- **The store is capped, at `nest.store_capacity_per_item`, and that was the decision.** An
  unbounded store is simpler and it is wrong three times over. It is an infinite sink, so a
  Belt pointed at the Nest can always hand off and **never backs up** — and back-pressure is
  the one mechanism this game has for showing a player that a line is overproducing, at
  exactly the place they are looking. It removes any reason to stop hoarding and build the
  thing the materials are for, where a bounded one gives a late Factory's surplus somewhere to
  *go*. And it is a number in `hash()` and in the save file with no bound on it at all.
  Bounded, a full store refuses the hand-off and the Belt packs up, which is the rule a full
  input buffer already obeys rather than a new one — so "nothing is destroyed" keeps its teeth.
- **Per Item, not one pot.** One shared total would let a Belt of coal crowd plate out of the
  store: a cross-Item interaction nobody tuned, and one whose outcome depended on which Belt
  happened to arrive first. One number applied to each Item independently also names no Item
  in `content/tuning.toml`, which is the argument `player.starting_stock` makes for being a
  single quoted bill.
- **Separate arrays from the Delivery counter, not one pot either.** What is banked is
  spendable and what is on the counter is spent: `_delivery_items` clears when a tier
  completes and `_nest_store_items` does not, so a HUD reading "2/3" can never be a surplus.
  One pot would have to tell the two apart with a rule rather than with a field.
- **`WITHDRAW_FROM_NEST` carries an Item and a count, where `DELIVER_TO_NEST` carries
  nothing.** That asymmetry is deliberate: a hand-over has one open bill and one answer to
  what the Nest wants, so the only choice is *when* to walk over. A withdrawal has neither —
  the store holds several Items at once, and because nothing deposits by hand, a player forced
  to take all of one Item to get any of it could never put the rest back. The Item travels as
  an index into the sorted Item ids, for the reason a Machine does in `BUILD_MACHINE`, and the
  count is clamped to what is there exactly as a hand-over is clamped to the bill.
- **The refusal is a projection and the action consults it.** `query_withdraw_refusal(player,
  item_index)` answers about a withdrawal that has not happened — the arrangement
  `query_build_refusal` and `query_delivery_refusal` have — and `_apply_withdraw_from_nest`
  calls the same function, so what a player is told and what the Simulation does are one rule.
  It asks about the **Item and not an amount**: what a player hovering a store row wants to
  know is whether there is anything to take, and a count in the signature would make that
  answer depend on a number nobody has typed yet.
- **One reach, not two.** A withdrawal is made from `nest.delivery_reach_metres`, through the
  same `_player_is_at_the_nest`, so there is no spot a player can stand on where the Nest
  takes goods but hands none back.
- **A Nest that has fallen is not a counter.** `_nest_store_room` is zero once the Run is
  over, as `_delivery_would_take` already is, and a withdrawal is refused `RUN_IS_OVER`. What
  was banked stays banked, because nothing is destroyed; it simply cannot be reached.
- **Which amount the key asks for is presentation.** `PlayerController.KEY_WITHDRAW` sends one
  intent per Item the Machine on the Build Gun is still short of, for exactly the shortfall,
  because build costs are the only sink for materials in the game and so "what the thing I am
  holding still costs" is the amount a player wants every time. A counter with a row per Item
  would send the same intent with different numbers and the Simulation would not know the
  difference — the same split `BuildGun.refusal_text` makes.
- **`test_nest_store.gd` ends with the acceptance test, and it runs on the shipped economy.**
  `content/` unaltered: 80 plate, an opening line that costs 78, a second Ammo Press at 14.
  It stands the whole line up, checks that a second Press is `MISSING_MATERIALS`, lets the
  Smelter belt plate into the Nest, withdraws 14 and builds it. The Map is the test's own,
  because the starter Map's Nodes are far enough apart that joining them up is a lesson in
  Belt routing rather than a statement about materials — and it carries no Breach, so no Wave
  interrupts the accounting. What is being measured is whether the Factory can pay.


## The Silo, the Charges, the dial and the Painting

The design's most distinctive mechanic, borrowed from StarCraft's nuclear silo and sharpened,
and the clearest statement of the keystone loop there is: a Charge is assembled out of
Belt-fed plate and rounds, so **more production means more artillery, full stop** (DESIGN.md).

- **A Silo is a Machine whose output is a Charge rather than an Item**, which is the Turret's
  trick a third time. `role=silo` in `content/machines.csv`, a Recipe with inputs and no
  outputs, and `_craft` advances it exactly as it advances a Smelter. The only thing the
  Simulation adds is what happens instead of depositing an output: `_assemble_a_charge`.
  **`produces_no_items()` is the predicate it joined** rather than a rival — a generator makes
  Power, a Turret makes damage or repair, a Silo makes a Charge, and the loader's
  outputs-must-be-empty rule needed no new clause. There is no Silo table: the stockpile, the
  loaded shell and the loaded count are three more per-Machine arrays indexed exactly like
  `_machine_progress_ticks`, because giving a Silo its own index space is how a Silo stops
  being a Machine.
- **A full Silo is idle and off the Power grid**, by one more clause in `_machine_would_work` —
  the single predicate behind what the grid bills, what advances and what a query calls
  starved. Deliberately *not* starvation: it has everything its Recipe asks for and nowhere to
  put the result, which is exactly the standing a Turret with nothing in reach has. Without it
  a Silo at capacity would go on eating plate and rounds and browning out the Factory to
  produce nothing.
- **`charge_capacity` is a column, so a bigger Silo is a row** — the argument `range_tiles` and
  `damage` already made. How much artillery a Factory can bank is the most consequential number
  about a Silo and it belongs next to the Power it draws and the hit points a Breaker has to
  chew through to take the stockpile with it.
- **A destroyed Silo loses its stockpile, and so does a demolished one.** `_remove_machine`
  drops the three entries and nothing anywhere hands a Charge back — #11's asymmetry applied to
  the most expensive thing a Factory can be holding, plus the one extra claim this mechanic
  makes: a load is irreversible, so taking the Silo apart must not be a way to undo one. A
  Charge is not an Item, so there is nothing for `_refund_machine` to return even if it wanted
  to. That is what makes a breakthrough threaten the players' heaviest weapon and not just
  their smelters.

### Loading by hand, and why it cannot be taken back

DESIGN.md names Silo loading **first** in its list of diegetic controls, and the reason is in
the same paragraph: friction is satisfying when it is problem-solving under pressure and tedious
when it is transcription. An irreversible commitment made *before* the fight is the first kind.

- **The dial is per-player Simulation state and commits nothing.** `_player_dial_stratagem` and
  `_player_dial_charges` are where a player has wound the shell selector and the charge counter
  before they walk over — the arrangement `_player_selected_machine` has, for both of its
  reasons: the controller may hold nothing authoritative, and in co-op what somebody else is
  winding up is worth drawing. Per player rather than per Silo, because a shared dial would let
  one player change another's commitment under their hands.
- **`LOAD_SILO` is the irreversible one, and the irreversibility is the absence of code.**
  There is no unload intent and there will not be one; `_load_silo_refusal` returns
  `SILO_ALREADY_LOADED` rather than replacing what is in the tube; and the only thing that ever
  clears a load is a Painting beginning. Fire what you loaded or lose it with the Silo.
- **A Charge is a multiplier, not a second Stratagem.** The count on the dial scales whichever
  magnitude the row quotes — `damage_per_charge` for a Barrage, `goods_per_charge` for a Supply
  Drop or a Sentry's magazine — so four Charges mean the same thing whatever is in the tube, and
  there is one rule rather than three. `silo.max_charges_per_load` is the dial's upper stop and
  is deliberately a *different* number from a Silo's `charge_capacity`: one says how much
  artillery a Factory may bank, the other how big one strike may be.
- **The refusal is a projection and the action consults it**, which matters more here than
  anywhere else in the project because this is the one act a player cannot take back. The HUD
  reads `query_load_silo_refusal` every frame about the Silo the key would commit to, so "already
  loaded — fire it or lose it" is on screen *before* the key goes down. That is what makes the
  irreversibility fair rather than cruel.
- **Which Silo the key means is presentation, and `game/` owns it.**
  `PlayerController.silo_tile_for_loading` is the Silo under the tool aim, or failing that the
  first Silo in reach, and **the HUD calls the same function** — a reason on screen about a
  different Silo from the one the key means is worse than no reason at all. Reach itself is the
  Simulation's answer, asked through the refusal, so there is no second opinion about how far an
  arm goes. The same split `BuildGun.refusal_text` and `KEY_WITHDRAW`'s choice of amount make.

### Painting, and what an interrupted one costs

The best co-op moment the design has, because one player is committed and helpless while the
others cover them (GLOSSARY.md).

- **The Charges leave the Silo on the tick the channel begins.** That is the whole of "an
  interrupted Painting consumes the Charge and produces nothing" — it is true by construction
  rather than by a rule somebody has to remember, because `_begin_painting` takes them out and
  there is no path by which they go back. Every interruption is then simply the channel not
  finishing.
- **Three things interrupt it: letting go, aiming somewhere else, and being hit.** `PAINT` is
  held and sent every tick, like `REPAIR` and `FIRE`, so releasing it *is* the interruption; and
  `_damage_player` calls `_interrupt_painting` on **any** damage rather than on going down,
  because a Stratagem a player could soak two Breaker bites through would not be exposed in any
  sense a player could feel. That one clause is what makes covering somebody a job.
- **A player must stand at the target, literally.** The painted tile is the tile under their
  feet — `_paint_refusal` returns `NOT_AT_THE_TARGET` otherwise — rather than a tile within some
  reach, because the whole price of a Stratagem is walking into the place you want it to land.
  It is also why `_walk` roots them once the channel starts: "at the target" has to mean
  something. **No aim crosses the float boundary**, for the reason `FIRE` carries none: where a
  player stands is authoritative fixed-point state already, so the controller derives the tile
  from a query.
- **Being mid-Painting is a refusal, not a mode.** `_act_refusal` is the one function every
  refusal a player's intent goes through now opens with, and it answers `PLAYER_IS_DOWN` or
  `PLAYER_IS_PAINTING` — two states in which a player does nothing, both *facts about them* in
  the same way their wallet is. Nothing anywhere asks whether acting is currently permitted, and
  building is still never gated. It is deliberately **not** folded into `_player_can_act`, which
  `_damage_player` and `query_player_is_alive` consult: a player mid-Painting is emphatically
  still alive and still takes the bite that interrupts them.
- **What interruption cost is state, not an inference.**
  `_player_paint_interrupted_tick` and `_player_charges_wasted` are hashed and saved, for two
  reasons. A player has to be able to read what a lost Painting cost them — a Charge that
  vanished with no accounting is exactly the bad luck Heat is built to avoid. And it is what
  lets a replay fixture *prove* an interruption happened rather than infer it from an effect
  that failed to arrive, which is a weaker claim about a stronger-sounding thing.

### The three Stratagems, and what each one reuses

`content/stratagems.csv` is the whole of it and **nothing in `sim/` names a Stratagem**. What
the Simulation knows is the three `effect` values; a second Barrage with a wider radius and a
longer channel is a row.

- **Artillery Barrage** takes `damage_per_charge × charges` off every Enemy within
  `radius_tiles` of the painted tile. Reach is compared **squared**, like a Turret's and a
  wrench's. Walked in **descending** Enemy index order — the one place in the project that does
  not walk Enemies forwards — because nothing here is a *choice* between Enemies, so there is no
  selection bias to avoid, and a kill removes its entry immediately exactly as `_fire` does.
  Enemies only: there is no friendly fire anywhere in this Simulation and this would be the one
  place it existed.
- **Supply Drop** hands `goods_per_charge × charges` to the painting player through
  `_give_to_player` — **their own pockets**, which are the same pockets the Build Gun spends
  from and a weapon fires out of. That is what makes it the answer to having run out; a drop
  that banked at the Nest would be a Delivery run in reverse and would ask the player to walk
  home, which is what a Stratagem is for not doing.
- **Sentry Drop** calls `_place_machine` with the Turret its row names, an expiry tick, and its
  input buffer pre-filled. **It is an ordinary Machine in every respect a player can observe** —
  it aims through `_aim`, spends rounds through `_craft`, obstructs Enemies, can be chewed down,
  and does not work on the tick it arrived. The two things that make it a Sentry are that expiry
  tick and that pre-filled buffer, and neither is a mechanism: it is how a Machine that arrived
  from outside the Map and needs no Belt is expressed in arrays that already existed.
  `_add_to_input` is uncapped — the cap lives in `_input_has_room` and belongs to a *Belt*
  hand-off — so a Sentry legitimately arrives holding more than a Belt could ever have put
  there, which is the literal content of "needs no Belt", and
  `query_turret_ammunition_capacity` reports `max(capacity, held)` so the gauge tells the truth
  about it.
- **`_place_machine` was extracted for this**, and it is the one place a Machine joins the
  Factory. A Sentry Drop places a Turret with no Build Gun, no build cost and nobody standing
  there, and a second copy of those appends would have been a second place to forget an array.
- **`_expire` walks Machines in descending index order** so removing one does not skip the next,
  and runs before anything reads a Machine index for the tick — the grid, the aim, the craft — so
  a Sentry whose time ran out draws no Power and fires nothing on the tick it goes. Its rounds
  go with it, for a different reason from a destruction: they were never the Factory's, so
  letting a Sentry expire next to a Belt is not a way to bank a Supply Drop.
- **Which Silo a Painting draws from is geography.** `_loaded_silo` takes the loaded Silo whose
  tile comes first in canonical tile order, through `MapLayout.tile_precedes` — the single
  definition of tile order this project has. Index order would have made "which of my two Silos
  fired" a fact about which one a player happened to build first.

### Where the balance stands, and nobody has played it

Shipped numbers, not a measured Run. A Barrage Charge is 150 points against a Crawler's 30 and a
Breaker's 240, over a six-tile radius, behind a five-second channel — so one Charge clears Chaff
and two kill a Breaker, if a player can stand still for five seconds in the middle of it. The
Silo's Recipe is **a plate and twenty rounds every twenty seconds**, deliberately priced in the
very Item a Turret and a player both spend: artillery competes with the magazine rather than
being free once the line is up. `silo.max_charges_per_load` is 4 against a capacity of 8, so a
full Silo is two strikes rather than one big button.

**The number most likely to be wrong is that twenty rounds a Charge**, because it is the one
that decides whether a Run that builds a Silo thereby stops being able to feed its Turrets — and
the joint pass #10, #11, #12 and #15 are all waiting for now has a fourth claimant on the same
Ammo Press. The second is `paint_seconds`: five seconds is a guess at how long a player can be
asked to be helpless, and it is the whole feel of the mechanic.

## The float-to-fixed boundary

ADR 0002 says nothing converts a float back into a Simulation quantity. A first-person
controller cannot honour that literally — a mouse reports pixels as floats and a camera ray
is float arithmetic — so the crossing is made **exactly once**, in
`game/input_quantiser.gd`, under three rules:

1. **It lives in `game/`, never in `sim/`.** The purity lint takes no new exemption for it,
   because it is not in the Simulation.
2. **What crosses is an integer intent.** Mouse travel becomes a floored fixed-point count
   of pixels; a camera ray becomes a whole tile. A replay reproduces the intent without
   ever reproducing the float.
3. **Flooring, clamping and NAN-guarding are explicit.** Every conversion floors toward
   negative infinity like `Fixed`, every conversion is bounded, and NAN and INF are reduced
   rather than cast — NAN compares false against everything, and an unguarded cast would let
   it through as an arbitrary integer and desync a Run.

It has a contract of its own in `tests/cases/test_input_quantiser.gd`, like `Fixed`, because
its rounding is not observable through the façade. If you need to read a new float device,
add a function there rather than converting at the call site. #15 did exactly that:
`aimed_tile_at_height` is the Pneumatic Wrench's aim, which crosses the *body* of a Machine
rather than the ground the Build Gun's hologram snaps to.

**Firing crosses nothing, and that is the rule honoured rather than dodged.** A player's yaw
and pitch are already authoritative fixed-point state, so where a round goes is something the
Simulation knows exactly; an aim carried in a `FIRE` intent would be a second opinion derived
from a float. See the Gear section above.

`game/player_controller.gd` holds the only other float on the way in: a **device buffer**
of mouse travel and clicks gathered between frames. That is the same category of thing as
`TickPump`'s leftover frame time — a reading on its way in, not a fact about the world —
and it is drained once per tick. Everything a decision depends on is read back out of the
Simulation with a query.

## Determinism rules

From [ADR 0002](docs/adr/0002-deterministic-lockstep-inputs-only-networking.md).
Inside `sim/`, all four are absolute:

1. **Fixed-point integers only.** No floats in state or in intermediate steps.
   `Fixed.to_float` is the single sanctioned crossing and is outbound only.
2. **No wall-clock time.** The Simulation knows which tick it is on and nothing
   else. Deciding *when* to step belongs to `game/tick_pump.gd`.
3. **No unseeded randomness.** `DeterministicRng`, seeded at construction, is the
   only source. Never `randi()`, `randf()` or `RandomNumberGenerator`.
4. **No iteration over an unordered collection.** Arrays indexed by id, in index
   order. Sort keys first where a Dictionary is unavoidable.

`tests/cases/test_simulation_purity.gd` enforces all four mechanically against
every file in `sim/`. To take a sanctioned exception, put
`# purity-ok: <reason>` on the offending line. There are three in the whole
Simulation; the test fails if that count drifts far upward.

## Adding state to the Simulation

Feed it into `hash()`. State that is not hashed is state whose divergence the
determinism harness cannot see, which quietly weakens the guarantee the whole
architecture rests on.

**That is the only thing you have to do.** You do not have to remember to save it:
`sim/run_save.gd` walks the Simulation's own property list and persists every
script variable it finds, so a new `var` is saved, loaded and round-tripped
without that file changing. See below.

## Saving and resuming a Run

`sim/run_save.gd` is the whole of it, and its promise is one sentence: **a Run
written out and read back hashes to the integer it hashed to before.** Because
`hash()` already covers everything that matters, that single comparison is the
entire acceptance criterion, and `tests/cases/test_run_save.gd` asserts it over a
Factory with Items in flight, a part-finished craft, a grid in deficit and a player
mid-stride.

- **There is no list of fields and no per-field code.** `RunSave` reflects over
  `Simulation.get_property_list()`. Forgetting to persist new state is therefore
  not a mistake that can be made — the one `# purity-ok:` line that reflection
  costs buys that outright. `test_run_save.gd` proves it with a `Simulation`
  subclass carrying Enemy arrays `RunSave` has never heard of, which round-trip
  anyway.
- **Two special cases, named in that file and nowhere else.** The `Definitions`
  (carried as a digest; content lives in `content/`) and the `DeterministicRng`
  (whose whole memory is one integer).
- **The file is a census and the load checks it.** Every property gets a line, and
  loading compares the file's names against the live Simulation's. A save written
  before an array existed refuses *by name* rather than resuming with it quietly
  empty. So does one carrying a property this build no longer has.
- **The save carries its own state hash and every load re-derives it.** Any failure
  to round-trip exactly is caught on every load a player ever performs, not only in
  the suite.
- **A property in a type the format cannot encode is refused by name**, not
  silently zeroed. Hold state as parallel integer arrays — which is the convention
  anyway — or teach `_encode_value` about the type.
- **`RunSave.DERIVED_PROPERTIES` is the one exception to "every property".** The
  flowfield is one entry per tile of the Map three arrays over, so carrying it would
  make every save hundreds of kilobytes of numbers the next tick recomputes, growing
  with the square of the Map rather than with the Factory. Excluding a property is safe
  only because the names on that list are **absent from `hash()`** too, which is what
  leaves the round-trip check with teeth — so check `hash()` before adding to it. A
  restored Run notices it is holding no field by its size rather than by a flag, and
  `test_enemies` steps a saved and a resumed Run side by side to prove the rebuild
  agrees.
- **The format is line-oriented text**, `<property> <type-tag> <payload…>`, keyed by
  name rather than by position. Chosen for diffability in a project whose method is
  comparing two states, and because a positional blob cannot report which field it is
  missing. The rationale, and the escape hatch if size ever becomes the constraint,
  are in the file's own header.
- **Saving is a read.** It takes no action, consumes no RNG draw and leaves the hash
  alone, so a Run saved mid-flight follows exactly the ticks it would have unsaved.
- **Rendering state is never saved** because there is none: `WorldView` rebuilds from
  `query_*` every frame and holds nothing authoritative.
- **Neither key is an Input Action.** `PlayerController.KEY_SAVE` (F5) and `KEY_LOAD`
  (F9) are handled in `Main._input` alongside Escape. Saving does nothing to the Run;
  loading *replaces* the Simulation, which no method on it could do and no replay
  could reproduce — resuming a Run is the same category of act as constructing one.
  The full argument is written above `PlayerController.KEY_SAVE`. Contrast
  `RELOAD_DEFINITIONS`, which is an action because it mutates the Simulation that
  exists, at a known tick.
- **A refused load leaves the running Run untouched**, the same rule a failed
  hot-reload obeys.

Every later ticket should carry a round-trip criterion, and the cheapest way to
write one is a hash comparison through `RunSave.serialise` / `deserialise` — or
`DeterminismHarness.verify(recording, restored_sim)`, which takes a replacement
Simulation for exactly this.

## The determinism harness

`sim/determinism_harness.gd` records a script of Input Actions, replays it from an
identical starting state, and compares the state hash **tick by tick** — not just
at the end, because a fault that perturbs a few ticks and settles back is still a
desync.

Every subsequent ticket is expected to leave a replay fixture behind:

```gdscript
var script: InputScript = InputScript.new()
script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
script.add_idle_ticks(30)

var recording: ReplayRecording = DeterminismHarness.record(script, seed, players)
var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
assert_true(divergence.is_identical, divergence.describe())
```

`record` takes an optional `Definitions`. Leave it out in a fixture: the replay
then re-reads `content/`, and a content change that would alter the Run is
reported as a `definitions_mismatch` rather than passing unnoticed. Pass one when
the scenario needs content the shipped files do not have.

`verify` takes an optional replacement Simulation, which is how a save/load round
trip gets proved exact and how the harness itself is proved to have teeth.

**A fixture is worth nothing without an honesty check beside it.** A replay of a Run in which
the thing never happened reads as a passing determinism test, and the failure mode is silent.
`test_gear.gd` established the shape and `test_silo.gd` leans on it hardest: its pair of
fixtures is a Charge assembled and **fired** and a Painting **interrupted**, and each has a
test that drives the same script and asserts the event rather than its absence — because an
interruption is exactly the kind of thing it is easy to conclude from an effect that failed to
arrive.

`tests/cases/test_recorded_session.gd` is the strongest fixture in the suite and the shape
later ones should copy: it drives the **real input producer** with a sequence of device
readings — mouse travel, held keys, clicks, a scroll wheel, Survey View held and released —
captures what crossed tick by tick, and replays that. A fixture written as Input Actions by
hand proves the Simulation is deterministic; one written as device readings proves the whole
chain from a mouse to a state hash is.

## Conventions

- Files and directories `snake_case.gd`; classes `PascalCase` via `class_name`.
- Tabs for indentation, as Godot's formatter expects.
- Static typing everywhere, including loop variables (`for i: int in ...`).
- Test files `tests/cases/test_*.gd` extending `TestCase`, methods `test_*`.
  Discovery and execution are sorted by name, so the suite is itself
  deterministic.
- Test names read as specifications — `test_a_turret_without_ammunition_does_not_fire`,
  not `test_turret_3`.
- Expected values in tests come from a worked example or a known literal, never
  from recomputing what the code does. `Fixed.mul(a, b) == (a * b) >> 16` asserts
  nothing.
- Domain vocabulary from `GLOSSARY.md`, capitalised: Nest, Breach, Factory,
  Machine, Belt, Heat, Wave, Turret, Silo, Charge, Delivery, Depth, Gear, Stratagem.
- Fixed-point constants are written `Fixed.from_rational(1, 3)`, never as a
  decimal literal. In a *data* file a rate is written in decimal and parsed with
  `Fixed.from_decimal_string`.
- **Every test method must assert something.** The runner counts assertions and
  fails a method that made none. If a test's happy path returns early, assert
  explicitly rather than falling off the end.
- **A method cut off by a runtime error fails, however far it got.** See the
  runtime-error guard below. A test that triggers one deliberately must claim it
  with `engine_log.drain()`, which is also the assertion that it happened.

## Test runner

Zero dependencies — no addons. The spec's first choice was gdUnit4; a
zero-dependency headless runner was its sanctioned fallback and is what shipped,
to avoid vendoring an addon into a public repository and to keep full control of
headless exit codes. There is no JUnit XML output yet; add it when CI needs it.

Two guards stop a method that did not really pass from reporting `ok`. Both exist
because the suite is the project's only guarantee of determinism, and a test that
reads green without having run is worse than no test at all.

**A method that asserted nothing fails.** That covers the empty test and the one
whose only statement aborted.

**A method cut off by a GDScript runtime error fails, naming the engine's own
error.** This is the harder half. A runtime error — a call to a function that does
not exist, an index out of range, a division by zero — aborts *only the frame it
fired in*: the caller resumes at the statement after the call, nothing is raised,
and every assertion that had already passed stays counted. So the assertion count
cannot tell a finished method from a severed one, and a method that aborts after
one passing assertion used to report `ok` with its untested remainder unmentioned.

Nothing in GDScript can catch such an error, so `tests/engine_log.gd` reads the
engine's *report* of it instead. Godot mirrors its output into
`user://logs/godot.log` and flushes as it goes, so the file is readable by the
process writing it; each runtime error lands there prefixed `SCRIPT ERROR: `,
which `push_error()` (`ERROR: `) and `push_warning()` (`WARNING: `) do not use, so
a test that deliberately drives production code into reporting an error is
unaffected. The runner resets the reader before every method and drains it after,
and records a failure per error — so detection does not depend on the depth of the
frame that died, and a method that ran to its end records nothing.

Consequences worth knowing:

- `debug/file_logging/enable_file_logging=true` in `project.godot` is load-bearing
  for the suite, not just for debugging. The runner prints its `Engine log:` line
  *through* the log and fails the whole suite if the line does not come back,
  because a guard that has quietly become a no-op is the exact failure it exists
  to prevent.
- A test that triggers a runtime error on purpose calls `engine_log.drain()` to
  claim it — the runner then finds nothing left and the method passes. Drain in
  the test method's own frame, not the aborted one, which it will reach because
  the abort killed only the callee.
- The guard's own tests are `tests/cases/test_runtime_abort_guard.gd`, covering
  both directions: an abort after a passing assertion must fail, and a method that
  completes must not. A guard that always fires and one that never fires are
  equally worthless, so neither case may be dropped.
