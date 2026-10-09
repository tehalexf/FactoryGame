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

## Chaff: the Enemy kind that swarms the Nest. An **alias** of `EnemyKind.CRAWLER` rather than
## a second copy of the number: `content/waves.csv` names kinds in words, `EnemyKind` is
## where a name and its integer meet, and a second authority here would be the one that
## drifted. Held as an integer in `_enemy_kind`, which is how the Breaker below joined the same
## arrays rather than getting its own — and how the Siege Hulk will.
const ENEMY_KIND_CRAWLER: int = EnemyKind.CRAWLER

## The Enemy kind that hunts the Factory rather than the Nest. An **alias** of
## `EnemyKind.BREAKER` for the same reason `ENEMY_KIND_CRAWLER` is one of its constant: the
## Wave table names kinds in words and a second authority here would be the one that
## drifted. A Breaker is an entry in the same Enemy arrays as a Crawler; what differs is
## which field it steers by and what it bites.
const ENEMY_KIND_BREAKER: int = EnemyKind.BREAKER

## The boss: the Enemy kind that bombards the Factory from beyond Turret range. An **alias**
## of `EnemyKind.SIEGE_HULK` for the reason the other two are aliases of theirs.
##
## It is an entry in the same Enemy arrays as a Crawler, which is the claim ADR 0001's whole
## Enemy scale target rests on: a boss is one more kind integer plus the state the other kinds
## do not have — which way it is facing — carried as **one more parallel array** rather than as
## a class, a second index space or an exception anywhere in the loop. What it adds to
## `_enemies` is two lines; what it adds to the data layout is two arrays.
const ENEMY_KIND_SIEGE_HULK: int = EnemyKind.SIEGE_HULK

## How far past `depth.breach_offset_tiles` the search for somewhere to put a new Breach will
## widen if every tile on the ring is already taken. Four, which is far more slack than the
## shipped Map needs — the point is that a crowded corner of the Map degrades into a Breach a
## few tiles further out rather than into no consequence at all.
const RING_SEARCH_WIDENING: int = 4

## Degrees in one whole turn. Angles are turns everywhere inside the Simulation; the
## tuning file is allowed degrees because that is how a human reasons about a tilt.
const DEGREES_PER_TURN: int = 360

## What an Enemy or a Repair Pylon has found to act on, as the `x` of a `(what, which)` pair.
##
## Three kinds of thing in the Factory have hit points — the Nest, a Machine and a Wall — and
## they live in three different index spaces, so "what is in front of me" cannot be one
## integer. A `Vector2i` rather than two returns or a packed integer: it is typed, it costs no
## allocation, and `BITE_NOTHING` is unambiguous where a plain -1 would collide with the
## perfectly ordinary Machine index 0.
const BITE_NOTHING: int = 0
const BITE_NEST: int = 1
const BITE_MACHINE: int = 2
const BITE_WALL: int = 3

## A player. The fourth thing in the Factory with hit points, added when players acquired
## health — and it slots into the same pair rather than into a second mechanism, which is
## what #11 said it would: "a player is one more clause in `_enemy_contact_target`, ranked
## below a Machine". The `y` is a player id rather than an index into an array that shifts,
## because player ids do not shift.
const BITE_PLAYER: int = 4

## What state a player's life is in. Three values and no more: a player is on their feet,
## is Downed and bleeding out, or is dead and waiting to come back at the Nest
## (GLOSSARY.md).
##
## One integer rather than two flags, because the three are mutually exclusive and a pair
## of booleans would make "Downed and dead at once" representable. Held alongside
## `_player_life_since_tick`, so how long a player has been in the state they are in is
## arithmetic rather than a second counter to keep in step — and a state entered *this*
## tick has elapsed zero ticks by construction, which is the same "does not act on the tick
## it arrived" rule a Machine and an Enemy obey.
const LIFE_ALIVE: int = 0
const LIFE_DOWNED: int = 1
const LIFE_DEAD: int = 2

## What a Repair Pylon has found to mend, in the same shape and the same index spaces, less
## the Nest — mending the Nest would un-end a Run, and `_run_over_tick` exists so that nothing
## can (see `_damage_the_nest`).
const MEND_NOTHING: int = BITE_NOTHING
const MEND_MACHINE: int = BITE_MACHINE
const MEND_WALL: int = BITE_WALL

## What a Siege Hulk has found to shell, in the same `(what, which)` shape and the same index
## spaces — a Machine or the Nest, and nothing else. A bombardment aimed at a Wall would be
## the Hulk spending six seconds on the cheapest thing in the game; aimed at a player it would
## be a homing shell rather than artillery.
const BOMBARD_NOTHING: int = BITE_NOTHING
const BOMBARD_MACHINE: int = BITE_MACHINE
const BOMBARD_NEST: int = BITE_NEST

## What a player's shot found, as the `x` of a `(what, which)` pair.
##
## Two index spaces rather than one, for the reason `BITE_*` names four: an Enemy index and a
## Hive index are different spaces, and a plain -1 would collide with the perfectly ordinary
## index 0. A Hive is a structure out on the Map rather than an Enemy that walks (GLOSSARY.md),
## so it is its own arrays here exactly as the Nest and the Walls are their own arrays there —
## and a round resolves against both in one pass, because a player aiming down a line does not
## care which of the Enemy's two kinds of thing is standing in it.
const HIT_NOTHING: int = 0
const HIT_ENEMY: int = 1
const HIT_HIVE: int = 2


## Why a Build Gun intent would be refused.
##
## A refused build stays a silent no-op whose hash does not move — a misaimed Build
## Gun is an ordinary thing for a player to do. The *reason* is therefore not stored
## state but a pure projection: `query_build_refusal` answers it about a placement
## that has not happened, so the hologram can show the reason before the click rather
## than after it, and `_apply_build_machine` consults the same function so the two can
## never disagree.
## The Machine tool: a click places what the Build Gun is holding. What a Run opens on.
const BUILD_TOOL_MACHINE: int = 0

## The Belt tool: a press, a drag and a release lay a Belt route. A Belt is not a Machine
## and cannot sit on the Machine list, so it is a tool rather than one more position.
const BUILD_TOOL_BELT: int = 1


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
	## The wrench was held on something whole. Nothing to mend is not a failure, but a HUD
	## that said nothing would leave a player holding a key at a Machine that was already
	## fine.
	NOT_DAMAGED = 16,
	## The wrench was held on something further away than `wrench.reach_metres`. Repairing is
	## melee: a player has to come and stand at the Machine.
	OUT_OF_REACH = 17,
	## The intent names no Item in the current definition set. The Item twin of
	## `NO_SUCH_MACHINE`: an index out of the sorted Item ids, which a hot-reload that
	## removed a Recipe can leave a client holding.
	NO_SUCH_ITEM = 18,
	## The Nest's store is holding none of the Item asked for. There is a counter and a
	## player standing at it, and nothing on it to take.
	NOTHING_TO_WITHDRAW = 19,
	## The player is Downed or dead. One reason covering both, because what a player can do
	## in either is the same — nothing — and a HUD that distinguished them would be saying
	## twice what `query_player_is_downed` already says once.
	##
	## **A refusal rather than a mode.** Nothing in the Simulation asks "is acting currently
	## permitted"; what it asks is whether *this* player is on their feet, which is a fact
	## about them in the same way being out of reach is a fact about where they stand. So
	## the Build Gun's hologram goes on reporting the real reason it will not place, and
	## building is still never gated (DESIGN.md).
	PLAYER_IS_DOWN = 20,
	## The player is holding no weapon — which a Run never opens in, because
	## `player.starting_weapon` is required, but which a hot-reload that deleted a row can
	## produce mid-Run.
	NO_WEAPON = 21,
	## The weapon is loaded but the player is not carrying enough of what it spends.
	## **Firing consumes Ammunition from the player's own pockets**, so this is the
	## first-person half of the keystone loop: the Factory is what keeps you shooting.
	OUT_OF_AMMUNITION = 22,
	## The weapon has not finished its interval between shots. Not a failure and not worth
	## a HUD line of its own — it is what a trigger held down looks like between rounds —
	## but the projection has to name it rather than report `NONE` about a tick in which
	## nothing happens.
	WEAPON_NOT_READY = 23,
	## The intent names no piece of Gear in the current definition set.
	NO_SUCH_GEAR = 24,
	## The Gear exists but no Delivery has unlocked it yet. The same standing
	## `CONTENT_IS_LOCKED` has for a Machine, and a separate reason because a player
	## reading "locked" wants to know *what* is locked.
	GEAR_IS_LOCKED = 25,
	## A component was fitted to a slot that is not the one its own row names, or a weapon
	## frame was fitted as though it were a component. Refused rather than redirected: the
	## intent is meant to describe the fitting completely, and silently moving it somewhere
	## else would make a recorded script lie about what happened.
	WRONG_SLOT = 26,
	## A revive was held on a player who is not Downed — on their feet, already dead, or the
	## rescuer themselves.
	NOTHING_TO_REVIVE = 27,
	## A revive was held on a solo Run. **Solo play has no Downed state** (GLOSSARY.md),
	## so there is never anybody to pick up.
	NO_TEAMMATE = 28,
	## The intent names no Stratagem in the current definition set. The Stratagem twin of
	## `NO_SUCH_MACHINE`: an index out of the sorted Stratagem ids, which a hot-reload that
	## deleted a row can leave a client holding.
	NO_SUCH_STRATAGEM = 29,
	## The Stratagem exists but no Delivery has unlocked it yet. The standing
	## `CONTENT_IS_LOCKED` has for a Machine and `GEAR_IS_LOCKED` has for a component, and a
	## reason of its own because a player reading "locked" wants to know *what* is locked.
	STRATAGEM_IS_LOCKED = 30,
	## The dial was worked at a tile with no Silo on it. A Silo's dial is a physical thing on
	## a physical Machine (DESIGN.md: diegetic controls are operated in the world), so there
	## is somewhere it has to be.
	NO_SILO_THERE = 31,
	## The Silo is already loaded, and **a completed load cannot be undone** (GLOSSARY.md:
	## committing a Charge is irreversible). This is the refusal that makes the irreversibility
	## real rather than a convention: there is no unload intent, and a second load is refused
	## rather than replacing the first. Fire what is in the tube or lose it.
	SILO_ALREADY_LOADED = 32,
	## The Silo is not holding as many Charges as the dial is asking for. Charges are built in
	## advance, never instantaneous (GLOSSARY.md), so the answer is to wait for the Silo to
	## assemble them or to turn the dial down.
	NOT_ENOUGH_CHARGES = 33,
	## The dial is asking for a number of Charges no load may carry — fewer than one, or more
	## than `silo.max_charges_per_load`.
	BAD_CHARGE_COUNT = 34,
	## A Painting was begun with no loaded Silo anywhere on the Map. Nothing to call in: the
	## load comes first and the Painting spends it.
	NOTHING_LOADED = 35,
	## The player is standing somewhere other than the tile they are painting. **A player
	## must stand at the target** (GLOSSARY.md) — that is the whole price of a Stratagem, and
	## it is why Painting is this design's best co-op moment.
	NOT_AT_THE_TARGET = 36,
	## The player is already channelling a Painting, and a Painting leaves them **unable to
	## act** (GLOSSARY.md). A refusal rather than a mode, exactly as `PLAYER_IS_DOWN` is:
	## nothing asks whether acting is currently permitted, it asks whether *this* player has
	## both hands on a designator, which is a fact about them in the same way their wallet is.
	PLAYER_IS_PAINTING = 37,
	## The Build Gun is not in the player's hands — they are holding a weapon, so the left
	## mouse button fires rather than places.
	##
	## **The one reason in this enum that nothing behind the façade ever returns**, and that
	## is deliberate rather than an oversight. Building is never gated: no refusal, no build
	## path and no `_fight` consults `_player_build_mode`, and
	## `test_nothing_in_the_simulation_asks_the_mode_for_permission` holds that line — a
	## player holding a rifle builds exactly as well as one holding the Build Gun, and an
	## `InputAction.build_machine` that arrives is applied whatever is in their hands.
	##
	## What this names is a fact about **an input**, not about a player's permissions: the
	## left button means one thing with a Build Gun out and another with a rifle out, so a
	## click that would have placed does nothing instead. That decision is `game/`'s from
	## end to end — `BuildGun.hand_refusal` is the only thing that returns this — and the
	## reason it is spelled here anyway is that `Refusal` is the shared vocabulary
	## `BuildGun.refusal_text` translates, and a second enum for one value would be two
	## vocabularies for one HUD line. See "Build mode is a hand, not a gate" in CLAUDE.md.
	BUILD_GUN_IS_HOLSTERED = 38,
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

## How high each player is off the ground, in fixed-point metres, and how fast they are
## rising or falling, in fixed-point metres per second.
##
## **Jumping is Simulation state, not a renderer trick**, for exactly the reason yaw and
## velocity are: where a player is standing decides what they can reach, what can reach
## them and where a round leaves from, so a height the camera invented would be a second
## opinion about the world. Both are hashed and both replay.
##
## Building is still flat (DESIGN.md) and there is no collision against anything but the
## ground, so this is a height above layer 0 and nothing else — a player jumping next to a
## Smelter passes through where the Smelter's roof would be. That is the honest limit of
## what #29 shipped, and it is a separate ticket from making movement feel like weight.
var _player_y: PackedInt64Array = PackedInt64Array()
var _player_velocity_y: PackedInt64Array = PackedInt64Array()

## Whether each player's jump key has been released since it last launched them.
##
## **Hashed, unlike the jump intent itself**, because it is what makes a jump a *press*:
## `player.jump_repeats_while_held` is false by default, so holding the key through a
## landing must not launch again, and "has it been let go of" is a fact that outlives the
## tick. Re-armed by the absence of the intent, which is the same way a `MOVE` throttle
## stops.
var _player_jump_armed: PackedInt64Array = PackedInt64Array()

## Whether each player asked to jump this tick.
##
## **Per tick and deliberately not hashed**, exactly like the walking throttle: `_walk`
## consumes it and clears it before the tick ends, so it is zero at every point a hash is
## taken, and sending no `JUMP` is how a player lets go of the key.
var _player_jump_held: PackedInt64Array = PackedInt64Array()

## The tick each player last landed on (-1 for never) and how fast they were falling when
## they did, in fixed-point metres per second.
##
## The *tick* rather than a countdown, which is the arrangement `_player_life_since_tick`
## already uses and for the same reasons: how long ago a landing was is arithmetic over two
## numbers that are hashed anyway, there is no second timer to keep in step, and a landing
## that happened this tick is zero ticks old. Two things read it — the settle that takes
## some of a player's ground acceleration away while they gather themselves, and the camera
## dip, which is scaled by the impact speed so that stepping off a kerb barely registers.
var _player_landing_tick: PackedInt64Array = PackedInt64Array()
var _player_landing_speed: PackedInt64Array = PackedInt64Array()

## How far into a sprint each player is, counted in ticks of
## `player.sprint_ramp_seconds`.
##
## **This is the whole of "sprint is a gait change rather than a multiplier".** One number
## ramps the speed a player is reaching for, widens the field of view and deepens the bob,
## so what a player feels when they start running is a change of gear rather than a figure
## going up. Ticks rather than a fixed-point fraction, for the reason the Survey View lift
## is counted in ticks: the ramp then takes exactly the tuned number of ticks with nothing
## rounding away at either end, and one caught halfway resumes from where it got to.
var _player_sprint_ticks: PackedInt64Array = PackedInt64Array()

## How far through their current stride each player is, in fixed-point turns in
## [0, Fixed.TURN).
##
## **Driven by distance travelled, not by a clock**, which is what makes the bob a *step*
## rather than a wobble: a player walking slowly bobs slowly, a sprinting one bobs fast, and
## a player standing still does not bob at all — none of which falls out of a timer. One
## stride is `player.bob_stride_metres` of ground covered.
##
## In the Simulation rather than in the renderer, which #29 left as an open choice. The
## argument for here is the one Survey View's transition already makes: it is state (a
## player caught mid-stride is in a different state from one caught on the beat), the
## Simulation already owns the camera, and putting it here is what makes the bob's size
## hot-reloadable tuning and makes it replay exactly. It is hashed. **What it is not is
## part of the aim**: the bob comes out of its own `query_player_view_*` projections, which
## only the renderer reads, so a shot still leaves from eye height and a hologram still
## snaps to the tile the player is pointing at rather than to the one their footfall
## nudged it onto.
var _player_step_phase: PackedInt64Array = PackedInt64Array()

## Whether each player has the Build Gun in their hands rather than their weapon, and the
## tick they last swapped on (-1 for never).
##
## **This is not a mode in the gating sense, and nothing in the Simulation reads it.** Not
## one refusal consults it, not `_fight`, not `_apply_build_machine` — grep for it and the
## only callers are the three queries below. Building is never gated (GLOSSARY.md,
## DESIGN.md: the Build Gun is available at all times, including mid-Wave) and #29 did not
## change that; what this flag decides is which Input Action `game/player_controller.gd`
## produces from a left click, and which object `WorldView` draws in front of the camera.
## Switching is instant, unlimited, and works mid-Wave and mid-burst.
##
## It is Simulation state anyway, for three reasons that have nothing to do with
## permission: what somebody is holding is a fact about them in the same way their wallet
## is, a recorded replay has to reproduce a swap or the clicks after it mean something
## different, and in co-op what the other three are holding is worth drawing.
##
## The tick rather than a countdown, the arrangement `_player_life_since_tick` and
## `_player_landing_tick` both use: how far through the holster a swap is, is arithmetic
## over two numbers that are hashed anyway.
var _player_build_mode: PackedInt64Array = PackedInt64Array()
var _player_mode_since_tick: PackedInt64Array = PackedInt64Array()

## Which tool is on each player's Build Gun: `BUILD_TOOL_MACHINE` or `BUILD_TOOL_BELT`.
##
## State here for the three reasons `_player_build_mode` is, and **consulted by nothing**
## for the same reason: a tool decides what the mouse means, never what a player may do.
## Grep this name and the only callers are its two queries, `_apply_set_build_tool` and
## `_apply_select_machine` — which puts the Machine tool back, because scrolling to a
## Smelter is a player saying they want to place one.
var _player_build_tool: PackedInt64Array = PackedInt64Array()

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

## Whether each player is holding the Pneumatic Wrench on something this tick, and which
## tile they are holding it on.
##
## **Per tick and deliberately not hashed**, exactly like the walking throttle above and for
## the same reason: `_repair` consumes both and clears both before the tick ends, so they are
## zero at every point a hash is taken, and a player who stops sending the intent stops
## repairing. Repairing is a *held* act — the acceptance criterion is that a Machine is
## restored over time — so an intent that latched would mend a Factory a player had walked
## away from.
var _player_repair_held: PackedInt64Array = PackedInt64Array()
var _player_repair_tile_x: PackedInt64Array = PackedInt64Array()
var _player_repair_tile_y: PackedInt64Array = PackedInt64Array()
var _player_repair_tile_z: PackedInt64Array = PackedInt64Array()

## Each player's unspent fraction of a hit point of hand repair, as an integer credit
## against `TICKS_PER_SECOND`.
##
## Authoritative state, and the reason repair replays identically. `wrench.repair_points_per_second`
## is not a whole number of points per tick, so the remainder is carried here exactly as the
## Power grid carries kilowatt-ticks and Heat carries its decay: every tick of a held wrench
## banks `points_per_second` of credit and every whole `TICKS_PER_SECOND` of credit spends one
## hit point. Over any window a Machine has gained exactly
## `floor(ticks * points_per_second / TICKS_PER_SECOND)` — **one floor applied to the total,
## never one per tick.** There is no fixed point in the mechanism at all, so there is nothing
## for it to lose over a forty-hour Run.
##
## Credit does not survive letting go, the same rule Power credit and Heat credit obey: a
## player cannot tap the key for an hour and then spend the bank in one tick.
var _player_repair_credit: PackedInt64Array = PackedInt64Array()

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

## What is left of each player, in whole hit points, and whether they are on their feet.
##
## **A player had no health in the Simulation until this ticket**, which is why #11 could
## only read GLOSSARY.md's "a Breaker prefers Machines rather than players" as "rather than
## the Nest". Now there is a third term, and nothing in `_enemy_contact_target` changed
## beyond gaining a clause ranked below a Machine — the shape #11 promised.
##
## Whole points, like a Machine's and the Nest's, for the reason those are: damage is
## counted in them and a fraction of a hit point is a rounding rule nobody needs.
var _player_health: PackedInt64Array = PackedInt64Array()

## `LIFE_ALIVE`, `LIFE_DOWNED` or `LIFE_DEAD`, and the tick that state began on.
##
## The tick rather than a countdown, so how long a player has been Downed is
## `_tick - _player_life_since_tick` — arithmetic over two numbers that are hashed anyway,
## with no second counter to keep in step and no chance of a timer surviving a transition.
## It also gives the "does not act on the tick it arrived" rule for free: a player Downed
## this tick has been Downed for zero ticks, so they do not spend a tick of their bleed-out
## on the tick they lost their footing.
var _player_life_state: PackedInt64Array = PackedInt64Array()
var _player_life_since_tick: PackedInt64Array = PackedInt64Array()

## The weapon frame in each player's hands, by Gear id.
##
## The *id* rather than the Gear index, for the reason `_player_selected_machine` holds an
## id: a hot-reload resorts the table, and a player must not find a different weapon in
## their hands because somebody added a row.
var _player_weapon: PackedStringArray = PackedStringArray()

## What is fitted to each player's frame: one **sorted** `PackedStringArray` of Gear ids
## per player, holding only what is actually fitted.
##
## **This is where "power comes from combination rather than from tiers" is stored**, and
## it is the same shape a player's pockets are, for the same two reasons. Ids rather than
## indices, so a hot-reload that resorts the Gear table cannot swap one component for
## another under a player's hands — and **ids rather than one entry per slot**, because a
## slot's *index* is interned from the table too and a reload that added a kind would
## renumber the slots while a positional array stayed put. A slot is not stored anywhere:
## which slot a component occupies is its own row's `kind`, so there is one authority for
## that and the fitted set cannot contradict it.
##
## Sorted, so iteration order is a property of what is fitted rather than of the order it
## was fitted in — the rule every other id array in this file obeys.
var _player_component_ids: Array = []

## Ticks each player still has to wait before their weapon will fire again, and the tick it
## last fired on.
##
## The cooldown is counted down rather than compared against a stored tick, because
## `seconds_per_shot` is hot-reloadable: a stored "fired at tick n" compared against a rate
## that changed mid-interval would jump the next shot forward or back, where a counter just
## finishes the interval it started. The last-shot tick is kept beside it because the
## renderer needs to know when to play the Shoot take and the muzzle flash, and a view that
## inferred it from a cooldown would miss a shot whose interval is one tick.
var _player_fire_cooldown: PackedInt64Array = PackedInt64Array()
var _player_last_shot_tick: PackedInt64Array = PackedInt64Array()

## How far each shot has kicked the view up and not yet come back down, in fixed-point
## turns.
##
## **Recoil is Simulation state because it moves where the next shot goes**, not merely
## where the camera points. A kick that only the renderer knew about would be a lie about
## aiming, and the pitch it adds to is authoritative state already. It recovers linearly
## towards zero at `gear.view_kick_recover_seconds`, so the climb of a held burst is a
## straight line a player can learn to pull against — which is the whole of what makes
## automatic fire a skill rather than a dice roll.
var _player_view_kick_turns: PackedInt64Array = PackedInt64Array()

## Each rescuer's unspent fraction of a hit point of revive, as an integer credit against
## `TICKS_PER_SECOND`.
##
## The same mechanism `_player_repair_credit` is, for the same reason and with the same
## rule: one floor applied to the total and never one per tick, and credit does not survive
## letting go or walking out of reach. A revive is hand repair pointed at a person.
var _player_revive_credit: PackedInt64Array = PackedInt64Array()

## Whether each player is holding the trigger this tick, and who each is holding a revive
## on (-1 for nobody).
##
## **Per tick and deliberately not hashed**, exactly like the walking throttle and the
## wrench: `_fight` and `_revive` consume and clear both before the tick ends, so they are
## zero at every point a hash is taken, and a player who lets go stops. Automatic fire is
## therefore the absence of letting go rather than a latch somebody has to remember to
## clear.
var _player_fire_held: PackedInt64Array = PackedInt64Array()
var _player_revive_target: PackedInt64Array = PackedInt64Array()

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

## The Nest's **store**: what a Belt has delivered past the open Delivery's bill, as parallel
## sorted Item ids and counts — the same shape the counter above, a Machine's buffers and a
## player's pockets use.
##
## This is the faucet that makes the Run a loop rather than a one-way spend. Build materials
## used to go only outwards — into Machines, back only from a demolish or the call-early
## bounty — so nothing the Factory made could reach the Build Gun and a Run could not fund a
## second Ammo Press out of its own output (issue #27). A Belt running into the Nest now pays
## the bill first and banks the rest, and `WITHDRAW_FROM_NEST` is how it comes back out. So
## the Nest is where a Run banks as well as where it spends and what it defends, which is the
## same argument that put progression there.
##
## **Capped, at `nest.store_capacity_per_item` each.** Three reasons, and the first is the
## one that decides it: an unbounded store is an infinite sink, and a Belt that can always
## hand off never backs up — which would delete the one legibility mechanism this project has
## at exactly the place a player is looking. Bounded, a full store refuses the hand-off and
## the Belt packs up visibly, which is the rule a full input buffer already obeys and not a
## new one. Second, a cap is a reason to keep building rather than hoarding, and it gives a
## late Factory's surplus somewhere to *go* that is not a warehouse. Third, it bounds what
## the hash and the save file carry, which an unbounded one does not.
##
## **Separate arrays from the counter above, not one pot.** What is banked is spendable and
## what is on the counter is spent: the counter clears when a tier completes and the store
## does not, and a HUD reading "2/3" must never be a surplus. One pot would have to tell the
## two apart anyway, with a rule rather than with a field.
var _nest_store_items: PackedStringArray = PackedStringArray()
var _nest_store_counts: PackedInt64Array = PackedInt64Array()

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

## The Hives standing on the Map, in the canonical tile order `MapLayout` sorted them into,
## and what is left of each.
##
## **A Hive is a structure rather than an Enemy that walks**, so it is its own parallel arrays
## exactly as the Nest and the Walls are — the Enemy's half of the arrangement the Factory
## already has. GLOSSARY.md calls it "an Enemy structure out on the Map that adds continuous
## pressure": it does not path, it does not bite, and the only question it answers is how much
## is left of it.
##
## Deliberately **not** an entry in the Enemy arrays, which was the other candidate and is the
## wrong one twice over. It would put something that never moves through a movement loop and a
## flowfield on every tick of every Run; and it would make `query_enemy_count` — the number the
## HUD draws as "the swarm" and the number every Enemy test asserts on — permanently two
## higher on the shipped Map than the Wave that is actually arriving. The Siege Hulk is the
## thing this ticket makes one more Enemy entry, because a Hulk *is* an Enemy: it walks, it
## hunts and it dies. A Hive is furniture with hit points.
##
## Where they are is geography and comes out of `MapLayout`; what is left of them is Simulation
## state, because **a destroyed Hive never comes back**. That permanence is the whole mechanic:
## "destroying one reduces pressure permanently but requires leaving the Factory"
## (GLOSSARY.md), and there is nowhere in this file that appends to these arrays after
## construction, which is what makes the sentence structural rather than a promise.
var _hive_tile_x: PackedInt64Array = PackedInt64Array()
var _hive_tile_y: PackedInt64Array = PackedInt64Array()
var _hive_tile_z: PackedInt64Array = PackedInt64Array()
var _hive_health: PackedInt64Array = PackedInt64Array()

## The shells in the air: where each one will land, in fixed-point metres, and how many ticks
## it has left to fly.
##
## **A shell is in flight rather than instantaneous, and that is the Telegraph rule rather
## than a flourish.** Nothing in this project may arrive unannounced (DESIGN.md), so the impact
## point is on the ground with a countdown for `siege_hulk.shell_flight_seconds` before
## anything happens there — long enough to walk out of the blast, which is what turns a
## bombardment from damage into a thing a player plays against.
##
## Appended in Enemy index order, which is ascending spawn serial, and landed in index order,
## so which of two shells lands first is fixed by which Hulk fired first. No serial, because
## nothing holds on to a shell: it is in the air for three seconds and then it is a crater.
var _shell_x: PackedInt64Array = PackedInt64Array()
var _shell_z: PackedInt64Array = PackedInt64Array()
var _shell_ticks_left: PackedInt64Array = PackedInt64Array()

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
##
## A Siege Hulk's shell runs on this same counter, and **so does its stomp**, which is the
## whole of why melee against it is useful rather than suicidal: one action per interval means
## a player standing at its feet is a player stopping the bombardment, at the only price this
## game charges for anything.
var _enemy_attack_cooldown: PackedInt64Array = PackedInt64Array()

## Whether each Enemy has broken ranks: 1 once it steers by the Factory's field rather than
## the Nest's, 0 while it is still marching with the Wave.
##
## **#34's latch, and the reason it is state rather than a predicate.** The switch is made on
## how far the Nest and the nearest Machine are — `_flow_distance` and `_machine_flow_distance`
## — and walking towards a Machine afterwards carries the Breaker *away* from the Nest again, so
## a Breaker that re-decided every tick would cross back over the boundary on its first step and
## shuffle on it for ever. Latching is both the fix and the better behaviour: a Breaker that has
## chosen a Machine commits to it, which is what makes the turn something a player can watch
## happen rather than a flicker. See `_breaker_has_broken_ranks` for the rule itself.
##
## Hashed, because it decides where an Enemy walks next, and therefore which Machine falls.
## One entry per Enemy, every Enemy, no branch — a parallel array is parallel. It is 0 for ever
## for a Crawler, whose two fields are the same field, and for a Siege Hulk, which steers by
## the Nest's field by design and has its own clause in `_enemies`.
var _enemy_broke_ranks: PackedInt64Array = PackedInt64Array()

## The point in fixed-point metres each Enemy is facing — the thing it last shelled, stomped or
## walked towards.
##
## **The one piece of state the Siege Hulk needs that no other kind does, and therefore one
## more parallel array rather than a class.** It is what makes the weak point real: a Hulk's
## front is armoured and its back is not, so "where did this hit come from" has to be a
## question the Simulation can answer exactly.
##
## A *point* rather than an angle, and that is the decision worth recording. An angle would
## need an arc-tangent, which fixed point does not have and which would mean a second table
## beside `Fixed.sin_turns` — where a point reduces the whole question to the **sign of one dot
## product**: the hit came from behind exactly when the gap to the shooter points away from the
## gap to what the Hulk is facing. No normalisation, no rounding rule, no trigonometry, and
## nothing for two clients to disagree about. The renderer turns it into a yaw with `atan2`,
## which is `game/`'s business and a float it is allowed to have.
##
## Meaningless for a Crawler and a Breaker, which carry no armour, and held for them anyway
## because a parallel array is parallel: one entry per Enemy, every Enemy, no branch.
var _enemy_face_x: PackedInt64Array = PackedInt64Array()
var _enemy_face_z: PackedInt64Array = PackedInt64Array()

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

## The second shared field: the same sweep, seeded on **every Machine's footprint** rather
## than on the Nest. What a Breaker steers by.
##
## A field rather than a target per Breaker, for exactly the reason the Nest's is one: a
## second breadth-first sweep is O(map) once and is then amortised across every Breaker
## alive, where "walk towards the nearest Machine" is a scan of the Factory per Enemy per
## tick and a path that has to be re-found every time a Machine falls. Two sweeps over 16641
## tiles is twice 2.5 ms on the ticks that rebuild and nothing at all on the ticks that do
## not — against O(Breakers x Machines) every single tick for the alternative.
##
## The seeds are the Machine tiles themselves, which are also obstructions, so the sweep
## starts *on* them at distance 0 and expands outward into free ground. A tile adjacent to a
## Machine therefore points at it, and nothing routes *through* a Machine, which is the same
## arrangement the Nest's field has.
##
## A Factory with no Machines leaves this empty — every tile -1 — and a Breaker with nothing
## to break falls back to the Nest's field. That is the right behaviour rather than a
## degenerate one: the Breaker's whole preference is Machines *over* the Nest, not instead
## of it.
##
## Derived, so it is rebuilt rather than hashed, under the same `_flowfield_stale` flag and
## in the same pass: both fields are a pure function of the Map and the obstructions on it,
## and anything that invalidates one invalidates the other.
var _machine_flow_direction: PackedInt64Array = PackedInt64Array()
var _machine_flow_distance: PackedInt64Array = PackedInt64Array()

## How high the Factory stands on every ground tile, in fixed-point metres — 0 for bare
## ground. The whole of what a player collides with (#30).
##
## **A third field rather than a column on the Enemies' two, deliberately.** An Enemy routes
## by flowfield and asks one question of a tile: may I walk through it. A player asks a
## different one: how high is it, because they can stand on top of the same Machine an
## Enemy has to walk around. Sharing `_flow_blocked` would mean one of the two mechanics
## constraining the other for no reason beyond both being about geometry — a Belt is solid
## to a player and transparent to a Crawler, and that difference is the point rather than an
## inconsistency. Nothing here reads the flowfield and nothing in the flowfield reads this.
##
## A field rather than a scan for the same reason the flowfield is one: collision runs every
## tick for every player, so the per-tick cost has to be a handful of array reads. Building
## it walks the *structures* and paints their footprints — O(Machines + Walls + Belt tiles)
## once, on a tick that built or lost something — against O(structures) per tile tested
## every tick for the alternative. Four tiles per player per tick either way after that.
##
## **There are no overhangs anywhere in this**, and that is what makes the whole mechanic
## cheap: every structure is a solid column from the ground to its height, so there is no
## ceiling to bump into, nothing to be trapped under, and "am I inside something" has
## exactly one answer — move up. Building is flat (DESIGN.md); a storey above layer 0 would
## be the ticket that changes that.
##
## Derived, so it is rebuilt rather than hashed, under its own flag and with the same size
## check `_flowfield` makes: a Run restored from a save arrives holding nothing, and asking
## whether the field is the right size rather than trusting a flag is what makes that
## correct however the Simulation was constructed.
var _solid_height: PackedInt64Array = PackedInt64Array()
var _solid_height_stale: bool = true

## The Walls standing in the Factory, in the order they were built, and what is left of
## each.
##
## **A Wall is not a Machine.** DESIGN.md lists it alongside the Nest and the Belt, outside
## the eight Machines: no row in `content/machines.csv`, no Recipe, no Power, no ports and no
## buffers. It is one tile of ground that obstructs Enemies and can be chewed through, and
## that is the whole of it — which is what makes it the cheapest thing in the game to put in
## front of something expensive.
##
## One tile each rather than a run, unlike a Belt. A Belt is a run because Items travel along
## it and the run is the thing; a Wall is a tile because the only question a Wall answers is
## whether *this* tile is walkable, and because a Wall destroyed in the middle of a run has
## to leave the rest of the run standing. `wall.health` in `content/tuning.toml` is its hit
## points, tuning rather than a row for the same reason a Belt's rating is.
var _wall_tile_x: PackedInt64Array = PackedInt64Array()
var _wall_tile_y: PackedInt64Array = PackedInt64Array()
var _wall_tile_z: PackedInt64Array = PackedInt64Array()
var _wall_health: PackedInt64Array = PackedInt64Array()

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

## What is left of each Machine, in whole hit points.
##
## **This is the array that makes a Factory something that can be taken from you**, and
## therefore the array that turns its layout from a logistics decision into a defensive one
## (GLOSSARY.md: a Machine is mortal). Whole points, like a Crawler's health and a Turret's
## `damage` column: damage and repair are counted in them and never scaled, so there is no
## rounding rule anywhere in combat and nothing to drift over a forty-hour Run.
##
## A Machine is built at the `health` its row declares and destroyed the moment this
## reaches zero. There is no wreck and no rubble: `_destroy_machine` takes it off the Map
## the way a demolition does, so a hole in a Factory's wall is a *hole*, the Belt chain
## through it is broken because the Machine it ran into is not there, and the flowfield
## routes Enemies straight through the gap on the next rebuild. **What does not happen is a
## refund**: a destroyed Machine's build cost and both its buffers are lost with it, where a
## demolished one hands all three back. Demolition is a player taking their own Factory
## apart and nothing is destroyed by it; destruction is the Enemy taking it, and a loss that
## paid out in materials would make a Machine about to fall something you would rather let
## fall than rescue.
##
## So **you repair the living and rebuild the dead**. `_repair` and `_mend` both clamp to
## the row's `health`, and neither can touch a Machine that is already gone.
var _machine_health: PackedInt64Array = PackedInt64Array()

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

## The Belts in canonical order — by the tile each run starts at. The order a Machine's
## branches are listed in, and therefore the list its rotation cursor indexes into.
##
## Derived from the same inputs under the same staleness flag as the update order above, and
## falling out of the same rebuild, which already sorts the Belts to decide where to start each
## chain. Cached rather than sorted per tick because this is the hottest loop in the project.
var _belt_canonical_order: PackedInt64Array = PackedInt64Array()

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
# ── The Silo, its Charges and the Painting that spends them ───────────────────
# Per-Machine arrays indexed exactly like `_machine_progress_ticks`, and per-player arrays
# indexed exactly like `_player_repair_credit`. There is no Silo table and no Stratagem
# subsystem, for the reason there is no Turret table: giving a Silo its own index space is
# how a Silo stops being a Machine.

## How many Charges each Machine has stockpiled. 0 for everything that is not a Silo.
##
## **This is what a destroyed Silo takes with it.** `_remove_machine` drops the entry, so the
## stockpile is lost with the Machine and nothing hands it back — the rule #11 argued for,
## applied to the most expensive thing a Factory can be holding. A breakthrough therefore
## threatens the players' heaviest weapon and not just their smelters.
var _silo_charges: PackedInt64Array = PackedInt64Array()

## What each Silo is loaded with, by Stratagem **id**, and how many Charges went into it.
## Empty and 0 for a Silo that is not loaded.
##
## An id rather than an index, for the reason `_machine_id` holds an id: a hot-reload that
## resorts the Stratagem table must not change what is in the tube under a player's hands.
##
## **A load is irreversible.** There is no intent that empties these, `_load_silo_refusal`
## refuses a second load outright, and the only thing that clears them is a Painting
## beginning. Which is the IRON NEST lesson taken seriously: friction is satisfying when it
## is problem-solving under pressure, and an irreversible commitment made *before* the fight
## is exactly that.
var _silo_loaded_stratagem: PackedStringArray = PackedStringArray()
var _silo_loaded_charges: PackedInt64Array = PackedInt64Array()

## The tick a Machine stands until, or -1 for one that stands indefinitely — which is every
## Machine a Build Gun placed. Only a Sentry Drop's Turret carries a real tick.
##
## A tick rather than a countdown, the arrangement `_player_life_since_tick` has: how long is
## left is arithmetic over two numbers that are hashed anyway, so there is no second counter
## to keep in step.
var _machine_expires_tick: PackedInt64Array = PackedInt64Array()

## Which of its Belts a Machine gave first claim to last — the rotation that makes two Belts
## off one Machine a **split** rather than a priority.
##
## An index into the Machine's own Belts *in canonical order*, which is what keeps the
## fairness free of the build-order bias the Belt update order exists to avoid: the list the
## cursor indexes into is geography, and the cursor is the only history in it. One entry per
## Machine, parallel to every other per-Machine array, so a Smelter with no Belts off it
## carries a 0 that nothing reads.
##
## Hashed, because it decides which branch runs next: two clients that disagreed about it
## would feed different consumers out of the same Factory.
var _machine_port_cursor: PackedInt64Array = PackedInt64Array()

## Where each player's dial is set — the shell type and the charge count they are carrying to
## a Silo. Not a load: nothing is committed until `LOAD_SILO`.
##
## Per player rather than per Silo, and Simulation state rather than something the controller
## remembers, for both of the reasons `_player_selected_machine` is: the Godot layer is
## forbidden to hold anything authoritative, and in co-op what somebody else is winding up is
## worth drawing. A dial on the Silo shared between four players would let one of them change
## another's commitment under their hands.
var _player_dial_stratagem: PackedStringArray = PackedStringArray()
var _player_dial_charges: PackedInt64Array = PackedInt64Array()

## The Painting intent, consumed and cleared every tick. **Held, like the wrench and the
## trigger**: a Painting is a channel, so what the Simulation needs to know each tick is
## "still on it, still that tile", and letting go is itself the act of interrupting. Zero at
## every point a hash is taken, which is why none of these four is hashed.
var _player_paint_held: PackedInt64Array = PackedInt64Array()
var _player_paint_tile_x: PackedInt64Array = PackedInt64Array()
var _player_paint_tile_y: PackedInt64Array = PackedInt64Array()
var _player_paint_tile_z: PackedInt64Array = PackedInt64Array()

## The Painting in flight: what it carries, where, and how far through it is.
##
## `_player_paint_charges` above zero is what "a Painting is in flight" means, rather than a
## separate flag — a Painting always carries at least one Charge, and a count of ticks served
## cannot say it because a Painting that began this tick has served none. That is the same
## rule a Machine built this tick and an Enemy through a Breach this tick obey.
##
## **The Charges left the Silo when this was filled in**, which is what makes "an interrupted
## Painting consumes the Charge and produces nothing" true by construction rather than by a
## special case somebody has to remember.
var _player_paint_stratagem: PackedStringArray = PackedStringArray()
var _player_paint_charges: PackedInt64Array = PackedInt64Array()
var _player_paint_target_x: PackedInt64Array = PackedInt64Array()
var _player_paint_target_y: PackedInt64Array = PackedInt64Array()
var _player_paint_target_z: PackedInt64Array = PackedInt64Array()
var _player_paint_ticks: PackedInt64Array = PackedInt64Array()

## What interruption has cost, per player: the tick the last Painting was interrupted on, or
## -1, and the running total of Charges lost to interruption.
##
## State rather than something inferred, for two reasons. A player has to be able to read what
## a lost Painting cost them — a Charge that vanished with no accounting is exactly the "bad
## luck" Heat is built to avoid. And it is what lets a replay fixture *prove* an interruption
## happened rather than assume it from an effect that did not arrive.
var _player_paint_interrupted_tick: PackedInt64Array = PackedInt64Array()
var _player_charges_wasted: PackedInt64Array = PackedInt64Array()

## What a *finished* Painting has delivered, per player: how many Stratagems have been called
## in and how many Charges went into them.
##
## The symmetric half of the two counters above, and state for the same two reasons. A player
## has to be able to read what their artillery has actually bought — a Run that fired four
## Charges and a Run that lost four to a Breaker's bite look identical from a stockpile that is
## empty either way. And it is what lets a fixture **prove** a Stratagem was fired rather than
## infer it from an effect: a Barrage that killed nothing because nothing was in the radius
## left no trace, a Sentry can expire before anybody looks, and a Supply Drop's goods are
## indistinguishable from a withdrawal. #37's acceptance criterion is "a competently built
## Factory can power, load and fire a Silo within a Run", and this is the figure that answers
## it in the balance harness.
var _player_stratagems_fired: PackedInt64Array = PackedInt64Array()
var _player_charges_fired: PackedInt64Array = PackedInt64Array()

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

	# The Hives, standing from tick 0 at full health. They take no tick of their own: what a
	# Hive does is make the Nest worse at hiding (see `_heat_decay_per_minute`), which is a
	# question asked of the live set rather than a thing done to it.
	_hive_tile_x = layout.hive_tile_x.duplicate()
	_hive_tile_y = layout.hive_tile_y.duplicate()
	_hive_tile_z = layout.hive_tile_z.duplicate()
	_hive_health.resize(_hive_tile_x.size())
	_hive_health.fill(_definitions.hive_health)

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
	_player_y.resize(players)
	_player_velocity_y.resize(players)
	_player_y.fill(0)
	_player_velocity_y.fill(0)
	_player_jump_armed.resize(players)
	_player_jump_held.resize(players)
	# Armed, so the first press of the Run jumps. A player who has never touched the key
	# has certainly let go of it.
	_player_jump_armed.fill(1)
	_player_jump_held.fill(0)
	_player_landing_tick.resize(players)
	_player_landing_speed.resize(players)
	# Never landed, which is different from landed on tick 0: a Run must not open with a
	# camera dip nobody earned.
	_player_landing_tick.fill(-1)
	_player_landing_speed.fill(0)
	_player_sprint_ticks.resize(players)
	_player_sprint_ticks.fill(0)
	_player_step_phase.resize(players)
	_player_step_phase.fill(0)
	_player_build_mode.resize(players)
	# **A Run opens with the weapon out** (#42, the player's own words: *"the knife being out
	# should be the default state"*). It used to open in build mode on the argument that the
	# first thing a Run asks of a player is a Factory; it asks for that second. What a player
	# does on the first tick is look at a world with things in it that can kill them, and a
	# Run that opens with a tool in your hands has decided for you which of those two you were
	# worried about. The Build Gun is one keypress away, nothing is gated either way, and
	# `Objective.line` names the key — so this is a default and not a restriction.
	_player_build_mode.fill(0)
	_player_mode_since_tick.resize(players)
	# Never swapped, which is different from swapped on tick 0: a Run must not open with a
	# holster animation playing for something nobody put away.
	_player_mode_since_tick.fill(-1)
	_player_build_tool.resize(players)
	# The Machine tool, because the first thing a Run asks of a player is a Miner on a Node.
	_player_build_tool.fill(BUILD_TOOL_MACHINE)
	_player_intent_forward.resize(players)
	_player_intent_strafe.resize(players)
	_player_intent_forward.fill(0)
	_player_intent_strafe.fill(0)
	_player_repair_held.resize(players)
	_player_repair_tile_x.resize(players)
	_player_repair_tile_y.resize(players)
	_player_repair_tile_z.resize(players)
	_player_repair_credit.resize(players)
	_player_repair_held.fill(0)
	_player_repair_tile_x.fill(0)
	_player_repair_tile_y.fill(0)
	_player_repair_tile_z.fill(0)
	_player_repair_credit.fill(0)
	_player_survey_held.resize(players)
	_player_sprint_held.resize(players)
	_player_survey_ticks.resize(players)
	_player_survey_held.fill(0)
	_player_sprint_held.fill(0)
	_player_survey_ticks.fill(0)
	_player_build_rotation.resize(players)
	_player_build_rotation.fill(0)
	# What `player.starting_machine` names — the first Machine of the production chain,
	# stated in content because the chain order is derived in `game/build_chain.gd` and is
	# none of the Simulation's business (#55). The loader has already refused a set naming
	# no row or a locked one, so this is a real, buildable Machine.
	_player_selected_machine.resize(players)
	_player_selected_machine.fill(_opening_machine())

	# On their feet, whole, holding what `player.starting_weapon` names and with every
	# slot empty. A Run opens with a frame and nothing fitted to it, because every
	# component is behind a Delivery — which is the pillar's whole shape: a build goal is
	# a Factory goal.
	_player_health.resize(players)
	_player_health.fill(_definitions.player_health)
	_player_life_state.resize(players)
	_player_life_state.fill(LIFE_ALIVE)
	_player_life_since_tick.resize(players)
	_player_life_since_tick.fill(0)
	_player_weapon.resize(players)
	_player_weapon.fill(_definitions.player_starting_weapon)
	_player_fire_cooldown.resize(players)
	_player_fire_cooldown.fill(0)
	# -1 rather than 0, so "has never fired" is distinguishable from "fired on tick 0" —
	# the renderer plays a muzzle flash off this and a Run must not open with one.
	_player_last_shot_tick.resize(players)
	_player_last_shot_tick.fill(-1)
	_player_view_kick_turns.resize(players)
	_player_view_kick_turns.fill(0)
	_player_revive_credit.resize(players)
	_player_revive_credit.fill(0)
	_player_fire_held.resize(players)
	_player_fire_held.fill(0)
	_player_revive_target.resize(players)
	_player_revive_target.fill(-1)
	# The dial opens on the first *unlocked* Stratagem and one Charge, so a Run has something
	# loadable on it rather than something a Silo would refuse. The Build Gun's opening
	# Machine was the same arrangement until #55 moved it into content; a Stratagem has no
	# equivalent of a chain order to disagree with, so the scan stays the right answer here.
	_player_dial_stratagem.resize(players)
	_player_dial_stratagem.fill(_opening_stratagem())
	_player_dial_charges.resize(players)
	_player_dial_charges.fill(1)
	_player_paint_held.resize(players)
	_player_paint_held.fill(0)
	_player_paint_tile_x.resize(players)
	_player_paint_tile_y.resize(players)
	_player_paint_tile_z.resize(players)
	_player_paint_tile_x.fill(0)
	_player_paint_tile_y.fill(0)
	_player_paint_tile_z.fill(0)
	_player_paint_stratagem.resize(players)
	_player_paint_stratagem.fill("")
	_player_paint_charges.resize(players)
	_player_paint_charges.fill(0)
	_player_paint_target_x.resize(players)
	_player_paint_target_y.resize(players)
	_player_paint_target_z.resize(players)
	_player_paint_target_x.fill(0)
	_player_paint_target_y.fill(0)
	_player_paint_target_z.fill(0)
	_player_paint_ticks.resize(players)
	_player_paint_ticks.fill(0)
	# -1 rather than 0, so "has never been interrupted" is distinguishable from "interrupted
	# on tick 0" — the same reason `_player_last_shot_tick` opens at -1.
	_player_paint_interrupted_tick.resize(players)
	_player_paint_interrupted_tick.fill(-1)
	_player_charges_wasted.resize(players)
	_player_charges_wasted.fill(0)
	_player_stratagems_fired.resize(players)
	_player_stratagems_fired.fill(0)
	_player_charges_fired.resize(players)
	_player_charges_fired.fill(0)
	for player_id: int in range(players):
		_player_component_ids.append(PackedStringArray())

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
	# Before the Factory runs, so a Machine a player brought back this tick is a Machine
	# that works this tick. Hand repair is a player act and belongs beside the other two.
	_repair()
	# Beside hand repair, because both are a player spending a tick of attention on
	# something in front of them, and after `_walk` so a shot leaves from where the player
	# now stands rather than from where they stood last tick.
	_revive()
	# Beside hand repair and a revive, because all three are a player spending a tick of
	# attention on something in front of them and nothing else. Before `_fight`, so that a
	# player who began a Painting this tick is already unable to pull a trigger.
	_paint()
	_fight()
	_transport()
	_deliveries()
	# Before anything reads a Machine index for this tick — the grid, the aim, the craft — so
	# a Sentry whose time ran out draws no Power, acquires nothing and fires nothing on the
	# tick it goes. A Sentry *placed* this tick is a Machine built this tick and does not work
	# this tick either, by the rule `_machine_would_work` already holds.
	_expire()
	_aim()
	_power()
	_extract()
	_craft()
	_heat_bleeds()
	_breaches_open()
	_waves()
	# Before the Enemies, so a shell a Siege Hulk fires this tick cannot land this tick. The
	# same rule a Machine built this tick and an Enemy through a Breach this tick obey, and
	# here it is what makes the flight time a Telegraph rather than a decoration.
	_shells()
	_enemies()
	# Last, because `_enemies` is what puts a player down: a bleed-out that advanced
	# before the bite landed would charge a player a tick for a state they were not in
	# yet. A player Downed this tick therefore starts bleeding on the next one, which is
	# the same rule a Machine built this tick and an Enemy through a Breach this tick obey.
	_lives()

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
		InputAction.Kind.JUMP:
			_apply_jump(action)
		InputAction.Kind.SET_BUILD_MODE:
			_apply_set_build_mode(action)
		InputAction.Kind.SET_BUILD_TOOL:
			_apply_set_build_tool(action)
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
		InputAction.Kind.WITHDRAW_FROM_NEST:
			_apply_withdraw_from_nest(action)
		InputAction.Kind.BUILD_WALL:
			_apply_build_wall(action)
		InputAction.Kind.REPAIR:
			_apply_repair(action)
		InputAction.Kind.FIRE:
			_apply_fire(action)
		InputAction.Kind.EQUIP_WEAPON:
			_apply_equip_weapon(action)
		InputAction.Kind.FIT_COMPONENT:
			_apply_fit_component(action)
		InputAction.Kind.REVIVE:
			_apply_revive(action)
		InputAction.Kind.SET_SILO_DIAL:
			_apply_set_silo_dial(action)
		InputAction.Kind.LOAD_SILO:
			_apply_load_silo(action)
		InputAction.Kind.PAINT:
			_apply_paint(action)


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


## Records that a player is holding the jump key. Leaving the ground is `_walk`'s job, one
## tick at a time, so two intents arriving in one tick cannot launch a player twice.
func _apply_jump(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	_player_jump_held[action.player_id] = 1 if action.jump_is_held() else 0


## Puts the Build Gun or the weapon in a player's hands.
##
## **Never refused and never gated**, including while a swap is already in progress, while
## a Wave is on the Map and while the trigger is down — the act is instant and the holster
## is only how long the model takes to move. A player who is already holding what they asked
## for is a no-op whose hash does not move, so leaning on the key does not restart the
## animation a dozen times a second.
##
## Not even `_player_can_act` is consulted, which is deliberate. Being Downed is a refusal
## for every intent that changes the world; what is in a player's hands changes nothing
## about the world, and a dead player's holster is drawn by the same query that draws a
## living one's.
func _apply_set_build_mode(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var wanted: int = 1 if action.build_mode_is_wanted() else 0
	if _player_build_mode[action.player_id] == wanted:
		return
	_player_build_mode[action.player_id] = wanted
	_player_mode_since_tick[action.player_id] = _tick


## Puts a tool on a player's Build Gun.
##
## Asking for the tool already in hand is a no-op whose hash does not move, so leaning on
## the key is not an act. An unknown tool leaves the Build Gun holding what it held, for
## the reason a `SELECT_MACHINE` naming no Machine does: a selection that silently became
## "nothing" would leave a player clicking at nothing.
##
## `_player_can_act` is deliberately not consulted, exactly as `_apply_set_build_mode`
## does not: what is in a player's hands changes nothing about the world.
func _apply_set_build_tool(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var wanted: int = action.build_tool_wanted()
	if wanted != BUILD_TOOL_MACHINE and wanted != BUILD_TOOL_BELT:
		return
	_player_build_tool[action.player_id] = wanted


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

## Moves every player one tick towards the throttle they asked for, and one tick further
## through whatever vertical arc they are on.
##
## Four steps, in this order: advance the sprint ramp, resolve the jump and gravity, turn
## the throttle into a world-space velocity the player wants, then move the velocity they
## *have* towards it by one tick of whichever acceleration applies and integrate position.
##
## **The accelerations are plural, and that is the point of #29.** A single figure for
## starting and stopping is the commonest cause of a first-person game feeling weightless,
## because a body leans into a start and slides into a stop. There are four of them —
## ground start, ground stop, air start, air stop — plus a fifth case, the landing settle,
## which takes a tuned fraction of the ground figures away for a tuned moment after a
## player touches down, so that arriving is something that happens over time rather than
## on one frame.
func _walk() -> void:
	var speed: int = _definitions.player_walk_speed
	var gravity_per_tick: int = Fixed.div(
		_definitions.player_gravity, Fixed.from_int(TICKS_PER_SECOND)
	)
	var impulse: int = _jump_impulse()
	var repeats: bool = _definitions.player_jump_repeats_while_held
	var sprint_span: int = _sprint_ramp_ticks()
	var settle_span: int = _seconds_in_ticks(_definitions.player_land_settle_seconds)
	# The Factory's height, brought up to date once for the whole loop. Every question
	# asked below reads the field rather than rebuilding it, so a Factory of hundreds of
	# Machines costs one O(structures) repaint on the tick something was built and four
	# array reads per player per tick for ever after.
	_solid_heights()

	for player_id: int in range(query_player_count()):
		# A Downed player is immobilised (GLOSSARY.md) and a dead one is not on the Map at
		# all, so neither walks. Stopped outright rather than decelerated: going down is a
		# collapse, and a corpse that slid another two metres would read as a bug. The
		# throttle is consumed anyway, so the per-tick arrays are still zero at the hash.
		# A player channelling a Painting stands at the target, exposed and unable to act
		# (GLOSSARY.md), and standing still is the literal half of that. Stopped rather than
		# decelerated, like going down, because a designator held on a tile while its holder
		# slid off it would make "at the target" a figure of speech.
		if (
			_player_life_state[player_id] != LIFE_ALIVE
			or _player_paint_charges[player_id] > 0
		):
			_player_velocity_x[player_id] = 0
			_player_velocity_z[player_id] = 0
			_player_velocity_y[player_id] = 0
			# Collapsed onto whatever is under them rather than onto the ground: a player
			# who went down on a Smelter roof stays on the roof, for the same reason a
			# corpse does not slide. `_support_height` with their own feet as the reach
			# answers "the highest thing at or below me", which on bare ground is 0 and
			# therefore exactly what this line used to say.
			_player_y[player_id] = _support_height(
				_player_x[player_id], _player_z[player_id], _player_y[player_id]
			)
			_lift_out_of_anything_built_on_them(player_id)
			_player_sprint_ticks[player_id] = 0
			_player_intent_forward[player_id] = 0
			_player_intent_strafe[player_id] = 0
			_player_jump_held[player_id] = 0
			continue

		# The sprint ramp, advanced before anything reads it, so holding the key for n
		# ticks always buys n ticks of gait however many times the intent arrives.
		var sprinting: bool = _player_sprint_held[player_id] != 0
		_player_sprint_ticks[player_id] = clampi(
			_player_sprint_ticks[player_id] + (1 if sprinting else -1), 0, sprint_span
		)
		var sprint_blend: int = _sprint_blend(player_id)

		# ── Up and down ──
		#
		# Resolved before the horizontal half, because whether a player is on the ground
		# is what decides which acceleration the horizontal half uses, and a player who
		# leaves the ground this tick is in the air for this tick's horizontal step.
		var wants_jump: bool = _player_jump_held[player_id] != 0
		# What is under them. Everything the ground used to be, except that the ground is
		# now whatever the Factory put there: a Smelter roof, a Belt deck, the Nest's
		# terrace, or the Map itself at 0. Measured from their own feet plus the step-up,
		# so a surface they could walk onto is a surface they can land on.
		var floor_height: int = _support_height(
			_player_x[player_id], _player_z[player_id], _step_reach(player_id)
		)
		var grounded: bool = (
			_player_y[player_id] == floor_height and _player_velocity_y[player_id] == 0
		)
		if grounded and wants_jump and (repeats or _player_jump_armed[player_id] != 0):
			_player_velocity_y[player_id] = impulse
			_player_jump_armed[player_id] = 0
			grounded = false
		# Re-armed by the absence of the intent, which is what makes a jump a press: the
		# key has to come up before it can go down again.
		if not wants_jump:
			_player_jump_armed[player_id] = 1

		if not grounded:
			_player_velocity_y[player_id] -= gravity_per_tick
			_player_y[player_id] += Fixed.div(
				_player_velocity_y[player_id], Fixed.from_int(TICKS_PER_SECOND)
			)
			if _player_y[player_id] <= floor_height:
				_player_y[player_id] = floor_height
				# The tick and the impact speed, for the settle and for the camera dip.
				# Recorded only on the way *down*, so a jump that launched and landed
				# inside one tick does not claim to have arrived from nowhere.
				if _player_velocity_y[player_id] < 0:
					_player_landing_tick[player_id] = _tick
					_player_landing_speed[player_id] = -_player_velocity_y[player_id]
				_player_velocity_y[player_id] = 0
				grounded = true

		# ── Along the ground ──
		#
		# Sprinting scales the speed a player is reaching for rather than their
		# acceleration, and it does it through the *ramp* rather than all at once, so
		# changing gear takes `player.sprint_ramp_seconds` and the speed, the field of
		# view and the bob all arrive together.
		var player_speed: int = Fixed.mul(
			speed,
			Fixed.lerp_fixed(
				Fixed.ONE, _definitions.player_sprint_multiplier, sprint_blend
			)
		)
		var wanted: FixedVec2 = _wanted_velocity(player_id, player_speed)

		var gap_x: int = wanted.x - _player_velocity_x[player_id]
		var gap_z: int = wanted.z - _player_velocity_z[player_id]
		var gap: int = _length(gap_x, gap_z)
		var acceleration: int = _horizontal_acceleration(
			player_id,
			grounded,
			_player_intent_forward[player_id] != 0 or _player_intent_strafe[player_id] != 0,
			settle_span
		)

		if gap <= acceleration:
			# Close enough to land on it exactly. Without this a player would jitter
			# around full speed forever, one acceleration step either side of it.
			_player_velocity_x[player_id] = wanted.x
			_player_velocity_z[player_id] = wanted.z
		elif acceleration > 0:
			_player_velocity_x[player_id] += Fixed.div(Fixed.mul(gap_x, acceleration), gap)
			_player_velocity_z[player_id] += Fixed.div(Fixed.mul(gap_z, acceleration), gap)

		_move_against_the_factory(player_id)
		_advance_step_phase(player_id)

		# Consumed. A throttle has to be re-asserted every tick, so standing still is
		# the absence of an intent rather than an intent of its own — and the same is true
		# of the jump key, whose absence is what re-arms it.
		_player_intent_forward[player_id] = 0
		_player_intent_strafe[player_id] = 0
		_player_jump_held[player_id] = 0


## Moves a player one tick along their horizontal velocity, as far as the Factory lets them.
##
## **One axis at a time, x then z.** That is what makes walking into a wall at an angle slide
## along it rather than stop dead, and it is one line of code rather than a contact normal.
## The order is fixed and documented because it is the only thing in here a player could
## conceivably notice: entering a one-tile gap diagonally resolves x first, which two clients
## agree on because the order is written down rather than emergent.
##
## **A refused axis keeps the coordinate it had rather than snapping to the obstacle's face.**
## Snapping is the usual choice and it is the wrong one here: the face is a tile boundary
## minus a radius, which is an exact fixed-point subtraction that still has to be re-tested
## for the corner case of two walls, and getting it wrong puts a player *inside* a solid —
## the one state this mechanic must never produce. Refusing costs at most one tick of travel,
## 12 cm at a sprint, which is smaller than the gap a player leaves anyway, and it cannot be
## wrong. Velocity on the refused axis goes to zero, so walking into a Wall is a stop and not
## a shudder.
##
## **Then the step up, once, after both axes.** A surface within `step_up_height` of their
## feet is a surface they end up standing on: a kerb when they are walking and a mantle when
## they are in the air, which is one rule rather than two and is what gets a player onto a
## Belt deck from a jump and onto the Nest's terrace from the ground.
func _move_against_the_factory(player_id: int) -> void:
	var reach: int = _step_reach(player_id)

	var travel_x: int = Fixed.div(
		_player_velocity_x[player_id], Fixed.from_int(TICKS_PER_SECOND)
	)
	if travel_x != 0:
		var wanted_x: int = _player_x[player_id] + travel_x
		if _obstruction_height(wanted_x, _player_z[player_id], reach) >= 0:
			_player_velocity_x[player_id] = 0
		else:
			_player_x[player_id] = wanted_x

	var travel_z: int = Fixed.div(
		_player_velocity_z[player_id], Fixed.from_int(TICKS_PER_SECOND)
	)
	if travel_z != 0:
		var wanted_z: int = _player_z[player_id] + travel_z
		if _obstruction_height(_player_x[player_id], wanted_z, reach) >= 0:
			_player_velocity_z[player_id] = 0
		else:
			_player_z[player_id] = wanted_z

	var surface: int = _support_height(_player_x[player_id], _player_z[player_id], reach)
	if surface > _player_y[player_id]:
		# Up onto it. The upward velocity goes with it: a mantle arrests a jump rather
		# than letting it carry on past the ledge it just caught.
		_player_y[player_id] = surface
		if _player_velocity_y[player_id] < 0:
			_player_landing_tick[player_id] = _tick
			_player_landing_speed[player_id] = -_player_velocity_y[player_id]
		_player_velocity_y[player_id] = 0

	_lift_out_of_anything_built_on_them(player_id)


## Puts a player on top of whatever has closed around them, if anything has.
##
## **The one recovery, and it is deliberate rather than a safety net.** The only way to be
## inside a solid is for the solid to have arrived: a Machine or a Wall built on the tile
## somebody was standing on, which is an ordinary thing to do in co-op and an easy thing to
## do to yourself while straddling a footprint edge. Movement cannot put a player inside
## anything, because a move into something too tall is refused.
##
## Up, never sideways, for two reasons. Nothing in this Simulation overhangs — every
## structure is a column from the ground to its height — so the top is always free, which
## makes "up" the one direction guaranteed to resolve, where a sideways push has to pick a
## direction and can be refused by a second structure. And up is what reads correctly: the
## Machine went up underneath you, so you end up on its roof, which is also where a player
## who wanted to build there would want you.
##
## That gives the whole mechanic its invariant, and it is the thing the tests pin: **a
## player's feet are never below the top of a tile they overlap.** It is restored on the
## tick it is broken, so there is no state a player can be left in that they cannot walk or
## jump out of — a Factory sealed around somebody is a roof they are standing on, and a
## pocket of Walls is somewhere they can still demolish their way out of.
func _lift_out_of_anything_built_on_them(player_id: int) -> void:
	var inside: int = _obstruction_height(
		_player_x[player_id], _player_z[player_id], _step_reach(player_id)
	)
	if inside < 0:
		return
	_player_y[player_id] = inside
	_player_velocity_y[player_id] = 0


## Advances a player's stride by the ground they covered this tick.
##
## A player in the air covers no stride, because they are not taking steps. The phase
## wraps, so it stays bounded over a forty-hour Run rather than growing until it loses
## precision — the same reason yaw wraps.
func _advance_step_phase(player_id: int) -> void:
	if not _is_on_their_feet(player_id):
		return
	var travelled: int = Fixed.div(
		_length(_player_velocity_x[player_id], _player_velocity_z[player_id]),
		Fixed.from_int(TICKS_PER_SECOND)
	)
	if travelled == 0:
		return
	_player_step_phase[player_id] = Fixed.wrap_turns(
		_player_step_phase[player_id] + Fixed.div(travelled, _definitions.player_bob_stride)
	)


## The upward velocity a standing jump leaves the ground at, in fixed-point metres per
## second: the one that reaches `player.jump_height_metres` under
## `player.gravity_metres_per_second_squared`.
##
## Derived rather than tuned, because a tuner thinks in how high they clear. `v = √(2gh)`,
## with the one `Fixed.sqrt` floored like every other lossy operation — so a jump arrives a
## hair under its nominal apex, which is also true of the once-a-tick integration below it
## and is why `test_movement_weight` asserts the apex within a tolerance rather than exactly.
func _jump_impulse() -> int:
	return Fixed.sqrt(
		Fixed.mul(
			Fixed.from_int(2),
			Fixed.mul(_definitions.player_gravity, _definitions.player_jump_height)
		)
	)


## How hard a player changes horizontal velocity this tick, in fixed-point metres per
## second — one tick's worth, not a rate.
##
## **Four figures and a fifth case, and every one of them is a feel number in
## `content/tuning.toml`.** Which applies is a question about two facts: whether the player
## is on the ground, and whether they are asking to go somewhere.
##
## - **Asking, on the ground** — `walk_acceleration`. A body leaning into a start.
## - **Not asking, on the ground** — `walk_deceleration`, deliberately lower, so letting go
##   is a slide and not a freeze. This one number is the single loudest difference between
##   feeling like a person and feeling like a camera.
## - **In the air** — `air_acceleration` and `air_deceleration`, both far lower, which is
##   this project's air-control decision written as two numbers rather than as a fraction.
##   See the comment on the keys.
## - **Just landed** — whichever ground figure applies, scaled by
##   `land_settle_acceleration_percent` for `land_settle_seconds`, so a landing settles
##   rather than restoring full authority on the first frame after it.
func _horizontal_acceleration(
	player_id: int, grounded: bool, asking: bool, settle_span: int
) -> int:
	var rate: int = 0
	if grounded:
		rate = (
			_definitions.player_walk_acceleration
			if asking
			else _definitions.player_walk_deceleration
		)
		if settle_span > 0 and _ticks_since_landing(player_id) < settle_span:
			# One floor applied once, to the result — there is no accumulator here, so
			# unlike the Power credit there is nothing for it to drift.
			rate = Fixed.div(
				Fixed.mul(
					rate, Fixed.from_int(_definitions.player_land_settle_acceleration_percent)
				),
				Fixed.from_int(100)
			)
	else:
		rate = (
			_definitions.player_air_acceleration
			if asking
			else _definitions.player_air_deceleration
		)
	return Fixed.div(rate, Fixed.from_int(TICKS_PER_SECOND))


## How many ticks ago a player landed, or a number larger than any window that asks —
## because a player who has never landed is not settling and is not dipping.
func _ticks_since_landing(player_id: int) -> int:
	if _player_landing_tick[player_id] < 0:
		return 0x3FFFFFFF
	return _tick - _player_landing_tick[player_id]


## A duration in fixed-point seconds as a whole number of ticks, rounded rather than
## floored — a duration is a feel number, so 0.18 s should mean the 11 ticks a tuner
## intends rather than the 10 flooring would give. Zero stays zero, which is how every
## window in this section is switched off.
func _seconds_in_ticks(seconds: int) -> int:
	if seconds <= 0:
		return 0
	return maxi(
		Fixed.round_to_int(Fixed.mul(seconds, Fixed.from_int(TICKS_PER_SECOND))), 1
	)


## How many ticks the sprint ramp takes. At least one, because a zero-tick ramp is a
## divide by nothing — `sprint_ramp_seconds = 0` therefore means "one tick", which is the
## snap it used to be.
func _sprint_ramp_ticks() -> int:
	return maxi(_seconds_in_ticks(_definitions.player_sprint_ramp_seconds), 1)


## How far into the sprint gait a player is, eased, in [0, Fixed.ONE]. The one number that
## ramps the speed, widens the field of view and deepens the bob.
func _sprint_blend(player_id: int) -> int:
	var span: int = _sprint_ramp_ticks()
	var progress: int = clampi(_player_sprint_ticks[player_id], 0, span)
	return Fixed.smoothstep_fixed(Fixed.div(Fixed.from_int(progress), Fixed.from_int(span)))


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
## everything forward, and then — in a pass of its own, once every Belt has moved — take
## one more Item from the Machine port behind.
##
## **Loading is a second pass because a branch is decided at the Machine, not at the Belt.**
## A Machine's output buffer is one pot and each Belt takes at most one Item a tick, so two
## Belts off one Machine compete; deciding that inside `_advance_belt` would mean deciding it
## in the order the Belts happen to be advanced in, which is the one order this section is at
## pains not to let anything depend on.
##
## **The two passes meet on exactly one tile, and the order between them is deliberate.** A Belt
## whose entry a Machine port reaches is usually not reachable by another Belt as well — the tile
## behind its entry is a Machine footprint tile or it is not — but two runs pointing different
## ways can land a hand-off on that same entry. Loading last means the **upstream Belt gets the
## slot and the port is refused**, which is the right way round: an Item on a Belt has nowhere
## else to go and backs the whole line up behind it, where a Machine's output buffer is uncapped
## and banks the surplus safely. Before #46 the port cut in and stalled the line feeding it.
## `test_an_item_already_on_a_belt_beats_a_machine_port_for_the_same_slot` pins it.
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
	_load_the_ports()


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

	var machine: int = _machine_a_belt_feeds(index)
	if machine != -1:
		return _accept_input(machine, item_id)

	# The Nest takes goods against the Delivery it is waiting on, which is what makes
	# progression something the Factory does rather than something a player carries by hand —
	# and banks whatever that tier is not waiting for, which is what makes the Factory's
	# output something a player can spend again. Still bounded, and still nothing is
	# destroyed: an Item the bill does not want and the store has no room for is refused, and
	# the Belt backs up where a player can see it.
	if _nest_covers(beyond):
		return _nest_accepts(item_id, 1) == 1

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
	var machine: int = _machine_a_belt_feeds(index)
	if machine != -1:
		return not _input_has_room(machine, items[0])

	if _nest_covers(beyond):
		return _nest_would_accept(items[0]) == 0

	var onward: int = _belt_entered_at(beyond)
	return onward == -1 or not _belt_has_entry_room(onward)


## Loads every Belt that runs out of a Machine port, giving a Machine's Belts **equal turns**
## at its output rather than always serving the same one first.
##
## Belts are gathered in canonical order — by the tile each run starts at, which is geography
## and not build history — and grouped by the Machine behind their entry. Each group is then
## served starting from that Machine's own cursor, so over any window every branch with room
## has taken an equal share give or take one Item. A player can put one Smelter's output onto
## two Belts and have both run, which is a factory game's second verb after laying a Belt.
##
## Machines are reached in the order their Belts appear in that canonical list, which is
## likewise geography; it could be any order at all without being observable, because no two
## Machines ever compete for the same Belt — a tile holds one Machine.
func _load_the_ports() -> void:
	var canonical: PackedInt64Array = _canonical_belts()
	var count: int = canonical.size()
	if count == 0:
		return

	# Which Machine is behind each Belt, asked once per Belt per tick — exactly as often as
	# the old per-Belt load asked it — and then read rather than asked again.
	var feeders: PackedInt64Array = PackedInt64Array()
	for position: int in range(count):
		feeders.append(_machine_behind_belt(canonical[position]))

	var done: PackedInt64Array = PackedInt64Array()
	for position: int in range(count):
		var machine: int = feeders[position]
		if machine == -1 or done.has(machine):
			continue
		done.append(machine)
		var branches: PackedInt64Array = PackedInt64Array()
		for other: int in range(position, count):
			if feeders[other] == machine:
				branches.append(canonical[other])
		_serve_the_branches(machine, branches)


## Hands one Item to each of a Machine's Belts that can take one, in rotation.
##
## The cursor says which branch had first claim last time, so the claim order starts one past
## it. Three things fall out of that, and each is a criterion rather than an accident:
##
## - **A blocked branch is skipped, not waited on.** A Belt with no room at its entry simply
##   fails to take and the next branch is offered the Item, so one full branch never starves
##   the other — and what neither of them can carry stays in the Machine's uncapped output
##   buffer, where a player watching two full Belts can read the surplus off the Machine.
## - **The cursor moves to one past whichever branch actually got the first Item**, not past
##   the one that merely had first claim. A branch that was blocked did not have its turn, so
##   it does not lose it.
## - **Scarcity is what the rotation is for.** A Machine producing faster than its branches
##   can carry serves all of them every tick and the cursor changes nothing; a Machine
##   producing one Item a tick alternates them exactly.
func _serve_the_branches(machine: int, branches: PackedInt64Array) -> void:
	var count: int = branches.size()
	var cursor: int = posmod(_machine_port_cursor[machine], count)
	var first_served: int = -1
	for step: int in range(count):
		var rank: int = (cursor + step) % count
		if not _load_from_port(branches[rank], machine):
			continue
		if first_served == -1:
			first_served = rank
	if first_served != -1:
		_machine_port_cursor[machine] = (first_served + 1) % count


## The Machine whose output port a Belt runs out of, or -1. The tile behind the entry end:
## Belts connect straight into Machine ports and no inserter entity exists (DESIGN.md).
##
## **-1 for a Belt that is standing against the wrong part of the wall**, since #47. The
## declaration in `content/machine_ports.csv` is what a player is shown an arrow for, and it is
## now the rule: a Belt whose entry sits behind a tile that is not a declared output port, or
## which runs the wrong way out of one, is not connected to that Machine at all.
##
## It matters that this is the one place that is decided rather than two. `_load_the_ports`
## groups a Machine's Belts by this answer, so a Belt that does not dock legally is **not in
## the rotation group** — it is not a branch that gets no turns, it is not a branch. And
## `query_belt_start_is_fed` reads the same function, so the red post the renderer stands at
## an unfed entry appears exactly where the Simulation would refuse to load.
func _machine_behind_belt(index: int) -> int:
	var direction: int = _belt_direction[index]
	var behind: Vector3i = _belt_entry_tile(index) - WorldGrid.direction_step(direction)
	var machine: int = query_machine_at_tile(behind)
	if machine == -1:
		return -1
	# An output's goods travel **along** the way its port faces, so a Belt running out of one
	# runs the same way the port points.
	if not _belt_docks_against(machine, MachinePorts.OUT_OF, behind, direction):
		return -1
	return machine


## The Machine a Belt's far end feeds, or -1, under the same rule in the other direction.
##
## An input's goods travel **against** the way its port faces — a port on a Machine's northern
## wall faces north and takes a Belt coming south — so the direction asked for is the Belt's
## own turned about.
func _machine_a_belt_feeds(index: int) -> int:
	var direction: int = _belt_direction[index]
	var beyond: Vector3i = _belt_exit_tile(index) + WorldGrid.direction_step(direction)
	var machine: int = query_machine_at_tile(beyond)
	if machine == -1:
		return -1
	if not _belt_docks_against(
		machine, MachinePorts.INTO, beyond, WorldGrid.wrap_rotation(direction + 2)
	):
		return -1
	return machine


## Whether a Machine declares a port of this flow on this tile of its wall, facing this way.
##
## **A Machine the table says nothing about takes a Belt anywhere on its footprint edge**,
## which is what the Simulation did everywhere before #47 and is the only honest answer: a
## declaration that does not exist cannot be enforced. That is the seam every test that brings
## its own Machines and no ports table works through, and `Definitions` is what stops the
## shipped content reaching it — a Machine that needs a Belt and declares no port is refused by
## name.
func _belt_docks_against(machine: int, flow: int, tile: Vector3i, facing: int) -> bool:
	var definition: MachineDefinition = _definitions.machine(_machine_id[machine])
	if definition == null:
		return true
	var ports: MachinePorts = _definitions.machine_ports()
	if not ports.declares(definition.id):
		return true
	return ports.has_port_at(
		definition.id,
		flow,
		tile,
		facing,
		query_machine_tile(machine),
		definition.footprint_x,
		definition.footprint_z,
		_machine_rotation[machine]
	)


## Takes one Item from the output buffer of the Machine behind a Belt's entry, if there is room
## at that entry, reporting whether one went.
##
## The Machine is passed in rather than looked up, because `_load_the_ports` has already asked
## which Machine is behind every Belt and the rotation is decided from those answers.
##
## The port is the **declared** output port the run starts against: Belts connect straight into
## Machine ports and no inserter entity exists (DESIGN.md), and since #47 which tiles of a wall
## are ports is `content/machine_ports.csv`'s answer rather than "any edge tile". That question
## is already settled by the time this is called — `_machine_behind_belt` is what answered it,
## and it answered -1 for a Belt docking anywhere else, so such a Belt never reaches here. The
## room check is what rate-limits loading — an Item can only enter once the
## last one is a full spacing clear, which is exactly the Belt's rated throughput and not a
## second number that could disagree with it.
##
## Which Item, when a Machine holds several: the first in its sorted buffer. Sorted by
## id, so the choice is a property of the content rather than of what was produced
## first.
func _load_from_port(index: int, machine: int) -> bool:
	if not _belt_has_entry_room(index):
		return false

	var items: PackedStringArray = _machine_buffer_items[machine]
	if items.is_empty():
		return false
	var item_id: String = items[0]
	_take_from_output(machine, item_id, 1)
	_place_on_belt(index, item_id)
	return true


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


## The Belts in canonical order, which is the order a Machine's branches are listed in. Rebuilt
## under the same flag and by the same function as the order above, because it is the sort that
## function already does.
func _canonical_belts() -> PackedInt64Array:
	if _belt_update_order_stale:
		_rebuild_belt_update_order()
	return _belt_canonical_order


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

	# The same sort is the canonical order a Machine's branches are served in, so it is kept
	# rather than thrown away and sorted again on every tick of every Run.
	_belt_canonical_order = PackedInt64Array()
	for start: int in starts:
		_belt_canonical_order.append(start)

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
	#
	# A Repair Pylon obeys the identical rule against a different question: a Factory with
	# nothing damaged in reach is a Pylon with nothing to do, so it draws no Power and spends
	# no repair material sitting over a Factory that is whole. One clause, two outputs.
	if definition.is_turret() and not _turret_has_work(index, definition):
		return false
	# A full Silo has nothing to do, so it draws no Power and consumes no inputs — one more
	# clause in the same predicate, and the same shape as a Turret with nothing in reach.
	# Deliberately *not* starvation: it has everything its Recipe asks for, it has nowhere to
	# put the Charge. Without this a Silo at capacity would go on eating plate and rounds and
	# browning out the Factory to produce nothing at all.
	if definition.is_silo() and not _silo_has_room(index, definition):
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
				if definition.heals():
					_mend(index, definition)
				else:
					_fire(index, definition)
			# And this is the whole of what a completed craft does for a Silo: the Charge is
			# the output. The plate and the rounds were consumed two lines above, which is
			# what makes a Charge something the Factory paid for rather than something a
			# timer produced.
			elif definition.is_silo():
				_assemble_a_charge(index)
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
		# A Repair Pylon holds no target and acquires nothing. `_mend_target` is a pure
		# function of the Factory's health, re-decided every tick, so there is no serial to
		# keep — and nothing it could hold: an Enemy serial is issued once and never reused,
		# but a Machine is an *index*, and indices shift the moment anything is destroyed.
		# A Pylon that stored one would mend the wrong Machine on the next casualty. Holding
		# nothing is the only safe answer, and it is also the right one: there is no reason to
		# finish mending the thing you started on rather than the thing nearest death.
		if definition.heals():
			continue
		if _turret_target_index(index, definition) != -1:
			continue
		_turret_target_serial[index] = _acquire_target(index, definition)


## Whether a Turret has anything to act on this tick, whichever its output is.
##
## The one predicate behind what the grid bills, what advances a Recipe and what a completed
## craft does, for both Turret classes — so an MG Turret with no Enemy in reach and a Repair
## Pylon over a whole Factory are idle by the same rule rather than by two.
func _turret_has_work(index: int, definition: MachineDefinition) -> bool:
	if definition.heals():
		return _mend_target(index, definition).x != MEND_NOTHING
	return _turret_target_index(index, definition) != -1


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
	# Armoured from where the Turret stands, exactly as a player's round is armoured from where
	# the player stands — one rule, so a Siege Hulk cannot be shrugging off a rifle and soaking
	# an MG round in the same tick. In practice a Turret never reaches a Hulk at all
	# (`Definitions` refuses content where one could, and the Hulk backs away from one that
	# does), so this is the rule being consistent rather than a case that fires often.
	var points: int = _armoured(target, definition.damage, _machine_centre_metres(index))
	_enemy_health[target] = maxi(_enemy_health[target] - points, 0)
	if _enemy_health[target] == 0:
		_remove_enemy(target)


## The most damaged thing in a Repair Pylon's reach, as a `(what, which)` pair, or
## `MEND_NOTHING`.
##
## **A pure read, re-decided every tick**, which is what `_machine_would_work` needs it to be:
## a query that moved a Pylon's target would move the state hash by being asked a question.
## And unlike an MG Turret's target there is nothing to hold on to — a Machine is an index and
## indices shift under a destruction, where an Enemy serial is issued once and never reused.
##
## "Most damaged" is the largest number of hit points *missing*, kept on a **strict**
## improvement and walked in index order — Machines first, then Walls — so a tie goes to the
## lowest Machine index on every client. Missing points rather than a fraction of health,
## because a fraction is a division and a division needs a rounding rule; absolute points is
## exact integer arithmetic and reads correctly anyway, since a Pylon should pour its material
## where the most of it is needed.
##
## Reach is measured from the Pylon's footprint centre to the target's, squared on both sides,
## exactly as an MG Turret measures its own — so turning a Pylon does not move the circle it
## covers, and a Machine exactly on the boundary is in or out by exact arithmetic rather than
## by a rounding rule.
##
## A Run that has ended mends nothing, for the reason a Turret that has nothing to shoot at
## fires nothing: the game is over, and a Factory still consuming material after the fact
## would keep drawing Power on a Map nobody is playing.
func _mend_target(index: int, definition: MachineDefinition) -> Vector2i:
	if query_run_is_over():
		return Vector2i(MEND_NOTHING, -1)

	var centre: FixedVec2 = _machine_centre_metres(index)
	var within: int = _squared_reach(definition)
	var best: Vector2i = Vector2i(MEND_NOTHING, -1)
	var best_missing: int = 0

	for machine: int in range(query_machine_count()):
		var missing: int = _machine_missing_health(machine)
		if missing <= 0 or missing <= best_missing:
			continue
		if _squared_metres_gap(centre, _machine_centre_metres(machine)) > within:
			continue
		best_missing = missing
		best = Vector2i(MEND_MACHINE, machine)

	for wall: int in range(query_wall_count()):
		var wall_missing: int = _wall_missing_health(wall)
		if wall_missing <= 0 or wall_missing <= best_missing:
			continue
		var at: FixedVec2 = WorldGrid.tile_centre_metres(query_wall_tile(wall))
		if _squared_metres_gap(centre, at) > within:
			continue
		best_missing = wall_missing
		best = Vector2i(MEND_WALL, wall)

	return best


## One pulse of repair: what a Repair Pylon does instead of depositing an output.
##
## Called from `_craft` on the tick a craft completes, after the repair material has been
## consumed — so a Pylon that mended has spent a plate and one that did not has not. The
## Recipe decides the rate and the material; `machines.csv` decides how much comes back.
## Exactly the arrangement `_fire` has, which is the point: GLOSSARY.md calls a Repair Pylon a
## Turret-class Machine whose output is repair rather than damage, and this is that sentence
## as code.
func _mend(index: int, definition: MachineDefinition) -> void:
	var target: Vector2i = _mend_target(index, definition)
	if target.x == MEND_NOTHING:
		return
	_turret_last_shot_tick[index] = _tick
	if target.x == MEND_MACHINE:
		_mend_machine(target.y, definition.repair)
		return
	_mend_wall(target.y, definition.repair)


## How far apart two points are, squared, in the same squared fixed-point metres
## `_squared_reach` returns. Deliberately not passed through `Fixed.mul`, which would shift the
## scale back down and floor on the way.
func _squared_metres_gap(from: FixedVec2, to: FixedVec2) -> int:
	var gap_x: int = to.x - from.x
	var gap_z: int = to.z - from.z
	return gap_x * gap_x + gap_z * gap_z


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
	_enemy_broke_ranks.remove_at(index)
	_enemy_face_x.remove_at(index)
	_enemy_face_z.remove_at(index)
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
	# Choosing a Machine is a player saying they want to place one, so it puts the Machine
	# tool back in their hands. The alternative is a Belt mode they have to remember to
	# leave, which is a mode in the sense this project does not have.
	_player_build_tool[action.player_id] = BUILD_TOOL_MACHINE


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

	_place_machine(definition, tile, rotation, -1)


## Stands a Machine up and returns its index.
##
## The one place a Machine joins the Factory, so the per-Machine arrays cannot fall out of
## step with each other. Extracted in #17 because a Sentry Drop places a Turret without a
## Build Gun, without a build cost and without a player standing there — and a second copy of
## these appends would have been a second place to forget an array.
##
## `expires_tick` is -1 for everything a Build Gun placed, which is to say for everything
## that stands until something takes it down. A Sentry Drop is the only thing that passes a
## real tick.
func _place_machine(
	definition: MachineDefinition, tile: Vector3i, rotation: int, expires_tick: int
) -> int:
	_machine_id.append(definition.id)
	_machine_rotation.append(WorldGrid.wrap_rotation(rotation))
	_machine_tile_x.append(tile.x)
	_machine_tile_y.append(tile.y)
	_machine_tile_z.append(tile.z)
	_machine_built_tick.append(_tick)
	# Whole, out of the row. A Machine arrives sound and the Wave is what changes that.
	_machine_health.append(definition.health)
	_machine_progress_ticks.append(0)
	_machine_heat_units.append(0)
	_machine_buffer_items.append(PackedStringArray())
	_machine_buffer_counts.append(PackedInt64Array())
	_machine_input_items.append(PackedStringArray())
	_machine_input_counts.append(PackedInt64Array())
	# Every Machine gets an entry, Turret or Silo or neither, so the per-Machine arrays stay
	# parallel and an index means the same thing in all of them. -1 is "shooting at nothing",
	# which is also what a Smelter is doing.
	_turret_target_serial.append(-1)
	_turret_last_shot_tick.append(-1)
	# A Silo arrives with an empty stockpile and nothing in the tube. Charges are built in
	# advance, never instantaneous (GLOSSARY.md), so a freshly built Silo is a Silo that
	# cannot fire — which is the whole reason the artillery supply line is a supply line.
	_silo_charges.append(0)
	_silo_loaded_stratagem.append("")
	_silo_loaded_charges.append(0)
	_machine_expires_tick.append(expires_tick)
	# Nobody has had first claim yet, so the canonically first Belt off it gets the first Item.
	_machine_port_cursor.append(0)
	# A new footprint is a new obstruction, so the Enemies' shared field no longer
	# describes the Map. Rebuilt on the next tick that has an Enemy to move, never here:
	# a player laying out a Factory places a Machine a second and the field is O(map).
	_flowfield_stale = true
	_solid_height_stale = true
	return _machine_id.size() - 1


## Why a placement would be refused, or `Refusal.NONE`.
##
## The single authority on whether a build is legal. `_apply_build_machine` obeys it
## and `query_build_refusal` reports it, so what a player is told and what the
## Simulation does are the same rule rather than two copies of it.
func _build_refusal(player_id: int, machine_index: int, tile: Vector3i, rotation: int) -> int:
	# A player who is Downed or dead is not building. **Still not a build mode** — nothing
	# here asks whether building is currently permitted (DESIGN.md), it asks whether *this*
	# player is on their feet, which is a fact about them in the same way their wallet is.
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
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


## Whether a player is carrying what a run of a structure costs: its per-tile price times
## the number of tiles the intent would stand up.
##
## **Per tile, and the whole route or nothing.** A route half-laid up to the tile the wallet
## ran out on is a player demolishing what they did not ask for — the same argument
## `_belt_route_refusal` already makes about an obstruction, which is why the two live in one
## function and are asked before the first Belt appears.
func _can_pay_for_structure(player_id: int, structure_id: String, tiles: int) -> bool:
	if not _is_player(player_id):
		return false
	if tiles <= 0:
		return true
	var items: PackedStringArray = _definitions.structure_cost_items(structure_id)
	var counts: PackedInt64Array = _definitions.structure_cost_counts(structure_id)
	for index: int in range(items.size()):
		if query_player_item(player_id, items[index]) < counts[index] * tiles:
			return false
	return true


## Takes what a run of a structure costs out of a player's pockets, or hands it back when
## `tiles` is negative — which is what a demolish is. One function for both directions, so a
## refund cannot come to disagree with a charge about the price.
func _settle_structure_cost(player_id: int, structure_id: String, tiles: int) -> void:
	if tiles == 0:
		return
	var items: PackedStringArray = _definitions.structure_cost_items(structure_id)
	var counts: PackedInt64Array = _definitions.structure_cost_counts(structure_id)
	for index: int in range(items.size()):
		var quantity: int = counts[index] * absi(tiles)
		if tiles > 0:
			_take_from_player(player_id, items[index], quantity)
		else:
			_give_to_player(player_id, items[index], quantity)


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
			if query_belt_at_tile(tile) != -1 or query_wall_at_tile(tile) != -1:
				return true
	return false


# ── Demolishing ───────────────────────────────────────────────────────────

## Takes a Machine or a Belt back apart, returning its materials to the player.
##
## Nothing is destroyed. A Machine hands back its build cost in full *and* whatever it
## was holding in either buffer; a Belt hands back the Items riding it **and what its tiles
## cost**, and a Wall hands back what its one tile cost. A Belt and a Wall are still not
## Machines and have no row in `content/machines.csv` (GLOSSARY.md): their price is a row in
## `content/structures.csv`, which is the table that owns both.
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
		return

	# A Wall hands its tile's price back in full, like everything else a player takes apart
	# themselves: a player who mis-walled a lane loses only the ticks. An Enemy chewing the
	# same Wall down returns nothing, which is #11's asymmetry and is why `_destroy_wall`
	# does not call this.
	var wall: int = query_wall_at_tile(tile)
	if wall != -1:
		_settle_structure_cost(action.player_id, Definitions.STRUCTURE_WALL, -1)
		_remove_wall(wall)


## Why demolishing at a tile would be refused, or `Refusal.NONE`.
func _demolish_refusal(player_id: int, tile: Vector3i) -> int:
	if not _is_player(player_id):
		return Refusal.NOTHING_THERE
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if (
		query_machine_at_tile(tile) != -1
		or query_belt_at_tile(tile) != -1
		or query_wall_at_tile(tile) != -1
	):
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


## Hands a Belt's price and the Items riding it back to a player. One Item a slot, so a packed
## Belt returns everything it was carrying, and the price is per tile of the run — so a route
## demolished tile by tile and a route demolished whole cost the same nothing.
func _refund_belt(player_id: int, index: int) -> void:
	_settle_structure_cost(
		player_id, Definitions.STRUCTURE_BELT, -_belt_tiles[index]
	)
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
	_machine_health.remove_at(index)
	_machine_progress_ticks.remove_at(index)
	_machine_heat_units.remove_at(index)
	_machine_buffer_items.remove_at(index)
	_machine_buffer_counts.remove_at(index)
	_machine_input_items.remove_at(index)
	_machine_input_counts.remove_at(index)
	_turret_target_serial.remove_at(index)
	_turret_last_shot_tick.remove_at(index)
	# **A destroyed Silo loses its stockpile, and a demolished one loses it too.** The entries
	# go with the Machine and nothing anywhere hands a Charge back — the asymmetry #11 argued
	# for, applied to the most expensive thing a Factory can be holding, plus the one extra
	# claim this ticket makes: a load is irreversible, so taking the Silo apart must not be a
	# way to undo one. A Charge is not an Item, so there is nothing for `_refund_machine` to
	# return even if it wanted to.
	_silo_charges.remove_at(index)
	_silo_loaded_stratagem.remove_at(index)
	_silo_loaded_charges.remove_at(index)
	_machine_expires_tick.remove_at(index)
	_machine_port_cursor.remove_at(index)
	_flowfield_stale = true
	_solid_height_stale = true


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
	# Solid to a player even though it is transparent to a Crawler, so the height field is
	# stale where the Enemies' fields are not. The one place the two part company.
	_solid_height_stale = true


# ── Mortality: damage, destruction, Walls and repair ──────────────────────────
# The section that makes a Factory's layout a defensive decision. Everything here moves one
# of two integer arrays — `_machine_health` and `_wall_health` — in whole hit points, with no
# fixed point anywhere, which is what makes damage and repair replay identically.
#
# The asymmetry worth knowing before reading on: **destruction is a loss and demolition is
# not.** `_refund_machine` hands back a build cost and both buffers; `_destroy_machine` hands
# back nothing at all.

## Takes hit points off a Machine, and destroys it if that was the last of them.
##
## The destruction happens here and now rather than at the end of the tick, the same rule
## `_fire` obeys for a killed Enemy: a Machine reduced to nothing must not be bitten twice by
## two Enemies in the same tick, and nothing that runs later in the tick should find it still
## standing.
func _damage_machine(index: int, points: int) -> void:
	if points <= 0 or not _is_machine(index):
		return
	_machine_health[index] = maxi(_machine_health[index] - points, 0)
	if _machine_health[index] == 0:
		_destroy_machine(index)


## Takes a destroyed Machine off the Map, **returning nothing to anybody**.
##
## That is the one decision in this section worth arguing, and it is deliberate. A demolition
## hands back the build cost, both buffers and every Item riding a Belt, because demolition is
## a player taking their own Factory apart and iterating on a layout has to stay cheap (issue
## #1, user story 7). Destruction is the Enemy taking it, and the whole point of mortality is
## that the Factory is something that can be *lost*. Three consequences, all of them wanted:
##
## * A Machine about to fall is worth rescuing. If destruction paid out, a player would stand
##   and watch — or demolish it themselves for the refund — rather than wrench it back up,
##   and the repair mechanic this ticket is about would be strictly worse than doing nothing.
## * There is no player to pay. A Machine ten tiles from anybody falls to a Breaker with
##   nobody standing there, and "the nearest player" is not a rule a lockstep Simulation
##   should want: it would make the refund depend on where four people happened to be.
## * The Items in it were real throughput. A Smelter holding eight plates when it falls is a
##   loss a player can feel and attribute, which is exactly what Heat asks of a mechanic.
##
## Removal rather than a wreck, for the same reason: a hole in a Factory's wall is a *hole*.
## The Belt chain through it breaks because the Machine its run pointed at is not there, the
## obstruction is gone so the next field rebuild routes Enemies straight through the gap, and
## a player who wants it back builds it again. **You repair the living and rebuild the dead.**
func _destroy_machine(index: int) -> void:
	_remove_machine(index)


## Takes hit points off a Wall, and removes it if that was the last of them. No refund, for
## the reasons above.
func _damage_wall(index: int, points: int) -> void:
	if points <= 0 or not _is_wall(index):
		return
	_wall_health[index] = maxi(_wall_health[index] - points, 0)
	if _wall_health[index] == 0:
		_remove_wall(index)


## Removes a Wall from every parallel array. The obstruction set changed, so the fields both
## Enemy kinds steer by no longer describe the Map.
func _remove_wall(index: int) -> void:
	_wall_tile_x.remove_at(index)
	_wall_tile_y.remove_at(index)
	_wall_tile_z.remove_at(index)
	_wall_health.remove_at(index)
	_flowfield_stale = true
	_solid_height_stale = true


## The most hit points a Machine can hold: the `health` its row declares, and what repair
## clamps to. Read off the definition rather than stored, so a balance change applied by
## hot-reload lands on the Factory that is already standing.
func _machine_max_health(index: int) -> int:
	if not _is_machine(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return 0 if definition == null else definition.health


## How many hit points a Machine is short of whole. 0 for one that is sound, and never
## negative — a hot-reload that *lowered* a row's health leaves a Machine over its own
## ceiling rather than destroying it, which is a balance change and not an attack.
func _machine_missing_health(index: int) -> int:
	return maxi(_machine_max_health(index) - _machine_health[index], 0)


## How many hit points a Wall is short of whole.
func _wall_missing_health(index: int) -> int:
	if not _is_wall(index):
		return 0
	return maxi(_definitions.wall_health - _wall_health[index], 0)


## Puts hit points back onto a Machine, never past the `health` its row declares.
func _mend_machine(index: int, points: int) -> void:
	if points <= 0 or not _is_machine(index):
		return
	_machine_health[index] = mini(_machine_health[index] + points, _machine_max_health(index))


## Puts hit points back onto a Wall, never past `wall.health`.
func _mend_wall(index: int, points: int) -> void:
	if points <= 0 or not _is_wall(index):
		return
	_wall_health[index] = mini(_wall_health[index] + points, _definitions.wall_health)


# ── Building a Wall ───────────────────────────────────────────────────────────

## Stands one tile of Wall, or refuses to.
##
## A Wall is not a Machine (DESIGN.md lists it alongside the Nest and the Belt), so this
## carries no definition index, spends no build cost and runs no Recipe. One tile per intent
## rather than a run, because the only question a Wall answers is whether *this* tile is
## walkable and because a Wall chewed through in the middle of a line has to leave the rest
## of the line standing.
##
## Refused as a silent no-op whose hash does not move, the same rule a misaimed build obeys.
func _apply_build_wall(action: InputAction) -> void:
	var tile: Vector3i = action.wall_tile()
	if _build_wall_refusal(action.player_id, tile) != Refusal.NONE:
		return

	_settle_structure_cost(action.player_id, Definitions.STRUCTURE_WALL, 1)
	_wall_tile_x.append(tile.x)
	_wall_tile_y.append(tile.y)
	_wall_tile_z.append(tile.z)
	_wall_health.append(_definitions.wall_health)
	# A new obstruction, so neither field describes the Map any more. Rebuilt on the next
	# tick that has an Enemy to move, never here: a player walling off a Breach places a
	# dozen of these in a second and a sweep is O(map).
	_flowfield_stale = true
	_solid_height_stale = true


## Why standing a Wall on a tile would be refused, or `Refusal.NONE`. The single authority on
## whether a Wall is legal there: `_apply_build_wall` obeys it and `query_build_wall_refusal`
## reports it, so what the hologram says and what the Simulation does are one rule.
func _build_wall_refusal(player_id: int, tile: Vector3i) -> int:
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if not WorldGrid.is_buildable(tile):
		return Refusal.OFF_THE_MAP
	if (
		_nest_covers(tile)
		or query_machine_at_tile(tile) != -1
		or query_belt_at_tile(tile) != -1
		or query_wall_at_tile(tile) != -1
	):
		return Refusal.OCCUPIED
	# A Wall is one tile per intent, so the per-tile price and the price of the thing are the
	# same number — which is the one place the two readings of `build_cost_per_tile` coincide.
	if not _can_pay_for_structure(player_id, Definitions.STRUCTURE_WALL, 1):
		return Refusal.MISSING_MATERIALS
	return Refusal.NONE


# ── Repairing by hand ─────────────────────────────────────────────────────────

## Records that a player is holding the Pneumatic Wrench on a tile this tick. Doing anything
## about it is `_repair`'s job, one tick at a time, so that two intents arriving in one tick
## cannot mend at twice the tuned rate.
func _apply_repair(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var tile: Vector3i = action.repair_tile()
	_player_repair_held[action.player_id] = 1
	_player_repair_tile_x[action.player_id] = tile.x
	_player_repair_tile_y[action.player_id] = tile.y
	_player_repair_tile_z[action.player_id] = tile.z


## Mends whatever each player is holding the wrench on, by one tick's worth.
##
## **This is what makes melee useful rather than a last resort** (DESIGN.md: the Pneumatic
## Wrench is the melee weapon and it is also what repairs). It costs no materials at all —
## what it costs is a player standing next to the Machine, in the open, during a Wave, doing
## nothing else. The Repair Pylon is the other half of that trade: material instead of
## attention. Nothing gates it on a Wave in either direction, exactly as nothing gates
## building: there is no mode anywhere in this project.
##
## A tick's worth is `wrench.repair_points_per_second` of integer credit against
## `TICKS_PER_SECOND`, with the remainder carried in `_player_repair_credit` — the same duty
## cycle Power and Heat use, so over any window a Machine has gained exactly
## `floor(ticks * points_per_second / TICKS_PER_SECOND)`: one floor applied to the total,
## never one per tick.
##
## The intent is consumed whatever comes of it, so a player who stops sending `REPAIR` stops
## repairing, and so the per-tick arrays are zero at every point a hash is taken. A refused
## hold banks nothing: credit does not survive a player walking out of reach any more than it
## survives letting go.
func _repair() -> void:
	for player_id: int in range(query_player_count()):
		var held: bool = _player_repair_held[player_id] != 0
		var tile: Vector3i = Vector3i(
			_player_repair_tile_x[player_id],
			_player_repair_tile_y[player_id],
			_player_repair_tile_z[player_id]
		)
		_player_repair_held[player_id] = 0
		_player_repair_tile_x[player_id] = 0
		_player_repair_tile_y[player_id] = 0
		_player_repair_tile_z[player_id] = 0

		if not held or _repair_refusal(player_id, tile) != Refusal.NONE:
			_player_repair_credit[player_id] = 0
			continue

		_player_repair_credit[player_id] += _definitions.wrench_repair_points_per_second
		@warning_ignore("integer_division")
		var points: int = _player_repair_credit[player_id] / TICKS_PER_SECOND
		if points <= 0:
			continue
		_player_repair_credit[player_id] -= points * TICKS_PER_SECOND

		var machine: int = query_machine_at_tile(tile)
		if machine != -1:
			_mend_machine(machine, points)
			continue
		_mend_wall(query_wall_at_tile(tile), points)


## Why a held wrench would mend nothing, or `Refusal.NONE`.
##
## A pure projection about a repair that has not happened, the same arrangement
## `query_build_refusal` has and for the same reason: the HUD can say "out of reach" or
## "already whole" while the player is still walking, and a refusal leaves the hash alone.
func _repair_refusal(player_id: int, tile: Vector3i) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked

	var machine: int = query_machine_at_tile(tile)
	var wall: int = query_wall_at_tile(tile)
	if machine == -1 and wall == -1:
		return Refusal.NOTHING_THERE
	if not _within_wrench_reach(player_id, tile):
		return Refusal.OUT_OF_REACH
	var missing: int = (
		_machine_missing_health(machine) if machine != -1 else _wall_missing_health(wall)
	)
	if missing <= 0:
		return Refusal.NOT_DAMAGED
	return Refusal.NONE


## Whether a player is close enough to a tile to put a wrench on it.
##
## Compared squared, for the reason a Turret's reach is: `Fixed.sqrt` floors, which would put
## a player exactly on the boundary in or out of reach depending on a rounding rule, where
## multiplying both sides is exact integer arithmetic. The products stay far inside 64 bits —
## the reach is a few metres.
func _within_wrench_reach(player_id: int, tile: Vector3i) -> bool:
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(tile)
	var gap_x: int = centre.x - _player_x[player_id]
	var gap_z: int = centre.z - _player_z[player_id]
	var reach: int = _definitions.wrench_reach_metres
	return gap_x * gap_x + gap_z * gap_z <= reach * reach


# ── Gear: the frame, its components, and what they add up to ──────────────────
#
# Gear is modular (GLOSSARY.md): one weapon frame accepts components — barrels, magazines,
# sights — each made on a different production line, and **power comes from combination
# rather than from tiers.** Nothing in this file names a weapon, a component or a slot;
# all of that is `content/gear.csv`, so a fourth weapon is a row exactly as a Cannon
# Turret was.
#
# The arithmetic is one rule applied five times: every component's percentage for a
# modifier is **added up**, and the sum is applied to the frame's own quoted figure with
# one integer multiply and one floor. Additive rather than multiplicative so that two
# components can be reasoned about in either order and so that nothing rounds at each
# link — a chain of fixed-point multiplications would make the order they were fitted in
# reach the state hash, which is both a determinism hazard and a design one.

## Which modifier `_component_percent` is being asked about. Constants rather than six
## near-identical loops, and not a `String` key, because a typo'd key would read as "no
## component changes this" and be invisible.
const MOD_DAMAGE: int = 0
const MOD_RANGE: int = 1
const MOD_SPREAD: int = 2
const MOD_INTERVAL: int = 3
const MOD_AMMUNITION: int = 4
const MOD_DAMAGE_TAKEN: int = 5


## The weapon frame a player is holding, or null — which a Run never opens in, because
## `player.starting_weapon` is required to name one, but which a hot-reload that deleted
## the row can produce mid-Run.
func _weapon_of(player_id: int) -> GearDefinition:
	if not _is_player(player_id):
		return null
	var definition: GearDefinition = _definitions.gear(_player_weapon[player_id])
	if definition == null or not definition.is_weapon():
		return null
	return definition


## Every component fitted to a player's frame, in the sorted id order they are held in.
## A fitted id that no longer names a component — a hot-reload deleted the row, or turned
## it into a frame — contributes nothing rather than crashing, which is the same
## degradation a Machine whose definition went away gets.
func _fitted_components(player_id: int) -> Array:
	var fitted: Array = []
	if not _is_player(player_id):
		return fitted
	for gear_id: String in _player_component_ids[player_id]:
		var definition: GearDefinition = _definitions.gear(gear_id)
		if definition != null and not definition.is_weapon():
			fitted.append(definition)
	return fitted


## The sum of one modifier across everything fitted, in whole percent. Zero with nothing
## fitted, which is what makes a bare frame exactly what its row says it is.
func _component_percent(player_id: int, which: int) -> int:
	var total: int = 0
	for definition: GearDefinition in _fitted_components(player_id):
		match which:
			MOD_DAMAGE:
				total += definition.damage_percent
			MOD_RANGE:
				total += definition.range_percent
			MOD_SPREAD:
				total += definition.spread_percent
			MOD_INTERVAL:
				total += definition.interval_percent
			MOD_AMMUNITION:
				total += definition.ammunition_percent
			MOD_DAMAGE_TAKEN:
				total += definition.damage_taken_percent
	return total


## A quoted figure with a percentage added to it: `floor(value * (100 + percent) / 100)`.
##
## **One floor, applied once**, which is the rule this project applies to the Power duty
## cycle, Heat's decay and hand repair — and the reason the modifiers are percentages of
## the frame rather than fixed-point multipliers. Works unchanged on a whole number of hit
## points and on a fixed-point count of metres, because both are integers and neither is
## ever negative.
##
## A total below -100% clamps at nothing rather than going negative: a weapon that did
## negative damage would heal what it shot, and content that asks for that is content
## somebody got wrong rather than a mechanic.
static func _scaled(value: int, percent: int) -> int:
	if value <= 0:
		return 0
	@warning_ignore("integer_division")
	return value * maxi(100 + percent, 0) / 100


# The whole of a weapon's effective behaviour, frame plus everything fitted. Each is a
# pure read, so a query can ask any of them without moving the state hash — which is what
# lets the HUD show a player what a component did before they go and find out.

func _weapon_damage(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return 0
	return _scaled(weapon.damage, _component_percent(player_id, MOD_DAMAGE))


func _weapon_range_metres(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return 0
	return _scaled(weapon.range_metres, _component_percent(player_id, MOD_RANGE))


## How far a shot may scatter, in fixed-point **turns** — degrees in the file because that
## is how a human reasons about an angle, turns everywhere in here because radians need PI
## and PI is a float.
func _weapon_spread_turns(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return 0
	var degrees: int = _scaled(weapon.spread_degrees, _component_percent(player_id, MOD_SPREAD))
	return Fixed.div(degrees, Fixed.from_int(DEGREES_PER_TURN))


## How many ticks between one shot and the next. Floored to whole ticks and never less
## than one, exactly as a Recipe's duration is: a rate counted in ticks is exact, where a
## fractional one would make the gap between two shots depend on when in the second they
## happened to fall.
func _weapon_interval_ticks(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return 0
	var seconds: int = _scaled(
		weapon.seconds_per_shot, _component_percent(player_id, MOD_INTERVAL)
	)
	return maxi(Fixed.floor_to_int(Fixed.mul(seconds, Fixed.from_int(TICKS_PER_SECOND))), 1)


## How many rounds one shot spends. A ranged weapon always spends at least one, whatever a
## component says: a weapon somebody tuned to free is not a weapon this loop can price.
func _weapon_ammunition_per_shot(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null or not weapon.is_ranged():
		return 0
	return maxi(
		_scaled(weapon.ammunition_per_shot, _component_percent(player_id, MOD_AMMUNITION)), 1
	)


# ── Equipping and fitting ─────────────────────────────────────────────────────

func _apply_equip_weapon(action: InputAction) -> void:
	if _equip_refusal(action.player_id, action.gear_index()) != Refusal.NONE:
		return
	# The resolved id, not the index — so a hot-reload that resorts the table cannot
	# change what is in a player's hands, which is the rule `_player_selected_machine`
	# already obeys.
	_player_weapon[action.player_id] = _definitions.gear_at(action.gear_index()).id
	# A weapon swap interrupts the interval the old one was part-way through. Deliberate,
	# and the alternative is worse: carrying the cooldown across would let a player fire a
	# slow weapon, swap to a fast one, and get the fast one's next shot early.
	_player_fire_cooldown[action.player_id] = 0


## Why putting a weapon in a player's hands would be refused, or `Refusal.NONE`.
##
## A pure projection about an equip that has not happened, the same arrangement
## `query_build_refusal` has and for the same reason: a HUD can grey a weapon out and say
## why before the key is pressed, and a refusal leaves the hash alone.
func _equip_refusal(player_id: int, gear_index: int) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	var definition: GearDefinition = _definitions.gear_at(gear_index)
	if definition == null:
		return Refusal.NO_SUCH_GEAR
	if not definition.is_weapon():
		return Refusal.WRONG_SLOT
	if _definitions.locks_gear(definition.id) and _unlocked_gear_ids.find(definition.id) == -1:
		return Refusal.GEAR_IS_LOCKED
	return Refusal.NONE


func _apply_fit_component(action: InputAction) -> void:
	var player_id: int = action.player_id
	var slot_index: int = action.gear_slot_index()
	var gear_index: int = action.gear_index()
	if _fit_refusal(player_id, slot_index, gear_index) != Refusal.NONE:
		return

	var slot_id: String = _definitions.gear_slot_id(slot_index)
	_clear_slot(player_id, slot_id)
	if gear_index < 0:
		return

	# Inserted in sorted order, not fitting order, for the reason a player's pockets are
	# sorted: what is on a frame has to be a property of the set rather than of how it got
	# there, or two players holding the same Gear would hash differently.
	var fitted: PackedStringArray = _player_component_ids[player_id]
	var gear_id: String = _definitions.gear_at(gear_index).id
	fitted.insert(fitted.bsearch(gear_id), gear_id)
	_player_component_ids[player_id] = fitted


## Takes whatever occupies a slot off a player's frame. Which slot a fitted component
## occupies is read back off its own row rather than remembered, so there is one authority
## for it and nothing to fall out of step.
func _clear_slot(player_id: int, slot_id: String) -> void:
	var fitted: PackedStringArray = _player_component_ids[player_id]
	for index: int in range(fitted.size() - 1, -1, -1):
		var definition: GearDefinition = _definitions.gear(fitted[index])
		if definition == null or definition.slot_id() == slot_id:
			fitted.remove_at(index)
	_player_component_ids[player_id] = fitted


## Why fitting a component would be refused, or `Refusal.NONE`. A Gear index of -1 empties
## the slot, which is always allowed of a slot that exists.
func _fit_refusal(player_id: int, slot_index: int, gear_index: int) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if _definitions.gear_slot_id(slot_index).is_empty():
		return Refusal.WRONG_SLOT
	if gear_index < 0:
		return Refusal.NONE
	var definition: GearDefinition = _definitions.gear_at(gear_index)
	if definition == null:
		return Refusal.NO_SUCH_GEAR
	# Refused rather than redirected to the slot the row names. The intent is meant to
	# describe the fitting completely — a recorded script has to say what went where
	# without being replayed to find out — so a pairing the two tables disagree about is a
	# mistake rather than something to quietly correct.
	if definition.slot_id() != _definitions.gear_slot_id(slot_index):
		return Refusal.WRONG_SLOT
	if _definitions.locks_gear(definition.id) and _unlocked_gear_ids.find(definition.id) == -1:
		return Refusal.GEAR_IS_LOCKED
	return Refusal.NONE


# ── Firing ────────────────────────────────────────────────────────────────────

func _apply_fire(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	_player_fire_held[action.player_id] = 1


## One tick of combat for every player: recoil comes back down, the interval between
## shots runs down, and a held trigger fires if everything it needs is in place.
##
## The intent is consumed whatever comes of it, so a player who stops sending `FIRE` stops
## firing and the per-tick array is zero at every point a hash is taken — the arrangement
## the walking throttle and the wrench both have.
##
## **The cooldown is advanced in the `elif`, not before the attempt**, so that
## `query_fire_refusal` and what actually happens can never disagree about a given tick.
## Decrementing first would leave a tick where the projection says the weapon is ready and
## the mechanism has not fired yet.
func _fight() -> void:
	for player_id: int in range(query_player_count()):
		var held: bool = _player_fire_held[player_id] != 0
		_player_fire_held[player_id] = 0

		_recover_view_kick(player_id)

		if held and _fire_refusal(player_id) == Refusal.NONE:
			_pull_the_trigger(player_id)
		elif _player_fire_cooldown[player_id] > 0:
			_player_fire_cooldown[player_id] -= 1


## Brings the view back down from a shot's kick, by one tick's worth.
##
## **Proportional to what is left, not a flat amount**, and this is the one place in the
## project where that is the right shape. Heat's decay is flat and the Power duty cycle is
## an integer credit precisely because both *accumulate* over a forty-hour Run and a
## per-tick ratio would shed a fraction each time and drift. Recoil is the opposite kind of
## quantity: it converges on **zero**, so a proportional step cannot drift anywhere — and
## shedding a fraction of what is left is what makes automatic fire controllable at all.
##
## A flat recovery was tried first and is unusable. A weapon firing eight times a second
## adds eight kicks a second, and a flat recovery of one kick per `recover_seconds` sheds
## two — so the view climbs without bound and a held trigger ends up pointed at the sky.
## Proportional recovery settles instead: the kick reaches the height at which one tick of
## shedding equals one shot's worth of climb, and sits there. That bloom is the thing a
## player learns to pull against, and `gear.view_kick_recover_seconds` is what decides how
## high it sits.
##
## Floored, with a minimum step of one, so a kick always reaches exactly zero rather than
## converging on it forever.
func _recover_view_kick(player_id: int) -> void:
	if _player_view_kick_turns[player_id] <= 0:
		return
	var span: int = maxi(_seconds_to_ticks(_definitions.gear_view_kick_recover_seconds), 1)
	@warning_ignore("integer_division")
	var step: int = maxi(_player_view_kick_turns[player_id] / span, 1)
	_player_view_kick_turns[player_id] = maxi(_player_view_kick_turns[player_id] - step, 0)


## How far one shot kicks the view, in fixed-point turns.
func _kick_per_shot_turns() -> int:
	return Fixed.div(
		_definitions.gear_view_kick_degrees_per_shot, Fixed.from_int(DEGREES_PER_TURN)
	)


## Why a held trigger would do nothing this tick, or `Refusal.NONE`.
##
## A pure projection about a shot that has not happened — the same arrangement
## `query_build_refusal` and `query_repair_refusal` have — so the HUD can read `DRY` off
## the weapon rather than off a count a player has to do themselves.
func _fire_refusal(player_id: int) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return Refusal.NO_WEAPON
	if _player_fire_cooldown[player_id] > 0:
		return Refusal.WEAPON_NOT_READY
	if weapon.is_ranged():
		if query_player_item(player_id, weapon.ammunition_item) < _weapon_ammunition_per_shot(player_id):
			return Refusal.OUT_OF_AMMUNITION
	return Refusal.NONE


## One shot. Spends the round, starts the interval, resolves the hit and *then* kicks the
## view — in that order, because the round leaves before the barrel climbs and a kick
## applied first would make a weapon fight its own first shot.
##
## **Firing consumes Ammunition from the player's own inventory** (issue #15), out of the
## same pockets the Build Gun spends from, which is the first-person half of the keystone
## loop: the Factory is what keeps you shooting, exactly as it is what keeps a Turret
## shooting.
func _pull_the_trigger(player_id: int) -> void:
	var weapon: GearDefinition = _weapon_of(player_id)
	_player_last_shot_tick[player_id] = _tick
	_player_fire_cooldown[player_id] = maxi(_weapon_interval_ticks(player_id) - 1, 0)

	if weapon.is_melee():
		_swing(player_id)
		return

	_take_from_player(
		player_id, weapon.ammunition_item, _weapon_ammunition_per_shot(player_id)
	)
	_shoot(player_id)
	_player_view_kick_turns[player_id] = mini(
		_player_view_kick_turns[player_id] + _kick_per_shot_turns(), MAX_PITCH_TURNS
	)


## A round down the line of aim, scattered by the weapon's spread.
##
## **Two RNG draws every shot, hit or miss**, so the stream is a function of how many
## times the trigger was pulled rather than of what happened to be standing there — which
## is what keeps a replay identical when a Crawler dies a tick earlier on one client than
## on another. The draws are consumed before anything is looked up, in player index order,
## so the order is total and the same everywhere.
##
## The shot leaves from the player's **eye height**, not from the camera: Survey View
## lifts the camera to twenty-six metres and is explicitly not a mode (DESIGN.md), so a
## player who raises it to read their Factory must not thereby be firing from a helicopter.
func _shoot(player_id: int) -> void:
	var spread: int = _weapon_spread_turns(player_id)
	var yaw: int = Fixed.wrap_turns(_player_yaw[player_id] + Fixed.mul(spread, _scatter()))
	var pitch: int = Fixed.clamp_fixed(
		_aim_pitch_turns(player_id) + Fixed.mul(spread, _scatter()),
		-MAX_PITCH_TURNS,
		MAX_PITCH_TURNS
	)

	_resolve_a_hit(
		player_id,
		_shot_target(player_id, _facing(yaw), _tangent(pitch), _weapon_range_metres(player_id)),
		_weapon_damage(player_id)
	)


## A swing of a melee weapon at whatever is in front of the player.
##
## Deliberately **not** the ray a round follows: a swing is a sweep, so what it catches is
## the nearest living Enemy inside the weapon's reach that is in front of the player at
## all, rather than one the player has to have centred. Spread does not enter into it and
## neither does pitch — you do not miss a Crawler at your feet by looking at the horizon —
## which is also why a melee weapon consumes no draw from the generator.
func _swing(player_id: int) -> void:
	_resolve_a_hit(
		player_id,
		_melee_target(player_id, _facing(_player_yaw[player_id]), _weapon_range_metres(player_id)),
		_weapon_damage(player_id)
	)


## A uniform fixed-point draw in [-1, 1), for scattering one axis of a shot.
func _scatter() -> int:
	return _rng.next_fixed() * 2 - Fixed.ONE


## The unit vector a yaw points along, on the horizontal plane. Godot's convention, the
## same one `_wanted_velocity` walks a player by, so forward is one definition and not two.
func _facing(yaw: int) -> FixedVec2:
	return FixedVec2.new(-Fixed.sin_turns(yaw), -Fixed.cos_turns(yaw))


## How much height a shot gains per metre travelled, from its pitch.
##
## A division rather than a second table, and it is safe: pitch is clamped to
## `MAX_PITCH_TURNS`, which is 0.24 of a turn, so the cosine never comes closer to zero
## than about 0.063 and the tangent is bounded at roughly sixteen.
func _tangent(pitch: int) -> int:
	return Fixed.div(Fixed.sin_turns(pitch), Fixed.cos_turns(pitch))


## Where a player is actually aiming: their own pitch plus whatever recoil has not come
## back down yet, clamped like any other pitch.
##
## **Recoil moves the aim and not merely the camera.** A kick the renderer applied on its
## own would be a lie about where the next round goes, and the whole reason recoil is
## Simulation state is that it is part of aiming rather than part of drawing.
func _aim_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.clamp_fixed(
		_player_pitch[player_id] + _player_view_kick_turns[player_id],
		-MAX_PITCH_TURNS,
		MAX_PITCH_TURNS
	)


## The Enemy a round meets first, or -1.
##
## **The whole of combat resolution, and every line of it is integer arithmetic.** An
## Enemy is a point in the Simulation — a position and a kind, never a node (#9) — so a
## round is resolved against a capsule standing on that point:
## `gear.enemy_hit_radius_metres` across and `gear.enemy_hit_height_metres` tall. Three
## tests, in the order that rejects most cheaply:
##
## 1. **How far along the line it is.** Behind the player or past the weapon's reach is a
##    miss. The dot product of the gap with the unit facing, which is two multiplies.
## 2. **How far off the line it is.** The magnitude of the cross product, against the
##    radius — the perpendicular distance from the line, exactly.
## 3. **How high the round is by then.** Eye height plus the tangent of the pitch times
##    the distance along, against the capsule's own extent. This is what makes aiming up
##    and down mean something rather than firing a vertical plane of lead.
##
## **The capsule is per kind, not one size for everything.** `gear.enemy_hit_*` is tuned for a
## low scuttling Crawler; a Siege Hulk is a building on legs and a Hive is a building, and a
## player who could miss either by a metre would read the gun as broken. `_enemy_hit_radius`
## and `_enemy_hit_height` are where that lives, beside a kind's health and speed.
##
## **Hives are resolved in the same pass**, because a player aiming down a line does not care
## which of the Enemy's two kinds of thing is standing in it. They are a second loop rather than
## a second function for exactly that reason, and they are walked *after* the Enemies on the same
## strict improvement — so an Enemy and a Hive exactly as far along hand the hit to the Enemy,
## which is the right way round: the thing that is about to bite you outranks the thing that has
## been sitting there all Run.
##
## Walked in Enemy index order, which is ascending spawn serial by construction, then in Hive
## index order, which is canonical tile order, and kept on a **strict** improvement in distance
## along the line — so two things exactly as far away hand the hit to the earlier spawn or the
## earlier tile, on every client. The same rule a Turret's acquisition obeys, and for the same
## reason.
func _shot_target(
	player_id: int, facing: FixedVec2, tangent: int, range_metres: int
) -> Vector2i:
	var from_x: int = _player_x[player_id]
	var from_z: int = _player_z[player_id]
	# Eye height above the ground the player is *standing on*, plus however far off it they
	# currently are. A jumping player really is shooting downwards at the swarm, and an
	# origin that ignored the jump would have made the one new way to change your elevation
	# a lie about where a round comes from. Survey View is still excluded, because the
	# camera is not where a shot leaves from (see the Gear section of CLAUDE.md).
	var eye: int = _definitions.player_eye_height + _player_y[player_id]

	var best_what: int = HIT_NOTHING
	var best_which: int = -1
	var best_along: int = 0
	for enemy: int in range(query_enemy_count()):
		if _enemy_health[enemy] <= 0:
			continue
		var radius: int = _enemy_hit_radius(_enemy_kind[enemy])
		var top: int = _enemy_hit_height(_enemy_kind[enemy]) + radius
		var gap_x: int = _enemy_x[enemy] - from_x
		var gap_z: int = _enemy_z[enemy] - from_z

		var along: int = Fixed.mul(gap_x, facing.x) + Fixed.mul(gap_z, facing.z)
		if along <= 0 or along > range_metres:
			continue
		if best_what != HIT_NOTHING and along >= best_along:
			continue

		var across: int = absi(Fixed.mul(gap_x, facing.z) - Fixed.mul(gap_z, facing.x))
		if across > radius:
			continue

		var height: int = eye + Fixed.mul(along, tangent)
		if height < -radius or height > top:
			continue

		best_what = HIT_ENEMY
		best_which = enemy
		best_along = along

	var hive_radius: int = _definitions.hive_hit_radius_metres
	var hive_top: int = _definitions.hive_hit_height_metres + hive_radius
	for hive: int in range(query_hive_count()):
		var centre: FixedVec2 = WorldGrid.tile_centre_metres(query_hive_tile(hive))
		var gap_x: int = centre.x - from_x
		var gap_z: int = centre.z - from_z

		var along: int = Fixed.mul(gap_x, facing.x) + Fixed.mul(gap_z, facing.z)
		if along <= 0 or along > range_metres:
			continue
		if best_what != HIT_NOTHING and along >= best_along:
			continue
		if absi(Fixed.mul(gap_x, facing.z) - Fixed.mul(gap_z, facing.x)) > hive_radius:
			continue
		var height: int = eye + Fixed.mul(along, tangent)
		if height < -hive_radius or height > hive_top:
			continue

		best_what = HIT_HIVE
		best_which = hive
		best_along = along

	return Vector2i(best_what, best_which)


## The Enemy a melee swing catches, or -1: the nearest living one inside the weapon's
## reach that is in front of the player.
##
## Compared **squared**, for the reason a Turret's reach is: `Fixed.sqrt` floors, which
## would put an Enemy exactly on the boundary in or out of reach depending on a rounding
## rule, where multiplying both sides is exact integer arithmetic. The products stay far
## inside 64 bits — a melee reach is a few metres.
func _melee_target(player_id: int, facing: FixedVec2, range_metres: int) -> Vector2i:
	var from_x: int = _player_x[player_id]
	var from_z: int = _player_z[player_id]
	var within: int = range_metres * range_metres

	var best_what: int = HIT_NOTHING
	var best_which: int = -1
	var best_gap: int = 0
	for enemy: int in range(query_enemy_count()):
		if _enemy_health[enemy] <= 0:
			continue
		var gap_x: int = _enemy_x[enemy] - from_x
		var gap_z: int = _enemy_z[enemy] - from_z
		var squared: int = gap_x * gap_x + gap_z * gap_z
		if squared > within:
			continue
		if Fixed.mul(gap_x, facing.x) + Fixed.mul(gap_z, facing.z) <= 0:
			continue
		if best_what != HIT_NOTHING and squared >= best_gap:
			continue
		best_what = HIT_ENEMY
		best_which = enemy
		best_gap = squared

	# A Hive is a wall a wrench can chip at, which is the honest consequence of the Pneumatic
	# Wrench being a weapon as well as a tool. Ranked after the Enemies for the reason a shot
	# ranks them after: the thing that bites back goes first.
	for hive: int in range(query_hive_count()):
		var centre: FixedVec2 = WorldGrid.tile_centre_metres(query_hive_tile(hive))
		var gap_x: int = centre.x - from_x
		var gap_z: int = centre.z - from_z
		var squared: int = gap_x * gap_x + gap_z * gap_z
		if squared > within:
			continue
		if Fixed.mul(gap_x, facing.x) + Fixed.mul(gap_z, facing.z) <= 0:
			continue
		if best_what != HIT_NOTHING and squared >= best_gap:
			continue
		best_what = HIT_HIVE
		best_which = hive
		best_gap = squared
	return Vector2i(best_what, best_which)


## Lands a player's hit on whatever their weapon found.
##
## One function for both weapons and both kinds of target, so what a round does and what a
## swing does cannot drift apart — and so the armour rule is applied in exactly one place.
##
## **The hit is measured from where the player is standing**, which is what makes a Siege Hulk's
## weak point real: the same weapon doing the same damage takes 15% off its front and all of it
## off its back, and the only difference is where the player chose to be. A Hive carries no
## armour, because it has no front: it is a building, and the fight it gives is the walk there
## and the Ammunition it costs.
func _resolve_a_hit(player_id: int, target: Vector2i, points: int) -> void:
	match target.x:
		HIT_ENEMY:
			_hit_enemy(target.y, _armoured(target.y, points, query_player_position(player_id)))
		HIT_HIVE:
			_damage_hive(target.y, points)


## Takes hit points off an Enemy and removes it if that was the last of them.
##
## Removed here and now rather than at the end of the tick, which is the rule `_fire`
## already follows: a second shot later in the same loop must not land on a corpse, and
## every Turret holding the dead serial has to be told.
func _hit_enemy(index: int, points: int) -> void:
	if points <= 0 or index < 0 or index >= _enemy_health.size():
		return
	_enemy_health[index] = maxi(_enemy_health[index] - points, 0)
	if _enemy_health[index] == 0:
		_remove_enemy(index)


# ── Downed, dead, and back at the Nest ────────────────────────────────────────
#
# **Death costs tempo and never progress or resources** (GLOSSARY.md, DESIGN.md). A player
# who dies drops nothing, unlearns nothing, and comes back holding exactly what they fell
# holding — which is why `_respawn` touches position, health and the clock and nothing
# else. The Factory is what can be taken from you (#11); you cannot.

## Whether a player may act at all this tick. Consulted by every refusal a player's intent
## goes through, so being Downed is a *fact about the player* rather than a mode somebody
## has to remember to check — and so the HUD gets the real reason out of the same function
## that does the refusing.
func _player_can_act(player_id: int) -> bool:
	return _is_player(player_id) and _player_life_state[player_id] == LIFE_ALIVE


## Why a player cannot act at all this tick, or `Refusal.NONE`.
##
## The one function every refusal a player's intent goes through opens with, so that the two
## states in which a player does nothing — Downed or dead, and channelling a Painting — are
## **facts about the player** rather than modes somebody has to remember to check at each
## site. Nothing in the Simulation asks whether acting is currently permitted; what it asks
## is whether this player is on their feet with their hands free, which is a fact in the same
## way their wallet is. Building is still never gated (DESIGN.md).
##
## Deliberately *not* folded into `_player_can_act`, which is consulted by `_damage_player`
## and by `query_player_is_alive`: a player mid-Painting is emphatically still alive and still
## takes a bite, and that bite is what interrupts them.
func _act_refusal(player_id: int) -> int:
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	if _player_life_state[player_id] != LIFE_ALIVE:
		return Refusal.PLAYER_IS_DOWN
	if _player_paint_charges[player_id] > 0:
		return Refusal.PLAYER_IS_PAINTING
	return Refusal.NONE


## Takes hit points off a player, and puts them down if that was the last of them.
##
## `damage_taken_percent` is where armour lands: the one Gear modifier that is not about
## the weapon, applied with the same single floor every other modifier gets. A total that
## would take a bite below nothing clamps at nothing rather than healing.
func _damage_player(player_id: int, points: int) -> void:
	if points <= 0 or not _player_can_act(player_id):
		return
	var taken: int = _scaled(points, _component_percent(player_id, MOD_DAMAGE_TAKEN))
	if taken <= 0:
		return
	_player_health[player_id] = maxi(_player_health[player_id] - taken, 0)
	# **Being hit interrupts a Painting, and the Charge is gone.** This is the clause that
	# makes Painting the co-op moment it is meant to be: one player is committed and helpless
	# while the others keep things off them, and a Painting nothing could interrupt would make
	# the channel a formality rather than a risk. It fires on any damage at all rather than on
	# going down, because a Stratagem a player could soak two Breaker bites through would not
	# be exposed in any sense a player could feel.
	_interrupt_painting(player_id)
	if _player_health[player_id] > 0:
		return
	_go_down(player_id)


## What happens at zero health.
##
## **Solo play has no Downed state** (GLOSSARY.md), and this is the whole of that rule:
## there is nobody to revive you, so a Downed state on a one-player Run would be a pause
## with no counterplay in it. A solo player dies outright and waits out the respawn; a
## player with teammates goes down, immobilised and bleeding, and the window is theirs to
## use.
func _go_down(player_id: int) -> void:
	_player_life_state[player_id] = (
		LIFE_DOWNED if query_player_count() > 1 else LIFE_DEAD
	)
	_player_life_since_tick[player_id] = _tick
	_player_velocity_x[player_id] = 0
	_player_velocity_z[player_id] = 0
	_player_view_kick_turns[player_id] = 0
	_player_fire_cooldown[player_id] = 0
	_player_revive_credit[player_id] = 0
	# A player who went down was already interrupted by the hit that put them there; this
	# covers going down any other way the Simulation ever learns to do it.
	_interrupt_painting(player_id)


## Advances every player's bleed-out and respawn by one tick.
##
## Elapsed time is `_tick - _player_life_since_tick`, so a player who went down *this*
## tick has been down for zero ticks and does not spend one of their window on the tick
## they lost their footing — the same rule a Machine built this tick and an Enemy through
## a Breach this tick obey.
func _lives() -> void:
	for player_id: int in range(query_player_count()):
		var elapsed: int = _tick - _player_life_since_tick[player_id]
		match _player_life_state[player_id]:
			LIFE_DOWNED:
				if elapsed >= _downed_ticks():
					_player_life_state[player_id] = LIFE_DEAD
					_player_life_since_tick[player_id] = _tick
			LIFE_DEAD:
				if elapsed >= _respawn_ticks():
					_respawn(player_id)


## Puts a player back on their feet at the Nest, whole.
##
## At the middle of the Nest's footprint, which is the one place on the Map that is always
## there and never moves. Nothing else is touched: not what they are carrying, not what
## the Run has unlocked, not the weapon in their hands or the components on it. **That is
## the acceptance criterion, written as the absence of code** — there is nowhere here for
## a death penalty to be added without somebody arguing for it first.
func _respawn(player_id: int) -> void:
	var at: FixedVec2 = _nest_centre_metres()
	_player_x[player_id] = at.x
	_player_z[player_id] = at.z
	_player_velocity_x[player_id] = 0
	_player_velocity_z[player_id] = 0
	# **On top of the Nest, not inside it.** The middle of the footprint was open ground
	# until #30 made the Nest solid, and a respawn into a solid is the one case the lift
	# below cannot be allowed to discover: coming back to life has to put somebody
	# somewhere they can stand, deliberately, rather than somewhere a recovery rule
	# rescues them from. The crown is that place — the one surface on the Map nothing can
	# be built on, nothing can take away, and the Run is lost without.
	_solid_heights()
	_player_y[player_id] = _solid_height_at(WorldGrid.tile_at_metres(at.x, at.z))
	_player_velocity_y[player_id] = 0
	_player_health[player_id] = _definitions.player_health
	_player_life_state[player_id] = LIFE_ALIVE
	_player_life_since_tick[player_id] = _tick
	_player_view_kick_turns[player_id] = 0
	_player_fire_cooldown[player_id] = 0
	_player_revive_credit[player_id] = 0


## The middle of the Nest's footprint, in fixed-point metres. Exact: a tile centre is a
## whole number of metres, so the average of two of them lands on a half-metre at worst.
func _nest_centre_metres() -> FixedVec2:
	var anchor: Vector3i = query_nest_tile()
	var size: Vector2i = query_nest_footprint()
	var near: FixedVec2 = WorldGrid.tile_centre_metres(anchor)
	var far: FixedVec2 = WorldGrid.tile_centre_metres(
		Vector3i(anchor.x + maxi(size.x - 1, 0), anchor.y, anchor.z + maxi(size.y - 1, 0))
	)
	var two: int = Fixed.from_int(2)
	return FixedVec2.new(Fixed.div(near.x + far.x, two), Fixed.div(near.z + far.z, two))


func _downed_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.player_downed_bleed_out_seconds), 1)


func _respawn_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.player_respawn_delay_seconds), 0)


func _revive_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.player_revive_seconds), 1)


# ── Reviving ──────────────────────────────────────────────────────────────────

func _apply_revive(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	_player_revive_target[action.player_id] = action.revive_target()


## Brings every Downed player a rescuer is standing over back up, by one tick's worth.
##
## **Hand repair pointed at a person**, and the same mechanism down to the arithmetic: an
## integer credit against the revive's own length, so over any window a Downed player has
## regained exactly `floor(ticks * health / revive_ticks)` — one floor applied to the
## total, never one per tick. Credit does not survive letting go or walking out of reach,
## the rule Power credit, Heat credit and the wrench all obey. What it costs the rescuer is
## what a wrench costs: standing still, in the open, during a Wave, doing nothing else.
##
## Rescuers are walked in player index order, so two people reviving the same teammate in
## the same tick both contribute and the order they do it in is the one every client
## agrees on.
func _revive() -> void:
	for player_id: int in range(query_player_count()):
		var target: int = _player_revive_target[player_id]
		_player_revive_target[player_id] = -1

		if _revive_refusal(player_id, target) != Refusal.NONE:
			_player_revive_credit[player_id] = 0
			continue

		_player_revive_credit[player_id] += _definitions.player_health
		var span: int = _revive_ticks()
		@warning_ignore("integer_division")
		var points: int = _player_revive_credit[player_id] / span
		if points <= 0:
			continue
		_player_revive_credit[player_id] -= points * span

		_player_health[target] = mini(
			_player_health[target] + points, _definitions.player_health
		)
		if _player_health[target] < _definitions.player_health:
			continue
		_player_life_state[target] = LIFE_ALIVE
		_player_life_since_tick[target] = _tick
		_player_revive_credit[player_id] = 0


## Why a held revive would pick nobody up, or `Refusal.NONE`. A pure projection about a
## revive that has not happened, the same arrangement every other refusal in this file is.
func _revive_refusal(rescuer: int, target: int) -> int:
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not _is_player(rescuer):
		return Refusal.NO_SUCH_PLAYER
	# Solo play has no Downed state, so on a one-player Run there is never anybody to pick
	# up and this is the honest reason rather than "nothing to revive".
	if query_player_count() <= 1:
		return Refusal.NO_TEAMMATE
	var blocked: int = _act_refusal(rescuer)
	if blocked != Refusal.NONE:
		return blocked
	if target == rescuer or not _is_player(target):
		return Refusal.NOTHING_TO_REVIVE
	if _player_life_state[target] != LIFE_DOWNED:
		return Refusal.NOTHING_TO_REVIVE
	if not _within_revive_reach(rescuer, target):
		return Refusal.OUT_OF_REACH
	return Refusal.NONE


## Whether a rescuer is close enough to reach a Downed player. Compared squared, for the
## reason the wrench's reach is.
func _within_revive_reach(rescuer: int, target: int) -> bool:
	var gap_x: int = _player_x[target] - _player_x[rescuer]
	var gap_z: int = _player_z[target] - _player_z[rescuer]
	var reach: int = _definitions.player_revive_reach_metres
	return gap_x * gap_x + gap_z * gap_z <= reach * reach


## The player an Enemy is close enough to bite, or -1.
##
## A distance rather than tile contact, unlike everything else an Enemy bites: the Nest, a
## Machine and a Wall all stand on tiles, and a player is a position in fixed-point metres.
## Asking which tile a player is standing on would make a bite land or miss depending on
## which side of a tile boundary they happened to be, which is not something a player could
## ever read off the screen.
##
## Walked in player index order and kept on a strict improvement, so a tie goes to the
## lowest player id on every client. A Downed player is **not** a target: they are already
## out of the fight, and finishing them would make the bleed-out window a fiction.
func _player_in_contact(enemy: int) -> int:
	var reach: int = _enemy_player_reach(_enemy_kind[enemy])
	var within: int = reach * reach
	var best: int = -1
	var best_gap: int = 0
	for player_id: int in range(query_player_count()):
		if _player_life_state[player_id] != LIFE_ALIVE:
			continue
		var gap_x: int = _player_x[player_id] - _enemy_x[enemy]
		var gap_z: int = _player_z[player_id] - _enemy_z[enemy]
		var squared: int = gap_x * gap_x + gap_z * gap_z
		if squared > within:
			continue
		if best != -1 and squared >= best_gap:
			continue
		best = player_id
		best_gap = squared
	return best



## How close a player has to be to an Enemy of a kind to be reached by it, in fixed-point
## metres.
##
## `enemy.player_bite_reach_metres` measured from the Enemy's **body** rather than from the
## point it stands on. For a Crawler and a Breaker those are the same thing and the number is
## exactly what the tuning file says; a Siege Hulk is several metres across, and a player
## standing inside its hull untouched because the centre is 1.6 m further away would be a free
## kill rather than a brave one.
func _enemy_player_reach(kind: int) -> int:
	if kind == EnemyKind.SIEGE_HULK:
		return _definitions.enemy_player_bite_reach_metres + _enemy_hit_radius(kind)
	return _definitions.enemy_player_bite_reach_metres


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


# ── The Silo, the dial, and the Painting ──────────────────────────────────────
#
# The design's most distinctive mechanic, borrowed from StarCraft's nuclear silo and
# sharpened. It is also the clearest statement of the keystone loop there is: a Charge is
# assembled out of Belt-fed plate and rounds, so **more production means more artillery, full
# stop** (docs/DESIGN.md).
#
# Four claims, and every one of them is a consequence of where state lives rather than a rule
# somebody has to remember:
#
# * **A Charge is assembled, never instantaneous.** The Silo is a Machine with a Recipe and
#   `_craft` advances it exactly as it advances a Smelter; the one line that differs is what
#   happens instead of depositing an output. A full Silo is idle and off the Power grid, by the
#   same clause that keeps a Turret with nothing in reach off it.
# * **A load is irreversible.** There is no unload intent, `_load_silo_refusal` refuses a
#   second load rather than replacing the first, and `_remove_machine` takes the load with the
#   Machine — so demolishing is not an undo either. DESIGN.md puts Silo loading first on the
#   diegetic list because that commitment is problem-solving under pressure, which is the side
#   of the IRON NEST line this project wants to be on.
# * **An interrupted Painting consumes the Charge and produces nothing.** True by
#   construction: `_begin_painting` takes the Charges off the Silo and `_interrupt_painting`
#   does not put them back, because there is nowhere to put them back to.
# * **A destroyed Silo loses its stockpile.** #11's asymmetry, applied to the most expensive
#   thing a Factory can be holding, which is what makes a breakthrough threaten the players'
#   heaviest weapon and not just their smelters.

## Winds a player's dial. Clamped, not refused: a dial is a physical thing with stops on it,
## and a counter that refused to go past four rather than stopping at four would be a strange
## piece of machinery.
##
## An index naming no Stratagem leaves the dial where it was, exactly as a `SELECT_MACHINE`
## naming no Machine leaves the Build Gun holding what it held — a selection that silently
## became "nothing" would leave a player committing an empty load.
func _apply_set_silo_dial(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var definition: StratagemDefinition = _definitions.stratagem_at(
		action.dial_stratagem_index()
	)
	if definition == null:
		return
	_player_dial_stratagem[action.player_id] = definition.id
	_player_dial_charges[action.player_id] = clampi(
		action.dial_charges(), 1, maxi(_definitions.silo_max_charges_per_load, 1)
	)


## Commits a load into a Silo, or refuses to. **Irreversible once it lands.**
##
## A refusal is a silent no-op whose hash does not move, exactly as a misaimed build is: a
## player walking up to a Silo that is already loaded is an ordinary thing to do, and
## `query_load_silo_refusal` is what tells them so *before* they press the key. That
## projection is the whole reason the irreversibility is fair rather than cruel — the
## commitment is made knowingly.
func _apply_load_silo(action: InputAction) -> void:
	var tile: Vector3i = action.load_silo_tile()
	var stratagem_index: int = action.load_stratagem_index()
	var charges: int = action.load_charges()
	if _load_silo_refusal(action.player_id, tile, stratagem_index, charges) != Refusal.NONE:
		return

	var index: int = _silo_at(tile)
	var definition: StratagemDefinition = _definitions.stratagem_at(stratagem_index)
	# The Charges leave the stockpile and go into the tube. Nothing takes them back out but a
	# Painting beginning, and nothing hands them back at all.
	_silo_charges[index] -= charges
	_silo_loaded_stratagem[index] = definition.id
	_silo_loaded_charges[index] = charges


## Why a load would be refused, or `Refusal.NONE`.
##
## The single authority on whether a load is legal: `_apply_load_silo` obeys it and
## `query_load_silo_refusal` reports it, so what a player is told and what the Simulation does
## are one rule and not two copies of it. The same arrangement `query_build_refusal` has, and
## it matters more here than anywhere else in the project, because this is the one act that
## cannot be taken back.
func _load_silo_refusal(
	player_id: int, tile: Vector3i, stratagem_index: int, charges: int
) -> int:
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if query_run_is_over():
		return Refusal.RUN_IS_OVER

	var definition: StratagemDefinition = _definitions.stratagem_at(stratagem_index)
	if definition == null:
		return Refusal.NO_SUCH_STRATAGEM
	# Before the Silo and before the stockpile, for the reason `CONTENT_IS_LOCKED` comes before
	# the ground and the wallet: being locked is a fact about the Stratagem, and a player
	# holding one they have not earned has the same problem at every Silo on the Map.
	if not _stratagem_is_unlocked(definition.id):
		return Refusal.STRATAGEM_IS_LOCKED
	if charges < 1 or charges > maxi(_definitions.silo_max_charges_per_load, 1):
		return Refusal.BAD_CHARGE_COUNT

	var index: int = _silo_at(tile)
	if index == -1:
		return Refusal.NO_SILO_THERE
	if not _within_silo_reach(player_id, index):
		return Refusal.OUT_OF_REACH
	# **The one that makes the mechanic what it is.** A loaded Silo is a commitment, so a
	# second load is refused rather than replacing the first. Fire what is in the tube or lose
	# it with the Silo.
	if _silo_loaded_charges[index] > 0:
		return Refusal.SILO_ALREADY_LOADED
	if _silo_charges[index] < charges:
		return Refusal.NOT_ENOUGH_CHARGES
	return Refusal.NONE


## The Silo whose footprint covers a tile, or -1. Any tile of it will do, exactly as any tile
## of a Machine's footprint takes a wrench.
func _silo_at(tile: Vector3i) -> int:
	var index: int = query_machine_at_tile(tile)
	if index == -1:
		return -1
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or not definition.is_silo():
		return -1
	return index


## Whether a player is standing close enough to work a Silo's dial.
##
## Measured to the **footprint**, not to its centre, through the same `_gap_to_span` a Delivery
## at the Nest uses — because a Silo is 4x4 and a reach to its centre would mean standing
## inside it. Squared on both sides, like every other reach in this project: `Fixed.sqrt`
## floors, and a player exactly on the boundary must not be in or out by a rounding rule.
func _within_silo_reach(player_id: int, index: int) -> bool:
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null:
		return false
	var origin: Vector3i = query_machine_tile(index)
	var size: Vector2i = WorldGrid.rotated_footprint(
		definition.footprint_x, definition.footprint_z, _machine_rotation[index]
	)
	var tile_size: int = WorldGrid.TILE_SIZE_METRES
	var gap_x: int = _gap_to_span(
		_player_x[player_id],
		Fixed.from_int(origin.x * tile_size),
		Fixed.from_int((origin.x + size.x) * tile_size)
	)
	var gap_z: int = _gap_to_span(
		_player_z[player_id],
		Fixed.from_int(origin.z * tile_size),
		Fixed.from_int((origin.z + size.y) * tile_size)
	)
	var reach: int = _definitions.silo_load_reach_metres
	return gap_x * gap_x + gap_z * gap_z <= reach * reach


## Records the Painting a player is holding this tick. Applying it is `_paint`'s job, once a
## tick, so two intents arriving in one tick cannot serve two ticks of channel.
func _apply_paint(action: InputAction) -> void:
	if not _is_player(action.player_id):
		return
	var tile: Vector3i = action.paint_tile()
	_player_paint_held[action.player_id] = 1
	_player_paint_tile_x[action.player_id] = tile.x
	_player_paint_tile_y[action.player_id] = tile.y
	_player_paint_tile_z[action.player_id] = tile.z


## Advances every Painting by one tick, begins the ones that were just started, and interrupts
## the ones that were let go of.
##
## Consumes and clears the held intent every tick, the arrangement `_repair` and `_fight` both
## have, so the four per-tick arrays are zero at every point a hash is taken.
##
## A Painting that begins this tick serves no tick of channel on it — the rule a Machine built
## this tick, an Enemy through a Breach this tick and a player Downed this tick all obey.
func _paint() -> void:
	for player_id: int in range(query_player_count()):
		var held: bool = _player_paint_held[player_id] != 0
		var tile: Vector3i = Vector3i(
			_player_paint_tile_x[player_id],
			_player_paint_tile_y[player_id],
			_player_paint_tile_z[player_id]
		)
		_player_paint_held[player_id] = 0
		_player_paint_tile_x[player_id] = 0
		_player_paint_tile_y[player_id] = 0
		_player_paint_tile_z[player_id] = 0

		if _player_paint_charges[player_id] > 0:
			# **Letting go is interrupting, and the Charges are already gone.** So is aiming
			# the designator at a different tile, which is a player changing their mind about
			# the target — the commitment was made when the channel began, and there is no
			# version of this where it can be re-aimed for free.
			if not held or tile != query_player_paint_tile(player_id):
				_interrupt_painting(player_id)
				continue
			# A Run that has ended calls nothing in, for the reason a Turret that has nothing
			# to shoot at fires nothing: the game is over. The Charges are spent either way.
			if query_run_is_over():
				_interrupt_painting(player_id)
				continue
			_player_paint_ticks[player_id] += 1
			if _player_paint_ticks[player_id] >= query_player_paint_ticks_required(player_id):
				_resolve_painting(player_id)
			continue

		if not held:
			continue
		if _paint_refusal(player_id, tile) != Refusal.NONE:
			continue
		_begin_painting(player_id, tile)


## Why a Painting would not start, or `Refusal.NONE`.
##
## A projection about a Painting that has not happened, the arrangement every other refusal in
## this project has — and the one that matters most, because what it is refusing is about to
## spend something irreplaceable. A player reads "nothing loaded" or "stand on the target"
## before they hold the key rather than after a Charge has gone.
func _paint_refusal(player_id: int, tile: Vector3i) -> int:
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	if not WorldGrid.is_within_extent(tile):
		return Refusal.OFF_THE_MAP
	# **A player must stand at the target** (GLOSSARY.md). Literally the tile under their feet,
	# rather than a reach: the whole price of a Stratagem is walking into the place you want it
	# to land and standing there unable to do anything else, and a reach would let a player buy
	# that off a few metres at a time. It is also why `_walk` roots them once the channel
	# starts — "at the target" has to mean something.
	if WorldGrid.tile_at_metres(_player_x[player_id], _player_z[player_id]) != tile:
		return Refusal.NOT_AT_THE_TARGET

	var silo: int = _loaded_silo()
	if silo == -1:
		return Refusal.NOTHING_LOADED
	var definition: StratagemDefinition = _definitions.stratagem(_silo_loaded_stratagem[silo])
	if definition == null:
		return Refusal.NO_SUCH_STRATAGEM
	if not _stratagem_is_unlocked(definition.id):
		return Refusal.STRATAGEM_IS_LOCKED
	# A Sentry Drop needs ground to stand on, and the answer to "there is a Smelter there" has
	# to arrive before the channel rather than after it. The ground can still be taken during
	# the five seconds a Barrage channels, which is why `_drop_a_sentry` checks again.
	if definition.is_sentry():
		var dropped: MachineDefinition = _definitions.machine(definition.sentry_machine)
		if dropped == null:
			return Refusal.NO_SUCH_MACHINE
		var size: Vector2i = WorldGrid.rotated_footprint(
			dropped.footprint_x, dropped.footprint_z, 0
		)
		if not WorldGrid.footprint_is_buildable(tile, size.x, size.y):
			return Refusal.OFF_THE_MAP
		if _footprint_is_occupied(tile, size.x, size.y):
			return Refusal.OCCUPIED
	return Refusal.NONE


## Takes the load out of a Silo and puts it in a player's hands as a Painting in flight.
##
## **This is the tick the Charges are spent on.** Everything about "an interrupted Painting
## consumes the Charge and produces nothing" follows from these five lines rather than from a
## rule anywhere else: there is no path by which they go back into the Silo, so the only
## question left is whether the channel finishes.
func _begin_painting(player_id: int, tile: Vector3i) -> void:
	var silo: int = _loaded_silo()
	_player_paint_stratagem[player_id] = _silo_loaded_stratagem[silo]
	_player_paint_charges[player_id] = _silo_loaded_charges[silo]
	_player_paint_target_x[player_id] = tile.x
	_player_paint_target_y[player_id] = tile.y
	_player_paint_target_z[player_id] = tile.z
	_player_paint_ticks[player_id] = 0
	_silo_loaded_stratagem[silo] = ""
	_silo_loaded_charges[silo] = 0


## Ends a Painting with nothing to show for it, and records what that cost.
##
## The count and the tick are state rather than something a HUD infers, for two reasons. A
## player has to be able to read what a lost Painting cost them — a Charge that vanished with
## no accounting is exactly the bad luck Heat is built to avoid. And it is what lets a replay
## fixture *prove* an interruption happened rather than infer it from an effect that failed to
## arrive, which is a weaker claim about a stronger-sounding thing.
func _interrupt_painting(player_id: int) -> void:
	if not _is_player(player_id) or _player_paint_charges[player_id] <= 0:
		return
	_player_charges_wasted[player_id] += _player_paint_charges[player_id]
	_player_paint_interrupted_tick[player_id] = _tick
	_clear_painting(player_id)


func _clear_painting(player_id: int) -> void:
	_player_paint_stratagem[player_id] = ""
	_player_paint_charges[player_id] = 0
	_player_paint_target_x[player_id] = 0
	_player_paint_target_y[player_id] = 0
	_player_paint_target_z[player_id] = 0
	_player_paint_ticks[player_id] = 0


## What a finished Painting does, dispatched on the Stratagem's own effect.
##
## Three effects and no fourth place to add one: a row in `content/stratagems.csv` chooses
## between these, and what varies inside each of them is columns. A second Barrage with a
## wider radius and a longer channel needs nothing here.
func _resolve_painting(player_id: int) -> void:
	var definition: StratagemDefinition = _definitions.stratagem(
		_player_paint_stratagem[player_id]
	)
	var charges: int = _player_paint_charges[player_id]
	var target: Vector3i = query_player_paint_tile(player_id)
	# Cleared before the effect lands, so that a Stratagem which puts a Machine down or hands
	# goods over is doing it to a player who is no longer channelling.
	_clear_painting(player_id)
	if definition == null or charges <= 0:
		return

	# Counted here rather than inside the three effects, because what was fired is one fact and
	# the effects are three shapes of consequence. A row whose effect lands on nothing still
	# fired.
	_player_stratagems_fired[player_id] += 1
	_player_charges_fired[player_id] += charges

	if definition.is_barrage():
		_shell_the_ground(definition, target, charges)
	elif definition.is_supply():
		_drop_supplies(definition, player_id, charges)
	elif definition.is_sentry():
		_drop_a_sentry(definition, target, charges)


## A Barrage: `damage_per_charge` times the Charges loaded, off every Enemy in reach of the
## painted tile.
##
## Reach is compared **squared**, like a Turret's and a wrench's, because `Fixed.sqrt` floors
## and a Crawler exactly on the boundary must not be in or out by a rounding rule.
##
## Walked in **descending** index order, which is the one place in this project that does not
## walk Enemies forwards. Nothing here is a *choice* between Enemies — every Enemy in the
## radius is hit, so no selection bias exists to avoid — and a kill removes its entry
## immediately, exactly as `_fire` does, which would make a forward walk skip the Enemy that
## slid into the gap. The resulting arrays are identical whichever way round it is read.
##
## Enemies only. There is no friendly fire anywhere in this Simulation and this would be the
## one place it existed, which is a design decision rather than an oversight: the price of a
## Barrage is already the channel, and charging a second price nobody tuned would make the
## heaviest Stratagem in the game the one nobody uses.
func _shell_the_ground(
	definition: StratagemDefinition, target: Vector3i, charges: int
) -> void:
	var centre: FixedVec2 = WorldGrid.tile_centre_metres(target)
	var reach: int = Fixed.from_int(definition.radius_tiles * WorldGrid.TILE_SIZE_METRES)
	var squared_reach: int = reach * reach
	var points: int = definition.damage_per_charge * charges
	for index: int in range(_enemy_health.size() - 1, -1, -1):
		if _squared_gap(centre, index) <= squared_reach:
			_hit_enemy(index, points)


## A Supply Drop: `goods_per_charge` times the Charges loaded, into the painting player's own
## pockets.
##
## **Their pockets rather than the Nest's store**, which is what makes it the answer to having
## run out: those are the same pockets the Build Gun spends from and a weapon fires out of, so
## Ammunition and repair material arrive where a player standing in a fight can use them. A
## drop that banked at the Nest would be a Delivery run in reverse and would ask the player to
## walk home, which is exactly what a Stratagem is for not having to do.
func _drop_supplies(definition: StratagemDefinition, player_id: int, charges: int) -> void:
	for slot: int in range(definition.goods_items.size()):
		_give_to_player(
			player_id, definition.goods_items[slot], definition.goods_counts[slot] * charges
		)


## A Sentry Drop: the Turret the row names, on the painted tile, for `sentry_seconds`, arriving
## with its magazine already filled.
##
## **An ordinary Machine in every respect a player can observe.** It aims through `_aim`, it
## spends rounds through `_craft`, it can be chewed down, it obstructs Enemies and it does not
## work on the tick it arrived — all of that is `_place_machine` and nothing else. The two
## things that make it a Sentry are an expiry tick and a pre-filled input buffer, and neither
## is a mechanism: it is how a Machine that arrived from outside the Map and needs no Belt is
## expressed in the arrays that already exist.
##
## It is filled through `_add_to_input`, which is uncapped — the cap lives in `_input_has_room`
## and belongs to a Belt hand-off. So a Sentry legitimately arrives holding more than a Belt
## could ever have put there, which is the literal content of "needs no Belt", and
## `query_turret_ammunition_capacity` reports the gauge honestly against what it is holding.
##
## The ground may have been taken during the channel, by a Machine somebody built or by a Belt
## somebody dragged. The Charges are spent either way, and nothing arrives — which is the same
## bargain an interrupted Painting strikes, and the reason `_paint_refusal` checks the ground
## up front so that this is the rare case rather than the ordinary one.
func _drop_a_sentry(
	definition: StratagemDefinition, target: Vector3i, charges: int
) -> void:
	var dropped: MachineDefinition = _definitions.machine(definition.sentry_machine)
	if dropped == null:
		return
	var size: Vector2i = WorldGrid.rotated_footprint(
		dropped.footprint_x, dropped.footprint_z, 0
	)
	if not WorldGrid.footprint_is_buildable(target, size.x, size.y):
		return
	if _footprint_is_occupied(target, size.x, size.y):
		return

	var index: int = _place_machine(
		dropped, target, 0, _tick + maxi(definition.sentry_seconds, 1) * TICKS_PER_SECOND
	)
	for slot: int in range(definition.goods_items.size()):
		_add_to_input(
			index, definition.goods_items[slot], definition.goods_counts[slot] * charges
		)


## Takes every Machine whose time is up off the Map.
##
## Walked in **descending** index order so that removing one does not skip the next, the same
## reason `_shell_the_ground` reads Enemies backwards. Which Machines go is a pure function of
## the tick and the hashed expiry array, so the order is only about the walk.
##
## A Sentry that expires loses what it was holding, exactly as a destroyed Machine does — but
## for a different reason, and one worth being explicit about: those rounds were never the
## Factory's. They arrived from outside the Map with the Turret and they leave with it, so a
## player cannot bank a Sentry Drop by letting its time run out next to a Belt.
func _expire() -> void:
	for index: int in range(_machine_expires_tick.size() - 1, -1, -1):
		if _machine_expires_tick[index] < 0:
			continue
		if _tick < _machine_expires_tick[index]:
			continue
		_remove_machine(index)


## Banks one assembled Charge, up to the Silo's capacity.
##
## Clamped rather than trusted, even though `_machine_would_work` already keeps a full Silo
## from crafting: a hot-reload can lower `charge_capacity` under a Silo that is already over
## it, and a stockpile that quietly grew past its own cap would be a number in the save file
## with no bound on it — which is the argument the Nest's store already made for being capped.
func _assemble_a_charge(index: int) -> void:
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	if definition == null or not definition.is_silo():
		return
	_silo_charges[index] = mini(_silo_charges[index] + 1, definition.charge_capacity)


## Whether a Silo has room for one more Charge.
func _silo_has_room(index: int, definition: MachineDefinition) -> bool:
	return _silo_charges[index] < definition.charge_capacity


## The loaded Silo a Painting draws from, or -1.
##
## **The one whose tile comes first in canonical tile order**, through `MapLayout.tile_precedes`
## — the single definition of tile order this project has, already used by Node sorting, Breach
## sorting and the runtime Breach insert. Geography rather than construction order, for the
## reason the Breaches are released in tile order: index order is the order a player happened
## to build in, and "which of my two Silos fired" should not be a fact about the past.
func _loaded_silo() -> int:
	var best: int = -1
	for index: int in range(query_machine_count()):
		if _silo_loaded_charges[index] <= 0:
			continue
		if best != -1 and not MapLayout.tile_precedes(
			query_machine_tile(index), query_machine_tile(best)
		):
			continue
		best = index
	return best


## Whether a Stratagem may be loaded: either no Delivery tier claims it, or one that has been
## completed does.
##
## A Stratagem is locked **because a tier names it**, which is why there is no `locked` column
## in `content/stratagems.csv` — the Stratagems a Run opens with are exactly the ones no tier
## names, the arrangement the Machines and the Gear already have.
func _stratagem_is_unlocked(stratagem_id: String) -> bool:
	if _unlocked_stratagem_ids.has(stratagem_id):
		return true
	return not _definitions.locks_stratagem(stratagem_id)


## The Stratagem a fresh Run opens with on the dial: the first unlocked one by id, so a Run
## has something loadable on it rather than something a Silo would refuse.
##
## The Build Gun's opening Machine was this same scan until #55 named it in content, and the
## difference is that a Machine had a *second* order to disagree with — the production chain
## the hotbar reads in. A Stratagem has no such order, so id order is not standing in for
## anything here and there is nothing for content to settle.
func _opening_stratagem() -> String:
	for stratagem_id: String in _definitions.stratagem_ids():
		if _stratagem_is_unlocked(stratagem_id):
			return stratagem_id
	return ""


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
## Lays the route a released drag asked for, or nothing at all.
##
## **The route is what crosses, and it lands whole or not at all.** A route half-laid up
## to the first obstruction would be a player having to demolish what they did not ask
## for, so the refusal is consulted over every tile of the route before the first Belt
## appears. `_belt_route_refusal` is the same function `query_belt_route_refusal` reports
## to the preview, which is what makes the red tiles a player saw and the Belts they got
## one rule rather than two.
func _apply_build_belt(action: InputAction) -> void:
	var from_tile: Vector3i = action.belt_from_tile()
	var to_tile: Vector3i = action.belt_to_tile()
	var corner_axis: int = action.belt_corner_axis()

	if _belt_route_refusal(action.player_id, from_tile, to_tile, corner_axis) != Refusal.NONE:
		return

	for run: BeltRoute.Run in _belt_route_runs(action.player_id, from_tile, to_tile, corner_axis):
		_settle_structure_cost(
			action.player_id, Definitions.STRUCTURE_BELT, run.length_tiles()
		)
		_lay_belt(run.from, run.direction, run.length_tiles())


## The runs a route breaks into, including the one-tile case a drag that never moved means.
##
## A one-tile Belt still has to be aimed and two identical tiles do not say which way, so
## the aim is the player's own facing — authoritative fixed-point state the Simulation
## already holds, read the same way by the apply and by the projection the preview asks, so
## the preview cannot point one way and the Belt another.
func _belt_route_runs(
	player_id: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> Array:
	if from_tile == to_tile and _is_player(player_id):
		return [
			BeltRoute.Run.new(
				from_tile,
				from_tile,
				WorldGrid.direction_from_turns(query_player_yaw_turns(player_id))
			)
		]
	return BeltRoute.segments(from_tile, to_tile, corner_axis)


## Stands one straight run of Belt up. The one place a Belt joins the Factory, so a route
## of two runs cannot fall out of step with a route of one.
func _lay_belt(entry: Vector3i, direction: int, tiles: int) -> void:
	_belt_tile_x.append(entry.x)
	_belt_tile_y.append(entry.y)
	_belt_tile_z.append(entry.z)
	_belt_direction.append(direction)
	_belt_tiles.append(tiles)
	_belt_item_ids.append(PackedStringArray())
	_belt_item_offsets.append(PackedInt64Array())
	_belt_update_order_stale = true
	# A new deck a player can stand on, and the one structure that changes the height field
	# without changing either of the Enemies' fields.
	_solid_height_stale = true


## Why a dragged route would be refused, or `Refusal.NONE`.
##
## The single authority on whether a route may be laid, in the shape `_build_refusal`
## already has: the apply obeys it and `query_belt_route_refusal` reports it, so what the
## preview shows and what the drag does cannot disagree.
##
## The **first** obstruction in route order, so a player dragging a long line reads about
## the tile nearest the end they started from rather than about whichever one the loop
## happened to reach last.
func _belt_route_refusal(
	player_id: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> int:
	# A player who is Downed or dead is not building. **Still not a build mode** — nothing
	# here asks whether building is currently permitted, it asks whether *this* player is
	# on their feet, which is a fact about them in the same way their wallet is.
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked

	var runs: Array = _belt_route_runs(player_id, from_tile, to_tile, corner_axis)
	if runs.is_empty():
		# No route at all: two tiles on different layers. There are no diagonal Belts and
		# no Belt between storeys (DESIGN.md), so this is the same answer an unreachable
		# tile gets.
		return Refusal.OFF_THE_MAP

	var tiles: int = 0
	for run: BeltRoute.Run in runs:
		var step: Vector3i = WorldGrid.direction_step(run.direction)
		tiles += run.length_tiles()
		for offset: int in range(run.length_tiles()):
			var refusal: int = _belt_tile_refusal(run.from + step * offset)
			if refusal != Refusal.NONE:
				return refusal
	# The ground before the wallet, exactly as a Machine's refusal orders them: a player
	# dragging across a Machine has a problem they fix by dragging somewhere else, and one
	# who cannot pay has a problem they fix by making a shorter route or more plate. The
	# length is the number they are deciding on and it is on screen while they decide.
	if not _can_pay_for_structure(player_id, Definitions.STRUCTURE_BELT, tiles):
		return Refusal.MISSING_MATERIALS
	return Refusal.NONE


## Why one tile of a route would be refused, or `Refusal.NONE`. What the preview tints a
## tile by, and what the whole-route refusal is the first non-`NONE` of.
func _belt_tile_refusal(tile: Vector3i) -> int:
	if not WorldGrid.is_buildable(tile):
		return Refusal.OFF_THE_MAP
	if query_belt_at_tile(tile) != -1 or query_machine_at_tile(tile) != -1:
		return Refusal.OCCUPIED
	if query_wall_at_tile(tile) != -1:
		return Refusal.OCCUPIED
	if _nest_covers(tile):
		return Refusal.OCCUPIED
	return Refusal.NONE


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
	_solid_height_stale = true


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
##
## **What the Hives standing on the Map do is lower the rate** rather than add to the total —
## see `_heat_decay_per_minute`.
func _heat_bleeds() -> void:
	if _heat <= 0:
		_heat = 0
		_heat_decay_credit = 0
		return

	_heat_decay_credit += _heat_decay_per_minute()
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
## **The first gap of a Run has its own baseline**, `heat.first_wave_interval_seconds`, and
## everything else about the interval is identical: Heat shortens it, the minimum floors it,
## and the Telegraph still gates the arrival. #35's playtest said *"crawlers dont seem to be
## coming"* — they were, 150 seconds out, in silence. The opening gap is the one interval a
## player has had no chance to shorten, because there is no Heat yet to shorten it with and
## nothing to defend against while it runs, so it is the one that teaches nothing by being
## long. It is read off `_wave_number` rather than off a flag, because "how many Waves have
## arrived" is already hashed state and a second fact saying the same thing could disagree
## with it.
##
## One integer division per call and no accumulation, so nothing here can drift. It is
## recomputed rather than carried precisely *because* a carried value would have to be
## adjusted every tick, and a per-tick adjustment is the shape this file refuses.
func _wave_interval_ticks() -> int:
	var baseline: int = _seconds_to_ticks(
		_definitions.heat_first_wave_interval_seconds
		if _wave_number == 0
		else _definitions.heat_wave_interval_baseline_seconds
	)
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
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
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
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
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


## Takes goods back out of the Nest's store and puts them in a player's hands, or refuses to.
##
## The symmetric half of `_apply_deliver_to_nest`, and the thing that closes the loop: a Belt
## banks what the open bill does not want, and this is how the Factory's output reaches the
## Build Gun. Clamped to what the store is holding, exactly as a hand-over is clamped to the
## bill — asking for more than is there takes what is there, because that is an ordinary
## thing for a player to do and not an error.
##
## Refused as a **silent no-op whose hash does not move**, the same rule a misaimed build, a
## refused hand-over and the call-early lever obey. `query_withdraw_refusal` is what says why,
## beforehand, and it is the *same function* this consults — so what a player is told and what
## the Simulation does are one rule and not two.
func _apply_withdraw_from_nest(action: InputAction) -> void:
	var item_index: int = action.withdraw_item_index()
	if _withdraw_refusal(action.player_id, item_index) != Refusal.NONE:
		return

	var item_id: String = _definitions.item_id(item_index)
	var drawn: int = _unbank_from_the_nest(item_id, action.withdraw_count())
	if drawn > 0:
		_give_to_player(action.player_id, item_id, drawn)


## Why taking an Item out of the Nest's store would be refused, or `Refusal.NONE`. A pure
## projection about a withdrawal that has not happened, so a HUD can grey a row out and say
## which of the three things is in the way before a player presses anything.
##
## **About the Item and not about an amount.** What a player hovering a store row asks is
## "can I take this at all"; how much they then take is clamped by the action, the way a
## hand-over's amount is clamped by the bill. A count in here would make the honest answer to
## "is there anything to take" depend on a number nobody has typed yet.
func _withdraw_refusal(player_id: int, item_index: int) -> int:
	if not _is_player(player_id):
		return Refusal.NO_SUCH_PLAYER
	var blocked: int = _act_refusal(player_id)
	if blocked != Refusal.NONE:
		return blocked
	if query_run_is_over():
		return Refusal.RUN_IS_OVER
	var item_id: String = _definitions.item_id(item_index)
	if item_id == "":
		return Refusal.NO_SUCH_ITEM
	if not _player_is_at_the_nest(player_id):
		return Refusal.TOO_FAR_FROM_THE_NEST
	if _nest_store_held(item_id) <= 0:
		return Refusal.NOTHING_TO_WITHDRAW
	return Refusal.NONE


## Whether a player is standing close enough to the Nest to hand goods over.
##
## The same question a withdrawal asks, because banking and spending happen at one counter:
## `nest.delivery_reach_metres` is one reach and not two, so there is no spot a player can
## stand on where the Nest will take goods but not hand any back.
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


## Everything the Nest will take of an Item right now, reporting how much of `quantity` it
## took: the open Delivery's bill first, then the store.
##
## **The one way goods enter the Nest**, so a Belt running into it has one rule and not two,
## and so the order is fixed rather than a function of which path arrived first. The bill
## first because progression is what the Nest is *for* — a store that swallowed ore the open
## tier was waiting on would quietly stall the chain a player is trying to finish.
func _nest_accepts(item_id: String, quantity: int) -> int:
	var taken: int = _accept_delivery(item_id, quantity)
	if taken < quantity:
		taken += _bank_at_the_nest(item_id, quantity - taken)
	return taken


## The pure twin of `_nest_accepts`: how much of an Item the Nest would take, without moving
## anything. What lets `_hand_off_blocked` report a Belt backed up against a Nest that wants
## nothing and has no room, rather than the renderer guessing it from a count that stopped.
func _nest_would_accept(item_id: String) -> int:
	return _delivery_would_take(item_id) + _nest_store_room(item_id)


## Puts goods into the Nest's store, reporting how many went in. Clamped to the room there
## is, because nothing is destroyed: what will not fit is not taken, and whatever offered it
## keeps it.
func _bank_at_the_nest(item_id: String, quantity: int) -> int:
	var banked: int = mini(_nest_store_room(item_id), quantity)
	if banked <= 0:
		return 0

	var slot: int = _nest_store_items.find(item_id)
	if slot != -1:
		_nest_store_counts[slot] += banked
	else:
		slot = _nest_store_items.bsearch(item_id)
		_nest_store_items.insert(slot, item_id)
		_nest_store_counts.insert(slot, banked)
	return banked


## Takes goods back out of the Nest's store, reporting how many came out. Clamped to what is
## there, and the Item's entry is dropped once it empties so the store lists what it holds
## rather than what it has ever held — which is also what keeps the hash a function of the
## contents and not of the history.
func _unbank_from_the_nest(item_id: String, quantity: int) -> int:
	var slot: int = _nest_store_items.find(item_id)
	if slot == -1:
		return 0
	var drawn: int = mini(_nest_store_counts[slot], maxi(quantity, 0))
	if drawn <= 0:
		return 0

	_nest_store_counts[slot] -= drawn
	if _nest_store_counts[slot] == 0:
		_nest_store_items.remove_at(slot)
		_nest_store_counts.remove_at(slot)
	return drawn


## How much of an Item the Nest's store is holding.
func _nest_store_held(item_id: String) -> int:
	var slot: int = _nest_store_items.find(item_id)
	if slot == -1:
		return 0
	return _nest_store_counts[slot]


## How much more of an Item the store has room for.
##
## Zero once the Run is over: a Nest that has fallen is not a counter anybody is banking at,
## which is the rule `_delivery_would_take` already obeys, and it is what stops a Belt
## quietly filling a ruin.
##
## **And zero for an Item a player could not spend again**, which is the single clause #37's
## second trap needed. The store is the faucet — "where Factory output becomes something a
## player can spend again" — and `Definitions.item_can_be_spent` is the question that asks
## whether a given Item is any such thing. Coal is not: nothing's `build_cost` names it and no
## weapon fires it, so 200 coal banked at the Nest is a Factory's fuel converted into a number
## with no sink. The *bill* still takes coal whenever a tier asks for it, because the bill is
## paid before the store and a tier asking for coal is the Delivery chain making the diversion
## the player's visible, finite decision.
##
## What that buys is the rule this project already relies on everywhere else, now reaching the
## case that mattered: a coal Belt a player ran to the Nest pays the open tier, and then the
## store refuses it, the Belt packs up where they can see it, and **the diversion ends
## itself**. Before this it went on quietly taking half of the one coal Node for ten minutes
## while the Boiler browned the Factory out, with the player having done nothing they could
## see. Nothing is destroyed: what will not fit is not taken.
func _nest_store_room(item_id: String) -> int:
	if query_run_is_over():
		return 0
	if not _definitions.item_can_be_spent(item_id):
		return 0
	return maxi(_definitions.nest_store_capacity_per_item - _nest_store_held(item_id), 0)


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


## The Machine a fresh Run opens with on the Build Gun: the one `player.starting_machine`
## names.
##
## **It used to be the first unlocked Machine by id, and that was three Machines past
## where the hotbar says to start.** The index space is the sorted content, so the first
## row is whatever sorts first — `ammo_press_mk1` on the shipped table — while the order a
## player reads the hotbar in is the *production chain*, derived in `game/build_chain.gd`
## out of what each Recipe eats and makes. Those are two different orders and only one of
## them is a `sim/` concept, so the Simulation is **told** where a Run starts rather than
## working it out: #55.
##
## No fallback and no scan, because the guarantee moved rather than being dropped.
## `Definitions._check_starting_machine` refuses a set whose key names no row or names one
## a Delivery tier locks, and a set with any error carries no definitions at all — so by
## the time this runs the id is a real, unlocked Machine. A fallback here would be a second
## opinion about which Machine that is, in the one place a disagreement is invisible.
##
## Read once, at construction, which is why a hot-reload that edits the key does not move
## what is already in a player's hands — the rule `player.starting_stock` obeys for the
## same reason: raising it mid-Run is not a way to conjure materials.
func _opening_machine() -> String:
	return _definitions.player_starting_machine


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
	# Marching, always. Even a Breaker emerging a tile from a Smelter starts on the Nest's
	# field: where it breaks ranks is a fact about the Map and not about the Breach, and a
	# Breaker that arrived already hunting would be the behaviour #34 replaced.
	_enemy_broke_ranks.append(0)
	# Facing the Nest, which is where everything on this Map is ultimately going. It matters
	# for a Siege Hulk and for nothing else: a Hulk that arrived facing its own feet would have
	# every direction count as behind it, so its armour would be missing for the walk in.
	var facing: FixedVec2 = _nest_centre_metres()
	_enemy_face_x.append(facing.x)
	_enemy_face_z.append(facing.z)
	_next_enemy_serial += 1


## The hit points an Enemy of a kind arrives with, or 0 for a kind that does not exist.
## One `match` rather than a column in the Wave table, because health is a property of the
## Enemy and the Wave table says how many of them come, not what they are.
func _enemy_health_for(kind: int) -> int:
	match kind:
		EnemyKind.CRAWLER:
			return _definitions.crawler_health
		EnemyKind.BREAKER:
			return _definitions.breaker_health
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_health
		_:
			return 0


## How far an Enemy of a kind walks in one tick, in fixed-point metres. One division per
## kind per tick and nothing accumulated, so there is nothing here to drift.
func _enemy_step_metres(kind: int) -> int:
	return Fixed.div(_enemy_speed(kind), Fixed.from_int(TICKS_PER_SECOND))


## How fast an Enemy of a kind moves, in fixed-point metres per second.
func _enemy_speed(kind: int) -> int:
	match kind:
		EnemyKind.CRAWLER:
			return _definitions.crawler_speed
		EnemyKind.BREAKER:
			return _definitions.breaker_speed
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_speed
		_:
			return 0


## What one bite from an Enemy of a kind takes off whatever it is chewing, in whole hit
## points. The same number whether the target is the Nest, a Machine or a Wall: an Enemy has
## one bite and the thing it bites has hit points, which is what keeps combat free of a table
## of multipliers.
func _enemy_damage(kind: int) -> int:
	match kind:
		EnemyKind.CRAWLER:
			return _definitions.crawler_damage
		EnemyKind.BREAKER:
			return _definitions.breaker_damage
		# A Siege Hulk's *stomp*, not its shell. The shell is
		# `siege_hulk.shell_damage` and is dealt where it lands rather than by whatever fired
		# it, which is the difference between artillery and a bite.
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_stomp_damage
		_:
			return 0


## How many whole ticks between one bite from an Enemy of a kind and the next. At least one:
## a bite that took no time would do unbounded damage.
func _enemy_attack_interval_ticks(kind: int) -> int:
	match kind:
		EnemyKind.CRAWLER:
			return maxi(_seconds_to_ticks(_definitions.crawler_attack_interval_seconds), 1)
		EnemyKind.BREAKER:
			return maxi(_seconds_to_ticks(_definitions.breaker_attack_interval_seconds), 1)
		EnemyKind.SIEGE_HULK:
			return maxi(_seconds_to_ticks(_definitions.siege_hulk_shell_interval_seconds), 1)
		_:
			return 1


## How wide an Enemy's hit volume is, in fixed-point metres.
##
## `gear.enemy_hit_radius_metres` is the Crawler's, and it is tuned for a low scuttling thing;
## a Siege Hulk is several metres across and a player who could miss one by a metre would read
## the gun as broken rather than themselves as imprecise. One `match` beside the other four,
## so a kind's size is where a kind's health and speed are.
##
## **The Breaker gained its own in #49, and the reason is readability rather than combat.** It
## and the Crawler were the same KayKit rig at the same declared height, so at thirty metres
## both were the same twenty-five pixels of dark silhouette and a player could not tell the
## thing that eats Machines from the thing that is merely numerous. Size is the cue that
## survives any range and any light, and this is the one authority on it: `WorldView` scales
## the body it draws by `query_enemy_hit_height_metres`, so **a player shoots at what they can
## see** and there is no second opinion about how big a Breaker is. The radius moved with the
## height for exactly that reason — the drawn body is scaled uniformly, so a capsule that kept
## the Crawler's width would be narrower than the Breaker a player is aiming at.
func _enemy_hit_radius(kind: int) -> int:
	match kind:
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_hit_radius_metres
		EnemyKind.BREAKER:
			return _definitions.breaker_hit_radius_metres
		_:
			return _definitions.gear_enemy_hit_radius_metres


## How tall an Enemy's hit volume is, in fixed-point metres.
func _enemy_hit_height(kind: int) -> int:
	match kind:
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_hit_height_metres
		EnemyKind.BREAKER:
			return _definitions.breaker_hit_height_metres
		_:
			return _definitions.gear_enemy_hit_height_metres


## How much of a hit an Enemy of a kind shrugs off **from the front**, as a whole percentage.
## Zero for everything but the boss, which is what "Chaff is one-hit" means arithmetically.
func _enemy_frontal_armour_percent(kind: int) -> int:
	match kind:
		EnemyKind.SIEGE_HULK:
			return _definitions.siege_hulk_frontal_armour_percent
		_:
			return 0


## How much of a hit an Enemy actually takes, given where in the world the hit came from.
##
## **This is the weak point, and it is the whole shape of the Siege Hulk fight.** The
## alternative was a damage sponge, which is a timer rather than a fight: more hit points only
## ever asks a player to hold the trigger for longer, and it would have made the answer to the
## boss "bring more Ammunition" instead of "move".
##
## The test is the **sign of one dot product** and nothing else: the Hulk's facing is held as a
## point (see `_enemy_face_x`), so the hit came from behind exactly when the gap to the shooter
## points away from the gap to what the Hulk is facing. Exact integer arithmetic, no
## normalisation, no arc-tangent and no rounding rule — so two clients cannot disagree about
## whether a round found the vents.
##
## A hit from exactly abreast counts as **behind**, which is the generous reading on purpose:
## the armour is the thing a player has to discover, and a boundary that punished a flank that
## was not quite far enough round would teach the wrong lesson.
func _armoured(index: int, points: int, from: FixedVec2) -> int:
	if points <= 0 or not _is_enemy(index):
		return 0
	var percent: int = _enemy_frontal_armour_percent(_enemy_kind[index])
	if percent <= 0:
		return points
	var face_x: int = _enemy_face_x[index] - _enemy_x[index]
	var face_z: int = _enemy_face_z[index] - _enemy_z[index]
	var to_x: int = from.x - _enemy_x[index]
	var to_z: int = from.z - _enemy_z[index]
	if Fixed.mul(face_x, to_x) + Fixed.mul(face_z, to_z) <= 0:
		return points
	return _scaled(points, -percent)


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

	# **Both fields, resolved once for the whole tick.** An Enemy that chews a Machine to
	# nothing part-way through this loop invalidates both of them — a destroyed Machine is
	# one fewer obstruction and one fewer seed — and rebuilding there would make the tick
	# O(Enemies x map), which is the quadratic the Chaff tier could never pay. So
	# `_destroy_machine` sets `_flowfield_stale` and nothing rebuilds until the next tick
	# that needs a field: the survivors finish this tick on the field they started it on and
	# inherit the new gap on the next. One tick of latency on a route is invisible; a 50 ms
	# hitch in the middle of a Wave is not.
	var nest_field: PackedInt64Array = _flowfield()
	var factory_field: PackedInt64Array = _machine_flowfield()
	# Swept with the two fields above and fresh for the same reason: how far the Nest is and
	# how far the nearest Machine is, in whole tiles, which is what #34's perimeter is
	# compared against.
	var nest_distance: PackedInt64Array = _flow_distance
	var factory_distance: PackedInt64Array = _machine_flow_distance

	for index: int in range(query_enemy_count()):
		# An Enemy does not act on the tick it came through its Breach, for the reason a
		# Machine does not run on the tick it was built: it arrived *during* that tick, and
		# crediting it a whole tick of walking would put its first step a tick early.
		if _enemy_spawn_tick[index] == _tick:
			continue
		var kind: int = _enemy_kind[index]
		# The boss, in two lines. Everything a Siege Hulk does differently from a Crawler is
		# behind one call rather than spread through the loop as branches, which is what keeps
		# the Chaff tier's loop the loop it was measured at.
		if kind == EnemyKind.SIEGE_HULK:
			_siege_hulk(index, nest_field)
			continue
		# **A Breaker marches with the Wave and then goes hunting (#34).** It steers by the
		# Nest's field — the road every Crawler walks, and the road a player fortifies —
		# until it is inside `enemy.breaker_breaks_ranks_within_tiles` of the Nest or of a
		# Machine, and by the Factory's field from that tile on. A Crawler steers by the
		# Nest's throughout. Falling back from one field onto the other is
		# `_enemy_direction`'s job, so the field an Enemy *moves* by and the field it decides
		# whether it is cornered by are the same field.
		var field: PackedInt64Array = nest_field
		if kind == EnemyKind.BREAKER:
			if _breaker_has_broken_ranks(index, nest_distance, factory_distance):
				field = factory_field
		if _enemy_bites(index, kind, field, nest_field):
			continue
		_advance_enemy(index, field, nest_field, _enemy_step_metres(kind))


## Whether a Breaker is hunting the Factory yet, latching it the tick it starts.
##
## **One sentence of rule: a Breaker marches with the Wave until it is within
## `enemy.breaker_breaks_ranks_within_tiles` of either the Nest or a Machine, and hunts from
## then on.** Two clauses, and both of them are needed:
##
## 1. **Within reach of the Nest.** The normal case, and the whole of #34. A Factory is built
##    around its Nest, so coming inside the Nest's perimeter is coming inside the Factory — and
##    it means the Breaker walks the *Wave's* road to get there, which is the road a player
##    fortifies. Before this it took whichever line was shortest to a Machine, so a Turret
##    covering the way in never saw one.
## 2. **Within reach of a Machine.** Without it the rule says something stupid on a Map whose
##    Factory is nowhere near its Nest: a Breaker would walk the length of the Factory, past
##    every Machine in it, to the Nest's doorstep, and then walk all the way back. With it, a
##    Breaker lunges at the first thing it can reach from the road it is on — which is also the
##    more legible rule, because it makes *what a player puts beside the lane* the thing that
##    gets eaten first.
##
## **Two reads of fields that are already built, and no third field.** `_flow_distance` and
## `_machine_flow_distance` hold the exact four-connected tile count from every tile to the
## Nest's footprint and to the nearest Machine, and both are swept already — so "is either of
## them at hand" is two array lookups and two integer comparisons. No distance, no square root,
## no rebuild. And a tile count means tiles of *walking*: a Machine behind a Wall is as far away
## as the detour round it.
##
## Latched, because the quantities it is decided on move the wrong way afterwards: a Breaker
## that has turned on a Machine is walking *away* from the Nest, so re-deciding every tick
## would send it back across the boundary on its first step and leave it shuffling there.
## Latching also says the right thing about a Breaker — once it has chosen, it commits, and the
## turn is something a player can watch happen.
##
## A tile neither sweep reached — inside an obstruction, or ground walled off from both — carries
## no distance and keeps the Breaker marching, because "unreachable" is not "at hand".
##
## Takes the distance arrays rather than reading the fields itself, for the reason `_enemies`
## resolves both of them once for the whole tick: a rebuild inside the Enemy loop would make
## the tick O(Enemies x map).
func _breaker_has_broken_ranks(
	index: int, nest_distance: PackedInt64Array, factory_distance: PackedInt64Array
) -> bool:
	if _enemy_broke_ranks[index] == 1:
		return true
	var perimeter: int = _definitions.breaker_breaks_ranks_within_tiles
	if perimeter <= 0:
		return false
	var cell: int = _field_index(WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index]))
	if cell == -1:
		return false
	var at_hand: bool = (
		_within_field_reach(cell, nest_distance, perimeter)
		or _within_field_reach(cell, factory_distance, perimeter)
	)
	if not at_hand:
		return false
	_enemy_broke_ranks[index] = 1
	return true


## Whether a swept field puts a cell's destination inside `tiles` steps of walking. False for a
## cell the sweep never reached, which is what keeps "unreachable" from reading as "at hand".
func _within_field_reach(cell: int, distance: PackedInt64Array, tiles: int) -> bool:
	if cell >= distance.size():
		return false
	var steps: int = distance[cell]
	return steps >= 0 and steps <= tiles


## Lets one Enemy bite whatever it is in contact with, and reports whether this tick was
## spent attacking rather than walking.
##
## Returns true while a bite is on cooldown as well as on the tick it lands: an Enemy chewing
## something stays put between bites rather than shuffling forward and back.
func _enemy_bites(
	index: int, kind: int, field: PackedInt64Array, fallback: PackedInt64Array
) -> bool:
	var target: Vector2i = _enemy_contact_target(index, kind, field, fallback)
	if target.x == BITE_NOTHING:
		return false
	if _enemy_attack_cooldown[index] > 0:
		_enemy_attack_cooldown[index] -= 1
		return true

	var points: int = _enemy_damage(kind)
	match target.x:
		BITE_NEST:
			_damage_the_nest(points)
		BITE_MACHINE:
			_damage_machine(target.y, points)
		BITE_WALL:
			_damage_wall(target.y, points)
		BITE_PLAYER:
			_damage_player(target.y, points)
	# One short of the interval, because this tick is the first of the wait. A bite every
	# `attack_interval_seconds` exactly, with nothing rounding.
	_enemy_attack_cooldown[index] = maxi(_enemy_attack_interval_ticks(kind) - 1, 0)
	return true


## What an Enemy would bite this tick, as a `(what, which)` pair, or `BITE_NOTHING`.
##
## Three clauses, in this order, and the order *is* the design:
##
## 1. **A Breaker takes a Machine over anything else.** That is the whole of what a Breaker
##    is (GLOSSARY.md: it preferentially attacks Machines rather than players) and it is what
##    makes Machine mortality *felt* rather than merely true — a Crawler walking past a
##    Smelter proves nothing about whether the Smelter was ever at risk.
## 2. **Either kind bites a player standing within reach.** #15 added this clause and
##    nothing else, which is what #11 promised it would be. Ranked *below* a Machine, so a
##    Breaker still prefers the Factory with somebody standing in front of it — which is
##    what makes GLOSSARY.md's sentence literal rather than aspirational — and *above* the
##    Nest, so putting yourself in a doorway buys the Nest time at the price of your own
##    skin.
## 3. **Either kind bites the Nest it is standing at.** A Breaker that has run out of Factory
##    is still an Enemy at the gate, and the Nest is still the only thing whose loss ends the
##    Run.
## 4. **Either kind chews its way out of a pocket it cannot route out of.** Without this,
##    sealing a Breach behind a ring of Walls would be a cheese rather than a defence: no
##    route means `_enemy_direction` falls back on walking straight at the Nest, and a swarm
##    would drift through solid Walls. With it, sealing buys exactly as much time as the
##    Walls have hit points, which is what a Wall is for. Machines before Walls, so a Crawler
##    boxed in by its own captor's Factory eats the Factory.
##
## A Crawler with a route therefore still walks past a Machine untouched, which is the
## Chaff's job: Chaff is the sense of threat and the Breaker is the threat (DESIGN.md).
func _enemy_contact_target(
	index: int, kind: int, field: PackedInt64Array, fallback: PackedInt64Array
) -> Vector2i:
	if not _is_enemy(index):
		return Vector2i(BITE_NOTHING, -1)
	var tile: Vector3i = WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])

	if kind == EnemyKind.BREAKER:
		var machine: int = _machine_in_contact(tile)
		if machine != -1:
			return Vector2i(BITE_MACHINE, machine)

	# A player standing within reach, of either kind. **Ranked below a Machine and above
	# the Nest**, which is exactly where #11 said this clause would go when players
	# acquired health — and it is what finally makes GLOSSARY.md's Breaker literal: a
	# Breaker with a Smelter in reach chews the Smelter with a player standing next to it,
	# which is the whole of "preferentially attacks Machines rather than players". Above
	# the Nest, so standing in a doorway is a real way to buy the Nest time, at the only
	# price this game charges for anything: your own attention and your own skin.
	var victim: int = _player_in_contact(index)
	if victim != -1:
		return Vector2i(BITE_PLAYER, victim)

	if _nest_in_contact(tile):
		return Vector2i(BITE_NEST, -1)

	if _enemy_direction(tile, field, fallback) != -1:
		return Vector2i(BITE_NOTHING, -1)
	# An Enemy *inside* an obstruction walks out of it rather than chewing it, which is #9's
	# rule and still the right one: a player who drops a Machine on top of a Crawler has not
	# built a prison, and `_towards_the_nest` is what makes that true. The chewing clause is
	# for an Enemy standing on open ground with nowhere left to walk — a sealed pocket — which
	# is the case where a beeline would send a swarm drifting through solid Walls.
	if _tile_is_blocked(tile):
		return Vector2i(BITE_NOTHING, -1)
	return _structure_in_contact(tile)


## The Machine whose footprint covers the tile an Enemy is standing on or one sharing an edge
## with it, or -1. Walked in Machine index order, which is construction order and the same on
## every client.
func _machine_in_contact(tile: Vector3i) -> int:
	for step: int in range(WorldGrid.DIRECTION_COUNT + 1):
		var at: Vector3i = tile if step == 0 else tile + WorldGrid.direction_step(step - 1)
		var machine: int = query_machine_at_tile(at)
		if machine != -1:
			return machine
	return -1


## The Machine or Wall in contact with a tile, Machines first. For the cornered case only:
## what an Enemy chews when it has nowhere left to walk.
func _structure_in_contact(tile: Vector3i) -> Vector2i:
	var machine: int = _machine_in_contact(tile)
	if machine != -1:
		return Vector2i(BITE_MACHINE, machine)
	for step: int in range(WorldGrid.DIRECTION_COUNT + 1):
		var at: Vector3i = tile if step == 0 else tile + WorldGrid.direction_step(step - 1)
		var wall: int = query_wall_at_tile(at)
		if wall != -1:
			return Vector2i(BITE_WALL, wall)
	return Vector2i(BITE_NOTHING, -1)


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
func _advance_enemy(
	index: int, field: PackedInt64Array, fallback: PackedInt64Array, step_metres: int
) -> void:
	if step_metres <= 0:
		return
	var tile: Vector3i = WorldGrid.tile_at_metres(_enemy_x[index], _enemy_z[index])
	var direction: int = _enemy_direction(tile, field, fallback)

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


## Backs an Enemy one tick directly away from a point.
##
## The Siege Hulk's answer to a Turret, and the only thing in this file that walks an Enemy
## *against* a field. It moves on whichever axis it is further out on, which is
## `_towards_the_nest` run backwards: a straight line is not pathing, it is a refusal to stand
## somewhere it can be shot. An Enemy exactly on top of the thing it is backing away from steps
## along +x, so the degenerate case moves rather than freezing.
func _withdraw_enemy(index: int, from: FixedVec2, step_metres: int) -> void:
	if step_metres <= 0:
		return
	var gap_x: int = _enemy_x[index] - from.x
	var gap_z: int = _enemy_z[index] - from.z
	if gap_x == 0 and gap_z == 0:
		_enemy_x[index] += step_metres
		return
	if absi(gap_x) >= absi(gap_z):
		_enemy_x[index] += signi(gap_x) * step_metres
		return
	_enemy_z[index] += signi(gap_z) * step_metres


## How far a coordinate is from the nearer end of a span, signed towards it. 0 when it is
## already inside the span.
func _gap_to_span(value: int, low: int, high: int) -> int:
	if value < low:
		return low - value
	if value > high:
		return high - value
	return 0


## The way out of a tile for an Enemy steering by `field`, falling back on `fallback`, or -1
## when neither field can route it anywhere.
##
## The fallback is what sends a Breaker whose Factory has been flattened — or whose quarry is
## walled off from it — at the Nest instead, and it is a no-op for a Crawler, whose two fields
## are the same field. Consulted by both `_advance_enemy` and `_enemy_contact_target`, so
## "which way am I going" and "am I cornered" are one answer rather than two that could
## disagree about whether a Wall should be chewed.
func _enemy_direction(
	tile: Vector3i, field: PackedInt64Array, fallback: PackedInt64Array
) -> int:
	var cell: int = _field_index(tile)
	if cell == -1:
		return -1
	var direction: int = field[cell] if cell < field.size() else -1
	if direction != -1:
		return direction
	return fallback[cell] if cell < fallback.size() else -1


# ── The Siege Hulk ────────────────────────────────────────────────────────────
#
# The threat the Factory cannot answer, and the reason the first-person pillar exists
# (DESIGN.md). Everything else in this game is solved by building; this is solved by a player
# walking out of the Nest with what the Factory made.
#
# It is an entry in the Enemy arrays like everything else. What it adds is one function, two
# parallel arrays and three tuning sections — no second index space, no class, no combat
# subsystem, and no branch anywhere in the Crawler's path.

## One Siege Hulk, one tick. Four clauses, and the order is the design.
##
## 1. **A player at its feet is answered first, and a stomp spends the shell's cooldown.** So
##    closing the distance is immediately worth something even before the Hulk is dead: a
##    player standing there is a player whose Factory is not being shelled. That is the same
##    trade standing in a doorway makes against a Crawler, at the same price — your own skin —
##    and it is what makes the sortie pay off from the first second rather than only at the
##    end.
## 2. **A Turret that could reach it makes it back off.** This is the acceptance criterion "it
##    cannot be defeated by Turrets alone" as behaviour rather than as arithmetic: push a
##    Turret line out towards it and it withdraws and goes on shelling from further away.
##    `Definitions` already refuses content where a Turret's reach covers the stand-off, so in
##    practice this clause fires only for a Turret a player has walked out into the field — and
##    then it fires, rather than letting the Factory quietly solve the one thing it must not.
## 3. **Nothing within shelling reach means walk.** It steers by the Crawlers' shared field,
##    because what it is looking for is the Factory and the Nest is in the middle of it — one
##    more consumer of a field that is already built rather than a third sweep.
## 4. **Otherwise hold and bombard.** It stops the moment anything is in reach, so where it
##    comes to rest *is* `siege_hulk.range_metres` and not a second number that could disagree
##    with it. Legible from the HUD and from the Map: it walks in, it halts, it shells.
func _siege_hulk(index: int, nest_field: PackedInt64Array) -> void:
	var step_metres: int = _enemy_step_metres(EnemyKind.SIEGE_HULK)
	var here: FixedVec2 = FixedVec2.new(_enemy_x[index], _enemy_z[index])

	var victim: int = _player_in_contact(index)
	if victim != -1:
		_face_enemy_at(index, query_player_position(victim))
		if _spend_the_hulks_cooldown(index):
			return
		_damage_player(victim, _enemy_damage(EnemyKind.SIEGE_HULK))
		return

	var turret: int = _turret_covering(index)
	if turret != -1:
		var threat: FixedVec2 = _machine_centre_metres(turret)
		_face_enemy_at(index, threat)
		_withdraw_enemy(index, threat, step_metres)
		return

	var target: Vector2i = _bombardment_target(index)
	if target.x == BOMBARD_NOTHING:
		_face_enemy_at(index, _nest_centre_metres())
		_advance_enemy(index, nest_field, nest_field, step_metres)
		return

	var impact: FixedVec2 = _bombardment_point(target)
	_face_enemy_at(index, impact)
	if _spend_the_hulks_cooldown(index):
		return
	_lob_a_shell(impact)


## Whether a Siege Hulk is still between actions, spending one tick of the wait if it is.
##
## One counter for the shell and the stomp, which is the whole of why melee against it works.
## Reset one short of the interval, for the reason a bite cooldown is: this tick is the first of
## the gap, so a Hulk acts every `siege_hulk.shell_interval_seconds` exactly.
func _spend_the_hulks_cooldown(index: int) -> bool:
	if _enemy_attack_cooldown[index] > 0:
		_enemy_attack_cooldown[index] -= 1
		return true
	_enemy_attack_cooldown[index] = maxi(
		_enemy_attack_interval_ticks(EnemyKind.SIEGE_HULK) - 1, 0
	)
	return false


## Points an Enemy at a place. The front of a Siege Hulk is wherever this last said, which is
## what `_armoured` measures a hit against.
func _face_enemy_at(index: int, at: FixedVec2) -> void:
	_enemy_face_x[index] = at.x
	_enemy_face_z[index] = at.z


## The Turret whose reach covers an Enemy, or -1. Walked in Machine index order, which is
## construction order and the same on every client.
func _turret_covering(enemy: int) -> int:
	for index: int in range(query_machine_count()):
		var definition: MachineDefinition = _definitions.machine(_machine_id[index])
		if definition == null or not definition.is_turret():
			continue
		if _within_reach(index, definition, enemy):
			return index
	return -1


## What a Siege Hulk would shell this tick, as a `(what, which)` pair, or `BOMBARD_NOTHING`.
##
## **Deterministic, and it reads no unordered collection.** The Machines are walked in index
## order — construction order, identical on every client — on a **strict** improvement in
## squared distance, so two Machines exactly as far away hand the shell to the one built first.
## The Nest is one more candidate, compared last and taken only on a strict improvement, so a
## Machine and the Nest at the same distance hand the shell to the Machine: the Factory is what
## a bombardment is for, and the Nest is what is left when there is no Factory.
##
## Squared on both sides, for the reason a Turret's reach is: `Fixed.sqrt` floors, and a Machine
## exactly on the boundary must not be in or out by a rounding rule.
func _bombardment_target(index: int) -> Vector2i:
	var here: FixedVec2 = FixedVec2.new(_enemy_x[index], _enemy_z[index])
	var reach: int = _definitions.siege_hulk_range_metres
	var within: int = reach * reach

	var best: int = -1
	var best_gap: int = 0
	for machine: int in range(query_machine_count()):
		var gap: int = _squared_metres_gap(here, _machine_centre_metres(machine))
		if gap > within:
			continue
		if best != -1 and gap >= best_gap:
			continue
		best = machine
		best_gap = gap

	var nest_gap: int = _squared_metres_gap(here, _nest_centre_metres())
	if nest_gap <= within and (best == -1 or nest_gap < best_gap):
		return Vector2i(BOMBARD_NEST, -1)
	if best != -1:
		return Vector2i(BOMBARD_MACHINE, best)
	return Vector2i(BOMBARD_NOTHING, -1)


## Where a shell at a bombardment target would land, in fixed-point metres: the footprint
## centre of whatever was chosen, for the reason a Turret measures from one.
func _bombardment_point(target: Vector2i) -> FixedVec2:
	if target.x == BOMBARD_MACHINE:
		return _machine_centre_metres(target.y)
	return _nest_centre_metres()


## Puts a shell in the air at a place on the ground.
##
## It lands `siege_hulk.shell_flight_seconds` later and not sooner, and the place is state the
## renderer and the HUD both read — so the marker a player dodges is literally where the damage
## will be rather than an approximation of it.
func _lob_a_shell(at: FixedVec2) -> void:
	_shell_x.append(at.x)
	_shell_z.append(at.z)
	_shell_ticks_left.append(maxi(_shell_flight_ticks(), 1))


## How long a shell is in the air, in whole ticks. At least one: a shell that landed on the
## tick it was fired is the ambush the Telegraph exists to prevent, and `Definitions` refuses a
## tuning value that would produce one, so this floor is the belt to that braces.
func _shell_flight_ticks() -> int:
	return maxi(_seconds_to_ticks(_definitions.siege_hulk_shell_flight_seconds), 1)


## Advances every shell in the air by one tick and lands the ones that have arrived.
##
## Walked in index order, which is the order the shells were fired in, so which of two shells
## lands first is a fact about which Hulk fired first. The landings are resolved before anything
## is removed, and the removals then run from the highest index down, because removing from the
## front of an array under a loop is the one way to make a deterministic pass disagree with
## itself.
func _shells() -> void:
	if query_run_is_over() or _shell_ticks_left.is_empty():
		return

	var landed: PackedInt64Array = PackedInt64Array()
	for index: int in range(_shell_ticks_left.size()):
		_shell_ticks_left[index] -= 1
		if _shell_ticks_left[index] <= 0:
			landed.append(index)

	for position: int in range(landed.size()):
		_a_shell_lands(landed[position])
	for position: int in range(landed.size() - 1, -1, -1):
		_remove_shell(landed[position])


## One shell, landing.
##
## Everything within `siege_hulk.shell_blast_radius_metres` of the impact point takes
## `siege_hulk.shell_damage`: Machines, Walls, players and the Nest — which is the acceptance
## criterion "it damages Machines and the Nest from that range" in one function rather than two
## rules. A blast rather than a single target because that is what a bombardment *is*, and
## because it gives dense building a cost that nothing else in the game charges for.
##
## Every distance is measured from a centre to a centre, squared on both sides, the way a
## Turret's reach and a Pylon's are. And every loop runs from the highest index **down**,
## because `_damage_machine` may destroy a Machine and `_remove_machine` closes the gap — the
## damage is independent per target, so the direction cannot change the outcome, and descending
## is what keeps the indices valid while it happens.
func _a_shell_lands(index: int) -> void:
	var at: FixedVec2 = FixedVec2.new(_shell_x[index], _shell_z[index])
	var radius: int = _definitions.siege_hulk_shell_blast_radius_metres
	var within: int = radius * radius
	var points: int = _definitions.siege_hulk_shell_damage

	for machine: int in range(query_machine_count() - 1, -1, -1):
		if _squared_metres_gap(at, _machine_centre_metres(machine)) <= within:
			_damage_machine(machine, points)
	for wall: int in range(query_wall_count() - 1, -1, -1):
		if _squared_metres_gap(at, WorldGrid.tile_centre_metres(query_wall_tile(wall))) <= within:
			_damage_wall(wall, points)
	# A player standing in the marker dies, which is what makes the marker worth reading. By
	# distance rather than by tile, for the reason an Enemy reaches a player by distance: a
	# player is a position in fixed-point metres and not a footprint.
	for player_id: int in range(query_player_count()):
		if _player_life_state[player_id] != LIFE_ALIVE:
			continue
		if _squared_metres_gap(at, query_player_position(player_id)) <= within:
			_damage_player(player_id, points)
	if _squared_metres_gap(at, _nest_centre_metres()) <= within:
		_damage_the_nest(points)


## Takes a shell out of the air, preserving the order of the rest.
func _remove_shell(index: int) -> void:
	_shell_x.remove_at(index)
	_shell_z.remove_at(index)
	_shell_ticks_left.remove_at(index)


# ── The Hives ─────────────────────────────────────────────────────────────────
#
# Continuous pressure out on the Map, and the one thing in this game whose removal is
# **permanent** (GLOSSARY.md). A Hive does two things and they are deliberately the same thing
# from the player's side: it pays Heat into the Wave schedule every minute it lives, and it
# sends an Enemy out every `hive.spawn_interval_seconds`. The first is what makes "reduces
# pressure permanently" a number a player can read off the gauge they already watch — Heat
# shortens the interval between Waves on the tick it rises, so a standing Hive is hunting the
# Factory sooner, right now, for ever. The second is what makes it *pressure* rather than
# arithmetic: the gaps between Waves stop being free.
#
# Both, rather than one, because either alone is half a mechanic. Heat alone would make a Hive
# an invisible modifier on a countdown; a spawner alone would make it a Breach that is merely
# further away, and killing it would relieve nothing a player could feel between Waves.

## How much Heat the Nest actually sheds per minute: what `heat.decay_per_minute` says, less
## `hive.heat_shadow_per_minute` for every Hive still standing, floored at nothing.
##
## **This one function is the whole of what a Hive does**, and the whole of why destroying one
## is permanent relief. A Hive takes no tick of its own, holds no cooldown and sends nothing out
## — it changes a rate, and the rate is read fresh every tick from the live set, so the moment
## the last Hive falls the Nest is hiding everything it ever could again.
##
## Derived rather than stored, for the reason `_wave_interval_ticks` is derived: a stored rate
## would have to be adjusted when a Hive died, and a per-event adjustment is the shape this file
## refuses. One subtraction per tick out of two integers, nothing accumulated, nothing to drift.
##
## Floored at zero rather than allowed to go negative, because a negative decay is Heat the
## Hives are *adding* — and that is the version of this mechanic that was rejected. Enough Hives
## make the Nest unable to hide anything; they never make it loud on their own, because an idle
## Factory is owed its silence (DESIGN.md).
func _heat_decay_per_minute() -> int:
	return maxi(
		_definitions.heat_decay_per_minute
		- query_hive_count() * _definitions.hive_heat_shadow_per_minute,
		0
	)


## Takes hit points off a Hive, and removes it for good if that was the last of them.
##
## **There is no path back.** Nothing in this file appends to the Hive arrays after
## construction, so a destroyed Hive is permanently destroyed and the pressure it was paying is
## permanently gone — which is the whole of what GLOSSARY.md promises and the reason a sortie is
## worth making at all.
func _damage_hive(index: int, points: int) -> void:
	if points <= 0 or not _is_hive(index):
		return
	_hive_health[index] = maxi(_hive_health[index] - points, 0)
	if _hive_health[index] == 0:
		_remove_hive(index)


## Takes a Hive off the Map, preserving the order of the rest.
func _remove_hive(index: int) -> void:
	_hive_tile_x.remove_at(index)
	_hive_tile_y.remove_at(index)
	_hive_tile_z.remove_at(index)
	_hive_health.remove_at(index)


func _is_hive(index: int) -> bool:
	return index >= 0 and index < _hive_health.size()


## Whether a tile is close enough to the Nest to bite it: the Nest's footprint covers it, or
## covers one sharing an edge with it.
##
## Tiles rather than a fixed-point radius, because the Nest is a footprint on a grid rather
## than a point, and a tile answer cannot disagree with the flowfield about which tiles count
## as at the Nest.
func _nest_in_contact(tile: Vector3i) -> bool:
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


## The field a Breaker steers by: the same sweep seeded on every Machine's footprint rather
## than on the Nest. Empty — every tile -1 — when the Factory has no Machines, which is what
## sends a Breaker with nothing to break at the Nest instead.
func _machine_flowfield() -> PackedInt64Array:
	if _flowfield_stale or _machine_flow_direction.size() != FIELD_TILES:
		_rebuild_flowfield()
	return _machine_flow_direction


## Rebuilds **both** shared fields: one breadth-first sweep outward from the Nest, and one
## outward from every Machine standing in the Factory.
##
## Two sweeps rather than one because there are two destinations a Wave can want — a Crawler
## swarms the Nest and a Breaker hunts the Factory (GLOSSARY.md) — and because a field is the
## right structure for both for the same reason it was the right structure for one. O(map)
## per destination once, amortised across every Enemy alive, against O(Enemies x Machines)
## every tick for "walk at the nearest Machine" and a path to re-find every time one falls.
## One pass over the obstructions serves both, so the marking is not paid twice.
##
## Both are rebuilt together under one `_flowfield_stale` flag: they are pure functions of
## the Map and the obstructions standing on it, and nothing can invalidate one without
## invalidating the other — a Machine built or destroyed is simultaneously a new obstruction
## and a new seed.
func _rebuild_flowfield() -> void:
	_mark_obstructions()

	var to_the_nest: Array = _sweep(_nest_seed_cells())
	_flow_direction = to_the_nest[0]
	_flow_distance = to_the_nest[1]

	var to_the_factory: Array = _sweep(_machine_seed_cells())
	_machine_flow_direction = to_the_factory[0]
	_machine_flow_distance = to_the_factory[1]

	_flowfield_stale = false


## One breadth-first sweep outward from a set of seed cells, returning `[direction, distance]`.
##
## Breadth first over four-connected tiles, so the distance it records is the exact number of
## tiles a walk to the nearest seed takes and no heuristic is involved. The direction stored
## on a tile is the way *back* towards whichever tile reached it first, and neighbours are
## pushed in `WorldGrid.DIRECTION_STEPS` index order out of a FIFO queue, so which tile gets
## there first is fixed by the grid's own direction order rather than by anything that
## happened during the Run: two clients build the identical field, down to which way a tile
## equidistant from two routes points.
##
## Obstructions are skipped rather than entered, which is what makes a Wall a Wall: the sweep
## flows around it, the tiles behind it get a longer distance or none at all, and every Enemy
## on the Map inherits the new route on the tick the field is rebuilt.
##
## A seed may itself be an obstruction — every Machine tile is one — so the sweep starts *on*
## the seeds at distance 0 and only the expansion checks for a block. That is how a tile
## beside a Machine comes to point at it while nothing routes through it, and it is the same
## arrangement the Nest has always had.
##
## Returns the two arrays rather than writing into members because a `PackedInt64Array`
## argument is a value in GDScript: a sweep that took one to fill would fill a copy.
func _sweep(seeds: PackedInt64Array) -> Array:
	var direction_out: PackedInt64Array = PackedInt64Array()
	direction_out.resize(FIELD_TILES)
	direction_out.fill(-1)
	var distance: PackedInt64Array = PackedInt64Array()
	distance.resize(FIELD_TILES)
	distance.fill(-1)

	var queue: PackedInt64Array = PackedInt64Array()
	for position: int in range(seeds.size()):
		var seed_cell: int = seeds[position]
		if seed_cell == -1 or distance[seed_cell] != -1:
			continue
		distance[seed_cell] = 0
		queue.append(seed_cell)

	var head: int = 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		@warning_ignore("integer_division")
		var row: int = cell / FIELD_WIDTH_TILES
		var reached_in: int = distance[cell] + 1
		for direction: int in range(WorldGrid.DIRECTION_COUNT):
			var offset: int = FIELD_STEPS[direction]
			var neighbour: int = cell + offset
			if neighbour < 0 or neighbour >= FIELD_TILES:
				continue
			# A step along x must not wrap off one edge of the Map onto the other.
			@warning_ignore("integer_division")
			if absi(offset) == 1 and neighbour / FIELD_WIDTH_TILES != row:
				continue
			if distance[neighbour] != -1 or _flow_blocked[neighbour] != 0:
				continue
			distance[neighbour] = reached_in
			# The neighbour's way out is back the way this step came.
			direction_out[neighbour] = WorldGrid.wrap_rotation(direction + 2)
			queue.append(neighbour)

	return [direction_out, distance]


## Every cell of the Nest's footprint, which is what the Crawlers' field is seeded on.
##
## The whole footprint because the destination is a 4x4 building and not a point: an Enemy
## heading for its near edge must not be routed to its anchor.
func _nest_seed_cells() -> PackedInt64Array:
	var cells: PackedInt64Array = PackedInt64Array()
	var size: Vector2i = query_nest_footprint()
	var anchor: Vector3i = query_nest_tile()
	for offset_x: int in range(size.x):
		for offset_z: int in range(size.y):
			cells.append(
				_field_index(Vector3i(anchor.x + offset_x, anchor.y, anchor.z + offset_z))
			)
	return cells


## Every cell every Machine's footprint covers, which is what the Breakers' field is seeded
## on. Walked in Machine index order — construction order, and therefore the same on every
## client — though the order cannot reach the field anyway: a seed is a seed at distance 0.
func _machine_seed_cells() -> PackedInt64Array:
	var cells: PackedInt64Array = PackedInt64Array()
	for index: int in range(query_machine_count()):
		var size: Vector2i = _machine_size(index)
		if size == Vector2i.ZERO:
			continue
		var origin: Vector3i = query_machine_tile(index)
		for offset_x: int in range(size.x):
			for offset_z: int in range(size.y):
				cells.append(
					_field_index(Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z))
				)
	return cells


## Paints every tile an Enemy cannot walk through.
##
## Machines obstruct: a Factory is a maze, and that is what makes laying one out a
## defensive decision rather than decoration. **Walls obstruct too** — that is the whole
## reason to build one — and they are one more loop here and nothing else, because this is
## the single definition of the obstruction set and `query_tile_obstructs_enemies` reads what
## it paints rather than asking the question a second way. Belts do not obstruct — a Crawler
## crawls over a conveyor — and neither do Nodes, which are ground.
##
## Both loops walk the *structures* and paint their tiles rather than asking each of the
## 16641 tiles what is standing on it: that is O(Machines + Walls) against
## O(tiles x (Machines + Walls)), and at this Map's size the second is a visible hitch every
## time a player places something.
##
## The Nest itself is deliberately not painted: it is the destination, seeded at distance
## zero, so a sweep that treated it as solid would have nowhere to start. A Machine *is*
## painted and is seeded as well, which is what lets the Breakers' field point at the
## Factory without routing through it.
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

	# One more loop, and that is the whole of what a Wall adds to pathing.
	for index: int in range(query_wall_count()):
		var wall_cell: int = _field_index(query_wall_tile(index))
		if wall_cell != -1:
			_flow_blocked[wall_cell] = 1


## Whether a tile stops an Enemy walking through it — what `_mark_obstructions` painted,
## read back for one tile. A tile the field does not cover obstructs nothing: it is not
## ground an Enemy could be walking on in the first place.
func _tile_obstructs_enemies(tile: Vector3i) -> bool:
	_flowfield()
	return _tile_is_blocked(tile)


## What `_mark_obstructions` painted on one tile, **without forcing a rebuild**. The inner
## half of `_tile_obstructs_enemies`, separated because the Enemy tick must not rebuild a
## field part-way through its own loop: it holds a snapshot of both fields for the whole tick
## (see `_enemies`), and a question asked mid-loop that rebuilt them would make the tick
## quadratic in the number of Enemies.
func _tile_is_blocked(tile: Vector3i) -> bool:
	var cell: int = _field_index(tile)
	if cell == -1 or cell >= _flow_blocked.size():
		return false
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


# ── Standing on the Factory ───────────────────────────────────────────────────
#
# What a player collides with, and all of it in fixed-point integers inside the Simulation
# (#30). It cannot be the engine's physics: that is float-based, so a player's position
# would depend on a solver rather than on the recorded inputs, two clients would part
# company on the first wall, and every replay fixture in the suite would become a lie.
#
# The good news is that it does not need to be general 3D collision. Everything is
# axis-aligned and grid-anchored, so this is box tests against a height per tile — and
# because nothing overhangs, the only two questions are "how high is the floor here" and
# "is that tile too tall to walk into".

## How high the Factory stands on one tile, in fixed-point metres, rebuilding the field if a
## structure has moved since it was last asked.
func _solid_heights() -> PackedInt64Array:
	if _solid_height_stale or _solid_height.size() != FIELD_TILES:
		_rebuild_solid_heights()
	return _solid_height


## Repaints the height of the Factory on every ground tile.
##
## One pass per kind of structure, each painting the *taller* of what is there and what it
## stands at, so a Belt laid against a Machine does not shorten it. What is solid is exactly
## the list the ticket names: Machines at the height their row declares, Walls at
## `wall.height_metres`, Belts at `belt.deck_height_metres`, and the Nest as its two
## quantised terraces.
##
## **A Breach and a Node are deliberately not solid.** A Node is ground a Miner stands on
## and a Breach is a hole Enemies come out of; neither is a building, and making either
## solid would change where a Factory can be laid out rather than what a player can stand
## on. A Hive is left alone for the same reason from the other side: it is the thing a
## sortie goes out to kill, and walling the player out of it would change that fight.
func _rebuild_solid_heights() -> void:
	_solid_height.resize(FIELD_TILES)
	_solid_height.fill(0)

	for index: int in range(query_machine_count()):
		var size: Vector2i = _machine_size(index)
		if size == Vector2i.ZERO:
			continue
		var height: int = _machine_height(index)
		var origin: Vector3i = query_machine_tile(index)
		for offset_x: int in range(size.x):
			for offset_z: int in range(size.y):
				_raise_solid(
					Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z), height
				)

	for index: int in range(query_wall_count()):
		_raise_solid(query_wall_tile(index), _definitions.wall_height)

	# A Belt is painted tile by tile along its run, which is the one structure here whose
	# footprint is a line rather than a rectangle.
	for index: int in range(query_belt_count()):
		var step: Vector3i = WorldGrid.direction_step(_belt_direction[index])
		var tile: Vector3i = _belt_entry_tile(index)
		for along: int in range(_belt_tiles[index]):
			_raise_solid(tile, _definitions.belt_deck_height)
			tile += step

	_paint_the_nest()
	_solid_height_stale = false


## Paints the Nest's stepped ziggurat: the crown on its inner tiles and the terrace on the
## ring around them.
##
## **Two terraces because the grid has room for two.** The body is three raked tiers of art
## over a 4x4 footprint, and a 4x4 has exactly one ring and one middle — so quantising it
## honestly gives the ring the first tier's head and the middle the full height. Anything
## finer would mean a collision grid finer than the build grid, which is a bigger change
## than this mechanic is worth and would buy a climb the jump cannot make anyway.
func _paint_the_nest() -> void:
	var origin: Vector3i = query_nest_tile()
	var size: Vector2i = query_nest_footprint()
	for offset_x: int in range(size.x):
		for offset_z: int in range(size.y):
			var on_the_ring: bool = (
				offset_x == 0
				or offset_z == 0
				or offset_x == size.x - 1
				or offset_z == size.y - 1
			)
			_raise_solid(
				Vector3i(origin.x + offset_x, origin.y, origin.z + offset_z),
				_definitions.nest_terrace_height if on_the_ring else _definitions.nest_height
			)


## Raises one tile's solid height to `height` if it is not already at least that tall.
## Taller wins, so the order the structures are painted in cannot reach the result.
func _raise_solid(tile: Vector3i, height: int) -> void:
	var cell: int = _field_index(tile)
	if cell == -1:
		return
	if height > _solid_height[cell]:
		_solid_height[cell] = height


## How tall a Machine's housing stands, in fixed-point metres, off its own row. Read rather
## than stored, so a hot-reload that changes the column lands on the Factory already
## standing — the arrangement `_machine_max_health` has.
func _machine_height(index: int) -> int:
	if not _is_machine(index):
		return 0
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return 0 if definition == null else definition.height


## How high the Factory stands on one tile, in fixed-point metres, **without forcing a
## rebuild** — the inner half of every question below, separated for the reason
## `_tile_is_blocked` is: a loop that asked and rebuilt mid-way would be quadratic.
func _solid_height_at(tile: Vector3i) -> int:
	var cell: int = _field_index(tile)
	if cell == -1 or cell >= _solid_height.size():
		return 0
	return _solid_height[cell]


## The highest surface under a player's box that they could be standing on, in fixed-point
## metres: the tallest tile they overlap whose top is no higher than `reach`.
##
## `reach` is their feet plus `player.step_up_height_metres`, so this one function answers
## both "what am I standing on" and "what would I step up onto". Bare ground is 0, which
## every player is always standing on somewhere, so there is no empty answer.
func _support_height(x: int, z: int, reach: int) -> int:
	var radius: int = _definitions.player_collision_radius
	var low: Vector3i = WorldGrid.tile_at_metres(x - radius, z - radius)
	var high: Vector3i = WorldGrid.tile_at_metres(x + radius, z + radius)
	var support: int = 0
	for tile_x: int in range(low.x, high.x + 1):
		for tile_z: int in range(low.z, high.z + 1):
			var height: int = _solid_height_at(
				Vector3i(tile_x, WorldGrid.GROUND_LAYER, tile_z)
			)
			if height <= reach and height > support:
				support = height
	return support


## The tallest tile under a player's box that stands above `reach`, or -1 when none does.
##
## Everything above a player's step-up is a wall to them, so this is what refuses a
## horizontal move — and after the move it is also how "am I inside something" is asked,
## because the only way to overlap a tile this tall is for it to have arrived around you.
func _obstruction_height(x: int, z: int, reach: int) -> int:
	var radius: int = _definitions.player_collision_radius
	var low: Vector3i = WorldGrid.tile_at_metres(x - radius, z - radius)
	var high: Vector3i = WorldGrid.tile_at_metres(x + radius, z + radius)
	var tallest: int = -1
	for tile_x: int in range(low.x, high.x + 1):
		for tile_z: int in range(low.z, high.z + 1):
			var height: int = _solid_height_at(
				Vector3i(tile_x, WorldGrid.GROUND_LAYER, tile_z)
			)
			if height > reach and height > tallest:
				tallest = height
	return tallest


## Whether a player has both feet on something.
##
## **"On the ground" became "on a surface" the moment the Factory became solid**, and this is
## the one place that is decided: standing on a Smelter roof is standing, so it accelerates,
## bobs and re-arms a jump exactly as standing on the Map does. Three things branch on it —
## the four accelerations, the stride and the bob — and before #30 all three asked whether
## `_player_y` was zero, which on a roof is the wrong question.
func _is_on_their_feet(player_id: int) -> bool:
	if _player_velocity_y[player_id] != 0:
		return false
	_solid_heights()
	return _player_y[player_id] == _support_height(
		_player_x[player_id], _player_z[player_id], _step_reach(player_id)
	)


## How far a player may reach up from where their feet are, in fixed-point metres. One
## number, read in both halves of the resolution, so what stops a move and what a move
## climbs onto can never disagree.
func _step_reach(player_id: int) -> int:
	return _player_y[player_id] + _definitions.player_step_up_height


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
	# Where a player is vertically, and the arc they are on. A player in the air is in a
	# different state from one standing on the same tile, so a jump that did not reach the
	# hash would be a jump the determinism harness could not see diverge.
	hasher.feed_ints(_player_y)
	hasher.feed_ints(_player_velocity_y)
	hasher.feed_ints(_player_jump_armed)
	hasher.feed_ints(_player_landing_tick)
	hasher.feed_ints(_player_landing_speed)
	hasher.feed_ints(_player_sprint_ticks)
	hasher.feed_ints(_player_step_phase)
	# What is in each player's hands. Hashed because a recorded replay has to reproduce a
	# swap — the clicks after one mean something different otherwise — and not because
	# anything consults it for permission. See `_player_build_mode`.
	hasher.feed_ints(_player_build_mode)
	hasher.feed_ints(_player_mode_since_tick)
	# Which tool is out, for the reason the mode is: a replay has to reproduce the swap, or
	# every drag after it means something different.
	hasher.feed_ints(_player_build_tool)
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
	# And what the Nest has banked past that bill, which is what the next tick will let a
	# player withdraw and spend. Sorted by Item id, so the hash is a property of what is in
	# the store rather than of the order it arrived in.
	hasher.feed_int(_nest_store_items.size())
	for slot: int in range(_nest_store_items.size()):
		hasher.feed_text(_nest_store_items[slot])
		hasher.feed_int(_nest_store_counts[slot])
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
	# Which Enemies have broken ranks. Hashed because it decides which of the two fields an
	# Enemy steers by from here on, and therefore which Machine falls next.
	hasher.feed_ints(_enemy_broke_ranks)
	# Which way every Enemy is facing. Hashed because it decides how much damage the *next*
	# hit does: a Siege Hulk's armour is a function of this and of where the shooter stands, so
	# two clients that disagreed about it would disagree about how long the boss lives.
	hasher.feed_ints(_enemy_face_x)
	hasher.feed_ints(_enemy_face_z)
	hasher.feed_int(_next_enemy_serial)
	# The Hives and what is left of each. Hashed because they decide the rate at which the Nest
	# sheds Heat, and therefore when every subsequent Wave arrives: two Runs that have cleared a
	# different number of them are not in the same state even if their Heat reads the same.
	hasher.feed_ints(_hive_tile_x)
	hasher.feed_ints(_hive_tile_y)
	hasher.feed_ints(_hive_tile_z)
	hasher.feed_ints(_hive_health)
	# Every shell in the air, in the order they were fired. A shell is damage that has already
	# been decided and has not landed yet, so a Run saved mid-bombardment has to restore the
	# marker a player is running out of rather than forget it.
	hasher.feed_ints(_shell_x)
	hasher.feed_ints(_shell_z)
	hasher.feed_ints(_shell_ticks_left)
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
	# What is left of every Machine. The array that decides whether a Factory still exists,
	# so a divergence in it is a divergence about what the Factory *is*.
	hasher.feed_ints(_machine_health)
	# What every Turret is shooting at, and when it last fired. The serial rather than an
	# index, which is the whole point of holding one: a hash over indices would agree between
	# two clients that are aimed at different Crawlers.
	hasher.feed_ints(_turret_target_serial)
	hasher.feed_ints(_turret_last_shot_tick)
	# What every Silo has banked, what is in its tube, and when a temporary Machine goes. All
	# of it decides what a later tick can do — a Silo one Charge short of a load is in a
	# different state from one that has just been loaded, and a Sentry with a second left is in
	# a different state from one with forty. The loaded Stratagem goes in as an **id** for the
	# reason `_machine_id` does: a hash over indices would agree between two clients whose
	# Stratagem table sorted differently.
	hasher.feed_ints(_silo_charges)
	hasher.feed_ints(_silo_loaded_charges)
	for stratagem_id: String in _silo_loaded_stratagem:
		hasher.feed_text(stratagem_id)
	hasher.feed_ints(_machine_expires_tick)
	# Which branch had first claim on each Machine's output last. Hashed because it decides
	# which of two Belts off one Machine runs next, and therefore which consumer is fed.
	hasher.feed_ints(_machine_port_cursor)
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
	# The Walls, and what is left of each. Where they stand shapes the fields every Enemy
	# steers by — which are derived and therefore not hashed — so this is the hashed cause
	# behind an unhashed effect, exactly as the Machine arrays are.
	hasher.feed_ints(_wall_tile_x)
	hasher.feed_ints(_wall_tile_y)
	hasher.feed_ints(_wall_tile_z)
	hasher.feed_ints(_wall_health)
	# Each player's unspent fraction of a hit point of hand repair. Authoritative state for
	# the reason the Power grid's credit is: it is what makes a rate exact rather than
	# approximately right, and a divergence in it is a divergence in how fast a Factory comes
	# back. The *held* half of the wrench intent is deliberately absent, for the reason the
	# walking throttle is: `_repair` consumes and clears it, so it is zero here every time.
	hasher.feed_ints(_player_repair_credit)
	# What is left of every player, and whether they are on their feet. The arrays that
	# decide whether a player is in the fight at all, so a divergence in any of them is a
	# divergence about who is playing. `_player_life_since_tick` is hashed with the state it
	# belongs to because the two together *are* the clock: how long somebody has been
	# bleeding out is arithmetic over them rather than a third number.
	hasher.feed_ints(_player_health)
	hasher.feed_ints(_player_life_state)
	hasher.feed_ints(_player_life_since_tick)
	hasher.feed_ints(_player_revive_credit)
	# The Gear in every player's hands, and what is fitted to it. Ids rather than indices,
	# for the reason `_player_selected_machine` holds an id: a hash over indices would agree
	# between two clients whose Gear table sorted differently.
	for gear_id: String in _player_weapon:
		hasher.feed_text(gear_id)
	for player_id: int in range(query_player_count()):
		var fitted: PackedStringArray = _player_component_ids[player_id]
		hasher.feed_int(fitted.size())
		for gear_id: String in fitted:
			hasher.feed_text(gear_id)
	# The weapon's own clock and the recoil it has not shed. Both decide what the *next*
	# tick's shot does — the cooldown decides whether there is one, the kick decides where
	# it goes — so neither may sit outside the hash. The last-shot tick is here because a
	# saved Run has to restore the muzzle flash it was in the middle of rather than invent
	# one. The **held** half of the trigger is deliberately absent, for the reason the
	# walking throttle is: `_fight` consumes and clears it, so it is zero here every time.
	hasher.feed_ints(_player_fire_cooldown)
	hasher.feed_ints(_player_last_shot_tick)
	hasher.feed_ints(_player_view_kick_turns)
	# The dial each player is carrying, and the Painting any of them is channelling. The dial
	# because it is what a `LOAD_SILO` commits and therefore decides what the next tick can
	# do; the Painting because a channel half-served is a channel, and because the Charges it
	# is holding have already left the Silo — a Run that diverged on which of those two places
	# the Charges were in would be a Run that disagreed about whether it still had artillery.
	# Ids rather than indices, for the reason `_player_selected_machine` holds an id. The
	# **held** half of the Painting intent is deliberately absent, like the walking throttle
	# and the trigger: `_paint` consumes and clears it, so it is zero here every time.
	for stratagem_id: String in _player_dial_stratagem:
		hasher.feed_text(stratagem_id)
	hasher.feed_ints(_player_dial_charges)
	for stratagem_id: String in _player_paint_stratagem:
		hasher.feed_text(stratagem_id)
	hasher.feed_ints(_player_paint_charges)
	hasher.feed_ints(_player_paint_target_x)
	hasher.feed_ints(_player_paint_target_y)
	hasher.feed_ints(_player_paint_target_z)
	hasher.feed_ints(_player_paint_ticks)
	# And what interruption has cost. Hashed because it is a fact about the Run that a player
	# reads and a fixture asserts on, and because a Charge lost on one client and not another
	# is the loudest possible divergence.
	hasher.feed_ints(_player_paint_interrupted_tick)
	hasher.feed_ints(_player_charges_wasted)
	hasher.feed_ints(_player_stratagems_fired)
	hasher.feed_ints(_player_charges_fired)
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
## How high a player is off the ground, in fixed-point metres. Zero with both feet down.
func query_player_height_metres(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_y[player_id]


## How fast a player is rising (positive) or falling (negative), in fixed-point metres per
## second.
func query_player_vertical_velocity(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_velocity_y[player_id]


## Whether a player has both feet on the ground. The single fact the four accelerations and
## the stride both branch on, so nothing infers it a second way.
func query_player_is_grounded(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _is_on_their_feet(player_id)


## How far into the sprint gait a player is, in [0, Fixed.ONE]. For a HUD, and for the
## renderer's own sway — the speed, the field of view and the bob already have it.
func query_player_sprint_blend(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _sprint_blend(player_id)


# ── What the camera does about all of that ────────────────────────────────────
#
# **Five projections the renderer reads and the Simulation never does.** That separation is
# the load-bearing part: `query_player_camera_height_metres` and
# `query_player_camera_pitch_turns` are the *aim* — a shot leaves along them and a
# hologram snaps to the tile they point at — and these are the cosmetic response laid on
# top. Folding a bob into the aim would mean a footfall moved where a round went and which
# tile a Build Gun was hovering, which is a bug wearing polish as a disguise.
#
# They are derived from state the Simulation already hashes (velocity, the step phase, the
# landing tick, the sprint ramp), so all of it replays exactly and all of its sizes are
# hot-reloadable tuning. Every one of them returns 0 when its tuning key is 0.

## How far a player's view has risen or fallen within their current stride, in fixed-point
## metres. Positive is up.
##
## Two dips per stride, because a walk falls on each foot. Scaled by how fast the player is
## actually moving and by how far into the sprint gait they are, so it fades in and out with
## the gait rather than switching on — and a player in mid-air has no stride at all.
func query_player_view_bob_vertical_metres(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.mul(
		Fixed.mul(_definitions.player_bob_vertical, _bob_strength(player_id)),
		Fixed.sin_turns(_player_step_phase[player_id] * 2)
	)


## How far a player's view has swung side to side within their current stride, in
## fixed-point metres. Positive is to their right, and it runs at *half* the vertical
## frequency because a walk sways once per pair of steps.
func query_player_view_bob_lateral_metres(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.mul(
		Fixed.mul(_definitions.player_bob_lateral, _bob_strength(player_id)),
		Fixed.sin_turns(_player_step_phase[player_id])
	)


## How far a landing has pushed a player's view down and not yet let it back up, in
## fixed-point metres. A positive magnitude: the renderer subtracts it.
##
## **Scaled by how hard they actually hit**, against
## `player.land_dip_reference_speed_metres_per_second`, so stepping off a kerb barely
## registers and a long drop does. It eases out with `Fixed.smoothstep_fixed` over
## `player.land_dip_seconds`, which is what makes a landing *settle* rather than snap back.
func query_player_view_dip_metres(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	var span: int = _seconds_in_ticks(_definitions.player_land_dip_seconds)
	if span == 0 or _definitions.player_land_dip_metres == 0:
		return 0
	var since: int = _ticks_since_landing(player_id)
	if since >= span:
		return 0
	var strength: int = Fixed.clamp_fixed(
		Fixed.div(
			_player_landing_speed[player_id], _definitions.player_land_dip_reference_speed
		),
		0,
		Fixed.ONE
	)
	var left: int = Fixed.ONE - Fixed.smoothstep_fixed(
		Fixed.div(Fixed.from_int(since), Fixed.from_int(span))
	)
	return Fixed.mul(Fixed.mul(_definitions.player_land_dip_metres, strength), left)


## How far a player's view is banked, in fixed-point turns, from the sideways travel they
## are carrying. Positive banks to their right.
##
## Lean under acceleration is the third of the three camera cues and the cheapest: it needs
## no state at all, because the sideways component of a velocity that is already hashed is
## exactly the quantity a body leans against.
func query_player_view_roll_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _degrees_to_turns(
		Fixed.mul(_definitions.player_lean_roll_degrees, _lateral_speed(player_id))
	)


## How far a player's view has pitched from leaning into their own forward travel, in
## fixed-point turns. Negative is nose-down, which is what running forward does.
##
## **Added by the renderer and not by `query_player_camera_pitch_turns`**, for the reason
## the bob is separate: this must not move where a round goes. Contrast the recoil kick,
## which is *in* that query precisely because it does.
func query_player_view_lean_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return -_degrees_to_turns(
		Fixed.mul(_definitions.player_lean_pitch_degrees, _forward_speed(player_id))
	)


## How far a player's view has fallen because they were killed or Downed, in fixed-point
## metres. A positive magnitude: the renderer subtracts it, exactly as it subtracts the
## landing dip.
##
## **A renderer-only projection rather than part of `query_player_camera_height_metres`,
## and that is #54's one real decision.** The precedent cuts both ways and the rule it is
## decided by is the quantity rather than the circumstance: the jump is *in* the aim because
## how high a player is standing is a fact a round has to honour, and the bob, the dip and
## the lean are out of it because a footfall must not move where a round goes. A body going
## limp is the second kind.
##
## The circumstantial argument — a dead player aims at nothing, so folding the collapse into
## the aim would be harmless today — is true and is the wrong test. It is true only because
## `_act_refusal` currently refuses every intent of a player who is not on their feet, which
## is a gate that could be narrowed: a **Downed** player in co-op is alive, revivable, still
## a target, and the one plausible future in which they are given something to do is one in
## which a collapse folded into the aim would quietly be pointing their rounds at the dirt.
## A projection cannot develop that bug. See `query_player_view_bob_vertical_metres` for the
## five this joins.
func query_player_view_collapse_metres(player_id: int) -> int:
	return Fixed.mul(_collapse_drop_metres(), query_player_collapse_blend(player_id))


## How far a player's view has banked over as it fell, in fixed-point turns. Positive banks
## to their right, which is the sign `query_player_view_roll_turns` uses.
##
## One direction for everybody rather than a side chosen per player: there is nothing in the
## Simulation that says which way a body happens to topple, and inventing one would mean
## either an RNG draw — which would cost the Run a draw it cannot afford to spend on
## presentation — or a new piece of hashed state for a fact nobody can act on.
func query_player_view_collapse_roll_turns(player_id: int) -> int:
	return Fixed.mul(
		_degrees_to_turns(_definitions.player_collapse_roll_degrees),
		query_player_collapse_blend(player_id)
	)


## How far through the collapse a player is, in [0, Fixed.ONE]: 0 standing, Fixed.ONE in the
## posture a dead player ends up in, and the smaller resting value in between for a Downed
## one. Eased with `Fixed.smoothstep_fixed`, so a body settles rather than snapping flat.
##
## **The same number runs backwards when a player gets up**, which is the whole of #54's
## acknowledgement that a respawn happened: `_respawn` and a revive both set
## `_player_life_since_tick`, so a player who is `LIFE_ALIVE` and has been for less than the
## gesture's length is one rising off the deck. It adds no state and no tuning key, and it
## cannot lengthen the wait, because the player is alive and in control throughout it.
##
## Two details in that, both deliberate. A Run **opens on your feet** rather than getting up
## off the floor, and the fact that says so is `_player_life_since_tick` being 0 at
## construction — a player cannot have got up on tick 0 because nothing had happened to them
## yet. And a *revived* player rises from the dead posture rather than from the Downed one
## they were actually in, because telling those apart would mean remembering a state that has
## ended; it is half a metre over half a second on a gesture nobody measures, and the
## alternative is hashed state for a cosmetic difference.
##
## **The blend is the shape and the two queries above are its sizes**, which is the
## arrangement `query_player_sprint_blend` already has beside the field of view and the bob:
## the renderer reads whichever unit it needs and the tuned magnitudes stay in the Simulation
## where they are hot-reloadable.
func query_player_collapse_blend(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	var resting: int = _collapse_resting_blend(player_id)
	var span: int = _seconds_in_ticks(_definitions.player_collapse_seconds)
	var rising: bool = _player_life_state[player_id] == LIFE_ALIVE
	# A player who has always been alive is standing, not getting up. Nothing has happened to
	# them, so there is nothing to play backwards.
	if rising and _player_life_since_tick[player_id] <= 0:
		return 0
	if span <= 0:
		# A hard cut: 0 seconds means a body is simply down, and up again on the tick it
		# revives.
		return 0 if rising else resting
	var since: int = _tick - _player_life_since_tick[player_id]
	if since >= span:
		return 0 if rising else resting
	var eased: int = Fixed.smoothstep_fixed(
		Fixed.div(Fixed.from_int(since), Fixed.from_int(span))
	)
	return (Fixed.ONE - eased) if rising else Fixed.mul(resting, eased)


## How far the view has fallen once a collapse has finished, in fixed-point metres. The
## gesture's full size, and the divisor a Downed player's shallower fall is stated as a
## fraction of. Clamped to the eye height, because a view cannot fall through the floor it
## is standing on.
func _collapse_drop_metres() -> int:
	return clampi(_definitions.player_death_view_drop, 0, _definitions.player_eye_height)


## What a player's current life state settles the blend at, in [0, Fixed.ONE].
##
## Dead is the whole gesture by definition; Downed is however far its own posture is down the
## same fall, so **the roll comes out proportionally smaller for free** and a Downed player is
## distinguishable from a dead one by the view alone rather than only by a HUD line. That
## also makes `player.death_view_drop_metres` the one switch for the whole gesture: a drop
## of nothing is a fall of nothing to be a fraction of.
func _collapse_resting_blend(player_id: int) -> int:
	var full: int = _collapse_drop_metres()
	if full <= 0:
		return 0
	match _player_life_state[player_id]:
		LIFE_DEAD:
			return Fixed.ONE
		LIFE_DOWNED:
			return Fixed.clamp_fixed(
				Fixed.div(_definitions.player_downed_view_drop, full), 0, Fixed.ONE
			)
	return 0


## The camera's field of view in fixed-point degrees: the tuned figure, widened by the
## whole of `player.sprint_field_of_view_add_degrees` as the sprint gait comes in.
func query_player_field_of_view_degrees(player_id: int) -> int:
	if not _is_player(player_id):
		return _definitions.player_field_of_view_degrees
	return _definitions.player_field_of_view_degrees + Fixed.mul(
		_definitions.player_sprint_field_of_view_add_degrees, _sprint_blend(player_id)
	)


## How much of the bob applies right now, in [0, Fixed.ONE]: zero standing still, zero in
## the air, and rising with speed up to a little over one at a full sprint.
##
## Speed-driven rather than clamped at one, because `player.bob_sprint_multiplier` is how a
## sprint bobs harder than a walk — the third of the three gait cues.
func _bob_strength(player_id: int) -> int:
	if not _is_on_their_feet(player_id):
		return 0
	var speed: int = _length(_player_velocity_x[player_id], _player_velocity_z[player_id])
	var fraction: int = Fixed.clamp_fixed(
		Fixed.div(speed, _definitions.player_walk_speed), 0, Fixed.ONE
	)
	return Fixed.mul(
		fraction,
		Fixed.lerp_fixed(
			Fixed.ONE, _definitions.player_bob_sprint_multiplier, _sprint_blend(player_id)
		)
	)


## How fast a player is travelling to their own right, in fixed-point metres per second.
## Negative is to their left. The player's frame, from the yaw the Simulation is holding —
## the same basis `_wanted_velocity` builds a throttle in, so there is one convention.
func _lateral_speed(player_id: int) -> int:
	var yaw: int = _player_yaw[player_id]
	return (
		Fixed.mul(_player_velocity_x[player_id], Fixed.cos_turns(yaw))
		- Fixed.mul(_player_velocity_z[player_id], Fixed.sin_turns(yaw))
	)


## How fast a player is travelling forwards, in fixed-point metres per second. Negative is
## backwards.
func _forward_speed(player_id: int) -> int:
	var yaw: int = _player_yaw[player_id]
	return (
		Fixed.mul(_player_velocity_x[player_id], -Fixed.sin_turns(yaw))
		+ Fixed.mul(_player_velocity_z[player_id], -Fixed.cos_turns(yaw))
	)


## An angle in fixed-point degrees as fixed-point turns. Degrees in the tuning file because
## that is how a human reasons about an angle; turns everywhere else because radians need
## PI and PI is a float.
func _degrees_to_turns(degrees: int) -> int:
	return Fixed.div(degrees, Fixed.from_int(DEGREES_PER_TURN))


# ── What is in a player's hands ───────────────────────────────────────────────

## Whether a player has the Build Gun out rather than their weapon.
##
## **Read by `game/player_controller.gd` to decide what a left click means, and by nothing
## in the Simulation.** Building is never gated and neither is firing; this is input
## routing and a holster animation, not a restriction. See `_player_build_mode`.
func query_player_is_in_build_mode(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_build_mode[player_id] != 0


## Which tool is on a player's Build Gun: `BUILD_TOOL_MACHINE` or `BUILD_TOOL_BELT`.
##
## **Read by `game/player_controller.gd` to decide what the primary button means, and by
## nothing in the Simulation.** The Machine tool for a player this Run does not have, so a
## caller that asks about nobody is told about the ordinary case rather than crashing.
func query_player_build_tool(player_id: int) -> int:
	if not _is_player(player_id):
		return BUILD_TOOL_MACHINE
	return _player_build_tool[player_id]


## Whether a player has the Belt tool out — the one the preview and the HUD actually ask.
func query_player_is_laying_belt(player_id: int) -> bool:
	return query_player_build_tool(player_id) == BUILD_TOOL_BELT


## How far the thing in a player's hands is out of frame, in [0, Fixed.ONE] — 0 at rest, 1
## at the midpoint of a swap.
##
## One number for both halves of the swap, because a holster is symmetric: the old object
## goes down over the first half and the new one comes up over the second, and a renderer
## only needs to know how far out and which object (`query_player_held_is_build_gun`). Eased
## with `Fixed.smoothstep_fixed`, so a swap starts and finishes gently rather than
## snatching.
##
## **`game/` does not read this.** It landed before #28's view model did, and #28 brought
## `holster` and `draw` as first-class animation roles timed off the clip lengths of the
## model actually on screen — so `WorldView` hands the Build Gun's id to `WeaponViewmodel`
## and the shape of the swap is the animator's. This stays because it is the Simulation's own
## authoritative answer, hashable state behind it, pinned by `test_movement_weight.gd` and
## the only answer available to anything that is not that renderer — a co-op client's HUD, a
## replay viewer, a second camera.
func query_player_holster_blend(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	var span: int = _seconds_in_ticks(_definitions.player_holster_seconds)
	if span == 0 or _player_mode_since_tick[player_id] < 0:
		return 0
	var since: int = _tick - _player_mode_since_tick[player_id]
	if since < 0 or since >= span:
		return 0
	var through: int = Fixed.div(Fixed.from_int(since), Fixed.from_int(span))
	# A triangle: up to full at the midpoint, back down to nothing at the end.
	return Fixed.smoothstep_fixed(Fixed.ONE - absi(Fixed.mul(Fixed.from_int(2), through) - Fixed.ONE))


## Which object is actually *in frame* right now — which is not the same question as which
## mode the player is in, for the first half of a swap.
##
## The mode changes on the tick the key is pressed, because nothing is gated; the object in
## frame is still the old one until the swap reaches its midpoint and the new one starts
## coming up, which is what makes a holster read as putting one thing away and drawing
## another rather than as one thing morphing.
##
## **`game/` does not read this either** — see `query_player_holster_blend` for why, and for
## why it is still here.
func query_player_held_is_build_gun(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	var wanted: bool = _player_build_mode[player_id] != 0
	var span: int = _seconds_in_ticks(_definitions.player_holster_seconds)
	if span == 0 or _player_mode_since_tick[player_id] < 0:
		return wanted
	var since: int = _tick - _player_mode_since_tick[player_id]
	if since < 0 or since * 2 >= span:
		return wanted
	return not wanted


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
	# The jump is in here and the bob is not, and that is the whole of the split: how high
	# a player is standing is a fact about the world that the aim must honour, where a bob
	# is a cosmetic response the renderer lays on top. See `query_player_view_bob_*`.
	return Fixed.lerp_fixed(
		_definitions.player_eye_height + _player_y[player_id],
		_definitions.survey_height,
		_survey_blend(player_id)
	)


## Where a player's camera is pointing, in fixed-point turns from level. The player's
## own pitch on foot — **recoil included** — tilted down to the tuned Survey View angle as
## the camera rises.
##
## The kick is in here rather than applied by the renderer because it is in the aim: what
## the camera shows and where the next round goes are one number (`_aim_pitch_turns`), and
## a view that kicked on its own would be lying about the second.
func query_player_camera_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return Fixed.lerp_fixed(
		_aim_pitch_turns(player_id), -_survey_pitch_turns(), _survey_blend(player_id)
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


## The unit vector a player is facing along, on the horizontal plane.
##
## The yaw stated as a direction rather than as an angle, and it is `_facing` — the one
## authority on what a yaw points along, shared with the throttle `_wanted_velocity`
## rotates. Handed out because the yaw *convention* is the Simulation's and a caller that
## rebuilt the basis out of `query_player_yaw_turns` would own a second copy of it: the
## mistake `_lateral_speed` and `_forward_speed` exist to avoid on the inside.
##
## #52's objective hint is the caller. "The ore is to your right" is a sentence about the
## player's own frame, and the geometry of a vector handed over is `game/`'s business in the
## way `WorldView`'s `atan2` on a Siege Hulk's facing point is. A projection: nothing in the
## Simulation reads it back.
func query_player_facing(player_id: int) -> FixedVec2:
	if not _is_player(player_id):
		return FixedVec2.zero()
	return _facing(_player_yaw[player_id])


## How far from level a player is looking, in fixed-point turns. Positive is up, and
## the magnitude never exceeds `MAX_PITCH_TURNS`.
func query_player_pitch_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_pitch[player_id]


## How far from level a player is **aiming**, in fixed-point turns: their own pitch plus
## whatever recoil has not come back down. What `query_player_pitch_turns` reports is the
## pitch they asked for; this is the pitch the next round will take.
func query_player_aim_pitch_turns(player_id: int) -> int:
	return _aim_pitch_turns(player_id)


## How far recoil has pushed the view up and not yet let it back down, in fixed-point
## turns. For a HUD that wants to draw the crosshair bloom; the aim already has it.
func query_player_view_kick_turns(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_view_kick_turns[player_id]


# ── Gear, health and mortality ────────────────────────────────────────────────

## What is left of a player, in whole hit points, and what whole is.
func query_player_health(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_health[player_id]


func query_player_max_health(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _definitions.player_health


## Whether a player is on their feet. The predicate every refusal consults, exposed so the
## HUD and the renderer read the same answer the Simulation acts on.
func query_player_is_alive(player_id: int) -> bool:
	return _player_can_act(player_id)


## Whether a player is Downed — at zero health, immobilised, bleeding out, and revivable
## by a teammate (GLOSSARY.md). **Never true on a solo Run**: there is nobody to revive
## you, so a solo player at zero health dies.
func query_player_is_downed(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_life_state[player_id] == LIFE_DOWNED


## Whether a player is dead and waiting to come back at the Nest.
func query_player_is_dead(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_life_state[player_id] == LIFE_DEAD


## How many ticks a Downed player has left before they die, or 0 if they are not Downed.
## What the klaxon counts down, and what a teammate deciding whether to come is reading.
func query_player_downed_ticks_remaining(player_id: int) -> int:
	if not query_player_is_downed(player_id):
		return 0
	return maxi(_downed_ticks() - (_tick - _player_life_since_tick[player_id]), 0)


## How many ticks a dead player has left before they respawn, or 0 if they are not dead.
## **The whole of what death costs**, counted out where a player can watch it.
func query_player_respawn_ticks_remaining(player_id: int) -> int:
	if not query_player_is_dead(player_id):
		return 0
	return maxi(_respawn_ticks() - (_tick - _player_life_since_tick[player_id]), 0)


## Why a held revive would pick nobody up, or `Refusal.NONE`. A projection about a revive
## that has not happened, the same arrangement `query_build_refusal` has.
func query_revive_refusal(rescuer: int, target: int) -> int:
	return _revive_refusal(rescuer, target)


## The Gear id of the weapon frame in a player's hands.
func query_player_weapon(player_id: int) -> String:
	if not _is_player(player_id):
		return ""
	return _player_weapon[player_id]


## The Gear *index* of the weapon frame in a player's hands, or -1 when it names nothing
## in the current definition set — which a hot-reload that deleted the row can do.
##
## An index for the renderer's and the controller's benefit, derived on the way out, for
## the reason `query_player_selected_machine_index` is: the id is authoritative and the
## index is a convenience over the table as it stands right now.
func query_player_weapon_index(player_id: int) -> int:
	if not _is_player(player_id):
		return -1
	return _definitions.gear_index(_player_weapon[player_id])


## Whether what a player is holding swings rather than shoots. What the controller reads
## to decide whether to draw a wrench or a rifle, and nothing in the Simulation branches
## on it outside `_pull_the_trigger`.
func query_player_weapon_is_melee(player_id: int) -> bool:
	var weapon: GearDefinition = _weapon_of(player_id)
	return weapon != null and weapon.is_melee()


## The Gear id fitted into one of the frame's slots, or empty.
##
## The slot is named by index into the definition set's interned slots — the `kind` values
## `content/gear.csv` mentions other than `weapon` — which is the same index a
## `FIT_COMPONENT` intent carries.
func query_player_component(player_id: int, slot_index: int) -> String:
	var slot_id: String = _definitions.gear_slot_id(slot_index)
	if slot_id.is_empty():
		return ""
	for definition: GearDefinition in _fitted_components(player_id):
		if definition.slot_id() == slot_id:
			return definition.id
	return ""


## Every Gear id fitted to a player's frame, sorted. A copy, like every other query.
func query_player_components(player_id: int) -> PackedStringArray:
	if not _is_player(player_id):
		return PackedStringArray()
	var fitted: PackedStringArray = _player_component_ids[player_id]
	return fitted.duplicate()


## Whether a piece of Gear is available to a player this Run.
##
## Gear a Delivery tier names is locked until that tier is completed; Gear no tier names
## is open from tick 0. One authority — `Definitions.locks_gear` — exactly as
## `query_machine_is_unlocked` has one.
func query_gear_is_unlocked(gear_index: int) -> bool:
	var definition: GearDefinition = _definitions.gear_at(gear_index)
	if definition == null:
		return false
	if not _definitions.locks_gear(definition.id):
		return true
	return _unlocked_gear_ids.find(definition.id) != -1


## Why putting a weapon in a player's hands would be refused, or `Refusal.NONE`.
func query_equip_refusal(player_id: int, gear_index: int) -> int:
	return _equip_refusal(player_id, gear_index)


## Why fitting a component into a slot would be refused, or `Refusal.NONE`. A Gear index
## of -1 asks about emptying the slot.
func query_fit_refusal(player_id: int, slot_index: int, gear_index: int) -> int:
	return _fit_refusal(player_id, slot_index, gear_index)


## Why a held trigger would do nothing this tick, or `Refusal.NONE`. What the HUD reads to
## say `DRY`, and the same function `_fight` obeys, so the reason on screen and the reason
## nothing happened are one rule.
func query_fire_refusal(player_id: int) -> int:
	return _fire_refusal(player_id)


# What a player's weapon actually does, frame plus everything fitted. These five are the
# acceptance criterion "component combinations measurably change weapon behaviour" made
# observable: a test fits a barrel and reads the damage back, and so does a player.

func query_player_weapon_damage(player_id: int) -> int:
	return _weapon_damage(player_id)


func query_player_weapon_range_metres(player_id: int) -> int:
	return _weapon_range_metres(player_id)


## How far a shot may scatter, in fixed-point **degrees** — turns inside the Simulation,
## degrees on the way out, because degrees is what the file is written in and what a HUD
## would show.
func query_player_weapon_spread_degrees(player_id: int) -> int:
	return Fixed.mul(_weapon_spread_turns(player_id), Fixed.from_int(DEGREES_PER_TURN))


func query_player_weapon_interval_ticks(player_id: int) -> int:
	return _weapon_interval_ticks(player_id)


func query_player_weapon_ammunition_per_shot(player_id: int) -> int:
	return _weapon_ammunition_per_shot(player_id)


## The Item a player's weapon spends, or empty for a melee weapon. What the HUD counts the
## magazine in, read off the weapon rather than named anywhere in `game/`.
func query_player_weapon_ammunition_item(player_id: int) -> String:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null:
		return ""
	return weapon.ammunition_item


## How many rounds a player is carrying for the weapon in their hands, and how many shots
## that is. Zero for a melee weapon, which spends nothing.
func query_player_ammunition(player_id: int) -> int:
	var weapon: GearDefinition = _weapon_of(player_id)
	if weapon == null or not weapon.is_ranged():
		return 0
	return query_player_item(player_id, weapon.ammunition_item)


func query_player_shots_remaining(player_id: int) -> int:
	var per_shot: int = _weapon_ammunition_per_shot(player_id)
	if per_shot <= 0:
		return 0
	@warning_ignore("integer_division")
	return query_player_ammunition(player_id) / per_shot


## Ticks a player still has to wait before their weapon fires again.
func query_player_fire_cooldown_ticks(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_fire_cooldown[player_id]


## The tick a player last fired on, or -1 if they never have. What the renderer plays a
## muzzle flash and a Shoot take off — hashed state rather than something the view infers,
## so a saved Run restores the shot it was in the middle of.
func query_player_last_shot_tick(player_id: int) -> int:
	if not _is_player(player_id):
		return -1
	return _player_last_shot_tick[player_id]


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


## Whether a Machine's Recipe produces what a Node yields, Depth left out of it.
##
## **A projection about a Machine that may not exist yet**, the same category of thing
## `query_build_refusal` is: it answers about a `content/machines.csv` row and a Node
## rather than about anything standing, which is what lets the Build Gun ask it of the
## Machine on the gun before a click. Nothing in the Simulation reads it; the two callers
## are `BuildGun.placement`, which uses it to decide which Node a Miner should snap to,
## and the HUD that says why it would not.
##
## It is a query rather than something `game/` works out for itself because the answer is
## `_machine_has_its_inputs`' own answer, less the Depth clause — and a Build Gun that
## promised a Miner would produce where the Simulation would call it starved is exactly
## the two-copies-of-a-rule this project does not have anywhere else.
func query_node_yields_for(machine_index: int, node_index: int) -> bool:
	if not _is_node(node_index):
		return false
	var definition: MachineDefinition = _definitions.machine_at(machine_index)
	if definition == null or not definition.is_miner():
		return false
	var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
	if recipe == null:
		return false
	return _recipe_yields(recipe, _node_resource[node_index])


## Whether a Machine's tier reaches the Depth a Node sits at.
##
## The other half of the question above, kept apart from it because **a player reading a
## refusal wants to know which of the two is wrong** — ore this Miner does not mine and
## ore it cannot lift are different problems with different answers, and the second one
## is "build the next Miner up". The standing `GEAR_IS_LOCKED` has beside
## `CONTENT_IS_LOCKED`.
##
## `_miner_reaches` is the authority and this is its only other caller, so `max_depth`
## is still read in exactly one place.
func query_node_is_within_depth_of(machine_index: int, node_index: int) -> bool:
	if not _is_node(node_index):
		return false
	var definition: MachineDefinition = _definitions.machine_at(machine_index)
	if definition == null or not definition.is_miner():
		return false
	return _miner_reaches(definition, node_index)


## Whether any Miner this Run could build right now would actually work this Node.
##
## **Both halves of the question and the unlock set as well**, which is what makes it one
## answer rather than three and the reason it lives here. `query_node_yields_for` and
## `query_node_is_within_depth_of` each answer about *one* `content/machines.csv` row, which
## is the right shape for a Build Gun that is holding one; what a mark on the ground and an
## objective line both need is whether there is *anything* a player owns that could lift it,
## and the two must not disagree — a beacon drawn as reachable over a seam the hint will not
## point at is exactly the two-copies-of-a-rule #36's `query_belt_end_is_connected` exists to
## prevent.
##
## A statement about this Run and not about the content: a Depth 2 seam is out of reach at
## tick 0 and in reach the moment a tier pays for `miner_mk2`, with no number having moved.
## Nothing in the Simulation reads it back.
##
## Walked in definition index order, which is sorted by id — the order every other loop over
## the Machine table uses, so the answer is a property of the content rather than of the walk.
func query_node_is_workable_now(node_index: int) -> bool:
	if not _is_node(node_index):
		return false
	for index: int in range(_definitions.machine_count()):
		var definition: MachineDefinition = _definitions.machine_at(index)
		if definition == null or not definition.is_miner():
			continue
		if not _machine_is_unlocked(definition.id):
			continue
		if not _miner_reaches(definition, node_index):
			continue
		var recipe: RecipeDefinition = _definitions.recipe_at(definition.recipe_index)
		if recipe != null and _recipe_yields(recipe, _node_resource[node_index]):
			return true
	return false


## Whether a Miner is standing on this Node and actually extracting from it.
##
## **Covering is not working, and #52 is the ticket that cost.** `query_node_under_machine` is
## geometry — the Node a footprint covers — and covering is one of the three things a Miner
## needs: an iron Miner over coal mines the wrong thing and a Mk1 on a Depth 2 seam cannot lift
## it, and both of those cover a Node while accumulating nothing at all. So this is
## `query_machine_is_starved` pointed the other way round, which keeps the question on
## `_machine_has_its_inputs` — the one predicate behind what the grid bills, what advances and
## what a query calls starved — rather than on a list of cases somebody has to keep in step
## with it.
##
## Two callers and they must not disagree: `Objective`'s first step goes quiet on it, and the
## beacon `WorldView` hangs over unworked ore goes quiet on it. A mark that vanished over ore
## the hint still points at would be two opinions about one fact. Nothing in the Simulation
## reads it back.
func query_node_is_being_worked(node_index: int) -> bool:
	if not _is_node(node_index):
		return false
	for index: int in range(query_machine_count()):
		if query_node_under_machine(index) != node_index:
			continue
		if not query_machine_is_starved(index):
			return true
	return false


## Whether any Machine's footprint covers this Node.
##
## Geometry, and deliberately a weaker claim than `query_node_is_being_worked`: a Machine here
## may be mining this ore, mining the wrong thing, or not a Miner at all. What the two callers
## share is the consequence rather than the cause — **this is ground nothing more can be put
## on** — which is what both of them are actually asking. `Objective` will not send a player to
## a tile that is occupied, and `WorldView` takes its mark off one, because a mark over ground
## a player cannot build on is an invitation that cannot be accepted.
##
## Walked from the Machines rather than asked of each Node, which is `_mark_obstructions`'
## lesson: a Factory has fewer Machines than this question has callers per frame. Nothing in
## the Simulation reads it back.
func query_node_is_built_on(node_index: int) -> bool:
	if not _is_node(node_index):
		return false
	for index: int in range(query_machine_count()):
		if query_node_under_machine(index) == node_index:
			return true
	return false


## Whether anything in the Factory is actually extracting from a Node.
##
## The opening step of a Run, asked of the whole Map rather than of one Node, because two
## things go quiet on it and must go quiet together: `Objective`'s first line, and the scanner
## that pings the nearest ore. A trail of pings still running across a Factory that is already
## mining would be leading a player somewhere they have been.
##
## A projection, and the loop is here rather than in `game/` for the reason the per-Node answer
## is: covering a Node is not working it, and that distinction belongs to
## `_machine_has_its_inputs` rather than to whichever caller asked. Nothing reads it back.
func query_anything_is_mining() -> bool:
	for node: int in range(query_node_count()):
		if query_node_is_being_worked(node):
			return true
	return false


## The nearest Node this Run could claim: workable now, with nothing built on it, measured
## from where the player is standing. -1 when there is nothing to point at.
##
## **One authority for "where should I go and put a Miner", because two things ask it.**
## `Objective`'s opening line names the ore and the way to turn, and the scanner draws a trail
## of pings out to it — and a trail running to one piece of ore while the line names another
## would be two opinions about one question. The same argument `BeltRoute` makes for being
## shared by the refusal, the apply and the preview.
##
## Both exclusions are the ones a player would make. Ore no unlocked Miner could lift is not
## somewhere to send them, and neither is ground already built on: the act this is pointing at
## ends in a click, and a tile with a Machine on it cannot take one.
##
## **Nearest by squared distance, so there is no square root and no rounding rule to decide a
## tie**, and Nodes are walked in index order — canonical tile order — on a *strict*
## improvement, so two Nodes exactly as far away hand the answer to the earlier tile on every
## client. The discipline a Turret's acquisition keeps, for the same reason.
##
## -1 rather than a nearest-anyway, the standing `query_turret_target_serial` has: it names
## something real or it names nothing. A projection; nothing in the Simulation reads it back.
func query_nearest_workable_node(player_id: int) -> int:
	if not _is_player(player_id):
		return -1
	var at: FixedVec2 = query_player_position(player_id)
	var nearest: int = -1
	var nearest_squared: int = 0
	for node: int in range(query_node_count()):
		if not query_node_is_workable_now(node):
			continue
		if query_node_is_built_on(node):
			continue
		var centre: FixedVec2 = query_tile_centre_metres(query_node_tile(node))
		var gap_x: int = centre.x - at.x
		var gap_z: int = centre.z - at.z
		var squared: int = Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z)
		if nearest == -1 or squared < nearest_squared:
			nearest = node
			nearest_squared = squared
	return nearest


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
	# A Sentry Drop's Turret arrives holding more than a Belt could ever have handed it, because
	# it was packed off the Map and needs no Belt — so the top of the gauge is whichever is
	# larger. Reporting the Belt's figure instead would draw a bar at 3000% and read as a bug
	# at exactly the moment a player most needs to know how long the Sentry has left in it.
	return maxi(capacity, _turret_ammunition(index))


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


# ── The Silo, the Stratagems, the dial and the Painting ───────────────────────

## How many Stratagems the content declares, and what each one is. Index order is the sorted
## Stratagem ids, which is the index space a `SET_SILO_DIAL` or `LOAD_SILO` intent travels in.
func query_stratagem_count() -> int:
	return _definitions.stratagem_count()


func query_stratagem_id(index: int) -> String:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return "" if definition == null else definition.id


func query_stratagem_display_name(index: int) -> String:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return "" if definition == null else definition.display_name


## Which of `StratagemDefinition.Effect` a Stratagem resolves as, or -1.
func query_stratagem_effect(index: int) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return -1 if definition == null else definition.effect


## How long a Stratagem channels, in whole ticks. Ticks rather than the file's seconds,
## because a tick is the Simulation's only unit of time and the conversion floors exactly
## once — the same arrangement a Recipe's duration has.
func query_stratagem_paint_ticks(index: int) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	if definition == null:
		return 0
	return maxi(_seconds_to_ticks(definition.paint_seconds), 1)


func query_stratagem_radius_tiles(index: int) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return 0 if definition == null else definition.radius_tiles


func query_stratagem_damage_per_charge(index: int) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return 0 if definition == null else definition.damage_per_charge


## Every Item one Charge of a Stratagem delivers, sorted by id. Empty for a Barrage.
func query_stratagem_goods(index: int) -> PackedStringArray:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return PackedStringArray() if definition == null else definition.goods_items.duplicate()


func query_stratagem_goods_per_charge(index: int, item_id: String) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return 0 if definition == null else definition.goods_of(item_id)


func query_stratagem_sentry_machine(index: int) -> String:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return "" if definition == null else definition.sentry_machine


func query_stratagem_sentry_seconds(index: int) -> int:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	return 0 if definition == null else definition.sentry_seconds


## Whether a Delivery has opened a Stratagem up, or it was never locked. The Stratagem twin of
## `query_machine_is_unlocked` and `query_gear_is_unlocked`.
func query_stratagem_is_unlocked(index: int) -> bool:
	var definition: StratagemDefinition = _definitions.stratagem_at(index)
	if definition == null:
		return false
	return _stratagem_is_unlocked(definition.id)


## Whether a Machine is a Silo. Asked of the Machine rather than inferred from its id, exactly
## as `query_machine_is_turret` is.
func query_machine_is_silo(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return definition != null and definition.is_silo()


## How many Charges a Silo has stockpiled, and how many it will hold. The two halves of the
## gauge a player reads to know whether there is artillery to call.
func query_silo_charges(index: int) -> int:
	if not query_machine_is_silo(index):
		return 0
	return _silo_charges[index]


func query_silo_charge_capacity(index: int) -> int:
	if not query_machine_is_silo(index):
		return 0
	return _definitions.machine(_machine_id[index]).charge_capacity


## What is in a Silo's tube: the Stratagem id, or "" for a Silo that is not loaded, and how
## many Charges went into it.
##
## **There is no query that would let anything take this back out**, and that is the point.
func query_silo_loaded_stratagem(index: int) -> String:
	if not query_machine_is_silo(index):
		return ""
	return _silo_loaded_stratagem[index]


func query_silo_loaded_charges(index: int) -> int:
	if not query_machine_is_silo(index):
		return 0
	return _silo_loaded_charges[index]


func query_silo_is_loaded(index: int) -> bool:
	return query_silo_loaded_charges(index) > 0


## The Silo a Painting would draw from, or -1 — the loaded one whose tile comes first in
## canonical tile order. What the HUD reads to say whether there is anything to call in.
func query_loaded_silo() -> int:
	return _loaded_silo()


## How close a player stands to work a Silo's dial, in fixed-point metres from its footprint.
func query_silo_load_reach_metres() -> int:
	return _definitions.silo_load_reach_metres


## The most Charges one load may commit — the dial's upper stop.
func query_max_charges_per_load() -> int:
	return maxi(_definitions.silo_max_charges_per_load, 1)


## The tick a Machine stands until, or -1 for one that stands indefinitely.
func query_machine_expires_tick(index: int) -> int:
	if not _is_machine(index):
		return -1
	return _machine_expires_tick[index]


## Whether a Machine is temporary — which, today, is exactly a Sentry Drop's Turret.
func query_machine_is_temporary(index: int) -> bool:
	return query_machine_expires_tick(index) >= 0


## How many ticks a temporary Machine has left, and 0 for one that is not temporary.
func query_machine_ticks_remaining(index: int) -> int:
	var expires: int = query_machine_expires_tick(index)
	if expires < 0:
		return 0
	return maxi(expires - _tick, 0)


## Where a player's dial is set. Not a load: nothing is committed until `LOAD_SILO`, and the
## HUD reads both this and `query_load_silo_refusal` so a player knows what they are about to
## commit and whether it would land.
func query_player_dial_stratagem(player_id: int) -> String:
	if not _is_player(player_id):
		return ""
	return _player_dial_stratagem[player_id]


## The same thing as an index into the sorted Stratagem ids, or -1. What a `LOAD_SILO` intent
## carries, so the controller reads it back rather than remembering it.
func query_player_dial_stratagem_index(player_id: int) -> int:
	return _definitions.stratagem_index(query_player_dial_stratagem(player_id))


func query_player_dial_charges(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_dial_charges[player_id]


## Why a load would be refused, or `Refusal.NONE`. A projection about a load that has not
## happened — the arrangement `query_build_refusal` has, and the one that matters most in this
## file: a load cannot be taken back, so the reason has to be on screen *before* the key.
func query_load_silo_refusal(
	player_id: int, tile: Vector3i, stratagem_index: int, charges: int
) -> int:
	return _load_silo_refusal(player_id, tile, stratagem_index, charges)


## Why a Painting would not start, or `Refusal.NONE`. The same kind of projection, about the
## act that spends what the load committed.
func query_paint_refusal(player_id: int, tile: Vector3i) -> int:
	return _paint_refusal(player_id, tile)


## Whether a player is channelling a Painting — which is to say, exposed and unable to act.
func query_player_is_painting(player_id: int) -> bool:
	if not _is_player(player_id):
		return false
	return _player_paint_charges[player_id] > 0


## The tile a Painting in flight is aimed at, which is also the tile its player is standing on.
func query_player_paint_tile(player_id: int) -> Vector3i:
	if not _is_player(player_id):
		return Vector3i.ZERO
	return Vector3i(
		_player_paint_target_x[player_id],
		_player_paint_target_y[player_id],
		_player_paint_target_z[player_id]
	)


## What a Painting in flight is carrying: the Stratagem id and the Charges already spent on it.
func query_player_paint_stratagem(player_id: int) -> String:
	if not _is_player(player_id):
		return ""
	return _player_paint_stratagem[player_id]


func query_player_paint_charges(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_paint_charges[player_id]


## Ticks of channel served, and ticks the Stratagem asks for. The two halves of the gauge the
## covering players watch — a fraction of a channel already served rather than a guess at how
## long is left, the shape the Telegraph's gauge has.
func query_player_paint_ticks_served(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_paint_ticks[player_id]


func query_player_paint_ticks_required(player_id: int) -> int:
	return query_stratagem_paint_ticks(
		_definitions.stratagem_index(query_player_paint_stratagem(player_id))
	)


## The tick a player's last Painting was interrupted on, or -1, and the Charges they have lost
## that way over the whole Run.
##
## **What an interrupted Painting costs, as a number.** State rather than an inference, so that
## a HUD can say it and a fixture can prove it rather than concluding it from an effect that
## never arrived.
func query_player_paint_interrupted_tick(player_id: int) -> int:
	if not _is_player(player_id):
		return -1
	return _player_paint_interrupted_tick[player_id]


func query_player_charges_wasted(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_charges_wasted[player_id]


## How many Stratagems a player has called in, and the Charges that went into them.
##
## **What a finished Painting bought, as a number**, beside what an interrupted one cost. The
## same argument: a HUD can say it, and a fixture can prove a Stratagem was fired rather than
## conclude it from an effect that may have landed on nothing.
func query_player_stratagems_fired(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_stratagems_fired[player_id]


func query_player_charges_fired(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	return _player_charges_fired[player_id]


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


## How many Enemies of a kind the Wave now being telegraphed will release, across every
## Breach — or 0 when no Telegraph is showing.
##
## **The legible half of #34.** A Breaker now arrives down the same road as everything else
## and turns on the Factory when it gets there, which is a lesson only if a player knows a
## Breaker is in the Wave *before* it is standing in their Smelter. So the warning names its
## tiers: six Crawlers and two Breakers is a different thing to stand somewhere for than
## eight Crawlers, and a Telegraph that said only "a Wave" could never have taught that.
##
## A **projection and not state**, which is why it reads off the definition set and the Heat
## rather than off `_wave_queue_kind`: that queue does not exist until `_begin_a_wave` composes
## it, and composing it early would be the Wave arriving. The number is therefore a promise
## about the Heat as it stands, and the Wave the Factory actually gets is composed from the
## Heat at the moment it *lands* — so a line that switches on during the Telegraph can still
## buy one more Crawler, which is the bet #12 is about and is correct to leave visible.
##
## Times every Breach, because `_release_from_the_breaches` releases one per Breach: a Map a
## player has dug two holes in is attacked through both, and a warning that did not say so
## would under-report by half.
func query_telegraphed_wave_count_of_kind(kind: int) -> int:
	if not query_wave_is_telegraphed():
		return 0
	var count: int = 0
	for index: int in range(_definitions.wave_entry_count()):
		var entry: WaveEntry = _definitions.wave_entry_at(index)
		if entry == null or entry.enemy_kind != kind:
			continue
		count += entry.count_at_heat(_heat)
	return count * query_breach_count()


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


## Why taking an Item out of the Nest's store would be refused, or `Refusal.NONE`. The same
## function `_apply_withdraw_from_nest` consults, so the reason on screen and the Simulation's
## own decision cannot disagree — the arrangement `query_build_refusal` and
## `query_delivery_refusal` already have.
func query_withdraw_refusal(player_id: int, item_index: int) -> int:
	return _withdraw_refusal(player_id, item_index)


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


## How much of an Item the Nest's store is holding — what a Belt has delivered past the open
## bill, and what a player standing at the Nest may withdraw and spend.
func query_nest_store(item_id: String) -> int:
	return _nest_store_held(item_id)


## Every Item the Nest's store is holding, sorted by id. A copy, and only Items it actually
## holds: an entry that empties is dropped, so this is the store's contents and not its
## history. The list a HUD draws the counter from.
func query_nest_store_items() -> PackedStringArray:
	return _nest_store_items.duplicate()


## How many of **each** Item the Nest's store will hold before it takes no more. One number
## per Item rather than one pot shared between them, so a Belt of coal cannot crowd plate out
## of the store.
func query_nest_store_capacity_per_item() -> int:
	return _definitions.nest_store_capacity_per_item


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
##
## **What the Hives are taking off it is already in this number**, which is the point of putting
## it here rather than beside it: the gauge a player has been reading all Run is the gauge that
## moves when they go out and kill one. `query_hive_heat_shadow_per_minute` is the same fact
## stated as a bill, for the sortie panel.
func query_heat_decay_per_minute() -> int:
	return _heat_decay_per_minute()


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


## Whether an Enemy is biting something rather than walking — the Nest, a Machine or a Wall.
## What the renderer reads to show a Crawler chewing.
##
## Asks `_enemy_contact_target`, which is the same function the tick asks, so what is drawn
## chewing is exactly what is being chewed. Not restricted to the Nest any more: a Breaker
## stopped at a Smelter is as much "attacking" as one stopped at the Nest, and a renderer that
## only knew about the Nest would draw a Breaker walking on the spot.
func query_enemy_is_attacking(index: int) -> bool:
	if not _is_enemy(index):
		return false
	var kind: int = _enemy_kind[index]
	# A Siege Hulk does not bite what it is standing on: it shells something sixty metres away,
	# or stomps whatever has walked up to it. Both are attacking, and neither is a contact
	# target, so the question is asked of the Hulk's own behaviour rather than of the tile.
	if kind == EnemyKind.SIEGE_HULK:
		return query_enemy_is_bombarding(index) or _player_in_contact(index) != -1
	var nest_field: PackedInt64Array = _flowfield()
	var field: PackedInt64Array = (
		_machine_flowfield() if kind == EnemyKind.BREAKER else nest_field
	)
	return _enemy_contact_target(index, kind, field, nest_field).x != BITE_NOTHING


## The point an Enemy is facing, in fixed-point metres. The Simulation holds a *point* rather
## than an angle because a point reduces the weak-point test to the sign of a dot product;
## `WorldView` turns it into a yaw with an `atan2`, which is a float `game/` is allowed.
func query_enemy_facing_point_metres(index: int) -> FixedVec2:
	if not _is_enemy(index):
		return FixedVec2.zero()
	return FixedVec2.new(_enemy_face_x[index], _enemy_face_z[index])


## The hit points an Enemy of this one's kind arrives with. What a HUD divides the remaining
## health by, so a player can see a boss's bar actually moving.
func query_enemy_max_health(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_health_for(_enemy_kind[index])


## How much of a hit this Enemy shrugs off when it is struck from the front, as a whole
## percentage. 0 for everything but a Siege Hulk.
##
## Exposed so the HUD can say `ARMOURED` rather than leaving a player to conclude their gun is
## broken. Deliberately **not** a query that says where the weak point is: discovering that the
## front is the wrong end is the fight, and a line of UI naming the answer would spend it.
func query_enemy_frontal_armour_percent(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_frontal_armour_percent(_enemy_kind[index])


## How tall an Enemy of this one's kind stands, in fixed-point metres.
##
## **The one authority on how big an Enemy is**, and the reason it is exposed rather than
## guessed at is #41's lesson in the other half of the renderer: a gauge hung off a
## `MACHINE_GAUGE_HEIGHT_METRES` set "taller than anything in the content" detached itself from
## every Machine that was not the tallest and shipped as a red rectangle with no owner. This is
## the number `_bite` reaches a player with, `_shot_target` resolves a round against and a
## Barrage measures, so a character mesh scaled to it is a character mesh a player can hit where
## they can see it.
##
## A projection the Simulation never reads back — it asks `_enemy_hit_height` directly, which is
## the same function — so asking cannot move the hash.
func query_enemy_hit_height_metres(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_hit_height(_enemy_kind[index])


## How wide an Enemy of this one's kind is, in fixed-point metres — the radius of the capsule a
## round is resolved against. The companion to `query_enemy_hit_height_metres`, and exposed for
## the same reason.
func query_enemy_hit_radius_metres(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_hit_radius(_enemy_kind[index])


## How far an Enemy reaches to attack — a Siege Hulk's shelling radius, and otherwise the reach
## it bites a player at. In fixed-point metres, so a HUD can draw the ring a player is standing
## inside.
func query_enemy_reach_metres(index: int) -> int:
	if not _is_enemy(index):
		return 0
	if _enemy_kind[index] == EnemyKind.SIEGE_HULK:
		return _definitions.siege_hulk_range_metres
	return _enemy_player_reach(_enemy_kind[index])


## Whether a Siege Hulk is standing still with something inside its reach to shell.
##
## A **pure read**, re-decided every tick, for the reason `_mend_target` is one: a query that
## moved a Hulk's target would move the state hash by being asked a question. It answers the
## three things that have to be true for the bombardment to be happening — nobody at its feet,
## no Turret able to reach it, and something in range — which is exactly the state the HUD and
## the renderer both want to draw.
func query_enemy_is_bombarding(index: int) -> bool:
	if not _is_enemy(index) or _enemy_kind[index] != EnemyKind.SIEGE_HULK:
		return false
	if query_run_is_over() or _enemy_spawn_tick[index] == _tick:
		return false
	if _player_in_contact(index) != -1:
		return false
	if _turret_covering(index) != -1:
		return false
	return _bombardment_target(index).x != BOMBARD_NOTHING


## Whether an Enemy has broken ranks — stopped marching on the Nest and turned on the Factory.
##
## True only of a Breaker, and only once it has come inside
## `enemy.breaker_breaks_ranks_within_tiles` of the Nest (#34). A Crawler never breaks ranks
## and neither does a Siege Hulk, so this is also the predicate a renderer asks to tell the
## threat to the Factory apart from the threat to the Nest *while it is still walking*.
##
## A pure read. Which Breakers have broken ranks is decided once a tick in `_enemies`, before
## anything is asked, for the reason `_aim` is the only thing that acquires: a query that
## latched would move the state hash by being asked a question.
func query_enemy_has_broken_ranks(index: int) -> bool:
	if not _is_enemy(index):
		return false
	return _enemy_broke_ranks[index] == 1


## Ticks until a Siege Hulk's next shell or stomp. One counter for both, which is why standing
## at its feet stops the bombardment.
func query_enemy_attack_ticks_remaining(index: int) -> int:
	if not _is_enemy(index):
		return 0
	return _enemy_attack_cooldown[index]


# ── The shells in the air ─────────────────────────────────────────────────────

## How many shells are in the air.
func query_shell_count() -> int:
	return _shell_ticks_left.size()


## Where a shell will land, in fixed-point metres. The marker a player runs out of is drawn from
## this, so what they dodge is literally where the damage will be.
func query_shell_impact_metres(index: int) -> FixedVec2:
	if index < 0 or index >= query_shell_count():
		return FixedVec2.zero()
	return FixedVec2.new(_shell_x[index], _shell_z[index])


## How many ticks a shell has left to fly. The countdown on the marker.
func query_shell_ticks_remaining(index: int) -> int:
	if index < 0 or index >= query_shell_count():
		return 0
	return _shell_ticks_left[index]


## How far from the impact point a shell is felt, in fixed-point metres. What decides how big
## the marker is drawn, so the ring on the ground is the blast rather than a guess at it.
func query_shell_blast_radius_metres() -> int:
	return _definitions.siege_hulk_shell_blast_radius_metres


## How long a shell is in the air from firing to landing, in whole ticks. The full span the
## marker's countdown is measured against, so the renderer is not told the number twice.
func query_shell_flight_ticks() -> int:
	return _shell_flight_ticks()


# ── The Hives ─────────────────────────────────────────────────────────────────

## How many Hives are still standing. Falls when one is destroyed and never rises again.
func query_hive_count() -> int:
	return _hive_health.size()


## Where a Hive stands.
func query_hive_tile(index: int) -> Vector3i:
	if not _is_hive(index):
		return Vector3i.ZERO
	return Vector3i(_hive_tile_x[index], _hive_tile_y[index], _hive_tile_z[index])


## What is left of a Hive, in whole hit points.
func query_hive_health(index: int) -> int:
	if not _is_hive(index):
		return 0
	return _hive_health[index]


## The hit points a Hive stands at full.
func query_hive_max_health() -> int:
	return _definitions.hive_health


## How much of the Nest's Heat shedding the standing Hives are drowning out between them, per
## minute.
##
## **The bill a player is paying for not having gone out there yet, in the units of the gauge
## they already watch.** It falls permanently when a Hive dies, which is what makes "destroying
## one reduces pressure permanently" a number rather than a promise.
func query_hive_heat_shadow_per_minute() -> int:
	return (
		_definitions.heat_decay_per_minute - _heat_decay_per_minute()
	)


# ── What leaving the Factory costs ────────────────────────────────────────────
#
# A sortie has to be a decision a player makes knowingly, which means the bill has to be
# readable *before* they walk out rather than discovered when they get back. Both of these are
# pure projections, like every other refusal and gauge in this file: the Simulation never reads
# either of them back, and the HUD puts them on screen the whole time a Hive or a Siege Hulk is
# standing.

## How far a player is from the Nest's footprint centre, in fixed-point metres. How far from
## home, and therefore how long the walk back to a wrench is.
##
## The one place in this file that takes a square root rather than comparing squares, and it is
## safe for the reason `query_power_ratio` is safe to divide: it is a gauge the Simulation never
## reads back, so the floor `Fixed.sqrt` applies cannot reach the state hash or move anything.
func query_player_metres_from_the_nest(player_id: int) -> int:
	if not _is_player(player_id):
		return 0
	var here: FixedVec2 = query_player_position(player_id)
	var centre: FixedVec2 = _nest_centre_metres()
	var gap_x: int = here.x - centre.x
	var gap_z: int = here.z - centre.z
	return Fixed.sqrt(Fixed.mul(gap_x, gap_x) + Fixed.mul(gap_z, gap_z))


## How many Machines are standing at less than full health.
##
## The other half of the bill: hand repair is what holds a Breaker off and what brings a shelled
## Factory back, and it is the one thing a player cannot do from out on the Map. A count rather
## than a list, because what a player deciding whether to leave needs is a number that is going
## up.
func query_machines_damaged() -> int:
	var damaged: int = 0
	for index: int in range(query_machine_count()):
		if _machine_missing_health(index) > 0:
			damaged += 1
	return damaged


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


## What is left of a Machine, in whole hit points, or 0 for an index naming none.
##
## Hashed state rather than a projection: a damaged Machine and a whole one are different
## states, and a save restores the Factory in the condition the Wave left it in.
func query_machine_health(index: int) -> int:
	if not _is_machine(index):
		return 0
	return _machine_health[index]


## The most hit points a Machine can hold — the `health` its row declares. What a wrench and a
## Repair Pylon mend towards, and the denominator of the gauge over a damaged Machine.
func query_machine_max_health(index: int) -> int:
	return _machine_max_health(index)


## Whether a Machine's output is repair rather than damage: a Repair Pylon.
##
## For the renderer and the HUD, which draw a Pylon's gauge in repair material rather than in
## rounds. The Simulation reads `MachineDefinition.heals()` directly.
func query_machine_is_repair_pylon(index: int) -> bool:
	if not _is_machine(index):
		return false
	var definition: MachineDefinition = _definitions.machine(_machine_id[index])
	return definition != null and definition.heals()


## How many Walls are standing.
func query_wall_count() -> int:
	return _wall_health.size()


## Which tile a Wall stands on.
func query_wall_tile(index: int) -> Vector3i:
	if not _is_wall(index):
		return Vector3i.ZERO
	return Vector3i(_wall_tile_x[index], _wall_tile_y[index], _wall_tile_z[index])


## The Wall standing on a tile, or -1. Walked in build order, which is cheap at this
## milestone's scale and the same on every client.
func query_wall_at_tile(tile: Vector3i) -> int:
	for index: int in range(query_wall_count()):
		if (
			_wall_tile_x[index] == tile.x
			and _wall_tile_y[index] == tile.y
			and _wall_tile_z[index] == tile.z
		):
			return index
	return -1


## What is left of a Wall, in whole hit points.
func query_wall_health(index: int) -> int:
	if not _is_wall(index):
		return 0
	return _wall_health[index]


## The hit points a Wall is built with, from `wall.health`. One number for every Wall, because
## there is one tier of Wall — a Wall has no row in `content/machines.csv` to differ in.
func query_wall_max_health() -> int:
	return _definitions.wall_health


## Why standing a Wall on a tile would be refused, or `Refusal.NONE`. A pure projection about
## a Wall that has not been built, so the hologram shows the reason before the click.
func query_build_wall_refusal(player_id: int, tile: Vector3i) -> int:
	return _build_wall_refusal(player_id, tile)


## Why holding the Pneumatic Wrench on a tile would mend nothing, or `Refusal.NONE`. A pure
## projection, so a HUD can say "out of reach" while the player is still walking over.
func query_repair_refusal(player_id: int, tile: Vector3i) -> int:
	return _repair_refusal(player_id, tile)


## How far a player can reach to repair, in fixed-point metres, from `wrench.reach_metres`.
func query_wrench_reach_metres() -> int:
	return _definitions.wrench_reach_metres


## How many Belts are laid.
func query_belt_count() -> int:
	return _belt_tiles.size()


## How many tiles long a Belt's run is. 0 for an unknown Belt.
func query_belt_length_tiles(index: int) -> int:
	if not _is_belt(index):
		return 0
	return _belt_tiles[index]


## Why the route a player is dragging would be refused, or `Refusal.NONE`.
##
## A projection of state that has not changed, in the shape `query_build_refusal` already
## has: asking costs nothing and changes nothing, which is what lets the preview ask every
## frame about a route nobody has committed to and put the reason on screen **before** the
## drag is released. `_apply_build_belt` consults the same function, so the route a player
## was told was clear is the route that lands.
func query_belt_route_refusal(
	player_id: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> int:
	return _belt_route_refusal(player_id, from_tile, to_tile, corner_axis)


## How many tiles of Belt a dragged route would stand up. The number a player is deciding on,
## and the multiplier the bill below is the per-tile price times.
func query_belt_route_tiles(
	player_id: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> int:
	var tiles: int = 0
	for run: BeltRoute.Run in _belt_route_runs(player_id, from_tile, to_tile, corner_axis):
		tiles += run.length_tiles()
	return tiles


## What a dragged route would cost, as parallel arrays of Item id and count — the whole bill
## for the whole route, not the per-tile price.
##
## A projection about a route that has not been laid, the same arrangement
## `query_belt_route_refusal` has and for the same reason: the bill belongs on screen **before
## the button comes up**, beside the length, which is the only version that leaves the hash
## alone. Empty for a route that costs nothing, which is what a set with no structures table
## prices every Belt at.
## Which Items a route's bill is made of. The route is taken as an argument it does not read,
## so that the two halves of one bill are asked the same question — which Items, and how many —
## rather than the caller having to know that only the counts depend on the length.
func query_belt_route_cost_items(
	_player_id: int, _from_tile: Vector3i, _to_tile: Vector3i, _corner_axis: int
) -> PackedStringArray:
	return _definitions.structure_cost_items(Definitions.STRUCTURE_BELT)


func query_belt_route_cost_counts(
	player_id: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> PackedInt64Array:
	var tiles: int = query_belt_route_tiles(player_id, from_tile, to_tile, corner_axis)
	var counts: PackedInt64Array = _definitions.structure_cost_counts(
		Definitions.STRUCTURE_BELT
	)
	var total: PackedInt64Array = PackedInt64Array()
	for index: int in range(counts.size()):
		total.append(counts[index] * tiles)
	return total


## What one tile of a structure costs — `Definitions.STRUCTURE_BELT` or `STRUCTURE_WALL` — as
## parallel arrays. What the Machine picker's Belt cell and the Wall key read, so the price on
## screen is the price the Simulation charges.
func query_structure_cost_items(structure_id: String) -> PackedStringArray:
	return _definitions.structure_cost_items(structure_id)


func query_structure_cost_counts(structure_id: String) -> PackedInt64Array:
	return _definitions.structure_cost_counts(structure_id)


## Why one tile of a route would be refused, or `Refusal.NONE`. What the preview tints each
## tile by, so the obstruction is marked where it is rather than described in a line of text
## somewhere else.
func query_belt_tile_refusal(tile: Vector3i) -> int:
	return _belt_tile_refusal(tile)


## Whether a Belt's far end leads anywhere goods can go: a Machine's footprint, the Nest's,
## or the entry tile of another Belt.
##
## **The geometry half of `_hand_off`, with the fullness left out.** A Belt into a Machine
## whose input buffer happens to be full is connected and backing up, which is a different
## thing a player wants to read differently — `query_belt_is_stalled` is that one. Asked every
## frame and remembering nothing, because there is no stored connection to go stale: Belts
## connect by adjacency and nothing else, so demolishing what a Belt fed makes it dangle on
## the next frame with no bookkeeping anywhere.
func query_belt_end_is_connected(index: int) -> bool:
	if not _is_belt(index):
		return false
	var beyond: Vector3i = (
		_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
	)
	# The declared port rather than the footprint, since #47, so a Belt that ends against a
	# Machine's blank wall is marked as going nowhere — which it does.
	if _machine_a_belt_feeds(index) != -1:
		return true
	if _nest_covers(beyond):
		return true
	return _belt_entered_at(beyond) != -1


## Whether anything is loading a Belt at its entry: a Machine output port behind it, or
## another Belt handing Items on.
##
## The geometry half of `_load_from_port`, in the shape above and for the same reason. A Belt
## nothing feeds is the commonest mistake a new player makes — it is laid the right length,
## pointed the right way, and starts one tile too far from the Machine — and it is invisible
## without this.
func query_belt_start_is_fed(index: int) -> bool:
	if not _is_belt(index):
		return false
	if _machine_behind_belt(index) != -1:
		return true
	var upstream: int = _belt_at_tile_feeding(_belt_entry_tile(index))
	return upstream != -1


## How many Belts run out of a Machine's declared output ports: the size of the branch its
## output is shared between.
##
## **`_machine_behind_belt`'s answer asked from the other side**, per Machine rather than per
## Belt, so the membership a player is shown is exactly the group `_load_the_ports` serves in
## rotation. A Belt docking against a wall that is not a declared output port is not in it —
## it is not a branch that gets no turns, it is not a branch (#47).
##
## 1 is an ordinary line and 2 or more is a split. A projection the Simulation never reads
## back: #46 put the rotation behind the façade and nothing drew it, which made a fairly
## shared Machine indistinguishable from a priority (#48).
func query_machine_branch_count(machine: int) -> int:
	return _branch_belts(machine).size()


## The nth Belt of a Machine's branch, in the canonical order `_load_the_ports` serves them
## in, or -1 past the end. Canonical order rather than index order for the reason the cursor
## indexes that way: the list is geography and not build history.
func query_machine_branch_belt(machine: int, which: int) -> int:
	var branches: PackedInt64Array = _branch_belts(machine)
	if which < 0 or which >= branches.size():
		return -1
	return branches[which]


## The Belts a Machine loads, in canonical order. The one definition both queries read, so
## the count and the membership cannot disagree about what a branch is.
func _branch_belts(machine: int) -> PackedInt64Array:
	var branches: PackedInt64Array = PackedInt64Array()
	if machine < 0 or machine >= query_machine_count():
		return branches
	var canonical: PackedInt64Array = _canonical_belts()
	for position: int in range(canonical.size()):
		if _machine_behind_belt(canonical[position]) == machine:
			branches.append(canonical[position])
	return branches


## The Belt, if any, whose far end hands Items onto the tile given. The reverse of
## `_belt_downstream`, walked rather than stored for the reason nothing else here is stored.
func _belt_at_tile_feeding(tile: Vector3i) -> int:
	for index: int in range(query_belt_count()):
		if _belt_covers(index, tile):
			continue
		if (
			_belt_exit_tile(index) + WorldGrid.direction_step(_belt_direction[index])
			== tile
		):
			return index
	return -1


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


# ── How tall the Factory is ───────────────────────────────────────────────────
#
# One projection per structure, because the renderer draws exactly these heights and the
# Simulation collides against exactly these heights, and a renderer holding its own constant
# for how tall a Wall is would be a second authority on a fact a player can walk into.

## How high the Factory stands on one tile, in fixed-point metres. 0 for bare ground, for a
## tile outside the Map, and for a Node or a Breach, neither of which is a building.
##
## The whole of what a player collides with, as one number per tile — so a test asks this
## rather than inferring a height from whatever happens to be standing there.
func query_solid_height_metres(tile: Vector3i) -> int:
	_solid_heights()
	return _solid_height_at(tile)


## How tall a Machine's housing stands, in fixed-point metres, off the `height_metres`
## column of its own row. 0 for an index naming none.
func query_machine_height_metres(index: int) -> int:
	return _machine_height(index)


## How tall a Wall stands, in fixed-point metres, from `wall.height_metres`.
func query_wall_height_metres() -> int:
	return _definitions.wall_height


## How high a Belt's deck stands, in fixed-point metres, from `belt.deck_height_metres`.
func query_belt_deck_height_metres() -> int:
	return _definitions.belt_deck_height


## How high the Nest's crown stands, in fixed-point metres, from `nest.height_metres`.
func query_nest_height_metres() -> int:
	return _definitions.nest_height


## How high the Nest's outer terrace stands, in fixed-point metres, from
## `nest.terrace_height_metres` — the step that makes the ziggurat climbable.
func query_nest_terrace_height_metres() -> int:
	return _definitions.nest_terrace_height


## The tallest surface a player walks straight up onto rather than having to clear, in
## fixed-point metres, from `player.step_up_height_metres`. A kerb on the ground and a
## mantle in the air.
func query_player_step_up_height_metres() -> int:
	return _definitions.player_step_up_height


## How wide a player is for collision, as the half-extent of their box, in fixed-point
## metres, from `player.collision_radius_metres`.
func query_player_collision_radius_metres() -> int:
	return _definitions.player_collision_radius


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


## Whether an index names a Wall standing in the Factory.
func _is_wall(index: int) -> bool:
	return index >= 0 and index < _wall_health.size()


func _is_belt(index: int) -> bool:
	return index >= 0 and index < _belt_tiles.size()


func _is_machine(index: int) -> bool:
	return index >= 0 and index < _machine_id.size()


func _is_node(index: int) -> bool:
	return index >= 0 and index < _node_resource.size()


func _is_player(player_id: int) -> bool:
	return player_id >= 0 and player_id < _player_x.size()
