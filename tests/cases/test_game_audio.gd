## The sound the Run makes: which cue fires on what, and what happens when the
## hero takes are not on this machine.
##
## DESIGN.md: "Each diegetic control therefore needs its hero sound before it
## ships. Audio is load-bearing here, not polish." So this file asserts that as a
## property rather than leaving it to somebody's ears — **every one of the five
## controls it names makes a distinct noise**, and every one of those noises
## resolves to a file that exists.
##
## Three seams, and none of them is an audio device:
##
## * `SoundBank` — "given the cue `silo_commit`, which file?". The interesting
##   claim is the licence one: the hero takes are cut out of a non-redistributable
##   bundle into a gitignored directory outside the shipping tree, so on most clones
##   they are absent and **every cue has to fall back to a committed CC0 one**. A
##   clone without the bundle gets a Kenney lever, not a silent one.
## * `AudioDirector.cues_for_frame` — "given what changed, what fires". A `RefCounted`
##   diff over query results, so every cue a player will ever hear is a cheap
##   assertion here rather than something only a microphone could catch.
## * `AudioDirector.ambience_db` — how loud the two Factory beds sit. "Machinery
##   ambience scales with Factory size" is a function of the Run and therefore a
##   test.
##
## And the one that matters most for the architecture: **listening to a Run does
## not change it**. The director reads queries and nothing else, so the same Input
## Action script leaves the same state hash whether anything was listening or not.
extends TestCase

# ── Fixtures ──────────────────────────────────────────────────────────────────
#
# Its own content, for the reason `test_silo.gd` brings its own: the shipped chain
# into a Silo is a Miner, a Smelter, an Ammo Press and twenty rounds a Charge,
# which is a minute of game time before the first assertion — and a test nobody
# runs asserts nothing. What is not altered is the shape. A Silo is a row with a
# Recipe fed by a Belt; a Boiler is a generator burning a Belt-fed fuel.

const AUDIO_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
plate_seam_mk1,Plate Seam,miner,2,2,2,0,0,400,1,0,0,0,0,dig_plate,
coal_seam_mk1,Coal Seam,miner,2,2,2,0,0,400,1,0,0,0,0,dig_coal,
boiler_mk1,Boiler Mk1,generator,2,2,2.2,0,600,450,0,0,0,0,0,burn_coal,
mg_turret_mk1,MG Turret Mk1,turret,2,2,2,0,0,350,0,8,15,0,0,fire_mg,
silo_mk1,Silo Mk1,silo,4,4,2.2,0,0,900,0,0,0,0,4,assemble_charge,
"""

const AUDIO_RECIPES: String = """id,display_name,inputs,outputs,seconds
assemble_charge,Assemble Charge,iron_plate:2,,0.5
dig_plate,Dig Plate,,iron_plate:1,0.1
dig_coal,Dig Coal,,coal:1,0.2
burn_coal,Burn Coal,coal:1,,1.0
fire_mg,Fire MG,ammunition:1,,0.25
"""

## One Crawler a Breach, flat. Nothing here is about the schedule.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

## A tier the opening Factory can pay off by hand, so that handing goods over is one
## step rather than a production chain. It has to unlock something or the loader
## refuses it, and a Gear component is the one thing nothing here reads.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_open,Open Licence,1,iron_plate:4,,mg_drum_magazine,
"""

const STOCKED_BILL: String = "iron_plate:400;ammunition:400"

## The dial's reach, stretched so a player standing on the tile they will paint can
## also work the Silo beside them. `test_silo.gd` owns the shipped four metres.
const SHIPPED_DIAL_REACH: String = "load_reach_metres = 4"
const REACHABLE_DIAL_REACH: String = "load_reach_metres = 12"

## The Nest's reach, stretched for the same reason: a Delivery test should be about
## the intake and not about walking twenty tiles.
const SHIPPED_DELIVERY_REACH: String = "delivery_reach_metres = 5"
const REACHABLE_DELIVERY_REACH: String = "delivery_reach_metres = 60"

## A Telegraph short enough to live inside a test, and long enough to still be
## running on the frame after the lever is pulled.
const SHIPPED_TELEGRAPH: String = "telegraph_seconds = 12"
const QUICK_TELEGRAPH: String = "telegraph_seconds = 3"

## This file brings its own Machine table — none of its five rows is a shipped id — so the
## opening selection has to be one of *these* (#55). `player.starting_machine` names a row
## in `machines.csv` and a set that names a row it has not got is an error carrying no
## definitions at all, which is the rule working rather than failing: a Build Gun pointed
## at a Machine the content does not define is not a thing to let through quietly.
##
## The plate seam, because it is this table's stand-in for the Miner and so the nearest
## thing to what the shipped file means. Nothing here asserts on the selection; what it has
## to be is *present*.
const AUDIO_STARTING_MACHINE: String = "plate_seam_mk1"

const GROUND: int = WorldGrid.GROUND_LAYER
const SILO_TILE: Vector3i = Vector3i(4, GROUND, 4)
const BOILER_TILE: Vector3i = Vector3i(-8, GROUND, 8)


func _content(overrides: Array = []) -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.machines = AUDIO_MACHINES
	fixture.recipes = AUDIO_RECIPES
	fixture.waves = ONE_CRAWLER
	fixture.deliveries = DELIVERIES
	return (
		fixture
		. tune(
			[
				[SHIPPED_DIAL_REACH, REACHABLE_DIAL_REACH],
				[SHIPPED_DELIVERY_REACH, REACHABLE_DELIVERY_REACH],
				[SHIPPED_TELEGRAPH, QUICK_TELEGRAPH],
			]
		)
		. stock(STOCKED_BILL)
		. starting_machine(AUDIO_STARTING_MACHINE)
		. tune(overrides)
		. definitions()
	)


## The Map. The Nest is up the +z lane, a plate seam feeds the Silo and a coal seam
## feeds the Boiler, and the player opens standing on tile (0,0) — which is the tile
## they paint, because a player must stand at the target.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, GROUND, 20)
	layout.add_node(Vector3i(4, GROUND, 12), "iron_plate", 1)
	layout.add_node(Vector3i(-8, GROUND, 4), "coal", 1)
	layout.sort_nodes()
	return layout


## The same Map with a Breach four tiles down the lane, so there is somewhere for a
## Wave to come out of. Separate, because a Breach means Crawlers, and a test about a
## dial should not also be a test about being interrupted.
func _breach_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.add_breach(Vector3i(0, GROUND, -4))
	layout.sort_breaches()
	return layout


func _sim(overrides: Array = []) -> Simulation:
	return Simulation.new(7, 1, _content(overrides), _layout())


## A Run on a Map with a Breach, which is the only kind that has Waves to call.
func _sim_with_a_breach() -> Simulation:
	return Simulation.new(7, 1, _content(), _breach_layout())


## A Silo at (4,4) fed by a Belt out of the plate seam at (4,12).
func _fed_silo(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("silo_mk1"), SILO_TILE),
		InputAction.build_machine(
			0, definitions.machine_index("plate_seam_mk1"), Vector3i(4, GROUND, 12)
		),
		InputAction.build_belt(0, Vector3i(4, GROUND, 11), Vector3i(4, GROUND, 8)),
	])


## A Boiler at (-8,8) with a coal seam at (-8,4) and a Belt between them. Returns
## the Belt's first tile, so a test can demolish it and watch the fire go out.
func _fed_boiler(sim: Simulation) -> Vector3i:
	var definitions: Definitions = sim.query_definitions()
	var belt_from: Vector3i = Vector3i(-8, GROUND, 6)
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("boiler_mk1"), BOILER_TILE),
		InputAction.build_machine(
			0, definitions.machine_index("coal_seam_mk1"), Vector3i(-8, GROUND, 4)
		),
		InputAction.build_belt(0, belt_from, Vector3i(-8, GROUND, 7)),
	])
	return belt_from


## Steps until the Silo is holding `wanted` Charges. Bounded, like every wait in
## this suite: an unbounded `while` is a hung suite rather than a failing one.
func _step_until_charges(sim: Simulation, wanted: int, limit: int = 1800) -> void:
	var ticks: int = 0
	while sim.query_silo_charges(0) < wanted and ticks < limit:
		sim.step([])
		ticks += 1


## The tile the player opens standing on, and therefore the only tile they can paint.
func _target(sim: Simulation) -> Vector3i:
	var here: FixedVec2 = sim.query_player_position(0)
	return WorldGrid.tile_at_metres(here.x, here.z)


## Every director this test method made, so `after_each` can free them.
##
## `AudioDirector` is a `Node3D` and these are never put in a tree, so nothing else
## would — and a leaked node is reported at engine exit as a warning that reads like
## a defect in the thing under test.
var _directors: Array[AudioDirector] = []


func after_each() -> void:
	for director: AudioDirector in _directors:
		director.free()
	_directors.clear()


## A director with nothing in its tree and nothing to hear yet.
func _director() -> AudioDirector:
	var director: AudioDirector = AudioDirector.new()
	_directors.append(director)
	return director


## A director that has already seen this Run, so the next `cues_for_frame` reports
## changes rather than the whole world arriving at once.
func _primed(sim: Simulation) -> AudioDirector:
	var director: AudioDirector = _director()
	director.cues_for_frame(sim)
	return director


## The cue names one frame produced.
func _names(cues: Array) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for cue: AudioDirector.Cue in cues:
		names.append(cue.name)
	return names


## Steps `sim` `ticks` times, gathering every cue the director reported along the
## way. One `cues_for_frame` per tick, which is the worst case for the diffing and
## therefore the right thing to assert against.
func _listen(director: AudioDirector, sim: Simulation, ticks: int, actions: Array = []) -> PackedStringArray:
	var heard: PackedStringArray = PackedStringArray()
	for i: int in range(ticks):
		sim.step(actions)
		heard.append_array(_names(director.cues_for_frame(sim)))
	return heard


# ── The catalogue ─────────────────────────────────────────────────────────────

func test_every_cue_resolves_to_a_file_that_exists() -> void:
	var bank: SoundBank = SoundBank.new()
	var cues: PackedStringArray = bank.cues()
	assert_true(cues.size() > 20, "the catalogue is not a stub: %d cues" % cues.size())

	for cue: String in cues:
		var paths: PackedStringArray = bank.paths_for(cue)
		if not assert_false(paths.is_empty(), "'%s' resolves to nothing at all" % cue):
			continue
		for path: String in paths:
			assert_true(
				FileAccess.file_exists(path),
				"'%s' names a file that is not there: %s" % [cue, path]
			)


## The claim the licence makes load-bearing. The hero takes come out of a bundle
## that may not be redistributed and are therefore absent from most clones, so a
## cue with no committed fallback would be a cue that is silent for almost
## everybody.
func test_every_cue_falls_back_to_something_committed() -> void:
	var bank: SoundBank = SoundBank.new()
	for cue: String in bank.cues():
		var fallbacks: PackedStringArray = bank.committed_paths(cue)
		if not assert_false(fallbacks.is_empty(), "'%s' has no committed fallback" % cue):
			continue
		for path: String in fallbacks:
			assert_true(
				path.begins_with("res://assets/audio/"),
				"a fallback must be committed CC0, not %s" % path
			)
			assert_true(FileAccess.file_exists(path), "no such fallback: %s" % path)


func test_the_hero_cues_live_outside_the_shipping_tree() -> void:
	# The same rule `WeaponViewmodel.WEAPON_BODY_DIRECTORY` obeys, and for the same
	# reason: a cut from a non-redistributable recording is a derivative of it and is
	# exactly as forbidden as the recording. `.gitignore` excludes the whole of
	# `assets_licensed/` and the licence guard blocks it.
	assert_true(
		SoundBank.HERO_DIRECTORY.begins_with("res://assets_licensed/"),
		"the Sonniss cuts must never be inside assets/"
	)
	assert_true(
		FileAccess.file_exists("res://assets_licensed/.gdignore"),
		"and Godot must be told not to walk that tree"
	)


## Issue #21: "Every Diegetic control has a distinct hero sound." Distinct, so the
## cues are compared against each other and not merely counted.
func test_the_five_diegetic_controls_each_have_their_own_sound() -> void:
	var bank: SoundBank = SoundBank.new()
	var seen: Dictionary = {}
	for cue: String in SoundBank.DIEGETIC_CUES:
		var paths: PackedStringArray = bank.paths_for(cue)
		if not assert_false(paths.is_empty(), "the diegetic cue '%s' resolves to nothing" % cue):
			continue
		var first: String = paths[0]
		assert_false(
			seen.has(first),
			"'%s' and '%s' are the same sound; a diegetic control needs its own"
				% [cue, seen.get(first, "")]
		)
		seen[first] = cue

	# Named individually, because the list in `DIEGETIC_CUES` is the thing under
	# test: a future edit that quietly drops one of the five should fail here.
	for required: String in [
		SoundBank.SILO_DIAL_SHELL,
		SoundBank.SILO_DIAL_CHARGES,
		SoundBank.SILO_COMMIT,
		SoundBank.PAINT_BEGIN,
		SoundBank.BOILER_STARTUP,
		SoundBank.BOILER_RELIEF,
		SoundBank.DELIVERY_INTAKE,
		SoundBank.CALL_WAVE_LEVER,
	]:
		assert_true(
			SoundBank.DIEGETIC_CUES.has(required),
			"%s is one of DESIGN.md's diegetic controls and must stay on the list" % required
		)


## Variation stops a Factory under fire sounding like one sample on repeat, and it
## is chosen by tick so that two Runs down the same script sound the same. The same
## rule `WeaponViewmodel` keeps for animation.
func test_variation_is_chosen_by_tick_and_not_at_random() -> void:
	var bank: SoundBank = SoundBank.new()
	# A cue with several committed takes, asked about with the bundle's hero take
	# deliberately out of the picture: `FOOTSTEP` has no hero take at all, because
	# the bundle ships no footsteps.
	var paths: PackedStringArray = bank.paths_for(SoundBank.FOOTSTEP)
	if not assert_true(paths.size() > 1, "footsteps must have several takes"):
		return

	var at_a_tick: AudioStream = bank.stream_for(SoundBank.FOOTSTEP, 12)
	assert_eq(
		bank.stream_for(SoundBank.FOOTSTEP, 12),
		at_a_tick,
		"the same tick must choose the same take, so a replay sounds the same twice"
	)
	var differed: bool = false
	for tick: int in range(paths.size()):
		if bank.stream_for(SoundBank.FOOTSTEP, tick) != at_a_tick:
			differed = true
	assert_true(differed, "and different ticks must choose differently, or there is no variation")


## #35's playtest, in the player's words: *"knife sound is too loud and too generic
## (needs variance)"*. The wrench is the weapon a Run opens with, so its swing is the
## sound a new player hears most often in the game, and it had exactly one committed
## take — one sample, on every swing, for the whole Run.
##
## Asserted about the **committed** takes rather than about whatever this machine has,
## because the hero take is deliberately one chosen recording and is absent from almost
## every clone: what nearly everybody actually hears is this list.
func test_the_cues_a_player_hears_over_and_over_have_more_than_one_take() -> void:
	var bank: SoundBank = SoundBank.new()
	# The cues a single Wave fires dozens of times: the weapon in hand, what it lands on,
	# and the Enemy answering. A second take is the cheapest possible fix for a sound
	# wearing out, and `tick % count` is the mechanism.
	for cue: String in [
		SoundBank.WEAPON_SWING,
		SoundBank.WEAPON_HIT,
		SoundBank.WEAPON_IMPACT,
		SoundBank.ENEMY_ATTACK,
		SoundBank.ENEMY_DEATH,
		SoundBank.FOOTSTEP,
		SoundBank.PLAYER_LAND,
	]:
		assert_true(
			bank.committed_paths(cue).size() > 1,
			"'%s' is heard over and over and has one take, so it is a machine gun of one"
				% cue
		)


## *"the middle core hum is too loud"* — the Factory's ambience beds, which a player
## standing at the Nest hears as coming from it.
##
## **A bed is the floor of the mix**, and that is the whole claim: it is the thing every
## other sound sits on top of, so it has to be quieter than the quietest of them. It was
## not — the quiet bed's ceiling was 3 dB *above* a footstep — and `ambience_db` ramps
## *up* to these figures as the Factory grows, so the ceiling is what a full Factory
## actually sustains rather than a worst case.
func test_the_ambience_beds_sit_under_everything_they_are_a_bed_for() -> void:
	# **The cues a bed carries are the one-shots**, which is what this always meant and
	# is now what it says. It excluded the two beds by name; it excludes everything
	# sustained, because a cue that runs continuously is in the same category a bed is
	# and is mixed against the same question. #42 made that concrete: the Telegraph's
	# cue runs for a minute at a time and is deliberately *at* bed level, and naming the
	# beds rather than their category would have made that a failure here instead of the
	# decision it is. `LOOPING_CUES` is the category and `SoundBank` already owns it.
	var bank: SoundBank = SoundBank.new()
	var beds: Array = [SoundBank.FACTORY_BED, SoundBank.FACTORY_BUSY]
	var quietest_cue: float = 0.0
	var quietest_name: String = ""
	for cue: String in bank.cues():
		if SoundBank.LOOPING_CUES.has(cue):
			continue
		if quietest_name.is_empty() or bank.gain_db(cue) < quietest_cue:
			quietest_cue = bank.gain_db(cue)
			quietest_name = cue
	for bed: String in beds:
		assert_true(
			bank.gain_db(bed) < quietest_cue,
			(
				"'%s' sits at %f dB, at or above the quietest cue it carries ('%s', %f dB)"
				% [bed, bank.gain_db(bed), quietest_name, quietest_cue]
			)
		)


# ── The director: a Run opens silent ──────────────────────────────────────────

func test_a_run_opens_silent() -> void:
	var sim: Simulation = _sim()
	var director: AudioDirector = _director()
	assert_eq(
		_names(director.cues_for_frame(sim)).size(),
		0,
		"the opening frame must not announce every condition that has just become true"
	)
	assert_eq(
		_names(director.cues_for_frame(sim)).size(),
		0,
		"and a frame on which nothing changed makes no noise either"
	)


## `Main.load_run` replaces the Simulation outright, so the tick goes backwards and
## nothing about the difference between two unrelated states is worth announcing.
func test_a_resumed_run_does_not_announce_the_difference() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	for i: int in range(40):
		sim.step([])
	var director: AudioDirector = _primed(sim)

	var fresh: Simulation = _sim()
	assert_eq(
		_names(director.cues_for_frame(fresh)).size(),
		0,
		"a Run resumed under a listening director must not play a Factory being demolished"
	)


# ── Diegetic control 1: the Silo's loading cycle ──────────────────────────────

func test_the_silo_dial_clicks_once_for_each_half_of_it() -> void:
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()
	var first: int = 0
	var second: int = mini(1, definitions.stratagem_count() - 1)
	if not assert_true(second > first, "this needs two Stratagems to choose between"):
		return

	sim.step([InputAction.set_silo_dial(0, first, 1)])
	var director: AudioDirector = _primed(sim)

	sim.step([InputAction.set_silo_dial(0, second, 1)])
	assert_true(
		_names(director.cues_for_frame(sim)).has(SoundBank.SILO_DIAL_SHELL),
		"winding the shell selector clicks"
	)
	assert_false(
		_names(director.cues_for_frame(sim)).has(SoundBank.SILO_DIAL_SHELL),
		"and a dial nobody is touching stays quiet"
	)

	sim.step([InputAction.set_silo_dial(0, second, 3)])
	var heard: PackedStringArray = _names(director.cues_for_frame(sim))
	assert_true(heard.has(SoundBank.SILO_DIAL_CHARGES), "winding the charge counter ticks")
	assert_false(
		heard.has(SoundBank.SILO_DIAL_SHELL),
		"and it is a different sound from the selector: what goes in the tube and how"
			+ " much of it are two decisions"
	)


func test_committing_the_dial_lands_at_the_silo_and_lands_heavily() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 2)
	if not assert_true(sim.query_silo_charges(0) >= 2, "the Silo has to have something in it"):
		return

	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	sim.step([InputAction.set_silo_dial(0, barrage, 2)])
	var director: AudioDirector = _primed(sim)

	sim.step([InputAction.load_silo(0, SILO_TILE, barrage, 2)])
	if not assert_true(
		sim.query_silo_is_loaded(0),
		"the load has to have landed; refusal %d, player at %s, charges %d"
			% [
				sim.query_load_silo_refusal(0, SILO_TILE, barrage, 2),
				str(sim.query_player_position(0)),
				sim.query_silo_charges(0),
			]
	):
		return

	var cues: Array = director.cues_for_frame(sim)
	var heard: PackedStringArray = _names(cues)
	assert_true(heard.has(SoundBank.SILO_COMMIT), "the breech closes")
	assert_true(
		heard.has(SoundBank.SILO_COMMIT_BODY),
		"with a second layer under it: this is the one act a player cannot take back,"
			+ " and a single latch click does not carry that"
	)

	for cue: AudioDirector.Cue in cues:
		if cue.name != SoundBank.SILO_COMMIT:
			continue
		assert_true(cue.positional, "a Silo's breech is at the Silo, not in the player's ear")
		# The footprint centre, not the anchor tile: a four-by-four body's anchor is
		# three metres off the middle of it.
		var centre: FixedVec2 = sim.query_tile_centre_metres(SILO_TILE + Vector3i(1, 0, 1))
		assert_true(
			cue.at.distance_to(
				Vector3(Fixed.to_float(centre.x), 0.0, Fixed.to_float(centre.z))
			) < 1.5,
			"and at the middle of its footprint: %v" % cue.at
		)

	assert_false(
		_names(director.cues_for_frame(sim)).has(SoundBank.SILO_COMMIT),
		"a Silo that is already loaded is not loaded again every frame"
	)


# ── Diegetic control 2: Painting ──────────────────────────────────────────────

func test_painting_begins_holds_and_ends_two_different_ways() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 2)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	sim.step([
		InputAction.set_silo_dial(0, barrage, 1),
		InputAction.load_silo(0, SILO_TILE, barrage, 1),
	])
	if not assert_true(sim.query_silo_is_loaded(0), "a Painting needs a loaded Silo"):
		return

	var director: AudioDirector = _primed(sim)
	var target: Vector3i = _target(sim)

	sim.step([InputAction.paint(0, target)])
	assert_true(
		_names(director.cues_for_frame(sim)).has(SoundBank.PAINT_BEGIN),
		"the channel opens"
	)
	assert_true(
		director.sustained_cues(sim).has(SoundBank.PAINT_LOOP),
		"and holds a sustained layer for as long as the player is rooted, so the whole"
			+ " base can hear that somebody is committed"
	)

	# Letting go is itself the interruption, and the Charges are already gone.
	sim.step([])
	var heard: PackedStringArray = _names(director.cues_for_frame(sim))
	assert_true(heard.has(SoundBank.PAINT_INTERRUPTED), "letting go costs the Charge, audibly")
	assert_false(heard.has(SoundBank.PAINT_COMPLETE), "and is not mistaken for a Stratagem landing")
	assert_false(
		director.sustained_cues(sim).has(SoundBank.PAINT_LOOP),
		"the held layer stops with the channel"
	)


func test_a_painting_that_lands_sounds_different_from_one_that_does_not() -> void:
	var sim: Simulation = _sim()
	_fed_silo(sim)
	_step_until_charges(sim, 2)
	var barrage: int = sim.query_definitions().stratagem_index("artillery_barrage")
	sim.step([
		InputAction.set_silo_dial(0, barrage, 1),
		InputAction.load_silo(0, SILO_TILE, barrage, 1),
	])
	if not assert_true(sim.query_silo_is_loaded(0), "a Painting needs a loaded Silo"):
		return

	var director: AudioDirector = _primed(sim)
	var target: Vector3i = _target(sim)
	var required: int = sim.query_stratagem_paint_ticks(barrage)
	var heard: PackedStringArray = _listen(
		director, sim, required + 4, [InputAction.paint(0, target)]
	)
	assert_true(heard.has(SoundBank.PAINT_COMPLETE), "a channel served in full lands")
	assert_false(
		heard.has(SoundBank.PAINT_INTERRUPTED),
		"and nothing about it is reported as a loss"
	)
	assert_eq(
		sim.query_player_charges_wasted(0), 0, "which the Simulation agrees with"
	)


# ── Diegetic control 3: Boiler startup and pressure relief ────────────────────

func test_the_boiler_answers_its_own_coal() -> void:
	var sim: Simulation = _sim()
	var belt_from: Vector3i = _fed_boiler(sim)
	# A Boiler with no coal yet is starved, which is the state it is built in.
	if not assert_true(sim.query_machine_is_starved(0), "a dry Boiler reads as starved"):
		return

	var director: AudioDirector = _primed(sim)
	var lit: PackedStringArray = _listen(director, sim, 400)
	assert_true(
		lit.has(SoundBank.BOILER_STARTUP),
		"coal arriving is the fire catching, and that is a sound"
	)
	assert_false(sim.query_machine_is_starved(0), "and the Boiler is burning")

	# Take the Belt away and the fire goes out. Nodes never deplete, so this is the
	# only way to make a fed Boiler run dry inside a test — and it is also exactly
	# what a Breaker eating a Belt mid-Wave does.
	sim.step([InputAction.demolish(0, belt_from)])
	var vented: PackedStringArray = _listen(director, sim, 400)
	assert_true(
		vented.has(SoundBank.BOILER_RELIEF),
		"and running dry vents, which is the other half of the control DESIGN.md names"
	)


func test_a_boiler_that_has_just_been_built_does_not_vent() -> void:
	# A Machine's first sighting is a build, not a state change. Without this the
	# frame a Boiler is placed on would play a pressure relief it never had.
	var sim: Simulation = _sim()
	var director: AudioDirector = _primed(sim)
	_fed_boiler(sim)

	var heard: PackedStringArray = _names(director.cues_for_frame(sim))
	assert_true(heard.has(SoundBank.MACHINE_BUILT), "placing it is heard")
	assert_false(heard.has(SoundBank.BOILER_RELIEF), "but it has no pressure to lose yet")
	assert_false(heard.has(SoundBank.BOILER_STARTUP), "and no fire to catch")


# ── Diegetic control 4: the Delivery intake at the Nest ───────────────────────

func test_the_nest_answers_a_delivery() -> void:
	var sim: Simulation = _sim()
	# Depth gates what is possible to deliver (GLOSSARY.md), so the Factory has to be
	# mining at the tier the Delivery asks for before the Nest will take anything —
	# which is a Miner on a Node, running.
	_fed_silo(sim)
	var waited: int = 0
	while sim.query_depth_reached() < 1 and waited < 300:
		sim.step([])
		waited += 1
	if not assert_true(sim.query_depth_reached() >= 1, "the Factory has to be mining"):
		return

	var director: AudioDirector = _primed(sim)
	sim.step([InputAction.deliver_to_nest(0)])
	# The tier asks for four plate and the player is carrying hundreds, so one handover
	# pays it off outright — which also takes `query_delivery_goods_delivered` back to
	# zero, because that counter is about the tier that is *open*. Asserting on the
	# completed list instead is what makes this a test of the handover rather than of
	# an intermediate counter.
	if not assert_eq(
		sim.query_completed_deliveries().size(),
		1,
		"the Delivery has to have landed; refusal: %d" % sim.query_delivery_refusal(0)
	):
		return

	var cues: Array = director.cues_for_frame(sim)
	var heard: PackedStringArray = _names(cues)
	assert_true(heard.has(SoundBank.DELIVERY_INTAKE), "goods going in are heard")
	assert_true(
		heard.has(SoundBank.DELIVERY_COMPLETE),
		"and a tier opening rings: progression is physical, so it is audible"
	)

	var nest: FixedVec2 = sim.query_tile_centre_metres(sim.query_nest_tile())
	for cue: AudioDirector.Cue in cues:
		if cue.name != SoundBank.DELIVERY_INTAKE:
			continue
		assert_true(cue.positional, "the intake is at the Nest")
		assert_true(
			absf(cue.at.z - Fixed.to_float(nest.z)) < 3.0,
			"and the Nest is up the lane, not where the player is standing"
		)

	assert_false(
		_names(director.cues_for_frame(sim)).has(SoundBank.DELIVERY_INTAKE),
		"and the intake is the act of delivering, not the state of having delivered"
	)


# ── Diegetic control 5: the call-Wave-early lever, and the Telegraph ──────────

func test_the_lever_is_heard_and_so_is_the_klaxon_it_starts() -> void:
	# A Map with no Breach has no Waves at all, so there is no Wave to call: this is
	# the one test here that needs somewhere for Enemies to come out of.
	var sim: Simulation = _sim_with_a_breach()
	var director: AudioDirector = _primed(sim)
	if not assert_eq(
		sim.query_call_wave_early_refusal(0), 0, "the lever has to be available to pull"
	):
		return

	sim.step([InputAction.call_wave_early(0)])
	var heard: PackedStringArray = _names(director.cues_for_frame(sim))
	assert_true(
		heard.has(SoundBank.CALL_WAVE_LEVER),
		"throwing the lever is heard on the frame the hand moves, not when the Wave"
			+ " eventually lands a Telegraph later"
	)
	assert_true(
		director.sustained_cues(sim).has(SoundBank.TELEGRAPH_KLAXON),
		"and the klaxon runs for as long as the Telegraph does — a warning you cannot"
			+ " hear is not a warning"
	)

	# It stops when the Telegraph stops, rather than being a one-shot that might have
	# finished before the Wave arrived — and the Wave itself is heard when it arrives.
	var waiting: PackedStringArray = PackedStringArray()
	var ticks: int = 0
	while sim.query_wave_is_telegraphed() and ticks < 600:
		sim.step([])
		waiting.append_array(_names(director.cues_for_frame(sim)))
		ticks += 1
	assert_false(
		director.sustained_cues(sim).has(SoundBank.TELEGRAPH_KLAXON),
		"and it stops with it"
	)
	assert_true(
		waiting.has(SoundBank.WAVE_BEGIN) or _listen(director, sim, 20).has(SoundBank.WAVE_BEGIN),
		"and the Wave the lever called announces itself when it arrives"
	)


# ── Machinery ambience that scales with the Factory ───────────────────────────

func test_machinery_ambience_scales_with_the_factory() -> void:
	var sim: Simulation = _sim()
	var director: AudioDirector = _director()

	var empty: PackedFloat32Array = director.ambience_db(sim)
	assert_eq(empty[0], AudioDirector.SILENT_DB, "an empty Map has no machinery to hear")
	assert_eq(empty[1], AudioDirector.SILENT_DB, "and certainly no factory hall")

	_fed_silo(sim)
	_step_until_charges(sim, 1)
	var small: PackedFloat32Array = director.ambience_db(sim)
	assert_true(small[0] > AudioDirector.SILENT_DB, "two Machines and a Belt make a noise")

	_fed_boiler(sim)
	for i: int in range(400):
		sim.step([])
	var larger: PackedFloat32Array = director.ambience_db(sim)
	assert_true(
		larger[0] >= small[0] and director.factory_works(sim) > 0.0,
		"and a bigger Factory is louder, which is the whole claim: growth is audible"
	)
	assert_true(
		larger[1] > AudioDirector.SILENT_DB,
		"and once there is a production line the busy bed comes in on top: %.1f dB"
			% larger[1]
	)


func test_a_starved_factory_goes_quiet() -> void:
	# The measure is **working** Machines, not placed ones. A Factory that has run
	# out is a reading a player can act on.
	var sim: Simulation = _sim()
	var director: AudioDirector = _director()
	_fed_boiler(sim)
	for i: int in range(400):
		sim.step([])
	var burning: float = director.factory_works(sim)

	sim.step([InputAction.demolish(0, Vector3i(-8, GROUND, 6))])
	var starving: int = 0
	while starving < 600 and not sim.query_machine_is_starved(0):
		sim.step([])
		starving += 1
	assert_true(
		director.factory_works(sim) < burning,
		"a Boiler with nothing to burn adds nothing to the noise the Factory makes"
	)


# ── The architecture: listening changes nothing ───────────────────────────────

## The claim ADR 0001 and ADR 0002 together make, applied to sound: this layer
## reads queries and writes nothing, so a Run sounds like a Run without becoming a
## different Run. Two Simulations down the same intents, one observed and one not.
func test_listening_to_a_run_does_not_change_it() -> void:
	var heard: Simulation = _sim()
	var unheard: Simulation = _sim()
	var director: AudioDirector = _director()

	_fed_silo(heard)
	_fed_silo(unheard)
	_fed_boiler(heard)
	_fed_boiler(unheard)

	for i: int in range(300):
		heard.step([])
		unheard.step([])
		# The listening Run is read every tick, including the ambience and the
		# sustained beds, which is every query this layer makes.
		director.cues_for_frame(heard)
		director.ambience_db(heard)
		director.sustained_cues(heard)
		assert_eq(
			heard.hash(),
			unheard.hash(),
			"the state hash moved at tick %d because something listened" % heard.query_tick()
		)
		if heard.hash() != unheard.hash():
			return

	assert_eq(heard.query_tick(), unheard.query_tick(), "and both Runs got as far as each other")


func test_the_director_holds_no_opinion_about_the_run() -> void:
	# A second director attached to a Run already in progress hears the same things
	# the first one does from then on, because neither of them remembers anything
	# except what the queries last said.
	var sim: Simulation = _sim()
	_fed_silo(sim)
	var first: AudioDirector = _primed(sim)
	var second: AudioDirector = _primed(sim)

	for i: int in range(120):
		sim.step([])
		assert_eq(
			_names(first.cues_for_frame(sim)),
			_names(second.cues_for_frame(sim)),
			"two listeners of the same Run must hear the same thing"
		)


# ── The Telegraph is a cue, not a siren (#42) ─────────────────────────────────

func test_the_telegraph_cue_is_the_quietest_thing_in_the_catalogue() -> void:
	# The player's verdict on two successive alarms was *"the klaxon is AWFUL, just make
	# it very subtle"*, and this is that made into a property rather than a measurement
	# somebody took once. The Telegraph is the only cue that runs **continuously**, for a
	# minute at a time, while a player is trying to think — so it is the one cue that must
	# never be loud, and anything that raises it back over the ambience beds should go red
	# here rather than in a playtest.
	#
	# It does not have to carry the warning on its own: `CLAUDE.md` is explicit that
	# nothing arrives unannounced, and the countdown, the gauge and the Wave's composition
	# are all already on the HUD. The sound's job is to make a player look up.
	var bank: SoundBank = SoundBank.new()
	var klaxon: float = bank.gain_db(SoundBank.TELEGRAPH_KLAXON)
	for cue: String in SoundBank.CATALOGUE:
		assert_true(
			klaxon <= bank.gain_db(cue),
			"%s is mixed at %.1f dB, under the Telegraph's %.1f" % [
				cue, bank.gain_db(cue), klaxon
			]
		)
	# At or below both beds, rather than strictly below. Level with the quiet one is the
	# shipped answer and the right place for it: a bed is the floor of the mix, and the
	# one cue that is itself quasi-ambient belongs on that floor rather than under it,
	# where nothing would be heard at all.
	assert_true(
		klaxon <= bank.gain_db(SoundBank.FACTORY_BED)
		and klaxon <= bank.gain_db(SoundBank.FACTORY_BUSY),
		"and it sits at or under both ambience beds, which is what 'subtle' means here"
	)


func test_the_telegraph_is_a_slow_repeat_rather_than_a_held_tone() -> void:
	# A tone held for a whole Telegraph is most of why the last two grated. The cue is a
	# struck plate with a long tail of nothing, looped by the player — so what runs for
	# the length of the Telegraph is a knock every few seconds, and the gaps are the part
	# that makes it bearable.
	#
	# What is asserted here is the half this layer owns: it is **sustained**, so it starts
	# and stops with `query_wave_is_telegraphed` rather than being a one-shot that might
	# finish before the Wave lands. The sparseness is the cut's, in
	# `tools/assets/convert_audio.sh`, and a test cannot hear it.
	assert_true(
		SoundBank.LOOPING_CUES.has(SoundBank.TELEGRAPH_KLAXON),
		"the Telegraph cue is looped by the player, so it stops when the Telegraph does"
	)


## #35 again, and the half of *"needs variance"* the branch could not reach: a hero
## cue resolved to **one** path, so the five committed takes of a wrench swing were
## variance for everybody except the player who filed the report. `convert_audio.sh
## --takes N` cuts several and `SoundBank._hero_paths` walks the numbered suffixes.
##
## Asserted **only where the bundle is actually on this machine**, which is the same
## shape `WeaponViewmodel`'s tests take about the purchased arms: on a clone without
## it there is nothing to make a claim about, and the claim for that clone is
## `test_the_cues_a_player_hears_over_and_over_have_more_than_one_take` above.
func test_the_hero_takes_vary_too_when_the_bundle_is_on_this_machine() -> void:
	var bank: SoundBank = SoundBank.new()
	var checked: int = 0
	for cue: String in [
		SoundBank.WEAPON_SWING,
		SoundBank.WEAPON_HIT,
		SoundBank.ENEMY_ATTACK,
		SoundBank.ENEMY_DEATH,
		SoundBank.PLAYER_LAND,
	]:
		if not bank.is_hero(cue):
			continue
		checked += 1
		var paths: PackedStringArray = bank.paths_for(cue)
		assert_true(
			paths.size() > 1,
			"'%s' has the bundle and still one hero take, so a Wave plays one sample" % cue
		)
		# Several takes and not the same file several times, which is the whole point.
		var seen: Dictionary = {}
		for path: String in paths:
			assert_false(seen.has(path), "'%s' resolves to %s twice" % [cue, path])
			seen[path] = true
		# And the variation still comes out of the tick rather than a clock.
		var at_a_tick: AudioStream = bank.stream_for(cue, 3)
		assert_eq(bank.stream_for(cue, 3), at_a_tick, "the same tick must choose the same take")
		var differed: bool = false
		for tick: int in range(paths.size()):
			if bank.stream_for(cue, tick) != at_a_tick:
				differed = true
		assert_true(differed, "'%s' must choose differently on a different tick" % cue)

	if checked == 0:
		# Not a skip and not a pass by accident: say which world this run was in.
		assert_true(
			true, "no Sonniss bundle on this machine, so there are no hero takes to vary"
		)


## A hero cut and a Kenney take of the same event are **not** reliably the same
## loudness, and where they are far apart one gain cannot be the mix in both worlds.
## So a catalogue entry may carry a fourth number, the gain for when the hero take is
## the one playing, and `gain_db` is its only reader.
##
## Two cues need it and the reasons are different. `FACTORY_BUSY` has to sit *above*
## `FACTORY_BED` or the crossfade that makes a Factory's growth audible inverts — and
## the hero busy cut measures below the hero bed while the Kenney busy loop measures
## above the Kenney bed, so the gap has to be built differently in each world.
## `WEAPON_SWING` is a whoosh standing in for impacts: low crest, so peak-normalising
## it leaves it 5 dB quieter than they are.
##
## The claim under test is not the numbers. It is that **whichever world this machine
## is in, `gain_db` answers for the file it is about to play**, and that a fourth gain
## is only ever *less* attenuation — a hero cut needing more would mean the hero cut
## was the louder file, which is the opposite of why this mechanism exists.
func test_a_cue_whose_two_sources_differ_in_loudness_carries_a_gain_for_each() -> void:
	var bank: SoundBank = SoundBank.new()
	var declared: int = 0
	for cue: String in bank.cues():
		var entry: Array = SoundBank.CATALOGUE[cue] as Array
		if entry.size() < 4:
			continue
		declared += 1
		var committed: float = entry[2] as float
		var hero: float = entry[3] as float
		assert_eq(
			bank.gain_db(cue),
			hero if bank.is_hero(cue) else committed,
			"'%s' must be mixed at the gain of the file it is going to play" % cue
		)
		assert_true(
			hero > committed,
			(
				"'%s' asks for more attenuation on its hero take (%f) than on its"
				+ " fallbacks (%f), which inverts what the fourth gain is for"
			) % [cue, hero, committed]
		)
	assert_true(declared > 0, "nothing declares a per-source gain; the mechanism is dead code")


## The loud ambience bed has to be the loud one. `ambience_db` crossfades the pair as
## the Factory grows and that is the whole of "growth is audible" — a busy bed mixed
## *under* the quiet one would make a Factory at full tilt the quieter of the two.
##
## Asserted about `ambience_db` at a size where both are running rather than about the
## two gains, because the gains are only the ceilings the ramps climb towards.
func test_the_busy_bed_is_the_louder_of_the_two_beds() -> void:
	var bank: SoundBank = SoundBank.new()
	assert_true(
		bank.gain_db(SoundBank.FACTORY_BUSY) > bank.gain_db(SoundBank.FACTORY_BED),
		(
			"the busy bed's ceiling (%f) is at or below the quiet bed's (%f)"
			% [bank.gain_db(SoundBank.FACTORY_BUSY), bank.gain_db(SoundBank.FACTORY_BED)]
		)
	)


## The one cue in the catalogue that is cut as a one-shot and played as a loop, and the
## reason it is: a klaxon's attack is the warning, and `--mode loop` crossfades a cue's
## tail over its own head, which would fade that attack in. So the Telegraph's cue is a
## horn blast with silence either side of it, looped by the engine, and it rearticulates
## once a cycle the way a real klaxon does.
func test_the_klaxon_is_looped_by_the_player_rather_than_by_the_cut() -> void:
	assert_true(
		SoundBank.LOOPING_CUES.has(SoundBank.TELEGRAPH_KLAXON),
		"a warning that stopped after one blast would not be a warning"
	)
	var recipe: String = FileAccess.get_file_as_string("res://tools/assets/convert_audio.sh")
	assert_false(recipe.is_empty(), "the recipe must be readable to be asserted about")
	for line: String in recipe.split("\n"):
		if not line.begins_with("cue telegraph_klaxon"):
			continue
		assert_false(
			line.contains("--mode loop"),
			"the klaxon must be cut as a one-shot, or its attack is crossfaded away"
		)
