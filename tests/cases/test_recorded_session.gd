## The replay fixture this ticket leaves behind: a session of real player input that
## replays to an identical hash, tick for tick.
##
## What makes it the fixture the ticket asked for rather than a hand-written script of
## Input Actions: every action in it is produced by the *actual* input producer,
## `PlayerController`, from a sequence of device readings — mouse travel, held keys,
## clicks, a scroll wheel, Survey View held and released. The session walks, looks, lifts
## the camera, selects, rotates, builds, **drags a Belt route out and releases it**, and
## demolishes, and it is built by driving the controller against a live Simulation exactly as
## a frame loop would.
##
## That is the whole determinism argument for the first-person layer. The mouse reports
## floats and the camera ray is float arithmetic, but what is *recorded* is a script of
## integer intents, and replaying that script from an identical starting state reproduces
## the Run exactly — so the floats on the way in cannot have reached the state.
##
## `definitions` is left null in the recording, so the replay re-reads `content/`. A
## content change that would alter the Run is then reported as `definitions_mismatch`
## rather than passing unnoticed.
extends TestCase

const SEED: int = 20260407
const PLAYERS: int = 1


func _sample() -> PlayerController.DeviceSample:
	return PlayerController.DeviceSample.new()


## The device readings of one session, tick by tick.
##
## Written as the readings a person's hands produce rather than as the intents they amount
## to: holding W for a second, sweeping the mouse, clicking, scrolling. The controller is
## what turns them into Input Actions, which is the part under test.
func _session() -> Array:
	var ticks: Array = []

	# Walk forward, sweeping the view to the right as you go.
	for tick: int in range(45):
		var walking: PlayerController.DeviceSample = _sample()
		walking.forward = 1.0
		walking.mouse_motion = Vector2(6.0, 0.0)
		ticks.append(walking)

	# Stop, look down at the ground in front of you, and let the slide die away.
	for tick: int in range(20):
		var settling: PlayerController.DeviceSample = _sample()
		settling.mouse_motion = Vector2(0.0, 11.0)
		ticks.append(settling)

	# Scroll to the next Machine, turn it a quarter, and place it.
	var scrolling: PlayerController.DeviceSample = _sample()
	scrolling.machine_steps = 1
	ticks.append(scrolling)

	var turning: PlayerController.DeviceSample = _sample()
	turning.rotate_steps = 1
	ticks.append(turning)

	var placing: PlayerController.DeviceSample = _sample()
	placing.place_clicked = true
	ticks.append(placing)

	# Lift into Survey View, strafe along the line while it is up, and build from above —
	# which is the thing Survey View exists for.
	for tick: int in range(40):
		var surveying: PlayerController.DeviceSample = _sample()
		surveying.survey_held = true
		surveying.strafe = 1.0
		ticks.append(surveying)

	var placing_from_above: PlayerController.DeviceSample = _sample()
	placing_from_above.survey_held = true
	placing_from_above.place_clicked = true
	ticks.append(placing_from_above)

	# Click again where the Machine now stands. Refused, and a refusal belongs in the
	# fixture: it has to be a no-op that replays like any other tick.
	var refused: PlayerController.DeviceSample = _sample()
	refused.survey_held = true
	refused.place_clicked = true
	ticks.append(refused)

	# Drop back to eye level, walking backwards and turning the other way.
	for tick: int in range(40):
		var dropping: PlayerController.DeviceSample = _sample()
		dropping.forward = -1.0
		dropping.mouse_motion = Vector2(-4.0, -2.0)
		ticks.append(dropping)

	# Change your mind about the last thing you built.
	var wrecking: PlayerController.DeviceSample = _sample()
	wrecking.demolish_clicked = true
	ticks.append(wrecking)

	# Walk the diagonal out to clear ground, then lay a Belt along the way you are facing.
	for tick: int in range(60):
		var strolling: PlayerController.DeviceSample = _sample()
		strolling.forward = 1.0
		strolling.strafe = -1.0
		ticks.append(strolling)

	# Put the Belt tool on the Build Gun, then **drag a route out**: press, turn the view so
	# the far end lands somewhere else, flip the corner the other way round with the right
	# button half way through, and release. That is the whole of #36's gesture through the
	# real input producer, and it is the fixture the ticket asked for — a drag reproduces
	# because what was recorded is the *route*, decided on release, and not the mouse travel
	# that aimed it.
	var tooling: PlayerController.DeviceSample = _sample()
	tooling.belt_clicked = true
	ticks.append(tooling)

	var anchoring: PlayerController.DeviceSample = _sample()
	anchoring.place_clicked = true
	ticks.append(anchoring)

	for tick: int in range(14):
		var dragging: PlayerController.DeviceSample = _sample()
		dragging.mouse_motion = Vector2(9.0, -3.0)
		ticks.append(dragging)

	var cornering: PlayerController.DeviceSample = _sample()
	cornering.rotate_steps = 1
	ticks.append(cornering)

	for tick: int in range(10):
		var dragging_on: PlayerController.DeviceSample = _sample()
		dragging_on.mouse_motion = Vector2(5.0, 2.0)
		ticks.append(dragging_on)

	var releasing: PlayerController.DeviceSample = _sample()
	releasing.primary_released = true
	ticks.append(releasing)

	# And take the tool back off, so the clicks later in the session mean what they meant
	# when they were recorded.
	var untooling: PlayerController.DeviceSample = _sample()
	untooling.belt_clicked = true
	ticks.append(untooling)

	# Decide you are ready and pull the lever. A called Wave belongs in the strongest
	# fixture in the suite: it is the one intent that changes *when* the Run gets harder, so
	# a drift in it would be a drift in the whole schedule.
	var calling: PlayerController.DeviceSample = _sample()
	calling.call_wave_clicked = true
	ticks.append(calling)

	# Pull it again a tick later, while the Telegraph it just started is running. Refused,
	# and a refusal belongs in the fixture for the reason a refused build does: it has to be
	# a no-op that replays like any other tick.
	var calling_again: PlayerController.DeviceSample = _sample()
	calling_again.call_wave_clicked = true
	ticks.append(calling_again)

	# Walk at the Nest and try to hand a Delivery over. A Run opens out of reach of it and
	# holding nothing the first tier wants, so this is refused — which is exactly why it
	# belongs here: a refused hand-over has to be a no-op that replays like any other tick,
	# the same claim the refused build and the refused lever above make.
	var handing_over: PlayerController.DeviceSample = _sample()
	handing_over.deliver_clicked = true
	ticks.append(handing_over)

	# ── Weight (#29) ──
	#
	# Hit the sprint key once, which at the shipped setting latches it on, and run. A
	# latched sprint is the controller's own reading of a device, so the fixture is where
	# that reading earns its keep: what was recorded is the resulting intent, so the replay
	# reproduces the gait without reproducing the keypress.
	var sprint_on: PlayerController.DeviceSample = _sample()
	sprint_on.sprint_clicked = true
	sprint_on.sprint_held = true
	sprint_on.forward = 1.0
	ticks.append(sprint_on)
	for tick: int in range(40):
		var running: PlayerController.DeviceSample = _sample()
		running.forward = 1.0
		ticks.append(running)

	# Jump while running, hold the key across the apex, and let go. Then wait out the
	# landing, which has a settle and a camera dip hanging off it.
	for tick: int in range(12):
		var leaping: PlayerController.DeviceSample = _sample()
		leaping.forward = 1.0
		leaping.jump_held = true
		ticks.append(leaping)
	for tick: int in range(40):
		var falling: PlayerController.DeviceSample = _sample()
		falling.forward = 1.0
		ticks.append(falling)

	# Press jump again, held, through a landing — which must not bounce, and must replay
	# not bouncing.
	for tick: int in range(90):
		var bouncing: PlayerController.DeviceSample = _sample()
		bouncing.jump_held = true
		ticks.append(bouncing)

	# Stop sprinting, holster the Build Gun and pull the trigger with the weapon out. The
	# same button that placed a Machine forty ticks ago now fires, which is the whole of
	# what the mode switch is for — and a mode switch has to replay or every click after it
	# means something different.
	var sprint_off: PlayerController.DeviceSample = _sample()
	sprint_off.sprint_clicked = true
	ticks.append(sprint_off)

	var holstering: PlayerController.DeviceSample = _sample()
	holstering.build_mode_clicked = true
	ticks.append(holstering)
	for tick: int in range(30):
		var shooting: PlayerController.DeviceSample = _sample()
		shooting.fire_held = true
		shooting.place_clicked = true
		ticks.append(shooting)

	# And back, with the same two readings of the same button, which must place again.
	var drawing: PlayerController.DeviceSample = _sample()
	drawing.build_mode_clicked = true
	drawing.fire_held = true
	drawing.place_clicked = true
	ticks.append(drawing)

	for tick: int in range(120):
		ticks.append(_sample())

	return ticks


## Drives the controller against a live Simulation and captures what crossed, tick by
## tick. The Simulation here is a throwaway: it exists so the controller has state to read
## its aim and its selection out of, exactly as it would in a frame loop.
func _record_session() -> InputScript:
	var sim: Simulation = Simulation.new(SEED, PLAYERS)
	var controller: PlayerController = PlayerController.new()
	var script: InputScript = InputScript.new()

	for sample: PlayerController.DeviceSample in _session():
		var actions: Array = controller.actions_for_tick(sim, 0, sample)
		script.add_tick(actions)
		sim.step(actions)

	return script


func test_determinism_a_recorded_session_of_walking_and_building_replays_identically() -> void:
	var script: InputScript = _record_session()
	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())
	assert_eq(
		divergence.ticks_compared,
		script.tick_count() + 1,
		"every tick of the session was compared, plus the starting state"
	)


func test_the_recorded_session_really_walked_looked_surveyed_and_built() -> void:
	# A fixture that did nothing would replay perfectly and prove nothing. This is the
	# assertion that keeps the one above honest.
	var script: InputScript = _record_session()
	var sim: Simulation = Simulation.new(SEED, PLAYERS)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))

	assert_true(sim.query_machine_count() >= 1, "the session built a Factory")
	assert_eq(
		sim.query_delivery_goods_delivered(sim.query_delivery_goods(0)[0]),
		0,
		"and the Delivery it tried to hand over really was refused"
	)
	assert_true(sim.query_belt_count() >= 1, "including a Belt")
	# The honesty check on the drag, and the thing a replay of a route that never happened
	# would read as green while proving nothing. A route that cornered is **two** Belts whose
	# runs are at right angles and which meet end to end, so that is what is asserted rather
	# than a Belt count.
	assert_eq(sim.query_belt_count(), 2, "the dragged route turned a corner")
	assert_ne(
		sim.query_belt_direction(0),
		sim.query_belt_direction(1),
		"its two runs are at right angles"
	)
	var first_exit: Vector3i = sim.query_belt_tile(0, sim.query_belt_length_tiles(0) - 1)
	assert_eq(
		first_exit + WorldGrid.direction_step(sim.query_belt_direction(0)),
		sim.query_belt_tile(1, 0),
		"and they meet end to end, which is what makes Items cross the corner"
	)
	assert_false(sim.query_player_is_laying_belt(0), "and the Belt tool went away again")
	assert_ne(sim.query_player_position(0).x, 0, "and walked off the spot")
	assert_ne(sim.query_player_yaw_turns(0), 0, "and looked around while doing it")
	# #29's half of the session. The jump is the one thing in here that is not observable at
	# the end of it — a jump that happened is a player standing back on the ground — so what
	# is asserted is the landing it left behind, which is hashed state.
	assert_true(sim.query_player_is_grounded(0), "the jumps landed")
	assert_true(
		sim.query_player_last_shot_tick(0) >= 0,
		"and the trigger really fired once the weapon was drawn"
	)
	assert_true(
		sim.query_player_is_in_build_mode(0), "and the Build Gun came back out at the end"
	)
	assert_false(sim.query_player_is_sprinting(0), "with the latched sprint turned off again")
	# The session spends a build cost and collects a called Wave's bounty, so what it proves
	# is that materials *moved* — the two are asserted apart in `test_build_gun` and
	# `test_heat`, and pinning the arithmetic of both here would only duplicate them.
	assert_ne(
		sim.query_player_item(0, "iron_plate"),
		sim.query_definitions().player_starting_stock_counts[0],
		"and moved materials doing it"
	)


func test_the_session_moves_the_hash_on_almost_every_tick() -> void:
	# A session whose hash sat still would be a session the harness could not tell from a
	# broken one. Idle ticks at the end are the exception, which is why this is "almost".
	var script: InputScript = _record_session()
	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS)

	var distinct: Dictionary = {}
	for tick: int in range(recording.hashes.size()):
		distinct[recording.hash_at(tick)] = true

	assert_true(
		distinct.size() > recording.hashes.size() / 2,
		"expected the state to keep moving, saw %d distinct of %d"
		% [distinct.size(), recording.hashes.size()]
	)


func test_a_recorded_session_replayed_into_a_broken_simulation_is_caught() -> void:
	# The harness has teeth against *this* script, not only against a hand-written one.
	var script: InputScript = _record_session()
	var recording: ReplayRecording = DeterminismHarness.record(script, SEED, PLAYERS)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(
		recording, DriftingSimulation.new(SEED, PLAYERS)
	)
	assert_false(divergence.is_identical, "a Simulation that drifts must not pass")
	assert_true(divergence.tick >= 0)


## A Simulation with a deliberate fault, to prove the fixture above would notice one.
class DriftingSimulation extends Simulation:
	func step(actions: Array) -> void:
		super.step(actions)
		# A single fixed-point unit of drift on one player's position, once. Enough to
		# change the hash and nothing a human watching the game would ever see, which is
		# exactly the class of fault a replay fixture exists to catch.
		if query_tick() == 7:
			_player_x[0] += 1
