# DEEP FOUNDRY — working notes

How to build, run and test this project, and the conventions the code follows.
Design lives in [docs/DESIGN.md](docs/DESIGN.md), vocabulary in
[GLOSSARY.md](GLOSSARY.md), architecture rationale in [docs/adr/](docs/adr/).

## Commands

```bash
tools/assets/run_tests.sh        # asset pipeline: licence guard, FBX conversion, Godot import
tools/assets/generate_machines.sh  # regenerate every Machine mesh from its declaration
tools/run_tests.sh              # the whole suite, headless. This is the CI command.
tools/run_tests.sh determinism   # only tests whose case.method contains "determinism"
godot --path .                   # run the game
godot --headless --path . --quit-after 120   # launch headless for 120 frames
```

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
content/tuning.toml     balance numbers that are not per-Machine or per-Recipe
```

**Adding a Machine or a Recipe is a row. It is never a code change.** There is no
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

`sim/csv_table.gd` and `sim/toml_document.gd` are the only parsers. Both are
hand-rolled: Godot ships no TOML parser, and vendoring one into a public repo is
out (`docs/ASSETS.md`). The TOML subset is sections, `key = value`, comments,
integers, decimals, quoted strings, `true`/`false` — and nothing else. Arrays,
inline tables and dates are valid TOML and are refused by name and line number.
If you need a fourth data file, reuse `CsvTable` rather than writing a parser.

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
- `sim/map_layout.gd` is the Map's geography: where the Nodes are, what Resource
  each yields, what Depth tier it sits at, where the Nest stands and where the
  Breaches are. Deliberately *not* in `content/` —
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
  `content/machines.csv` defines six — #10 added the Ammo Press and the MG Turret, leaving
  `press_mk1`, `assembler_mk1`, `generator_mk1` and `silo_mk1` undeclared — so loading it
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
- **A Breach is fixed and known in advance**, which is the whole deal GLOSSARY.md
  strikes: it is fortifiable, and it could not be if it moved. `MapLayout` sorts them
  into tile order, and Enemies are released in that order, so which Breach goes first
  is geography rather than the order somebody typed the rows in. A Map with **no**
  Breach has no Waves at all — which is the geography `MapLayout.empty()` gives a test
  that is studying the Factory and not the threat.
- **The Wave schedule here is a scaffold and says so.** A baseline timer and a count
  that grows linearly, four keys in `[wave]`. Heat, the Telegraph and the
  call-Wave-early lever are what will really decide arrival and size; that ticket
  replaces `_waves()` and the whole `[wave]` section.

### Enemies are array entries, never nodes

Per ADR 0001, and this is the decision the whole Enemy scale target rests on.
Idiomatic engine agents cap out around 150-250 before frame times collapse; instanced
array entries reach thousands. Milestone 1 ships twenty Crawlers **on the final
architecture** so that the Chaff tier switching on later is more array entries rather
than a rewrite.

- An Enemy is an index into parallel `PackedInt64Array`s — serial, kind, position in
  fixed-point metres, health, spawn tick, bite cooldown. There is no Enemy class, no
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

### One shared flowfield, not a path per agent

DESIGN.md calls this not a close call: rebuilding one field is O(map) once and is then
amortised across every Enemy alive, where per-agent A* is O(agents × path) every time
anything moves — and every Enemy converges on the same destination.

- `_flow_direction` holds a `WorldGrid` direction per ground tile, `_flow_distance` the
  exact tile count to the Nest, both as flat arrays indexed by tile. One breadth-first
  sweep outward from the **whole Nest footprint**, four-connected, so no heuristic is
  involved and an Enemy heading for the Nest's near edge is not routed to its anchor.
- **Derived, so it is rebuilt rather than hashed**, exactly like `_belt_update_order`.
  It is a pure function of the Map and the obstructions standing on it, both of which
  are hashed. Rebuilt when a Machine is built or demolished or a reload could have
  resized a footprint — never on a tick that changed neither, and never at all while
  no Enemy is on the Map.
- **`_mark_obstructions` is the single definition of what obstructs**, and
  `query_tile_obstructs_enemies` reads what it painted rather than asking the question
  a second way. Machines obstruct; Belts and Nodes do not — a Crawler crawls over a
  conveyor. **Walls join that function in the ticket that adds them**, as one more loop.
- It paints by walking the **Machines**, not by asking each of the 16641 tiles what is
  standing on it. That is O(Machines) against O(tiles × Machines), and it is the
  difference between a 2.5 ms rebuild and a 55 ms one — a three-frame hitch every time
  a player places something.
- The sweep walks **flat index space** rather than `Vector3i`, for the same reason:
  `FIELD_STEPS` mirrors `WorldGrid.DIRECTION_STEPS` so the recorded direction still
  means what `direction_step` says it means, and `test_flowfield` walks a 60x60 region
  of the field a tile at a time to prove the two orders agree.
- An Enemy on a tile the field cannot route — inside a Machine a player dropped on top
  of it, or in a pocket sealed off from the Nest — walks straight at the Nest instead.
  Without that, pinning a Crawler under a Machine would be a cheese rather than a
  defence.
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

Two things a later ticket should know. **The shipped Wave schedule grows a Wave's count but
never its arrival rate**, so the pressure is Wave *length* against a fixed production rate
rather than a rising intensity — that is `_waves()` being the scaffold #9 said it was, and
**Heat is the ticket that makes escalation real** (GLOSSARY.md, DESIGN.md). And **a Machine's
output buffer is uncapped**, so a Belt that fills up banks the surplus in the Ammo Press
indefinitely; the stockpile a player builds between Waves is real and unbounded, which is
currently what carries the early Waves. Heat should expect to retune `fire_mg`,
`make_ammunition` and `range_tiles` alongside the `[wave]` section.

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
- **Survey View is held, not toggled**, and its transition is counted in ticks *inside*
  the Simulation, eased on the way out with `Fixed.smoothstep_fixed`. That is a decision
  about feel rather than about determinism: its height, duration and tilt are
  hot-reloadable tuning, and the only way to find out whether a lift feels good is to try
  several. **It is not a mode** — nothing consults it to decide whether an intent is
  allowed, and a player can walk and build while surveying.
- **Building is never gated.** There is no build mode, no flag, and no check anywhere in
  the Simulation that asks whether building is currently permitted (GLOSSARY.md: the Build
  Gun is available at all times, including mid-Wave).

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

Where the stock comes from is `player.starting_stock_per_item`, and the file says plainly
that it is a scaffold: Delivery progression (milestone 5) is what will really decide it.
It is granted once at construction, so raising the number mid-Run is not a way to conjure
materials.

### Rotation

`WorldGrid.rotated_footprint` swaps a footprint's extents without moving its anchor, so a
2x3 Machine turned a quarter covers 3x2 tiles from the same origin. One convention, shared
by placement validation and the renderer. Rotation is per-Machine state and is hashed; a
turned Machine covers different ground and presents its ports to different tiles.

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
add a function there rather than converting at the call site.

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
  Machine, Belt, Heat, Wave, Turret, Silo, Charge, Delivery.
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
