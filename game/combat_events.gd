## What happened in a fight, derived from what the Simulation says changed.
##
## #69. Every other fact a shot needs is already a projection — where a Turret is, when it last
## fired, what it is aiming at, where an Enemy stands — and **a tick number is already an
## event**: "this gun last fired on tick 4812" is a change reported as a number, so a renderer
## answers "did it just go off" with a subtraction and remembers nothing. That is why
## `game/world_view.gd` draws a muzzle flash without this file's help.
##
## One fact is not available that way. **Where a round went and what it struck is known inside
## `_fight` and `_fire` and told to nobody**: `query_enemy_health` reports what an Enemy's
## health *is*, and a round landing is a change in it. The same is true of a death — an Enemy
## reduced to nothing is removed from the arrays on the tick it dies, so by the time anything
## can ask, there is nothing left to ask about.
##
## ## Why this diffs rather than the Simulation exposing the outcome
##
## The honest alternative is for `_resolve_a_hit` to record what it did, and it was rejected on
## the same grounds #54 rejected recording what killed a player: it is new hashed, saved and
## replayed state, in the Simulation, bought for a mark on the screen. Nothing about the Run
## would change and `hash()` would — which is the one price this project charges reluctantly.
##
## And it is not needed, because the evidence is complete. A round that landed left a smaller
## number behind it; a round that killed left a serial absent from a set that only ever grows
## by appending. `game/audio_director.gd` has read exactly that since #21 — it snapshots
## `[health, attacking, position]` per Enemy serial, plays a death cue off a serial that has
## gone, and already attributes a hit to a melee swing within `MELEE_WINDOW_TICKS` — so this
## is that file's design pointed at the picture rather than at the sound, and the precedent is
## literal rather than analogous.
##
## ## It reads, it never writes, and it remembers nothing about the Run
##
## ADR 0001 makes the Godot layer an input producer and a state reader. The snapshot here is
## the same category of thing as `TickPump`'s leftover frame time and `AudioDirector`'s own: a
## reading on its way through, not a fact about the world. Nothing is ever consulted about
## whether something is true, the Simulation stays the authority, and
## `tests/cases/test_combat_events.gd` asserts that asking leaves the state hash where it was.
##
## ## Nothing is timed by a clock
##
## Every event carries **the tick it happened on**, and a consumer works out how old a mark is
## by subtracting that from `query_tick`. So a frame that stepped nothing sees the same events
## at the same ages, and two Runs down the same Input Action script look the same — the rule
## `WorldView.SCANNER_PERIOD_TICKS` states and `WeaponViewmodel` already keeps for animation.
##
## Where the tick comes from is worth knowing. **An attributed event is stamped with the tick
## its own shot was fired on**, read back out of `query_turret_last_shot_tick` or
## `query_player_last_shot_tick`, so it is a Simulation quantity and not a reading of when a
## frame happened to look. An event nothing can be attributed to — a melee swing, an Artillery
## Barrage, a Breaker's bite — is stamped with the last tick the Simulation executed, which is
## the renderer's own best reading and is exact whenever a frame has stepped one tick. Nothing
## `WorldView` draws is unattributed, so the inexact case is not reachable from anything on
## screen; it is reported anyway because the next thing to read this file is #70, which is
## about an Enemy's own body rather than about who shot it.
class_name CombatEvents
extends RefCounted

## What happened. Deliberately about the thing it happened *to* rather than about the weapon:
## one round, one bite and one Charge of a Barrage all reduce an Enemy's health, and a consumer
## that needed to tell them apart would be asking this file to re-derive `_resolve_a_hit`.
enum Kind {
	## Something took health off an Enemy and it is still standing.
	HIT,
	## Something took the last of an Enemy's health. Reported with where it was standing when
	## it was last seen alive, because by now it is gone from the arrays entirely.
	KILLED,
}

## Who did it, where that can be told from the queries alone.
enum From {
	## Nothing fired on the tick this happened, or nothing that fired was aiming at it. A
	## wrench, a Barrage, a Breaker's own bite — all real, none of them a shot with a line of
	## flight anything could draw.
	NOBODY,
	TURRET,
	PLAYER,
}

## How long an event stays available to be asked about, in ticks. **As long as the
## longest-lived mark drawn off one**, which is what this number has always meant and is now
## `WorldView.DEATH_MARK_TICKS` — #70's soot on the ground, two and a half seconds. It was 60
## while every mark was a flash or a burst. Short enough that a forty-hour Run accumulates
## nothing either way: the list is swept every time it is observed.
const MEMORY_TICKS: int = 150

## Which player's trigger is read. One for now; co-op makes it the local id, and in lockstep
## every other player's shots are visible through exactly the same queries.
const LOCAL_PLAYER: int = 0


## One thing that happened, as a plain bag of values with no behaviour — so a test can read one
## without a renderer attached and a consumer can draw one without asking the Simulation
## anything further.
class Event extends RefCounted:
	var kind: int = Kind.HIT
	## The Enemy it happened to, by **serial** rather than by index. An index shifts the moment
	## anything dies (`_remove_enemy` closes the gap); a serial is issued once and never reused
	## (#9), so it either names the Crawler this was about or names nothing.
	var serial: int = -1
	## Which kind of Enemy, so a consumer can size a mark against the body it is about without
	## resolving a serial that may already be gone.
	var enemy_kind: int = -1
	## Where it happened, in world metres, at the middle of the height a round is resolved
	## against — so a mark about a hit stands on the thing that was hit rather than at its feet.
	var at: Vector3 = Vector3.ZERO
	## How many hit points came off. Always positive; a `KILLED` carries the points of the blow
	## that finished it.
	var points: int = 0
	## The tick it happened on. See the file header: a shot's own stamp where there is one, and
	## the last tick the Simulation executed where there is not.
	var tick: int = -1
	var from: int = From.NOBODY
	## The Machine index of the Turret, or the id of the player. -1 for `From.NOBODY`.
	var from_index: int = -1


## Enemy serial -> `[health, enemy kind, where it is]`, as of the last time this was observed.
var _enemies: Dictionary = {}

## Machine index -> the serial that Turret was aiming at, as of the last time this was observed.
##
## Held because of the one case that would otherwise go unattributed: `_fire` removes an Enemy
## it reduced to nothing **and clears that serial off every Turret holding it**, in the same
## tick, so a Turret's killing shot is a shot whose target is already unresolvable by the time
## anything outside the façade can look. Last frame's answer is the only evidence there is.
var _turret_targets: Dictionary = {}

## The tick the Simulation had reached when this was last observed, so a frame that stepped
## nothing diffs nothing.
var _observed_tick: int = -1

var _events: Array[Event] = []


## Diffs what the queries say now against what they said last time, and appends whatever
## changed. Call once a frame, before anything reads `events()`.
##
## A frame that stepped no ticks is a no-op in both directions: nothing is appended, and
## nothing already reported is forgotten, so the marks a consumer draws do not flicker on a
## frame the Simulation did not advance.
func observe(sim: Simulation) -> void:
	if sim == null:
		return
	var tick: int = sim.query_tick()
	if tick == _observed_tick:
		return

	var was: Dictionary = _enemies
	var shooters: Dictionary = _targets_of_the_guns_that_fired(sim)
	_enemies = _enemies_now(sim)

	if _observed_tick >= 0:
		# Only once there is something to diff against. The first observation of a Run — or of
		# a Simulation that has just been loaded from a save — establishes the snapshot and
		# reports nothing, because every Enemy standing on it would otherwise read as having
		# just appeared.
		_report_what_changed(sim, was, shooters, tick)

	_turret_targets = _turrets_aiming_now(sim)
	_observed_tick = tick
	_forget_what_is_too_old(tick)


## Everything that happened recently, oldest first. Each event carries the tick it happened on;
## how long a mark lives is the consumer's decision and not this file's.
func events() -> Array[Event]:
	return _events


## Every Enemy's health, kind and position, keyed by the serial that outlives its index.
func _enemies_now(sim: Simulation) -> Dictionary:
	var now: Dictionary = {}
	for index: int in range(sim.query_enemy_count()):
		now[sim.query_enemy_serial(index)] = [
			sim.query_enemy_health(index),
			sim.query_enemy_kind(index),
			_enemy_centre(sim, index),
		]
	return now


## Where an Enemy's body is, at the middle of the height a round is resolved against.
## `query_enemy_hit_height_metres` is the very number `WorldView` scales the drawn body by, so
## the mark and the thing it is about are one size.
func _enemy_centre(sim: Simulation, index: int) -> Vector3:
	var at: FixedVec2 = sim.query_enemy_position_metres(index)
	return Vector3(
		Fixed.to_float(at.x),
		Fixed.to_float(sim.query_enemy_hit_height_metres(index)) * 0.5,
		Fixed.to_float(at.z)
	)


## What each Turret is aiming at now, keyed by Machine index. Repair Pylons are left out: a
## Pylon holds no target at all, because a Machine is an index and indices shift.
func _turrets_aiming_now(sim: Simulation) -> Dictionary:
	var aiming: Dictionary = {}
	for index: int in range(sim.query_machine_count()):
		if not sim.query_machine_is_turret(index):
			continue
		if sim.query_machine_is_repair_pylon(index):
			continue
		aiming[index] = sim.query_turret_target_serial(index)
	return aiming


## Serial -> `[From, index, tick]` for every gun that went off since the last observation, as a
## claim on whatever that gun was pointing at.
##
## **A Turret's claim is its target, this frame or last.** `_mend` stamps the very same
## `_turret_last_shot_tick` that `_fire` does, so Pylons are excluded by name; and a killing
## shot clears its own target, so last frame's answer is consulted too.
##
## Walked in Machine index order on a first-claim-wins basis, so two Turrets that fired at the
## same Crawler on the same tick hand the shot to the lower index on every client — the rule
## `_acquire_target` already obeys.
func _targets_of_the_guns_that_fired(sim: Simulation) -> Dictionary:
	var claims: Dictionary = {}
	var tick: int = sim.query_tick()
	for index: int in range(sim.query_machine_count()):
		if not sim.query_machine_is_turret(index):
			continue
		if sim.query_machine_is_repair_pylon(index):
			continue
		var fired: int = sim.query_turret_last_shot_tick(index)
		if fired < _observed_tick or fired < 0 or fired >= tick:
			continue
		var at: int = sim.query_turret_target_serial(index)
		if at == -1:
			at = _turret_targets.get(index, -1) as int
		if at == -1 or claims.has(at):
			continue
		claims[at] = [From.TURRET, index, fired]
	return claims


## Appends one event per Enemy whose health went down, and one per Enemy that is no longer
## there at all.
##
## **Only downwards.** A wrench and a Repair Pylon put health back and a Factory under repair
## is not a Factory being shot at — the clause `AudioDirector` already carries for a Machine's
## health, applied to an Enemy's.
func _report_what_changed(
	sim: Simulation, was: Dictionary, shooters: Dictionary, tick: int
) -> void:
	# Serials rather than indices, sorted, because a Dictionary has no order a lockstep layer
	# may iterate — rule 4 of ADR 0002, which this file obeys even though it is presentation.
	var serials: Array = _enemies.keys()
	serials.sort()
	for serial: int in serials:
		if not was.has(serial):
			continue
		var before: Array = was[serial] as Array
		var now: Array = _enemies[serial] as Array
		var lost: int = (before[0] as int) - (now[0] as int)
		if lost <= 0:
			continue
		_append(sim, Kind.HIT, serial, now[1] as int, now[2] as Vector3, lost, shooters, tick)

	var gone: Array = was.keys()
	gone.sort()
	for serial: int in gone:
		if _enemies.has(serial):
			continue
		var last_seen: Array = was[serial] as Array
		_append(
			sim,
			Kind.KILLED,
			serial,
			last_seen[1] as int,
			last_seen[2] as Vector3,
			maxi(last_seen[0] as int, 1),
			shooters,
			tick
		)


## Records one event, attributed to whichever gun has a claim on the Enemy it happened to.
##
## The player is the fallback rather than the first guess, and the order matters: a Turret's
## claim is evidence — it was aiming at *this* Crawler — where a player's trigger says only
## that a round left the barrel, since no query reports where it went. So a tick on which both
## fired gives the hit to the Turret that was pointing at it, and the player takes the hits
## nothing else can account for.
func _append(
	sim: Simulation,
	kind: int,
	serial: int,
	enemy_kind: int,
	at: Vector3,
	points: int,
	shooters: Dictionary,
	tick: int
) -> void:
	var event: Event = Event.new()
	event.kind = kind
	event.serial = serial
	event.enemy_kind = enemy_kind
	event.at = at
	event.points = points
	# The last tick the Simulation executed, which is what `step` leaves behind: `_tick` is
	# incremented last, so the freshest thing anything outside the façade can see is one tick
	# old. Overwritten below by the firing tick of whatever is credited with it.
	event.tick = tick - 1

	if shooters.has(serial):
		var claim: Array = shooters[serial] as Array
		event.from = claim[0] as int
		event.from_index = claim[1] as int
		event.tick = claim[2] as int
		_events.append(event)
		return

	var pulled: int = sim.query_player_last_shot_tick(LOCAL_PLAYER)
	if pulled >= _observed_tick and pulled >= 0 and pulled < tick and _is_shooting(sim):
		event.from = From.PLAYER
		event.from_index = LOCAL_PLAYER
		event.tick = pulled
	_events.append(event)


## Whether the local player's weapon throws something, rather than swinging. A melee hit is a
## real hit and is reported — it is simply not a shot, so nothing should draw a line of flight
## for it, and `From.NOBODY` is how this file says so without inventing a third kind of shooter.
func _is_shooting(sim: Simulation) -> bool:
	var weapon: GearDefinition = sim.query_definitions().gear(
		sim.query_player_weapon(LOCAL_PLAYER)
	)
	return weapon != null and weapon.is_ranged()


## Drops events older than `MEMORY_TICKS`. Swept on every observation rather than on a cap, so a
## Run that fires nothing for an hour is holding nothing.
func _forget_what_is_too_old(tick: int) -> void:
	var kept: Array[Event] = []
	for event: Event in _events:
		if tick - event.tick < MEMORY_TICKS:
			kept.append(event)
	_events = kept
