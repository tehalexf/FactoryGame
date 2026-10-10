## The machine answering you: every sound the Run makes, derived from what the
## Simulation says changed.
##
## DESIGN.md is blunt about why this file exists. IRON NEST's most-praised quality
## is its sound design and its most-cited criticism is that its loop reduces to
## "plunk in figures here, enter the results there" — and the line between
## satisfying friction and tedium is whether the machine answers you. **A lever
## that clunks is a reward; a silent lever is a chore.** So this is not polish, and
## no diegetic control ships silent.
##
## ## It reads. It never writes, and it never remembers the Run
##
## ADR 0001 makes the Godot layer an input producer and a state reader. This is a
## state reader, and the strictest kind: it holds **no authoritative state at
## all**, only a snapshot of what the queries said last frame, which exists for one
## reason — a sound is a *change*, and a query reports a *condition*. "There is a
## loaded Silo" is not a cue; "there was not one and now there is" is.
##
## That is the same category of thing as `TickPump`'s leftover frame time and
## `PlayerController`'s device buffer: a reading on its way through, not a fact
## about the world. Nothing here is ever consulted about whether something is true.
## The Simulation stays the authority, the state hash does not move, and
## `tests/cases/test_game_audio.gd` asserts exactly that by running the same script
## with and without a director attached.
##
## ## Three seams, because two of them need no audio device
##
## * `cues_for_frame(sim)` — "given what changed, what should fire". Returns plain
##   records and plays nothing. Every cue a player will ever hear is a cheap
##   assertion against this rather than something only a microphone could catch.
## * `ambience_db(sim)` and `sustained_cues(sim)` — pure functions of the Run: how
##   loud the two Factory beds sit, and which sustained beds should be running.
## * `sync(sim)` — the only one that touches a player node or the AudioServer.
##
## ## What it does not do
##
## Nothing here is rate-limited by wall-clock time, and nothing picks a variant
## with `randi`. Variation is `tick % count` inside `SoundBank`, and the two cues
## that would otherwise machine-gun — a Machine being chewed on, an Enemy swinging
## — are spaced by **ticks**. Two Runs down the same Input Action script therefore
## sound the same, which is the audio half of the rule `WeaponViewmodel` already
## keeps for animation.
class_name AudioDirector
extends Node3D

## Which player this instance is listening for. One for now; co-op makes it the
## local id, and every cue below that is about *a* player rather than *the world*
## is deliberately scoped to it — somebody else's footsteps are their business.
const LOCAL_PLAYER: int = 0

## How many positional one-shots may be in flight at once. A Wave at the Milestone
## 1 Enemy count with a full Factory under fire is the load this was sized for:
## twenty Enemies, a handful of Turrets, and the Machines they are eating.
const POSITIONAL_VOICES: int = 24

## How many non-positional one-shots may be in flight at once. Fewer, because these
## are the player's own hands and feet and there are only so many of those — but
## more than one, because a shot is three layers.
const LOCAL_VOICES: int = 8

## How far a positional cue carries, in metres, and the distance at which it is
## heard at its catalogue gain. A Factory is tens of metres across and the point of
## positional audio here is knowing *which* corner of it is in trouble, so the
## falloff has to be audible well inside the base rather than only at the map edge.
const VOICE_UNIT_SIZE: float = 12.0
const VOICE_MAX_DISTANCE: float = 90.0

## How far a player walks between footsteps, in metres. The gait is derived from
## distance travelled rather than from a clock, so a player who stops mid-stride
## stops making noise and a sprinting one steps faster for free.
const STRIDE_METRES: float = 2.1

## The quietest a player is set to rather than being stopped. Godot treats -80 dB
## as silence, and leaving a bed running at silence is cheaper and clickless
## compared with stopping and restarting it as a Factory grows and shrinks.
const SILENT_DB: float = -80.0

## How many ticks apart two cues about the same object may be. A Breaker chewing a
## Smelter damages it every tick and a cue a tick is a buzz rather than an alarm.
const REPEAT_COOLDOWN_TICKS: int = 18

## How soon after a melee swing an Enemy losing health is read as *that* swing
## landing rather than as a Turret's round arriving. Generous, because the swing
## animation is long and the alternative — a wrench that hits silently — is worse
## than a wrench that occasionally takes credit for a Turret.
const MELEE_WINDOW_TICKS: int = 12

## How many cooldown keys may pile up before the bag is swept. Comfortably more
## than the Milestone 1 Enemy count plus a Factory's worth of Machines, so a sweep
## is a rare event rather than a per-frame cost.
const COOLDOWN_KEYS_BEFORE_PRUNE: int = 256

# ── How the Factory's two ambience beds are mixed ─────────────────────────────
# "Machinery ambience scales with Factory size" (issue #21), and the measure is
# **working** Machines rather than placed ones: a starved Factory is a quiet
# Factory, which is a reading a player can act on. A Belt counts for a quarter of a
# Machine, because a Belt is a small noise and there are a great many of them.

const BELT_WEIGHT: float = 0.25

## The quiet bed comes up over the first few working Machines and is at full level
## by the time there is a production line worth looking at.
const BED_FULL_AT_WORKS: float = 8.0
const BED_FLOOR_DB: float = -14.0

## The busy bed — a factory hall with alarms and machines in it — stays out until
## the Factory is genuinely busy, then climbs. Nothing before `BUSY_FROM_WORKS` so
## that two Miners and a Smelter do not sound like a shipyard.
const BUSY_FROM_WORKS: float = 5.0
const BUSY_FULL_AT_WORKS: float = 32.0
const BUSY_FLOOR_DB: float = -22.0


## One sound to play, where, and how much louder or quieter than its catalogue gain.
##
## A plain bag of values with no behaviour, so a test can read one without an audio
## device and `sync` can consume one without asking the Simulation anything.
class Cue extends RefCounted:
	var name: String = ""
	## Where it happens, in world metres. Ignored when `positional` is false.
	var at: Vector3 = Vector3.ZERO
	## False for the player's own hands, feet and HUD: those are not *somewhere*,
	## they are here, and panning them away from the listener is wrong.
	var positional: bool = false
	## On top of `SoundBank.gain_db`, for the cases where one event wants the same
	## cue at two weights.
	var trim_db: float = 0.0

	func _init(cue_name: String = "", world_position: Vector3 = Vector3.ZERO,
			is_positional: bool = false, trim: float = 0.0) -> void:
		name = cue_name
		at = world_position
		positional = is_positional
		trim_db = trim


## What the queries said last frame. Everything in here exists only to be compared
## against what they say this frame.
class Snapshot extends RefCounted:
	## -1 until the first read, which is how the opening frame is told apart from a
	## frame on which everything changed at once.
	var tick: int = -1
	var dial_stratagem: int = -1
	var dial_charges: int = -1
	## Silo tile -> where its body is, for the Silos with something in the tube.
	var loaded_silos: Dictionary = {}
	var painting: bool = false
	## The tick this player's last Painting was interrupted on, or -1. **This is how
	## a finished channel is told from an abandoned one**: every interruption records
	## a tick and a completion records nothing, so a Painting that stopped without the
	## tick moving is one that landed. The alternative — comparing ticks served against
	## ticks required — is wrong whenever a frame covers more than one tick, which is
	## most frames.
	var paint_interrupted_tick: int = -1
	## Machine tile -> `[health, where its body is]`, for every Machine standing.
	##
	## **The position is recorded rather than looked up when a cue fires**, and that
	## is what lets a destroyed Machine still be heard: by the time this layer
	## notices one is gone, there is no index left to ask where it stood.
	var machines: Dictionary = {}
	## Machine tile -> `[whether that generator was starved, where it is]`.
	## Generators only.
	var generators_starved: Dictionary = {}
	## Turret tile -> `[the tick it last fired on, where it is]`.
	var turret_shots: Dictionary = {}
	## Enemy serial -> `[health, attacking, position]`.
	var enemies: Dictionary = {}
	var delivered_goods: int = 0
	var deliveries_completed: int = 0
	var wave_number: int = 0
	var telegraphed: bool = false
	var breaches: int = 0
	var nest_health: int = 0
	var nest_position: Vector3 = Vector3.ZERO
	var player_shot_tick: int = -1
	var shots_remaining: int = -1
	var player_health: int = -1
	var player_downed: bool = false
	## Whether the player is on their feet at all — Downed *or* dead is off them. The fact
	## `PLAYER_DOWN` fires on, because a body hits the deck once however it got there, and
	## because `player_downed` is **never true on a solo Run** (GLOSSARY.md). Opens `true`,
	## so a Run whose first frame finds somebody already down does not thud for it; the
	## opening frame reports no diffs anyway.
	var player_on_their_feet: bool = true
	var player_grounded: bool = true
	var player_position: Vector3 = Vector3.ZERO
	## How far the player has walked since the last footstep, in metres.
	var stride: float = 0.0
	var run_over: bool = false


var _bank: SoundBank = SoundBank.new()
var _last: Snapshot = Snapshot.new()
## Object key -> the tick a cue about it last fired on, so a Machine being eaten
## groans rather than buzzes. Pruned as it goes — see `_cooled_down` — because an
## Enemy serial is never reused and a long Run would otherwise accumulate one key
## per Enemy that ever swung.
var _cooldowns: Dictionary = {}

var _positional: Array[AudioStreamPlayer3D] = []
var _local: Array[AudioStreamPlayer] = []
## Cue name -> the player holding that sustained bed. Four of them, built on
## demand: the two Factory beds, the Telegraph klaxon and the Painting channel.
var _sustained: Dictionary = {}
## Whether the one-shot voice pools have been built. Deferred to the first `sync`
## rather than done in `_init`, so a director a test only ever asks
## `cues_for_frame` of never touches the AudioServer at all. The sustained beds are
## separate and later still — `_hold` builds each one the first time it is wanted.
##
## The pools are built **once and all at once**, which is the rule `WorldView`
## keeps for Machines: the scene tree must not grow a node as a Run goes on.
var _voices_built: bool = false


## The catalogue, so a test can ask what a cue resolves to without reaching into
## this file's internals.
func bank() -> SoundBank:
	return _bank


# ── The one function that makes a noise ───────────────────────────────────────

## Play whatever changed, and set the sustained beds to where the Run has them.
func sync(sim: Simulation) -> void:
	var tick: int = sim.query_tick()
	var cues: Array = cues_for_frame(sim)
	if not cues.is_empty():
		_build_voices()
		for cue: Cue in cues:
			_play(cue, tick)
	_sync_sustained(sim)


# ── Seam one: what changed ────────────────────────────────────────────────────

## The cues this frame has earned, in the order they should be started in.
##
## Pure except for the snapshot, which is the whole mechanism: every branch below
## compares a query against what it said last time and then records the new answer.
## Nothing here reads the node tree, the clock or an audio device, which is what
## makes the entire sound design assertable headless.
##
## **Two frames produce nothing at all**, deliberately:
##
## * the first, because every condition has just become true and a Run must not
##   open with a Machine-built cue per Machine and a Wave horn;
## * any frame on which the tick went *backwards*, which is a resumed save
##   (`Main.load_run` replaces the Simulation outright). The snapshot is re-read and
##   the Run carries on silently from there, rather than announcing the difference
##   between two unrelated states.
func cues_for_frame(sim: Simulation) -> Array:
	var now: Snapshot = _read(sim)
	var opening: bool = _last.tick < 0 or now.tick < _last.tick
	var cues: Array = []
	if not opening:
		cues = _differences(sim, _last, now)
	# The stride carries across frames rather than being re-read, because it is the
	# one quantity here the Simulation does not hold: how far this player has walked
	# since their last footstep.
	now.stride = _advance_stride(sim, _last, now, cues, opening)
	_last = now
	return cues


## How loud the two Factory ambience beds should sit, in dB: `[bed, busy]`.
##
## A pure function of the Run, so the claim "growth is audible" is a test rather
## than a listening session. `SILENT_DB` means off.
func ambience_db(sim: Simulation) -> PackedFloat32Array:
	var works: float = factory_works(sim)
	var bed: float = SILENT_DB
	var busy: float = SILENT_DB
	if works > 0.0:
		bed = _bank.gain_db(SoundBank.FACTORY_BED) + _ramp(
			works, 1.0, BED_FULL_AT_WORKS, BED_FLOOR_DB, 0.0
		)
	if works > BUSY_FROM_WORKS:
		busy = _bank.gain_db(SoundBank.FACTORY_BUSY) + _ramp(
			works, BUSY_FROM_WORKS, BUSY_FULL_AT_WORKS, BUSY_FLOOR_DB, 0.0
		)
	return PackedFloat32Array([bed, busy])


## How much Factory there is to be heard: working Machines, plus a quarter of a
## Machine per Belt tile.
##
## **Working**, not placed. A Machine the Simulation calls starved is producing
## nothing, and a Factory that has run out of ore going quiet is a reading a player
## can act on — the audio half of the idle-Miner rule the renderer already keeps.
func factory_works(sim: Simulation) -> float:
	var working: int = 0
	for index: int in range(sim.query_machine_count()):
		if not sim.query_machine_is_starved(index):
			working += 1
	var belt_tiles: int = 0
	for index: int in range(sim.query_belt_count()):
		belt_tiles += sim.query_belt_length_tiles(index)
	return float(working) + float(belt_tiles) * BELT_WEIGHT


## Which sustained beds should be running right now, besides the two ambience ones.
##
## Pure, and the whole of the Telegraph's "a warning you cannot hear is not a
## warning": the klaxon is on for exactly as long as `query_wave_is_telegraphed`
## is, and stops when it stops rather than being a one-shot that might have
## finished before the Wave lands.
func sustained_cues(sim: Simulation) -> PackedStringArray:
	var running: PackedStringArray = PackedStringArray()
	if sim.query_wave_is_telegraphed():
		running.append(SoundBank.TELEGRAPH_KLAXON)
	if sim.query_player_is_painting(LOCAL_PLAYER):
		running.append(SoundBank.PAINT_LOOP)
	return running


# ── Reading the Run ───────────────────────────────────────────────────────────

func _read(sim: Simulation) -> Snapshot:
	var now: Snapshot = Snapshot.new()
	now.tick = sim.query_tick()
	now.dial_stratagem = sim.query_player_dial_stratagem_index(LOCAL_PLAYER)
	now.dial_charges = sim.query_player_dial_charges(LOCAL_PLAYER)
	now.painting = sim.query_player_is_painting(LOCAL_PLAYER)
	now.paint_interrupted_tick = sim.query_player_paint_interrupted_tick(LOCAL_PLAYER)

	var definitions: Definitions = sim.query_definitions()
	for index: int in range(sim.query_machine_count()):
		var tile: Vector3i = sim.query_machine_tile(index)
		var at: Vector3 = _machine_centre(sim, index)
		now.machines[tile] = [sim.query_machine_health(index), at]
		if sim.query_machine_is_silo(index) and sim.query_silo_is_loaded(index):
			now.loaded_silos[tile] = at
		if sim.query_machine_is_turret(index):
			now.turret_shots[tile] = [sim.query_turret_last_shot_tick(index), at]
		var definition: MachineDefinition = definitions.machine(sim.query_machine_id(index))
		if definition != null and definition.is_generator():
			now.generators_starved[tile] = [sim.query_machine_is_starved(index), at]

	for index: int in range(sim.query_enemy_count()):
		now.enemies[sim.query_enemy_serial(index)] = [
			sim.query_enemy_health(index),
			sim.query_enemy_is_attacking(index),
			_ground(sim.query_enemy_position_metres(index)),
		]

	for item_id: String in definitions.item_ids():
		now.delivered_goods += sim.query_delivery_goods_delivered(item_id)
	now.deliveries_completed = sim.query_completed_deliveries().size()
	now.wave_number = sim.query_wave_number()
	now.telegraphed = sim.query_wave_is_telegraphed()
	now.breaches = sim.query_breach_count()
	now.nest_health = sim.query_nest_health()
	now.nest_position = _tile_centre(sim, sim.query_nest_tile())

	now.player_shot_tick = sim.query_player_last_shot_tick(LOCAL_PLAYER)
	now.shots_remaining = sim.query_player_shots_remaining(LOCAL_PLAYER)
	now.player_health = sim.query_player_health(LOCAL_PLAYER)
	now.player_downed = sim.query_player_is_downed(LOCAL_PLAYER)
	now.player_on_their_feet = sim.query_player_is_alive(LOCAL_PLAYER)
	now.player_grounded = sim.query_player_is_grounded(LOCAL_PLAYER)
	now.player_position = _ground(sim.query_player_position(LOCAL_PLAYER))
	now.run_over = sim.query_run_is_over()
	return now


# ── Seam one, continued: one branch per thing a player can hear ───────────────

func _differences(sim: Simulation, was: Snapshot, now: Snapshot) -> Array:
	var cues: Array = []
	_diegetic_cues(sim, was, now, cues)
	_wave_cues(was, now, cues)
	_factory_cues(was, now, cues)
	_combat_cues(sim, was, now, cues)
	_player_cues(sim, was, now, cues)
	return cues


## The five controls DESIGN.md names, in its order. Every one of them is here, and
## none of them is silent.
func _diegetic_cues(sim: Simulation, was: Snapshot, now: Snapshot, cues: Array) -> void:
	# 1. The Silo's loading dial. Two controls, two sounds: the shell selector
	# chooses *what*, the charge counter chooses *how much*. Both are under the
	# player's own hands, so neither is positional.
	if now.dial_stratagem != was.dial_stratagem:
		cues.append(Cue.new(SoundBank.SILO_DIAL_SHELL))
	if now.dial_charges != was.dial_charges:
		cues.append(Cue.new(SoundBank.SILO_DIAL_CHARGES))

	# 1b. The commit, at the Silo rather than at the player: a four-metre body with
	# a tube, and the sound belongs to the body. **Two layers**, because this is the
	# one act a player cannot take back and a single latch click does not carry that.
	for tile: Vector3i in now.loaded_silos.keys():
		if was.loaded_silos.has(tile):
			continue
		var at: Vector3 = now.loaded_silos[tile] as Vector3
		cues.append(Cue.new(SoundBank.SILO_COMMIT, at, true))
		cues.append(Cue.new(SoundBank.SILO_COMMIT_BODY, at, true))

	# 2. Painting: a channel, so it has a beginning, a held layer (see
	# `sustained_cues`), and two different endings. Which ending is the whole of what
	# an interrupted Painting costs — the Charges left the Silo on the tick it began
	# and nothing gives them back.
	if now.painting and not was.painting:
		cues.append(Cue.new(SoundBank.PAINT_BEGIN))
	var interrupted: bool = now.paint_interrupted_tick != was.paint_interrupted_tick
	if interrupted:
		cues.append(Cue.new(SoundBank.PAINT_INTERRUPTED))
	elif was.painting and not now.painting:
		cues.append(Cue.new(SoundBank.PAINT_COMPLETE))

	# 3. Boiler startup and pressure relief.
	#
	# **The Simulation has no boiler valve yet** — there is no Input Action for one,
	# and inventing a player-operated control here would be this layer holding state
	# about the Run, which it may not. So the two sounds are hung on the thing the
	# Simulation *does* model: a generator's fuel. Coal arriving is the fire
	# catching; running dry is the pressure going, and that vents. When the valve
	# itself is a ticket, these two cues are what it will pull.
	for tile: Vector3i in now.generators_starved.keys():
		if not was.generators_starved.has(tile):
			continue
		var state: Array = now.generators_starved[tile] as Array
		var starved_now: bool = state[0] as bool
		if starved_now == ((was.generators_starved[tile] as Array)[0] as bool):
			continue
		cues.append(
			Cue.new(
				SoundBank.BOILER_RELIEF if starved_now else SoundBank.BOILER_STARTUP,
				state[1] as Vector3,
				true
			)
		)

	# 4. The Delivery intake at the Nest. Progression is physical (GLOSSARY.md), so
	# the intake is at the Nest's own tile and not in the player's ear — and a tier
	# completing rings, which is the Nest telling the whole Map that something new is
	# possible.
	var nest: Vector3 = now.nest_position
	# **Or**, not just the first clause. `delivered_goods` is what has been handed over
	# against the *open* tier, so a Delivery that finishes a tier takes it back to zero
	# in the same frame it filled it — and a handover big enough to open a tier is the
	# last one that should be inaudible.
	if now.delivered_goods > was.delivered_goods \
			or now.deliveries_completed > was.deliveries_completed:
		cues.append(Cue.new(SoundBank.DELIVERY_INTAKE, nest, true))
	if now.deliveries_completed > was.deliveries_completed:
		cues.append(Cue.new(SoundBank.DELIVERY_COMPLETE, nest, true))

	# 5. The call-Wave-early lever. On the Nest, where the lever will be when it is
	# art rather than `KEY_CALL_WAVE`; the klaxon that goes with it is the Telegraph's
	# own, in `sustained_cues`.
	#
	# **On the Telegraph starting, not on the Wave arriving.** Pulling the lever does
	# not produce a Wave; it produces a Telegraph, and the Wave lands a dozen seconds
	# later (`wave.telegraph_seconds` is a floor on the warning, including for a Wave
	# somebody called). A clunk a dozen seconds after the hand that caused it is not a
	# control answering you, which is the whole point of this file.
	if now.telegraphed and not was.telegraphed and sim.query_wave_was_called_early():
		cues.append(Cue.new(SoundBank.CALL_WAVE_LEVER, nest, true))


func _wave_cues(was: Snapshot, now: Snapshot, cues: Array) -> void:
	if now.wave_number > was.wave_number:
		cues.append(Cue.new(SoundBank.WAVE_BEGIN))
	if now.breaches > was.breaches:
		cues.append(Cue.new(SoundBank.BREACH_OPENS))
	if now.run_over and not was.run_over:
		cues.append(Cue.new(SoundBank.RUN_OVER))


func _factory_cues(was: Snapshot, now: Snapshot, cues: Array) -> void:
	for tile: Vector3i in now.machines.keys():
		var state: Array = now.machines[tile] as Array
		var at: Vector3 = state[1] as Vector3
		if not was.machines.has(tile):
			cues.append(Cue.new(SoundBank.MACHINE_BUILT, at, true))
			continue
		# Only downwards. A wrench and a Repair Pylon put health back and a Factory
		# being mended is not an event worth a sound per tick.
		if (state[0] as int) < ((was.machines[tile] as Array)[0] as int) \
				and _cooled_down("damage:" + str(tile), now.tick):
			cues.append(Cue.new(SoundBank.MACHINE_DAMAGED, at, true))

	for tile: Vector3i in was.machines.keys():
		if now.machines.has(tile):
			continue
		# Gone. Destroyed or demolished — the Simulation does not distinguish them
		# in a query and neither does this, because a Machine leaving the grid under
		# a player's own Build Gun still wants the same crunch.
		cues.append(
			Cue.new(SoundBank.MACHINE_DESTROYED, (was.machines[tile] as Array)[1] as Vector3, true)
		)

	for tile: Vector3i in now.turret_shots.keys():
		if not was.turret_shots.has(tile):
			continue
		var shot: Array = now.turret_shots[tile] as Array
		if (shot[0] as int) > ((was.turret_shots[tile] as Array)[0] as int):
			cues.append(Cue.new(SoundBank.TURRET_FIRE, shot[1] as Vector3, true))

	if now.nest_health < was.nest_health and _cooled_down("nest", now.tick):
		cues.append(Cue.new(SoundBank.NEST_DAMAGED, now.nest_position, true))


func _combat_cues(sim: Simulation, was: Snapshot, now: Snapshot, cues: Array) -> void:
	var melee: bool = sim.query_player_weapon_is_melee(LOCAL_PLAYER)
	var swung_recently: bool = (
		melee
		and now.player_shot_tick >= 0
		and now.tick - now.player_shot_tick <= MELEE_WINDOW_TICKS
	)

	for serial: int in now.enemies.keys():
		var state: Array = now.enemies[serial] as Array
		if not was.enemies.has(serial):
			continue
		var before: Array = was.enemies[serial] as Array
		if (state[0] as int) < (before[0] as int):
			# A round, or a wrench. Which one is a guess and it is allowed to be one:
			# the Simulation records damage, not who dealt it.
			cues.append(
				Cue.new(
					SoundBank.WEAPON_HIT if swung_recently else SoundBank.WEAPON_IMPACT,
					state[2] as Vector3,
					true
				)
			)
		if (state[1] as bool) and not (before[1] as bool) \
				and _cooled_down("enemy:%d" % serial, now.tick):
			cues.append(Cue.new(SoundBank.ENEMY_ATTACK, state[2] as Vector3, true))

	for serial: int in was.enemies.keys():
		if now.enemies.has(serial):
			continue
		# The last position it was seen at, which is where it died.
		cues.append(
			Cue.new(SoundBank.ENEMY_DEATH, (was.enemies[serial] as Array)[2] as Vector3, true)
		)


func _player_cues(sim: Simulation, was: Snapshot, now: Snapshot, cues: Array) -> void:
	# A shot is three layers started together: the body for the pressure, the crack
	# for the mechanism, the tail for the room. One file never sounds like a gun.
	# A melee weapon swings instead, and has nothing to layer.
	if now.player_shot_tick > was.player_shot_tick:
		if sim.query_player_weapon_is_melee(LOCAL_PLAYER):
			cues.append(Cue.new(SoundBank.WEAPON_SWING))
		else:
			cues.append(Cue.new(SoundBank.WEAPON_FIRE_BODY))
			cues.append(Cue.new(SoundBank.WEAPON_FIRE_CRACK))
			cues.append(Cue.new(SoundBank.WEAPON_FIRE_TAIL))

	# The Simulation has no reload and no magazine: a round leaves a player's pockets
	# the tick it is fired. So a reload is a player who **was** dry and now is not,
	# which is the same derivation `WeaponAnimator` makes — and the one going the
	# other way is worth hearing too, because a dry weapon mid-Wave is news.
	if not sim.query_player_weapon_is_melee(LOCAL_PLAYER):
		if was.shots_remaining == 0 and now.shots_remaining > 0:
			cues.append(Cue.new(SoundBank.WEAPON_RELOAD))
		elif was.shots_remaining > 0 and now.shots_remaining == 0:
			cues.append(Cue.new(SoundBank.WEAPON_DRY))

	if now.player_health < was.player_health:
		cues.append(Cue.new(SoundBank.PLAYER_HURT))
	# **On leaving their feet, not on going Downed**, and that is a bug fix rather than a
	# refinement. `query_player_is_downed` is **never true on a solo Run** — there is nobody to
	# revive you, so a solo player at zero health goes straight to dead (GLOSSARY.md) — so this
	# branch fired on no solo death ever, and the most consequential event in a Run was
	# completely silent. #54's own description credits it with a thud it never made.
	#
	# One edge covers both states, which is also the right thing to say about it: a body
	# hitting the deck sounds the same whether a teammate is coming for it or not, and a player
	# who goes Downed and *then* bleeds out has fallen once, so they thud once.
	if was.player_on_their_feet and not now.player_on_their_feet:
		cues.append(Cue.new(SoundBank.PLAYER_DOWN))
	if now.player_grounded and not was.player_grounded:
		cues.append(Cue.new(SoundBank.PLAYER_LAND))


## How far this player has walked since their last footstep, after appending a
## footstep to `cues` if they have gone a full stride.
##
## Gait from **distance**, not from a clock: a sprinting player steps faster
## without a second number, a player who stops mid-stride stops making noise, and a
## Downed one makes none at all. This is the only quantity in the file the
## Simulation does not hold, which is why it is the only one carried forward.
func _advance_stride(
	sim: Simulation, was: Snapshot, now: Snapshot, cues: Array, opening: bool
) -> float:
	if opening or not now.player_grounded or now.player_downed \
			or not sim.query_player_is_alive(LOCAL_PLAYER):
		return 0.0
	var travelled: Vector3 = now.player_position - was.player_position
	var stride: float = was.stride + Vector2(travelled.x, travelled.z).length()
	if stride < STRIDE_METRES:
		return stride
	cues.append(Cue.new(SoundBank.FOOTSTEP))
	return stride - STRIDE_METRES


## Whether enough ticks have passed since the last cue about `key` — and records
## this one if so. The cooldown is in **ticks**, so it is a function of the Run and
## not of how fast this machine draws.
func _cooled_down(key: String, tick: int) -> bool:
	var last: int = _cooldowns.get(key, -REPEAT_COOLDOWN_TICKS - 1) as int
	if tick - last < REPEAT_COOLDOWN_TICKS:
		return false
	if _cooldowns.size() >= COOLDOWN_KEYS_BEFORE_PRUNE:
		_prune_cooldowns(tick)
	_cooldowns[key] = tick
	return true


## Drop the keys that could not refuse anything any more.
##
## An Enemy serial is never reused and a Machine tile is reused rarely, so without
## this the bag grows for as long as the Run does. An entry older than the cooldown
## would return true on its next lookup anyway, so forgetting it changes nothing a
## player could hear — which is why this can be a blunt sweep rather than
## bookkeeping at every death.
func _prune_cooldowns(tick: int) -> void:
	var fresh: Dictionary = {}
	for key: String in _cooldowns.keys():
		if tick - (_cooldowns[key] as int) < REPEAT_COOLDOWN_TICKS:
			fresh[key] = _cooldowns[key]
	_cooldowns = fresh


## A fixed-point horizontal position as a world point on the ground plane.
##
## `Fixed.to_float` is the sanctioned crossing from the Simulation's integers into
## the renderer's floats (`game/world_view.gd`), and this and `_tile_centre` are
## the only two places in this file that cross it — both of them inside `_read`.
## Every branch above works on whatever `_read` produced and never sees a Fixed
## value at all.
func _ground(position: FixedVec2) -> Vector3:
	return Vector3(Fixed.to_float(position.x), 0.0, Fixed.to_float(position.z))


func _tile_centre(sim: Simulation, tile: Vector3i) -> Vector3:
	var centre: FixedVec2 = sim.query_tile_centre_metres(tile)
	return Vector3(
		Fixed.to_float(centre.x),
		Fixed.to_float(sim.query_layer_height_metres(tile.y)),
		Fixed.to_float(centre.z)
	)


## The middle of a Machine's **footprint**, which is where its noise comes from.
##
## Not its anchor tile: a footprint is anchored at a tile and grows along +x and +z
## (CLAUDE.md), so a Silo's anchor is three metres off the middle of the four-by-four
## body a player is standing at. At a twelve-metre unit size that is audible.
func _machine_centre(sim: Simulation, index: int) -> Vector3:
	var tile: Vector3i = sim.query_machine_tile(index)
	var footprint: Vector2i = sim.query_machine_footprint(index)
	var near: Vector3 = _tile_centre(sim, tile)
	var far: Vector3 = _tile_centre(
		sim, tile + Vector3i(maxi(footprint.x - 1, 0), 0, maxi(footprint.y - 1, 0))
	)
	return (near + far) * 0.5


## `floor_db` at `from` works, `ceiling_db` at `to` and beyond, straight line
## between. Linear in dB rather than in amplitude, which is how a fader behaves and
## therefore how a mix is reasoned about.
func _ramp(works: float, from: float, to: float, floor_db: float, ceiling_db: float) -> float:
	if works <= from:
		return floor_db
	if works >= to or to <= from:
		return ceiling_db
	return floor_db + (ceiling_db - floor_db) * (works - from) / (to - from)


# ── Seam three: the only part that needs an audio device ──────────────────────

## Stop every voice on the way out, and let go of its stream.
##
## A courtesy to the mixer rather than bookkeeping: a player torn down mid-buffer
## on a real audio driver is a click, and the ambience beds are deliberately never
## stopped while a Run is on (see `_sync_sustained`), so this is the only place
## they are.
##
## **It does not silence Godot's own exit warnings, and nothing here can.** A
## still-playing `AudioStreamPlayer` leaks its `AudioStreamPlaybackOggVorbis` at
## engine shutdown under the headless dummy audio driver — four ObjectDB instances
## and two resources per playing stream — and that is reproducible with a bare
## `AudioStreamPlayer` in an otherwise empty project, with none of this file
## involved. So `godot --headless --quit-after N` reports eight leaks for the two
## ambience beds. The test suite does not, because the tests exercise
## `cues_for_frame` and `ambience_db` and never need a voice at all.
func _exit_tree() -> void:
	for cue: String in _sustained.keys():
		var sustained: AudioStreamPlayer = _sustained[cue] as AudioStreamPlayer
		if sustained != null:
			sustained.stop()
			sustained.stream = null
	for voice: AudioStreamPlayer3D in _positional:
		voice.stop()
		voice.stream = null
	for local: AudioStreamPlayer in _local:
		local.stop()
		local.stream = null


func _build_voices() -> void:
	if _voices_built:
		return
	_voices_built = true
	for i: int in range(POSITIONAL_VOICES):
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.unit_size = VOICE_UNIT_SIZE
		voice.max_distance = VOICE_MAX_DISTANCE
		# Inverse-square is what a real source does and what a player's ear expects
		# of a Turret two hundred metres off; the alternative reads as everything
		# being equally close.
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(voice)
		_positional.append(voice)
	for i: int in range(LOCAL_VOICES):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(voice)
		_local.append(voice)


func _play(cue: Cue, tick: int) -> void:
	var stream: AudioStream = _bank.stream_for(cue.name, tick)
	if stream == null:
		# No hero take and no fallback either. An ordinary state for a clone with a
		# half-installed asset tree, and not worth a warning a player would see.
		return
	var volume: float = _bank.gain_db(cue.name) + cue.trim_db
	if cue.positional:
		var voice: AudioStreamPlayer3D = _free_positional()
		voice.stream = stream
		voice.volume_db = volume
		voice.global_position = cue.at
		voice.play()
		return
	var local: AudioStreamPlayer = _free_local()
	local.stream = stream
	local.volume_db = volume
	local.play()


## The first idle positional voice, or the one that has been playing longest.
##
## Stealing rather than dropping: at the Milestone 1 Enemy count under a full
## Factory the pool does run out, and the cue a player most wants to hear is the one
## that just happened rather than the one that started a second ago.
func _free_positional() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = _positional[0]
	var furthest_in: float = -1.0
	for voice: AudioStreamPlayer3D in _positional:
		if not voice.playing:
			return voice
		var position: float = voice.get_playback_position()
		if position > furthest_in:
			furthest_in = position
			oldest = voice
	return oldest


func _free_local() -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = _local[0]
	var furthest_in: float = -1.0
	for voice: AudioStreamPlayer in _local:
		if not voice.playing:
			return voice
		var position: float = voice.get_playback_position()
		if position > furthest_in:
			furthest_in = position
			oldest = voice
	return oldest


## Put the four sustained beds where the Run has them: the two Factory ambiences at
## whatever `ambience_db` says, the Telegraph klaxon and the Painting channel on or
## off.
##
## An ambience bed **starts when it first has a level and is then never stopped**,
## only taken to `SILENT_DB`. Two halves, and both matter:
##
## * Not stopped, because a bed restarted every time a Miner runs out of ore would
##   click, and a Factory that grows and starves and grows again does that often.
## * Not started before it has a level, because a Run opens on an empty Map with no
##   machinery to hear — and two Vorbis decoders running at silence from the first
##   frame are two decoders doing nothing.
func _sync_sustained(sim: Simulation) -> void:
	_build_voices()
	var levels: PackedFloat32Array = ambience_db(sim)
	_hold(SoundBank.FACTORY_BED, levels[0] > SILENT_DB, levels[0], true)
	_hold(SoundBank.FACTORY_BUSY, levels[1] > SILENT_DB, levels[1], true)

	var running: PackedStringArray = sustained_cues(sim)
	for cue: String in [SoundBank.TELEGRAPH_KLAXON, SoundBank.PAINT_LOOP]:
		_hold(cue, running.has(cue), _bank.gain_db(cue))


## Hold `cue` playing or stopped at `volume_db`, building its player the first time
## it is wanted. `keep_running` is for the ambience beds: once started they are
## only ever turned down, never stopped.
func _hold(cue: String, wanted: bool, volume_db: float, keep_running: bool = false) -> void:
	var voice: AudioStreamPlayer = _sustained.get(cue, null) as AudioStreamPlayer
	if voice == null:
		if not wanted:
			# Nothing to build yet. A bed with no level and a klaxon nobody has
			# triggered both cost a decoder and a node they have not earned.
			return
		var stream: AudioStream = _bank.stream_for(cue)
		if stream == null:
			return
		voice = AudioStreamPlayer.new()
		voice.stream = stream
		add_child(voice)
		_sustained[cue] = voice
	voice.volume_db = volume_db
	if wanted and not voice.playing:
		voice.play()
	elif not wanted and voice.playing and not keep_running:
		voice.stop()
