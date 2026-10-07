## The Simulation: the whole authoritative game state, and the project's only
## test seam.
##
## Its entire surface is three things:
##
##     step(actions)    advance exactly one tick
##     hash()           reduce the whole state to one integer
##     query_*(...)     read-only projections
##
## Nothing else gets to touch state. The Godot-side layer turns devices into
## Input Actions, calls `step`, and draws what the queries return — it holds no
## authoritative state of its own, which is what keeps the seam count at one
## (ADR 0001). Later tickets add the modules behind this façade — grid, Belts,
## Machines, Power, Heat, Waves, Turrets, Silo, Delivery — and they are all
## tested through these same three entry points, never directly.
##
## The rules every line behind this façade obeys, from ADR 0002:
##
## * Fixed-point integers only. No floats, in state or in intermediate steps.
## * No wall-clock time. The Simulation has no idea how long a tick took; it only
##   knows which tick it is on. Deciding *when* to step is the caller's business.
##   `TICKS_PER_SECOND` is a conversion rate for tuning values, not a clock.
## * No unseeded randomness. `DeterministicRng`, seeded at construction, is the
##   only source, and its state is part of the hash.
## * No iteration over an unordered collection. Arrays indexed by id, in index
##   order. Where a Dictionary is unavoidable, its keys get sorted first.
##
## `tests/cases/test_simulation_purity.gd` enforces all four against the source of
## every file in this directory, so a later ticket cannot quietly break one.
class_name Simulation
extends RefCounted

## Simulation ticks per second of game time. Fixed, because a variable tick rate
## would make the Simulation depend on real time. Rates expressed per second in
## tuning files are converted with this.
const TICKS_PER_SECOND: int = 60

## Ticks in a minute of game time. Heat's decay is quoted per minute because that is the
## span a human reasons about a Factory over, and the conversion has to be exact: the
## decay is carried as an integer credit against this number rather than as a per-tick
## fraction, so nothing is shed and nothing drifts over a forty-hour Run.
const TICKS_PER_MINUTE: int = TICKS_PER_SECOND * 60

## How far from level a player may pitch the view, in fixed-point turns. 0.24 of a
## turn is 86.4 degrees — not quite the vertical, so the horizon never vanishes
## entirely and the view cannot roll over the top.
const MAX_PITCH_TURNS: int = Fixed.ONE * 24 / 100

## How many pixels of mouse travel the tuned look sensitivity is quoted per. A
## thousand, so the tuning file carries a number around 0.4 rather than 0.0004.
const LOOK_PIXEL_UNIT: int = 1000

## How many ground tiles the flowfield covers on each axis, and in total. The Map is
## finite and handcrafted (GLOSSARY.md), so the field is a flat array indexed by tile
## rather than a growing structure — one allocation, no Dictionary, and an index that is
## pure arithmetic.
const FIELD_WIDTH_TILES: int = WorldGrid.HALF_EXTENT_TILES * 2 + 1
const FIELD_TILES: int = FIELD_WIDTH_TILES * FIELD_WIDTH_TILES

## What one step in each direction adds to a field index. **In the same order as
## `WorldGrid.DIRECTION_STEPS`** — +x, +z, -x, -z — because the direction the sweep records
## is a `WorldGrid` direction and an Enemy resolves it back through `direction_step`. The
## sweep works in index space rather than in tiles because it visits every tile of the Map
## four times and vector arithmetic there is the difference between a frame and three.
## `test_flowfield` asserts the two orders agree by following the field a tile at a time.
const FIELD_STEPS: Array = [1, FIELD_WIDTH_TILES, -1, -FIELD_WIDTH_TILES]

## The one Enemy kind Milestone 1 ships. An **alias** of `EnemyKind.CRAWLER` rather than a
## second copy of the number: `content/waves.csv` names kinds in words, `EnemyKind` is
## where a name and its integer meet, and a second authority here would be the one that
## drifted. Held as an integer in `_enemy_kind` so the
## Breaker and the Siege Hulk join the same arrays rather than getting their own.
const ENEMY_KIND_CRAWLER: int = EnemyKind.CRAWLER

## How far past `depth.breach_offset_tiles` the search for somewhere to put a new Breach will
## widen if every tile on the ring is already taken. Four, which is far more slack than the
## shipped Map needs — the point is that a crowded corner of the Map degrades into a Breach a
## few tiles further out rather than into no consequence at all.
const RING_SEARCH_WIDENING: int = 4

## Degrees in one whole turn. Angles are turns everywhere inside the Simulation; the
## tuning file is allowed degrees because that is how a human reasons about a tilt.
const DEGREES_PER_TURN: int = 360


## Why a Build Gun intent would be refused.
##
## A refused build stays a silent no-op whose hash does not move — a misaimed Build
## Gun is an ordinary thing for a player to do. The *reason* is therefore not stored
## state but a pure projection: `query_build_refusal` answers it about a placement
## that has not happened, so the hologram can show the reason before the click rather
## than after it, and `_apply_build_machine` consults the same function so the two can
## never disagree.
enum Refusal {
	## Nothing in the way. The placement would succeed.
	NONE = 0,
	## The intent names no Machine in the current definition set.
	NO_SUCH_MACHINE = 1,
	## Some tile of the footprint is outside the Map, or on a layer building cannot
	## reach — which is every layer but the ground while building is flat.
	OFF_THE_MAP = 2,
	## A Machine or a Belt is already standing on some tile of the footprint.
	OCCUPIED = 3,
	## The player does not hold the Machine's build cost.
	MISSING_MATERIALS = 4,
	## Nothing to demolish on that tile.
	NOTHING_THERE = 5,
	## The lever was pulled while the Wave it would call is already on its way — the
	## Telegraph is running, so there is nothing left to bring forward.
	WAVE_ALREADY_COMING = 6,
	## The lever was pulled while the current Wave is still coming out of the Breaches.
	## Calling then would stack two Waves on one Telegraph, which is the ambush the
	## Telegraph exists to prevent.
	WAVE_STILL_ARRIVING = 7,
	## There is nowhere for a Wave to enter. A Map with no Breach has no Waves at all,
	## so there is no Wave to call.
	NO_BREACH = 8,
	## The Run is over. Nothing is called after the Nest has fallen.
	RUN_IS_OVER = 9,
	## The intent names a player this Run does not have.
	NO_SUCH_PLAYER = 10,
	## The Machine's definition exists but no Delivery has unlocked it yet. A reason
	## rather than a separate gate, because a player who cannot build something has to be
	## told why — and because placement and the reason it gives are one function.
	CONTENT_IS_LOCKED = 11,
	## Every Delivery tier has been completed. There is nothing left for the Nest to want.
	NO_DELIVERY_PENDING = 12,
	## The next Delivery sits at a Depth the Factory is not mining at. Depth gates what is
	## possible to deliver (GLOSSARY.md), and the way past it is a Miner that reaches
	## deeper, not a bigger pile of goods.
	DEPTH_TOO_SHALLOW = 13,
	## The player is too far from the Nest to hand anything over. Progression is physical.
	TOO_FAR_FROM_THE_NEST = 14,
	## The player is holding none of what the Nest is still waiting for.
	NOTHING_TO_DELIVER = 15,
}

# Note what is *not* a constant here any more: how fast a player walks. That lives
# in content/tuning.toml, because it is a balance number and balance numbers belong
# to whoever is tuning the game, not to whoever is editing code.

# ── State ─────────────────────────────────────────────────────────────────────
# Everything below is authoritative, fed into the hash in a fixed order, and
# data-oriented: parallel arrays indexed by id rather than objects in a graph.

var _tick: int = 0
var _seed: int = 0
var _rng: DeterministicRng = null

## The content definitions this Run is using: Machines, Recipes, Items and tuning,
## loaded from content/. Immutable — a reload swaps the whole set rather than
## editing it, which is what lets queries hand it out without copying.
var _definitions: Definitions = null

## How many times the definitions have been reloaded mid-Run. Hashed, so reloading
## back to the original files does not restore the earlier hash: the Run did change,
## and a hash that said otherwise could not describe its own history.
var _definition_generation: int = 0

## Player positions in fixed-point metres, indexed by player id.
var _player_x: PackedInt64Array = PackedInt64Array()
var _player_z: PackedInt64Array = PackedInt64Array()

## Where each player is looking, in fixed-point *turns* — one whole revolution is
## `Fixed.TURN`. Yaw wraps; pitch clamps just short of the vertical.
##
## This is authoritative Simulation state rather than a property of a camera, and
## that is the load-bearing decision of the whole first-person layer. The camera is
## told where to point by a query; it never decides. A controller that accumulated
## its own yaw would be holding authoritative state, the Build Gun's aim would be
## derived from a float, and the first thing to diverge in co-op would be where
## everybody is pointing.
var _player_yaw: PackedInt64Array = PackedInt64Array()
var _player_pitch: PackedInt64Array = PackedInt64Array()

## How fast each player is moving, in fixed-point metres per second. State, not a
## derived quantity: a player who let go of the keys a moment ago is still sliding,
## and that slide is what makes a 1.8 m person feel like a person rather than a
## cursor. The rate it converges on the throttle is `player.walk_acceleration…` in
## `content/tuning.toml`.
var _player_velocity_x: PackedInt64Array = PackedInt64Array()
var _player_velocity_z: PackedInt64Array = PackedInt64Array()

## The throttle each player asked for this tick, in their own frame: forward and
## strafe, each in [-ONE, ONE].
##
## Deliberately *per tick* and deliberately not hashed. `_walk` consumes it and
## clears it before the tick ends, so it is zero at every point a hash is taken, and
## sending no `MOVE` is how a player stands still — which means an idle tick in a
## recorded script is a tick spent slowing down rather than one spent coasting on a
## throttle nobody is holding any more.
var _player_intent_forward: PackedInt64Array = PackedInt64Array()
var _player_intent_strafe: PackedInt64Array = PackedInt64Array()

## Whether each player is holding Survey View down this tick, and how many ticks of
## the transition they have accumulated.
##
## Ticks rather than a fixed-point fraction, for the reason craft progress is counted
## in ticks: the lift then takes exactly the tuned number of ticks, with nothing
## rounding away at either end, and a lift interrupted halfway resumes from where it
## actually got to. The easing is applied on the way out, in the query, so the stored
## progress stays linear and reversible.
##
## In the Simulation rather than in the camera because the transition is state — a
## half-raised camera is a different state from one at either end — and because that
## is what lets its height and duration be tuned in `content/tuning.toml` while the
## game is running. Finding out whether a lift feels good means trying several.
var _player_survey_held: PackedInt64Array = PackedInt64Array()
var _player_sprint_held: PackedInt64Array = PackedInt64Array()
var _player_survey_ticks: PackedInt64Array = PackedInt64Array()

## What each player has on the Build Gun, and which way round.
##
## The *id* rather than the definition index, for the reason a placed Machine holds
## its id: a hot-reload resorts the definition table, and a player must not find a
## different Machine on the Build Gun because somebody added a row. The rotation
## persists until changed, so a player lines a Machine up once and places several.
##
## Here rather than in the controller because the controller is forbidden to hold
## anything authoritative — and because in co-op what another player is lining up is
## worth drawing.
var _player_selected_machine: PackedStringArray = PackedStringArray()
var _player_build_rotation: PackedInt64Array = PackedInt64Array()

## What each player is carrying, as one sorted `PackedStringArray` of Item ids and one
## matching `PackedInt64Array` of counts per player — the same shape a Machine's
## buffers use, for the same reasons: ids rather than interned indices, so a
## hot-reload cannot relabel a player's pockets, and sorted, so iteration order is a
## property of the content rather than of what happened.
##
## Building spends a Machine's `build_cost` out of this and demolishing returns it in
## full, which is what makes iterating on a layout cheap (issue #1, user story 7).
## Where the materials come from in the first place is `player.starting_stock`, which is
## exactly the opening line and no more. Past that, what a player can build is what the
## Nest has unlocked.
var _player_item_ids: Array = []
var _player_item_counts: Array = []

## The Map's Nodes, as parallel arrays in the canonical order `MapLayout` sorted
## them into. None of this changes during a Run: a Node is inexhaustible (DESIGN.md),
## so there is no quantity here to run down and nothing subtracts from one.
var _node_tile_x: PackedInt64Array = PackedInt64Array()
var _node_tile_y: PackedInt64Array = PackedInt64Array()
var _node_tile_z: PackedInt64Array = PackedInt64Array()
var _node_resource: PackedStringArray = PackedStringArray()
var _node_depth: PackedInt64Array = PackedInt64Array()

## How many crafts each Node has given up at a Depth of `depth.breach_tier` or more, and
## whether it has already opened its Breach. One entry per Node, in Node index order.
##
## **Per Node, not per Miner, and this is the design decision rather than a convenience.**
## What opens a Breach is the hole in the ground, so knocking the Miner down and putting a
## new one back is not a way to reset the count, and the Breach is attributable to the mine
## a player chose to open rather than to a Machine that has since been demolished.
##
## `_node_breach_opened` is what bounds the whole mechanic: a Node opens at most one Breach,
## ever. Without it a forty-hour Run could ring itself with a hundred holes, which is a
## performance ceiling as much as a balance one — and the cap being per Node rather than per
## Run is what keeps the *second* deep mine a real decision too.
##
## A Node is still inexhaustible (DESIGN.md): nothing here subtracts from what it yields.
## This is a count of what the Factory has taken, not of what is left.
var _node_deep_crafts: PackedInt64Array = PackedInt64Array()
var _node_breach_opened: PackedInt64Array = PackedInt64Array()

## Where the Nest stands and how much of it is left.
##
## The structure the whole Run is about: its destruction ends the Run and nothing else
## does (GLOSSARY.md). The tile and the footprint are geography, copied out of
## `MapLayout` and never changed; the health is the one number Enemies move.
##
## Not a Machine. It runs no Recipe, draws no Power, and cannot be built or
## demolished — DESIGN.md lists it alongside Belt and Wall, outside the eight
## Machines — so it has no row in `content/machines.csv` and no entry in the Machine
## arrays. Its hit points come from `nest.health` in `content/tuning.toml`, because
## that is a balance number.
var _nest_tile_x: int = 0
var _nest_tile_y: int = 0
var _nest_tile_z: int = 0
var _nest_health: int = 0

# ── Delivery progression ──────────────────────────────────────────────────────
# Progression is physical: goods brought to the Nest unlock the next tier of Machines,
# Gear components and Stratagems (GLOSSARY.md). There is no research menu, no science
# resource and no stat increase anywhere in it — what a Delivery changes is what a player
# can *build*.
#
# **Everything here is a resolved id, never an index into the definition table.** That is
# the same precedent `_machine_id` and `_player_selected_machine` set, and it is what makes
# a hot-reload safe: a content edit that resorts the tiers, or inserts one in the middle,
# cannot change what a Run has already unlocked. All four arrays are kept sorted, so
# iteration order is a property of the content rather than of the order things were earned.

## The Delivery tiers this Run has completed, by id, sorted.
##
## The chain is walked in the definition set's own id order, and the *next* Delivery is
## the first tier whose id is not in here. So completing one unlocks exactly its own tier
## and nothing else: there is no counter to skip ahead and no tier that falls out by
## implication.
var _completed_delivery_ids: PackedStringArray = PackedStringArray()

## What the Deliveries completed so far have unlocked, by id, sorted. Three lists because
## they are three different kinds of thing, and a Machine id is checked against
## `content/machines.csv` while a Gear component and a Stratagem are identifiers the
## Simulation records now and a later milestone implements.
var _unlocked_machine_ids: PackedStringArray = PackedStringArray()
var _unlocked_gear_ids: PackedStringArray = PackedStringArray()
var _unlocked_stratagem_ids: PackedStringArray = PackedStringArray()

## What the Nest is holding against the Delivery it is currently waiting on, as parallel
## sorted Item ids and counts — the same shape a Machine's buffers and a player's pockets
## use.
##
## A Delivery is paid in instalments, because it arrives on a Belt an Item at a time and
## because carrying a hundred plates in one trip is not a decision. Cleared the moment a
## tier completes, so the counter only ever holds goods against the open tier.
var _delivery_items: PackedStringArray = PackedStringArray()
var _delivery_counts: PackedInt64Array = PackedInt64Array()

## The Breaches: the tiles Enemies enter the Map at, in the canonical tile order
## `MapLayout.tile_precedes` defines. A Breach never moves once it exists — it is known in
## advance and fortifiable (GLOSSARY.md), which it could not be if it moved — but the set
## **grows**, because sustained deep mining opens new ones.
##
## That growth is why these are Simulation state and not a question asked of `MapLayout`
## every tick. `MapLayout` is the geography a Run *starts* from: it is authored, it is not
## hot-reloadable, and it is the same for every Run on this Map. Where the Breaches are *now*
## is a fact about this Run and about what this player chose to dig, so it lives here, it is
## hashed, and `RunSave` carries it. The line between the two is exactly that: `MapLayout`
## owns the opening geography and the canonical order; the Simulation owns the live set.
##
## **New Breaches are inserted in canonical position, never appended.** Enemies are released
## in Breach order, so appending would make which Breach goes first a function of when a
## player dug rather than of geography — and two clients whose Miners finished a craft in a
## different order would then release Enemies in a different sequence. `_insert_breach` is
## the one way anything joins this array.
var _breach_tile_x: PackedInt64Array = PackedInt64Array()
var _breach_tile_y: PackedInt64Array = PackedInt64Array()
var _breach_tile_z: PackedInt64Array = PackedInt64Array()

## The Breaches that have been announced but have not opened yet: where each one will be,
## which tick it was announced on, and how many ticks of its Telegraph are left.
##
## **A Breach is telegraphed before it first spawns, and that is a gate rather than a
## courtesy** — the same rule every Wave obeys. A hole opening silently beside a Factory is
## precisely the ambush the Telegraph exists to prevent (DESIGN.md), and the warning here is
## longer than a Wave's because the answer to a new Breach is a Turret and a Belt rather
## than standing somewhere different.
##
## The announced tick is held so a pending Breach does not spend its first tick of warning on
## the tick it was announced — the same rule a Machine built this tick follows, and held
## explicitly rather than left to where `_breaches_open` sits in `step`.
var _pending_breach_tile_x: PackedInt64Array = PackedInt64Array()
var _pending_breach_tile_y: PackedInt64Array = PackedInt64Array()
var _pending_breach_tile_z: PackedInt64Array = PackedInt64Array()
var _pending_breach_announced_tick: PackedInt64Array = PackedInt64Array()
var _pending_breach_ticks_left: PackedInt64Array = PackedInt64Array()

## Heat: the scalar that measures how much attention the Factory has drawn
## (GLOSSARY.md), and the thing that makes scaling up a bet rather than a free gain.
##
## **A whole number of heat units, and there is no fixed point anywhere in it.** That is
## the central decision of this whole mechanic and it is a determinism decision. Heat
## accumulates continuously across a forty-hour Run, so it is exposed to exactly the
## failure #7 eliminated from Power throttling: a per-tick fixed-point ratio sheds up to
## 2⁻¹⁶ every tick and silently drifts, and a Run that drifted would be a Run whose Waves
## arrived at different times on two clients.
##
## The accumulator's shape, in two halves:
##
## * **In, event-driven.** A completed craft adds a whole number of units, once, at the
##   moment it completes. Crafts are discrete, so this is integer addition and there is
##   nothing to round.
## * **Out, a duty cycle over whole ticks.** The decay is quoted per minute, which is not
##   a whole number of units per tick, so the sub-unit remainder is carried in
##   `_heat_decay_credit` exactly as the Power grid carries kilowatt-ticks: every tick
##   banks `heat.decay_per_minute` credit, and every whole `TICKS_PER_MINUTE` of credit
##   spends one unit of Heat. Over any window the Factory has shed exactly
##   `floor(ticks * decay_per_minute / TICKS_PER_MINUTE)` units — **one floor applied to
##   the total, never one per tick.**
##
## Credit does not survive the Factory going cold, for the reason Power credit does not
## survive demand falling: a Nest that has nothing to hide cannot bank the shedding and
## spend it on a later spike.
var _heat: int = 0
var _heat_decay_credit: int = 0

## Which Wave the Run has reached, how long it is since the last one, how long the
## Telegraph in front of the next one has been showing, and whether a player has called
## it early.
##
## The schedule is **derived from Heat rather than counted down**, which is what makes a
## hot Factory hunted sooner and not merely harder: `_wave_interval_ticks` is a function
## of the Heat the Factory is carrying *right now*, so switching on a new line pulls the
## countdown towards the player on the tick they switch it on. A stored countdown could
## only ever have shortened the Wave after next, which teaches nothing.
var _wave_number: int = 0
var _wave_elapsed_ticks: int = 0

## How many consecutive ticks the Telegraph has been showing. Reset the moment it stops,
## so a Factory that cooled back down loses its warning rather than banking it.
##
## Load-bearing rather than cosmetic: a Wave is not due until this has reached the tuned
## Telegraph length, whatever the interval says and whatever a player called. That is the
## single mechanism behind "the core loop never ambushes the player" (DESIGN.md) — a Heat
## spike cannot pull a Wave out of a clear sky, because the spike shortens the interval
## and the Telegraph still has to run.
var _telegraph_ticks_served: int = 0

## 1 once a player has pulled the call-early lever and until that Wave arrives. An
## integer rather than a bool because every other held flag in this file is one and
## because `RunSave` encodes integers.
var _wave_called_early: int = 0

## The current Wave's release queue: one entry per Enemy each Breach has still to let
## out, as `EnemyKind` integers, and how far through it the Breaches have got.
##
## Composed once when the Wave arrives, out of `content/waves.csv` against the Heat at
## that moment, so a Wave is a fact about how hot the Factory was when it was summoned
## rather than something that keeps re-deciding itself while it spawns. A cursor rather
## than popping the front, because popping a `PackedInt64Array` from the front is O(n)
## and a hot Factory's queue is long.
var _wave_queue_kind: PackedInt64Array = PackedInt64Array()
var _wave_queue_cursor: int = 0

## Ticks until the next Enemy of the current Wave crawls out of its Breach.
var _ticks_until_next_spawn: int = 0

## The tick the Run ended on, or -1 while it is still running.
##
## State rather than `_nest_health <= 0` derived, for two reasons: the moment a Run
## ended is a fact worth reporting next to the Wave it reached, and a later ticket that
## lets a fallen Nest be repaired must not thereby un-end a Run.
var _run_over_tick: int = -1

## The Enemies on the Map. Parallel arrays of integers, **never nodes and never one
## object each** — ADR 0001 makes Godot a renderer, and the ~100-Enemy target DESIGN.md
## sets depends on exactly this: idiomatic engine agents cap out around 150-250 before
## frame times collapse, where instanced array entries reach thousands. Milestone 1
## ships twenty Crawlers; the architecture is sized for the Chaff tier that switches on
## later, because the layout is the part that is expensive to change afterwards.
##
## Positions are fixed-point metres on the horizontal plane, like a player's.
##
## **Index order is spawn order, always.** `_enemy_serial` rises strictly with index,
## entries are only ever appended, and a removal pass preserves the order of the
## survivors. Every loop over Enemies therefore walks them in the one order every
## client agrees on, which is the half of determinism the purity lint cannot check: it
## catches a float, it would never catch an ordering bug.
var _enemy_serial: PackedInt64Array = PackedInt64Array()
var _enemy_kind: PackedInt64Array = PackedInt64Array()
var _enemy_x: PackedInt64Array = PackedInt64Array()
var _enemy_z: PackedInt64Array = PackedInt64Array()
var _enemy_health: PackedInt64Array = PackedInt64Array()
var _enemy_spawn_tick: PackedInt64Array = PackedInt64Array()

## Ticks until each Enemy may bite again. 0 means it bites the moment it is in contact.
var _enemy_attack_cooldown: PackedInt64Array = PackedInt64Array()

## The serial the next Enemy to spawn will carry. Monotonic and never reused, so an
## Enemy has a stable identity across the ticks it exists for even as indices shift
## under it — which is what a Turret needs to keep shooting at the thing it was
## shooting at.
var _next_enemy_serial: int = 0

## The flowfield: one shared vector field over the ground, pointing every tile at the
## Nest.
##
## **One field, not one path each.** Rebuilding this is O(map) once and is then
## amortised across every Enemy alive, where per-agent A* is O(agents x path) every time
## anything moves. Every Enemy converges on the same destination, so the shared field is
## not a compromise — it is strictly the better structure, and DESIGN.md calls it not a
## close call.
##
## `_flow_direction` holds a `WorldGrid` direction per ground tile — the way out of that
## tile towards the Nest — and -1 where there is none: inside the Nest itself, inside an
## obstruction, and on ground the Nest cannot be reached from. `_flow_distance` holds the
## tile count to the Nest, which is what makes "the field routes around this" a thing a
## test can assert rather than infer from where Enemies ended up.
##
## **Derived, so it is rebuilt rather than hashed**, exactly like `_belt_update_order`: a
## pure function of the Map and the obstructions standing on it. Rebuilt when that set
## changes — a Machine built or demolished, a definition reload that could resize a
## footprint — and never on a tick that changed neither.
var _flow_direction: PackedInt64Array = PackedInt64Array()
var _flow_distance: PackedInt64Array = PackedInt64Array()

## Which ground tiles an Enemy cannot walk through, one byte each, rebuilt alongside the
## field it shaped.
##
## Marked by walking the *Machines* and painting their footprints rather than by asking
## every tile on the Map what is standing on it: the first is O(Machines), the second is
## O(tiles x Machines), and at 16641 tiles the second is a visible hitch every time a
## player places something. It doubles as the answer `query_tile_obstructs_enemies` gives,
## so the obstruction set still has exactly one definition.
var _flow_blocked: PackedByteArray = PackedByteArray()
var _flowfield_stale: bool = true

## The Machines standing in the Factory, in the order they were built. Parallel
## arrays rather than objects, so a tick walks integers in index order.
##
## The *id* is held rather than the definition index, because a hot-reload resorts
## the definition table: a Factory already standing must not be renumbered under its
## own feet. The index is a wire detail of the build intent and nothing more.
var _machine_id: PackedStringArray = PackedStringArray()
var _machine_tile_x: PackedInt64Array = PackedInt64Array()
var _machine_tile_y: PackedInt64Array = PackedInt64Array()
var _machine_tile_z: PackedInt64Array = PackedInt64Array()

## Which way each Machine faces, in quarter turns. A quarter or three-quarter turn
## swaps the footprint's extents; the anchor tile does not move. Hashed, because a
## turned Machine covers different ground and presents its ports to different tiles.
var _machine_rotation: PackedInt64Array = PackedInt64Array()

## The tick each Machine was placed on. A Machine does not run on the tick it was
## built: it was placed during that tick, and crediting it a full tick of work for
## the instant it appeared would make a Machine's first output land a tick early.
## Also what a later ticket needs to show a Machine's age.
var _machine_built_tick: PackedInt64Array = PackedInt64Array()

## Ticks accumulated towards the current craft, per Machine. Ticks rather than a
## fixed-point fraction: a craft takes a whole number of ticks, so counting them is
## exact and no rounding accumulates over a 40-hour Run.
var _machine_progress_ticks: PackedInt64Array = PackedInt64Array()

## How much Heat each Machine has added over its whole life, in heat units.
##
## The answer to "what is making me hot", and the reason it is a stock rather than a rate:
## a rate has to be averaged over a window, and a window is either short enough to be
## noise or long enough to be a different Factory. A lifetime total is exact integer state,
## it is hashed, it round-trips, and it is attributable — a player reads it off the
## Machine they built and knows what that decision cost them. The instantaneous rate is
## available too, as a projection (`query_machine_heat_per_minute`), which is where a
## division belongs: in a gauge the Simulation never reads back.
var _machine_heat_units: PackedInt64Array = PackedInt64Array()

## What each Machine is holding, as one sorted `PackedStringArray` of Item ids and
## one matching `PackedInt64Array` of counts per Machine. Item *ids*, not interned
## indices, so a hot-reload that changes the Item set cannot silently relabel a
## buffer. Sorted, so iteration order is a property of the content rather than of
## the order things happened to be produced in.
##
## This is a Machine's own output buffer, the one a Belt loading from its output port
## drains. Uncapped: a producer whose chest fills is a Power-and-Heat-era concern, and the
## back-pressure a player diagnoses is the Belt backing up, not the Miner.
var _machine_buffer_items: Array = []
var _machine_buffer_counts: Array = []

## The Belts in the Factory, in the order they were laid. A Belt is a straight run of
## tiles anchored at the end Items *enter* from, running `tiles` tiles along
## `direction`; the far end is where Items leave. Belts are not Machines (GLOSSARY.md
## keeps the two apart) and have no row in `content/machines.csv`.
var _belt_tile_x: PackedInt64Array = PackedInt64Array()
var _belt_tile_y: PackedInt64Array = PackedInt64Array()
var _belt_tile_z: PackedInt64Array = PackedInt64Array()
var _belt_direction: PackedInt64Array = PackedInt64Array()
var _belt_tiles: PackedInt64Array = PackedInt64Array()

## The Items riding each Belt: one `PackedStringArray` of Item ids and one matching
## `PackedInt64Array` of positions per Belt, ordered front first — the Item nearest the
## far end is slot 0. Arrays of integers rather than an object per Item, because this
## is the system that dominates a late-game frame and an Item is a position and an id
## and nothing else.
##
## A position is a whole number of *sub-units* along the run, not a fixed-point
## distance. Sub-units are sized so that an Item advances exactly one of them per tick
## (see `_belt_subunits_per_tile`), which is what makes throughput an exact function of
## the rating in `content/tuning.toml` rather than something that emerges from
## rounding. Metres are computed only on the way out, for the renderer.
##
## Item *ids* rather than interned Item indices, for the reason a Machine's buffer
## holds ids: a hot-reload resorts the Item set, and relabelling the ore already on a
## Belt would be a silent corruption.
var _belt_item_ids: Array = []
var _belt_item_offsets: Array = []

## The order the Belts are advanced in each tick, and the answer to the one question
## this system cannot dodge: updating Belts in index order would make a line's
## throughput depend on the order it was built in, because a Belt that runs after the
## Belt it feeds sees a slot that has already been vacated while one that runs before
## it does not.
##
## So index order is not used. Each tick walks the Belts **downstream first**: a Belt
## is advanced only after the Belt it hands Items to has been. Chains are followed
## from a canonical starting order — by the entry tile of the run, which is geography
## and not history — and a Belt loop, which has no downstream-most member, is broken at
## its canonically first Belt. Where two Belts merge into one, priority therefore goes to
## whichever starts at the lower tile, rather than to whichever was laid first.
##
## Derived, not authoritative: a pure function of where the Belts are, so it is rebuilt
## rather than hashed. Rebuilt only when a Belt is laid, because nothing else can change
## which Belt feeds which.
var _belt_update_order: PackedInt64Array = PackedInt64Array()
var _belt_update_order_stale: bool = true

## The one Power grid's reading at the end of the tick it last ran: what the Factory's
## generators and its baseline plant between them supplied, and what its working
## Machines between them drew, both in whole kilowatts.
##
## There is exactly one grid and it has no topology — no wires, no sub-networks, no
## distance (GLOSSARY.md, DESIGN.md). Total supply against total demand, globally, and a
## shortfall throttles every Machine in the Factory by the same proportion. That is the
## whole model, and it is the reason a Boiler dying mid-Wave makes every gauge in the base
## dip together instead of killing one Machine.
##
## Kilowatts, as whole integers. The throttle is an exact ratio of these two numbers, so
## keeping them integral is what keeps the ratio from needing a rounding rule at all.
var _power_supply_kw: int = 0
var _power_demand_kw: int = 0

## The grid's unspent supply, in kilowatt-ticks, and the mechanism that makes a
## proportional throttle exact rather than approximately right.
##
## A throttled Machine does not advance a fraction of a tick — fractions accumulate
## rounding, and over a 40-hour Run a rate that is 0.9999 of what the file says is a
## Factory that quietly under-produces. Instead the grid runs a duty cycle: every tick it
## banks `min(supply, demand)` and spends `demand` to buy the Factory one whole tick of
## work. On a grid supplying 1 against a demand of 3, that buys a tick every third tick —
## exactly a third rate, with the remainder carried in this integer rather than thrown
## away. Over any window a Machine has advanced exactly `floor(ticks * supply / demand)`
## ticks: one floor, applied once to the total, never once per tick.
##
## Power is not storable in Milestone 1 — there are no batteries — so this is clamped
## below `demand` rather than allowed to bank a surplus.
var _power_credit_kw_ticks: int = 0

## Whether the grid bought the Factory a tick of work on the tick that last ran. One
## answer for the whole Factory, because there is one grid.
var _power_tick_granted: bool = true

## Which Enemy each Turret is shooting at, **as a serial**, and -1 for one that is not
## shooting at anything. Indexed by Machine, like every other per-Machine array, and 0 for
## a Machine that is not a Turret — there is no second array and no Turret table, because a
## Turret is a Machine (GLOSSARY.md) and giving it its own index space is how a Turret stops
## being one.
##
## **A serial rather than an index, and this is the single most likely determinism bug in
## the whole feature.** Enemy indices shift the moment an Enemy dies: `_remove_enemy` closes
## the gap, so index 4 is a different Crawler after index 2 is killed. A Turret holding an
## index would silently switch targets on another Turret's kill, and two clients whose kills
## landed in a different order — which they may, because a kill is a tick of arithmetic and
## not a message — would diverge. A serial is issued once and never reused, so it either
## names the Crawler it was aimed at or names nothing.
##
## Acquisition walks the Enemies in index order, which is ascending serial by construction,
## and keeps the strictly nearest — so a tie between two equidistant Crawlers goes to the
## earlier spawn on every client, rather than to whichever the iteration happened to reach
## first.
var _turret_target_serial: PackedInt64Array = PackedInt64Array()

## The tick each Turret last fired on, and -1 for one that never has.
##
## State rather than derived, because it is not recoverable from anything else: a shot takes
## no time and leaves nothing behind but a dead Crawler, and whether a Turret just fired is
## what a muzzle flash and a tracer are drawn from. It is also how a test asserts "it did
## not fire" without having to infer that from an Enemy that would have survived anyway.
var _turret_last_shot_tick: PackedInt64Array = PackedInt64Array()

## What each Machine is holding *for* its Recipe, as the same sorted id/count pair as
## the output buffer. A Belt fills this; crafting empties it. Its capacity is what
## back-pressure pushes against: when it is full the Belt feeding it cannot hand over,
## so the Belt fills and stalls where a player can see it.
var _machine_input_items: Array = []
var _machine_input_counts: Array = []


## Builds a Simulation. Two built with the same arguments are indistinguishable,
## which is the property the determinism harness rests on — and that now includes
## the definitions, so "the same arguments" means the same content files too.
##
## Passing no definitions loads the shipped content. A set that failed to load is
## kept as-is rather than replaced by a working-looking default: the errors are
## pushed where a developer will see them, `query_definitions_loaded` reports false,
## and the Godot layer refuses to start a Run. A Simulation that silently invented
## numbers to stay runnable would be worse than one that does nothing.
func _init(
	world_seed: int = 0,
	player_count: int = 1,
	definitions: Definitions = null,
	map_layout: MapLayout = null
) -> void:
	_seed = world_seed
	_rng = DeterministicRng.new(world_seed)

	_definitions = definitions
	if _definitions == null:
		_definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	if _definitions.has_errors():
		push_error("content definitions failed to load:\n%s" % _definitions.describe_errors())

	var layout: MapLayout = map_layout
	if layout == null:
		layout = MapLayout.starter()
	_node_tile_x = layout.node_tile_x.duplicate()
	_node_tile_y = layout.node_tile_y.duplicate()
	_node_tile_z = layout.node_tile_z.duplicate()
	_node_resource = layout.node_resource.duplicate()
	_node_depth = layout.node_depth.duplicate()
	_node_deep_crafts.resize(_node_resource.size())
	_node_deep_crafts.fill(0)
	_node_breach_opened.resize(_node_resource.size())
	_node_breach_opened.fill(0)

	_nest_tile_x = layout.nest_tile.x
	_nest_tile_y = layout.nest_tile.y
	_nest_tile_z = layout.nest_tile.z
	_nest_health = _definitions.nest_health
	_breach_tile_x = layout.breach_tile_x.duplicate()
	_breach_tile_y = layout.breach_tile_y.duplicate()
	_breach_tile_z = layout.breach_tile_z.duplicate()

	var players: int = maxi(player_count, 1)
	_player_x.resize(players)
	_player_z.resize(players)
	_player_x.fill(0)
	_player_z.fill(0)
	_player_yaw.resize(players)
	_player_pitch.resize(players)
	_player_yaw.fill(0)
	_player_pitch.fill(0)
	_player_velocity_x.resize(players)
	_player_velocity_z.resize(players)
	_player_velocity_x.fill(0)
	_player_velocity_z.fill(0)
	_player_intent_forward.resize(players)
	_player_intent_strafe.resize(players)
	_player_intent_forward.fill(0)
	_player_intent_strafe.fill(0)
	_player_survey_held.resize(players)
	_player_sprint_held.resize(players)
	_player_survey_ticks.resize(players)
	_player_survey_held.fill(0)
	_player_sprint_held.fill(0)
	_player_survey_ticks.fill(0)
	_player_build_rotation.resize(players)
	_player_build_rotation.fill(0)
	# The first *unlocked* Machine by id, so a fresh Run has something buildable on the
	# Build Gun rather than something it would refuse. Empty when the definitions failed to
	# load, which is the one case where there is genuinely nothing to hold.
	_player_selected_machine.resize(players)
	_player_selected_machine.fill(_opening_machine())

	# The opening stock, granted once at construction. Deliberately not re-granted on a
	# hot-reload: raising the bill mid-Run must not be a way to conjure materials.
	for player_id: int in range(players):
		_player_item_ids.append(_definitions.player_starting_stock_items.duplicate())
		_player_item_counts.append(_definitions.player_starting_stock_counts.duplicate())

	# A reading before the first tick, so a HUD drawn on tick 0 shows the grid the Run
	# actually starts on rather than a pair of zeroes.
	_read_the_grid()


# ── Advancing ─────────────────────────────────────────────────────────────────

## Advances the Simulation by exactly one tick, applying the given Input Actions.
##
## Whole ticks only — there is no partial step and no delta argument. A caller
## that wants to run at a different speed calls this more or less often, and gets
## bit-identical results either way.
##
## Actions are applied in the order given, before the tick's own updates. Lockstep
## requires every client to see the same order, so the caller is responsible for
## ordering them canonically before they get here.
func step(actions: Array) -> void:
	for action: InputAction in actions:
		_apply(action)

	_walk()
	_survey()
	_transport()
	_deliveries()
	_aim()
	_power()
	_extract()
	_craft()
	_heat_bleeds()
	_breaches_open()
	_waves()
	_enemies()

	_tick += 1


func _apply(action: InputAction) -> void:
	if action == null:
		return

	match action.kind:
		InputAction.Kind.NONE:
			pass
		InputAction.Kind.MOVE:
			_apply_move(action)
		InputAction.Kind.RELOAD_DEFINITIONS:
			_apply_reload_definitions(action)
		InputAction.Kind.BUILD_MACHINE:
			_apply_build_machine(action)
		InputAction.Kind.BUILD_BELT:
			_apply_build_belt(action)
		InputAction.Kind.LOOK:
			_apply_look(action)
		InputAction.Kind.SURVEY_VIEW:
			_apply_survey_view(action)
		InputAction.Kind.SPRINT:
			_player_sprint_held[action.player_id] = 1 if action.sprint_is_held() else 0
		InputAction.Kind.SELECT_MACHINE:
			_apply_select_machine(action)
		InputAction.Kind.ROTATE_BUILD:
			_apply_rotate_build(action)
		InputAction.Kind.DEMOLISH:
			_apply_demolish(action)
		InputAction.Kind.CALL_WAVE_EARLY:
			_apply_call_wave_early(action)
		InputAction.Kind.DELIVER_TO_NEST:
			_apply_deliver_to_nest(action)


## Records the throttle a player asked for this tick. Applying it is `_walk`'s job,
## one tick at a time, so that two intents arriving in one tick cannot double a
## player's acceleration and so that the throttle is read exactly once per tick.
##
## Intent is a direction and throttle in the player's own frame — forward and strafe
## — not a destination and not a world-space direction. The Simulation owns the
## speed, so a malformed or hostile client cannot move faster by sending a bigger
## number, and it owns the *yaw*, so a client cannot walk somewhere other than where
## the Simulation says it is looking either.
func _apply_move(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return

	_player_intent_forward[action.player_id] = action.move_intent_forward()
	_player_intent_strafe[action.player_id] = action.move_intent_strafe()


## Turns the view.
##
## The intent is a count of pixels of mouse travel; the sensitivity that converts it
## into an angle comes from tuning, so a client cannot turn faster by sending a
## larger number and the feel of the mouse is a number in a file.
##
## Yaw wraps, because a player keeps turning and an angle that grew without bound
## would eventually lose precision. Pitch clamps just short of straight up and
## straight down: rolling over the vertical would leave a player facing backwards
## with no idea how they got there.
func _apply_look(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return

	var yaw_delta: int = _look_turns(action.look_pixels_right())
	var pitch_delta: int = _look_turns(action.look_pixels_down())

	# Right is a *decrease* in yaw: a positive rotation about Godot's +y axis turns
	# left. Down is a decrease in pitch, so the sign of each matches the sign of the
	# mouse travel a player intuits.
	_player_yaw[action.player_id] = Fixed.wrap_turns(_player_yaw[action.player_id] - yaw_delta)
	_player_pitch[action.player_id] = Fixed.clamp_fixed(
		_player_pitch[action.player_id] - pitch_delta, -MAX_PITCH_TURNS, MAX_PITCH_TURNS
	)


## Records whether a player is holding Survey View. Moving the camera is `_survey`'s
## job, one tick at a time, so holding the key for n ticks always buys n ticks of lift
## however many times the intent arrives.
func _apply_survey_view(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	_player_survey_held[action.player_id] = 1 if action.survey_is_held() else 0


## How far a count of pixels of mouse travel turns the view, in fixed-point turns.
## One division by a thousand and one multiplication by the tuned sensitivity, both
## floored like every other lossy fixed-point operation.
func _look_turns(pixels: int) -> int:
	return Fixed.mul(
		_definitions.player_look_sensitivity, Fixed.div(pixels, Fixed.from_int(LOOK_PIXEL_UNIT))
	)


# ── Walking ───────────────────────────────────────────────────────────────────

## Moves every player one tick towards the throttle they asked for.
##
## Three steps, in this order: turn the throttle into a world-space velocity the
## player wants, move the velocity they *have* towards it by one tick of
## acceleration, then integrate position. Acceleration rather than an instant change
## is what gives a 1.8 m person weight, and the same figure decelerates them, so
## letting go of the keys is a stop rather than a freeze.
func _walk() -> void:
	var speed: int = _definitions.player_walk_speed
	var acceleration: int = Fixed.div(
		_definitions.player_walk_acceleration, Fixed.from_int(TICKS_PER_SECOND)
	)

	for player_id: int in range(query_player_count()):
		# Sprinting scales the speed a player is reaching for, not their acceleration, so
		# a sprint ramps up over the same time a walk does rather than snapping.
		var player_speed: int = speed
		if _player_sprint_held[player_id] != 0:
			player_speed = Fixed.mul(speed, _definitions.player_sprint_multiplier)
		var wanted: FixedVec2 = _wanted_velocity(player_id, player_speed)

		var gap_x: int = wanted.x - _player_velocity_x[player_id]
		var gap_z: int = wanted.z - _player_velocity_z[player_id]
		var gap: int = _length(gap_x, gap_z)

		if gap <= acceleration:
			# Close enough to land on it exactly. Without this a player would jitter
			# around full speed forever, one acceleration step either side of it.
			_player_velocity_x[player_id] = wanted.x
			_player_velocity_z[player_id] = wanted.z
		else:
			_player_velocity_x[player_id] += Fixed.div(Fixed.mul(gap_x, acceleration), gap)
			_player_velocity_z[player_id] += Fixed.div(Fixed.mul(gap_z, acceleration), gap)

		_player_x[player_id] += Fixed.div(
			_player_velocity_x[player_id], Fixed.from_int(TICKS_PER_SECOND)
		)
		_player_z[player_id] += Fixed.div(
			_player_velocity_z[player_id], Fixed.from_int(TICKS_PER_SECOND)
		)

		# Consumed. A throttle has to be re-asserted every tick, so standing still is
		# the absence of an intent rather than an intent of its own.
		_player_intent_forward[player_id] = 0
		_player_intent_strafe[player_id] = 0


## The world-space velocity a player's throttle asks for, in fixed-point metres per
## second. The throttle is rotated by the yaw the Simulation is holding, and
## normalised first if it is longer than full — forward and strafe at once is a
## throttle of root two, and taking that literally would make the diagonal 41%
## faster, which is the oldest bug in first-person movement.
func _wanted_velocity(player_id: int, speed: int) -> FixedVec2:
	var forward: int = _player_intent_forward[player_id]
	var strafe: int = _player_intent_strafe[player_id]

	var throttle: int = _length(forward, strafe)
	if throttle == 0:
		return FixedVec2.zero()
	if throttle > Fixed.ONE:
		forward = Fixed.div(forward, throttle)
		strafe = Fixed.div(strafe, throttle)

	# Godot's convention, so the renderer needs no second opinion: at yaw 0 forward
	# is -z and right is +x, and a positive yaw rotates both to the left.
	var yaw: int = _player_yaw[player_id]
	var sine: int = Fixed.sin_turns(yaw)
	var cosine: int = Fixed.cos_turns(yaw)

	return FixedVec2.new(
		Fixed.mul(Fixed.mul(forward, -sine) + Fixed.mul(strafe, cosine), speed),
		Fixed.mul(Fixed.mul(forward, -cosine) + Fixed.mul(strafe, -sine), speed)
	)


## The footprint a placed Machine actually occupies, turned by its rotation, as
## (size along x, size along z). Zero when the Machine's definition has gone — which
## a hot-reload that removed a row can do — so callers skip it rather than crash.
func _machine_size(index: int) -> Vector2i:
	if not _is_machine(index):
		return Vector2i.ZERO
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return Vector2i.ZERO
	return WorldGrid.rotated_footprint(
		definition.footprint_x, definition.footprint_z, _machine_rotation[index]
	)


## The tuned Survey View tilt, converted from degrees to turns. Degrees in the file
## because that is how a human reasons about an angle; turns everywhere else because
## radians would need a float.
func _survey_pitch_turns() -> int:
	return Fixed.div(_definitions.survey_pitch_degrees, Fixed.from_int(DEGREES_PER_TURN))


## The length of a fixed-point vector on the horizontal plane.
func _length(x: int, z: int) -> int:
	return Fixed.sqrt(Fixed.mul(x, x) + Fixed.mul(z, z))


# ── Survey View ───────────────────────────────────────────────────────────────

## Advances every player's Survey View transition by one tick: up while the key is
## held, down once it is released.
##
## Symmetric and reversible. Letting go halfway up comes back down from where the
## camera actually got to rather than restarting, which is what stops a quick tap
## reading as a jolt.
func _survey() -> void:
	var span: int = _survey_transition_ticks()
	for player_id: int in range(query_player_count()):
		var progress: int = _player_survey_ticks[player_id]
		progress += 1 if _player_survey_held[player_id] != 0 else -1
		_player_survey_ticks[player_id] = clampi(progress, 0, span)


## How many ticks the Survey View lift takes, from the tuned duration. Rounded rather
## than floored — a duration is a feel number, so 0.4 s should mean the 24 ticks a
## tuner intends rather than the 23 flooring would give — and never less than one,
## because a zero-tick transition is a divide by nothing.
func _survey_transition_ticks() -> int:
	return maxi(
		Fixed.round_to_int(
			Fixed.mul(_definitions.survey_transition_seconds, Fixed.from_int(TICKS_PER_SECOND))
		),
		1
	)


## How far through the Survey View transition a player is, eased, in [0, Fixed.ONE].
func _survey_blend(player_id: int) -> int:
	var span: int = _survey_transition_ticks()
	var progress: int = clampi(_player_survey_ticks[player_id], 0, span)
	return Fixed.smoothstep_fixed(Fixed.div(Fixed.from_int(progress), Fixed.from_int(span)))


# ── Transport ─────────────────────────────────────────────────────────────────

## Advances every Belt by one tick: hand off what has reached the far end, carry
## everything forward, then take one more Item from the Machine port behind.
##
## The Belts are walked **downstream first** (`_belt_update_order`), never in index
## order, so a line's behaviour is a function of its geography and not of the order its
## Belts happened to be laid in.
##
## Belts run before Machines in a tick, so an Item delivered into a Machine's input
## buffer is available to that Machine's craft the same tick, while an Item a Machine
## has just produced waits for the next tick before a Belt collects it — the same
## "placed this tick does not act this tick" rule a freshly built Machine follows.
func _transport() -> void:
	var order: PackedInt64Array = _ordered_belts()
	for position: int in range(order.size()):
		_advance_belt(order[position])


## One Belt, one tick.
##
## Items are held nose to tail, slot 0 nearest the far end, and each one advances
## exactly one sub-unit unless the Item ahead of it — or the end of the run — is in the
## way. That clamp is the whole of back-pressure: nothing is special-cased for a full
## Belt, Items simply pack at their spacing behind whatever has stopped, and the queue
## that forms is the queue the player sees.
func _advance_belt(index: int) -> void:
	var spacing: int = _belt_spacing_subunits()
	var front: int = _belt_front_offset(index)
	var items: PackedStringArray = _belt_item_ids[index]
	var offsets: PackedInt64Array = _belt_item_offsets[index]

	if offsets.size() > 0 and offsets[0] >= front and _hand_off(index, items[0]):
		items.remove_at(0)
		offsets.remove_at(0)

	for slot: int in range(offsets.size()):
		var limit: int = front if slot == 0 else offsets[slot - 1] - spacing
		offsets[slot] = mini(offsets[slot] + 1, limit)

	_belt_item_ids[index] = items
	_belt_item_offsets[index] = offsets

	_load_from_port(index)


## Hands the leading Item off the far end of a Belt, reporting whether it went.
##
## The far end feeds whatever is on the next tile: a Machine's input port, or another
## Belt that *starts* there. A Belt merely passing through that tile is not a
## connection — side-loading onto the middle of a Belt does not exist yet, and a silent
## one would make a line's throughput unexplainable.
##
## Refused when the destination cannot take the Item: a full input buffer, a Machine
## whose Recipe does not want it, a Miner (whose input is the ground), a Belt with no
## room at its entry, or nothing at all. A refusal leaves the Item exactly where it is,
## which is what makes a blockage visible from the outside.
func _hand_off(index: int, item_id: String) -> bool:
	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)

	var machine: int = query_machine_at_tile(beyond)
	if machine != -1:
		return _accept_input(machine, item_id)

	# The Nest takes goods against the Delivery it is waiting on, which is what makes
	# progression something the Factory does rather than something a player carries by
	# hand. It takes only what that tier still wants: there is no store behind the counter,
	# so an Item the open Delivery does not ask for backs the Belt up where a player can see
	# it rather than disappearing into the Nest.
	if _nest_covers(beyond):
		return _accept_delivery(item_id, 1) == 1

	var onward: int = _belt_entered_at(beyond)
	if onward == -1 or not _belt_has_entry_room(onward):
		return false
	_place_on_belt(onward, item_id)
	return true


## Whether a Belt's leading Item has reached the far end and cannot get off it.
##
## The pure twin of `_hand_off`: it asks the destination the same question without moving
## anything, which is what lets a query report a blockage rather than the renderer
## guessing one from a count that stopped changing.
func _hand_off_blocked(index: int) -> bool:
	var items: PackedStringArray = _belt_item_ids[index]
	if items.is_empty():
		return false
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if offsets[0] < _belt_front_offset(index):
		return false

	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)
	var machine: int = query_machine_at_tile(beyond)
	if machine != -1:
		return not _input_has_room(machine, items[0])

	if _nest_covers(beyond):
		return _delivery_would_take(items[0]) == 0

	var onward: int = _belt_entered_at(beyond)
	return onward == -1 or not _belt_has_entry_room(onward)


## Takes one Item from the Machine output port a Belt runs out of, if there is one and
## there is room at the Belt's entry.
##
## The port is the Machine footprint tile the run starts against: Belts connect straight
## into Machine ports and no inserter entity exists (DESIGN.md). Any footprint edge tile
## counts for now; `content/machine_ports.csv` declares the exact edge and tile each port
## sits on, and CLAUDE.md records why the Simulation cannot adopt that table yet and which
## ticket should. The room check is what
## rate-limits loading — an Item can only enter once the last one is a full spacing
## clear, which is exactly the Belt's rated throughput and not a second number that
## could disagree with it.
##
## Which Item, when a Machine holds several: the first in its sorted buffer. Sorted by
## id, so the choice is a property of the content rather than of what was produced
## first.
func _load_from_port(index: int) -> void:
	if not _belt_has_entry_room(index):
		return

	var behind: Vector3i = (
		_belt_entry_tile(index) - WorldGrid.direction_step(_belt_direction[index])
	)
	var machine: int = query_machine_at_tile(behind)
	if machine == -1:
		return

	var items: PackedStringArray = _machine_buffer_items[machine]
	if items.is_empty():
		return
	var item_id: String = items[0]
	_take_from_output(machine, item_id, 1)
	_place_on_belt(index, item_id)


## Whether a Belt has room for another Item at its entry end. True when the hindmost
## Item is at least one spacing clear of the entry, so Items never overlap and a Belt
## never holds more than its capacity.
func _belt_has_entry_room(index: int) -> bool:
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if offsets.is_empty():
		return true
	return offsets[offsets.size() - 1] >= _belt_spacing_subunits()


## Puts an Item on at the entry end of a Belt. The caller has already established there
## is room.
func _place_on_belt(index: int, item_id: String) -> void:
	var items: PackedStringArray = _belt_item_ids[index]
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	items.append(item_id)
	offsets.append(0)
	_belt_item_ids[index] = items
	_belt_item_offsets[index] = offsets


# ── Belt geometry ─────────────────────────────────────────────────────────────
# A Belt's lane is measured in sub-units, sized so that an Item advances exactly one
# per tick. That is what makes throughput exact: one Item leaves a saturated Belt every
# `ticks_per_item` ticks because the spacing between Items is exactly that many
# sub-units, and no rounding enters anywhere. Metres appear only in the queries.

## How many ticks pass between one Item and the next on a saturated Belt. Floored from
## the rating in tuning, and never less than one — a Belt that moved an Item in no time
## would have infinite throughput.
func _belt_ticks_per_item() -> int:
	if _definitions.belt_items_per_second <= 0:
		return 1
	var exact: int = Fixed.div(
		Fixed.from_int(TICKS_PER_SECOND), _definitions.belt_items_per_second
	)
	return maxi(Fixed.floor_to_int(exact), 1)


## How many Items fit on one tile of Belt.
func _belt_items_per_tile() -> int:
	return maxi(_definitions.belt_items_per_tile, 1)


## Sub-units in one tile of Belt. One Item's spacing is `_belt_ticks_per_item()`
## sub-units, and a tile holds `_belt_items_per_tile()` of them.
func _belt_subunits_per_tile() -> int:
	return _belt_items_per_tile() * _belt_ticks_per_item()


## How far apart Items sit on a Belt, in sub-units. Equal to the ticks per Item, which
## is the identity that makes a saturated Belt deliver at exactly its rating.
func _belt_spacing_subunits() -> int:
	return _belt_ticks_per_item()


## The whole length of a Belt's lane in sub-units.
func _belt_lane_subunits(index: int) -> int:
	return _belt_tiles[index] * _belt_subunits_per_tile()


## The furthest an Item can get along a Belt: one spacing short of the end, because an
## Item occupies a spacing's worth of lane rather than a point.
func _belt_front_offset(index: int) -> int:
	return _belt_lane_subunits(index) - _belt_spacing_subunits()


## The last tile of a Belt's run — the end Items leave from.
func _belt_exit_tile(index: int) -> Vector3i:
	return (
		_belt_entry_tile(index)
		+ WorldGrid.direction_step(_belt_direction[index]) * (_belt_tiles[index] - 1)
	)


## The Belt whose run *starts* on a tile, or -1. What a hand-off looks for, so that only
## an end-to-end join counts as a connection.
func _belt_entered_at(tile: Vector3i) -> int:
	for index: int in range(query_belt_count()):
		if _belt_entry_tile(index) == tile:
			return index
	return -1


## The Belt a Belt hands its Items to, or -1 when its far end feeds a Machine or
## nothing. At most one, which is what keeps the update order a chase down each chain
## rather than a general topological sort.
func _belt_downstream(index: int) -> int:
	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)
	if query_machine_at_tile(beyond) != -1:
		return -1
	return _belt_entered_at(beyond)


## Converts a position along a Belt to fixed-point metres.
##
## Takes *twice* the sub-unit count, so that an Item's centre — half a spacing past its
## own position — stays a whole number of half-sub-units and the single division below
## is the only rounding in the whole conversion. Dividing once, at the end, is what
## keeps a 500-tile Belt's far end at exactly 1000 m rather than 999.98 m.
func _subunits_to_metres(doubled_subunits: int) -> int:
	return Fixed.div(
		Fixed.from_int(doubled_subunits * WorldGrid.TILE_SIZE_METRES),
		Fixed.from_int(2 * _belt_subunits_per_tile())
	)


# ── Belt update order ─────────────────────────────────────────────────────────

## The order this tick advances the Belts in, downstream first.
func _ordered_belts() -> PackedInt64Array:
	if _belt_update_order_stale:
		_rebuild_belt_update_order()
	return _belt_update_order


## Rebuilds the downstream-first order.
##
## Each Belt feeds at most one other, so the graph is a set of chains and loops rather
## than an arbitrary one, and the order falls out of walking each chain to its end and
## recording it backwards. Chains are started in canonical tile order, so the result is
## a function of where the Belts are. A loop — every member feeding another member — is
## entered at its canonically first Belt and that is where the cycle is cut; one join in
## a Belt loop therefore carries a tick of latency, which is the price of a loop having
## no downstream-most member to start from.
func _rebuild_belt_update_order() -> void:
	var count: int = query_belt_count()
	var starts: Array = []
	for index: int in range(count):
		starts.append(index)
	starts.sort_custom(func(a: int, b: int) -> bool: return _belt_precedes(a, b))

	# 0 not reached, 1 on the chain being walked, 2 placed in the order.
	var visited: PackedInt64Array = PackedInt64Array()
	visited.resize(count)
	visited.fill(0)

	var order: PackedInt64Array = PackedInt64Array()
	for start: int in starts:
		if visited[start] != 0:
			continue
		var chain: PackedInt64Array = PackedInt64Array()
		var current: int = start
		while current != -1 and visited[current] == 0:
			visited[current] = 1
			chain.append(current)
			current = _belt_downstream(current)
		for position: int in range(chain.size() - 1, -1, -1):
			visited[chain[position]] = 2
			order.append(chain[position])

	_belt_update_order = order
	_belt_update_order_stale = false


## Canonical order over Belts: by the tile their run starts at, layer then x then z.
## Geography, so it cannot depend on build order. Total, because no two Belts share a
## tile.
func _belt_precedes(a: int, b: int) -> bool:
	if _belt_tile_y[a] != _belt_tile_y[b]:
		return _belt_tile_y[a] < _belt_tile_y[b]
	if _belt_tile_x[a] != _belt_tile_x[b]:
		return _belt_tile_x[a] < _belt_tile_x[b]
	return _belt_tile_z[a] < _belt_tile_z[b]


# ── Power ─────────────────────────────────────────────────────────────────────

## Reads the one Power grid and decides whether it can buy the Factory this tick.
##
## Runs after the Belts and before the Machines, so a lump of coal delivered to a Boiler
## this tick is already burning when the grid is read — the same "delivered this tick is
## usable this tick" rule a crafter's inputs follow.
##
## A shortfall throttles proportionally and picks no favourites: there is one grid, one
## ratio, and every Machine drawing from it advances on the same ticks. Nothing is halted
## outright and nothing is singled out, which is what makes a brownout read as the whole
## Factory sagging together rather than as one Machine mysteriously dead.
func _power() -> void:
	_read_the_grid()

	if _power_demand_kw <= 0:
		# Nothing is drawing, so there is nothing to ration and nothing to carry over.
		_power_credit_kw_ticks = 0
		_power_tick_granted = true
		return

	# Power is not storable: a grid whose demand just fell cannot have been banking the
	# difference, so credit never exceeds one tick's worth of demand.
	_power_credit_kw_ticks = mini(_power_credit_kw_ticks, maxi(_power_demand_kw - 1, 0))
	_power_credit_kw_ticks += mini(_power_supply_kw, _power_demand_kw)

	_power_tick_granted = _power_credit_kw_ticks >= _power_demand_kw
	if _power_tick_granted:
		_power_credit_kw_ticks -= _power_demand_kw


## Totals the grid: what is supplied, and what is drawn.
##
## Demand counts a Machine only while it would actually work. A Smelter with an empty
## input buffer is not consuming anything, so it is not on the grid either — which means
## cutting a Belt lightens the load rather than browning out the Machines that are still
## fed, and the gauge a player reads is the Factory that is running rather than the
## Factory that was built.
func _read_the_grid() -> void:
	var supply: int = _definitions.power_baseline_supply_kw
	var demand: int = 0
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not _machine_would_work(index, definition):
			continue
		supply += definition.power_supply_kw
		demand += _depth_adjusted_draw_kw(index, definition)
	_power_supply_kw = supply
	_power_demand_kw = demand


## What a Machine actually draws from the one grid: its quoted draw, plus what Depth adds.
##
## **Deeper ore costs proportionally more Power** (GLOSSARY.md), and this is the only place
## that is decided. The first tier draws exactly what `content/machines.csv` says, and every
## tier past it adds `depth.draw_percent_per_depth` of that figure — so the cost scales with
## the Machine rather than being a flat surcharge that a big Miner would shrug off and a
## small one would choke on.
##
## Whole kilowatts, with the one division floored and **applied to the total rather than
## accumulated**: this is recomputed from scratch every tick out of two integers from the
## definitions, so unlike the Power credit and the Heat decay there is nothing here that
## could drift. That is the same reason `_wave_interval_ticks` is derived rather than stored.
##
## Only a Miner has a Depth; a crafter, a generator and a Turret draw what their row says.
func _depth_adjusted_draw_kw(index: int, definition: MachineDefinition) -> int:
	var base: int = definition.power_draw_kw
	if base <= 0 or not definition.is_miner():
		return base
	var node_index: int = _node_under_machine(index, definition)
	if node_index == -1:
		return base
	var tiers_past_the_first: int = maxi(_node_depth[node_index] - 1, 0)
	@warning_ignore("integer_division")
	var surcharge: int = (
		base * _definitions.depth_draw_percent_per_depth * tiers_past_the_first / 100
	)
	return base + surcharge


## Whether a Machine has everything it needs to advance a craft this tick, leaving Power
## out of it. The shared answer behind three questions that must never disagree: what the
## grid charges for, what `_extract` and `_craft` advance, and — through
## `_machine_has_its_inputs` — what a query calls starved.
##
## A Machine placed this tick would not work this tick, which is the rule that keeps a
## freshly built Machine's first output from landing a tick early. Starvation deliberately
## does *not* ask that question: a Miner put down on a Node is not starved, it is new.
func _machine_would_work(index: int, definition: MachineDefinition) -> bool:
	if _machine_built_tick[index] == _tick:
		return false
	if _definitions.recipe_at(definition.recipe_index) == null:
		return false
	# A Turret with nothing in reach does not work, which means it does not draw Power, does
	# not advance its Recipe and does not spend a round. A Turret is therefore idle between
	# Waves for the same reason a Smelter with an empty Belt is: there is nothing for it to
	# do. Deliberately *not* starvation — it has its Ammunition, it has no target.
	if definition.is_turret() and _turret_target_index(index, definition) == -1:
		return false
	return _machine_has_its_inputs(index, definition)


## Whether a Machine is holding what its Recipe needs. A Miner's input is the ground under
## it, a crafter's and a generator's arrives on a Belt.
func _machine_has_its_inputs(index: int, definition: MachineDefinition) -> bool:
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return false
	if definition.is_miner():
		var node_index: int = _node_under_machine(index, definition)
		if node_index == -1 or not _miner_reaches(definition, node_index):
			return false
		return _recipe_yields(recipe, _node_resource[node_index])
	return _holds_a_whole_recipe(index, recipe)


## Whether a Miner's tier reaches the Depth a Node sits at.
##
## `max_depth` in `content/machines.csv` is the whole of a Miner's tier, so a Miner that
## reaches deeper is a **row** and never a code change (GLOSSARY.md: different Miners reach
## different Depths). The comparison is the only place the number is read, and it is read
## through `_machine_has_its_inputs`, so a Miner over ore it cannot reach is **starved** —
## not throttled, not halted, and not quietly banking progress. That matters three ways at
## once: it draws no Power, it advances no craft, and `query_machine_is_starved` already
## says so, which is the same treatment a Miner on bare rock gets. A Miner over ore it
## cannot lift is visibly doing nothing, which is the only honest reading of it.
func _miner_reaches(definition: MachineDefinition, node_index: int) -> bool:
	return _node_depth[node_index] <= definition.max_depth


## Whether the grid lets a given Machine advance this tick.
##
## A Machine that draws nothing is never throttled: a Steam Boiler burns its coal at the
## rate its Recipe states whatever the grid is doing, which is what stops a brownout from
## throttling the very generators that would end it.
func _power_allows(definition: MachineDefinition) -> bool:
	if definition.power_draw_kw <= 0:
		return true
	return _power_tick_granted


# ── Extraction ────────────────────────────────────────────────────────────────

## Advances every Miner by one tick.
##
## A Miner's input is the ground it stands on: it produces only while its footprint
## covers a Node whose Resource its Recipe produces, and otherwise sits idle without
## accumulating progress — so a Miner placed on bare rock is visibly doing nothing
## rather than invisibly banking time against a Node it might get later.
##
## Nothing is subtracted from the Node. Nodes are inexhaustible (DESIGN.md), which is
## why there is no quantity here to take.
##
## A Miner on a short grid is slowed, not stopped: the grid buys the whole Factory a tick
## of work or none of one, so a throttled Miner accumulates progress on a fraction of the
## ticks and a Belt running out of it visibly thins.
##
## Walks Machines in index order, which is construction order and therefore the same
## on every client.
func _extract() -> void:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not definition.is_miner():
			continue
		if not _machine_would_work(index, definition):
			continue
		if not _power_allows(definition):
			continue

		var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
		var required: int = _ticks_per_craft(recipe)
		_machine_progress_ticks[index] += 1
		while _machine_progress_ticks[index] >= required:
			_machine_progress_ticks[index] -= required
			_deposit_outputs(index, recipe)
			_note_a_craft(index, definition)
			_note_a_deep_craft(index, definition)


# ── Crafting ──────────────────────────────────────────────────────────────────

## Advances every crafting Machine by one tick.
##
## A crafter's inputs arrive on a Belt, so unlike a Miner it can be starved. A starved
## Machine banks nothing: it does not accumulate a part-craft while it waits for the
## second half of its Recipe, because a Machine that did would pay out the instant its
## inputs landed and a line's first output would appear earlier than the line can
## actually support.
##
## Inputs are consumed when the craft completes rather than when it starts. Either rule
## is defensible; this one keeps "what the Machine is holding" equal to "what a player
## would get back if they knocked it down", and it means a Recipe's duration is the only
## thing between an input arriving and an output appearing.
##
## Power throttles this the same way it throttles extraction, and for the same reason it
## does not throttle a generator: a Machine that draws nothing from the grid is never held
## back by it, so a Steam Boiler burns its coal at the rate its Recipe states even in the
## brownout it is trying to end.
##
## Walks Machines in index order, which is construction order and therefore the same on
## every client. Index order is safe here in a way it is not for Belts: a Machine's tick
## reads and writes only its own buffers, so no Machine can observe another's progress
## within a tick.
func _craft() -> void:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or definition.is_miner():
			continue
		if not _machine_would_work(index, definition):
			continue
		if not _power_allows(definition):
			continue

		var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
		var required: int = _ticks_per_craft(recipe)
		_machine_progress_ticks[index] += 1
		while _machine_progress_ticks[index] >= required:
			_machine_progress_ticks[index] -= required
			_consume_inputs(index, recipe)
			_deposit_outputs(index, recipe)
			_note_a_craft(index, definition)
			# A Turret's Recipe has no outputs to deposit, so this is the whole of what a
			# completed craft does for one: the shot is the output. The round was consumed
			# the line above, which is what makes a Turret that fired a Turret with one
			# fewer round and a Turret that did not fire a Turret still holding it.
			if definition.is_turret():
				_fire(index, definition)
			if not _holds_a_whole_recipe(index, recipe):
				break


## Whether a Machine is holding every input its Recipe needs, in the quantity it needs.
## A Recipe with no inputs is always satisfied — that is a Miner's Recipe, and the
## ground is its input.
func _holds_a_whole_recipe(index: int, recipe: RecipeDefinition) -> bool:
	for slot: int in range(recipe.input_count()):
		var item_id: String = _definitions.item_id(recipe.input_item(slot))
		if item_id.is_empty():
			return false
		if query_machine_input(index, item_id) < recipe.input_quantity(slot):
			return false
	return true


## Takes one craft's inputs out of a Machine's input buffer.
func _consume_inputs(index: int, recipe: RecipeDefinition) -> void:
	for slot: int in range(recipe.input_count()):
		var item_id: String = _definitions.item_id(recipe.input_item(slot))
		if item_id.is_empty():
			continue
		_take_from_input(index, item_id, recipe.input_quantity(slot))


## How many whole ticks one craft takes. A Recipe states its duration in seconds
## because that is how a human reasons about a rate; a tick is the Simulation's only
## unit of time, so the conversion happens once, here, and floors like every other
## lossy operation. A Recipe faster than one tick still takes one: a craft that took
## no time would produce infinitely.
func _ticks_per_craft(recipe: RecipeDefinition) -> int:
	var exact: int = Fixed.mul(recipe.duration_seconds, Fixed.from_int(TICKS_PER_SECOND))
	return maxi(Fixed.floor_to_int(exact), 1)


## The Node a Machine's footprint covers, or -1. A footprint covering two Nodes takes
## the lowest-indexed one, which is the canonical order `MapLayout` sorted them into.
func _node_under_machine(index: int, definition: MachineDefinition) -> int:
	var origin: Vector3i = query_machine_tile(index)
	var size: Vector2i = WorldGrid.rotated_footprint(
		definition.footprint_x, definition.footprint_z, _machine_rotation[index]
	)
	for node_index: int in range(query_node_count()):
		if WorldGrid.footprint_covers(origin, size.x, size.y, query_node_tile(node_index)):
			return node_index
	return -1


## Whether a Recipe produces a given Item id.
func _recipe_yields(recipe: RecipeDefinition, item_id: String) -> bool:
	for slot: int in range(recipe.output_count()):
		if _definitions.item_id(recipe.output_item(slot)) == item_id:
			return true
	return false


## Adds one craft's outputs to a Machine's own output buffer, which is what a Belt running
## out of its port drains. Deliberately uncapped: capping it would stop a Node proving
## itself inexhaustible, and the back-pressure this milestone is about is the Belt filling
## against a full *input* port, which is capped.
func _deposit_outputs(index: int, recipe: RecipeDefinition) -> void:
	for slot: int in range(recipe.output_count()):
		var item_id: String = _definitions.item_id(recipe.output_item(slot))
		if item_id.is_empty():
			continue
		_add_to_buffer(index, item_id, recipe.output_quantity(slot))


## Adds to a Machine's buffer, keeping the Item ids sorted so the buffer's order is a
## property of the content rather than of the order things were produced in.
func _add_to_buffer(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_buffer_items[index]
	var counts: PackedInt64Array = _machine_buffer_counts[index]

	var slot: int = items.find(item_id)
	if slot != -1:
		counts[slot] += quantity
		return

	var insert_at: int = items.size()
	for existing: int in range(items.size()):
		if item_id < items[existing]:
			insert_at = existing
			break
	items.insert(insert_at, item_id)
	counts.insert(insert_at, quantity)
	_machine_buffer_items[index] = items
	_machine_buffer_counts[index] = counts


## Takes Items back out of a Machine's output buffer, which is what a Belt loading from
## its port does. An Item id that runs to zero is removed rather than left at zero: a
## buffer listing an Item it does not have would make a Machine look like it is holding
## something it is not.
func _take_from_output(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_buffer_items[index]
	var counts: PackedInt64Array = _machine_buffer_counts[index]

	var slot: int = items.find(item_id)
	if slot == -1:
		return
	counts[slot] -= quantity
	if counts[slot] <= 0:
		items.remove_at(slot)
		counts.remove_at(slot)
	_machine_buffer_items[index] = items
	_machine_buffer_counts[index] = counts


# ── Turrets: aiming, and firing ───────────────────────────────────────────────
# The keystone loop, and deliberately the smallest amount of code that could implement it.
# There is no combat subsystem here: a Turret is a Machine whose Recipe consumes Ammunition
# and produces no Item, `_craft` advances it exactly as it advances a Smelter, and the only
# thing this section adds is *what happens instead of depositing an output* — a shot.
#
# Which is why a Cannon Turret is a row in `content/machines.csv` and nothing else. Its
# reach, its hit and its round are `range_tiles`, `damage` and its Recipe; none of the three
# is named anywhere in this file.

## Points every Turret at something, once a tick, before the grid is read.
##
## Before the grid on purpose: a Turret with nothing to shoot at would not work this tick, so
## it must not be on the Power grid this tick either — the same rule that keeps a starved
## Smelter off it. `_machine_would_work` asks this section the question and `_read_the_grid`
## asks `_machine_would_work`, so what the grid charges for, what advances, and what fires
## are one answer and not three.
##
## A Turret that already holds a live target in reach keeps it. That is what makes a Turret
## finish what it started rather than re-deciding every tick and drifting between two
## Crawlers a metre apart, and it is why the target is held as a serial: the index it sits at
## changes under it every time anything dies.
func _aim() -> void:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not definition.is_turret():
			continue
		if _turret_target_index(index, definition) != -1:
			continue
		_turret_target_serial[index] = _acquire_target(index, definition)


## The Enemy a Turret is currently shooting at, as an *index*, or -1 when it is shooting at
## nothing: it holds no serial, the Enemy that serial named is dead, or that Enemy has walked
## out of reach.
##
## A pure read, which it has to be: `_machine_would_work` consults it and
## `query_machine_is_throttled` consults that, and a query that re-aimed a Turret would move
## the state hash by being asked a question.
##
## A Run that has ended points every Turret at nothing, for the reason Waves and Enemies
## stop: the game is over, and a Factory still firing into a frozen swarm would keep drawing
## Power and burning Ammunition after the fact.
func _turret_target_index(index: int, definition: MachineDefinition) -> int:
	if query_run_is_over():
		return -1
	var serial: int = _turret_target_serial[index]
	if serial < 0:
		return -1
	var found: int = _enemy_of_serial(serial)
	if found == -1 or _enemy_health[found] <= 0:
		return -1
	if not _within_reach(index, definition, found):
		return -1
	return found


## The serial of the nearest Enemy within a Turret's reach, or -1 when there is none.
##
## Walked in Enemy index order, which is ascending spawn serial by construction, and kept on
## a **strict** improvement — so two Crawlers exactly as far away hand the shot to the one
## that spawned first, on every client, rather than to whichever the loop reached first under
## some other ordering. That is the whole of what makes target selection replay identically.
func _acquire_target(index: int, definition: MachineDefinition) -> int:
	var centre: FixedVec2 = _machine_centre_metres(index)
	var within: int = _squared_reach(definition)
	var best: int = -1
	var best_gap: int = 0
	for enemy: int in range(query_enemy_count()):
		if _enemy_health[enemy] <= 0:
			continue
		var gap: int = _squared_gap(centre, enemy)
		if gap > within:
			continue
		if best == -1 or gap < best_gap:
			best = enemy
			best_gap = gap
	if best == -1:
		return -1
	return _enemy_serial[best]


## Whether an Enemy is inside a Turret's reach.
func _within_reach(index: int, definition: MachineDefinition, enemy: int) -> bool:
	return _squared_gap(_machine_centre_metres(index), enemy) <= _squared_reach(definition)


## A Turret's reach *squared*, in squared fixed-point metres.
##
## Squared, and compared against a squared distance, because the alternative is a square
## root — and `Fixed.sqrt` floors, which would make a Crawler exactly on the boundary
## in reach or out of it depending on a rounding rule. Multiplying both sides instead is
## exact integer arithmetic with no rounding anywhere, which is what a range check inside a
## lockstep Simulation has to be. The products stay far inside 64 bits: the Map is 129 tiles
## across, so the largest distance squared is about 1.4e14 against a 9.2e18 ceiling.
func _squared_reach(definition: MachineDefinition) -> int:
	var reach: int = Fixed.from_int(definition.range_tiles * WorldGrid.TILE_SIZE_METRES)
	return reach * reach


## How far an Enemy is from a point, squared, in the same squared fixed-point metres
## `_squared_reach` returns. Deliberately not passed through `Fixed.mul`, which would shift
## the scale back down and floor on the way: nothing compares this against a plain distance,
## so the larger scale costs nothing and keeps the comparison exact.
func _squared_gap(from: FixedVec2, enemy: int) -> int:
	var gap_x: int = _enemy_x[enemy] - from.x
	var gap_z: int = _enemy_z[enemy] - from.z
	return gap_x * gap_x + gap_z * gap_z


## The middle of a Machine's footprint, in fixed-point metres on the horizontal plane.
##
## A Turret measures its reach from here rather than from its anchor tile, so turning a 2x3
## Turret a quarter does not move the circle it covers. Exact: a tile centre is a whole
## number of metres, so the average of two of them lands on a half-metre at worst and fixed
## point holds that precisely.
func _machine_centre_metres(index: int) -> FixedVec2:
	var size: Vector2i = _machine_size(index)
	var anchor: Vector3i = query_machine_tile(index)
	var near: FixedVec2 = WorldGrid.tile_centre_metres(anchor)
	var far: FixedVec2 = WorldGrid.tile_centre_metres(
		Vector3i(anchor.x + maxi(size.x - 1, 0), anchor.y, anchor.z + maxi(size.y - 1, 0))
	)
	var two: int = Fixed.from_int(2)
	return FixedVec2.new(Fixed.div(near.x + far.x, two), Fixed.div(near.z + far.z, two))


## The Enemy carrying a serial, or -1 when it is dead or never existed.
##
## A binary search rather than a scan, and it is exact rather than approximately right:
## `_enemy_serial` is strictly ascending with index by construction (spawns append, removals
## preserve order), which is the same invariant every loop over Enemies depends on.
func _enemy_of_serial(serial: int) -> int:
	var at: int = _enemy_serial.bsearch(serial)
	if at < 0 or at >= _enemy_serial.size() or _enemy_serial[at] != serial:
		return -1
	return at


## One shot: what a Turret does instead of depositing an output.
##
## Called from `_craft` on the tick a craft completes, after its Ammunition has been consumed
## — so a Turret that fired has spent a round, and a Turret that did not has not. The Recipe
## decides the rate and the rounds per shot; `machines.csv` decides the hit.
##
## An Enemy reduced to nothing is removed here and now rather than at the end of the tick.
## That is what stops a second Turret later in the same loop from spending a round on a
## corpse: the serial it is holding no longer resolves, so `_machine_would_work` reports it
## idle and it keeps its Ammunition for the next tick.
func _fire(index: int, definition: MachineDefinition) -> void:
	var target: int = _turret_target_index(index, definition)
	if target == -1:
		return
	_turret_last_shot_tick[index] = _tick
	_enemy_health[target] = maxi(_enemy_health[target] - definition.damage, 0)
	if _enemy_health[target] == 0:
		_remove_enemy(target)


## Takes an Enemy off the Map, preserving the order of the survivors — which is the invariant
## that keeps Enemy index order equal to ascending spawn serial, and therefore keeps every
## loop over Enemies the same on every client.
func _remove_enemy(index: int) -> void:
	var serial: int = _enemy_serial[index]
	_enemy_serial.remove_at(index)
	_enemy_kind.remove_at(index)
	_enemy_x.remove_at(index)
	_enemy_z.remove_at(index)
	_enemy_health.remove_at(index)
	_enemy_spawn_tick.remove_at(index)
	_enemy_attack_cooldown.remove_at(index)
	_forget_target(serial)


## Clears a dead Enemy's serial off every Turret holding it, so that
## `query_turret_target_serial` either names something alive or names nothing. A stale serial
## would be just as deterministic — it resolves to -1 and the Turret re-aims next tick — but
## it would make the state hash carry the ghost of a Crawler, and a saved Run would restore
## one.
func _forget_target(serial: int) -> void:
	for index: int in range(query_machine_count()):
		if _turret_target_serial[index] == serial:
			_turret_target_serial[index] = -1


## How many Items a Turret is holding for its Recipe: its magazine, in rounds.
func _turret_ammunition(index: int) -> int:
	if not _is_turret(index):
		return 0
	return query_machine_input_total(index)


## Whether a Machine is a Turret. False for an unknown index and for one whose definition a
## hot-reload took away.
func _is_turret(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return definition != null and definition.is_turret()


# ── Machine input ports ───────────────────────────────────────────────────────

## Puts one Item into a Machine's input buffer, reporting whether it fitted.
##
## This is the back-pressure boundary. A refusal here is what stops a Belt handing over,
## which is what makes the Belt fill up, which is what the player sees. So every reason
## to refuse is a reason the Factory is visibly backed up: a Machine that does not run
## the Item's Recipe, a Miner (whose input is the ground under it, not a port), and a
## buffer already at capacity.
func _accept_input(index: int, item_id: String) -> bool:
	if not _input_has_room(index, item_id):
		return false
	_add_to_input(index, item_id, 1)
	return true


## Whether a Machine's input port would take one more of an Item. The pure half of
## `_accept_input`, so that a query can ask the same question a hand-off asks without
## moving anything.
func _input_has_room(index: int, item_id: String) -> bool:
	var capacity: int = _input_capacity(index, item_id)
	if capacity <= 0:
		return false
	return query_machine_input(index, item_id) < capacity


## How much of an Item a Machine will hold for its Recipe, and 0 for an Item its Recipe
## has no use for. A capacity in crafts rather than in Items, so a Recipe that eats two
## ore a craft buffers twice what one eating a single ore does without anyone tuning the
## two separately.
func _input_capacity(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or definition.is_miner():
		return 0
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return 0
	for slot: int in range(recipe.input_count()):
		if _definitions.item_id(recipe.input_item(slot)) == item_id:
			return recipe.input_quantity(slot) * maxi(_definitions.machine_input_buffer_crafts, 1)
	return 0


## Adds to a Machine's input buffer, sorted by Item id for the same reason the output
## buffer is.
func _add_to_input(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_input_items[index]
	var counts: PackedInt64Array = _machine_input_counts[index]

	var slot: int = items.find(item_id)
	if slot != -1:
		counts[slot] += quantity
		_machine_input_counts[index] = counts
		return

	var insert_at: int = items.size()
	for existing: int in range(items.size()):
		if item_id < items[existing]:
			insert_at = existing
			break
	items.insert(insert_at, item_id)
	counts.insert(insert_at, quantity)
	_machine_input_items[index] = items
	_machine_input_counts[index] = counts


## Takes Items out of a Machine's input buffer, dropping an id that runs to zero.
func _take_from_input(index: int, item_id: String, quantity: int) -> void:
	var items: PackedStringArray = _machine_input_items[index]
	var counts: PackedInt64Array = _machine_input_counts[index]

	var slot: int = items.find(item_id)
	if slot == -1:
		return
	counts[slot] -= quantity
	if counts[slot] <= 0:
		items.remove_at(slot)
		counts.remove_at(slot)
	_machine_input_items[index] = items
	_machine_input_counts[index] = counts


## Puts a Machine on a player's Build Gun.
##
## An index naming no Machine is refused and the previous choice stands, because a
## selection that silently became "nothing" would leave a player clicking at a
## hologram that was not there.
func _apply_select_machine(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var definition: MachineDefinition = _definitions.machine_at(action.selected_machine_index())
	if definition == null:
		return
	_player_selected_machine[action.player_id] = definition.id


## Turns a player's Build Gun by a signed number of quarter turns.
func _apply_rotate_build(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	_player_build_rotation[action.player_id] = WorldGrid.wrap_rotation(
		_player_build_rotation[action.player_id] + action.rotation_quarter_turns()
	)


## Places a Machine, or refuses to.
##
## Refused when the action names no Machine, when any tile of the footprint is
## unbuildable — off the Map, or off layer 0 while building is flat — or when the
## footprint overlaps a Machine that is already there. A refusal is a no-op: nothing
## is placed, nothing is logged at error level, and the hash does not move, because a
## misaimed Build Gun is an ordinary thing for a player to do.
##
## The footprint comes from `content/machines.csv` and from nowhere else. There is
## deliberately no second copy of those numbers in this file.
func _apply_build_machine(action: InputAction) -> void:
	var rotation: int = WorldGrid.wrap_rotation(action.build_rotation())
	var tile: Vector3i = action.build_tile()

	if _build_refusal(action.player_id, action.build_machine_index(), tile, rotation) != Refusal.NONE:
		return

	var definition: MachineDefinition = _definitions.machine_at(action.build_machine_index())
	for index: int in range(definition.build_cost_items.size()):
		_take_from_player(
			action.player_id,
			definition.build_cost_items[index],
			definition.build_cost_counts[index]
		)

	_machine_id.append(definition.id)
	_machine_rotation.append(rotation)
	_machine_tile_x.append(tile.x)
	_machine_tile_y.append(tile.y)
	_machine_tile_z.append(tile.z)
	_machine_built_tick.append(_tick)
	_machine_progress_ticks.append(0)
	_machine_heat_units.append(0)
	_machine_buffer_items.append(PackedStringArray())
	_machine_buffer_counts.append(PackedInt64Array())
	_machine_input_items.append(PackedStringArray())
	_machine_input_counts.append(PackedInt64Array())
	# Every Machine gets an entry, Turret or not, so the per-Machine arrays stay parallel and
	# an index means the same thing in all of them. -1 is "shooting at nothing", which is also
	# what a Smelter is doing.
	_turret_target_serial.append(-1)
	_turret_last_shot_tick.append(-1)
	# A new footprint is a new obstruction, so the Enemies' shared field no longer
	# describes the Map. Rebuilt on the next tick that has an Enemy to move, never here:
	# a player laying out a Factory places a Machine a second and the field is O(map).
	_flowfield_stale = true


## Why a placement would be refused, or `Refusal.NONE`.
##
## The single authority on whether a build is legal. `_apply_build_machine` obeys it
## and `query_build_refusal` reports it, so what a player is told and what the
## Simulation does are the same rule rather than two copies of it.
func _build_refusal(player_id: int, machine_index: int, tile: Vector3i, rotation: int) -> int:
	var definition: MachineDefinition = _definitions.machine_at(machine_index)
	if definition == null:
		return Refusal.NO_SUCH_MACHINE
	# Before the ground and before the wallet, because being locked is a fact about the
	# Machine rather than about the tile: a player holding something they have not unlocked
	# has the same problem wherever they aim it, and telling them about the tile first would
	# send them walking. A locked Machine may still be put on the Build Gun — the hologram
	# asks this function every frame about the tile it is over, so the reason is on screen
	# before the click, which is the only version that leaves the hash alone.
	if not _machine_is_unlocked(definition.id):
		return Refusal.CONTENT_IS_LOCKED

	var size: Vector2i = WorldGrid.rotated_footprint(
		definition.footprint_x, definition.footprint_z, WorldGrid.wrap_rotation(rotation)
	)
	if not WorldGrid.footprint_is_buildable(tile, size.x, size.y):
		return Refusal.OFF_THE_MAP
	if _footprint_is_occupied(tile, size.x, size.y):
		return Refusal.OCCUPIED
	# The ground before the wallet: a player aiming at a wall has a more immediate
	# problem than an empty pocket, and one they can fix by aiming somewhere else.
	if not _can_pay_for(player_id, definition):
		return Refusal.MISSING_MATERIALS
	return Refusal.NONE


## Whether a player is carrying everything a Machine costs to build.
func _can_pay_for(player_id: int, definition: MachineDefinition) -> bool:
	if not _is_player(player_id):
		return false
	for index: int in range(definition.build_cost_items.size()):
		var held: int = query_player_item(player_id, definition.build_cost_items[index])
		if held < definition.build_cost_counts[index]:
			return false
	return true


## Whether a footprint would overlap something already placed — a Machine or a Belt.
## Walks both in index order, which is cheap at Milestone 1 scale and ordered by
## construction.
func _footprint_is_occupied(origin: Vector3i, size_x: int, size_z: int) -> bool:
	var nest: Vector2i = query_nest_footprint()
	if WorldGrid.footprints_overlap(
		origin, size_x, size_z, query_nest_tile(), nest.x, nest.y
	):
		return true
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null:
			continue
		var standing: Vector2i = _machine_size(index)
		if WorldGrid.footprints_overlap(
			origin, size_x, size_z, query_machine_tile(index), standing.x, standing.y
		):
			return true
	for offset_x: int in range(size_x):
		for offset_z: int in range(size_z):
			var tile: Vector3i = Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z)
			if query_belt_at_tile(tile) != -1:
				return true
	return false


# ── Demolishing ───────────────────────────────────────────────────────────

## Takes a Machine or a Belt back apart, returning its materials to the player.
##
## Nothing is destroyed. A Machine hands back its build cost in full *and* whatever it
## was holding in either buffer; a Belt hands back the Items riding it. A Belt has no
## build cost to return because it has no row in `content/machines.csv` — it is not a
## Machine (GLOSSARY.md), and its one tier's rating lives in tuning. Giving Belts a
## cost belongs to the ticket that gives them tiers.
##
## A Machine is demolished by pointing at any tile of its footprint rather than at its
## anchor, because a player aiming a Build Gun is aiming at a Machine and not at a
## coordinate.
func _apply_demolish(action: InputAction) -> void:
	var tile: Vector3i = action.demolish_tile()
	if _demolish_refusal(action.player_id, tile) != Refusal.NONE:
		return

	var machine: int = query_machine_at_tile(tile)
	if machine != -1:
		_refund_machine(action.player_id, machine)
		_remove_machine(machine)
		return

	var belt: int = query_belt_at_tile(tile)
	if belt != -1:
		_refund_belt(action.player_id, belt)
		_remove_belt(belt)


## Why demolishing at a tile would be refused, or `Refusal.NONE`.
func _demolish_refusal(player_id: int, tile: Vector3i) -> int:
	if not _is_player(player_id):
		return Refusal.NOTHING_THERE
	if query_machine_at_tile(tile) != -1 or query_belt_at_tile(tile) != -1:
		return Refusal.NONE
	return Refusal.NOTHING_THERE


## Hands a Machine's build cost and both its buffers back to a player.
func _refund_machine(player_id: int, index: int) -> void:
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition != null:
		for cost: int in range(definition.build_cost_items.size()):
			_give_to_player(
				player_id,
				definition.build_cost_items[cost],
				definition.build_cost_counts[cost]
			)

	var output_items: PackedStringArray = _machine_buffer_items[index]
	var output_counts: PackedInt64Array = _machine_buffer_counts[index]
	for slot: int in range(output_items.size()):
		_give_to_player(player_id, output_items[slot], output_counts[slot])

	var input_items: PackedStringArray = _machine_input_items[index]
	var input_counts: PackedInt64Array = _machine_input_counts[index]
	for slot: int in range(input_items.size()):
		_give_to_player(player_id, input_items[slot], input_counts[slot])


## Hands the Items riding a Belt back to a player. One Item a slot, so a packed Belt
## returns everything it was carrying.
func _refund_belt(player_id: int, index: int) -> void:
	var riding: PackedStringArray = _belt_item_ids[index]
	for slot: int in range(riding.size()):
		_give_to_player(player_id, riding[slot], 1)


## Removes a Machine from every parallel array. Machines are indexed by build order, so
## this shifts the indices after it — which is safe because nothing outside the
## Simulation holds an index across a tick, and nothing inside holds one at all.
func _remove_machine(index: int) -> void:
	_machine_id.remove_at(index)
	_machine_rotation.remove_at(index)
	_machine_tile_x.remove_at(index)
	_machine_tile_y.remove_at(index)
	_machine_tile_z.remove_at(index)
	_machine_built_tick.remove_at(index)
	_machine_progress_ticks.remove_at(index)
	_machine_heat_units.remove_at(index)
	_machine_buffer_items.remove_at(index)
	_machine_buffer_counts.remove_at(index)
	_machine_input_items.remove_at(index)
	_machine_input_counts.remove_at(index)
	_turret_target_serial.remove_at(index)
	_turret_last_shot_tick.remove_at(index)
	_flowfield_stale = true


## Removes a Belt and the Items on it. The update order is derived from which Belt
## feeds which, so it is stale the moment a run disappears.
func _remove_belt(index: int) -> void:
	_belt_tile_x.remove_at(index)
	_belt_tile_y.remove_at(index)
	_belt_tile_z.remove_at(index)
	_belt_direction.remove_at(index)
	_belt_tiles.remove_at(index)
	_belt_item_ids.remove_at(index)
	_belt_item_offsets.remove_at(index)
	_belt_update_order_stale = true


# ── What a player is carrying ────────────────────────────────────────────

## Adds to what a player is carrying, keeping the Item ids sorted.
func _give_to_player(player_id: int, item_id: String, quantity: int) -> void:
	if not _is_player(player_id) or quantity <= 0:
		return

	var items: PackedStringArray = _player_item_ids[player_id]
	var counts: PackedInt64Array = _player_item_counts[player_id]

	var slot: int = items.find(item_id)
	if slot != -1:
		counts[slot] += quantity
	else:
		slot = items.bsearch(item_id)
		items.insert(slot, item_id)
		counts.insert(slot, quantity)

	_player_item_ids[player_id] = items
	_player_item_counts[player_id] = counts


## Takes from what a player is carrying. An Item that runs out leaves no zero-count
## entry behind, so two players holding the same materials hold the same arrays and
## hash the same.
func _take_from_player(player_id: int, item_id: String, quantity: int) -> void:
	if not _is_player(player_id) or quantity <= 0:
		return

	var items: PackedStringArray = _player_item_ids[player_id]
	var counts: PackedInt64Array = _player_item_counts[player_id]

	var slot: int = items.find(item_id)
	if slot == -1:
		return

	counts[slot] = maxi(counts[slot] - quantity, 0)
	if counts[slot] == 0:
		items.remove_at(slot)
		counts.remove_at(slot)

	_player_item_ids[player_id] = items
	_player_item_counts[player_id] = counts


# ── Laying a Belt ─────────────────────────────────────────────────────────────

## Lays a Belt along a straight run, or refuses to.
##
## Refused when the run is not axis-aligned on one layer, when any tile of it cannot
## be built on, or when any tile of it is already taken by a Machine or another Belt.
## Like a refused build, a refused Belt is a silent no-op that does not move the hash:
## dragging a Belt into a wall is an ordinary thing for a player to do.
##
## The run is stored as an anchor, a direction and a length rather than as a list of
## tiles, because that is three integers instead of a growing array and the tiles are
## recoverable from it exactly.
func _apply_build_belt(action: InputAction) -> void:
	var from_tile: Vector3i = action.belt_from_tile()
	var to_tile: Vector3i = action.belt_to_tile()

	var direction: int = WorldGrid.direction_from_to(from_tile, to_tile)
	if direction == -1:
		return

	var tiles: int = WorldGrid.tiles_between(from_tile, to_tile)
	var step: Vector3i = WorldGrid.direction_step(direction)
	for offset: int in range(tiles):
		var tile: Vector3i = from_tile + step * offset
		if not WorldGrid.is_buildable(tile):
			return
		if query_belt_at_tile(tile) != -1 or query_machine_at_tile(tile) != -1:
			return
		if _nest_covers(tile):
			return

	_belt_tile_x.append(from_tile.x)
	_belt_tile_y.append(from_tile.y)
	_belt_tile_z.append(from_tile.z)
	_belt_direction.append(direction)
	_belt_tiles.append(tiles)
	_belt_item_ids.append(PackedStringArray())
	_belt_item_offsets.append(PackedInt64Array())
	_belt_update_order_stale = true


## Swaps in a new definition set, or refuses to.
##
## Three ways an attempt is refused, all of them silent in effect and loud in the
## log, because this arrives while a Run is in progress and a Run in progress must
## not be taken down by a typo:
##
##   * no payload — nothing to apply;
##   * the payload failed to load — applying it would leave the Run with no content;
##   * the payload does not hash to the digest the action claims — in lockstep that
##     means the action and the set disagree, and applying it would desync.
##
## A refusal leaves the definitions and the generation counter exactly as they were,
## so a refused reload is not a reload and the hash does not move.
func _apply_reload_definitions(action: InputAction) -> void:
	var incoming: Definitions = action.reload_payload()

	if incoming == null:
		push_error("a definition reload carried no definitions; keeping the current set")
		return
	if incoming.has_errors():
		push_error(
			"a definition reload failed to load; keeping the current set:\n%s"
			% incoming.describe_errors()
		)
		return
	if incoming.digest() != action.declared_digest():
		push_error(
			"a definition reload claimed digest %d but carries %d; keeping the current set"
			% [action.declared_digest(), incoming.digest()]
		)
		return

	_definitions = incoming
	_definition_generation += 1
	# A reload can resize a footprint, which moves an obstruction without moving a
	# Machine, so the field has to be taken as stale even though nothing was built.
	_flowfield_stale = true



# ── Heat ──────────────────────────────────────────────────────────────────────

## Records the Heat one completed craft added, to the Factory's total and to the Machine's
## own.
##
## **Completed crafts are what Heat is made of.** The alternatives were Power drawn and
## Machines running, and both were rejected for the same reason: Heat has to be something
## a player can watch themselves cause, or the mechanic teaches nothing and the Waves read
## as bad luck. A craft is the one event in the Factory that is unambiguously throughput —
## it is the thing a player built the Machine in order to get, it happens visibly, and it
## stops the moment the line starves. Power drawn would have made Heat a second reading of
## a gauge that already exists, and would have charged a slow Recipe with a big draw more
## than a fast line that actually produces. A count of Machines running would have punished
## building rather than producing, and made a starved line exactly as hot as a fed one.
##
## Depth is the second term, because deeper ore is louder (GLOSSARY.md). Only a Miner has
## one — a crafter pays the flat rate.
##
## Integer addition at a discrete event, which is the whole reason this cannot drift.
func _note_a_craft(index: int, definition: MachineDefinition) -> void:
	var units: int = _definitions.heat_per_craft
	if definition.is_miner():
		var node_index: int = _node_under_machine(index, definition)
		if node_index != -1:
			units += _definitions.heat_per_craft_per_depth * _node_depth[node_index]
	if units <= 0:
		return
	_heat += units
	_machine_heat_units[index] += units


## Sheds the Heat the Nest can hide, once per tick.
##
## A **duty cycle over whole ticks**, not a fraction of one. The decay is quoted per
## minute and a minute is `TICKS_PER_MINUTE` ticks, so a tick's worth is not a whole unit:
## every tick banks `heat.decay_per_minute` of credit and every whole `TICKS_PER_MINUTE`
## of credit spends one unit, with the remainder carried in an integer. Over any window
## the Factory has shed exactly `floor(ticks * decay_per_minute / TICKS_PER_MINUTE)` units
## — one floor applied once to the total, never once per tick. This is #7's lesson applied
## to the one quantity in the game that accumulates for forty hours: there is no fixed
## point in the mechanism at all, so there is nothing for it to lose.
##
## The drain is flat rather than proportional, which is a design decision as much as a
## determinism one. A proportional decay would be a per-tick ratio — the exact shape that
## drifts — and it would give the Factory an equilibrium Heat, which is the opposite of
## what this game is about. Flat means Heat measures throughput *in excess of what the
## Nest can hide*, and that rises without bound as the Factory does.
##
## Credit does not survive the Factory going cold: a Nest with nothing to hide cannot bank
## the shedding and spend it on a later spike, the same rule Power credit obeys.
func _heat_bleeds() -> void:
	if _heat <= 0:
		_heat = 0
		_heat_decay_credit = 0
		return

	_heat_decay_credit += _definitions.heat_decay_per_minute
	@warning_ignore("integer_division")
	var shed: int = _heat_decay_credit / TICKS_PER_MINUTE
	if shed > 0:
		_heat_decay_credit -= shed * TICKS_PER_MINUTE
		_heat = maxi(_heat - shed, 0)
	if _heat <= 0:
		_heat = 0
		_heat_decay_credit = 0


# ── Depth: the Breach a deep mine opens ───────────────────────────────────────
# The half of Depth that is not a number. Deeper ore is richer, draws more Power and raises
# more Heat — all three of which a player could read as an upgrade with a price tag. What
# makes Depth a *decision* is that extracting at it **rearranges the Map they have to
# defend**: a new Breach opens near the mine, so reaching for better ore buys geography it
# did not ask for. A bigger number would have been the easy version and the wrong one.

## Counts one completed craft against the Node it came out of, and opens a Breach once that
## Node has given up `depth.breach_crafts` of them.
##
## **Sustained extraction, not a single craft**: one load of deep ore is prospecting and
## should not summon anything, where a line that has been running on it for minutes is a hole
## in the ground somebody has noticed. Counted per Node for the reason `_node_deep_crafts`
## explains, and only at or past `depth.breach_tier`, so the ore a Run opens on is never a
## transgression.
##
## Separate from `_note_a_craft` rather than folded into it, because Heat and Breaches are
## two mechanics that happen to share an event: Heat returns early when a craft is worth no
## units, and a Factory tuned to make no Heat must still be answerable for digging.
func _note_a_deep_craft(index: int, definition: MachineDefinition) -> void:
	if not definition.is_miner():
		return
	var node_index: int = _node_under_machine(index, definition)
	if node_index == -1 or _node_depth[node_index] < _definitions.depth_breach_tier:
		return

	_node_deep_crafts[node_index] += 1
	if _node_breach_opened[node_index] != 0:
		return
	if _node_deep_crafts[node_index] < _definitions.depth_breach_crafts:
		return
	if _announce_a_breach_near(node_index):
		_node_breach_opened[node_index] = 1


## Announces a Breach near a Node, and reports whether it found anywhere to put one.
##
## The tile is the **first valid one on the ring `depth.breach_offset_tiles` tiles out from
## the mine, in the Map's own canonical tile order** — ascending x, then ascending z, which
## in practice puts it on the ring's north-west corner. Predictable rather than random, and
## deliberately so twice over: a Breach is only fortifiable if a player can plan for it
## (GLOSSARY.md), and geography that depended on an RNG draw would make *which* Breach you
## got a function of how many draws the Run had spent.
##
## A valid tile is on the Map, on the ground, not already a Breach or an announced one, and
## not under the Nest. Obstructions are deliberately **not** consulted: that would mean
## reading the flowfield, the flowfield is built lazily, and forcing a rebuild here is
## exactly the "rebuild of unrelated state" this must not do. A Breach that ends up inside a
## Machine is already handled — the field cannot route that tile, so an Enemy there walks
## straight at the Nest (see `_advance_enemy`).
##
## The ring widens by up to `RING_SEARCH_WIDENING` if every tile on it is taken, and if even
## that fails nothing is announced and the Node stays eligible: the next deep craft tries
## again. A Map with nowhere to put a Breach is geography, not an error.
func _announce_a_breach_near(node_index: int) -> bool:
	var mine: Vector3i = query_node_tile(node_index)
	var offset: int = maxi(_definitions.depth_breach_offset_tiles, 1)
	for ring: int in range(offset, offset + RING_SEARCH_WIDENING + 1):
		for step_x: int in range(-ring, ring + 1):
			for step_z: int in range(-ring, ring + 1):
				# The ring, not the square: only tiles at exactly this Chebyshev distance.
				if absi(step_x) != ring and absi(step_z) != ring:
					continue
				var tile: Vector3i = Vector3i(mine.x + step_x, mine.y, mine.z + step_z)
				if not _tile_can_hold_a_breach(tile):
					continue
				_pending_breach_tile_x.append(tile.x)
				_pending_breach_tile_y.append(tile.y)
				_pending_breach_tile_z.append(tile.z)
				_pending_breach_announced_tick.append(_tick)
				_pending_breach_ticks_left.append(_breach_telegraph_ticks())
				return true
	return false


## Whether a tile could become a Breach: on the Map, on the ground, and not already taken by
## a Breach, an announced one or the Nest.
func _tile_can_hold_a_breach(tile: Vector3i) -> bool:
	if _field_index(tile) == -1:
		return false
	if _nest_covers(tile):
		return false
	for index: int in range(query_breach_count()):
		if query_breach_tile(index) == tile:
			return false
	for index: int in range(query_pending_breach_count()):
		if query_pending_breach_tile(index) == tile:
			return false
	return true


## How long a newly opened Breach is telegraphed, in whole ticks. At least one, for the
## reason `_telegraph_ticks` is: a warning of no length is the ambush it exists to prevent.
func _breach_telegraph_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.depth_breach_telegraph_seconds), 1)


## Runs down every announced Breach's Telegraph and opens the ones whose warning is served.
##
## Runs before `_waves`, so the Breach set a Wave reads is settled for the tick. A Breach
## announced on *this* tick is skipped, which is the same rule a Machine built this tick
## follows — it was announced during the tick, and crediting it a tick of warning for the
## instant it appeared would make the first warning a tick short.
##
## **This does not mark the flowfield stale, and that is the point rather than an omission.**
## The field is a pure function of the Map's ground and the Machines standing on it; a Breach
## is neither, because a Breach does not obstruct and is not a destination. The field already
## routes every ground tile to the Nest, so the tile a new Breach opens on already has a
## direction and a distance, and an Enemy coming out of it steers by the same field every
## other Enemy is using. Rebuilding would be O(map) work to arrive at the identical answer.
func _breaches_open() -> void:
	var survivor: int = 0
	for index: int in range(query_pending_breach_count()):
		var tile: Vector3i = query_pending_breach_tile(index)
		var announced: int = _pending_breach_announced_tick[index]
		var left: int = _pending_breach_ticks_left[index]
		if announced < _tick:
			left -= 1
		if left <= 0:
			_insert_breach(tile)
			continue
		# Kept, shuffled down over whatever has already opened. Order is preserved among the
		# survivors, exactly as `_remove_enemy` preserves it among Enemies.
		_pending_breach_tile_x[survivor] = tile.x
		_pending_breach_tile_y[survivor] = tile.y
		_pending_breach_tile_z[survivor] = tile.z
		_pending_breach_announced_tick[survivor] = announced
		_pending_breach_ticks_left[survivor] = left
		survivor += 1

	_pending_breach_tile_x.resize(survivor)
	_pending_breach_tile_y.resize(survivor)
	_pending_breach_tile_z.resize(survivor)
	_pending_breach_announced_tick.resize(survivor)
	_pending_breach_ticks_left.resize(survivor)


## Puts a Breach on the Map **in canonical tile order**, which is the one way anything joins
## that array.
##
## This is the determinism trap in the whole feature. `MapLayout` sorts the starting Breaches
## into tile order and `_release_from_the_breaches` walks them in index order, so Enemy
## release order is geography. Appending a runtime Breach would quietly change that to "the
## order a player happened to dig in" — and because serials are issued in release order, two
## clients whose Miners completed a craft in a different order would then disagree about
## which Crawler is which. Inserting at the position `MapLayout.tile_precedes` names keeps
## the invariant exactly, and `test_depth` asserts the array is still ascending afterwards.
func _insert_breach(tile: Vector3i) -> void:
	var at: int = query_breach_count()
	for index: int in range(query_breach_count()):
		if MapLayout.tile_precedes(tile, query_breach_tile(index)):
			at = index
			break
	_breach_tile_x.insert(at, tile.x)
	_breach_tile_y.insert(at, tile.y)
	_breach_tile_z.insert(at, tile.z)


# ── The Nest, the Breaches and the Waves ──────────────────────────

## Runs the Wave schedule: the Telegraph, the arrival, and the Breaches letting Enemies out.
##
## Three things happen here in a fixed order, and the order is the argument:
##
## 1. **Time passes.** `_wave_elapsed_ticks` counts up rather than a stored countdown
##    counting down, because the interval it is measured against is a function of the
##    Factory's Heat *right now*. Switching on a new line therefore pulls the next Wave
##    towards the player on the tick they switch it on, which is the lesson the whole
##    mechanic exists to teach; a stored countdown could only ever have shortened the Wave
##    after next.
## 2. **The Telegraph runs.** It shows while the Wave is within `wave.telegraph_seconds`,
##    and it is counted, and a Wave is not due until the count is full. That is the one
##    mechanism behind "the core loop never ambushes the player" — not a convention every
##    caller has to remember, but a gate every Wave passes through, including a called one
##    and including one a Heat spike pulled forward.
## 3. **Enemies trickle out**, one per Breach per `wave.spawn_interval_seconds`, out of a
##    queue composed from `content/waves.csv` at the moment the Wave arrived.
##
## A Map with no Breach has no Waves at all, and here that means the whole clock is
## frozen: Enemies enter at Breaches and nowhere else, so geography with nowhere to enter
## is geography nothing attacks, and a countdown that kept running would report a Wave
## that is never coming. Heat still accumulates — a Factory is as loud as it is wherever
## it is standing — which is what lets a test study Heat without a Wave interrupting.
func _waves() -> void:
	if query_run_is_over() or query_breach_count() == 0:
		return

	_wave_elapsed_ticks += 1

	if _telegraph_is_showing():
		_telegraph_ticks_served += 1
	else:
		_telegraph_ticks_served = 0

	if _a_wave_is_due():
		_begin_a_wave()

	_release_from_the_breaches()


## How long the gap between Waves is at the Factory's current Heat, in whole ticks.
##
## The baseline, less a second for every `heat.per_second_sooner` units of Heat, floored at
## `heat.wave_interval_minimum_seconds`. Derived on demand rather than stored, so it tracks
## Heat tick by tick in both directions — a Factory that cools gets its breathing room
## back, which is what makes tearing a line down a real decision rather than a sunk cost.
##
## One integer division per call and no accumulation, so nothing here can drift. It is
## recomputed rather than carried precisely *because* a carried value would have to be
## adjusted every tick, and a per-tick adjustment is the shape this file refuses.
func _wave_interval_ticks() -> int:
	var baseline: int = _seconds_to_ticks(_definitions.heat_wave_interval_baseline_seconds)
	var minimum: int = maxi(_seconds_to_ticks(_definitions.heat_wave_interval_minimum_seconds), 1)
	var sooner: int = _definitions.heat_per_second_sooner
	var seconds_cut: int = 0
	if sooner > 0:
		@warning_ignore("integer_division")
		seconds_cut = _heat / sooner
	return maxi(baseline - seconds_cut * TICKS_PER_SECOND, minimum)


## How long the Telegraph runs, in whole ticks. At least one: a Telegraph of no length is
## the ambush it exists to prevent, and `Definitions` refuses a tuning value that would
## produce one, so this floor is the belt to that braces.
func _telegraph_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.wave_telegraph_seconds), 1)


## Whether the warning is up this tick. Either the Wave is close enough on the clock, or a
## player called it — a called Wave telegraphs from the moment the lever is pulled, which
## is what makes the lever a *throttle* rather than a surprise the caller inflicts on
## everyone else standing in the Factory.
func _telegraph_is_showing() -> bool:
	if _wave_called_early == 1:
		return true
	return _wave_interval_ticks() - _wave_elapsed_ticks <= _telegraph_ticks()


## Whether a Wave arrives this tick.
##
## The Telegraph is checked **first and unconditionally**, so there is exactly one way a
## Wave can arrive and it goes through the warning. A called Wave waives the interval and
## nothing else; a Heat spike shortens the interval and nothing else.
func _a_wave_is_due() -> bool:
	if _telegraph_ticks_served < _telegraph_ticks():
		return false
	if _wave_called_early == 1:
		return true
	return _wave_elapsed_ticks >= _wave_interval_ticks()


## Composes the Wave that has just arrived and clears the clock for the next one.
##
## The composition is read out of `content/waves.csv` against the Heat at this moment and
## then fixed, so a Wave is a fact about how hot the Factory was when it was summoned
## rather than something that keeps re-deciding itself while it spawns. Every tier the
## Factory has reached contributes — a hot Factory is sent the Chaff it was always getting
## *and* whatever its Heat has newly unlocked — in table order, which is sorted by id and
## therefore a property of the table rather than of authoring order.
func _begin_a_wave() -> void:
	_wave_number += 1
	_wave_elapsed_ticks = 0
	_telegraph_ticks_served = 0
	_wave_called_early = 0
	_ticks_until_next_spawn = 0

	_wave_queue_kind = PackedInt64Array()
	_wave_queue_cursor = 0
	for index: int in range(_definitions.wave_entry_count()):
		var entry: WaveEntry = _definitions.wave_entry_at(index)
		if entry == null:
			continue
		for i: int in range(entry.count_at_heat(_heat)):
			_wave_queue_kind.append(entry.enemy_kind)


## Lets the next Enemy of the current Wave out of every Breach.
##
## One per Breach, walked in the canonical tile order `MapLayout` sorted them into.
## Geography rather than authoring order, so two clients spawn the same Enemies in the
## same sequence and the serials they carry agree.
func _release_from_the_breaches() -> void:
	if _wave_queue_cursor >= _wave_queue_kind.size():
		return
	if _ticks_until_next_spawn > 0:
		_ticks_until_next_spawn -= 1
		return

	var kind: int = _wave_queue_kind[_wave_queue_cursor]
	for index: int in range(query_breach_count()):
		_spawn_enemy(kind, query_breach_tile(index))
	_wave_queue_cursor += 1
	# One short of the interval, for the reason a bite cooldown is: this tick is the first
	# of the gap, so an Enemy emerges every `wave.spawn_interval_seconds` exactly.
	_ticks_until_next_spawn = maxi(
		_seconds_to_ticks(_definitions.wave_spawn_interval_seconds) - 1, 0
	)


## Calls the next Wave early, and pays the player who called it.
##
## The lever: a throttle for a group that thinks it is ready, and the reason a co-op team
## argues productively about whether it is. What it buys the Enemy is nothing at all — a
## Wave is composed from the Heat the Factory is carrying when it *arrives*, and calling
## early means it arrives while that Heat is still lower than it would have been. What it
## costs the player is the breathing room they gave up. That is the whole trade, and it is
## legible without a second number to tune.
##
## The Telegraph is not waived. A called Wave arrives exactly `wave.telegraph_seconds`
## later and not one tick sooner, which is what keeps the lever from being a way for one
## player to ambush four.
##
## Refused as a **silent no-op whose hash does not move**, the same rule a misaimed build
## obeys: `query_call_wave_early_refusal` is what tells a player why, before they pull it.
func _apply_call_wave_early(action: InputAction) -> void:
	if _call_wave_early_refusal(action.player_id) != Refusal.NONE:
		return

	_wave_called_early = 1
	# Served from zero, so the full Telegraph runs from the moment the lever moves rather
	# than crediting whatever warning happened to be up already.
	_telegraph_ticks_served = 0

	# Paid in the materials a Run opens with — `player.starting_stock`'s own bill — and not
	# in a count of every Item in the game, which is what it used to be. The lever is a
	# trade of breathing room for the means to defend, so what it pays has to be build
	# materials; paying out of the whole Item set would also have conjured the very goods
	# `content/deliveries.csv` asks for, and progression a lever can buy is not progression.
	var bounty: int = _definitions.wave_call_early_bounty
	if bounty > 0:
		for item_id: String in _definitions.player_starting_stock_items:
			_give_to_player(action.player_id, item_id, bounty)


## Why the lever would refuse, or `Refusal.NONE`. A pure projection about a pull that has
## not happened, so a HUD can grey the lever out and say why rather than reporting a
## silence after the fact.
func _call_wave_early_refusal(player_id: int) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if query_breach_count() == 0:
		return Refusal.NO_BREACH
	if player_id < 0 or player_id >= query_player_count():
		return Refusal.NO_SUCH_PLAYER
	if _wave_queue_cursor < _wave_queue_kind.size():
		return Refusal.WAVE_STILL_ARRIVING
	if _wave_called_early == 1 or _telegraph_is_showing():
		return Refusal.WAVE_ALREADY_COMING
	return Refusal.NONE


# ── Delivery progression ──────────────────────────────────────────────────────

## Which Delivery tier the Nest is waiting on, as an index into the definition set, or -1
## when the chain is finished.
##
## The chain is walked in the definition set's own id order and nothing is skipped: the
## next tier is the first one this Run has not completed. A tier whose Depth the Factory
## has not reached is still the next tier — it is refused rather than passed over, which is
## what makes Depth a gate rather than a filter.
func _next_delivery_index() -> int:
	for index: int in range(_definitions.delivery_count()):
		if not _completed_delivery_ids.has(_definitions.delivery_at(index).id):
			return index
	return -1


## The deepest Node the Factory is actually mining.
##
## Derived rather than stored, and derived from the Factory rather than from a flag: a
## Depth is reached by standing a Miner that reaches it on a Node that has it, and lost
## again by taking that Miner down. So the gate measures the Factory, which is the only
## thing a player can argue with.
##
## Three conditions, all of them already the Simulation's own rules and asked through the
## same functions `_machine_has_its_inputs` asks: the Machine is a Miner, its footprint
## covers a Node, and `_miner_reaches` says its tier reaches that Node's Depth with a Recipe
## that yields what is under it. A Miner Mk1 parked on a Depth 3 Node is starved, and it has
## reached Depth nothing — one predicate, so the Delivery gate and the extraction rule cannot
## disagree about what a Factory is mining.
func _depth_reached() -> int:
	var deepest: int = 0
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not definition.is_miner():
			continue
		var node: int = _node_under_machine(index, definition)
		if node == -1:
			continue
		if not _miner_reaches(definition, node):
			continue
		var recipe: RecipeDefinition = _definitions.recipe(definition.recipe_id)
		if recipe == null or not _recipe_yields(recipe, _node_resource[node]):
			continue
		deepest = maxi(deepest, _node_depth[node])
	return deepest


## Hands a player's goods over to the Nest, or refuses to.
##
## Progression is physical (GLOSSARY.md): there is no research menu, so this is a player
## standing at the Nest with materials in hand. Everything the open tier is still waiting
## for and the player is carrying crosses the counter, clamped to the bill — the Nest never
## takes more than it asked for, so there is no surplus to give back and nothing is
## destroyed.
##
## Refused as a **silent no-op whose hash does not move**, the same rule a misaimed build
## and the call-early lever obey. `query_delivery_refusal` is what says why, beforehand.
func _apply_deliver_to_nest(action: InputAction) -> void:
	if _delivery_refusal(action.player_id) != Refusal.NONE:
		return

	var definition: DeliveryDefinition = _definitions.delivery_at(_next_delivery_index())
	for item_id: String in definition.goods_items:
		var handed: int = _accept_delivery(item_id, query_player_item(action.player_id, item_id))
		if handed > 0:
			_take_from_player(action.player_id, item_id, handed)


## Why handing a Delivery over would be refused, or `Refusal.NONE`. A pure projection about
## a hand-over that has not happened, so the HUD says what is missing before a player walks
## across the Map rather than after.
func _delivery_refusal(player_id: int) -> int:
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	var index: int = _next_delivery_index()
	if index == -1:
		return Refusal.NO_DELIVERY_PENDING
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	if _depth_reached() < definition.min_depth:
		return Refusal.DEPTH_TOO_SHALLOW
	if not _player_is_at_the_nest(player_id):
		return Refusal.TOO_FAR_FROM_THE_NEST
	for item_id: String in definition.goods_items:
		if _delivery_would_take(item_id) > 0 and query_player_item(player_id, item_id) > 0:
			return Refusal.NONE
	return Refusal.NOTHING_TO_DELIVER


## Whether a player is standing close enough to the Nest to hand goods over.
##
## Measured to the nearest point of the Nest's footprint rather than to its anchor, so a
## 4x4 Nest is a building a player walks up to rather than a coordinate they have to find.
## Compared squared, for the reason a Turret's reach is: `Fixed.sqrt` floors, and a floor
## would put a player exactly on the boundary in or out of reach depending on a rounding
## rule.
func _player_is_at_the_nest(player_id: int) -> bool:
	var footprint: Vector2i = query_nest_footprint()
	var origin: Vector3i = query_nest_tile()
	var tile_size: int = WorldGrid.TILE_SIZE_METRES
	var low_x: int = Fixed.from_int(origin.x * tile_size)
	var low_z: int = Fixed.from_int(origin.z * tile_size)
	var high_x: int = Fixed.from_int((origin.x + footprint.x) * tile_size)
	var high_z: int = Fixed.from_int((origin.z + footprint.y) * tile_size)

	var gap_x: int = _gap_to_span(_player_x[player_id], low_x, high_x)
	var gap_z: int = _gap_to_span(_player_z[player_id], low_z, high_z)
	var reach: int = _definitions.nest_delivery_reach
	return gap_x * gap_x + gap_z * gap_z <= reach * reach


## Adds goods to the Nest's counter against the open Delivery, reporting how many it took.
##
## The one place goods become progress, so a Belt running into the Nest and a player
## handing a pile over are the same event with the same rules. It takes only what the open
## tier is still waiting for: there is no store behind this, so an Item the Nest does not
## want is refused and whatever offered it keeps it.
func _accept_delivery(item_id: String, quantity: int) -> int:
	var taken: int = mini(_delivery_would_take(item_id), quantity)
	if taken <= 0:
		return 0

	var slot: int = _delivery_items.find(item_id)
	if slot != -1:
		_delivery_counts[slot] += taken
	else:
		slot = _delivery_items.bsearch(item_id)
		_delivery_items.insert(slot, item_id)
		_delivery_counts.insert(slot, taken)
	return taken


## How many more of an Item the Nest would take right now.
##
## The pure twin of `_accept_delivery`: it asks the same question without moving anything,
## which is what lets `_hand_off_blocked` report a Belt backed up against a Nest that has
## stopped wanting what it is carrying. Zero once the Run is over, once the chain is
## finished, while the open tier is gated above the Depth the Factory is mining, and for any
## Item that tier does not ask for.
func _delivery_would_take(item_id: String) -> int:
	if query_run_is_over():
		return 0
	var index: int = _next_delivery_index()
	if index == -1:
		return 0
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	if _depth_reached() < definition.min_depth:
		return 0
	return maxi(definition.goods_required(item_id) - _delivered_so_far(item_id), 0)


## How much of an Item the Nest is already holding against the open Delivery.
func _delivered_so_far(item_id: String) -> int:
	var slot: int = _delivery_items.find(item_id)
	if slot == -1:
		return 0
	return _delivery_counts[slot]


## Whether the open Delivery's bill has been met in full.
func _delivery_is_paid(definition: DeliveryDefinition) -> bool:
	for slot: int in range(definition.goods_items.size()):
		if _delivered_so_far(definition.goods_items[slot]) < definition.goods_counts[slot]:
			return false
	return true


## Settles the Nest's counter, once a tick, and unlocks **exactly the tier** whose bill has
## been met.
##
## One place, which is the point: goods reach the counter from two directions — a Belt
## running into the Nest and a player standing at it with a pile in hand — and a tier that
## completed on one path and not the other would be two rules. It runs straight after
## `_transport`, so goods that arrived this tick are settled this tick and before anything
## that could end the Run.
##
## Nothing is unlocked by implication: the ids recorded are the ids that tier names, so a
## tier the chain has not reached is not quietly earned and a tier completed does not open
## the one after it. The ids rather than indices, so a content edit that resorts the table
## cannot renumber what a Run has earned — the same reason `_machine_id` holds an id.
func _deliveries() -> void:
	var index: int = _next_delivery_index()
	if index == -1:
		return
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	if not _delivery_is_paid(definition):
		return

	_insert_sorted(_completed_delivery_ids, definition.id)
	for machine_id: String in definition.unlocks_machines:
		_insert_sorted(_unlocked_machine_ids, machine_id)
	for gear_id: String in definition.unlocks_gear:
		_insert_sorted(_unlocked_gear_ids, gear_id)
	for stratagem_id: String in definition.unlocks_stratagems:
		_insert_sorted(_unlocked_stratagem_ids, stratagem_id)

	# The counter is cleared rather than carried, so what the Nest is holding is always
	# holdings against the tier it is waiting on and never a surplus from the last one.
	_delivery_items.clear()
	_delivery_counts.clear()


## Adds an id to a sorted list, once. Sorted so that iteration order — and therefore the
## state hash — is a property of what was unlocked rather than of the order it was earned
## in; once, so a tier re-read after a hot-reload cannot double an entry.
func _insert_sorted(ids: PackedStringArray, id: String) -> void:
	if ids.has(id):
		return
	ids.insert(ids.bsearch(id), id)


## Whether a Machine may be built: either no Delivery tier claims it, or one that has been
## completed does.
##
## A Machine is locked **because a tier names it**, which is why there is no `locked`
## column in `content/machines.csv` — the Machines a Run opens with are exactly the ones no
## tier names, and a second copy of that fact would fall out of step the first time a tier
## moved.
func _machine_is_unlocked(machine_id: String) -> bool:
	if _unlocked_machine_ids.has(machine_id):
		return true
	return not _definitions.locks_machine(machine_id)


## The Machine a fresh Run opens with on the Build Gun: the first unlocked one by id.
##
## The first *unlocked* one, because a Build Gun that opens holding something the
## Simulation would refuse to place teaches a player that the game is broken.
func _opening_machine() -> String:
	for machine_id: String in _definitions.machine_ids():
		if _machine_is_unlocked(machine_id):
			return machine_id
	return ""


## Puts one Enemy of the given kind on the Map at the centre of a tile.
##
## Appends, always, which is the whole of why Enemy iteration order is deterministic: the
## arrays are in ascending serial order by construction and nothing reorders them.
##
## Takes the kind rather than assuming it, because the Wave table names kinds and
## Milestone 1 shipping exactly one of them is a content fact rather than a structural one.
## A kind with no tuned health would arrive with none and die on its first tick, so an
## unknown kind is refused here as well as at load time — `_enemy_health_for` is the one
## place a kind becomes a number of hit points.
func _spawn_enemy(kind: int, tile: Vector3i) -> void:
	var health: int = _enemy_health_for(kind)
	if health <= 0:
		return
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(tile)
	_enemy_serial.append(_next_enemy_serial)
	_enemy_kind.append(kind)
	_enemy_x.append(centre.x)
	_enemy_z.append(centre.z)
	_enemy_health.append(health)
	_enemy_spawn_tick.append(_tick)
	_enemy_attack_cooldown.append(0)
	_next_enemy_serial += 1


## The hit points an Enemy of a kind arrives with, or 0 for a kind that does not exist.
## One `match` rather than a column in the Wave table, because health is a property of the
## Enemy and the Wave table says how many of them come, not what they are.
func _enemy_health_for(kind: int) -> int:
	match kind:
		EnemyKind.CRAWLER:
			return _definitions.crawler_health
		_:
			return 0


## Moves every Enemy one tick along the shared flowfield, and lets the ones in contact
## with the Nest bite it.
##
## Walked in index order, which is ascending spawn serial and therefore identical on every
## client. Nothing here reads another Enemy's position, so index order carries no bias of
## the kind the Belts have to avoid: Enemies do not collide with each other, by design —
## a swarm is a swarm, and the alternative is an O(n²) separation pass that the Chaff tier
## could not afford.
func _enemies() -> void:
	if query_run_is_over() or query_enemy_count() == 0:
		return

	var field: PackedInt64Array = _flowfield()
	var step_metres: int = Fixed.div(
		_definitions.crawler_speed, Fixed.from_int(TICKS_PER_SECOND)
	)
	var bite_ticks: int = maxi(
		_seconds_to_ticks(_definitions.crawler_attack_interval_seconds), 1
	)

	for index: int in range(query_enemy_count()):
		# An Enemy does not act on the tick it came through its Breach, for the reason a
		# Machine does not run on the tick it was built: it arrived *during* that tick, and
		# crediting it a whole tick of walking would put its first step a tick early.
		if _enemy_spawn_tick[index] == _tick:
			continue
		if _enemy_is_in_contact(index):
			if _enemy_attack_cooldown[index] > 0:
				_enemy_attack_cooldown[index] -= 1
				continue
			_damage_the_nest(_definitions.crawler_damage)
			# One short of the interval, because this tick is the first of the wait. A bite
			# every `enemy.crawler_attack_interval_seconds` exactly, with nothing rounding.
			_enemy_attack_cooldown[index] = bite_ticks - 1
			continue
		_advance_enemy(index, field, step_metres)


## One Enemy, one tick, along the field.
##
## The field names the way out of the tile the Enemy is standing on; the Enemy walks that
## way and, at the same time, slides towards the middle of its lane by no more than the
## same distance. The lane correction is what keeps an Enemy that was nudged off centre
## from cutting a corner through an obstruction, and it can never make the Enemy faster
## than its tuned speed along the axis it is travelling on.
##
## An Enemy on a tile the field has no direction for — inside an obstruction a player
## built on top of it, or on ground the Nest cannot be reached from — falls back to
## walking straight at the Nest on whichever axis it is further out on. Without that a
## Crawler could be parked for ever by dropping a Machine on it, which is a cheese rather
## than a defence.
func _advance_enemy(index: int, field: PackedInt64Array, step_metres: int) -> void:
	var tile: Vector3i = WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])
	var cell: int = _field_index(tile)
	var direction: int = -1 if cell == -1 else field[cell]

	var step: Vector3i = Vector3i.ZERO
	if direction == -1:
		step = _towards_the_nest(tile)
	else:
		step = WorldGrid.direction_step(direction)
	if step == Vector3i.ZERO:
		return

	_enemy_x[index] += step.x * step_metres
	_enemy_z[index] += step.z * step_metres

	# Slide towards the middle of the lane, on the axis the Enemy is not travelling along.
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(
		WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])
	)
	if step.x == 0:
		_enemy_x[index] += Fixed.clamp_fixed(centre.x - _enemy_x[index], -step_metres, step_metres)
	if step.z == 0:
		_enemy_z[index] += Fixed.clamp_fixed(centre.z - _enemy_z[index], -step_metres, step_metres)


## The one-tile step that closes the larger of the two gaps to the Nest's footprint. The
## fallback for a tile the field cannot route, and nothing else uses it — a straight line
## is not pathing, it is a refusal to be stuck.
func _towards_the_nest(tile: Vector3i) -> Vector3i:
	var size: Vector2i = query_nest_footprint()
	var anchor: Vector3i = query_nest_tile()
	var gap_x: int = _gap_to_span(tile.x, anchor.x, anchor.x + size.x - 1)
	var gap_z: int = _gap_to_span(tile.z, anchor.z, anchor.z + size.y - 1)
	if absi(gap_x) >= absi(gap_z) and gap_x != 0:
		return Vector3i(signi(gap_x), 0, 0)
	if gap_z != 0:
		return Vector3i(0, 0, signi(gap_z))
	return Vector3i.ZERO


## How far a coordinate is from the nearer end of a span, signed towards it. 0 when it is
## already inside the span.
func _gap_to_span(value: int, low: int, high: int) -> int:
	if value < low:
		return low - value
	if value > high:
		return high - value
	return 0


## Whether an Enemy is close enough to the Nest to bite it: standing on a tile the Nest's
## footprint covers, or on one sharing an edge with it.
##
## Tiles rather than a fixed-point radius, because the Nest is a footprint on a grid
## rather than a point, and a tile answer cannot disagree with the flowfield about which
## tiles count as at the Nest.
func _enemy_is_in_contact(index: int) -> bool:
	if not _is_enemy(index):
		return false
	var tile: Vector3i = WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])
	if _nest_covers(tile):
		return true
	for direction: int in range(WorldGrid.DIRECTION_COUNT):
		if _nest_covers(tile + WorldGrid.direction_step(direction)):
			return true
	return false


## Whether the Nest's footprint covers a tile.
func _nest_covers(tile: Vector3i) -> bool:
	var size: Vector2i = query_nest_footprint()
	return WorldGrid.footprint_covers(query_nest_tile(), size.x, size.y, tile)


## Takes hit points off the Nest, and ends the Run if that was the last of them.
##
## The Run ends exactly once. `_run_over_tick` is set on the tick the Nest fell and never
## cleared, so the Wave reached is frozen at the Wave that did it rather than drifting
## afterwards, and a later ticket that lets a Nest be repaired cannot un-end a Run.
func _damage_the_nest(points: int) -> void:
	if points <= 0 or query_run_is_over():
		return
	_nest_health = maxi(_nest_health - points, 0)
	if _nest_health == 0:
		_run_over_tick = _tick


## How many whole ticks a fixed-point number of seconds is. Floored, like every other
## lossy conversion, and never negative.
func _seconds_to_ticks(seconds: int) -> int:
	return maxi(Fixed.floor_to_int(Fixed.mul(seconds, Fixed.from_int(TICKS_PER_SECOND))), 0)


# ── The flowfield ───────────────────────────────────────────

## The field every Enemy steers by, rebuilt only if the obstructions moved.
##
## The size check is not belt-and-braces: the field is derived, so `RunSave` leaves it out
## of a save entirely, and a Run restored from one arrives holding nothing. Asking whether
## it is the right size rather than trusting a flag is what makes that correct however the
## Simulation was constructed.
func _flowfield() -> PackedInt64Array:
	if _flowfield_stale or _flow_direction.size() != FIELD_TILES:
		_rebuild_flowfield()
	return _flow_direction


## Rebuilds the shared field: one breadth-first sweep outward from the Nest.
##
## O(map) once, amortised across every Enemy alive — which is the whole argument for a
## field over per-agent A*, and it only gets stronger as the Chaff tier arrives. Breadth
## first over four-connected tiles, so the distance it records is the exact number of
## tiles a walk to the Nest takes and no heuristic is involved.
##
## The direction stored on a tile is the way *back* towards whichever tile reached it
## first. Neighbours are pushed in `WorldGrid.DIRECTION_STEPS` index order out of a FIFO
## queue, so which tile gets there first is fixed by the grid's own direction order rather
## than by anything that happened during the Run: two clients build the identical field,
## down to which way a tile equidistant from two routes points.
##
## Obstructions are skipped rather than entered, which is what makes a wall a wall: the
## sweep flows around it, the tiles behind it get a longer distance or none at all, and
## every Enemy on the Map inherits the new route on the tick the field is rebuilt.
func _rebuild_flowfield() -> void:
	_flow_direction.resize(FIELD_TILES)
	_flow_direction.fill(-1)
	_flow_distance.resize(FIELD_TILES)
	_flow_distance.fill(-1)
	_mark_obstructions()

	# Seeded on the whole Nest footprint, because the destination is a 4x4 building and
	# not a point: an Enemy heading for its near edge must not be routed to its anchor.
	var queue: PackedInt64Array = PackedInt64Array()
	var size: Vector2i = query_nest_footprint()
	var anchor: Vector3i = query_nest_tile()
	for offset_x: int in range(size.x):
		for offset_z: int in range(size.y):
			var seed_cell: int = _field_index(
				Vector3i(anchor.x + offset_x, anchor.y, anchor.z + offset_z)
			)
			if seed_cell == -1:
				continue
			_flow_distance[seed_cell] = 0
			queue.append(seed_cell)

	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		@warning_ignore("integer_division")
		var row: int = cell / FIELD_WIDTH_TILES
		var reached_in: int = _flow_distance[cell] + 1
		for direction: int in range(WorldGrid.DIRECTION_COUNT):
			var offset: int = FIELD_STEPS[direction]
			var neighbour: int = cell + offset
			if neighbour < 0 or neighbour >= FIELD_TILES:
				continue
			# A step along x must not wrap off one edge of the Map onto the other.
			@warning_ignore("integer_division")
			if absi(offset) == 1 and neighbour / FIELD_WIDTH_TILES != row:
				continue
			if _flow_distance[neighbour] != -1 or _flow_blocked[neighbour] != 0:
				continue
			_flow_distance[neighbour] = reached_in
			# The neighbour's way out is back the way this step came.
			_flow_direction[neighbour] = WorldGrid.wrap_rotation(direction + 2)
			queue.append(neighbour)

	_flowfield_stale = false


## Paints every tile an Enemy cannot walk through.
##
## Machines obstruct: a Factory is a maze, and that is what makes laying one out a
## defensive decision rather than decoration. Belts do not — a Crawler crawls over a
## conveyor — and neither do Nodes, which are ground. **Walls join this function in the
## ticket that adds them**, as one more loop and nothing else; it is the single definition
## of the obstruction set, which is why `query_tile_obstructs_enemies` reads what it paints
## rather than asking the question a second way.
##
## The Nest itself is deliberately not painted: it is the destination, seeded at distance
## zero, so a sweep that treated it as solid would have nowhere to start.
func _mark_obstructions() -> void:
	_flow_blocked.resize(FIELD_TILES)
	_flow_blocked.fill(0)
	for index: int in range(query_machine_count()):
		var size: Vector2i = _machine_size(index)
		if size == Vector2i.ZERO:
			continue
		var origin: Vector3i = query_machine_tile(index)
		for offset_x: int in range(size.x):
			for offset_z: int in range(size.y):
				var cell: int = _field_index(
					Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z)
				)
				if cell != -1:
					_flow_blocked[cell] = 1


## Whether a tile stops an Enemy walking through it — what `_mark_obstructions` painted,
## read back for one tile. A tile the field does not cover obstructs nothing: it is not
## ground an Enemy could be walking on in the first place.
func _tile_obstructs_enemies(tile: Vector3i) -> bool:
	var cell: int = _field_index(tile)
	if cell == -1:
		return false
	_flowfield()
	return _flow_blocked[cell] != 0


## Where a ground tile sits in the flat field arrays, or -1 for a tile the field does not
## cover — outside the Map, or on a layer above the ground. Pure arithmetic, so no
## Dictionary and no lookup table.
func _field_index(tile: Vector3i) -> int:
	if tile.y != WorldGrid.GROUND_LAYER:
		return -1
	if absi(tile.x) > WorldGrid.HALF_EXTENT_TILES or absi(tile.z) > WorldGrid.HALF_EXTENT_TILES:
		return -1
	return (
		(tile.z + WorldGrid.HALF_EXTENT_TILES) * FIELD_WIDTH_TILES
		+ tile.x
		+ WorldGrid.HALF_EXTENT_TILES
	)


## The tile a field index belongs to. The exact inverse of `_field_index`.
func _field_tile(cell: int) -> Vector3i:
	@warning_ignore("integer_division")
	var row: int = cell / FIELD_WIDTH_TILES
	return Vector3i(
		cell - row * FIELD_WIDTH_TILES - WorldGrid.HALF_EXTENT_TILES,
		WorldGrid.GROUND_LAYER,
		row - WorldGrid.HALF_EXTENT_TILES
	)


# ── Hashing ───────────────────────────────────────────────────────────────────

## Reduces the whole authoritative state to one integer.
##
## A pure read: it never mutates anything, so a test or a desync check can call it
## as often as it likes. Every new piece of state a later ticket adds must be fed
## in here, in a fixed order — state that is not hashed is state whose divergence
## the harness cannot see.
func hash() -> int:
	var hasher: StateHasher = StateHasher.new()
	hasher.feed_int(_tick)
	hasher.feed_int(_seed)
	hasher.feed_int(_rng.state)
	hasher.feed_ints(_player_x)
	hasher.feed_ints(_player_z)
	hasher.feed_ints(_player_yaw)
	hasher.feed_ints(_player_pitch)
	hasher.feed_ints(_player_velocity_x)
	hasher.feed_ints(_player_velocity_z)
	hasher.feed_ints(_player_survey_held)
	hasher.feed_ints(_player_sprint_held)
	hasher.feed_ints(_player_survey_ticks)
	hasher.feed_ints(_player_build_rotation)
	for machine_id: String in _player_selected_machine:
		hasher.feed_text(machine_id)
	for player_id: int in range(query_player_count()):
		var carried: PackedStringArray = _player_item_ids[player_id]
		var carried_counts: PackedInt64Array = _player_item_counts[player_id]
		hasher.feed_int(carried.size())
		for slot: int in range(carried.size()):
			hasher.feed_text(carried[slot])
			hasher.feed_int(carried_counts[slot])
	# The definitions are state. A Run using different content is in a different
	# state even before its first tick, and a Run that reloaded mid-flight is in a
	# different state from one that did not.
	hasher.feed_int(_definitions.digest())
	hasher.feed_int(_definition_generation)
	# The Map. Constant through a Run today, hashed anyway: two Runs on different
	# geography are in different states before either of them steps.
	hasher.feed_ints(_node_tile_x)
	hasher.feed_ints(_node_tile_y)
	hasher.feed_ints(_node_tile_z)
	hasher.feed_ints(_node_depth)
	for resource_id: String in _node_resource:
		hasher.feed_text(resource_id)
	# The Nest and the Breaches. Where they are is geography and constant through a Run,
	# hashed anyway for the reason the Nodes are; what is left of the Nest is the one
	# number that can end the Run, so a divergence in it is a divergence about whether the
	# game is still being played.
	hasher.feed_int(_nest_tile_x)
	hasher.feed_int(_nest_tile_y)
	hasher.feed_int(_nest_tile_z)
	hasher.feed_int(_nest_health)
	hasher.feed_ints(_breach_tile_x)
	hasher.feed_ints(_breach_tile_y)
	hasher.feed_ints(_breach_tile_z)
	# What the Run has unlocked, and what the Nest is holding against the tier it is waiting
	# on. Hashed because it decides what the next tick will let a player build, and because
	# two Runs that have progressed differently are not in the same state. Ids rather than
	# indices, so a hot-reload that resorts the Delivery table cannot move this hash without
	# anything having been earned or spent.
	hasher.feed_int(_completed_delivery_ids.size())
	for delivery_id: String in _completed_delivery_ids:
		hasher.feed_text(delivery_id)
	hasher.feed_int(_unlocked_machine_ids.size())
	for machine_id: String in _unlocked_machine_ids:
		hasher.feed_text(machine_id)
	hasher.feed_int(_unlocked_gear_ids.size())
	for gear_id: String in _unlocked_gear_ids:
		hasher.feed_text(gear_id)
	hasher.feed_int(_unlocked_stratagem_ids.size())
	for stratagem_id: String in _unlocked_stratagem_ids:
		hasher.feed_text(stratagem_id)
	hasher.feed_int(_delivery_items.size())
	for slot: int in range(_delivery_items.size()):
		hasher.feed_text(_delivery_items[slot])
		hasher.feed_int(_delivery_counts[slot])
	# Depth: what each Node has given up and the Breaches that are on their way. All of it
	# decides what a later tick does — a Node one craft from its threshold is in a different
	# state from one that has just opened a Breach, and a warning half-served is a warning.
	hasher.feed_ints(_node_deep_crafts)
	hasher.feed_ints(_node_breach_opened)
	hasher.feed_ints(_pending_breach_tile_x)
	hasher.feed_ints(_pending_breach_tile_y)
	hasher.feed_ints(_pending_breach_tile_z)
	hasher.feed_ints(_pending_breach_announced_tick)
	hasher.feed_ints(_pending_breach_ticks_left)
	# The Wave clock, and whether the Run is over. Every one of these decides what the next
	# tick does, so none of them may sit outside the hash.
	hasher.feed_int(_heat)
	hasher.feed_int(_heat_decay_credit)
	hasher.feed_int(_wave_number)
	hasher.feed_int(_wave_elapsed_ticks)
	hasher.feed_int(_telegraph_ticks_served)
	hasher.feed_int(_wave_called_early)
	hasher.feed_ints(_wave_queue_kind)
	hasher.feed_int(_wave_queue_cursor)
	hasher.feed_int(_ticks_until_next_spawn)
	hasher.feed_int(_run_over_tick)
	# Every Enemy on the Map, in index order — which is ascending spawn serial, the one
	# order every client agrees on. The flowfield they steer by is deliberately *not*
	# hashed: it is derived, a pure function of the Map and the Machines standing on it,
	# both of which are hashed above. `_belt_update_order` is left out for the same reason.
	hasher.feed_ints(_enemy_serial)
	hasher.feed_ints(_enemy_kind)
	hasher.feed_ints(_enemy_x)
	hasher.feed_ints(_enemy_z)
	hasher.feed_ints(_enemy_health)
	hasher.feed_ints(_enemy_spawn_tick)
	hasher.feed_ints(_enemy_attack_cooldown)
	hasher.feed_int(_next_enemy_serial)
	# The Factory: what is built, where, how far through a craft it is, and what it
	# is holding. All of it, because a divergence the harness cannot see is a
	# divergence that reaches co-op.
	hasher.feed_ints(_machine_tile_x)
	hasher.feed_ints(_machine_tile_y)
	hasher.feed_ints(_machine_tile_z)
	hasher.feed_ints(_machine_rotation)
	hasher.feed_ints(_machine_built_tick)
	hasher.feed_ints(_machine_heat_units)
	hasher.feed_ints(_machine_progress_ticks)
	# What every Turret is shooting at, and when it last fired. The serial rather than an
	# index, which is the whole point of holding one: a hash over indices would agree between
	# two clients that are aimed at different Crawlers.
	hasher.feed_ints(_turret_target_serial)
	hasher.feed_ints(_turret_last_shot_tick)
	for index: int in range(query_machine_count()):
		hasher.feed_text(_machine_id[index])
		var items: PackedStringArray = _machine_buffer_items[index]
		var counts: PackedInt64Array = _machine_buffer_counts[index]
		hasher.feed_int(items.size())
		for slot: int in range(items.size()):
			hasher.feed_text(items[slot])
			hasher.feed_int(counts[slot])
		# And what it is holding *for* its Recipe. Hashed separately from the output
		# buffer, because a Machine with two ore waiting and a Machine with two ore made
		# are in different states.
		var input_items: PackedStringArray = _machine_input_items[index]
		var input_counts: PackedInt64Array = _machine_input_counts[index]
		hasher.feed_int(input_items.size())
		for slot: int in range(input_items.size()):
			hasher.feed_text(input_items[slot])
			hasher.feed_int(input_counts[slot])
	# The one Power grid. The credit carried between ticks is what makes a proportional
	# throttle exact, so it is authoritative state and a divergence in it is a divergence
	# in every Machine's rate; the two gauge readings are hashed with it because a Factory
	# in deficit and a Factory in surplus are not in the same state.
	hasher.feed_int(_power_supply_kw)
	hasher.feed_int(_power_demand_kw)
	hasher.feed_int(_power_credit_kw_ticks)
	hasher.feed_int(1 if _power_tick_granted else 0)
	# The Belts, and every Item riding one. Items are derived state — recomputed
	# identically on every client and never replicated (ADR 0002) — and that is exactly
	# why they have to be hashed: the guarantee that they are identical everywhere is
	# worth nothing if nothing checks it.
	hasher.feed_ints(_belt_tile_x)
	hasher.feed_ints(_belt_tile_y)
	hasher.feed_ints(_belt_tile_z)
	hasher.feed_ints(_belt_direction)
	hasher.feed_ints(_belt_tiles)
	for index: int in range(query_belt_count()):
		var belt_items: PackedStringArray = _belt_item_ids[index]
		var belt_offsets: PackedInt64Array = _belt_item_offsets[index]
		hasher.feed_int(belt_items.size())
		for slot: int in range(belt_items.size()):
			hasher.feed_text(belt_items[slot])
			hasher.feed_int(belt_offsets[slot])
	return hasher.digest()


# ── Queries ───────────────────────────────────────────────────────────────────
# Read-only projections. They copy rather than hand out references, so a caller
# cannot reach through a query and mutate state.

## Which tick the Simulation has completed. A fresh Simulation is on tick 0.
func query_tick() -> int:
	return _tick


## The seed this Simulation was built from.
func query_seed() -> int:
	return _seed


func query_player_count() -> int:
	return _player_x.size()


## A player's position in fixed-point metres. An unknown id reads as the origin
## rather than crashing: in lockstep, a malformed action must degrade, not take
## the Run down.
func query_player_position(player_id: int) -> FixedVec2:
	if not _is_player(player_id):
		return FixedVec2.zero()
	return FixedVec2.new(_player_x[player_id], _player_z[player_id])


## How fast a player is moving, in fixed-point metres per second. Non-zero for a
## while after they let go of the keys, because they are still slowing down.
func query_player_velocity(player_id: int) -> FixedVec2:
	if not _is_player(player_id):
		return FixedVec2.zero()
	return FixedVec2.new(_player_velocity_x[player_id], _player_velocity_z[player_id])


## How much of an Item a player is carrying. 0 for one they have none of.
func query_player_item(player_id: int, item_id: String) -> int:
	if not _is_player(player_id):
		return 0
	var items: PackedStringArray = _player_item_ids[player_id]
	var slot: int = items.find(item_id)
	if slot == -1:
		return 0
	return _player_item_counts[player_id][slot]


## Every Item a player is carrying at least one of, sorted by id.
func query_player_items(player_id: int) -> PackedStringArray:
	if not _is_player(player_id):
		return PackedStringArray()
	return (_player_item_ids[player_id] as PackedStringArray).duplicate()


## Why demolishing whatever is on `tile` would be refused, or `Refusal.NONE`. A pure
## projection, like `query_build_refusal`, so the HUD can say why before a player
## clicks rather than after.
func query_demolish_refusal(player_id: int, tile: Vector3i) -> int:
	return _demolish_refusal(player_id, tile)


## The id of the Machine a player has on the Build Gun. Empty only when the
## definitions carry no Machines at all.
func query_player_selected_machine(player_id: int) -> String:
	if not _is_player(player_id):
		return ""
	return _player_selected_machine[player_id]


## The definition index of the Machine a player has on the Build Gun, or -1. Derived
## from the stored id rather than held beside it, so the two cannot disagree after a
## hot-reload resorts the table.
func query_player_selected_machine_index(player_id: int) -> int:
	return _definitions.machine_index(query_player_selected_machine(player_id))


## How many quarter turns a player's Build Gun is turned by, in [0, 4).
func query_player_build_rotation(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_build_rotation[player_id]


## Whether a player is holding Survey View. True the moment the key goes down, even
## though the camera takes the tuned transition to arrive.
func query_player_is_surveying(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_survey_held[player_id] != 0


## How far through the Survey View transition a player is, in fixed point: 0 at eye
## level, Fixed.ONE fully raised, eased so the ends are gentle.
## Whether this player is sprinting. For the HUD; the Simulation reads the flag
## directly rather than going back through a query.
func query_player_is_sprinting(player_id: int) -> bool:
	return _player_sprint_held[player_id] != 0


func query_player_survey_blend(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _survey_blend(player_id)


## How high a player's camera is off the ground, in fixed-point metres. Eye height on
## foot, the tuned Survey View height fully raised, and somewhere between during the
## transition.
func query_player_camera_height_metres(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.lerp_fixed(
		_definitions.player_eye_height, _definitions.survey_height, _survey_blend(player_id)
	)


## Where a player's camera is pointing, in fixed-point turns from level. The player's
## own pitch on foot, tilted down to the tuned Survey View angle as the camera rises.
func query_player_camera_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.lerp_fixed(
		_player_pitch[player_id], -_survey_pitch_turns(), _survey_blend(player_id)
	)


## Where a player's camera stands on the horizontal plane, in fixed-point metres.
## The player's own position, in Survey View as on foot: the camera rises straight up
## and tilts, so a player can walk the Factory while reading it from above.
func query_player_camera_ground_metres(player_id: int) -> FixedVec2:
	return query_player_position(player_id)


## Which way a player is facing, in fixed-point turns in [0, Fixed.TURN). 0 looks
## down -z, which is Godot's forward, and the value increases turning left.
func query_player_yaw_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_yaw[player_id]


## How far from level a player is looking, in fixed-point turns. Positive is up, and
## the magnitude never exceeds `MAX_PITCH_TURNS`.
func query_player_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_pitch[player_id]


## The content definitions this Run is using.
##
## Handed out by reference rather than copied, which is the one exception to the
## copy-out rule and is safe for the reason the rule exists: a loaded definition set
## is immutable, so there is nothing a caller could mutate. A reload replaces it.
func query_definitions() -> Definitions:
	return _definitions


## Whether the definitions loaded cleanly. False means the Run must not start.
func query_definitions_loaded() -> bool:
	return not _definitions.has_errors()


## Why the definitions did not load, each naming the file and the row. Empty when
## they did.
func query_definition_errors() -> PackedStringArray:
	return _definitions.errors.duplicate()


## The digest of the definition set in use. What a recording stores so a replay
## cannot quietly run against different content.
func query_definition_digest() -> int:
	return _definitions.digest()


## How many reloads this Run has applied. 0 for a Run that has not hot-reloaded.
func query_definition_generation() -> int:
	return _definition_generation


## How many Nodes the Map holds.
func query_node_count() -> int:
	return _node_resource.size()


## The tile a Node sits on. An unknown index reads as the origin rather than
## crashing, for the same reason an unknown player does.
func query_node_tile(index: int) -> Vector3i:
	if not _is_node(index):
		return Vector3i.ZERO
	return Vector3i(_node_tile_x[index], _node_tile_y[index], _node_tile_z[index])


## The Resource a Node yields, as an Item id. "" for an unknown Node — never a
## plausible-looking default, because a mistyped index must not read as iron ore.
func query_node_resource(index: int) -> String:
	if not _is_node(index):
		return ""
	return _node_resource[index]


## How many crafts a Node has given up at `depth.breach_tier` or deeper. What a player reads
## to know how close their deep mine is to opening a hole — the counter is hashed state rather
## than an estimate, for the reason `query_machine_heat_units` is.
func query_node_deep_crafts(index: int) -> int:
	if not _is_node(index):
		return 0
	return _node_deep_crafts[index]


## How many deep crafts open a Breach. The threshold the count above is read against, so a
## HUD can show "31/40" rather than a number with no scale.
func query_node_deep_crafts_until_a_breach() -> int:
	return _definitions.depth_breach_crafts


## Whether a Node has already opened its Breach. One each, ever, so a player knows the mine
## they have been running for an hour is not about to cost them a second hole.
func query_node_has_opened_a_breach(index: int) -> bool:
	if not _is_node(index):
		return false
	return _node_breach_opened[index] != 0


## The Depth tier a Node sits at. Tiers start at 1; 0 for an unknown Node.
func query_node_depth(index: int) -> int:
	if not _is_node(index):
		return 0
	return _node_depth[index]


## The Node on a tile, or -1. Nodes occupy one tile each.
func query_node_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_node_count()):
		if query_node_tile(index) == tile:
			return index
	return -1


## How many Machines are standing.
func query_machine_count() -> int:
	return _machine_id.size()


## The definition id of a Machine, as written in `content/machines.csv`. "" for an
## unknown index.
func query_machine_id(index: int) -> String:
	if not _is_machine(index):
		return ""
	return _machine_id[index]


## Why placing `machine_index` at `tile`, turned by `rotation` quarter turns, would be
## refused — or `Refusal.NONE` if it would succeed.
##
## A projection of state that has not changed: asking costs nothing and changes
## nothing, which is what lets the hologram ask every frame about the tile it is
## hovering over and put the reason on screen before a player clicks. The wording
## belongs to the Godot layer; the rule belongs here.
func query_build_refusal(player_id: int, machine_index: int, tile: Vector3i, rotation: int) -> int:
	return _build_refusal(player_id, machine_index, tile, rotation)


## Which way a Machine faces, in quarter turns.
func query_machine_rotation(index: int) -> int:
	if not _is_machine(index):
		return 0
	return _machine_rotation[index]


## The footprint a Machine occupies, turned by its rotation: (tiles along x, tiles
## along z). The renderer sizes a mesh from this rather than from the file's two
## columns, so a turned Machine is drawn over the ground it actually covers.
func query_machine_footprint(index: int) -> Vector2i:
	return _machine_size(index)


## The tile a Machine's footprint is anchored at.
func query_machine_tile(index: int) -> Vector3i:
	if not _is_machine(index):
		return Vector3i.ZERO
	return Vector3i(_machine_tile_x[index], _machine_tile_y[index], _machine_tile_z[index])


## The Machine whose footprint covers a tile, or -1. The footprint is whatever
## `content/machines.csv` states, so this answers for every tile a 4x4 Machine sits
## on, not only its anchor.
func query_machine_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_machine_count()):
		var size: Vector2i = _machine_size(index)
		if size == Vector2i.ZERO:
			continue
		if WorldGrid.footprint_covers(query_machine_tile(index), size.x, size.y, tile):
			return index
	return -1


## How much of an Item a Machine is holding in its own output buffer. 0 for an Item
## it has never produced, and for an unknown Machine.
func query_machine_output(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var items: PackedStringArray = _machine_buffer_items[index]
	var slot: int = items.find(item_id)
	if slot == -1:
		return 0
	var counts: PackedInt64Array = _machine_buffer_counts[index]
	return counts[slot]


## The Item ids a Machine is holding, sorted. A copy, like every query.
func query_machine_output_items(index: int) -> PackedStringArray:
	if not _is_machine(index):
		return PackedStringArray()
	var items: PackedStringArray = _machine_buffer_items[index]
	return items.duplicate()


## How many Items of all kinds a Machine is holding.
func query_machine_output_total(index: int) -> int:
	if not _is_machine(index):
		return 0
	var total: int = 0
	for count: int in _machine_buffer_counts[index]:
		total += count
	return total


## How much of an Item a Machine is holding for its Recipe, in its input buffer. 0 for
## an Item its Recipe has no use for, and for an unknown Machine.
func query_machine_input(index: int, item_id: String) -> int:
	if not _is_machine(index):
		return 0
	var items: PackedStringArray = _machine_input_items[index]
	var slot: int = items.find(item_id)
	if slot == -1:
		return 0
	var counts: PackedInt64Array = _machine_input_counts[index]
	return counts[slot]


## The Item ids a Machine is holding for its Recipe, sorted.
func query_machine_input_items(index: int) -> PackedStringArray:
	if not _is_machine(index):
		return PackedStringArray()
	var items: PackedStringArray = _machine_input_items[index]
	return items.duplicate()


## How many Items of all kinds a Machine is holding for its Recipe.
func query_machine_input_total(index: int) -> int:
	if not _is_machine(index):
		return 0
	var total: int = 0
	for count: int in _machine_input_counts[index]:
		total += count
	return total


## How much of an Item a Machine will hold for its Recipe before its input port refuses
## more. 0 for an Item its Recipe does not use — which is how a Belt pointed at the
## wrong Machine backs up instead of quietly voiding what it carries.
func query_machine_input_capacity(index: int, item_id: String) -> int:
	return _input_capacity(index, item_id)


## How much of an Item the whole Factory is holding — in output buffers, in input
## buffers, and riding on Belts. What a HUD shows, and it counts the Belts because ore
## in transit has not vanished.
func query_item_total(item_id: String) -> int:
	var total: int = 0
	for index: int in range(query_machine_count()):
		total += query_machine_output(index, item_id)
		total += query_machine_input(index, item_id)
	for index: int in range(query_belt_count()):
		var items: PackedStringArray = _belt_item_ids[index]
		for slot: int in range(items.size()):
			if items[slot] == item_id:
				total += 1
	return total


## Whether a Machine cannot run for want of its inputs.
##
## The one question a player asks of a Machine that is doing nothing, answered by the
## Simulation rather than inferred by the renderer from a count that stopped moving. A
## Miner is starved when the ground under it holds no Node its Recipe can take; a crafter
## is starved when its input buffer does not hold a whole Recipe's worth.
##
## False for a Machine with no definition or no Recipe: that is a broken definition set,
## which `query_definitions_loaded` reports, not a starved Machine.
func query_machine_is_starved(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return false
	if _definitions.recipe_at(definition.recipe_index) == null:
		return false
	return not _machine_has_its_inputs(index, definition)


## The Node a Machine's footprint covers, or -1. A Miner over no Node produces
## nothing, and this is how the rendering layer can say so.
func query_node_under_machine(index: int) -> int:
	if not _is_machine(index):
		return -1
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return -1
	return _node_under_machine(index, definition)


# ── Turrets ───────────────────────────────────────────────────────────────────
# A Turret is read through the Machine queries like anything else — `query_machine_id`,
# `query_machine_input`, `query_machine_is_starved`. What is here is only what a Turret has
# that a Smelter does not: a reach, a target and a magazine.

## Whether a Machine is a Turret: a Machine whose output is damage rather than an Item.
func query_machine_is_turret(index: int) -> bool:
	return _is_turret(index)


## How far a Turret reaches, in fixed-point metres from the centre of its footprint. 0 for
## anything that is not a Turret.
func query_turret_range_metres(index: int) -> int:
	if not _is_turret(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return Fixed.from_int(definition.range_tiles * WorldGrid.TILE_SIZE_METRES)


## The **serial** of the Enemy a Turret is shooting at, or -1 when it is shooting at nothing.
##
## A serial and never an index, because that is what the Simulation itself holds: an index
## shifts the moment anything dies, so a renderer drawing a tracer from one would point at a
## different Crawler on the frame after a kill. Resolve it with `query_enemy_index_of_serial`.
func query_turret_target_serial(index: int) -> int:
	if not _is_turret(index):
		return -1
	return _turret_target_serial[index]


## The tick a Turret last fired on, or -1 for one that never has. What a muzzle flash and a
## tracer are drawn from, and how a test asserts that a Turret did *not* fire.
func query_turret_last_shot_tick(index: int) -> int:
	if not _is_turret(index):
		return -1
	return _turret_last_shot_tick[index]


## How many rounds a Turret is holding: the Items in its input buffer, which for a Turret is
## its magazine. 0 means it does not fire.
func query_turret_ammunition(index: int) -> int:
	return _turret_ammunition(index)


## How many rounds a Turret will hold before its input port refuses more — the top of the
## gauge a player reads from across the Factory.
func query_turret_ammunition_capacity(index: int) -> int:
	if not _is_turret(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return 0
	var capacity: int = 0
	for slot: int in range(recipe.input_count()):
		capacity += _input_capacity(index, _definitions.item_id(recipe.input_item(slot)))
	return capacity


## How many more times a Turret can fire on what it is holding.
##
## Not the same number as `query_turret_ammunition` whenever a Recipe eats more than one
## round a shot — which is exactly what a Cannon Turret's does — so the two are separate
## queries rather than one that is right for the MG and wrong for everything else.
func query_turret_shots_remaining(index: int) -> int:
	if not _is_turret(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null or recipe.input_count() == 0:
		return 0
	var shots: int = -1
	for slot: int in range(recipe.input_count()):
		var needed: int = recipe.input_quantity(slot)
		if needed <= 0:
			continue
		@warning_ignore("integer_division")
		var possible: int = (
			query_machine_input(index, _definitions.item_id(recipe.input_item(slot))) / needed
		)
		if shots == -1 or possible < shots:
			shots = possible
	return maxi(shots, 0)


# ── The Nest, the Breaches, the Waves and the Enemies ─────────────────────────

## The tile the Nest's footprint is anchored at.
func query_nest_tile() -> Vector3i:
	return Vector3i(_nest_tile_x, _nest_tile_y, _nest_tile_z)


## The ground the Nest covers, as (tiles along x, tiles along z). Square, so there is no
## rotation to ask about.
func query_nest_footprint() -> Vector2i:
	return Vector2i(MapLayout.NEST_FOOTPRINT_TILES, MapLayout.NEST_FOOTPRINT_TILES)


## What is left of the Nest, in whole hit points. 0 means the Run is over.
func query_nest_health() -> int:
	return _nest_health


## What the Nest has when it is whole, from `nest.health` in `content/tuning.toml`. What
## a HUD draws a bar against.
func query_nest_max_health() -> int:
	return _definitions.nest_health


## Whether a tile is part of the Nest. True for every tile of the footprint, not only its
## anchor, like `query_machine_at_tile`.
func query_nest_covers_tile(tile: Vector3i) -> bool:
	return _nest_covers(tile)


## How many Breaches the Map has.
func query_breach_count() -> int:
	return _breach_tile_x.size()


## The tile a Breach sits on. The origin for an unknown index, rather than crashing.
func query_breach_tile(index: int) -> Vector3i:
	if index < 0 or index >= query_breach_count():
		return Vector3i.ZERO
	return Vector3i(_breach_tile_x[index], _breach_tile_y[index], _breach_tile_z[index])


## How many Breaches have been announced but have not opened yet.
func query_pending_breach_count() -> int:
	return _pending_breach_tile_x.size()


## Where an announced Breach will open. The origin for an unknown index, rather than crashing.
##
## A projection about a hole that does not exist yet, which is what lets the renderer mark the
## ground and the HUD raise a klaxon over it *before* anything comes out. The same arrangement
## `query_build_refusal` has: the player is told before the fact rather than after it.
func query_pending_breach_tile(index: int) -> Vector3i:
	if index < 0 or index >= query_pending_breach_count():
		return Vector3i.ZERO
	return Vector3i(
		_pending_breach_tile_x[index],
		_pending_breach_tile_y[index],
		_pending_breach_tile_z[index]
	)


## How many ticks of warning an announced Breach has left before it opens.
func query_pending_breach_ticks_remaining(index: int) -> int:
	if index < 0 or index >= query_pending_breach_count():
		return 0
	return _pending_breach_ticks_left[index]


## How long a newly opened Breach is telegraphed for, in whole ticks — what the countdown
## above is a fraction of, so a gauge has a denominator.
func query_breach_telegraph_ticks() -> int:
	return _breach_telegraph_ticks()


## Which Wave the Run has reached. 0 before the first one arrives, and frozen at whatever
## it was once the Run is over — which is the number the Run-over report names.
func query_wave_number() -> int:
	return _wave_number


## How many ticks must still pass before the next Wave arrives. 0 once the Run is over.
##
## The honest answer rather than the clock's: the **later** of what the interval has left
## and what the Telegraph has left, because both have to be satisfied and a Wave arrives
## when the slower of them does. A player reading this is reading the number the Simulation
## will actually act on, which is the only version worth putting on a HUD.
##
## It moves with Heat, in both directions and immediately. That is the point: a player who
## switches on a new line watches this jump towards them, and that is how the bet is made
## legible before it is lost.
func query_ticks_until_next_wave() -> int:
	if query_run_is_over():
		return 0
	var telegraph_left: int = maxi(_telegraph_ticks() - _telegraph_ticks_served, 0)
	if _wave_called_early == 1:
		return telegraph_left
	return maxi(maxi(_wave_interval_ticks() - _wave_elapsed_ticks, 0), telegraph_left)


## How long the gap between Waves currently is, in ticks. The baseline shortened by Heat.
## Read beside `query_ticks_until_next_wave` so a gauge can show the countdown as a
## fraction of the gap it is counting down through.
func query_wave_interval_ticks() -> int:
	return _wave_interval_ticks()


## How many Enemies the current Wave has still to send through each Breach. 0 between
## Waves.
func query_wave_spawns_remaining() -> int:
	return maxi(_wave_queue_kind.size() - _wave_queue_cursor, 0)


## How many Enemies of each kind the current Wave still owes each Breach, by `EnemyKind`.
## What a HUD draws the shape of an incoming Wave from.
func query_wave_spawns_remaining_of_kind(kind: int) -> int:
	var remaining: int = 0
	for index: int in range(_wave_queue_cursor, _wave_queue_kind.size()):
		if _wave_queue_kind[index] == kind:
			remaining += 1
	return remaining


# ── The Telegraph ─────────────────────────────────────────────────────────────

## Whether the Telegraph is showing: a Wave is coming and the warning is up.
##
## True for at least `wave.telegraph_seconds` before **every** Wave, without exception —
## a Wave the clock brought, a Wave a Heat spike pulled forward, and a Wave a player
## called. That is an invariant of `_a_wave_is_due` rather than a convention, which is what
## makes "the core loop never ambushes the player" (DESIGN.md) a property of the code
## instead of a promise about it.
func query_wave_is_telegraphed() -> bool:
	if query_run_is_over() or query_breach_count() == 0:
		return false
	return _telegraph_is_showing()


## How many ticks the Telegraph has been showing, and how long it runs for in total. The
## two numbers a rising gauge is drawn from; there is no audio yet, so the klaxon
## GLOSSARY.md describes is a HUD warning and this is what fills it.
func query_telegraph_ticks_served() -> int:
	return _telegraph_ticks_served


func query_telegraph_ticks() -> int:
	return _telegraph_ticks()


## Whether the Wave now being telegraphed was called by a player rather than by the clock.
## Worth drawing: a called Wave is a decision somebody in the Factory made, and in co-op
## the other three deserve to know it was made rather than merely that a Wave is coming.
func query_wave_was_called_early() -> bool:
	return _wave_called_early == 1


## Why pulling the call-early lever would be refused, or `Refusal.NONE`.
##
## A projection about a pull that has not happened, exactly like `query_build_refusal`: the
## reason is on screen *before* the player commits, which is both better than reporting a
## silence afterwards and the only version that leaves the hash alone.
func query_call_wave_early_refusal(player_id: int) -> int:
	return _call_wave_early_refusal(player_id)


# ── Delivery progression ──────────────────────────────────────────────────────
# What the Nest wants, what it is holding, and what the Run has unlocked. All of it is a
# projection of state the Simulation already holds — nothing here decides anything, and
# `query_delivery_refusal` in particular is a question about a hand-over that has not
# happened, so asking it cannot move the hash.

## How many Delivery tiers the content defines.
func query_delivery_count() -> int:
	return _definitions.delivery_count()


## Which tier the Nest is waiting on, as an index into the definition set, or -1 when the
## chain is finished. The first tier this Run has not completed; nothing is skipped.
func query_next_delivery() -> int:
	return _next_delivery_index()


func query_delivery_id(index: int) -> String:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	return "" if definition == null else definition.id


func query_delivery_display_name(index: int) -> String:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	return "" if definition == null else definition.display_name


func query_delivery_min_depth(index: int) -> int:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	return 0 if definition == null else definition.min_depth


## The Items a tier asks for, in the sorted order the file was parsed into. What the next
## Delivery requires has to be readable, or a player aiming a Factory at a goal is guessing.
func query_delivery_goods(index: int) -> PackedStringArray:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	return PackedStringArray() if definition == null else definition.goods_items.duplicate()


## How many of an Item a tier asks for. Zero for an Item it does not want.
func query_delivery_goods_required(index: int, item_id: String) -> int:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	return 0 if definition == null else definition.goods_required(item_id)


## How many of an Item the Nest is holding against the tier it is waiting on. Always about
## the open tier, because the counter is cleared the moment one completes.
func query_delivery_goods_delivered(item_id: String) -> int:
	return _delivered_so_far(item_id)


## Whether a tier has been completed.
func query_delivery_is_complete(index: int) -> bool:
	var definition: DeliveryDefinition = _definitions.delivery_at(index)
	if definition == null:
		return false
	return _completed_delivery_ids.has(definition.id)


## Why handing a Delivery over would be refused, or `Refusal.NONE`.
func query_delivery_refusal(player_id: int) -> int:
	return _delivery_refusal(player_id)


## The deepest Node the Factory is actually mining — the figure Delivery tiers are gated
## against. Derived from the Miners standing on the Map, so it rises when one is built over
## a deeper Node and falls when that Miner comes down.
func query_depth_reached() -> int:
	return _depth_reached()


## How close a player has to be to the Nest's footprint to hand goods over, in fixed-point
## metres.
func query_delivery_reach_metres() -> int:
	return _definitions.nest_delivery_reach


## Whether a player is standing close enough to the Nest to hand goods over.
func query_player_is_at_the_nest(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_is_at_the_nest(player_id)


## Whether a Machine may be built at all, by definition index. False for one whose
## definition exists but which no completed Delivery has unlocked — which is the same
## question `query_build_refusal` answers with `CONTENT_IS_LOCKED`, asked without a tile.
func query_machine_is_unlocked(machine_index: int) -> bool:
	var definition: MachineDefinition = _definitions.machine_at(machine_index)
	if definition == null:
		return false
	return _machine_is_unlocked(definition.id)


## The Gear components this Run has unlocked, by id, sorted. Gear itself is a later
## milestone; what a Run has earned is recorded, hashed and saved from now.
func query_unlocked_gear() -> PackedStringArray:
	return _unlocked_gear_ids.duplicate()


## The Stratagems this Run has unlocked, by id, sorted. Same standing as the Gear list.
func query_unlocked_stratagems() -> PackedStringArray:
	return _unlocked_stratagem_ids.duplicate()


## The Delivery tiers this Run has completed, by id, sorted.
func query_completed_deliveries() -> PackedStringArray:
	return _completed_delivery_ids.duplicate()


# ── Heat ──────────────────────────────────────────────────────────────────────

## The Factory's Heat, in whole heat units.
##
## The number that makes every new Machine a bet: it rises with throughput, it drives when
## the next Wave arrives and what is in it, and it is on the HUD so the bet is informed.
## An integer, with no fixed point behind it anywhere — see `_heat_bleeds`.
func query_heat() -> int:
	return _heat


## How much Heat the Factory is shedding per minute, in heat units. The other half of the
## reading: Heat on its own says how loud the Factory is, and this says how much of that it
## is getting away with.
func query_heat_decay_per_minute() -> int:
	return _definitions.heat_decay_per_minute


## How much Heat the Factory is currently generating per minute, in heat units — the sum of
## every Machine that is producing right now.
##
## A projection, and the Simulation never reads it back. It is where the division lives, in
## the same sense `query_power_ratio` is: the Simulation accrues Heat a whole craft at a
## time and this turns that into a rate for a gauge, so the flooring here cannot reach the
## state hash or move a single unit of Heat.
func query_heat_per_minute() -> int:
	var total: int = 0
	for index: int in range(query_machine_count()):
		total += query_machine_heat_per_minute(index)
	return total


## How much Heat one Machine has added over its whole life, in heat units.
##
## The contributor reading, and the reason a player can make an informed bet rather than
## feeling unlucky: this says which Machine made them hot, in a number that is exact state
## rather than an estimate. A demolished Machine takes its total with it, because the
## Factory it was part of is not the Factory that is standing.
func query_machine_heat_units(index: int) -> int:
	if index < 0 or index >= _machine_heat_units.size():
		return 0
	return _machine_heat_units[index]


## How much Heat one Machine is adding per minute at this moment, in heat units. 0 for a
## Machine that is not producing — starved, newly built, or stopped by a brownout — because
## a Machine that is not producing is not making the Factory loud.
##
## A projection like `query_heat_per_minute`, floored, and never read back by the
## Simulation. Power's duty cycle is deliberately *not* folded in: this reports what the
## Machine's Recipe is worth while it runs, and the Power gauge reports how often it is
## running, so the two readings stay one fact each.
func query_machine_heat_per_minute(index: int) -> int:
	if index < 0 or index >= query_machine_count():
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or not _machine_would_work(index, definition):
		return 0
	if not _power_allows(definition):
		return 0
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return 0
	var per_craft: int = _definitions.heat_per_craft
	if definition.is_miner():
		var node_index: int = _node_under_machine(index, definition)
		if node_index != -1:
			per_craft += _definitions.heat_per_craft_per_depth * _node_depth[node_index]
	@warning_ignore("integer_division")
	var rate: int = per_craft * TICKS_PER_MINUTE / _ticks_per_craft(recipe)
	return rate


## Whether the Run has ended. True from the tick the Nest fell, and never false again.
func query_run_is_over() -> bool:
	return _run_over_tick != -1


## The tick the Run ended on, or -1 while it is still running. Read beside
## `query_wave_number` to report how far a Run got and how long it took.
func query_run_over_tick() -> int:
	return _run_over_tick


## How many Enemies are on the Map.
func query_enemy_count() -> int:
	return _enemy_serial.size()


## Where an Enemy is, in fixed-point metres on the horizontal plane. The origin for an
## unknown index, like an unknown player.
func query_enemy_position_metres(index: int) -> FixedVec2:
	if not _is_enemy(index):
		return FixedVec2.zero()
	return FixedVec2.new(_enemy_x[index], _enemy_z[index])


## The ground tile an Enemy is standing on.
func query_enemy_tile(index: int) -> Vector3i:
	if not _is_enemy(index):
		return Vector3i.ZERO
	return WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])


## An Enemy's remaining hit points. 0 for an unknown index.
func query_enemy_health(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_health[index]


## Which kind of Enemy this is — `ENEMY_KIND_CRAWLER` for everything Milestone 1 spawns.
## -1 for an unknown index, never a plausible-looking default.
func query_enemy_kind(index: int) -> int:
	if not _is_enemy(index):
		return -1
	return _enemy_kind[index]


## An Enemy's serial: a number issued once at spawn and never reused.
##
## The thing to hold on to rather than an index, because indices shift as Enemies die.
## Strictly increasing with index, which is the invariant that makes Enemy iteration order
## deterministic — a test asserts it directly rather than trusting the comment.
func query_enemy_serial(index: int) -> int:
	if not _is_enemy(index):
		return -1
	return _enemy_serial[index]


## The Enemy carrying a serial, or -1 when it is dead or never existed.
##
## The inverse of `query_enemy_serial`, and what the renderer needs to turn a Turret's target
## back into something it can draw a tracer at. Exact rather than approximate: serials ascend
## strictly with index, so this is a binary search and not a guess.
func query_enemy_index_of_serial(serial: int) -> int:
	return _enemy_of_serial(serial)


## The tick an Enemy came through its Breach.
func query_enemy_spawn_tick(index: int) -> int:
	if not _is_enemy(index):
		return -1
	return _enemy_spawn_tick[index]


## Whether an Enemy is in contact with the Nest, and therefore biting it rather than
## walking. What the renderer reads to show a Crawler chewing.
func query_enemy_is_attacking(index: int) -> bool:
	return _enemy_is_in_contact(index)


## The way out of a tile towards the Nest, as a `WorldGrid` direction, or -1 where there is
## none: inside the Nest, inside an obstruction, off the Map, or on ground the Nest cannot
## be walked to from.
##
## The shared field itself, exposed so a test can assert that an obstruction re-routed it
## rather than inferring that from where Enemies happened to end up.
func query_flow_direction(tile: Vector3i) -> int:
	var cell: int = _field_index(tile)
	if cell == -1:
		return -1
	var field: PackedInt64Array = _flowfield()
	return field[cell]


## How many tiles a walk from a tile to the Nest takes along the field, or -1 where the
## Nest cannot be reached. 0 on the Nest's own tiles.
func query_flow_distance_tiles(tile: Vector3i) -> int:
	var cell: int = _field_index(tile)
	if cell == -1:
		return -1
	_flowfield()
	return _flow_distance[cell]


## Whether a tile stops an Enemy walking through it. Machines do; Belts, Nodes and bare
## ground do not. Walls join the answer with the ticket that adds them.
func query_tile_obstructs_enemies(tile: Vector3i) -> bool:
	return _tile_obstructs_enemies(tile)


# ── The Power grid ────────────────────────────────────────────────────────────

## What the one Power grid supplied on the tick that last ran, in whole kilowatts: the
## baseline plant plus every generator that was burning.
func query_power_supply_kw() -> int:
	return _power_supply_kw


## What the Factory drew on the tick that last ran, in whole kilowatts. Only Machines
## that were actually working are on it — an idle Machine draws nothing.
func query_power_demand_kw() -> int:
	return _power_demand_kw


## How much of its demand the Factory is getting, in fixed point: `ONE` when supply meets
## demand or nothing is drawing, and `supply / demand` when it does not.
##
## **This number is for the gauge, and the Simulation never reads it back.** It is the one
## place Power touches fixed point, and `from_rational` floors, so a grid supplying 1
## against a demand of 3 reads as 0.33332... rather than a third. The throttle itself is
## driven by the two integers, not by this — which is exactly why the rounding here can
## never reach the state hash or move a single Item.
func query_power_ratio() -> int:
	if _power_demand_kw <= 0:
		return Fixed.ONE
	if _power_supply_kw >= _power_demand_kw:
		return Fixed.ONE
	return Fixed.from_rational(_power_supply_kw, _power_demand_kw)


## What one Machine is putting on the grid this tick, in whole kilowatts, and 0 for one that
## is not working — because a Machine that is not working is not on the grid at all.
##
## Not a second opinion about the draw: this is the very figure `_read_the_grid` totals, so
## the attribution a player reads off a deep Miner and the brownout they are trying to
## explain are one number. It is where Depth's Power cost becomes visible, which matters
## because a surcharge nothing reports is a surcharge that reads as a bug.
func query_machine_power_draw_kw(index: int) -> int:
	if not _is_machine(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or not _machine_would_work(index, definition):
		return 0
	return _depth_adjusted_draw_kw(index, definition)


## Whether the grid is short: demand above supply. The brownout, as one boolean.
func query_power_is_in_deficit() -> bool:
	return _power_demand_kw > 0 and _power_supply_kw < _power_demand_kw


## Whether the grid held a Machine back on the tick that last ran.
##
## False for a Machine that draws nothing and for one that is not working anyway — a
## starved Smelter is starved, not throttled, and a HUD that confused the two would send a
## player to lay a Belt when the answer is a Boiler.
func query_machine_is_throttled(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or definition.power_draw_kw <= 0:
		return false
	if not _machine_would_work(index, definition):
		return false
	return query_power_is_in_deficit()


## How many Belts are laid.
func query_belt_count() -> int:
	return _belt_tiles.size()


## How many tiles long a Belt's run is. 0 for an unknown Belt.
func query_belt_length_tiles(index: int) -> int:
	if not _is_belt(index):
		return 0
	return _belt_tiles[index]


## Which way a Belt carries, as a `WorldGrid` direction. -1 for an unknown Belt.
func query_belt_direction(index: int) -> int:
	if not _is_belt(index):
		return -1
	return _belt_direction[index]


## The nth tile of a Belt's run, counted from the end Items enter at. The origin for
## an unknown Belt or an out-of-range step, for the same reason an unknown Machine
## reads as the origin rather than crashing.
func query_belt_tile(index: int, step: int) -> Vector3i:
	if not _is_belt(index):
		return Vector3i.ZERO
	if step < 0 or step >= _belt_tiles[index]:
		return Vector3i.ZERO
	return _belt_entry_tile(index) + WorldGrid.direction_step(_belt_direction[index]) * step


## The Belt covering a tile, or -1. A Belt is one tile wide, so this answers for every
## tile of a run and not only its anchor.
func query_belt_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_belt_count()):
		if _belt_covers(index, tile):
			return index
	return -1


## How many Items a Belt is carrying.
func query_belt_item_count(index: int) -> int:
	if not _is_belt(index):
		return 0
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	return offsets.size()


## The Item in one of a Belt's slots, counted from the far end — slot 0 is the Item
## nearest the end it will leave by. "" for an unknown Belt or slot, never a
## plausible-looking default.
func query_belt_item_id(index: int, slot: int) -> String:
	if not _is_belt(index):
		return ""
	var items: PackedStringArray = _belt_item_ids[index]
	if slot < 0 or slot >= items.size():
		return ""
	return items[slot]


## Where an Item on a Belt actually is, in fixed-point metres on the horizontal plane.
##
## The truth rather than an approximation, and the reason the Godot layer needs no
## notion of Belt motion of its own: a backed-up Belt reads as a queue of Items packed
## at their spacing because that is literally where they are.
func query_belt_item_position_metres(index: int, slot: int) -> FixedVec2:
	if not _is_belt(index):
		return FixedVec2.zero()
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if slot < 0 or slot >= offsets.size():
		return FixedVec2.zero()

	var step: Vector3i = WorldGrid.direction_step(_belt_direction[index])
	var entry: FixedVec2 = WorldGrid.tile_centre_metres(_belt_entry_tile(index))
	var half_tile: int = Fixed.from_rational(WorldGrid.TILE_SIZE_METRES, 2)
	# An Item's centre is half a spacing past its own position along the run, measured
	# from the entry *edge* of the first tile rather than from that tile's centre.
	var along: int = _subunits_to_metres(2 * offsets[slot] + _belt_spacing_subunits())
	var from_edge: int = along - half_tile
	return FixedVec2.new(entry.x + step.x * from_edge, entry.z + step.z * from_edge)


## How far along a Belt an Item has travelled, in fixed-point metres from the end it
## entered by. What a test or a diagnostic reads to say where a queue begins.
func query_belt_item_distance_metres(index: int, slot: int) -> int:
	if not _is_belt(index):
		return 0
	var offsets: PackedInt64Array = _belt_item_offsets[index]
	if slot < 0 or slot >= offsets.size():
		return 0
	return _subunits_to_metres(2 * offsets[slot] + _belt_spacing_subunits())


## How many Items a Belt holds when it is completely full: its length times the density
## tuning states.
func query_belt_capacity(index: int) -> int:
	if not _is_belt(index):
		return 0
	return _belt_tiles[index] * _belt_items_per_tile()


## Whether a Belt is backed up: its leading Item has reached the far end and whatever is
## there will not take it.
##
## The diagnosis a player makes by looking at the Factory, available to the HUD and to a
## test as one boolean. True from the first Item that cannot get off, not only once the
## whole run is packed — a Belt one Item short of full is already losing throughput.
func query_belt_is_stalled(index: int) -> bool:
	if not _is_belt(index):
		return false
	return _hand_off_blocked(index)


## Whether a Belt is carrying as many Items as it can hold.
func query_belt_is_full(index: int) -> bool:
	if not _is_belt(index):
		return false
	return query_belt_item_count(index) >= query_belt_capacity(index)


## How many ticks pass between consecutive Items on a saturated Belt. The Belt's rating
## from `content/tuning.toml`, turned into the whole number of ticks the Simulation
## actually works in.
func query_belt_ticks_per_item() -> int:
	return _belt_ticks_per_item()


## How many Items fit on one tile of Belt.
func query_belt_items_per_tile() -> int:
	return _belt_items_per_tile()


## The grid's tile edge length in fixed-point metres. 2 m, per DESIGN.md.
func query_tile_size_metres() -> int:
	return WorldGrid.tile_size_metres()


## How far the Map extends from the origin in tiles, on both horizontal axes.
func query_grid_half_extent_tiles() -> int:
	return WorldGrid.HALF_EXTENT_TILES


## Whether something may be built on a tile: inside the Map, and on a layer the
## build rules allow. Only layer 0 while building is flat.
func query_is_buildable_tile(tile: Vector3i) -> bool:
	return WorldGrid.is_buildable(tile)


## The centre of a tile on the horizontal plane, in fixed-point metres. What the
## rendering layer places a Machine's mesh at.
func query_tile_centre_metres(tile: Vector3i) -> FixedVec2:
	return WorldGrid.tile_centre_metres(tile)


## The floor height of a layer in fixed-point metres. 0 for the ground; a 4 m storey
## is reserved above it for when vertical building is switched on.
func query_layer_height_metres(layer: int) -> int:
	return WorldGrid.layer_height_metres(layer)


## The tile a Belt's run is anchored at — the end Items enter from.
func _belt_entry_tile(index: int) -> Vector3i:
	return Vector3i(_belt_tile_x[index], _belt_tile_y[index], _belt_tile_z[index])


## Whether a Belt's run covers a tile.
func _belt_covers(index: int, tile: Vector3i) -> bool:
	var entry: Vector3i = _belt_entry_tile(index)
	if tile.y != entry.y:
		return false
	var step: Vector3i = WorldGrid.direction_step(_belt_direction[index])
	var along: int = (tile.x - entry.x) * step.x + (tile.z - entry.z) * step.z
	if along < 0 or along >= _belt_tiles[index]:
		return false
	return entry + step * along == tile


func _is_enemy(index: int) -> bool:
	return index >= 0 and index < _enemy_serial.size()


func _is_belt(index: int) -> bool:
	return index >= 0 and index < _belt_tiles.size()


func _is_machine(index: int) -> bool:
	return index >= 0 and index < _machine_id.size()


func _is_node(index: int) -> bool:
	return index >= 0 and index < _node_resource.size()


func _is_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < _player_x.size()
