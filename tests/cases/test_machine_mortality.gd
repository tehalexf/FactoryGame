## Machine mortality: Machines that take damage and are destroyed, Breakers that hunt
## them, Walls that shape where a Wave walks, a Pneumatic Wrench that mends by hand, and a
## Repair Pylon that mends by Recipe. Through the Simulation façade, which is the only seam.
##
## The claim this file stands behind is the one that turns a Factory's layout from a
## logistics decision into a defensive one: **the Factory is something that can be taken
## from you**. Before this, a Crawler walked past a Smelter. After it, where the Smelter
## stands decides whether it survives the Wave.
extends TestCase

## The Nest at the origin covering (0,0) to (3,3), one Breach twenty tiles east on the
## Nest's own lane — far enough out that a Machine can stand between the two and be the
## first thing anything arriving meets.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	layout.add_breach(Vector3i(20, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	return layout


## One Breaker a Breach and never any more, so these tests watch exactly one of them.
const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
shock_breakers,breaker,0,1,0,1
"""

## One Crawler a Breach, for the tests about what a Crawler does *not* do.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## The shipped content with the Telegraph shortened to half a second, so a called Wave
## arrives in thirty ticks rather than twelve seconds. Every other number is the real
## file's, which is what makes the arithmetic below readable against `content/tuning.toml`.
func _content(waves: String = ONE_BREAKER, overrides: Array = []) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
	for pair: PackedStringArray in overrides:
		assert_true(tuning.contains(pair[0]), "the tuning override %s must match" % pair[0])
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning.replace(SHIPPED_STOCK, STOCKED),
		waves,
		DELIVERIES,
		GEAR,
		STRATAGEMS,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## A Run with its first Wave already called, so it arrives half a second in. The lever is
## the honest way to bring a Wave forward in a test: it is the code path a player uses.
func _sim(waves: String = ONE_BREAKER, overrides: Array = []) -> Simulation:
	var sim: Simulation = Simulation.new(11, 1, _content(waves, overrides), _layout())
	sim.step([InputAction.call_wave_early(0)])
	return sim


func _step(sim: Simulation, ticks: int) -> void:
	for i: int in range(ticks):
		sim.step([])


## Builds a Machine by id at a tile and steps the tick that places it.
func _build(sim: Simulation, machine_id: String, tile: Vector3i) -> void:
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index(machine_id), tile)
	])


## Steps until `predicate` holds, and reports how many ticks that took — or -1 if it never
## did inside `limit`. Bounded, so a broken Simulation fails rather than hangs.
func _step_until(sim: Simulation, limit: int, predicate: Callable) -> int:
	for tick: int in range(limit):
		if predicate.call():
			return tick
		sim.step([])
	return -1 if not predicate.call() else limit


# ── A Machine has health ──────────────────────────────────────────────────────

func test_a_machine_is_built_at_the_health_its_row_declares() -> void:
	var sim: Simulation = _sim()
	_build(sim, "smelter_mk1", Vector3i(16, WorldGrid.GROUND_LAYER, 0))
	assert_eq(sim.query_machine_count(), 1)
	assert_eq(sim.query_machine_health(0), 500, "smelter_mk1's health column")
	assert_eq(sim.query_machine_max_health(0), 500, "and it starts whole")


func test_a_breaker_chews_the_machine_it_reaches() -> void:
	var sim: Simulation = _sim()
	_build(sim, "smelter_mk1", Vector3i(16, WorldGrid.GROUND_LAYER, 0))
	var bitten: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_machine_health(0) < 500
	)
	assert_true(bitten != -1, "a Breaker walked to the Smelter and bit it")
	# enemy.breaker_damage is 60 a bite.
	assert_eq(sim.query_machine_health(0), 440, "one bite off the Smelter")
	assert_eq(sim.query_nest_health(), sim.query_nest_max_health(), "and the Nest untouched")


func test_a_machine_chewed_to_nothing_is_destroyed() -> void:
	var sim: Simulation = _sim()
	_build(sim, "smelter_mk1", Vector3i(16, WorldGrid.GROUND_LAYER, 0))
	var gone: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_machine_count() == 0
	)
	assert_true(gone != -1, "500 health at 60 a bite is nine bites")
	assert_eq(sim.query_machine_at_tile(Vector3i(17, WorldGrid.GROUND_LAYER, 1)), -1)
	assert_false(sim.query_run_is_over(), "losing a Machine is survivable; losing the Nest is not")


# ── What a destroyed Machine takes with it ────────────────────────────────────

## A Map whose Nest is far to the south-west, so the ground around the origin is free to
## build on and a player standing where a Run starts them is within wrench reach of it. The
## Breach is twenty tiles east, as always.
func _open_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-30, WorldGrid.GROUND_LAYER, -30)
	layout.add_node(Vector3i(14, WorldGrid.GROUND_LAYER, 0), "iron_ore", 1)
	layout.add_breach(Vector3i(20, WorldGrid.GROUND_LAYER, 1))
	layout.sort_breaches()
	layout.sort_nodes()
	return layout


## A Run on `_open_layout` with the first Wave called.
func _open_sim(waves: String = ONE_BREAKER, overrides: Array = []) -> Simulation:
	var sim: Simulation = Simulation.new(11, 1, _content(waves, overrides), _open_layout())
	sim.step([InputAction.call_wave_early(0)])
	return sim


## A Breaker that flattens whatever it bites in one go, so a test about what destruction
## *does* does not spend nine seconds of game time getting there.
const ONE_SHOT_BREAKER: Array = [["breaker_damage = 60", "breaker_damage = 10000"]]


func test_a_destroyed_machine_breaks_the_belt_chain_through_it() -> void:
	var sim: Simulation = _open_sim(ONE_BREAKER, ONE_SHOT_BREAKER)
	var ground: int = WorldGrid.GROUND_LAYER
	# A Miner on the Node, and a Belt running west out of its output port.
	_build(sim, "miner_mk1", Vector3i(14, ground, 0))
	sim.step([InputAction.build_belt(0, Vector3i(13, ground, 0), Vector3i(10, ground, 0))])

	var loaded: int = _step_until(
		sim, 600, func() -> bool: return sim.query_belt_item_count(0) >= 2
	)
	assert_true(loaded != -1, "the Miner is feeding the Belt")

	var gone: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_machine_count() == 0
	)
	assert_true(gone != -1, "a Breaker reached the Miner and flattened it")

	# The run's entry is against a footprint that is not there any more, so nothing loads
	# onto it ever again. Six hundred ticks is forty Items' worth at the Belt's rated four a
	# second, and the count does not move by one.
	var stranded: int = sim.query_belt_item_count(0)
	_step(sim, 600)
	assert_eq(
		sim.query_belt_item_count(0),
		stranded,
		"the chain is broken: the Belt holds what it was carrying and gains nothing"
	)
	assert_true(
		stranded < sim.query_belt_capacity(0),
		"and it is stalled part-full rather than packed, which is what a cut line looks like"
	)


func test_a_destroyed_machine_takes_its_build_cost_and_its_contents_with_it() -> void:
	var sim: Simulation = _open_sim(ONE_BREAKER, ONE_SHOT_BREAKER)
	var ground: int = WorldGrid.GROUND_LAYER
	_build(sim, "miner_mk1", Vector3i(14, ground, 0))
	# This file's player.starting_stock is iron_plate:200, the lever paid
	# wave.call_early_bounty_per_item of 25 in that bill's one Item, and miner_mk1 costs
	# iron_plate:8.
	assert_eq(sim.query_player_item(0, "iron_plate"), 217, "the build cost was spent")

	var mined: int = _step_until(
		sim, 600, func() -> bool: return sim.query_machine_output(0, "iron_ore") >= 2
	)
	assert_true(mined != -1, "the Miner is holding ore when it falls")

	var gone: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_machine_count() == 0
	)
	assert_true(gone != -1, "and then it falls")

	assert_eq(
		sim.query_player_item(0, "iron_plate"),
		217,
		"destruction is a loss, not a refund — the build cost is gone with it"
	)
	assert_eq(
		sim.query_item_total("iron_ore"),
		0,
		"and so is the ore it was holding, unlike a demolition, which hands everything back"
	)


func test_demolishing_the_same_machine_hands_everything_back() -> void:
	# The contrast that makes the rule above a decision rather than an oversight: taking your
	# own Factory apart destroys nothing (issue #1, user story 7).
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var ground: int = WorldGrid.GROUND_LAYER
	_build(sim, "miner_mk1", Vector3i(14, ground, 0))
	var mined: int = _step_until(
		sim, 600, func() -> bool: return sim.query_machine_output(0, "iron_ore") >= 2
	)
	assert_true(mined != -1)
	var held: int = sim.query_machine_output(0, "iron_ore")
	var carried: int = sim.query_player_item(0, "iron_ore")

	sim.step([InputAction.demolish(0, Vector3i(14, ground, 0))])
	assert_eq(sim.query_machine_count(), 0)
	assert_eq(sim.query_player_item(0, "iron_plate"), 225, "the build cost came back in full")
	assert_eq(
		sim.query_player_item(0, "iron_ore"),
		carried + held,
		"and so did everything it held"
	)


# ── A Breaker prefers a Machine to the Nest ───────────────────────────────────

func test_a_breaker_goes_for_the_factory_and_a_crawler_goes_for_the_nest() -> void:
	# The acceptance criterion that makes mortality *felt*: the same Factory, the same Breach,
	# the same geometry, and two Enemy kinds that choose differently. The Smelter is well off
	# the lane between the Breach and the Nest, so neither Enemy meets it by accident.
	var ground: int = WorldGrid.GROUND_LAYER
	var smelter: Vector3i = Vector3i(16, ground, 8)

	var hunted: Simulation = _sim(ONE_BREAKER)
	_build(hunted, "smelter_mk1", smelter)
	var chewed: int = _step_until(
		hunted, 3000, func() -> bool: return hunted.query_machine_health(0) < 500
	)
	assert_true(chewed != -1, "the Breaker walked off the lane to the Smelter")
	assert_eq(
		hunted.query_nest_health(),
		hunted.query_nest_max_health(),
		"and never touched the Nest on the way"
	)

	var swarming: Simulation = _sim(ONE_CRAWLER)
	_build(swarming, "smelter_mk1", smelter)
	var bitten: int = _step_until(
		swarming, 3000, func() -> bool: return swarming.query_nest_health() < 6000
	)
	assert_true(bitten != -1, "the Crawler went for the Nest")
	assert_eq(
		swarming.query_machine_health(0),
		500,
		"and walked past the Smelter without touching it — Chaff is the sense of threat"
	)


func test_a_breaker_with_nothing_left_to_break_goes_for_the_nest() -> void:
	# The fallback that keeps a Breaker an Enemy rather than a Machine-shaped appetite: a
	# Factory with no Machines leaves its field empty, and an empty field sends it at the Nest.
	var sim: Simulation = _sim(ONE_BREAKER)
	assert_eq(sim.query_machine_count(), 0, "nothing built this Run")
	var bitten: int = _step_until(
		sim, 3000, func() -> bool: return sim.query_nest_health() < 6000
	)
	assert_true(bitten != -1, "it arrived at the Nest and bit it")


# ── Walls ─────────────────────────────────────────────────────────────────────

func test_a_wall_is_built_at_the_health_tuning_declares() -> void:
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var tile: Vector3i = Vector3i(6, WorldGrid.GROUND_LAYER, 6)
	sim.step([InputAction.build_wall(0, tile)])
	assert_eq(sim.query_wall_count(), 1)
	assert_eq(sim.query_wall_tile(0), tile)
	assert_eq(sim.query_wall_health(0), 240, "wall.health")
	assert_eq(sim.query_wall_max_health(), 240)
	assert_eq(sim.query_wall_at_tile(tile), 0)


func test_a_wall_obstructs_enemies() -> void:
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var tile: Vector3i = Vector3i(6, WorldGrid.GROUND_LAYER, 6)
	assert_false(sim.query_tile_obstructs_enemies(tile), "bare ground before the Wall")
	sim.step([InputAction.build_wall(0, tile)])
	assert_true(sim.query_tile_obstructs_enemies(tile), "and solid after it")
	assert_eq(
		sim.query_flow_direction(tile), -1, "the sweep flows around it rather than into it"
	)


func test_a_wall_refuses_a_tile_something_is_already_standing_on() -> void:
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var ground: int = WorldGrid.GROUND_LAYER
	var tile: Vector3i = Vector3i(6, ground, 6)
	sim.step([InputAction.build_wall(0, tile)])

	var before: int = sim.hash()
	sim.step([InputAction.build_wall(0, tile)])
	assert_eq(sim.query_wall_count(), 1, "a second Wall on the same tile is refused")
	assert_eq(
		sim.query_build_wall_refusal(0, tile),
		Simulation.Refusal.OCCUPIED,
		"and the hologram is told why before the click"
	)
	assert_ne(sim.hash(), before, "the tick still happened")

	assert_eq(
		sim.query_build_wall_refusal(0, Vector3i(500, ground, 0)),
		Simulation.Refusal.OFF_THE_MAP
	)
	assert_eq(
		sim.query_build_wall_refusal(0, sim.query_nest_tile()),
		Simulation.Refusal.OCCUPIED,
		"the Nest is not ground to build on"
	)


func test_a_wall_stops_a_machine_and_a_belt_going_over_it() -> void:
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([InputAction.build_wall(0, Vector3i(6, ground, 6))])

	# smelter_mk1 is 3x3, so an anchor at (4,4) covers (6,6).
	assert_eq(
		sim.query_build_refusal(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(4, ground, 4), 0
		),
		Simulation.Refusal.OCCUPIED
	)
	sim.step([InputAction.build_belt(0, Vector3i(6, ground, 4), Vector3i(6, ground, 8))])
	assert_eq(sim.query_belt_count(), 0, "a Belt run cannot cross a Wall either")


func test_demolishing_a_wall_takes_it_down() -> void:
	var sim: Simulation = _open_sim(ONE_CRAWLER)
	var tile: Vector3i = Vector3i(6, WorldGrid.GROUND_LAYER, 6)
	sim.step([InputAction.build_wall(0, tile)])
	assert_eq(sim.query_demolish_refusal(0, tile), Simulation.Refusal.NONE)
	sim.step([InputAction.demolish(0, tile)])
	assert_eq(sim.query_wall_count(), 0)
	assert_false(sim.query_tile_obstructs_enemies(tile), "and the ground is walkable again")


# ── Sealing a Breach buys time; it does not stop a Wave ───────────────────────

## A Map whose Nest is far away and whose single Breach sits six tiles east of the origin,
## so four Walls seal it completely — the field is four-connected, so an orthogonal ring is
## a seal.
##
## **Six tiles east rather than on the origin, because that is where the player is standing.**
## A player who has sent no `MOVE` is at (0, 0), and since #15 a Crawler bites a player it
## can reach before it chews the Wall in front of it — so a Breach at the origin would have
## this fixture measuring the player's hit points instead of the Wall's. Twelve metres is
## well outside `enemy.player_bite_reach_metres`.
func _sealed_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(-30, WorldGrid.GROUND_LAYER, -30)
	layout.add_node(Vector3i(14, WorldGrid.GROUND_LAYER, 3), "iron_plate", 1)
	layout.add_breach(Vector3i(6, WorldGrid.GROUND_LAYER, 0))
	layout.sort_breaches()
	layout.sort_nodes()
	return layout


## The four tiles that ring the Breach, in the order they are built. Index 0 is the one on
## the Breach's +x side, which is the first direction `_structure_in_contact` looks in and
## therefore the Wall a cornered Crawler starts on.
const SEAL_TILES: Array = [Vector3i(7, 0, 0), Vector3i(5, 0, 0), Vector3i(6, 0, 1), Vector3i(6, 0, -1)]


func _seal_the_breach(sim: Simulation) -> void:
	for tile: Vector3i in SEAL_TILES:
		sim.step([InputAction.build_wall(0, Vector3i(tile.x, WorldGrid.GROUND_LAYER, tile.z))])


func test_sealing_a_breach_buys_time_rather_than_stopping_a_wave() -> void:
	# The clause that keeps a Wall a defence rather than a cheese. A sealed pocket leaves the
	# field with no route out, and an Enemy with no route chews what is in its way.
	var sim: Simulation = Simulation.new(11, 1, _content(ONE_CRAWLER), _sealed_layout())
	sim.step([InputAction.call_wave_early(0)])
	_seal_the_breach(sim)
	assert_eq(sim.query_wall_count(), 4)

	var spawned: int = _step_until(sim, 600, func() -> bool: return sim.query_enemy_count() > 0)
	assert_true(spawned != -1, "a Crawler came out into the pocket")

	var chewing: int = _step_until(
		sim, 600, func() -> bool: return sim.query_wall_health(0) < 240
	)
	assert_true(chewing != -1, "and started on the Wall in front of it")
	assert_true(sim.query_enemy_is_attacking(0), "which is what it is doing rather than walking")

	# wall.health is 240 and enemy.crawler_damage is 10 a second, so twenty-four seconds.
	var breached: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_wall_count() == 3
	)
	assert_true(breached != -1, "the seal bought twenty-four seconds and then gave way")
	assert_eq(sim.query_nest_health(), 6000, "the Nest was untouched for all of it")


# ── The Pneumatic Wrench ──────────────────────────────────────────────────────

## A Breaker that bites once and then waits a hundred seconds, so a test can measure a
## repair rate against a Machine that is damaged and no longer being chewed.
const ONE_BITE_BREAKER: Array = [
	["breaker_attack_interval_seconds = 1", "breaker_attack_interval_seconds = 100"]
]


## A damaged Smelter standing at the origin, where a player who has not moved can reach it,
## and the Breaker that damaged it waiting out a hundred-second cooldown.
func _damaged_sim() -> Simulation:
	var sim: Simulation = _open_sim(ONE_BREAKER, ONE_BITE_BREAKER)
	_build(sim, "smelter_mk1", Vector3i(0, WorldGrid.GROUND_LAYER, 0))
	var bitten: int = _step_until(
		sim, 3000, func() -> bool: return sim.query_machine_health(0) < 500
	)
	assert_true(bitten != -1, "the Breaker reached the Smelter and bit it once")
	assert_eq(sim.query_machine_health(0), 440)
	return sim


func test_a_held_wrench_mends_a_machine_at_the_tuned_rate() -> void:
	var sim: Simulation = _damaged_sim()
	var tile: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	assert_eq(
		sim.query_repair_refusal(0, tile),
		Simulation.Refusal.NONE,
		"a player who has not moved is within wrench.reach_metres of the origin tile"
	)

	# wrench.repair_points_per_second is 60 against 60 ticks a second: one point a tick.
	for i: int in range(30):
		sim.step([InputAction.repair(0, tile)])
	assert_eq(sim.query_machine_health(0), 470, "thirty ticks, thirty points")

	for i: int in range(60):
		sim.step([InputAction.repair(0, tile)])
	assert_eq(
		sim.query_machine_health(0), 500, "and it stops at the health its row declares"
	)
	assert_eq(
		sim.query_repair_refusal(0, tile),
		Simulation.Refusal.NOT_DAMAGED,
		"a whole Machine is nothing to mend"
	)


func test_letting_go_of_the_wrench_stops_the_repair() -> void:
	var sim: Simulation = _damaged_sim()
	var tile: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	for i: int in range(10):
		sim.step([InputAction.repair(0, tile)])
	assert_eq(sim.query_machine_health(0), 450)
	_step(sim, 120)
	assert_eq(
		sim.query_machine_health(0), 450, "an intent that is not sent is an intent not held"
	)


func test_a_wrench_refuses_what_it_cannot_reach_and_what_is_not_there() -> void:
	var sim: Simulation = _damaged_sim()
	var ground: int = WorldGrid.GROUND_LAYER
	assert_eq(
		sim.query_repair_refusal(0, Vector3i(40, ground, 40)),
		Simulation.Refusal.NOTHING_THERE,
		"bare ground"
	)
	# The Smelter is 3x3 from the origin, so (2,2) is its far corner — 5 m away against a
	# four-metre reach.
	assert_eq(
		sim.query_repair_refusal(0, Vector3i(2, ground, 2)),
		Simulation.Refusal.OUT_OF_REACH,
		"repairing is melee: a player has to come and stand at it"
	)
	var before: int = sim.query_machine_health(0)
	for i: int in range(60):
		sim.step([InputAction.repair(0, Vector3i(2, ground, 2))])
	assert_eq(sim.query_machine_health(0), before, "and a refused hold mends nothing")


func test_a_wrench_holds_a_machine_against_the_breaker_chewing_it() -> void:
	# The acceptance criterion: repairing by hand works *during* a Wave. Nothing is gated on
	# one, in either direction, for the reason building is not.
	var tile: Vector3i = Vector3i(0, WorldGrid.GROUND_LAYER, 0)

	var abandoned: Simulation = _open_sim(ONE_BREAKER)
	_build(abandoned, "smelter_mk1", tile)
	var lost: int = _step_until(
		abandoned, 3000, func() -> bool: return abandoned.query_machine_count() == 0
	)
	assert_true(lost != -1, "left alone, the Smelter falls")

	var defended: Simulation = _open_sim(ONE_BREAKER)
	_build(defended, "smelter_mk1", tile)
	for i: int in range(lost + 600):
		defended.step([InputAction.repair(0, tile)])
	assert_eq(
		defended.query_machine_count(),
		1,
		"held under the wrench it is still standing long after the other one fell"
	)
	assert_true(
		defended.query_machine_health(0) > 0, "which is what makes melee useful mid-Wave"
	)


# ── The Repair Pylon ──────────────────────────────────────────────────────────

## Content for the Pylon: a Node that yields plate directly, so repair material reaches the
## Pylon's input port over one short Belt rather than through a three-stage chain, and the
## shipped Repair Pylon's own numbers. Nothing about the Pylon is special-cased here — its
## row is `content/machines.csv`'s, copied, and its reach, its pulse and its Recipe are the
## shipped ones. Power is left out of it so a brownout cannot be mistaken for starvation.
const MEND_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
plate_seam_mk1,Plate Seam,miner,2,2,0,0,400,1,0,0,0,0,dig_plate,
repair_pylon_mk1,Repair Pylon Mk1,turret,2,2,0,0,300,0,6,0,40,0,mend_machinery,
"""

const MEND_RECIPES: String = """id,display_name,inputs,outputs,seconds
dig_plate,Dig Plate,,iron_plate:1,0.5
mend_machinery,Mend Machinery,iron_plate:1,,1
"""


func _mend_content(waves: String = ONE_CRAWLER) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	tuning = tuning.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
	return Definitions.parse(
		MEND_MACHINES, MEND_RECIPES, tuning.replace(SHIPPED_STOCK, STOCKED), waves, DELIVERIES,
		GEAR,
		STRATAGEMS,
		"machines.csv", "recipes.csv", "tuning.toml", "waves.csv", "deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## A sealed Breach with a Crawler chewing the Wall in front of it, and a Repair Pylon fed by
## a Belt out of a plate seam standing within reach of that Wall.
##
## The Wall is the thing being mended rather than a Machine because it is the thing an Enemy
## will attack without being coaxed: the Pylon mends both, by the same two lines.
func _pylon_sim() -> Simulation:
	var ground: int = WorldGrid.GROUND_LAYER
	var sim: Simulation = Simulation.new(11, 1, _mend_content(), _sealed_layout())
	sim.step([InputAction.call_wave_early(0)])
	_build(sim, "repair_pylon_mk1", Vector3i(10, ground, 3))
	_build(sim, "plate_seam_mk1", Vector3i(14, ground, 3))
	sim.step([InputAction.build_belt(0, Vector3i(13, ground, 3), Vector3i(12, ground, 3))])
	_seal_the_breach(sim)
	return sim


func test_a_repair_pylon_mends_what_is_being_chewed_nearby() -> void:
	var sim: Simulation = _pylon_sim()
	assert_eq(sim.query_wall_count(), 4)
	assert_true(sim.query_machine_is_repair_pylon(0), "index 0 is the Pylon")

	var fed: int = sim.query_definitions().machine_index("repair_pylon_mk1")
	assert_true(fed != -1, "the Pylon is a row like any other")
	var loaded: int = _step_until(
		sim, 600, func() -> bool: return sim.query_machine_input(0, "iron_plate") > 0
	)
	assert_true(loaded != -1, "repair material arrives over a Belt, into an input port")

	var chewing: int = _step_until(
		sim, 900, func() -> bool: return sim.query_wall_health(0) < 240
	)
	assert_true(chewing != -1, "and the Crawler starts on the Wall")

	# machines.csv gives the Pylon repair 40 a pulse and mend_machinery one pulse a second,
	# against a Crawler's 10 a second: the Wall nets thirty a second and never falls.
	_step(sim, 2400)
	assert_eq(
		sim.query_wall_count(), 4, "forty seconds in, the Wall the Pylon is mending still stands"
	)
	assert_true(
		sim.query_wall_health(0) >= 240 - 10,
		"held within one bite of full health: 40 back a second against 10 taken"
	)
	assert_true(sim.query_turret_last_shot_tick(0) != -1, "because the Pylon has been pulsing")


func test_a_repair_pylon_spends_repair_material_to_do_it() -> void:
	# The Turret bargain, in the other direction: defence costs continuous production, and so
	# does keeping a Factory standing. A Pylon with nothing to spend mends nothing.
	var sim: Simulation = _pylon_sim()
	var chewing: int = _step_until(
		sim, 900, func() -> bool: return sim.query_wall_health(0) < 240
	)
	assert_true(chewing != -1)

	# Cut the supply: the Belt is gone, so the input buffer runs down and stays down.
	sim.step([InputAction.demolish(0, Vector3i(13, WorldGrid.GROUND_LAYER, 3))])
	var dry: int = _step_until(
		sim, 900, func() -> bool: return sim.query_machine_input(0, "iron_plate") == 0
	)
	assert_true(dry != -1, "it spent what it was holding")
	assert_true(sim.query_machine_is_starved(0), "an empty hopper reads as starved")

	var fell: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_wall_count() == 3
	)
	assert_true(fell != -1, "and without material the Wall goes the way it would have anyway")


func test_a_repair_pylon_over_a_whole_factory_does_nothing_at_all() -> void:
	# The same clause that keeps an MG Turret with nothing in reach off the Power grid: a
	# Turret with nothing to do does not work, and `produces_no_items` is the predicate both
	# roles share. Deliberately not starvation — it has its material, it has no patient.
	var ground: int = WorldGrid.GROUND_LAYER
	var sim: Simulation = Simulation.new(11, 1, _mend_content(ONE_CRAWLER), _sealed_layout())
	_build(sim, "repair_pylon_mk1", Vector3i(10, ground, 3))
	_build(sim, "plate_seam_mk1", Vector3i(14, ground, 3))
	sim.step([InputAction.build_belt(0, Vector3i(13, ground, 3), Vector3i(12, ground, 3))])
	var loaded: int = _step_until(
		sim, 600, func() -> bool: return sim.query_machine_input(0, "iron_plate") > 0
	)
	assert_true(loaded != -1)

	var held: int = sim.query_machine_input(0, "iron_plate")
	_step(sim, 300)
	assert_eq(
		sim.query_machine_input(0, "iron_plate"),
		mini(held + 300 / 15, sim.query_machine_input_capacity(0, "iron_plate")),
		"nothing is damaged, so the Pylon has spent not one plate"
	)
	assert_eq(sim.query_turret_last_shot_tick(0), -1, "it has never pulsed")
	assert_false(sim.query_machine_is_starved(0), "and it is not starved — it is simply idle")


# ── Replay fixtures ───────────────────────────────────────────────────────────
# Three scenarios, left behind as recordings the way every ticket is expected to (CLAUDE.md):
# a Breaker destroying a Machine, a repair held through a Wave, and a Repair Pylon pulsing.
# Each one is paired with a second test that drives the identical script through a plain
# Simulation and asserts the scenario actually happened — a fixture that replays a Run in
# which nothing was destroyed and nothing was mended would prove nothing at all.
#
# They run on the starter Map, which is what `DeterminismHarness.record` builds, with the
# shipped Machines, Recipes and tuning and one substitution: a Wave table of Breakers from a
# cold start. `content/waves.csv` holds the Breaker tier behind 500 Heat, which is correct
# balance and the wrong thing to wait for in a fixture.

## Shipped content with the Telegraph shortened and the Wave table replaced by Breakers from
## the first Wave. Passed to `record` rather than left null, which the harness supports for
## exactly this: a scenario the shipped files cannot produce quickly.
func _fixture_content(waves: String = ONE_BREAKER) -> Definitions:
	var definitions: Definitions = _content(waves)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	return definitions


## The tile the fixtures put a victim Smelter on: in the lane between the starter Map's
## Breach at (16,-6) and its Nest at (-6,-6), so a Breaker meets it on the way.
const FIXTURE_VICTIM_TILE: Vector3i = Vector3i(10, 0, -6)

## The tile the repair fixture puts its Smelter on: the origin, which is where a Run starts a
## player standing, so a held wrench is inside `wrench.reach_metres` without walking.
const FIXTURE_WRENCH_TILE: Vector3i = Vector3i(0, 0, 0)


func _at(tile: Vector3i) -> Vector3i:
	return Vector3i(tile.x, WorldGrid.GROUND_LAYER, tile.z)


## Tick 0 of every fixture: stand a Machine up and pull the lever.
func _opening_tick(definitions: Definitions, tile: Vector3i) -> Array:
	return [
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), _at(tile)),
		InputAction.call_wave_early(0),
	]


func _destruction_script(definitions: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick(_opening_tick(definitions, FIXTURE_VICTIM_TILE))
	# Long enough for the Breaker to cross six metres and spend nine bites on a Smelter.
	script.add_idle_ticks(25 * Simulation.TICKS_PER_SECOND)
	return script


func test_determinism_a_breaker_destroying_a_machine_replays_identically() -> void:
	var definitions: Definitions = _fixture_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_destruction_script(definitions), 7, 1, definitions
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_destruction_fixture_really_did_destroy_a_machine() -> void:
	var definitions: Definitions = _fixture_content()
	var sim: Simulation = Simulation.new(7, 1, definitions, MapLayout.starter())
	var script: InputScript = _destruction_script(definitions)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
	assert_eq(sim.query_machine_count(), 0, "the Smelter was chewed to nothing")
	assert_eq(sim.query_nest_health(), sim.query_nest_max_health(), "and the Nest never was")


func _wrench_script(definitions: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick(_opening_tick(definitions, FIXTURE_WRENCH_TILE))
	# Twenty-two seconds for the Breaker to walk the forty metres from the Breach to the
	# origin and get a few bites in, then twenty-five seconds of a player holding the wrench
	# on it while it is being chewed.
	script.add_idle_ticks(22 * Simulation.TICKS_PER_SECOND)
	for tick: int in range(25 * Simulation.TICKS_PER_SECOND):
		script.add_tick([InputAction.repair(0, _at(FIXTURE_WRENCH_TILE))])
	return script


func test_determinism_a_repair_held_through_a_wave_replays_identically() -> void:
	var definitions: Definitions = _fixture_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_wrench_script(definitions), 7, 1, definitions
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_repair_fixture_really_did_repair_under_attack() -> void:
	var definitions: Definitions = _fixture_content()
	var sim: Simulation = Simulation.new(7, 1, definitions, MapLayout.starter())
	var script: InputScript = _wrench_script(definitions)

	var ever_rose: bool = false
	var ever_fell: bool = false
	var previous: int = sim.query_machine_health(0)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		if sim.query_machine_count() == 0:
			break
		var now: int = sim.query_machine_health(0)
		if now > previous:
			ever_rose = true
		if now < previous:
			ever_fell = true
		previous = now

	assert_true(ever_fell, "the Breaker bit the Smelter")
	assert_true(ever_rose, "and the wrench put hit points back while it was doing it")
	assert_eq(sim.query_machine_count(), 1, "which is what kept the Smelter standing")


## The Factory the Pylon fixture builds, in one tick: a Miner on the starter Map's iron ore,
## a Smelter it feeds, a Repair Pylon the Smelter feeds, and a second Smelter out in the lane
## from the Breach for the Breaker to chew. The Pylon stands within its six-tile reach of
## that victim and well out of the Breaker's way.
func _pylon_machines(definitions: Definitions) -> Array:
	var ground: int = WorldGrid.GROUND_LAYER
	var miner: int = definitions.machine_index("miner_mk1")
	var smelter: int = definitions.machine_index("smelter_mk1")
	var pylon: int = definitions.machine_index("repair_pylon_mk1")
	return [
		InputAction.build_machine(0, smelter, Vector3i(10, ground, -6)),
		InputAction.build_machine(0, pylon, Vector3i(9, ground, -2)),
		InputAction.build_machine(0, miner, Vector3i(4, ground, 4)),
		InputAction.build_machine(0, smelter, Vector3i(9, ground, 4)),
		InputAction.call_wave_early(0),
	]


func _pylon_belts() -> Array:
	var ground: int = WorldGrid.GROUND_LAYER
	return [
		# Ore out of the Miner's east port into the plate Smelter's west port.
		InputAction.build_belt(0, Vector3i(6, ground, 4), Vector3i(8, ground, 4)),
		# Plate out of that Smelter's north port into the Pylon's south port.
		InputAction.build_belt(0, Vector3i(9, ground, 3), Vector3i(9, ground, 0)),
	]


## The Pylon fixture's content: the same again, with a gentler Breaker.
##
## Not a thumb on the scales — it is what makes the fixture a fixture *of the Pylon*. At the
## shipped sixty a bite the victim Smelter falls in eight seconds, which is less time than the
## Miner, the Smelter and two Belts behind the Pylon take to deliver its first plate, so the
## recording would be of a Pylon that never pulsed. Twenty a bite gives the supply chain time
## to reach it, which is the scenario worth having a recording of.
func _pylon_content() -> Definitions:
	return _content(ONE_BREAKER, [PackedStringArray(["breaker_damage = 60", "breaker_damage = 20"])])


func _pylon_script(definitions: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick(_pylon_machines(definitions))
	script.add_tick(_pylon_belts())
	script.add_idle_ticks(40 * Simulation.TICKS_PER_SECOND)
	return script


func test_determinism_a_repair_pylon_mending_under_attack_replays_identically() -> void:
	var definitions: Definitions = _pylon_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_pylon_script(definitions), 7, 1, definitions
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_pylon_fixture_really_did_mend_something() -> void:
	var definitions: Definitions = _pylon_content()
	var sim: Simulation = Simulation.new(7, 1, definitions, MapLayout.starter())
	var script: InputScript = _pylon_script(definitions)

	var pulsed: bool = false
	var mended: bool = false
	var previous: int = 0
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		var pylon: int = sim.query_machine_at_tile(Vector3i(9, WorldGrid.GROUND_LAYER, -2))
		if pylon == -1:
			continue
		if sim.query_turret_last_shot_tick(pylon) != -1:
			pulsed = true
		var victim: int = sim.query_machine_at_tile(Vector3i(10, WorldGrid.GROUND_LAYER, -6))
		var now: int = 0 if victim == -1 else sim.query_machine_health(victim)
		if now > previous and previous > 0:
			mended = true
		previous = now

	assert_true(pulsed, "the Pylon spent repair material")
	assert_true(mended, "and hit points went back onto the Machine the Breaker was chewing")


# ── Saving and resuming ───────────────────────────────────────────────────────

func test_a_damaged_factory_round_trips_through_a_save() -> void:
	# The cheapest acceptance criterion in the project, and the one the whole save file's
	# promise reduces to: a Run written out and read back hashes to what it hashed to before.
	# Everything this ticket added — Machine health, the Walls and their health, each player's
	# unspent repair credit — is reflected over by `RunSave` without that file naming any of it.
	var sim: Simulation = _damaged_sim()
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([InputAction.build_wall(0, Vector3i(6, ground, 6))])
	# A fraction of a hit point of repair banked mid-mend, so the credit array is not zero.
	sim.step([InputAction.repair(0, Vector3i(0, ground, 0))])
	assert_true(sim.query_machine_health(0) < sim.query_machine_max_health(0))
	assert_eq(sim.query_wall_count(), 1)

	var content: Definitions = _content(ONE_BREAKER, ONE_BITE_BREAKER)
	var loaded: RunSave.Load = RunSave.deserialise(
		RunSave.serialise(sim),
		content,
		Simulation.new(0, 1, content, MapLayout.empty())
	)
	assert_false(loaded.has_errors(), loaded.describe_errors())
	assert_eq(
		loaded.simulation.hash(), sim.hash(), "the same integer, over a Factory under attack"
	)
	assert_eq(loaded.simulation.query_machine_health(0), sim.query_machine_health(0))
	assert_eq(loaded.simulation.query_wall_health(0), 240)
	assert_true(
		loaded.simulation.query_tile_obstructs_enemies(Vector3i(6, ground, 6)),
		"and the fields rebuild from the restored Walls rather than being carried in the file"
	)


# ── Fixtures that keep progression out of the way ─────────────────────────────
# The shipped Delivery chain and the shipped opening stock are balance, and neither is what
# this file asserts: a Run opens holding exactly the 80 plate one line costs
# (`content/tuning.toml`), which is not enough to build and rebuild the way these tests do.
# So the stock becomes an explicit 200 plate — plate only, because `call_early_bounty_per_item`
# pays out in the opening bill's Items and an ore bounty would put ore in a player's pockets
# that the destruction tests need to come from a Miner — and the tier locks nothing, so
# nothing here is refused as `CONTENT_IS_LOCKED`. `test_delivery.gd` is where the real chain
# and the real bill are asserted.

const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:80"'
const STOCKED: String = 'starting_stock = "iron_plate:200"'

## The Gear a Run is holding, inline so the fixture is a complete definition set. One
## weapon frame and whatever component this file's Delivery tiers name, because a tier
## naming Gear that does not exist is content somebody broke. These tests are not about
## combat, so the frame is the Pneumatic Wrench and nothing is fitted to it.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""


## A Stratagem table that is not what this file is about. One row, so the table is not empty —
## `Definitions` refuses an empty one, because a Silo with nothing to load is a Machine a
## player can build, feed and never use. `test_silo.gd` is where the shipped table is
## asserted, exactly as `test_delivery.gd` is where the shipped Delivery chain is.
const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""
