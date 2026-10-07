## The Nest's store — through the Simulation façade, which is the only seam (CLAUDE.md).
##
## #14 gave the Nest a counter that takes goods and keeps nothing, so materials only ever
## left a player's pockets: into a Machine when they built, back only from a demolish or the
## call-early bounty. Nothing the Factory made could get back into a player's hands, so a Run
## could not fund a second Ammo Press out of its own output — which is the thing #10 measured
## as what you need to survive. This file is the symmetric half, and the three things it is
## built to protect:
##
## 1. **A Belt delivering past the open bill banks the surplus**, rather than being refused.
## 2. **A player at the Nest can take it back out**, and is told why beforehand when they
##    cannot — a projection, like `query_build_refusal` and `query_delivery_refusal`.
## 3. **Nothing is destroyed.** The store is capped, so a Belt pointed at a full one backs up
##    where a player can see it, which is the existing rule rather than a new one.
extends TestCase

const SEED: int = 27
const GROUND: int = WorldGrid.GROUND_LAYER

## The Nest a couple of tiles off the origin, so a player standing where a Run starts them is
## within `nest.delivery_reach_metres` of its footprint without standing inside it. The Nest
## covers tiles 1..4 along both axes, so one iron Node at tile 8 is clear of it with room for
## a Belt between the two.
const NODE: Vector3i = Vector3i(8, GROUND, 1)

## Where the Press goes: clear of the Nest, the Node and the Belt.
const SOMEWHERE_CLEAR: Vector3i = Vector3i(14, GROUND, 14)


func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(1, GROUND, 1)
	layout.add_node(NODE, "iron_ore", 1)
	layout.sort_nodes()
	return layout


## The same Map with the Nest pushed well out of reach of where a Run starts a player, so a
## withdrawal made from the spawn point is one made from too far away.
func _distant_nest_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.nest_tile = Vector3i(30, GROUND, 30)
	return layout


## The Press costs **ore** rather than plate, which is what lets this fixture show a Machine
## funded out of the Nest's store: the Item the Factory banks is the Item the Press is paid
## in. Nothing here is locked — what a Delivery unlocks is `test_delivery.gd`'s subject.
const MACHINES: String = """id,display_name,role,footprint_x,footprint_z,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,0,0,400,1,0,0,0,mine_iron_ore,iron_plate:2
press_mk1,Press Mk1,crafter,2,2,0,0,500,0,0,0,0,press_iron_frame,iron_ore:4
"""

const RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.1
press_iron_frame,Press Iron Frame,iron_plate:2,iron_frame:1,1
"""

## One tier, and it wants an iron frame this Run has no way to make. So the bill's ore column
## fills, the tier stays **open**, and every ore after the third arrives at a counter that is
## still the current one — which is exactly "past the current Delivery's bill" and not "after
## the chain finished".
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:3;iron_frame:2,,drum_magazine,
"""

## The Gear a Run is holding, inline so the fixture is a complete definition set. One weapon
## frame and the component the tier above names, because a tier naming Gear that does not
## exist is content somebody broke. This file is about the counter rather than about combat.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
drum_magazine,Drum Magazine,magazine,,0,0,0,0,,0,0,0,0,-30,0,0
"""

const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,150,40
"""

## Exactly two plate: one Miner and nothing over. A Run that wants anything else has to get
## it out of the Nest, which is what this file is about. The store holds five of an Item, so
## both an overflow past the bill and a store filled to its cap are a few seconds away.
const TUNING: String = """[player]
walk_speed_metres_per_second = 4
sprint_speed_multiplier = 1.8
walk_acceleration_metres_per_second_squared = 24
walk_deceleration_metres_per_second_squared = 9
air_acceleration_metres_per_second_squared = 6
air_deceleration_metres_per_second_squared = 1.5
jump_height_metres = 1.1
gravity_metres_per_second_squared = 22
jump_repeats_while_held = false
land_settle_seconds = 0.18
land_settle_acceleration_percent = 45
sprint_ramp_seconds = 0.45
sprint_is_toggle = true
bob_vertical_metres = 0.012
bob_lateral_metres = 0.008
bob_stride_metres = 1.6
bob_sprint_multiplier = 1.6
land_dip_metres = 0.035
land_dip_seconds = 0.22
land_dip_reference_speed_metres_per_second = 7
lean_roll_degrees_per_metre_per_second = 0.12
lean_pitch_degrees_per_metre_per_second = 0.06
field_of_view_degrees = 75
sprint_field_of_view_add_degrees = 6
holster_seconds = 0.2
look_sensitivity_turns_per_1000_pixels = 0.4
eye_height_metres = 1.7
health = 150
downed_bleed_out_seconds = 20
respawn_delay_seconds = 8
revive_seconds = 4
revive_reach_metres = 3
starting_weapon = "pneumatic_wrench"
starting_stock = "iron_plate:2"
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
store_capacity_per_item = 5
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
[gear]
enemy_hit_radius_metres = 0.6
enemy_hit_height_metres = 1.6
view_kick_degrees_per_shot = 0.35
view_kick_recover_seconds = 0.5
[enemy]
crawler_health = 30
player_bite_reach_metres = 1.6
crawler_speed_metres_per_second = 3
crawler_damage = 10
crawler_attack_interval_seconds = 1
breaker_health = 240
breaker_speed_metres_per_second = 2
breaker_damage = 60
breaker_attack_interval_seconds = 1
"""


func _content(tuning: String = TUNING) -> Definitions:
	return Definitions.parse(
		MACHINES,
		RECIPES,
		tuning,
		WAVES,
		DELIVERIES,
		GEAR,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv"
	)


func _sim(layout: MapLayout = null) -> Simulation:
	var content: Definitions = _content()
	assert_false(content.has_errors(), content.describe_errors())
	return Simulation.new(SEED, 1, content, _layout() if layout == null else layout)


func _index(sim: Simulation, id: String) -> int:
	return sim.query_definitions().machine_index(id)


func _item(sim: Simulation, id: String) -> int:
	return sim.query_definitions().item_index(id)


## A Miner over the Node with a Belt out of it and into the Nest. Two ticks, because a Belt is
## refused on a tile a Machine already stands on and the two arriving together would depend on
## the order within one tick.
func _belt_fed_miner(sim: Simulation) -> void:
	sim.step([InputAction.build_machine(0, _index(sim, "miner_mk1"), NODE)])
	sim.step([InputAction.build_belt(0, Vector3i(7, GROUND, 1), Vector3i(5, GROUND, 1))])


## Steps until `predicate` holds, or until `limit` ticks have passed. Returns whether it held,
## so a caller asserts on the outcome rather than on how long it took.
func _step_until(sim: Simulation, limit: int, predicate: Callable) -> bool:
	for tick: int in range(limit):
		if predicate.call():
			return true
		sim.step([])
	return predicate.call()


# ── A Belt past the open bill banks the surplus ────────────────────────────────

func test_a_belt_delivering_past_the_open_bill_banks_the_surplus() -> void:
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)

	assert_true(
		_step_until(sim, 600, func() -> bool: return sim.query_nest_store("iron_ore") > 0),
		"ore reached the Nest and kept coming"
	)
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 3, "the bill was paid in full first")
	assert_false(
		sim.query_delivery_is_complete(0), "and the tier is still open, waiting on a frame"
	)
	assert_true(sim.query_nest_store("iron_ore") > 0, "so the ore past the bill was banked")


func test_a_belt_into_a_full_store_backs_up_rather_than_destroying_what_it_carries() -> void:
	# Nothing in this game destroys Items, and an unbounded store would have been the one
	# place that rule quietly stopped applying. A full store refuses the hand-off, so the
	# queue packs up behind it where a player can see it — the same way a full input buffer
	# reads, and the same way the Nest already read before it kept anything at all.
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	var capacity: int = sim.query_nest_store_capacity_per_item()
	assert_eq(capacity, 5, "the fixture's cap, so a full store is a few seconds away")

	assert_true(
		_step_until(
			sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") == capacity
		),
		"the store filled to its cap"
	)
	for tick: int in range(600):
		sim.step([])

	assert_eq(sim.query_nest_store("iron_ore"), capacity, "and took not one ore more")
	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 3, "the bill is still paid")
	assert_true(sim.query_belt_is_full(0), "the Belt behind it has packed solid")
	assert_true(sim.query_belt_is_stalled(0), "stalled rather than quietly swallowing ore")


func test_the_store_lists_only_what_it_actually_holds() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_nest_store_items(), PackedStringArray(), "a Run opens with an empty store")
	assert_eq(sim.query_nest_store("iron_ore"), 0)

	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 600, func() -> bool: return sim.query_nest_store("iron_ore") > 0),
		"ore was banked"
	)
	assert_eq(sim.query_nest_store_items(), PackedStringArray(["iron_ore"]), "and ore alone")


# ── A player at the Nest takes it back out ────────────────────────────────────

func test_a_player_within_reach_of_the_nest_withdraws_from_the_store() -> void:
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") == 5),
		"the store is full, and the player is carrying no ore at all"
	)
	assert_eq(sim.query_player_item(0, "iron_ore"), 0, "the premise: empty pockets")

	var ore: int = _item(sim, "iron_ore")
	assert_eq(sim.query_withdraw_refusal(0, ore), Simulation.Refusal.NONE, "nothing in the way")
	sim.step([InputAction.withdraw_from_nest(0, ore, 4)])

	assert_eq(sim.query_player_item(0, "iron_ore"), 4, "four ore crossed the counter outwards")
	assert_eq(sim.query_nest_store("iron_ore"), 1, "and the fifth stayed banked")


func test_a_withdrawal_is_clamped_to_what_the_store_is_holding() -> void:
	# The same rule a hand-over obeys in the other direction: the Nest never takes more than
	# the bill asked for, and it never hands out more than it has. Asking for too much is an
	# ordinary thing to do, not an error.
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") == 5),
		"the store is full"
	)

	sim.step([InputAction.withdraw_from_nest(0, _item(sim, "iron_ore"), 500)])
	assert_eq(sim.query_player_item(0, "iron_ore"), 5, "exactly what was there")
	assert_eq(sim.query_nest_store("iron_ore"), 0, "and the store is empty")
	assert_eq(
		sim.query_nest_store_items(),
		PackedStringArray(),
		"an emptied Item is dropped rather than left as a zero"
	)


func test_a_run_funds_a_machine_it_cannot_afford_out_of_the_nests_store() -> void:
	# The hole #27 names, in miniature: a Run spends its opening bill down to nothing and the
	# only materials left anywhere are the ones the Factory made. The Press costs four ore and
	# the player has none, so what goes down is bought with Factory output and nothing else.
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	var press: int = _index(sim, "press_mk1")

	assert_eq(sim.query_player_item(0, "iron_plate"), 0, "the opening bill is spent to the plate")
	assert_eq(
		sim.query_build_refusal(0, press, SOMEWHERE_CLEAR, 0),
		Simulation.Refusal.MISSING_MATERIALS,
		"and the Press is out of reach of a player's pockets"
	)

	assert_true(
		_step_until(sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") >= 4),
		"the Factory banked the four ore the Press costs"
	)
	sim.step([InputAction.withdraw_from_nest(0, _item(sim, "iron_ore"), 4)])
	assert_eq(
		sim.query_build_refusal(0, press, SOMEWHERE_CLEAR, 0),
		Simulation.Refusal.NONE,
		"which is now in hand"
	)

	sim.step([InputAction.build_machine(0, press, SOMEWHERE_CLEAR)])
	assert_eq(sim.query_machine_count(), 2, "the Miner, and the Press its own output paid for")


# ── Refusals are a projection, and a refused withdrawal is a no-op ────────────

func test_a_withdrawal_made_out_of_reach_is_refused_by_name_and_moves_nothing() -> void:
	# Banking is physical for the reason spending is: one counter, one reach, and no menu.
	var sim: Simulation = _sim(_distant_nest_layout())
	var ore: int = _item(sim, "iron_ore")
	assert_eq(sim.query_withdraw_refusal(0, ore), Simulation.Refusal.TOO_FAR_FROM_THE_NEST)

	var before: int = sim.hash()
	sim.step([InputAction.withdraw_from_nest(0, ore, 4)])
	assert_eq(sim.query_player_item(0, "iron_ore"), 0, "nothing came out")
	assert_ne(sim.hash(), before, "a tick passed, and that is the only thing that moved")


func test_a_withdrawal_from_an_empty_store_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_withdraw_refusal(0, _item(sim, "iron_ore")),
		Simulation.Refusal.NOTHING_TO_WITHDRAW,
		"standing at the Nest, with nothing on the counter"
	)


func test_a_withdrawal_naming_no_item_is_refused_by_name() -> void:
	# An index out of the sorted Item ids is what a hot-reload that dropped a Recipe leaves a
	# client holding, so it has to degrade to a named no-op rather than to an empty string.
	var sim: Simulation = _sim()
	var beyond: int = sim.query_definitions().item_count()
	assert_eq(sim.query_withdraw_refusal(0, beyond), Simulation.Refusal.NO_SUCH_ITEM)
	assert_eq(sim.query_withdraw_refusal(0, -1), Simulation.Refusal.NO_SUCH_ITEM)

	var before: int = sim.hash()
	sim.step([InputAction.withdraw_from_nest(0, beyond, 4)])
	assert_ne(sim.hash(), before, "a tick passed and nothing else did")


func test_a_withdrawal_by_a_player_this_run_does_not_have_is_refused_by_name() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.query_withdraw_refusal(4, _item(sim, "iron_ore")), Simulation.Refusal.NO_SUCH_PLAYER)


func test_a_nest_that_has_fallen_neither_banks_nor_hands_anything_back() -> void:
	# A Run that ended stays ended, and a ruin is not a counter. The store keeps what it had —
	# nothing is destroyed — but it takes nothing more and gives nothing back.
	var sim: Simulation = _doomed_sim()
	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 600, func() -> bool: return sim.query_nest_store("iron_ore") > 0),
		"the Factory banked something before the Nest fell"
	)

	assert_true(
		_step_until(sim, 4000, func() -> bool: return sim.query_run_is_over()),
		"and then the Nest fell"
	)
	var banked: int = sim.query_nest_store("iron_ore")
	assert_true(banked > 0, "the premise: there is something on the counter to argue about")

	var ore: int = _item(sim, "iron_ore")
	assert_eq(sim.query_withdraw_refusal(0, ore), Simulation.Refusal.RUN_IS_OVER)

	var held: int = sim.query_player_item(0, "iron_ore")
	sim.step([InputAction.withdraw_from_nest(0, ore, 4)])
	for tick: int in range(120):
		sim.step([])

	assert_eq(sim.query_player_item(0, "iron_ore"), held, "nothing came back out")
	assert_eq(sim.query_nest_store("iron_ore"), banked, "nothing more went in")
	assert_true(sim.query_belt_is_stalled(0), "and the Belt stalled rather than voiding its ore")


## A Map with a Breach six tiles off the Nest, and a Nest with almost no hit points, so a
## Run ends within a few seconds rather than within a few minutes.
func _doomed_layout() -> MapLayout:
	var layout: MapLayout = _layout()
	layout.add_breach(Vector3i(10, GROUND, 10))
	layout.sort_breaches()
	return layout


func _doomed_sim() -> Simulation:
	var content: Definitions = _content(
		TUNING.replace("health = 6000", "health = 10").replace(
			"wave_interval_baseline_seconds = 150", "wave_interval_baseline_seconds = 2"
		).replace(
			"wave_interval_minimum_seconds = 40", "wave_interval_minimum_seconds = 1"
		).replace("telegraph_seconds = 12", "telegraph_seconds = 1")
	)
	assert_false(content.has_errors(), content.describe_errors())
	return Simulation.new(SEED, 1, content, _doomed_layout())


# ── The store survives a save and a replay ────────────────────────────────────

func test_the_nest_store_round_trips_through_save_and_load() -> void:
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") >= 2),
		"the store is holding something worth losing"
	)

	var loaded: RunSave.Load = RunSave.deserialise(RunSave.serialise(sim), sim.query_definitions())
	if not assert_false(loaded.has_errors(), loaded.describe_errors()):
		return
	assert_eq(loaded.simulation.hash(), sim.hash(), "the whole Run, to the integer")
	assert_eq(
		loaded.simulation.query_nest_store("iron_ore"),
		sim.query_nest_store("iron_ore"),
		"including what the Nest had banked"
	)
	assert_eq(loaded.simulation.query_nest_store_items(), sim.query_nest_store_items())


func test_the_store_is_hashed() -> void:
	# State outside the hash is state whose divergence the harness cannot see. Two Runs that
	# are identical but for what the Nest is holding have to be two different integers.
	var sim: Simulation = _sim()
	_belt_fed_miner(sim)
	assert_true(
		_step_until(sim, 1200, func() -> bool: return sim.query_nest_store("iron_ore") > 0),
		"the store is holding something"
	)
	var banked: int = sim.hash()

	sim.step([InputAction.withdraw_from_nest(0, _item(sim, "iron_ore"), 1)])
	var drawn: int = sim.hash()
	assert_ne(banked, drawn, "a withdrawal moved the hash")

	# And the ore is in the player's pockets rather than nowhere: putting the Run back where
	# it was is not something a withdrawal can be undone into, so the standing proof that the
	# store is in the hash is the save round trip above and this inequality.
	assert_eq(sim.query_player_item(0, "iron_ore"), 1)


## The replay harness builds its own Simulation on the starter Map — a recording carries a
## seed, a script and a definition set, and not a Map — so this fixture mines the starter
## Map's own iron Node at (4, 4) and runs two Belts back to the Nest at (-6, -6): west along
## z = 4, then north along x = -3 into the Nest's footprint. The reach is lengthened so the
## withdrawal can be made from where a Run starts a player, exactly as `test_delivery.gd`
## does, because where a player is standing is not what this fixture is about.
const STARTER_NODE: Vector3i = Vector3i(4, GROUND, 4)


func _reachable_content() -> Definitions:
	var content: Definitions = _content(
		TUNING.replace("delivery_reach_metres = 5", "delivery_reach_metres = 20")
	)
	assert_false(content.has_errors(), content.describe_errors())
	return content


## Deposit, overflow past a bill, and a withdrawal that funds a Machine — the three things
## #27 asked for, in one script.
func _store_script(content: Definitions) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, content.machine_index("miner_mk1"), STARTER_NODE)
	])
	script.add_tick([InputAction.build_belt(0, Vector3i(3, GROUND, 4), Vector3i(-2, GROUND, 4))])
	script.add_tick([InputAction.build_belt(0, Vector3i(-3, GROUND, 4), Vector3i(-3, GROUND, -2))])
	script.add_idle_ticks(1500)
	script.add_tick([
		InputAction.withdraw_from_nest(0, content.item_index("iron_ore"), 4)
	])
	script.add_tick([
		InputAction.build_machine(0, content.machine_index("press_mk1"), SOMEWHERE_CLEAR)
	])
	script.add_idle_ticks(60)
	return script


func test_a_nest_store_fixture_really_does_bank_past_the_bill_and_fund_a_machine() -> void:
	# A fixture that banked nothing would replay perfectly and prove nothing. This is the
	# assertion that keeps the replay below honest.
	var content: Definitions = _reachable_content()
	var script: InputScript = _store_script(content)
	var sim: Simulation = Simulation.new(SEED, 1, content)
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))

	assert_eq(sim.query_delivery_goods_delivered("iron_ore"), 3, "the open bill was paid first")
	assert_false(sim.query_delivery_is_complete(0), "the tier is still open, waiting on a frame")
	assert_eq(sim.query_player_item(0, "iron_plate"), 0, "the opening bill went on the Miner")
	assert_eq(sim.query_machine_count(), 2, "and the Press was funded out of the Nest's store")


func test_determinism_banking_past_a_bill_and_withdrawing_replays_identically() -> void:
	var content: Definitions = _reachable_content()
	var recording: ReplayRecording = DeterminismHarness.record(
		_store_script(content), SEED, 1, content
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


# ── The acceptance test: a Run funds its second Ammo Press ────────────────────
#
# Everything above runs on a fixture built to make one rule easy to see. This one runs on
# **the shipped economy** — `content/machines.csv`, `content/recipes.csv`,
# `content/deliveries.csv` and `content/tuning.toml`, unaltered — because the hole #27 names
# is a balance fact and not a mechanism: 80 plate, a competent opening line that costs 78,
# and a second Ammo Press at 14 that #10 measured as the thing you need to survive past
# Wave 16. Before the store there was no way to pay for it. This is the proof that there is.
#
# Only the Map is this file's own, and deliberately: the starter Map's Nodes are far enough
# apart that joining them up is a lesson in Belt routing rather than a statement about
# materials, and the geography is not what the acceptance criterion is about. There is no
# Breach on it, so no Wave interrupts the accounting — what is being measured is whether the
# Factory can pay, not whether it can also fight.

## The whole competent opening line, in build order, and what `content/machines.csv` charges
## for it. 78 against the 80 `player.starting_stock` grants.
const OPENING_LINE: Array = [
	["miner_mk1", Vector3i(12, GROUND, 1)],
	["smelter_mk1", Vector3i(7, GROUND, 1)],
	["coal_miner_mk1", Vector3i(8, GROUND, 10)],
	["steam_boiler_mk1", Vector3i(0, GROUND, 10)],
	["ammo_press_mk1", Vector3i(14, GROUND, 10)],
	["mg_turret_mk1", Vector3i(18, GROUND, 10)],
]

## Where the second Ammo Press goes, clear of everything above.
const SECOND_PRESS: Vector3i = Vector3i(22, GROUND, 10)


## A Map the shipped Machines fit on in one line: an iron seam and a coal seam both within a
## Belt's run of a Nest a player starts beside. No Breach, so there are no Waves.
func _shipped_layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(1, GROUND, 1)
	layout.add_node(Vector3i(12, GROUND, 1), "iron_ore", 1)
	layout.add_node(Vector3i(8, GROUND, 10), "coal", 1)
	layout.sort_nodes()
	return layout


## Stands the opening line up and wires it: ore from the Miner into the Smelter, plate from
## the Smelter into the Nest, coal from the coal Miner into the Boiler. One intent a tick,
## because a Belt is refused on a tile a Machine already stands on.
func _build_the_opening_line(sim: Simulation) -> void:
	for entry: Array in OPENING_LINE:
		sim.step([InputAction.build_machine(0, _index(sim, entry[0]), entry[1])])
	sim.step([InputAction.build_belt(0, Vector3i(11, GROUND, 1), Vector3i(10, GROUND, 1))])
	sim.step([InputAction.build_belt(0, Vector3i(6, GROUND, 1), Vector3i(5, GROUND, 1))])
	sim.step([InputAction.build_belt(0, Vector3i(7, GROUND, 10), Vector3i(3, GROUND, 10))])


func test_a_run_funds_a_second_ammo_press_out_of_factory_output_alone() -> void:
	var shipped: Definitions = Simulation.new(SEED, 1).query_definitions()
	assert_false(shipped.has_errors(), shipped.describe_errors())
	var sim: Simulation = Simulation.new(SEED, 1, shipped, _shipped_layout())

	assert_eq(sim.query_player_item(0, "iron_plate"), 80, "a Run opens with the shipped bill")
	_build_the_opening_line(sim)
	assert_eq(sim.query_machine_count(), 6, "the whole competent opening line is standing")
	assert_eq(sim.query_player_item(0, "iron_plate"), 2, "and it cost all but two plate")

	var press: int = _index(sim, "ammo_press_mk1")
	assert_eq(
		sim.query_build_refusal(0, press, SECOND_PRESS, 0),
		Simulation.Refusal.MISSING_MATERIALS,
		"so a second Ammo Press is out of reach of the player's pockets, which is the premise"
	)

	# The Smelter's plate rides a Belt into the Nest. The open tier wants coal, so plate is
	# not on its bill and every plate that arrives is banked.
	var cost: int = 14
	assert_eq(
		shipped.machine("ammo_press_mk1").build_cost_counts[0], cost, "what the row charges"
	)
	assert_true(
		_step_until(
			sim, 20000, func() -> bool: return sim.query_nest_store("iron_plate") >= cost
		),
		"the Factory banked the plate for a second Ammo Press out of its own output"
	)
	assert_eq(sim.query_player_item(0, "iron_plate"), 2, "without a single plate from pockets")

	sim.step([InputAction.withdraw_from_nest(0, _item(sim, "iron_plate"), cost)])
	assert_eq(sim.query_player_item(0, "iron_plate"), 2 + cost, "withdrawn at the Nest")
	assert_eq(
		sim.query_build_refusal(0, press, SECOND_PRESS, 0),
		Simulation.Refusal.NONE,
		"and a second Ammo Press is affordable"
	)

	sim.step([InputAction.build_machine(0, press, SECOND_PRESS)])
	assert_eq(sim.query_machine_count(), 7, "the second Ammo Press is standing")
	assert_eq(sim.query_machine_id(6), "ammo_press_mk1")
	assert_eq(sim.query_player_item(0, "iron_plate"), 2, "paid for out of the Factory, in full")
