## Saving and resuming a Run.
##
## The whole test is one assertion repeated: a Run written out and read back hashes
## to the same integer it did before. `Simulation.hash()` already covers every piece
## of state that matters, so a save that loses something fails loudly here rather
## than subtly in a player's Factory an hour later.
extends TestCase

## Where the Smelter lands in `_a_factory_mid_run`'s Machine list: Machines are held in
## the order they were built, and the Smelter is the second.
const SMELTER: int = 1

## Content that differs from `content/`, so its digest differs. Used to prove a Run
## refuses to resume onto definitions it was not saved under.
const ALTERED_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,0,0,mine_iron_ore,
"""

const ALTERED_RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
"""

const ALTERED_TUNING: String = """[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
starting_stock = "iron_ore:200"
[belt]
items_per_second = 4
items_per_tile = 4
[machine]
input_buffer_crafts = 2
[survey]
height_metres = 26
transition_seconds = 0.4
pitch_degrees = 68
[power]
baseline_supply_kw = 300
[nest]
health = 6000
delivery_reach_metres = 5
[wave]
telegraph_seconds = 12
spawn_interval_seconds = 0.5
call_early_bounty_per_item = 25

[heat]
per_craft = 2
per_craft_per_depth = 1
decay_per_minute = 240
wave_interval_baseline_seconds = 150
wave_interval_minimum_seconds = 40
per_second_sooner = 20
[enemy]
crawler_health = 30
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
"""


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


# ── The round trip ────────────────────────────────────────────────────────────

func test_a_fresh_run_round_trips_to_an_identical_hash() -> void:
	var sim: Simulation = Simulation.new(1, 1)

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim))

	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(loaded.simulation.hash(), sim.hash(), "a round trip must be exact")


## A Run with something in it worth losing: a Miner over ore, a Belt with Items in
## flight, a Smelter that has crafted and is holding ore for the next craft, a second
## Miner that pushes the grid into deficit so Power is carrying credit, a player who has
## walked and turned and spent build costs, and a Build Gun turned a quarter.
## Everything the acceptance criteria name, in one state.
##
## 900 ticks because content/recipes.csv puts the Smelter's first plate on tick 597 at
## full rate and the deficit stretches that: a Factory saved before its first craft
## finishes has no part-finished craft to lose.
func _a_factory_mid_run() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(10, 0, 0), "coal", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(99, 1, null, layout)
	var definitions: Definitions = sim.query_definitions()

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(5, 0, 0)),
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(6, 0, 0)),
		# Demand 420 kW against a 300 kW baseline, so the grid is short and carrying
		# credit from tick to tick rather than sitting at a round zero.
		InputAction.build_machine(0, definitions.machine_index("coal_miner_mk1"), Vector3i(10, 0, 0)),
	])
	# Turn, walk, scroll to another Machine and rotate it — so the player's own state is
	# as far from its construction defaults as the Factory's is.
	sim.step([
		InputAction.look(0, Fixed.from_int(420), Fixed.from_int(-130)),
		InputAction.select_machine(0, definitions.machine_index("steam_boiler_mk1")),
		InputAction.rotate_build(0, 1),
		InputAction.sprint(0, true),
		InputAction.move(0, Fixed.ONE, Fixed.from_rational(1, 2)),
	])
	for tick: int in range(900):
		sim.step([InputAction.move(0, Fixed.from_rational(1, 3), 0)])
	return sim


func test_the_mid_run_factory_these_tests_save_is_actually_mid_run() -> void:
	# Without this the round-trip assertions below could all be passing over an empty
	# Factory, which would prove nothing about Belts, crafting or Power.
	var sim: Simulation = _a_factory_mid_run()
	assert_eq(sim.query_machine_count(), 3, "two Miners and a Smelter")
	assert_eq(sim.query_belt_count(), 1)
	assert_true(sim.query_belt_item_count(0) > 0, "with Items in flight on the Belt")
	assert_true(sim.query_machine_input_total(SMELTER) > 0, "and ore waiting in the Smelter")
	assert_true(sim.query_machine_output_total(SMELTER) > 0, "which has already made a plate")
	assert_true(sim.query_power_is_in_deficit(), "and a grid short of what it is asked for")
	assert_true(
		sim.query_player_item(0, "iron_plate") < 200,
		"and a player who has paid for what they built"
	)
	assert_ne(sim.query_player_position(0).x, 0, "and who has walked")


func test_a_factory_mid_run_round_trips_to_an_identical_hash() -> void:
	var sim: Simulation = _a_factory_mid_run()

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim))

	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(loaded.simulation.hash(), sim.hash(), "every array, or the hash moves")


func test_belt_item_positions_survive_the_round_trip() -> void:
	var sim: Simulation = _a_factory_mid_run()
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(sim)).simulation

	assert_eq(restored.query_belt_item_count(0), sim.query_belt_item_count(0))
	for slot: int in range(sim.query_belt_item_count(0)):
		assert_eq(
			restored.query_belt_item_id(0, slot),
			sim.query_belt_item_id(0, slot),
			"the Item in slot %d" % slot
		)
		assert_eq(
			restored.query_belt_item_distance_metres(0, slot),
			sim.query_belt_item_distance_metres(0, slot),
			"and exactly where along the run it had got to"
		)


func test_machine_progress_and_both_buffers_survive_the_round_trip() -> void:
	var sim: Simulation = _a_factory_mid_run()
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(sim)).simulation

	for index: int in range(sim.query_machine_count()):
		assert_eq(restored.query_machine_id(index), sim.query_machine_id(index))
		assert_eq(
			restored.query_machine_output_total(index),
			sim.query_machine_output_total(index),
			"what Machine %d has made" % index
		)
		assert_eq(
			restored.query_machine_input_total(index),
			sim.query_machine_input_total(index),
			"and what it is holding for its Recipe"
		)
		assert_eq(
			restored.query_machine_is_starved(index),
			sim.query_machine_is_starved(index)
		)
	# Progress part-way through a craft is not a query of its own, so it is observed the
	# way a player would: the next output lands on the same tick either way.
	var sim_before: int = sim.query_machine_output_total(SMELTER)
	var restored_before: int = restored.query_machine_output_total(SMELTER)
	var ticks_to_next: int = -1
	for tick: int in range(600):
		sim.step([])
		restored.step([])
		if ticks_to_next == -1 and sim.query_machine_output_total(SMELTER) > sim_before:
			ticks_to_next = tick
		assert_eq(
			restored.query_machine_output_total(SMELTER),
			sim.query_machine_output_total(SMELTER),
			"the Smelter's output after %d further ticks" % (tick + 1)
		)
	assert_true(ticks_to_next >= 0, "the Smelter did finish a craft, so progress was real")
	assert_eq(restored_before, sim_before, "and both started from the same count")


func test_power_state_survives_the_round_trip() -> void:
	var sim: Simulation = _a_factory_mid_run()
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(sim)).simulation

	assert_eq(restored.query_power_supply_kw(), sim.query_power_supply_kw())
	assert_eq(restored.query_power_demand_kw(), sim.query_power_demand_kw())
	assert_eq(restored.query_power_ratio(), sim.query_power_ratio())
	assert_eq(restored.query_power_is_in_deficit(), sim.query_power_is_in_deficit())


func test_the_player_survives_the_round_trip() -> void:
	var sim: Simulation = _a_factory_mid_run()
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(sim)).simulation

	assert_eq(restored.query_tick(), sim.query_tick(), "a resumed Run is on the same tick")
	assert_eq(restored.query_seed(), sim.query_seed())
	assert_eq(restored.query_player_position(0).x, sim.query_player_position(0).x)
	assert_eq(restored.query_player_position(0).z, sim.query_player_position(0).z)
	assert_eq(restored.query_player_velocity(0).x, sim.query_player_velocity(0).x)
	assert_eq(restored.query_player_velocity(0).z, sim.query_player_velocity(0).z)
	assert_eq(restored.query_player_yaw_turns(0), sim.query_player_yaw_turns(0))
	assert_eq(restored.query_player_pitch_turns(0), sim.query_player_pitch_turns(0))
	assert_eq(
		restored.query_player_selected_machine(0),
		sim.query_player_selected_machine(0),
		"the Build Gun keeps what was on it"
	)
	assert_eq(
		restored.query_player_build_rotation(0),
		sim.query_player_build_rotation(0),
		"and which way round it was turned"
	)
	for item_id: String in sim.query_player_items(0):
		assert_eq(
			restored.query_player_item(0, item_id),
			sim.query_player_item(0, item_id),
			"the player's stock of %s, spent build costs and all" % item_id
		)
	assert_eq(restored.query_player_items(0), sim.query_player_items(0))


func test_a_resumed_run_continues_identically_tick_for_tick() -> void:
	# The strongest form of the criterion. A hash that matches at the moment of loading
	# proves the state was restored; replaying a script into the restored Run proves it
	# was restored *usefully*, with nothing derived left stale.
	var sim: Simulation = _a_factory_mid_run()
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(sim)).simulation

	for tick: int in range(400):
		var actions: Array = [InputAction.move(0, Fixed.from_rational(-1, 2), Fixed.ONE)]
		sim.step(actions)
		restored.step(actions)
		assert_eq(restored.hash(), sim.hash(), "diverged %d ticks after resuming" % (tick + 1))


# ── Saving is a read ──────────────────────────────────────────────────────────

func test_saving_does_not_change_the_state_it_saves() -> void:
	var sim: Simulation = _a_factory_mid_run()
	var before: int = sim.hash()
	RunSave.serialise(sim)
	assert_eq(sim.hash(), before, "serialising is a read, not a step")
	assert_eq(sim.query_tick(), 902, "and it advances nothing")


func test_saving_every_tick_does_not_perturb_the_hash_sequence() -> void:
	# Two Runs built identically, one of which is saved at every single tick. If
	# serialising touched anything at all — consumed an RNG draw, cleared a buffer,
	# rebuilt a derived order — the two would part company.
	var saved: Simulation = Simulation.new(5, 1)
	var untouched: Simulation = Simulation.new(5, 1)
	var definitions: Definitions = saved.query_definitions()
	var build: Array = [
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), saved.query_node_tile(0)),
		InputAction.build_belt(0, Vector3i(20, 0, 20), Vector3i(23, 0, 20)),
	]
	saved.step(build)
	untouched.step(build)

	for tick: int in range(200):
		RunSave.serialise(saved)
		var actions: Array = [InputAction.look(0, Fixed.from_int(3), 0)]
		saved.step(actions)
		untouched.step(actions)
		assert_eq(
			saved.hash(),
			untouched.hash(),
			"saving on tick %d moved the Run that saved" % (tick + 1)
		)


func test_a_restored_run_replays_a_recorded_script_identically() -> void:
	# The determinism harness's own answer to this ticket: `verify` takes a replacement
	# Simulation precisely so a save/load round trip can be proved exact against a
	# recording made without one.
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_tick([InputAction.look(0, Fixed.from_int(90), Fixed.from_int(20))])
	script.add_idle_ticks(120)

	var recording: ReplayRecording = DeterminismHarness.record(script, 31, 1)
	var fresh: Simulation = Simulation.new(31, 1)
	var restored: Simulation = RunSave.deserialise(RunSave.serialise(fresh)).simulation

	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, restored)
	assert_true(divergence.is_identical, divergence.describe())
	assert_eq(divergence.ticks_compared, script.tick_count() + 1)


# ── Refusing what it should not load ──────────────────────────────────────────

func test_a_save_in_an_incompatible_format_is_refused_by_number() -> void:
	var text: String = RunSave.serialise(Simulation.new(1, 1))
	var future: String = text.replace(
		"%s %d" % [RunSave.KEY_FORMAT, RunSave.FORMAT_VERSION], "%s 99" % RunSave.KEY_FORMAT
	)

	var loaded: RunSave.Load = RunSave.deserialise(future)

	assert_true(loaded.has_errors(), "a format this build does not read must not load")
	assert_true(loaded.version_mismatch, "and must say that is why")
	assert_null(loaded.simulation, "loading garbage is worse than loading nothing")
	assert_true(loaded.describe_errors().contains("99"), loaded.describe_errors())
	assert_true(loaded.describe_errors().contains("format 1"), loaded.describe_errors())


func test_a_file_that_is_not_a_save_is_refused_before_it_is_parsed() -> void:
	var loaded: RunSave.Load = RunSave.deserialise("[gd_resource type=\"Resource\"]\n")
	assert_true(loaded.has_errors())
	assert_null(loaded.simulation)
	assert_true(
		loaded.describe_errors().contains(RunSave.MAGIC),
		"the message should say what it was looking for"
	)


func test_an_empty_file_is_refused() -> void:
	var loaded: RunSave.Load = RunSave.deserialise("")
	assert_true(loaded.has_errors())
	assert_null(loaded.simulation)


func test_a_save_whose_state_has_been_tampered_with_is_refused() -> void:
	# The save carries its own state hash and the load re-derives it, so a corrupted
	# array is caught rather than resumed. This is the mechanism that makes every load a
	# test of the round trip, not only the suite.
	var sim: Simulation = _a_factory_mid_run()
	var tampered: String = RunSave.serialise(sim).replace(
		"_power_credit_kw_ticks i", "_power_credit_kw_ticks i 1"
	)

	var loaded: RunSave.Load = RunSave.deserialise(tampered)

	assert_true(loaded.has_errors(), "a Run that does not hash to what was written is corrupt")
	assert_true(loaded.state_mismatch)
	assert_null(loaded.simulation)


## The shipped Wave composition, inline so the fixture is a complete definition set. A
## Wave's contents are a table (`content/waves.csv`), and a set with no rows in it is an
## error rather than a Run that is never attacked.
const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""


func test_a_save_made_under_different_content_definitions_is_refused() -> void:
	# `ReplayRecording` does exactly this, and for the same reason: content that has
	# changed is a different game, and reporting it as a different game sends the reader
	# somewhere useful.
	var sim: Simulation = Simulation.new(1, 1)
	var other_content: Definitions = Definitions.parse(
		ALTERED_MACHINES, ALTERED_RECIPES, ALTERED_TUNING, WAVES, DELIVERIES
	)

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim), other_content)

	assert_false(other_content.has_errors(), other_content.describe_errors())
	assert_true(loaded.has_errors(), "a Run must not silently drift onto other content")
	assert_true(loaded.definitions_mismatch, "and must say that is why")
	assert_null(loaded.simulation)


# ── State a later ticket adds ─────────────────────────────────────────────────
# The serialiser has no list of fields and no knowledge of what a Belt is: it walks the
# Simulation's own property list. These prove it, with a subclass standing in for the
# Enemy state a later ticket brings — the same way `DeterminismHarness.verify` takes a
# replacement Simulation to prove the harness has teeth.


## A Simulation with state this ticket has never heard of, hashed the way a real ticket
## would hash it.
class SimulationWithEnemies extends Simulation:
	var _enemy_hp: PackedInt64Array = PackedInt64Array()
	var _enemy_sigil: PackedStringArray = PackedStringArray()

	func spawn(hp: int, kind: String) -> void:
		_enemy_hp.append(hp)
		_enemy_sigil.append(kind)

	func hash() -> int:
		var hasher: StateHasher = StateHasher.new()
		hasher.feed_int(super.hash())
		hasher.feed_ints(_enemy_hp)
		for kind: String in _enemy_sigil:
			hasher.feed_text(kind)
		return hasher.digest()


## A Simulation holding state in a type the format cannot encode.
class SimulationWithAnExoticField extends Simulation:
	var _nest_tile: Vector3i = Vector3i(3, 0, 4)


func test_state_a_later_ticket_adds_round_trips_without_the_serialiser_changing() -> void:
	var sim: SimulationWithEnemies = SimulationWithEnemies.new(2, 1)
	sim.spawn(40, "crawler")
	sim.spawn(7, "chaff")
	sim.step([])

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), null, SimulationWithEnemies.new(2, 1)
	)

	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(
		loaded.simulation.hash(),
		sim.hash(),
		"arrays this file has never heard of are saved because nothing lists them"
	)


func test_a_save_carrying_state_this_build_does_not_hold_is_refused_by_name() -> void:
	var sim: SimulationWithEnemies = SimulationWithEnemies.new(2, 1)
	sim.spawn(40, "crawler")

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim))

	assert_true(loaded.has_errors(), "a save from a build that held more state must not load")
	assert_true(loaded.state_mismatch)
	assert_true(loaded.describe_errors().contains("_enemy_hp"), loaded.describe_errors())


func test_a_save_missing_state_this_build_holds_is_refused_by_name() -> void:
	# The case that makes this ticket a contract rather than a convenience: a Run saved
	# before Enemies existed cannot resume into a build that has them with every Enemy
	# array quietly empty.
	var text: String = RunSave.serialise(Simulation.new(2, 1))

	var loaded: RunSave.Load = RunSave.deserialise(text, null, SimulationWithEnemies.new(2, 1))

	assert_true(loaded.has_errors())
	assert_true(loaded.state_mismatch)
	assert_true(loaded.describe_errors().contains("_enemy_sigil"), loaded.describe_errors())
	assert_null(loaded.simulation)


func test_state_in_a_type_the_format_cannot_encode_is_refused_by_name() -> void:
	# Not a silent zero and not a crash. The Simulation's convention is parallel integer
	# arrays — even a tile is three of them — so the refusal is also the right advice.
	var sim: SimulationWithAnExoticField = SimulationWithAnExoticField.new(2, 1)

	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim), null, SimulationWithAnExoticField.new(2, 1)
	)

	assert_true(loaded.has_errors())
	assert_true(loaded.describe_errors().contains("_nest_tile"), loaded.describe_errors())
	assert_null(loaded.simulation)


# ── The file the player actually gets ─────────────────────────────────────────

const SAVE_PATH: String = "user://run_save_test.deepfoundry"


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func test_a_run_written_to_a_file_and_read_back_is_identical() -> void:
	var sim: Simulation = _a_factory_mid_run()

	assert_eq(RunSave.write_to_file(sim, SAVE_PATH), "", "writing should not fail")
	var loaded: RunSave.Load = RunSave.read_from_file(SAVE_PATH)

	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(loaded.simulation.hash(), sim.hash())


func test_reading_a_run_that_was_never_saved_says_so() -> void:
	var loaded: RunSave.Load = RunSave.read_from_file("user://no_such_run.deepfoundry")
	assert_true(loaded.has_errors())
	assert_null(loaded.simulation)
	assert_true(loaded.describe_errors().contains("no saved Run"), loaded.describe_errors())


# ── The format itself ─────────────────────────────────────────────────────────

func test_the_save_is_readable_text_naming_every_property_it_carries() -> void:
	var text: String = RunSave.serialise(_a_factory_mid_run())
	assert_true(text.begins_with(RunSave.MAGIC + "\n"), "a save announces what it is")
	assert_true(text.contains("\n_belt_item_offsets "), "and names each property it carries")
	assert_true(text.contains("\n_power_credit_kw_ticks "))
	# One line per property and nothing else in the body, which is what makes two saves
	# diffable line for line.
	var sim: Simulation = Simulation.new(1, 1)
	var body: int = 0
	for line: String in RunSave.serialise(sim).split("\n"):
		if not line.is_empty():
			body += 1
	assert_eq(
		body,
		RunSave.state_property_names(sim).size() + 4,
		"every property gets exactly one line, after the magic line and three header lines"
	)


func test_an_item_id_with_awkward_characters_survives_the_round_trip() -> void:
	# Item ids are well-behaved identifiers today, but a save format that relies on that
	# is one content change away from corrupting a Factory.
	var awkward: PackedStringArray = PackedStringArray(
		["", "a b", "with\\backslash", "two\nlines", "\\z", "trailing "]
	)
	for original: String in awkward:
		var encoded: String = RunSave.encode_text(original)
		assert_false(encoded.contains(" "), "an encoded token must not contain a separator")
		assert_eq(RunSave.decode_text(encoded), original, "round trip of %s" % [original])


## The Delivery tiers, inline so the fixture is a complete definition set. Progression is
## physical (`content/deliveries.csv`), and a table with no rows in it is an error rather
## than a Run with no progression. This one unlocks a Gear component and names no Machine,
## so nothing this file builds is locked behind it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""
