## Standing on the Factory: what is solid, what a player can climb, and what happens when
## the Factory closes around them.
##
## #30's whole ticket. Before it, a player collided with the ground and nothing else — you
## walked through a Smelter and jumped through where its roof would be — which made a
## Factory something to stand *in* and never *on*.
##
## Everything here is driven through the façade: `step` with Input Actions, assertions on
## `query_*` and on `hash()`. Expected values come from `content/tuning.toml` and the
## declared heights in `content/machines.csv`, never from restating the resolution code.
##
## The one number every assertion here leans on: a player clears
## `player.jump_height_metres` (1.1 m) plus `player.step_up_height_metres` (0.75 m), so
## 1.85 m is the reach, and that is what separates a Smelter (1.5 m, climbable from the
## ground) from a Steam Boiler (2.2 m, which wants a Belt to launch from).
extends TestCase

## A long way from the Nest, the Breaches and anything else the Map puts on the ground, so
## a test about a wall is a test about a wall. Tile (10, 0, 10) is 20 m east and 20 m south
## of the origin; `MapLayout.empty()` puts the Nest at (-6, -6).
const CLEAR_TILE: Vector3i = Vector3i(10, WorldGrid.GROUND_LAYER, 10)


func _clear_sim(players: int = 1) -> Simulation:
	return Simulation.new(7, players, null, MapLayout.empty())


## Steps a Simulation `ticks` times, re-sending the same intents every tick — which is how
## a throttle and a held key work.
func _hold(sim: Simulation, ticks: int, actions: Array) -> void:
	for _i: int in range(ticks):
		var copied: Array = []
		for action: InputAction in actions:
			copied.append(action)
		sim.step(copied)


## Puts a player's feet at a point in fixed-point metres, by walking the Simulation's own
## state there rather than by teleporting: a test that set a private array would be testing
## something `step` cannot produce. There is no `TELEPORT` intent, so this drives `MOVE`
## until the player is within a tile of where it wants them, and asserts it got there.
##
## Deliberately crude — it is scaffolding, not a mechanic. Walking east is `strafe` at yaw
## 0, and walking south is `strafe` after a half turn is not needed because `forward` at
## yaw 0 is north: the two axes are driven one at a time.
func _walk_to(sim: Simulation, x: int, z: int) -> void:
	for _i: int in range(2000):
		var here: FixedVec2 = sim.query_player_position(0)
		var gap_x: int = x - here.x
		var gap_z: int = z - here.z
		var close_enough: int = Fixed.from_decimal_string("0.05")
		if absi(gap_x) <= close_enough and absi(gap_z) <= close_enough:
			return
		# +x is strafe at yaw 0; -z is forward at yaw 0.
		var strafe: int = Fixed.clamp_fixed(
			Fixed.mul(gap_x, Fixed.from_int(4)), -Fixed.ONE, Fixed.ONE
		)
		var forward: int = Fixed.clamp_fixed(
			Fixed.mul(-gap_z, Fixed.from_int(4)), -Fixed.ONE, Fixed.ONE
		)
		sim.step([InputAction.move(0, forward, strafe)])
	assert_true(false, "the scaffolding failed to walk a player to where a test wanted them")


# ── What is solid ─────────────────────────────────────────────────────────────

func test_bare_ground_is_not_solid_at_all() -> void:
	var sim: Simulation = _clear_sim()
	assert_eq(sim.query_solid_height_metres(CLEAR_TILE), 0, "nothing is standing there")


func test_a_machine_is_solid_to_the_height_its_row_declares() -> void:
	# The Smelter's row says 1.5 m, and the whole 3x3 footprint is solid to it — not only
	# the anchor tile, which is the half of this that a footprint-shaped collision gets
	# wrong.
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	var declared: int = Fixed.from_decimal_string("1.5")
	assert_eq(sim.query_machine_height_metres(0), declared, "the Smelter's declared height")
	for offset_x: int in range(3):
		for offset_z: int in range(3):
			var tile: Vector3i = CLEAR_TILE + Vector3i(offset_x, 0, offset_z)
			assert_eq(
				sim.query_solid_height_metres(tile),
				declared,
				"every tile of the footprint is solid, including %s" % tile
			)


func test_a_taller_machine_is_solid_higher_and_nothing_averages_them() -> void:
	# #24 made the heights vary a lot, and the Simulation has to carry that: a Smelter at
	# 1.5 m and a Steam Boiler at 2.2 m are different things to a player on foot, and one
	# shared constant for "a Machine" would have thrown away the whole point of the art
	# pass.
	var sim: Simulation = _clear_sim()
	var definitions: Definitions = sim.query_definitions()
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), CLEAR_TILE),
		InputAction.build_machine(
			0, definitions.machine_index("steam_boiler_mk1"), CLEAR_TILE + Vector3i(4, 0, 0)
		),
	])
	assert_eq(
		sim.query_solid_height_metres(CLEAR_TILE),
		Fixed.from_decimal_string("1.5"),
		"the Smelter"
	)
	assert_eq(
		sim.query_solid_height_metres(CLEAR_TILE + Vector3i(4, 0, 0)),
		Fixed.from_decimal_string("2.2"),
		"the Boiler, which is 70 cm of difference a player can feel"
	)


func test_a_wall_is_solid_above_what_a_player_can_climb() -> void:
	# A Wall is the one structure whose entire purpose is to stop something, so the claim
	# worth asserting is not its height but that its height is out of reach: above a jump
	# plus a mantle, or a perimeter is a suggestion.
	var sim: Simulation = _clear_sim()
	sim.step([InputAction.build_wall(0, CLEAR_TILE)])
	var height: int = sim.query_wall_height_metres()
	assert_eq(sim.query_solid_height_metres(CLEAR_TILE), height, "a Wall is solid")
	assert_true(
		height > sim.query_player_step_up_height_metres() + Fixed.from_decimal_string("1.1"),
		"a Wall out of reach of a jump and a mantle, got %f" % Fixed.to_float(height)
	)


func test_a_belt_is_solid_at_its_deck_and_a_jump_clears_it() -> void:
	# **The Belt decision, asserted as the two inequalities it is made of.** A Belt is
	# solid — a trestle is a thing in the world — but its deck sits above the step-up and
	# below the jump, so a Belt line stops a walk and never stops a Factory: you hop onto
	# it and walk it. Solid-and-unjumpable would make a Factory a maze; a step-up would
	# make a Belt something a player stops noticing.
	var sim: Simulation = _clear_sim()
	sim.step([InputAction.build_belt(0, CLEAR_TILE, CLEAR_TILE + Vector3i(3, 0, 0))])
	var deck: int = sim.query_belt_deck_height_metres()
	for along: int in range(4):
		assert_eq(
			sim.query_solid_height_metres(CLEAR_TILE + Vector3i(along, 0, 0)),
			deck,
			"every tile of the run is a deck"
		)
	assert_true(
		deck > sim.query_player_step_up_height_metres(),
		"above the step-up, so getting onto a Belt is a hop and not an accident"
	)
	assert_true(
		deck < Fixed.from_decimal_string("1.1"),
		"and below the jump, so a Belt line is never a wall"
	)


func test_the_nest_is_a_climbable_ziggurat_rather_than_a_block() -> void:
	# A 4x4 footprint has exactly one ring and one middle, so the three raked tiers of art
	# quantise to two: the terrace on the ring and the crown in the middle. The terrace is
	# what makes the Nest climbable, and that it is within reach is the assertion.
	var sim: Simulation = _clear_sim()
	var anchor: Vector3i = sim.query_nest_tile()
	var terrace: int = sim.query_nest_terrace_height_metres()
	var crown: int = sim.query_nest_height_metres()
	assert_eq(sim.query_solid_height_metres(anchor), terrace, "the corner is the terrace")
	assert_eq(
		sim.query_solid_height_metres(anchor + Vector3i(1, 0, 1)),
		crown,
		"and the middle is the crown"
	)
	assert_true(crown > terrace, "a ziggurat steps up, it does not step down")
	assert_true(
		terrace <= sim.query_player_step_up_height_metres() + Fixed.from_decimal_string("1.1"),
		"the terrace is within a jump and a mantle of the ground, got %f"
		% Fixed.to_float(terrace)
	)


func test_a_node_and_a_breach_are_ground_rather_than_buildings() -> void:
	# Deliberate: a Node is ground a Miner stands on and a Breach is a hole Enemies come
	# out of. Making either solid would change where a Factory can be laid out rather than
	# what a player can stand on.
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-20, WorldGrid.GROUND_LAYER, -20)
	layout.add_node(CLEAR_TILE, "iron_ore", 1)
	layout.sort_nodes()
	layout.add_breach(CLEAR_TILE + Vector3i(4, 0, 0))
	layout.sort_breaches()
	var sim: Simulation = Simulation.new(7, 1, null, layout)
	assert_eq(sim.query_solid_height_metres(CLEAR_TILE), 0, "a Node is ground")
	assert_eq(
		sim.query_solid_height_metres(CLEAR_TILE + Vector3i(4, 0, 0)), 0, "a Breach is a hole"
	)


# ── Walking into things ───────────────────────────────────────────────────────

func test_a_wall_stops_a_player_walking_into_it() -> void:
	var sim: Simulation = _clear_sim()
	# A Wall on the tile spanning 20 m to 22 m along x, with the player walking east at it
	# from 16 m.
	sim.step([InputAction.build_wall(0, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(16), Fixed.from_int(21))
	_hold(sim, 240, [InputAction.move(0, 0, Fixed.ONE)])

	var stopped: int = sim.query_player_position(0).x
	assert_true(
		stopped < Fixed.from_int(20),
		"a player should be held outside the Wall's tile, got x %f" % Fixed.to_float(stopped)
	)
	assert_true(
		stopped > Fixed.from_decimal_string("19.0"),
		"and held at it rather than metres short, got x %f" % Fixed.to_float(stopped)
	)
	assert_eq(sim.query_player_velocity(0).x, 0, "walking into a Wall is a stop, not a shudder")


func test_a_wall_cannot_be_jumped() -> void:
	var sim: Simulation = _clear_sim()
	sim.step([InputAction.build_wall(0, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(16), Fixed.from_int(21))
	# Jumping and pushing east for four seconds. A Wall stands above a jump plus a mantle,
	# so this must get nowhere at all.
	for _i: int in range(240):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
	assert_true(
		sim.query_player_position(0).x < Fixed.from_int(20),
		"a jump does not get over a Wall, got x %f"
		% Fixed.to_float(sim.query_player_position(0).x)
	)


func test_a_player_walks_round_a_machine_rather_than_through_it() -> void:
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("steam_boiler_mk1")
	# 3x2 anchored at (10,0,10): 20 m to 26 m along x, 20 m to 24 m along z.
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(16), Fixed.from_int(22))
	_hold(sim, 300, [InputAction.move(0, 0, Fixed.ONE)])
	assert_true(
		sim.query_player_position(0).x < Fixed.from_int(20),
		"a Boiler is above reach, so east is closed, got x %f"
		% Fixed.to_float(sim.query_player_position(0).x)
	)
	assert_eq(sim.query_player_height_metres(0), 0, "and they are still on the ground")


# ── Standing on things ────────────────────────────────────────────────────────

func test_a_player_can_jump_onto_a_smelter_and_walk_across_its_roof() -> void:
	# The acceptance criterion in one test. A Smelter is 1.5 m, a jump plus a mantle
	# reaches 1.85 m, so its roof is somewhere a player gets to from the ground — and once
	# up there they are *standing*, which is what makes walking across it possible.
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	# 3x3 anchored at (10,0,10): 20 m to 26 m on both axes.
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(19), Fixed.from_int(23))

	var roof: int = Fixed.from_decimal_string("1.5")
	var landed: bool = false
	for _i: int in range(180):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == roof and sim.query_player_is_grounded(0):
			landed = true
			break
	assert_true(landed, "a jump and a mantle should put a player on the roof")

	var before: int = sim.query_player_position(0).x
	_hold(sim, 60, [InputAction.move(0, 0, Fixed.ONE)])
	assert_eq(sim.query_player_height_metres(0), roof, "and they walk along it, still up")
	assert_true(
		sim.query_player_position(0).x > before,
		"covering ground on the roof rather than standing still on it"
	)
	assert_true(sim.query_player_is_grounded(0), "standing on a roof is standing")


func test_walking_off_a_roof_is_a_fall() -> void:
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	# Straight onto the roof's middle, then east until the roof runs out.
	_walk_to(sim, Fixed.from_int(19), Fixed.from_int(23))
	for _i: int in range(180):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == Fixed.from_decimal_string("1.5"):
			break
	_hold(sim, 300, [InputAction.move(0, 0, Fixed.ONE)])
	assert_eq(sim.query_player_height_metres(0), 0, "off the far edge and back on the ground")
	assert_true(
		sim.query_player_position(0).x > Fixed.from_int(26),
		"past the footprint, got x %f" % Fixed.to_float(sim.query_player_position(0).x)
	)


func test_a_jump_onto_a_belt_line_leaves_a_player_standing_on_the_deck() -> void:
	# The jump-up-onto-something half of the fixture, and the Belt decision in motion.
	var sim: Simulation = _clear_sim()
	sim.step([InputAction.build_belt(0, CLEAR_TILE, CLEAR_TILE + Vector3i(0, 0, 5))])
	_walk_to(sim, Fixed.from_int(18), Fixed.from_int(21))

	# Walking east into it first: the deck is above the step-up, so this stops.
	_hold(sim, 120, [InputAction.move(0, 0, Fixed.ONE)])
	assert_eq(sim.query_player_height_metres(0), 0, "a walk does not climb a trestle")
	assert_true(
		sim.query_player_position(0).x < Fixed.from_int(20),
		"it stops you, got x %f" % Fixed.to_float(sim.query_player_position(0).x)
	)

	var deck: int = sim.query_belt_deck_height_metres()
	var on_the_belt: bool = false
	for _i: int in range(120):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == deck and sim.query_player_is_grounded(0):
			on_the_belt = true
			break
	assert_true(on_the_belt, "but a jump puts you on the deck, and a Belt line is walkable")


func test_a_belt_against_a_boiler_is_the_way_up_onto_it() -> void:
	# The emergent half of the step-up decision, and the reason a Factory is parkour: a
	# Boiler's 2.2 m roof is out of reach from the ground (1.85 m) and in reach from a
	# Belt deck (0.9 + 1.85 = 2.75 m). Nothing in the Simulation knows that; it falls out
	# of two tuned numbers and a declared height.
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("steam_boiler_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	sim.step([
		InputAction.build_belt(
			0, CLEAR_TILE + Vector3i(-1, 0, 0), CLEAR_TILE + Vector3i(-1, 0, 3)
		),
	])
	_walk_to(sim, Fixed.from_int(17), Fixed.from_int(21))

	var roof: int = Fixed.from_decimal_string("2.2")
	var up: bool = false
	for _i: int in range(240):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == roof:
			up = true
			break
	assert_true(up, "a Belt laid against a Boiler is a step onto its roof")


func test_a_run_opens_with_a_player_on_the_ground_and_not_in_the_nest() -> void:
	# The Nest is solid now, and a Run opens at the world origin rather than inside it.
	# Worth pinning: a starting position inside a structure would be the one case the
	# recovery below cannot be allowed to discover.
	var sim: Simulation = Simulation.new()
	assert_eq(sim.query_player_height_metres(0), 0, "both feet on the Map")
	assert_true(sim.query_player_is_grounded(0), "and standing")


# ── Getting stuck, and the one recovery ───────────────────────────────────────

func test_a_machine_built_on_a_standing_player_lifts_them_onto_its_roof() -> void:
	# **The recovery, and it is deliberate rather than a safety net.** The only way to be
	# inside a solid is for the solid to have arrived, and nothing in this Simulation
	# overhangs — so up is the one direction guaranteed to resolve, and it is also what
	# reads correctly: the Machine went up underneath you, so you end up on it.
	var sim: Simulation = _clear_sim(2)
	var index: int = sim.query_definitions().machine_index("steam_boiler_mk1")
	# Player 0 stands in the middle of the tile the Boiler is about to cover.
	_walk_to(sim, Fixed.from_int(21), Fixed.from_int(21))
	assert_eq(sim.query_player_height_metres(0), 0, "on the ground to begin with")

	sim.step([InputAction.build_machine(1, index, CLEAR_TILE)])
	assert_eq(
		sim.query_player_height_metres(0),
		Fixed.from_decimal_string("2.2"),
		"and on the roof of what was built on them"
	)
	assert_true(sim.query_player_is_grounded(0), "standing, not falling")


func test_a_player_lifted_onto_a_roof_can_walk_off_it_again() -> void:
	# The other half of "recoverable": being put on top is only a recovery if it is
	# somewhere a player can leave.
	var sim: Simulation = _clear_sim(2)
	var index: int = sim.query_definitions().machine_index("steam_boiler_mk1")
	_walk_to(sim, Fixed.from_int(21), Fixed.from_int(21))
	sim.step([InputAction.build_machine(1, index, CLEAR_TILE)])
	_hold(sim, 300, [InputAction.move(0, 0, -Fixed.ONE)])
	assert_eq(sim.query_player_height_metres(0), 0, "walked west off the roof and down")


func test_a_player_is_never_left_with_their_feet_inside_a_solid() -> void:
	# The invariant the whole mechanic rests on, asserted as an invariant: whatever is
	# built, wherever a player is, their feet end up at or above the top of every tile
	# they overlap. A Wall is the harder case — it is taller than a Machine and cheaper to
	# spam — so this builds a pocket of them around somebody and then checks.
	var sim: Simulation = _clear_sim(2)
	_walk_to(sim, Fixed.from_int(21), Fixed.from_int(21))
	var walls: Array = []
	for offset_x: int in range(-1, 2):
		for offset_z: int in range(-1, 2):
			walls.append(InputAction.build_wall(1, CLEAR_TILE + Vector3i(offset_x, 0, offset_z)))
	sim.step(walls)

	var tile: Vector3i = WorldGrid.tile_at_metres(
		sim.query_player_position(0).x, sim.query_player_position(0).z
	)
	assert_true(
		sim.query_player_height_metres(0) >= sim.query_solid_height_metres(tile),
		"feet at %f against a solid top of %f"
		% [
			Fixed.to_float(sim.query_player_height_metres(0)),
			Fixed.to_float(sim.query_solid_height_metres(tile)),
		]
	)
	assert_eq(
		sim.query_player_height_metres(0),
		sim.query_wall_height_metres(),
		"sealed in by Walls means standing on top of them, which is a way out"
	)


func test_demolishing_the_thing_you_are_standing_on_drops_you() -> void:
	var sim: Simulation = _clear_sim(2)
	var index: int = sim.query_definitions().machine_index("steam_boiler_mk1")
	_walk_to(sim, Fixed.from_int(21), Fixed.from_int(21))
	sim.step([InputAction.build_machine(1, index, CLEAR_TILE)])
	assert_eq(
		sim.query_player_height_metres(0),
		Fixed.from_decimal_string("2.2"),
		"standing on the Boiler"
	)
	sim.step([InputAction.demolish(1, CLEAR_TILE)])
	assert_false(sim.query_player_is_grounded(0), "the floor went, so they are falling")
	_hold(sim, 120, [])
	assert_eq(sim.query_player_height_metres(0), 0, "and they land on the Map")


# ── What this does not change ─────────────────────────────────────────────────

func test_a_belt_stops_a_player_and_still_lets_a_crawler_over_it() -> void:
	# **The two mechanics are not coupled, and this is the assertion that says so.** An
	# Enemy routes by flowfield and asks whether a tile is walkable; a player asks how high
	# it is. A Belt is solid to one and transparent to the other, and that difference is
	# the point rather than an inconsistency — sharing one obstruction set would have made
	# it impossible.
	var sim: Simulation = _clear_sim()
	sim.step([InputAction.build_belt(0, CLEAR_TILE, CLEAR_TILE + Vector3i(0, 0, 5))])
	assert_true(
		sim.query_solid_height_metres(CLEAR_TILE) > 0, "solid to somebody on foot"
	)
	assert_false(
		sim.query_tile_obstructs_enemies(CLEAR_TILE),
		"and still nothing at all to a Crawler, which crawls over a conveyor"
	)


func test_a_machine_obstructs_both_and_at_its_own_height() -> void:
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	assert_true(sim.query_tile_obstructs_enemies(CLEAR_TILE), "a Factory is a maze to an Enemy")
	assert_eq(
		sim.query_solid_height_metres(CLEAR_TILE),
		Fixed.from_decimal_string("1.5"),
		"and a surface to a player"
	)


# ── Determinism, the hash and the round trip ──────────────────────────────────

func test_where_a_player_is_standing_reaches_the_hash() -> void:
	# The height a player is standing at was already hashed (#29), and collision is what
	# now decides it — so a run in which somebody climbed a Smelter must not hash like one
	# in which they stood beside it.
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(19), Fixed.from_int(23))
	var beside: int = sim.hash()
	for _i: int in range(180):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == Fixed.from_decimal_string("1.5"):
			break
	assert_true(sim.hash() != beside, "standing on the roof is a different state")


func test_a_factory_with_a_player_on_its_roof_saves_and_resumes_identically() -> void:
	# The height field is derived, so `RunSave` leaves it out — and a resumed Run has to
	# rebuild it and agree. That is exactly the claim the flowfield's own round trip makes.
	var sim: Simulation = _clear_sim()
	var index: int = sim.query_definitions().machine_index("smelter_mk1")
	sim.step([InputAction.build_machine(0, index, CLEAR_TILE)])
	_walk_to(sim, Fixed.from_int(19), Fixed.from_int(23))
	for _i: int in range(180):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		if sim.query_player_height_metres(0) == Fixed.from_decimal_string("1.5"):
			break

	var written: String = RunSave.serialise(sim)
	var replacement: Simulation = Simulation.new(
		7, 1, sim.query_definitions(), MapLayout.empty()
	)
	var loaded: RunSave.Load = RunSave.deserialise(
		written, sim.query_definitions(), replacement
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	var restored: Simulation = loaded.simulation
	assert_eq(restored.hash(), sim.hash(), "a Run on a roof round-trips exactly")

	# And both go on agreeing, which is what proves the rebuild rather than the restore.
	for _i: int in range(60):
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		restored.step([InputAction.move(0, 0, Fixed.ONE)])
	assert_eq(restored.hash(), sim.hash(), "and keep agreeing once they are walking again")


## The Factory the replay fixture builds, around the origin a Run opens at.
##
## Geometry worth writing down, because every assertion below is about where things are:
## a player starts at (0 m, 0 m) with a 0.4 m box, two Walls stand on the tiles spanning
## -4 m to -2 m along x, a two-tile Belt run stands on 2 m to 4 m, and a 3x3 Smelter stands
## on 4 m to 10 m. So west is a dead end and east is a staircase.
func _build_the_fixture_factory(definitions: Definitions) -> Array:
	return [
		InputAction.build_wall(0, Vector3i(-2, WorldGrid.GROUND_LAYER, -1)),
		InputAction.build_wall(0, Vector3i(-2, WorldGrid.GROUND_LAYER, 0)),
		InputAction.build_belt(
			0,
			Vector3i(1, WorldGrid.GROUND_LAYER, -1),
			Vector3i(1, WorldGrid.GROUND_LAYER, 0)
		),
		InputAction.build_machine(
			0,
			definitions.machine_index("smelter_mk1"),
			Vector3i(2, WorldGrid.GROUND_LAYER, -1)
		),
	]


func test_determinism_a_wall_stop_a_roof_stand_and_a_jump_up_replay_identically() -> void:
	# The fixture the ticket asks for, with all three events in one script so the replay
	# covers them together: a Wall that stops a walk, a jump that gets a player up onto a
	# Belt deck, and a roof they end up standing on.
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	var script: InputScript = InputScript.new()
	script.add_tick(_build_the_fixture_factory(definitions))
	# West into the Walls, which stops the walk.
	for _i: int in range(90):
		script.add_tick([InputAction.move(0, 0, -Fixed.ONE)])
	# Then east, jumping — up onto the Belt deck and from there onto the Smelter's roof.
	for _i: int in range(240):
		script.add_tick([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		script.add_tick([InputAction.move(0, 0, Fixed.ONE)])
	script.add_idle_ticks(60)

	var recording: ReplayRecording = DeterminismHarness.record(script, 7, 1)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_collision_fixture_really_did_stop_stand_and_climb() -> void:
	# **The honesty check beside the fixture.** A replay of a Run in which none of it
	# happened reads as a passing determinism test, and the failure is silent — so this
	# drives the same script and asserts the three events rather than their absence.
	var sim: Simulation = Simulation.new(7, 1)
	sim.step(_build_the_fixture_factory(sim.query_definitions()))

	var stopped_by_the_wall: bool = false
	for _i: int in range(90):
		sim.step([InputAction.move(0, 0, -Fixed.ONE)])
		if (
			sim.query_player_velocity(0).x == 0
			and sim.query_player_position(0).x < -Fixed.ONE
		):
			stopped_by_the_wall = true
	assert_true(stopped_by_the_wall, "the walk west really did run into the Walls")

	var stood_on_the_deck: bool = false
	var stood_on_the_roof: bool = false
	for _i: int in range(240):
		sim.step([InputAction.move(0, 0, Fixed.ONE), InputAction.jump(0, true)])
		sim.step([InputAction.move(0, 0, Fixed.ONE)])
		var feet: int = sim.query_player_height_metres(0)
		if feet == sim.query_belt_deck_height_metres() and sim.query_player_is_grounded(0):
			stood_on_the_deck = true
		if feet == Fixed.from_decimal_string("1.5") and sim.query_player_is_grounded(0):
			stood_on_the_roof = true
	assert_true(stood_on_the_deck, "and a jump really did put them on the Belt deck")
	assert_true(stood_on_the_roof, "and the climb really did end on the Smelter's roof")
