## Delivery progression at the Nest — through the Simulation façade, which is the only
## seam (CLAUDE.md).
##
## Progression is physical (GLOSSARY.md, DESIGN.md): there is no research menu and no
## science resource, so the whole of it is goods arriving at the Nest and content becoming
## buildable. The three things this file is built to protect:
##
## 1. **A completed Delivery unlocks exactly its own tier.** Nothing by implication, and
##    nothing a hot-reload that resorts the table can relabel.
## 2. **Locked content cannot be built, and the player is told why.** One function answers
##    both the placement and the reason, so the two can never disagree.
## 3. **Depth gates what is possible to deliver.** Measured off the Miners standing on the
##    Map rather than off a flag, so a player can argue with it.
extends TestCase

const SEED: int = 11
const GROUND: int = WorldGrid.GROUND_LAYER

## The Nest a couple of tiles off the origin, so a player standing where a Run starts them
## is within `nest.delivery_reach_metres` of its footprint without standing inside it. One
## iron Node at Depth 1 well clear of that footprint, and one at Depth 2 further out, so the
## Depth gate has somewhere to be opened from.
const SHALLOW_NODE: Vector3i = Vector3i(10, GROUND, 0)
const DEEP_NODE: Vector3i = Vector3i(16, GROUND, 0)


func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(1, GROUND, 1)
	layout.add_node(SHALLOW_NODE, "iron_ore", 1)
	layout.add_node(DEEP_NODE, "iron_ore", 2)
	layout.sort_nodes()
	return layout


## The same Map with the Nest pushed well out of reach of where a Run starts a player, so a
## hand-over made from the spawn point is a hand-over made from too far away.
func _distant_nest_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.nest_tile = Vector3i(30, GROUND, 30)
	return layout


const MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,0,0,400,1,0,0,0,mine_iron_ore,iron_plate:2
miner_mk2,Miner Mk2,miner,2,2,0,0,500,2,0,0,0,mine_iron_ore,iron_plate:4
press_mk1,Press Mk1,crafter,2,2,0,0,500,0,0,0,0,press_iron_frame,iron_plate:2
"""

const RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.1
press_iron_frame,Press Iron Frame,iron_plate:2,iron_frame:1,1
"""

## Two tiers. The first wants ore and unlocks the Press, a Gear component and a Stratagem;
## the second sits at Depth 2, which only Miner Mk2 standing on the deep Node reaches.
##
## Miner Mk2 is unlocked by the first tier as well, which is what lets one Run walk the
## whole chain: deliver, unlock the deeper Miner, mine deeper, and the second tier opens.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:3,press_mk1;miner_mk2,drum_magazine,resupply_drop
t02_deep,Deep Licence,2,iron_frame:1,,reflex_sight,orbital_barrage
"""

const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""

## Plate to build with and ore to hand over. Nothing else: this file is about what the Nest
## will take, so what a player is holding has to be exactly what the fixture says.
const TUNING: String = """[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
walk_acceleration_metres_per_second_squared = 24
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
starting_stock = "iron_ore:4;iron_plate:20"
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
[wall]
health = 240
[wrench]
repair_points_per_second = 60
reach_metres = 4
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
[depth]
draw_percent_per_depth = 60
breach_tier = 2
breach_crafts = 40
breach_offset_tiles = 6
breach_telegraph_seconds = 45
[enemy]
crawler_health = 30
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
breaker_health = 240
breaker_speed_metres_per_second = 2
breaker_damage = 60
breaker_attack_interval_seconds = 1
"""


func _content(
	deliveries: String = DELIVERIES, machines: String = MACHINES, tuning: String = TUNING
) -> Definitions:
	return Definitions.parse(
		machines,
		RECIPES,
		tuning,
		WAVES,
		deliveries,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv"
	)


func _sim(layout: MapLayout = null) -> Simulation:
	var content: Definitions = _content()
	assert_false(content.has_errors(), content.describe_errors())
	return Simulation.new(SEED, 1, content, _layout() if layout == null else layout)


func _index(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


## Stands a Miner over a Node, which is how a Factory reaches a Depth. The footprint is 2x2
## anchored on the Node's own tile, so it covers it.
func _mine(sim: Simulation, machine_id: String, node: Vector3i) -> void:
	sim.step([InputAction.build_machine(0, _index(sim, machine_id), node)])


# ── The Nest accepts a Delivery ───────────────────────────────────────────────

func test_the_nest_accepts_the_goods_the_open_tier_names() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)

	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.NONE, "ore in hand, at the Nest")
	sim.step([InputAction.deliver_to_nest(0)])

	# Three of the four ore crossed the counter, because three is what the tier asked for —
	# which is also the whole bill, so the tier settles on the same tick and the counter is
	# cleared behind it.
	assert_true(sim.query_delivery_is_complete(0), "the bill was met")
	assert_eq(sim.query_player_item(0, "iron_ore"), 1, "and the fourth ore stayed in hand")


func test_the_nest_takes_a_delivery_in_instalments() -> void:
	# Goods arrive off a Belt one Item at a time, so the counter has to hold a part-paid bill
	# rather than demanding the whole thing in one trip.
	var sim: Simulation = _sim(_belt_layout())
	_belt_fed_miner(sim)

	var part_paid: int = 0
	for tick: int in range(600):
		sim.step([])
		part_paid = sim.query_delivery_goods_delivered("iron_ore")
		if part_paid > 0 and part_paid < 3:
			break
	assert_true(part_paid > 0 and part_paid < 3, "the bill is part paid, at %d of 3" % part_paid)
	assert_false(sim.query_delivery_is_complete(0), "and not settled until it is met in full")

	for tick: int in range(600):
		sim.step([])
		if sim.query_delivery_is_complete(0):
			break
	assert_true(sim.query_delivery_is_complete(0), "the last instalment completed it")


# ── Completing one unlocks exactly its tier ───────────────────────────────────

func test_completing_a_delivery_unlocks_exactly_its_own_tier_and_nothing_else() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	var press: int = _index(sim, "press_mk1")
	assert_false(sim.query_machine_is_unlocked(press), "the premise: the Press starts locked")

	sim.step([InputAction.deliver_to_nest(0)])

	assert_true(sim.query_delivery_is_complete(0), "the first tier is paid")
	assert_false(sim.query_delivery_is_complete(1), "and the second is not")
	assert_true(sim.query_machine_is_unlocked(press), "its Machine is buildable")
	assert_eq(
		sim.query_unlocked_gear(),
		PackedStringArray(["drum_magazine"]),
		"its Gear component and nothing from the tier after it"
	)
	assert_eq(
		sim.query_unlocked_stratagems(),
		PackedStringArray(["resupply_drop"]),
		"and its Stratagem alone"
	)
	assert_eq(sim.query_completed_deliveries(), PackedStringArray(["t01_opening"]))


func test_a_completed_delivery_changes_no_number_anywhere() -> void:
	# "Unlocks are Machines, Gear components and Stratagems, never stat increases." The
	# Delivery table has no numeric column at all, so the strongest statement of that is
	# that the whole definition set — every tuning value and every Machine's row — is the
	# same integer before and after a tier completes.
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	var before: int = sim.query_definition_digest()

	sim.step([InputAction.deliver_to_nest(0)])

	assert_true(sim.query_delivery_is_complete(0), "a tier really did complete")
	assert_eq(sim.query_definition_digest(), before, "and the content it is playing is unchanged")


func test_the_next_delivery_is_the_first_one_not_yet_completed() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_next_delivery(), 0)
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_next_delivery(), 1, "the chain moved on by exactly one")


# ── What the next Delivery requires is visible ────────────────────────────────

func test_what_the_next_delivery_requires_is_readable_before_it_is_paid() -> void:
	# A player aiming a Factory at a goal they cannot read is guessing, so every part of the
	# bill is a query: which tier, what it wants, how much of it has arrived, and the Depth
	# it is gated at.
	var sim: Simulation = _sim()
	var next: int = sim.query_next_delivery()

	assert_eq(sim.query_delivery_id(next), "t01_opening")
	assert_eq(sim.query_delivery_display_name(next), "Opening Licence")
	assert_eq(sim.query_delivery_goods(next), PackedStringArray(["iron_ore"]))
	assert_eq(sim.query_delivery_goods_required(next, "iron_ore"), 3)
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 0, "nothing has arrived yet")
	assert_eq(sim.query_delivery_min_depth(next), 1)
	assert_eq(sim.query_delivery_count(), 2, "and how long the chain is")


func test_the_counter_is_cleared_when_a_tier_completes() -> void:
	# What the Nest is holding is always holdings against the tier it is waiting on, so a
	# HUD reading "2/3" can never be a surplus left over from the tier before.
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 0, "the counter is empty again")
	assert_eq(sim.query_delivery_goods_required(1, "iron_frame"), 1, "against a fresh bill")


# ── Locked content cannot be built ────────────────────────────────────────────

func test_a_machine_no_delivery_has_unlocked_cannot_be_built_and_the_refusal_says_why() -> void:
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	var tile: Vector3i = Vector3i(20, GROUND, 20)

	assert_not_null(
		sim.query_definitions().machine("press_mk1"), "the definition exists, which is the point"
	)
	assert_eq(
		sim.query_build_refusal(0, press, tile, 0),
		Simulation.Refusal.CONTENT_IS_LOCKED,
		"and the hologram is told why before the click"
	)

	var before: int = sim.hash()
	sim.step([InputAction.build_machine(0, press, tile)])
	assert_eq(sim.query_machine_count(), 0, "nothing was placed")
	assert_ne(sim.hash(), before, "a tick passed")
	assert_eq(sim.query_player_item(0, "iron_plate"), 20, "and nothing was charged for it")


func test_the_same_machine_builds_once_a_delivery_has_unlocked_it() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])

	var press: int = _index(sim, "press_mk1")
	var tile: Vector3i = Vector3i(20, GROUND, 20)
	assert_eq(sim.query_build_refusal(0, press, tile, 0), Simulation.Refusal.NONE)
	sim.step([InputAction.build_machine(0, press, tile)])
	assert_eq(sim.query_machine_count(), 2, "the Miner and the Press it paid for")


func test_a_locked_machine_may_still_be_put_on_the_build_gun() -> void:
	# The reason belongs on the hologram, which means a player has to be able to aim a locked
	# Machine and read why it will not go down. Refusing the selection as well would be the
	# second gate CLAUDE.md says must not exist.
	var sim: Simulation = _sim()
	var press: int = _index(sim, "press_mk1")
	sim.step([InputAction.select_machine(0, press)])
	assert_eq(sim.query_player_selected_machine(0), "press_mk1", "it is on the gun")
	assert_eq(
		sim.query_build_refusal(0, press, Vector3i(20, GROUND, 20), 0),
		Simulation.Refusal.CONTENT_IS_LOCKED,
		"and the gun says why"
	)


func test_a_run_opens_with_an_unlocked_machine_on_the_build_gun() -> void:
	# `press_mk1` sorts after `miner_mk1` and before `miner_mk2`, and two of those three are
	# locked, so a Build Gun that simply took the first row would open holding something the
	# Simulation refuses to place.
	var sim: Simulation = _sim()
	assert_eq(sim.query_player_selected_machine(0), "miner_mk1")
	assert_eq(
		sim.query_build_refusal(
			0, _index(sim, "miner_mk1"), Vector3i(20, GROUND, 20), 0
		),
		Simulation.Refusal.NONE,
		"and what it is holding is buildable"
	)


# ── Depth gates which Deliveries are available ────────────────────────────────

func test_the_depth_reached_is_the_deepest_node_a_miner_is_actually_working() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_depth_reached(), 0, "a Factory with no Miner has reached no Depth")

	_mine(sim, "miner_mk1", SHALLOW_NODE)
	assert_eq(sim.query_depth_reached(), 1)

	# A Mk1 parked on the Depth 2 Node reaches nothing further: `max_depth` is 1 in its row.
	_mine(sim, "miner_mk1", DEEP_NODE)
	assert_eq(sim.query_depth_reached(), 1, "max_depth is a limit and not a label")


func test_a_delivery_above_the_depth_the_factory_mines_at_is_refused() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_next_delivery(), 1, "the premise: the Depth 2 tier is next")

	# The player is holding no iron frame either, but Depth is the reason reported, because
	# it is the one a bigger pile of goods cannot fix.
	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.DEPTH_TOO_SHALLOW)


func test_mining_deeper_opens_the_tier_that_was_gated() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.DEPTH_TOO_SHALLOW, "the premise")

	# Miner Mk2 is what the first tier bought, and standing it on the deep Node is what opens
	# the second — the chain pays for the tool that opens the gate on the tier after it.
	_mine(sim, "miner_mk2", DEEP_NODE)
	assert_eq(sim.query_depth_reached(), 2)
	assert_eq(
		sim.query_delivery_refusal(0),
		Simulation.Refusal.NOTHING_TO_DELIVER,
		"the Depth gate is open, and what is missing now is the goods"
	)


# ── A Belt into the Nest pays the Delivery ────────────────────────────────────

func test_a_belt_is_refused_by_a_nest_whose_next_tier_is_out_of_depth() -> void:
	# The gate is on the Delivery, not on who is offering, so a Factory piping ore at a Nest
	# waiting on a tier it cannot reach is refused exactly as a player would be — and the ore
	# stays on the Belt rather than disappearing.
	var sim: Simulation = _sim(_belt_layout())
	_belt_fed_miner(sim)
	for tick: int in range(1200):
		sim.step([])
		if sim.query_delivery_is_complete(0):
			break
	assert_true(sim.query_delivery_is_complete(0), "the premise: the first tier is paid")
	assert_eq(sim.query_next_delivery(), 1, "and the gated tier is next")

	var held: int = sim.query_delivery_goods_delivered("iron_ore")
	for tick: int in range(600):
		sim.step([])
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), held, "no more ore crossed")
	assert_eq(sim.query_delivery_goods_delivered("iron_frame"), 0, "and no frame did either")
	assert_true(sim.query_belt_is_stalled(0), "the Belt stalled against a closed counter")


func test_a_belt_running_into_the_nest_pays_the_open_delivery() -> void:
	# This is what makes progression something the Factory does. The Miner is three tiles
	# east of the Nest's edge and a Belt carries its ore back into it.
	var sim: Simulation = _sim(_belt_layout())
	_belt_fed_miner(sim)
	assert_eq(sim.query_belt_count(), 1, "the premise: one Belt pointing at the Nest")

	for tick: int in range(600):
		sim.step([])
		if sim.query_delivery_is_complete(0):
			break

	assert_true(sim.query_delivery_is_complete(0), "the Factory paid its own Delivery")
	assert_true(
		sim.query_machine_is_unlocked(_index(sim, "press_mk1")),
		"and the unlock landed without a player carrying a thing"
	)


## The same Map with the Node close enough east of the Nest for one Belt to join the two.
## The Nest covers tiles 1..4 along both axes, so the Miner anchors at tile 8 and its Belt
## runs west from tile 7 to tile 5, handing off into the Nest tile at 4.
func _belt_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(1, GROUND, 1)
	layout.add_node(Vector3i(8, GROUND, 1), "iron_ore", 1)
	layout.sort_nodes()
	return layout


## A Miner over that Node with a Belt out of it and into the Nest. Two ticks, because a Belt
## is refused on a tile a Machine already stands on and the two arriving together would
## depend on the order within one tick.
func _belt_fed_miner(sim: Simulation) -> void:
	sim.step([InputAction.build_machine(0, _index(sim, "miner_mk1"), Vector3i(8, GROUND, 1))])
	sim.step([InputAction.build_belt(0, Vector3i(7, GROUND, 1), Vector3i(5, GROUND, 1))])


func test_a_belt_carrying_what_the_nest_does_not_want_backs_up_rather_than_vanishing() -> void:
	# Nothing in this game destroys Items. A Nest that has stopped wanting ore refuses the
	# hand-off, so the queue packs up behind it where a player can see it — the same way a
	# full input buffer reads.
	var sim: Simulation = _sim(_belt_layout())
	_belt_fed_miner(sim)

	for tick: int in range(1200):
		sim.step([])

	assert_true(sim.query_delivery_is_complete(0), "the first tier was paid on the way")
	assert_true(sim.query_belt_is_full(0), "and the Belt behind it has packed solid")
	assert_true(sim.query_belt_is_stalled(0), "stalled rather than quietly swallowing ore")


# ── Refusals are a query, and a refused hand-over is a no-op ──────────────────

func test_a_delivery_handed_over_out_of_reach_is_refused_by_name() -> void:
	var sim: Simulation = _sim(_distant_nest_layout())
	_mine(sim, "miner_mk1", SHALLOW_NODE)

	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.TOO_FAR_FROM_THE_NEST)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_player_item(0, "iron_ore"), 4, "the ore is still in hand")
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 0, "and the counter is untouched")


func test_a_hand_over_with_nothing_the_nest_wants_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	# Tier two wants an iron frame, which this Run has no Press to make, and it is also out
	# of Depth — so open the gate first and the remaining complaint is the goods.
	_mine(sim, "miner_mk2", DEEP_NODE)
	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.NOTHING_TO_DELIVER)


func test_a_hand_over_by_a_player_this_run_does_not_have_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_delivery_refusal(4), Simulation.Refusal.NO_SUCH_PLAYER)


func test_a_run_whose_chain_is_finished_says_so() -> void:
	var sim: Simulation = _sim(_layout())
	var one_tier: String = (
		"""id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:3,press_mk1,drum_magazine,resupply_drop
"""
	)
	var content: Definitions = _content(one_tier)
	assert_false(content.has_errors(), content.describe_errors())
	var run: Simulation = Simulation.new(SEED, 1, content, _layout())
	_mine(run, "miner_mk1", SHALLOW_NODE)
	run.step([InputAction.deliver_to_nest(0)])

	assert_eq(run.query_next_delivery(), -1, "there is nothing left to deliver")
	assert_eq(run.query_delivery_refusal(0), Simulation.Refusal.NO_DELIVERY_PENDING)
	assert_eq(sim.query_delivery_count(), 2, "and the two-tier fixture is unaffected")


# ── The tiers are a data table ────────────────────────────────────────────────

func test_adding_a_delivery_tier_is_a_row() -> void:
	# The acceptance criterion, asserted as behaviour rather than as a parsed table: a third
	# tier appears in the chain, unlocks what its row says, and no code knows about it.
	var three_tiers: String = DELIVERIES + "t03_extra,Extra Licence,2,iron_ore:1,,blast_shield,\n"
	var content: Definitions = _content(three_tiers)
	assert_false(content.has_errors(), content.describe_errors())

	var sim: Simulation = Simulation.new(SEED, 1, content, _layout())
	assert_eq(sim.query_delivery_count(), 3)
	assert_eq(sim.query_delivery_id(2), "t03_extra")
	assert_eq(sim.query_delivery_goods_required(2, "iron_ore"), 1)
	assert_eq(sim.query_delivery_min_depth(2), 2)


# ── Unlock state survives a reload, a save and a replay ───────────────────────

func test_a_hot_reload_that_resorts_the_table_does_not_change_what_is_unlocked() -> void:
	# The Simulation holds resolved ids rather than indices for exactly this reason. Inserting
	# a tier ahead of the one already earned renumbers the table; it must not renumber the Run.
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_eq(sim.query_completed_deliveries(), PackedStringArray(["t01_opening"]), "the premise")

	# A tier inserted ahead of the one already earned, so every index in the table moves.
	var resorted: String = DELIVERIES + "t00_prelude,Prelude Licence,1,iron_ore:1,,blast_shield,\n"
	var reloaded: Definitions = _content(resorted)
	assert_false(reloaded.has_errors(), reloaded.describe_errors())
	sim.step([InputAction.reload_definitions(0, reloaded)])

	assert_eq(
		sim.query_completed_deliveries(),
		PackedStringArray(["t01_opening"]),
		"what was earned is still what was earned"
	)
	assert_true(
		sim.query_machine_is_unlocked(_index(sim, "press_mk1")),
		"and the Machine it bought is still buildable"
	)
	assert_eq(sim.query_delivery_id(0), "t00_prelude", "even though index 0 is now a new tier")
	assert_eq(sim.query_next_delivery(), 0, "which the chain now wants first")


func test_unlock_state_round_trips_through_save_and_load() -> void:
	var sim: Simulation = _sim()
	_mine(sim, "miner_mk1", SHALLOW_NODE)
	sim.step([InputAction.deliver_to_nest(0)])
	_mine(sim, "miner_mk2", DEEP_NODE)
	for tick: int in range(30):
		sim.step([])

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim), sim.query_definitions())
	if not assert_false(loaded.has_errors(), loaded.describe_errors()):
		return
	assert_eq(loaded.simulation.hash(), sim.hash(), "the whole Run, to the integer")
	assert_eq(loaded.simulation.query_completed_deliveries(), sim.query_completed_deliveries())
	assert_eq(loaded.simulation.query_unlocked_gear(), sim.query_unlocked_gear())
	assert_eq(loaded.simulation.query_unlocked_stratagems(), sim.query_unlocked_stratagems())


func test_a_part_paid_delivery_round_trips_through_save_and_load() -> void:
	var sim: Simulation = _sim(_belt_layout())
	_belt_fed_miner(sim)
	for tick: int in range(600):
		sim.step([])
		if sim.query_delivery_goods_delivered("iron_ore") > 0:
			break

	assert_true(sim.query_delivery_goods_delivered("iron_ore") > 0, "the counter is part paid")
	assert_false(sim.query_delivery_is_complete(0), "and not yet settled")

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim), sim.query_definitions())
	if not assert_false(loaded.has_errors(), loaded.describe_errors()):
		return
	assert_eq(loaded.simulation.hash(), sim.hash())
	assert_eq(
		loaded.simulation.query_delivery_goods_delivered("iron_ore"),
		sim.query_delivery_goods_delivered("iron_ore"),
		"including what the Nest was holding"
	)


## The replay harness builds its own Simulation on the starter Map — a recording carries a
## seed, a script and a definition set, and not a Map — so the fixtures below reach the Nest
## by lengthening `nest.delivery_reach_metres` rather than by walking there. A hand-over's
## reach is tuning, and what these fixtures are for is the Delivery and the unlock.
##
## The starter Map's iron Node at tile (4, 4) sits at Depth 1, which is the tier this chain
## opens with.
const STARTER_NODE: Vector3i = Vector3i(4, GROUND, 4)
const SOMEWHERE_CLEAR: Vector3i = Vector3i(20, GROUND, 20)


func _reachable_content() -> Definitions:
	var content: Definitions = _content(
		DELIVERIES, MACHINES, TUNING.replace("delivery_reach_metres = 5", "delivery_reach_metres = 20")
	)
	assert_false(content.has_errors(), content.describe_errors())
	return content


func _delivery_script(content: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, content.machine_index("miner_mk1"), STARTER_NODE)
	])
	script.add_tick([InputAction.deliver_to_nest(0)])
	script.add_tick([
		InputAction.build_machine(0, content.machine_index("press_mk1"), SOMEWHERE_CLEAR)
	])
	script.add_idle_ticks(120)
	return script


func test_a_delivery_fixture_really_does_complete_and_unlock() -> void:
	# A fixture that delivered nothing would replay perfectly and prove nothing. This is the
	# assertion that keeps the replay below honest.
	var content: Definitions = _reachable_content()
	var script: InputScript = _delivery_script(content)
	var sim: Simulation = Simulation.new(SEED, 1, content)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))

	assert_true(sim.query_delivery_is_complete(0), "the tier was paid")
	assert_eq(sim.query_unlocked_gear(), PackedStringArray(["drum_magazine"]), "and unlocked")
	assert_eq(sim.query_machine_count(), 2, "and the Machine it bought went down")


func test_determinism_a_delivery_completing_and_unlocking_replays_identically() -> void:
	var content: Definitions = _reachable_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_delivery_script(content), SEED, 1, content
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func _refused_build_script(content: Definitions) -> InputScript:
	var press: int = content.machine_index("press_mk1")
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.select_machine(0, press)])
	for which: int in range(3):
		script.add_tick([
			InputAction.build_machine(0, press, Vector3i(20 + which * 3, GROUND, 20))
		])
	script.add_idle_ticks(60)
	return script


func test_a_refused_build_fixture_really_was_refused_for_being_locked() -> void:
	var content: Definitions = _reachable_content()
	var script: InputScript = _refused_build_script(content)
	var sim: Simulation = Simulation.new(SEED, 1, content)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))

	assert_eq(sim.query_machine_count(), 0, "three clicks placed nothing")
	assert_eq(sim.query_player_selected_machine(0), "press_mk1", "the locked Machine was on the gun")
	assert_eq(
		sim.query_build_refusal(0, content.machine_index("press_mk1"), SOMEWHERE_CLEAR, 0),
		Simulation.Refusal.CONTENT_IS_LOCKED,
		"and being locked is why"
	)


func test_determinism_a_refused_build_of_locked_content_replays_identically() -> void:
	# A refusal has to replay like any other tick, which is the whole reason it is a silent
	# no-op rather than an error.
	var content: Definitions = _reachable_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_refused_build_script(content), SEED, 1, content
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


# ── The content that ships ────────────────────────────────────────────────────

func test_the_shipped_chain_locks_a_machine_and_opens_with_the_rest() -> void:
	# The keystone loop is deliberately not behind the chain: a Run opens able to build the
	# Miner, Smelter, coal Miner, Boiler, Ammo Press and MG Turret, and the one shipped
	# Machine it has to earn is Miner Mk2.
	var sim: Simulation = Simulation.new(SEED, 1)
	assert_true(sim.query_definitions_loaded(), "the shipped content")
	var definitions: Definitions = sim.query_definitions()
	for machine_id: String in [
		"ammo_press_mk1",
		"coal_miner_mk1",
		"mg_turret_mk1",
		"miner_mk1",
		"smelter_mk1",
		"steam_boiler_mk1",
	]:
		assert_true(
			sim.query_machine_is_unlocked(definitions.machine_index(machine_id)),
			"%s is what a Run opens with" % machine_id
		)
	assert_false(
		sim.query_machine_is_unlocked(definitions.machine_index("miner_mk2")),
		"and Miner Mk2 is what it has to earn"
	)


func test_a_run_opens_holding_exactly_the_plates_for_the_opening_line() -> void:
	# The scaffold this ticket replaces granted 200 of every Item in the game. A Run now opens
	# with one explicit bill: 80 iron plate, against the 78 the whole competent Factory costs.
	var sim: Simulation = Simulation.new(SEED, 1)
	assert_eq(sim.query_player_items(0), PackedStringArray(["iron_plate"]), "plate and nothing else")
	assert_eq(sim.query_player_item(0, "iron_plate"), 80)

	var definitions: Definitions = sim.query_definitions()
	var line: int = 0
	for machine_id: String in [
		"miner_mk1",
		"smelter_mk1",
		"coal_miner_mk1",
		"steam_boiler_mk1",
		"ammo_press_mk1",
		"mg_turret_mk1",
	]:
		var machine: MachineDefinition = definitions.machine(machine_id)
		for slot: int in range(machine.build_cost_items.size()):
			line += machine.build_cost_counts[slot]
	assert_eq(line, 78, "the opening line costs 78 plate, so 80 is it and two over")
