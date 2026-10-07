## Definitions inside the Simulation, and what reloading them mid-Run does.
##
## Tested through the façade — `step`, `hash`, `query_*` — because that is where
## the question lives: a reload is a change to the Simulation, and the thing worth
## asserting is that the change is *visible* rather than silent.
##
## The position this file pins down, which ADR 0002 leaves no room to fudge:
##
## 1. A reload is an **Input Action**, not a back door. It goes through `step`, so
##    it is ordered with every other intent, it lands in a recorded script, and a
##    replay reproduces it exactly. The façade stays at three entry points.
## 2. A reload **changes the state hash at the tick it is applied**. It is a change
##    to the Simulation and it is hashed like one. Two Runs that reloaded different
##    things, or reloaded at different ticks, do not share a hash.
## 3. A reload is **not undoable**. Reloading back to the original files does not
##    restore the earlier hash, because the Run did change — a generation counter
##    is part of the state. A Run that pretended otherwise would be a Run whose
##    history the hash cannot describe.
## 4. A replay **refuses to run against different definitions**. A recording
##    carries the digest of the definition set it was made under, and a mismatch
##    is reported as a mismatch, never as a tick divergence and never as a pass.
## 5. A reload that **failed to load is refused**, and the Run carries on with the
##    definitions it had. A typo in a tuning file must not take down a Run in
##    progress; it must be refused, loudly, and leave everything as it was.
extends TestCase

const SEED: int = 31337
const PLAYERS: int = 1

## The two walking speeds these fixtures differ by, in metres per second.
##
## Deliberately tiny — smaller than the 0.4 m/s a single tick of acceleration buys —
## so that one tick of full throttle lands exactly on the tuned speed. That makes a
## reload's effect observable in the *one tick* it is applied on, which is the
## property several tests below are about. At a realistic 4 m/s the first tick is
## acceleration-limited and would look the same whatever the speed were set to.
const SLOW_SPEED: String = "0.25"
const FAST_SPEED: String = "0.375"

## One tick at 0.25 m/s, forward along -z: -16384 / 60 is -273.07, and flooring is
## toward negative infinity regardless of sign, so it is -274 rather than -273.
const STEP_AT_SLOW: int = -274
## The same at 0.375 m/s: -24576 / 60 is -409.6, floored to -410.
const STEP_AT_FAST: int = -410

const MACHINES: String = """
id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,120,0,400,1,mine_iron_ore,
"""

const RECIPES: String = """
id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,1.5
"""


## The tuning keys this file is not about. Every key the Simulation reads must be present
## for a set to load, so a test that varies one carries the rest unchanged.
const OTHER_TUNING: String = """
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
starting_stock_per_item = 200
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
"""


func _definitions(walk_speed: String) -> Definitions:
	return Definitions.parse(
		MACHINES,
		RECIPES,
		"[player]\nwalk_speed_metres_per_second = %s\n" % walk_speed + OTHER_TUNING,
		"machines.csv",
		"recipes.csv",
		"tuning.toml"
	)


func _slow() -> Definitions:
	return _definitions(SLOW_SPEED)


func _fast() -> Definitions:
	return _definitions(FAST_SPEED)


# ── Definitions reach the Simulation ──────────────────────────────────────────

func test_a_simulation_built_without_definitions_loads_the_shipped_content() -> void:
	var sim: Simulation = Simulation.new(SEED, PLAYERS)
	assert_eq(sim.query_definition_errors(), PackedStringArray([]), "the shipped content must load")
	assert_true(sim.query_definitions().has_machine("miner_mk1"))


func test_a_tuning_value_drives_the_simulation() -> void:
	# Proof that tuning is not decoration: the same action produces a different
	# result because a number in a file is different.
	var slow: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var fast: Simulation = Simulation.new(SEED, PLAYERS, _fast())

	slow.step([InputAction.move(0, Fixed.ONE, 0)])
	fast.step([InputAction.move(0, Fixed.ONE, 0)])

	assert_eq(slow.query_player_position(0).z, STEP_AT_SLOW)
	assert_eq(fast.query_player_position(0).z, STEP_AT_FAST)


func test_the_definition_set_is_part_of_the_state_hash() -> void:
	var slow: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var fast: Simulation = Simulation.new(SEED, PLAYERS, _fast())
	assert_ne(
		slow.hash(),
		fast.hash(),
		"two Runs on different definitions must not share a starting hash"
	)


func test_the_same_definitions_produce_the_same_starting_hash() -> void:
	var one: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var other: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	assert_eq(one.hash(), other.hash(), "the same files, the same state")


func test_definitions_that_failed_to_load_are_reported_and_nothing_is_invented() -> void:
	# A Run must not start on a broken definition set, and the way it refuses is by
	# saying so rather than by substituting plausible numbers.
	var broken: Definitions = Definitions.parse("nonsense", RECIPES, "[player]\n")
	var sim: Simulation = Simulation.new(SEED, PLAYERS, broken)

	assert_true(sim.query_definition_errors().size() > 0)
	assert_false(sim.query_definitions_loaded())
	assert_eq(sim.query_definitions().machine_count(), 0, "no half-loaded content")

	sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(
		sim.query_player_position(0).z,
		0,
		"with no tuning there is no walk speed, so nothing moves — and the errors say why"
	)


# ── Reloading mid-Run ─────────────────────────────────────────────────────────

func test_a_reload_action_replaces_the_definitions() -> void:
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	sim.step([InputAction.reload_definitions(0, _fast())])
	assert_eq(sim.query_definition_digest(), _fast().digest())


func test_a_reload_takes_effect_on_the_tick_it_is_applied() -> void:
	# Actions are applied before the tick's own updates, so a move in the same tick
	# as the reload already uses the new value. Being explicit about that is the
	# whole point: the ordering is what makes the reload reproducible.
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	sim.step([InputAction.reload_definitions(0, _fast()), InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).z, STEP_AT_FAST)


func test_a_reload_changes_the_state_hash() -> void:
	var reloaded: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var untouched: Simulation = Simulation.new(SEED, PLAYERS, _slow())

	reloaded.step([InputAction.reload_definitions(0, _fast())])
	untouched.step([])

	assert_ne(
		reloaded.hash(),
		untouched.hash(),
		"a definition change mid-Run must never be invisible to the hash"
	)


func test_reloading_the_original_definitions_does_not_restore_the_earlier_hash() -> void:
	# A reload is a thing that happened to the Run. The generation counter is state,
	# so the hash remembers it even when the content is identical again.
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var before: int = sim.hash()

	sim.step([InputAction.reload_definitions(0, _slow())])

	assert_eq(sim.query_definition_digest(), _slow().digest(), "same content")
	assert_eq(sim.query_definition_generation(), 1, "but the Run has reloaded once")
	assert_ne(sim.hash(), before, "and the hash says so")


func test_a_reload_counts_up_every_time() -> void:
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	assert_eq(sim.query_definition_generation(), 0)
	sim.step([InputAction.reload_definitions(0, _fast())])
	sim.step([InputAction.reload_definitions(0, _slow())])
	assert_eq(sim.query_definition_generation(), 2)


# ── Reloads that are refused ──────────────────────────────────────────────────

func test_a_reload_of_a_broken_definition_set_is_refused() -> void:
	# The behaviour that matters most while someone is tuning with the game running:
	# a typo must not take the Run down, and must not take effect either.
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	var before: int = sim.hash()

	var broken: Definitions = Definitions.parse(MACHINES, RECIPES, "[player]\nwalk_speed = oops\n")
	sim.step([InputAction.reload_definitions(0, broken)])

	assert_eq(sim.query_definition_digest(), _slow().digest(), "the old definitions stand")
	assert_eq(sim.query_definition_generation(), 0, "a refused reload is not a reload")

	sim.step([InputAction.move(0, Fixed.ONE, 0)])
	assert_eq(sim.query_player_position(0).z, STEP_AT_SLOW, "and the Run carries on unchanged")
	assert_ne(before, 0)


func test_a_reload_carrying_no_definitions_is_refused() -> void:
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())
	sim.step([InputAction.reload_definitions(0, null)])
	assert_eq(sim.query_definition_digest(), _slow().digest())
	assert_eq(sim.query_definition_generation(), 0)


func test_a_reload_whose_declared_digest_disagrees_with_its_payload_is_refused() -> void:
	# In lockstep the digest in the action is what every client checks its own copy
	# against. An action whose digest does not match the payload it arrived with is
	# corrupt, and applying it would desync every client that disagreed.
	var sim: Simulation = Simulation.new(SEED, PLAYERS, _slow())

	var tampered: InputAction = InputAction.reload_definitions(0, _fast())
	tampered.args = PackedInt64Array([tampered.args[0] + 1])

	sim.step([tampered])
	assert_eq(sim.query_definition_digest(), _slow().digest())
	assert_eq(sim.query_definition_generation(), 0)


# ── Replay ────────────────────────────────────────────────────────────────────

func test_a_run_that_reloaded_mid_flight_replays_exactly() -> void:
	# The reason a reload is an Input Action rather than a method call: it is in the
	# script, so the replay performs the same reload at the same tick and the hashes
	# agree tick for tick.
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(2)
	script.add_tick([InputAction.reload_definitions(0, _fast())])
	script.add_tick([InputAction.move(0, Fixed.ONE, Fixed.HALF)])
	script.add_idle_ticks(3)
	script.add_tick([InputAction.move(0, -Fixed.HALF, 0)])

	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS, _slow())
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_a_recording_remembers_which_definitions_it_was_made_under() -> void:
	var script: InputScript = InputScript.new()
	script.add_idle_ticks(3)
	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS, _slow())
	assert_eq(recording.definitions_digest, _slow().digest())


func test_a_replay_under_different_definitions_is_refused_not_passed() -> void:
	# The failure this guard exists to prevent: a fixture recorded months ago
	# quietly "passing" against content that has since changed, or being reported as
	# a tick divergence that sends someone hunting through the wrong code.
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(2)

	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS, _slow())
	var elsewhere: Simulation = Simulation.new(SEED, PLAYERS, _fast())

	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, elsewhere)
	assert_false(divergence.is_identical)
	assert_true(divergence.definitions_mismatch, "the cause must be named, not guessed at")
	assert_true(
		divergence.describe().contains("definition"),
		"got: %s" % divergence.describe()
	)


func test_a_replay_under_the_same_definitions_is_not_refused() -> void:
	# The guard must not fire on a legitimate replay, or it is worthless.
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(2)

	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS, _slow())
	var same: Simulation = Simulation.new(SEED, PLAYERS, _slow())

	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording, same)
	assert_false(divergence.definitions_mismatch)
	assert_true(divergence.is_identical, divergence.describe())
