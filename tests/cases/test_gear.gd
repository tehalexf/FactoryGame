## Gear: modular weapons, first-person combat, and what losing a fight costs.
##
## The claim this file stands behind is the other half of DESIGN.md's keystone loop. #10
## proved that production is combat power through a Turret; this proves it through the
## player's own hands — **you fight with what your Factory made**, and a build goal is a
## Factory goal because the thing that makes your rifle better is a component off a
## different production line.
##
## Three things are asserted that no amount of code reading would settle:
##
## * **A component measurably changes the weapon it is fitted to**, and two components add
##   rather than multiply, so the table is a design space rather than a tier list.
## * **A fourth weapon is a row.** `test_a_fourth_weapon_is_a_row_and_nothing_in_sim_knows_it`
##   adds one to the shipped files and shoots something with it, with no code change at all
##   — the same proof `test_turrets` gives for a Cannon Turret.
## * **Death costs tempo and nothing else.** Not a plate, not a Delivery, not a component.
##
## Everything goes through the Simulation façade, which is the only seam.
extends TestCase

# ── The fixture ───────────────────────────────────────────────────────────────
#
# One Breach on the diagonal from the player, because of how aiming has to work in a test.
# A player who has sent no `MOVE` stands at (0, 0) and an Enemy walks the centre of a tile
# lane, which is always an odd number of metres — so nothing is ever exactly in front of a
# player who has not turned. The Breach at tile (4, -5) puts its Crawler at (9, -9) metres,
# **exactly forty-five degrees** to the player's right, and 625 pixels of mouse travel is
# exactly an eighth of a turn at the shipped sensitivity of 0.2 turns per 1000 pixels. So
# the aim in these tests is exact arithmetic rather than a number somebody tuned until it
# passed.
#
# The Crawler is also frozen — `crawler_speed_metres_per_second` is cut to a hundredth —
# because what is under test is the weapon and not the walk. Over six hundred ticks it
# drifts under a tenth of a metre, well inside the hit volume.

## The tile the aiming Breach sits on, and the Crawler's position in metres when it arrives.
const DIAGONAL_BREACH: Vector3i = Vector3i(4, 0, -5)

## Pixels of mouse travel that turn the view exactly forty-five degrees to the right.
## `player.look_sensitivity_turns_per_1000_pixels` is 0.2, so 625 pixels is 0.125 turns.
const FORTY_FIVE_DEGREES_RIGHT: int = 625

## A melee Breach, close enough that the wrench reaches without any aiming at all: a swing
## catches anything in front of the player inside the weapon's reach, and tile (1, -1) puts
## its Crawler at (3, -1) metres — 3.16 m away and forward of a player facing -z.
const MELEE_BREACH: Vector3i = Vector3i(1, 0, -1)

## One Crawler a Breach and never any more, so these tests watch exactly one of them.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

## A Breach that lets a stream of Crawlers out, for the tests about being overwhelmed.
const MANY_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
"""

## One Breaker a Breach, for the test about what an Enemy chooses to bite.
const ONE_BREAKER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
shock_breakers,breaker,0,1,0,1
"""

## A Breaker that stands where it came out, for the same reason the fixture's Crawler does:
## what is under test is the weapon and not the walk.
const FROZEN_BREAKER: Array = [
	["breaker_speed_metres_per_second = 2", "breaker_speed_metres_per_second = 0.02"]
]

## A Delivery tier that locks the Drum Magazine and nothing else, so the lock tests have
## something locked and the rest of the file has everything else open. One plate, so the
## opening stock below pays for it.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_munitions,Munitions Licence,1,iron_plate:1,,drum_magazine,
"""

## The same tier, naming a component the **shipped** `content/gear.csv` actually has. The
## replay fixtures below record against the shipped Gear table, and a tier naming Gear that
## does not exist is content somebody broke — so the two have to agree.
const SHIPPED_DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_munitions,Munitions Licence,1,iron_plate:1,,mg_drum_magazine,
"""

## The shipped stock line, and the one this file uses instead.
##
## Ammunition is in it because the shipped bill is deliberately still plate alone — a Run is
## meant to get its rounds out of an Ammo Press and the Nest's store (see
## `content/tuning.toml`). A test about what a weapon *does* should not also have to build a
## Factory first, so the fixture hands the player rounds and the shipped game does not.
const SHIPPED_STOCK: String = 'starting_stock = "iron_plate:80"'
const ARMED_STOCK: String = 'starting_stock = "ammunition:400;iron_plate:80"'

## The Gear this file fights with. Its own table rather than the shipped one, for the reason
## `test_turrets` brings its own Machines: the numbers are chosen so the arithmetic in the
## assertions is readable, and a spread of zero is what lets a test about *aim* not be a
## test about luck. `test_the_shipped_gear_table_loads_and_its_three_weapons_differ` is where
## the real file is asserted.
##
## Three weapons and four components, covering four slots — barrel, magazine, sight and
## plating — so "the set of slots is exactly the set of kinds the table mentions" is
## exercised with more than one.
const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
bolt_rifle,Bolt Rifle,weapon,ranged,30,60,0,1,ammunition,1,0,0,0,0,0,0
drum_autocannon,Drum Autocannon,weapon,ranged,10,30,0,0.1,ammunition,2,0,0,0,0,0,0
pneumatic_wrench,Pneumatic Wrench,weapon,melee,50,4,0,0.5,,0,0,0,0,0,0,0
heavy_barrel,Heavy Barrel,barrel,,0,0,0,0,,0,100,50,0,100,100,0
belt_feed,Belt Feed,magazine,,0,0,0,0,,0,0,0,0,-50,0,0
drum_magazine,Drum Magazine,magazine,,0,0,0,0,,0,0,0,0,-75,0,0
reflex_sight,Reflex Sight,sight,,0,0,0,0,,0,0,10,0,0,0,0
hardened_plating,Hardened Plating,plating,,0,0,0,0,,0,0,0,0,0,0,-50
"""


## A Stratagem table that is not what this file is about. One row, so the table is not empty —
## `Definitions` refuses an empty one, because a Silo with nothing to load is a Machine a
## player can build, feed and never use. `test_silo.gd` is where the shipped table is
## asserted, exactly as `test_delivery.gd` is where the shipped Delivery chain is.
const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## The shipped Machines, Recipes and tuning, with the Telegraph shortened so a called Wave
## arrives in half a second, the player armed, and the Crawler frozen. Every other number is
## the real file's, which is what keeps the arithmetic below readable against
## `content/tuning.toml`.
func _content(
	waves: String = ONE_CRAWLER,
	overrides: Array = [],
	gear: String = GEAR,
	deliveries: String = DELIVERIES
) -> Definitions:
	var tuning: String = _read("res://content/tuning.toml")
	var substitutions: Array = [
		["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
		["crawler_speed_metres_per_second = 3", "crawler_speed_metres_per_second = 0.03"],
		[SHIPPED_STOCK, ARMED_STOCK],
	]
	substitutions.append_array(overrides)
	for pair: Array in substitutions:
		assert_true(tuning.contains(pair[0]), "the tuning override %s must match" % pair[0])
		tuning = tuning.replace(pair[0], pair[1])
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning,
		waves,
		deliveries,
		gear,
		STRATAGEMS,
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


## A Map whose Nest is far to the south-west by default, so the ground around the player is
## open, and whose single Breach is wherever the test wants its Crawler to come from.
func _layout(
	breach: Vector3i = DIAGONAL_BREACH, nest: Vector3i = Vector3i(-30, 0, -30)
) -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(nest.x, WorldGrid.GROUND_LAYER, nest.z)
	layout.add_node(Vector3i(14, WorldGrid.GROUND_LAYER, 6), "iron_ore", 1)
	layout.add_breach(Vector3i(breach.x, WorldGrid.GROUND_LAYER, breach.z))
	layout.sort_breaches()
	layout.sort_nodes()
	return layout


func _sim(
	waves: String = ONE_CRAWLER,
	overrides: Array = [],
	breach: Vector3i = DIAGONAL_BREACH,
	players: int = 1,
	gear: String = GEAR,
	nest: Vector3i = Vector3i(-30, 0, -30)
) -> Simulation:
	var sim: Simulation = Simulation.new(
		11, players, _content(waves, overrides, gear), _layout(breach, nest)
	)
	sim.step([InputAction.call_wave_early(0)])
	return sim


func _step(sim: Simulation, ticks: int) -> void:
	for i: int in range(ticks):
		sim.step([])


## Steps until `predicate` holds, and reports how many ticks that took — or -1 if it never
## did inside `limit`. Bounded, so a broken Simulation fails rather than hangs.
func _step_until(sim: Simulation, limit: int, predicate: Callable) -> int:
	for tick: int in range(limit):
		if predicate.call():
			return tick
		sim.step([])
	return -1 if not predicate.call() else limit


## Puts a weapon in the player's hands by id, and steps the tick that does it.
func _equip(sim: Simulation, gear_id: String) -> void:
	sim.step([
		InputAction.equip_weapon(0, sim.query_definitions().gear_index(gear_id))
	])


## Fits a component into the slot its own row names, and steps the tick that does it.
func _fit(sim: Simulation, gear_id: String) -> void:
	var definitions: Definitions = sim.query_definitions()
	var definition: GearDefinition = definitions.gear(gear_id)
	sim.step([
		InputAction.fit_component(
			0,
			definitions.gear_slot_index(definition.slot_id()),
			definitions.gear_index(gear_id)
		)
	])


## Turns the view to forty-five degrees right and steps the tick that does it. Exact: see
## `FORTY_FIVE_DEGREES_RIGHT`.
func _aim_at_the_diagonal(sim: Simulation) -> void:
	sim.step([InputAction.look(0, Fixed.from_int(FORTY_FIVE_DEGREES_RIGHT), 0)])


## Steps until a Crawler is on the Map, then aims at it.
func _wait_for_a_crawler(sim: Simulation) -> void:
	var spawned: int = _step_until(sim, 600, func() -> bool: return sim.query_enemy_count() > 0)
	assert_true(spawned != -1, "a Crawler came out of the Breach")


# ── What a Run opens with ─────────────────────────────────────────────────────

func test_a_run_opens_holding_the_weapon_the_tuning_names_and_nothing_fitted() -> void:
	var sim: Simulation = _sim()
	assert_eq(
		sim.query_player_weapon(0),
		"pneumatic_wrench",
		"`player.starting_weapon`, resolved to an id rather than an index"
	)
	assert_true(sim.query_player_weapon_is_melee(0), "the wrench swings rather than shoots")
	for slot: int in range(sim.query_definitions().gear_slot_count()):
		assert_eq(
			sim.query_player_component(0, slot),
			"",
			"every slot opens empty — every component is behind a Delivery"
		)


func test_the_slots_are_exactly_the_kinds_the_gear_table_names() -> void:
	# There is no slot table and there will not be one, for the reason there is no Item
	# table: writing `barrel` in a row is what makes a barrel slot exist. Sorted, so the
	# index a `FIT_COMPONENT` intent carries is a property of the content rather than of the
	# order somebody typed the rows in.
	var definitions: Definitions = _content()
	assert_false(definitions.has_errors(), definitions.describe_errors())
	assert_eq(
		definitions.gear_slot_ids(),
		PackedStringArray(["barrel", "magazine", "plating", "sight"]),
		"four kinds other than `weapon`, in sorted order"
	)
	assert_eq(definitions.weapon_count(), 3, "and three frames")


func test_the_shipped_gear_table_loads_and_its_three_weapons_differ() -> void:
	# The real file, asserted the way `test_delivery` asserts the real Delivery chain. What
	# DESIGN.md promises is three weapons that differ in accuracy, damage and Ammunition
	# cost, and this is that sentence as arithmetic.
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())

	var wrench: GearDefinition = definitions.gear("pneumatic_wrench")
	var rifle: GearDefinition = definitions.gear("bolt_rifle")
	var autocannon: GearDefinition = definitions.gear("drum_autocannon")
	assert_not_null(wrench)
	assert_not_null(rifle)
	assert_not_null(autocannon)

	assert_true(wrench.is_melee(), "the Pneumatic Wrench is the melee weapon")
	assert_eq(wrench.ammunition_item, "", "and it spends a player's presence, not an Item")

	assert_true(
		rifle.spread_degrees < autocannon.spread_degrees,
		"the Bolt Rifle is the precise one"
	)
	assert_true(
		rifle.damage > autocannon.damage, "and it hits harder a shot"
	)
	assert_true(
		rifle.ammunition_per_shot < autocannon.ammunition_per_shot,
		"and it is cheap on Ammunition where the Drum Autocannon devours it"
	)
	assert_true(
		autocannon.seconds_per_shot < rifle.seconds_per_shot,
		"which it does by firing far faster — that is what clears a crowd"
	)


# ── Firing ────────────────────────────────────────────────────────────────────

func test_a_rifle_shot_kills_a_crawler_and_spends_a_round() -> void:
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")
	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)

	assert_eq(sim.query_enemy_count(), 1)
	# 400 from the fixture's bill plus the 25 `wave.call_early_bounty_per_item` paid for
	# pulling the lever, which pays in exactly the Items `player.starting_stock` names.
	var loaded: int = sim.query_player_ammunition(0)
	assert_eq(loaded, 425, "the fixture's opening rounds and the lever's bounty")
	assert_eq(sim.query_fire_refusal(0), Simulation.Refusal.NONE, "loaded, aimed and ready")

	sim.step([InputAction.fire(0)])

	assert_eq(sim.query_enemy_count(), 0, "30 damage against a Crawler's 30 health")
	assert_eq(sim.query_player_ammunition(0), loaded - 1, "and one round out of the pockets")
	assert_eq(sim.query_player_last_shot_tick(0), sim.query_tick() - 1, "it fired this tick")


func test_a_shot_that_is_not_aimed_at_anything_hits_nothing_and_still_costs_a_round() -> void:
	# The other half of the same claim: aiming is a thing a player does, and a round spent
	# missing is spent. If this passed without the aim, the test above would be asserting
	# that firing in any direction kills whatever is on the Map.
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")
	_wait_for_a_crawler(sim)
	var loaded: int = sim.query_player_ammunition(0)

	sim.step([InputAction.fire(0)])

	assert_eq(sim.query_enemy_count(), 1, "the Crawler is forty-five degrees away, untouched")
	assert_eq(sim.query_player_ammunition(0), loaded - 1, "and the round is gone anyway")


func test_a_weapon_fires_at_the_rate_its_row_declares_and_no_faster() -> void:
	# `seconds_per_shot` is 1 on the fixture's rifle: sixty ticks. A trigger held for three
	# hundred ticks therefore spends five rounds, not three hundred.
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")
	assert_eq(sim.query_player_weapon_interval_ticks(0), 60, "one second, in whole ticks")

	var before: int = sim.query_player_ammunition(0)
	for tick: int in range(300):
		sim.step([InputAction.fire(0)])
	assert_eq(before - sim.query_player_ammunition(0), 5, "five shots in three hundred ticks")


func test_the_drum_autocannon_devours_ammunition_where_the_bolt_rifle_sips() -> void:
	# DESIGN.md's distinction, as arithmetic. The fixture's autocannon fires every 5 ticks —
	# 0.1 s is 0.09999 in 16.16 fixed point and a rate floors to whole ticks — at two rounds
	# a shot; the rifle every 60 at one. Over three hundred ticks that is sixty shots and a
	# hundred and twenty rounds against five shots and five rounds: twenty-four times the
	# Ammunition for twelve times the shots.
	var rifle: Simulation = _sim()
	_equip(rifle, "bolt_rifle")
	var autocannon: Simulation = _sim()
	_equip(autocannon, "drum_autocannon")

	assert_eq(autocannon.query_player_weapon_interval_ticks(0), 5)
	assert_eq(autocannon.query_player_weapon_ammunition_per_shot(0), 2)

	var rifle_before: int = rifle.query_player_ammunition(0)
	var autocannon_before: int = autocannon.query_player_ammunition(0)
	for tick: int in range(300):
		rifle.step([InputAction.fire(0)])
		autocannon.step([InputAction.fire(0)])

	assert_eq(rifle_before - rifle.query_player_ammunition(0), 5)
	assert_eq(autocannon_before - autocannon.query_player_ammunition(0), 120)


func test_firing_with_no_ammunition_does_nothing_at_all_and_says_why() -> void:
	# The first-person half of "a Turret with no Ammunition does not fire". Defence costs
	# continuous production in a player's hands exactly as it does in a Turret's.
	var sim: Simulation = _sim(ONE_CRAWLER, [[ARMED_STOCK, 'starting_stock = "iron_plate:80"']])
	_equip(sim, "drum_autocannon")
	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)

	assert_eq(sim.query_player_ammunition(0), 0, "the Factory has made nothing yet")
	assert_eq(
		sim.query_fire_refusal(0),
		Simulation.Refusal.OUT_OF_AMMUNITION,
		"and the HUD can read DRY off the weapon rather than off a count"
	)

	var before: int = sim.hash()
	sim.step([InputAction.fire(0)])
	# One tick of Wave clock moves the hash, so the comparison is on what firing did:
	# nothing. The Crawler is alive, nothing was spent, and no shot was recorded.
	assert_eq(sim.query_enemy_count(), 1, "the Crawler is untouched")
	assert_eq(sim.query_player_last_shot_tick(0), -1, "and nothing ever fired")
	assert_ne(before, 0, "the hash before the refused shot was real")


func test_the_pneumatic_wrench_does_melee_damage_and_still_repairs() -> void:
	# GLOSSARY.md's Pneumatic Wrench is the melee weapon *and* the repair tool, and #11
	# landed the repair half. This is both halves in one Run: the same frame in the same
	# hands, swinging at a Crawler and then mending what the Crawler's friends chewed.
	var sim: Simulation = _sim(ONE_CRAWLER, [], MELEE_BREACH)
	assert_eq(sim.query_player_weapon(0), "pneumatic_wrench")
	_wait_for_a_crawler(sim)

	# The swing: 3.16 m away and in front, inside the wrench's 4 m reach, and no aiming at
	# all — a swing is a sweep rather than a ray.
	assert_eq(sim.query_player_weapon_damage(0), 50, "the fixture's wrench")
	assert_eq(sim.query_enemy_count(), 1)
	sim.step([InputAction.fire(0)])
	assert_eq(
		sim.query_enemy_count(),
		0,
		"50 against a Crawler's 30, and an Enemy at nothing is off the Map on the tick it died"
	)

	# And the repair half, unchanged by any of this.
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([
		InputAction.build_machine(
			0, sim.query_definitions().machine_index("smelter_mk1"), Vector3i(0, ground, 0)
		)
	])
	assert_eq(sim.query_machine_count(), 1, "a Smelter where the player is standing")
	assert_eq(
		sim.query_repair_refusal(0, Vector3i(0, ground, 0)),
		Simulation.Refusal.NOT_DAMAGED,
		"already whole — the wrench is still the repair tool, in reach and refusing for the right reason"
	)


# ── Components ────────────────────────────────────────────────────────────────

func test_a_component_measurably_changes_the_weapon_it_is_fitted_to() -> void:
	# The acceptance criterion, read off five queries. The fixture's Heavy Barrel is +100%
	# damage, +50% range, +100% interval and +100% Ammunition — a slower, harder, longer,
	# hungrier rifle, which is a *trade* rather than an upgrade.
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")

	assert_eq(sim.query_player_weapon_damage(0), 30, "the bare frame")
	assert_eq(sim.query_player_weapon_range_metres(0), Fixed.from_int(60))
	assert_eq(sim.query_player_weapon_interval_ticks(0), 60)
	assert_eq(sim.query_player_weapon_ammunition_per_shot(0), 1)

	_fit(sim, "heavy_barrel")
	assert_eq(
		sim.query_player_component(0, sim.query_definitions().gear_slot_index("barrel")),
		"heavy_barrel",
		"fitted into the slot its own row names"
	)

	assert_eq(sim.query_player_weapon_damage(0), 60, "+100% of 30")
	assert_eq(sim.query_player_weapon_range_metres(0), Fixed.from_int(90), "+50% of 60 m")
	assert_eq(sim.query_player_weapon_interval_ticks(0), 120, "+100% of one second")
	assert_eq(sim.query_player_weapon_ammunition_per_shot(0), 2, "+100% of one round")


func test_a_fitted_component_measurably_changes_what_a_shot_does() -> void:
	# The same claim at the other end: not a number in a query, but a Breaker that takes
	# fewer shots. A Breaker has 240 health; the bare rifle needs eight shots at 30 and the
	# Heavy Barrel needs four at 60.
	# The Breaker is frozen for the reason the Crawler is: what is under test is the weapon,
	# and a Breaker that walked off the forty-five-degree line mid-burst would make this a
	# test about aiming at a moving target.
	var bare: Simulation = _sim(ONE_BREAKER, FROZEN_BREAKER)
	_equip(bare, "bolt_rifle")
	var fitted: Simulation = _sim(ONE_BREAKER, FROZEN_BREAKER)
	_equip(fitted, "bolt_rifle")
	_fit(fitted, "heavy_barrel")

	assert_eq(_shots_to_kill(bare), 8, "240 health at 30 a shot")
	assert_eq(_shots_to_kill(fitted), 4, "and at 60 a shot, half as many")


## Fires at the diagonal Breach's Enemy until it dies, and reports how many rounds it took.
## -1 if it never did, so a broken Simulation fails rather than hangs.
func _shots_to_kill(sim: Simulation) -> int:
	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)
	var before: int = sim.query_player_ammunition(0)
	var per_shot: int = sim.query_player_weapon_ammunition_per_shot(0)
	for tick: int in range(2400):
		if sim.query_enemy_count() == 0:
			@warning_ignore("integer_division")
			return (before - sim.query_player_ammunition(0)) / per_shot
		sim.step([InputAction.fire(0)])
	return -1


func test_two_components_add_rather_than_multiply() -> void:
	# Why the modifiers are percentages summed once rather than fixed-point multipliers
	# chained: two components can be reasoned about in either order, nothing rounds at each
	# link, and the order they were fitted in cannot reach the state hash. The Heavy Barrel
	# is +100% interval and the Belt Feed -50%, so together they are +50% — 90 ticks — and
	# not the 60 that multiplying 2.0 by 0.5 would give.
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")
	_fit(sim, "heavy_barrel")
	_fit(sim, "belt_feed")
	assert_eq(sim.query_player_weapon_interval_ticks(0), 90, "+100% and -50% is +50%")

	var other: Simulation = _sim()
	_equip(other, "bolt_rifle")
	_fit(other, "belt_feed")
	_fit(other, "heavy_barrel")
	assert_eq(
		other.query_player_weapon_interval_ticks(0),
		90,
		"and fitting them the other way round is the same weapon"
	)
	assert_eq(
		other.query_player_components(0),
		sim.query_player_components(0),
		"held in sorted id order, so two frames carrying the same Gear hash the same"
	)


func test_a_component_only_fits_the_slot_its_own_row_names() -> void:
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()
	var sight_slot: int = definitions.gear_slot_index("sight")
	var barrel: int = definitions.gear_index("heavy_barrel")

	assert_eq(
		sim.query_fit_refusal(0, sight_slot, barrel),
		Simulation.Refusal.WRONG_SLOT,
		"a barrel is not a sight, and the intent is refused rather than quietly redirected"
	)
	sim.step([InputAction.fit_component(0, sight_slot, barrel)])
	assert_eq(sim.query_player_component(0, sight_slot), "", "so nothing was fitted")

	assert_eq(
		sim.query_fit_refusal(0, definitions.gear_slot_index("barrel"), definitions.gear_index("bolt_rifle")),
		Simulation.Refusal.WRONG_SLOT,
		"and a weapon frame is held, never fitted"
	)


func test_a_slot_can_be_emptied_again() -> void:
	var sim: Simulation = _sim()
	_equip(sim, "bolt_rifle")
	_fit(sim, "heavy_barrel")
	assert_eq(sim.query_player_weapon_damage(0), 60)

	var barrel_slot: int = sim.query_definitions().gear_slot_index("barrel")
	sim.step([InputAction.fit_component(0, barrel_slot, -1)])
	assert_eq(sim.query_player_component(0, barrel_slot), "", "a Gear index of -1 empties the slot")
	assert_eq(sim.query_player_weapon_damage(0), 30, "and the frame is what its row says again")


func test_fitting_a_second_component_to_one_slot_replaces_the_first() -> void:
	# A frame has one of each slot. The alternative — refusing — would make a player empty
	# a slot before filling it, which is a step nobody wants in the middle of a Wave.
	var sim: Simulation = _sim()
	var barrel_slot: int = sim.query_definitions().gear_slot_index("barrel")
	_fit(sim, "heavy_barrel")
	assert_eq(sim.query_player_component(0, barrel_slot), "heavy_barrel")

	# A second barrel, added to the fixture's table for exactly this.
	var two_barrels: String = GEAR + "light_barrel,Light Barrel,barrel,,0,0,0,0,,0,0,0,0,-25,0,0\n"
	var other: Simulation = _sim(ONE_CRAWLER, [], DIAGONAL_BREACH, 1, two_barrels)
	_fit(other, "heavy_barrel")
	_fit(other, "light_barrel")
	assert_eq(
		other.query_player_component(0, barrel_slot),
		"light_barrel",
		"the second barrel took the slot"
	)
	assert_eq(
		other.query_player_components(0).size(), 1, "and the first is off the frame entirely"
	)


func test_a_component_no_delivery_has_unlocked_cannot_be_fitted_until_it_is() -> void:
	# **This is what makes a build goal a Factory goal.** The Drum Magazine is behind
	# `t01_munitions`, so the way to get a faster weapon is to run a Belt into the Nest —
	# which is the whole thesis of the pillar, and the same rule a locked Machine obeys.
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()
	var magazine: int = definitions.gear_index("drum_magazine")
	var slot: int = definitions.gear_slot_index("magazine")

	assert_false(sim.query_gear_is_unlocked(magazine), "locked, because a tier names it")
	assert_true(
		sim.query_gear_is_unlocked(definitions.gear_index("heavy_barrel")),
		"and the Heavy Barrel is open, because no tier does"
	)
	assert_eq(sim.query_fit_refusal(0, slot, magazine), Simulation.Refusal.GEAR_IS_LOCKED)
	sim.step([InputAction.fit_component(0, slot, magazine)])
	assert_eq(sim.query_player_component(0, slot), "", "refused as a silent no-op")

	# Deliver the plate the tier wants. The player is miles from the Nest, so walk the goods
	# over by hand is not on; the honest short path is a Belt, and the honest *short* path
	# for a test is to put the player at the Nest — which neither is possible nor needed,
	# because what is being asserted is the gate and not the walk. So: a Run whose tier is
	# already complete, built from a Delivery table that asks for nothing this fixture
	# cannot pay, and the assertion is that completing it opens the slot.
	assert_eq(sim.query_next_delivery(), 0, "the tier is still open")


func test_completing_a_delivery_unlocks_the_component_it_names() -> void:
	var ground: int = WorldGrid.GROUND_LAYER
	# A Map whose Nest is next to the player, so a Delivery is a key press rather than a
	# hike. `nest.delivery_reach_metres` is 5, and the Nest's footprint edge is two tiles
	# from the origin. The Node under the player's feet is there so a Miner can stand on it:
	# the tier is gated at Depth 1, and Depth is what the Factory is *actually* mining
	# rather than a box to tick.
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(2, ground, -2)
	layout.add_node(Vector3i(-4, ground, 0), "iron_ore", 1)
	layout.add_breach(Vector3i(4, ground, -5))
	layout.sort_breaches()
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(11, 1, _content(), layout)

	var definitions: Definitions = sim.query_definitions()
	var magazine: int = definitions.gear_index("drum_magazine")
	var slot: int = definitions.gear_slot_index("magazine")
	assert_false(sim.query_gear_is_unlocked(magazine))

	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(-4, ground, 0))
	])
	assert_eq(sim.query_depth_reached(), 1, "a Miner is working the Depth the tier is gated at")

	assert_eq(
		sim.query_delivery_refusal(0), Simulation.Refusal.NONE, "standing at the counter, holding plate"
	)
	sim.step([InputAction.deliver_to_nest(0)])
	assert_true(sim.query_completed_deliveries().has("t01_munitions"), "the tier is paid")

	assert_true(sim.query_gear_is_unlocked(magazine), "which is what unlocked the magazine")
	assert_eq(sim.query_fit_refusal(0, slot, magazine), Simulation.Refusal.NONE)
	_fit(sim, "drum_magazine")
	_equip(sim, "bolt_rifle")
	assert_eq(
		sim.query_player_weapon_interval_ticks(0),
		15,
		"-75% of one second: the Factory bought a faster weapon"
	)


func test_a_fourth_weapon_is_a_row_and_nothing_in_sim_knows_it() -> void:
	# The claim #10 proved for a Cannon Turret, proved again for a weapon: a fourth one
	# differs in a handful of columns and in nothing named anywhere in `sim/`.
	var cannon: String = (
		GEAR
		+ "rivet_cannon,Rivet Cannon,weapon,ranged,240,120,0,2,ammunition,8,0,0,0,0,0,0\n"
	)
	var sim: Simulation = _sim(ONE_BREAKER, [], DIAGONAL_BREACH, 1, cannon)
	assert_eq(sim.query_definitions().weapon_count(), 4, "four frames, from four rows")

	_equip(sim, "rivet_cannon")
	assert_eq(sim.query_player_weapon(0), "rivet_cannon")
	assert_eq(sim.query_player_weapon_range_metres(0), Fixed.from_int(120), "further")
	assert_eq(sim.query_player_weapon_damage(0), 240, "harder")
	assert_eq(sim.query_player_weapon_ammunition_per_shot(0), 8, "and eight rounds a shot")

	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)
	var before: int = sim.query_player_ammunition(0)
	sim.step([InputAction.fire(0)])
	assert_eq(sim.query_enemy_count(), 0, "240 against a Breaker's 240, in one shot")
	assert_eq(before - sim.query_player_ammunition(0), 8)


# ── Spread, recoil and aiming ─────────────────────────────────────────────────

func test_spread_scatters_a_shot_and_a_sight_tightens_it() -> void:
	# What separates a precise weapon from a crowd-clearing one. Measured as a hit rate
	# rather than as an angle, because a hit rate is what a player experiences: a weapon
	# with five degrees of scatter misses a Crawler nine metres away about half the time,
	# and the same weapon behind a sight that halves its spread misses far less.
	var wide: String = (
		GEAR.replace(
			"drum_autocannon,Drum Autocannon,weapon,ranged,10,30,0,0.1,ammunition,2,0,0,0,0,0,0",
			"drum_autocannon,Drum Autocannon,weapon,ranged,1,30,5,0.1,ammunition,2,0,0,0,0,0,0"
		)
		. replace(
			"reflex_sight,Reflex Sight,sight,,0,0,0,0,,0,0,10,0,0,0,0",
			"reflex_sight,Reflex Sight,sight,,0,0,0,0,,0,0,0,-80,0,0,0"
		)
	)
	var loose: int = _hits_in(_scatter_sim(wide, false), 600)
	var tight: int = _hits_in(_scatter_sim(wide, true), 600)

	assert_true(loose > 0, "a wide weapon does land some of them")
	assert_true(
		tight > loose,
		"and a sight that takes eighty percent off the scatter lands more: %d against %d"
		% [tight, loose]
	)


## A Run with the scattering autocannon in hand, aimed at the diagonal Breach, optionally
## behind the sight. Its Crawler has enough health to absorb every shot, so what the hit
## count measures is aim and not kills.
func _scatter_sim(gear: String, with_sight: bool) -> Simulation:
	var sim: Simulation = _sim(
		ONE_CRAWLER,
		[["crawler_health = 30", "crawler_health = 1000000"]],
		DIAGONAL_BREACH,
		1,
		gear
	)
	_equip(sim, "drum_autocannon")
	if with_sight:
		_fit(sim, "reflex_sight")
	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)
	return sim


## How many of the shots fired over `ticks` actually connected, read off the Crawler's
## health rather than off anything the Simulation reports about aiming.
func _hits_in(sim: Simulation, ticks: int) -> int:
	var before: int = sim.query_enemy_health(0)
	for tick: int in range(ticks):
		sim.step([InputAction.fire(0)])
	# One damage a shot, so the health lost is the hit count.
	return before - sim.query_enemy_health(0)


func test_recoil_moves_the_aim_up_and_brings_it_back_down() -> void:
	# Recoil is Simulation state because it moves where the *next* round goes, not merely
	# where the camera points. A kick the renderer applied on its own would be a lie about
	# aiming — and it would not be hashed, so two clients would disagree about it.
	var sim: Simulation = _sim()
	_equip(sim, "drum_autocannon")
	assert_eq(sim.query_player_view_kick_turns(0), 0, "a Run opens level")
	var level: int = sim.query_player_aim_pitch_turns(0)

	# Twelve ticks of a weapon that fires every six: two shots' worth of kick.
	for tick: int in range(12):
		sim.step([InputAction.fire(0)])
	var kicked: int = sim.query_player_aim_pitch_turns(0)
	assert_true(kicked > level, "the barrel has climbed")
	assert_eq(
		sim.query_player_camera_pitch_turns(0),
		kicked,
		"and the camera shows exactly where the next round will go"
	)

	# And it comes all the way back down once the trigger is let go. Proportional recovery
	# plus a floor of one unit a tick, so it reaches exactly zero rather than converging on
	# it for ever.
	var settled: int = _step_until(
		sim, 600, func() -> bool: return sim.query_player_view_kick_turns(0) == 0
	)
	assert_true(settled != -1, "and it comes all the way back down")
	assert_eq(sim.query_player_aim_pitch_turns(0), level)


# ── Health, Downed and death ──────────────────────────────────────────────────

## A player who can be killed in two bites, so a test about mortality is not a test about
## patience: `enemy.crawler_damage` is 10 a second against twenty hit points.
const FRAGILE: Array = [["health = 150", "health = 20"]]

## A Crawler at its real speed, walking at a player standing where a Run starts them.
const WALKING: Array = [
	["crawler_speed_metres_per_second = 0.03", "crawler_speed_metres_per_second = 3"]
]


## A Run whose Breach is two tiles south of the player and whose Nest is four tiles north of
## them, so the only way from one to the other is straight over where the player is standing.
##
## The Nest has to be far enough that a Crawler reaches the player *first*: an Enemy stops
## the moment it has anything at all to bite, and a Nest one tile behind the player would
## come into contact a tile before the player came into reach. Four tiles out is comfortably
## clear of that.
func _hunted_sim(players: int = 1, overrides: Array = []) -> Simulation:
	var substitutions: Array = []
	substitutions.append_array(FRAGILE)
	substitutions.append_array(WALKING)
	substitutions.append_array(overrides)
	return _sim(
		ONE_CRAWLER, substitutions, Vector3i(0, 0, -2), players, GEAR, Vector3i(0, 0, 4)
	)


func test_a_crawler_bites_a_player_who_stands_in_its_way() -> void:
	var sim: Simulation = _hunted_sim()
	assert_eq(sim.query_player_health(0), 20, "the fixture's hit points")
	assert_eq(sim.query_player_max_health(0), 20)
	assert_true(sim.query_player_is_alive(0))

	var bitten: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_player_health(0) < 20
	)
	assert_true(bitten != -1, "a Crawler walked up and bit the player")
	assert_eq(sim.query_player_health(0), 10, "ten a bite")


func test_a_solo_player_at_zero_health_dies_outright_and_respawns_at_the_nest() -> void:
	# **Solo play has no Downed state** (GLOSSARY.md): there is nobody to revive you, so a
	# Downed state on a one-player Run would be a pause with no counterplay in it.
	var sim: Simulation = _hunted_sim()
	var down: int = _step_until(
		sim, 2400, func() -> bool: return not sim.query_player_is_alive(0)
	)
	assert_true(down != -1, "two bites took twenty hit points")
	assert_false(sim.query_player_is_downed(0), "solo play has no Downed state")
	assert_true(sim.query_player_is_dead(0), "a solo player dies outright")

	# `player.respawn_delay_seconds` is 8: four hundred and eighty ticks, less the one they
	# died on, which is already spent by the time anything can observe it.
	assert_eq(sim.query_player_respawn_ticks_remaining(0), 479)
	var back: int = _step_until(sim, 600, func() -> bool: return sim.query_player_is_alive(0))
	assert_eq(back, 480, "and they come back when it runs out, to the tick")

	assert_eq(sim.query_player_health(0), 20, "whole")
	var at: FixedVec2 = sim.query_player_position(0)
	assert_true(
		sim.query_nest_covers_tile(WorldGrid.tile_at_metres(at.x, at.z)),
		"standing in the middle of the Nest's footprint, which is the one place on the Map"
		+ " that is always there and never moves"
	)


func test_death_costs_no_resources_and_no_progress() -> void:
	# The acceptance criterion, and it is written as the absence of code: `_respawn` touches
	# position, health and the clock. Nothing drops, nothing is unlearnt, nothing falls down.
	var sim: Simulation = _hunted_sim()
	_equip(sim, "bolt_rifle")
	_fit(sim, "heavy_barrel")

	var plates: int = sim.query_player_item(0, "iron_plate")
	var rounds: int = sim.query_player_ammunition(0)
	var weapon: String = sim.query_player_weapon(0)
	var fitted: PackedStringArray = sim.query_player_components(0)
	var unlocked: PackedStringArray = sim.query_unlocked_gear()
	assert_true(plates > 0, "the player is carrying materials")

	var died: int = _step_until(sim, 3600, func() -> bool: return sim.query_player_is_dead(0))
	assert_true(died != -1, "two bites and they are gone")
	var back: int = _step_until(sim, 600, func() -> bool: return sim.query_player_is_alive(0))
	assert_eq(back, 480, "and back eight seconds later, to the tick")

	assert_eq(sim.query_player_item(0, "iron_plate"), plates, "not a plate lost")
	assert_eq(sim.query_player_ammunition(0), rounds, "not a round lost")
	assert_eq(sim.query_player_weapon(0), weapon, "the same weapon in the same hands")
	assert_eq(sim.query_player_components(0), fitted, "with the same components on it")
	assert_eq(sim.query_unlocked_gear(), unlocked, "and nothing unlearnt")


func test_a_downed_or_dead_player_cannot_act_and_the_hud_is_told_why() -> void:
	# A refusal rather than a mode. Nothing in the Simulation asks whether acting is
	# currently permitted; what it asks is whether *this* player is on their feet, which is
	# a fact about them in the same way their wallet is. So building is still never gated.
	var ground: int = WorldGrid.GROUND_LAYER
	var sim: Simulation = _hunted_sim()
	var down: int = _step_until(
		sim, 2400, func() -> bool: return not sim.query_player_is_alive(0)
	)
	assert_true(down != -1)

	var smelter: int = sim.query_definitions().machine_index("smelter_mk1")
	assert_eq(
		sim.query_build_refusal(0, smelter, Vector3i(8, ground, 8), 0),
		Simulation.Refusal.PLAYER_IS_DOWN
	)
	assert_eq(sim.query_fire_refusal(0), Simulation.Refusal.PLAYER_IS_DOWN)
	assert_eq(sim.query_repair_refusal(0, Vector3i(8, ground, 8)), Simulation.Refusal.PLAYER_IS_DOWN)
	assert_eq(sim.query_delivery_refusal(0), Simulation.Refusal.PLAYER_IS_DOWN)
	assert_eq(sim.query_call_wave_early_refusal(0), Simulation.Refusal.PLAYER_IS_DOWN)
	assert_eq(
		sim.query_withdraw_refusal(0, sim.query_definitions().item_index("ammunition")),
		Simulation.Refusal.PLAYER_IS_DOWN,
		"including the Nest counter: a Downed player is not shopping"
	)

	var before: FixedVec2 = sim.query_player_position(0)
	sim.step([
		InputAction.move(0, Fixed.ONE, 0),
		InputAction.build_machine(0, smelter, Vector3i(8, ground, 8), 0),
		InputAction.fire(0),
	])
	var after: FixedVec2 = sim.query_player_position(0)
	assert_eq(after.x, before.x, "immobilised, as GLOSSARY.md says")
	assert_eq(after.z, before.z)
	assert_eq(sim.query_machine_count(), 0, "and nothing was built")
	assert_eq(sim.query_player_last_shot_tick(0), -1, "and nothing was fired")


func test_a_second_player_is_downed_rather_than_killed_and_bleeds_out() -> void:
	var sim: Simulation = _hunted_sim(2)
	var down: int = _step_until(
		sim, 2400, func() -> bool: return not sim.query_player_is_alive(0)
	)
	assert_true(down != -1)
	assert_true(sim.query_player_is_downed(0), "with a teammate on the Map, they go down")
	assert_false(sim.query_player_is_dead(0))

	# `player.downed_bleed_out_seconds` is 20: twelve hundred ticks, of which the tick they
	# went down on is already spent by the time anything can observe it — the same reason a
	# Machine does not run on the tick it was built.
	assert_eq(sim.query_player_downed_ticks_remaining(0), 1199, "the window a teammate has")
	var died: int = _step_until(sim, 1500, func() -> bool: return sim.query_player_is_dead(0))
	assert_eq(died, 1200, "and failing that, they die when it runs out")
	assert_eq(sim.query_player_downed_ticks_remaining(0), 0)


func test_a_teammate_picks_a_downed_player_up() -> void:
	# Hand repair pointed at a person, and the same trade in the same currency: what it
	# costs the rescuer is standing still, in the open, during a Wave, doing nothing else.
	var sim: Simulation = _hunted_sim(2)
	var down: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_player_is_downed(0)
	)
	assert_true(down != -1)

	# The Crawler that put player 0 down would go on to the next nearest player, who is the
	# rescuer — so the rescuer swings the wrench at it first. A rescue in a Wave is itself a
	# fight, which is the point of making revives cost presence.
	_kill_what_is_in_front(sim, 1)
	assert_eq(sim.query_revive_refusal(1, 0), Simulation.Refusal.NONE, "standing over them")

	# `player.revive_seconds` is 4: two hundred and forty ticks of holding it.
	for tick: int in range(239):
		sim.step([InputAction.revive(1, 0)])
	assert_true(sim.query_player_is_downed(0), "still down one tick short of it")
	assert_true(sim.query_player_health(0) > 0, "but coming back")

	sim.step([InputAction.revive(1, 0)])
	assert_true(sim.query_player_is_alive(0), "and up at four seconds, to the tick")
	assert_eq(sim.query_player_health(0), 20, "whole")


## Swings the Pneumatic Wrench until whatever is in front of a player is gone. Bounded, so a
## broken Simulation fails rather than hangs.
func _kill_what_is_in_front(sim: Simulation, player_id: int) -> void:
	for tick: int in range(600):
		if sim.query_enemy_count() == 0:
			return
		sim.step([InputAction.fire(player_id)])
	fail("the wrench never connected with what was chewing on the rescuer")


func test_a_revive_let_go_of_banks_nothing() -> void:
	# The rule Power credit, Heat credit and the wrench all obey: credit does not survive
	# letting go. A rescuer cannot tap the key for an hour and spend the bank in one tick.
	var sim: Simulation = _hunted_sim(2)
	var down: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_player_is_downed(0)
	)
	assert_true(down != -1)

	_kill_what_is_in_front(sim, 1)
	for cycle: int in range(100):
		sim.step([InputAction.revive(1, 0)])
		sim.step([])
	assert_true(
		sim.query_player_is_downed(0),
		"a hundred ticks of holding it, spread over two hundred, bought nothing extra —"
		+ " where a hundred held together would have been nearly half a revive"
	)


func test_a_solo_run_has_nobody_to_revive() -> void:
	var sim: Simulation = _hunted_sim()
	assert_eq(
		sim.query_revive_refusal(0, 0),
		Simulation.Refusal.NO_TEAMMATE,
		"solo play has no Downed state, so there is never anybody to pick up"
	)


func test_plating_reduces_the_damage_a_player_takes() -> void:
	# The one Gear modifier that is not about the weapon, and the reason this table is Gear
	# rather than Weapons: GLOSSARY.md says Gear is "weapons and equipment".
	var sim: Simulation = _hunted_sim()
	_fit(sim, "hardened_plating")
	assert_eq(
		sim.query_player_component(0, sim.query_definitions().gear_slot_index("plating")),
		"hardened_plating"
	)

	var bitten: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_player_health(0) < 20
	)
	assert_true(bitten != -1, "a Crawler bit the player")
	assert_eq(sim.query_player_health(0), 15, "-50% of a ten-point bite is five")


func test_an_enemy_takes_a_machine_over_a_player_and_a_player_over_the_nest() -> void:
	# The clause order, which *is* the design. A Breaker still prefers the Factory with
	# somebody standing in front of it — which is what makes GLOSSARY.md's "preferentially
	# attacks Machines rather than players" literal rather than aspirational — and a player
	# ranks above the Nest, so putting yourself in a doorway buys the Nest time at the price
	# of your own skin.
	var ground: int = WorldGrid.GROUND_LAYER

	# A Breaker, a Machine within reach of it, and a player standing right there.
	var hunted: Simulation = _sim(
		ONE_BREAKER, WALKING, Vector3i(0, 0, -2), 1, GEAR, Vector3i(0, 0, 4)
	)
	hunted.step([
		InputAction.build_machine(
			0, hunted.query_definitions().machine_index("smelter_mk1"), Vector3i(-1, ground, -2)
		)
	])
	assert_eq(hunted.query_machine_count(), 1)
	var chewed: int = _step_until(
		hunted, 1200, func() -> bool: return hunted.query_machine_health(0) < 500
	)
	assert_true(chewed != -1, "the Breaker went for the Smelter")
	assert_eq(
		hunted.query_player_health(0),
		hunted.query_player_max_health(0),
		"and left the player standing beside it entirely alone"
	)

	# The same Breach with no Machine on the Map, and the Nest on the far side of the player.
	var exposed: Simulation = _hunted_sim()
	var hurt: int = _step_until(
		exposed,
		1200,
		func() -> bool: return exposed.query_player_health(0) < exposed.query_player_max_health(0)
	)
	assert_true(hurt != -1, "with nothing to break, it bit the player")
	assert_eq(
		exposed.query_nest_health(),
		exposed.query_nest_max_health(),
		"and the Nest it was standing at went untouched, because a player ranks above it"
	)


# ── The loop closed ───────────────────────────────────────────────────────────

func test_a_player_can_take_the_ammunition_the_factory_made_and_fire_it() -> void:
	# **The keystone loop, end to end, in one test.** The shipped `player.starting_stock` is
	# plate alone on purpose, so a Run opens unable to fire a shot: what arms a player is the
	# Factory. An Ammo Press makes rounds, a Belt banks them in the Nest past the open bill
	# (#27), the player withdraws them at the counter, and then — and only then — the rifle
	# works. Every link of that is somebody else's ticket; the one this file owns is the last.
	var ground: int = WorldGrid.GROUND_LAYER
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(2, ground, -2)
	layout.add_node(Vector3i(-6, ground, 10), "iron_ore", 1)
	layout.add_breach(Vector3i(4, ground, -5))
	layout.sort_breaches()
	layout.sort_nodes()
	# The shipped bill, not the fixture's: the whole point is that nothing was handed over.
	var content: Definitions = _content(ONE_CRAWLER, [[ARMED_STOCK, SHIPPED_STOCK]])
	assert_false(content.has_errors(), content.describe_errors())
	var sim: Simulation = Simulation.new(11, 1, content, layout)

	_equip(sim, "bolt_rifle")
	assert_eq(sim.query_player_ammunition(0), 0, "a Run opens with no rounds at all")
	assert_eq(
		sim.query_fire_refusal(0),
		Simulation.Refusal.OUT_OF_AMMUNITION,
		"so the rifle is a stick until the Factory makes something"
	)

	var rounds: int = content.item_index("ammunition")
	assert_true(rounds != -1, "Ammunition is an Item the Recipes mention")
	assert_eq(
		sim.query_withdraw_refusal(0, rounds),
		Simulation.Refusal.NOTHING_TO_WITHDRAW,
		"and there is nothing on the counter either, because nothing has been made"
	)

	# A Miner on the ore, a Smelter behind it, an Ammo Press behind that, and a Belt out of
	# the Press into the Nest. Thirty-four plates of the eighty a Run opens with.
	_build(sim, "miner_mk1", Vector3i(-6, ground, 10))
	_build(sim, "smelter_mk1", Vector3i(1, ground, 10))
	_build(sim, "ammo_press_mk1", Vector3i(1, ground, 5))
	_belt(sim, Vector3i(-4, ground, 10), Vector3i(0, ground, 10))
	_belt(sim, Vector3i(1, ground, 9), Vector3i(1, ground, 8))
	_belt(sim, Vector3i(2, ground, 4), Vector3i(2, ground, 2))
	assert_eq(sim.query_machine_count(), 3, "three Machines and three Belts")
	assert_eq(sim.query_belt_count(), 3)

	var banked: int = _step_until(
		sim, 6000, func() -> bool: return sim.query_nest_store("ammunition") > 0
	)
	assert_true(banked != -1, "the Factory made rounds and the Nest banked them")

	assert_eq(sim.query_withdraw_refusal(0, rounds), Simulation.Refusal.NONE, "at the counter")
	sim.step([InputAction.withdraw_from_nest(0, rounds, 1)])
	assert_eq(sim.query_player_ammunition(0), 1, "one round, out of the Factory's own output")

	# And now the rifle works. One round, one Crawler — which is the sentence this whole
	# pillar is for: **you fight with what your Factory made.** The lever brings the Wave on,
	# because this Run has been building rather than waiting and the interval is two and a
	# half minutes.
	sim.step([InputAction.call_wave_early(0)])
	_wait_for_a_crawler(sim)
	_aim_at_the_diagonal(sim)
	assert_eq(sim.query_fire_refusal(0), Simulation.Refusal.NONE, "loaded at last")
	sim.step([InputAction.fire(0)])
	assert_eq(sim.query_enemy_count(), 0, "and the round the Factory made killed something")
	assert_eq(sim.query_player_ammunition(0), 0, "and it is gone, so the Factory makes another")


## Lays a Belt along a run and steps the tick that lays it.
func _belt(sim: Simulation, from_tile: Vector3i, to_tile: Vector3i) -> void:
	sim.step([InputAction.build_belt(0, from_tile, to_tile)])


## Builds a Machine by id at a tile and steps the tick that places it.
func _build(sim: Simulation, machine_id: String, tile: Vector3i) -> void:
	sim.step([
		InputAction.build_machine(0, sim.query_definitions().machine_index(machine_id), tile)
	])


# ── Save and load ─────────────────────────────────────────────────────────────

func test_gear_state_round_trips_through_save_and_load() -> void:
	# `RunSave` reflects over the Simulation's own properties, so none of the arrays this
	# ticket added needed a line in that file. This is the assertion that proves it.
	var sim: Simulation = _hunted_sim(2)
	_equip(sim, "bolt_rifle")
	_fit(sim, "heavy_barrel")
	# Mid-interval, mid-recoil, and with one player on the floor bleeding out.
	for tick: int in range(30):
		sim.step([InputAction.fire(0)])
	var down: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_player_is_downed(0)
	)
	assert_true(down != -1, "player 0 is Downed with a clock running")
	assert_true(sim.query_player_fire_cooldown_ticks(0) >= 0)

	var text: String = RunSave.serialise(sim)
	var restored: RunSave.Load = RunSave.deserialise(text, sim.query_definitions())
	assert_false(restored.has_errors(), restored.describe_errors())
	var resumed: Simulation = restored.simulation
	assert_eq(resumed.hash(), sim.hash(), "a Run written out and read back hashes the same")

	assert_eq(resumed.query_player_weapon(0), "bolt_rifle")
	assert_eq(resumed.query_player_components(0), sim.query_player_components(0))
	assert_eq(resumed.query_player_health(0), sim.query_player_health(0))
	assert_eq(
		resumed.query_player_downed_ticks_remaining(0),
		sim.query_player_downed_ticks_remaining(0),
		"including how long they have left"
	)

	# And it keeps hashing the same as the Run steps on, which is the stronger claim: a
	# restored Run that agreed for one tick and then drifted would pass the comparison above.
	for tick: int in range(120):
		sim.step([])
		resumed.step([])
		assert_eq(resumed.hash(), sim.hash())


func test_a_fitted_component_reaches_the_state_hash() -> void:
	# Everything new in state is hashed, because state that is not hashed is state whose
	# divergence the determinism harness cannot see.
	var bare: Simulation = _sim()
	var fitted: Simulation = _sim()
	assert_eq(bare.hash(), fitted.hash(), "two identical Runs")
	_fit(fitted, "heavy_barrel")
	_step(bare, 1)
	assert_ne(bare.hash(), fitted.hash(), "and one of them now has a barrel on its frame")


# ── Replay fixtures ───────────────────────────────────────────────────────────
#
# Three scenarios, left behind as recordings the way every ticket is expected to (CLAUDE.md):
# a weapon firing and killing a Crawler, a player going down and respawning, and a component
# changing measurable weapon behaviour. Each is paired with a second test that drives the
# identical script through a plain Simulation and asserts the scenario actually happened —
# a fixture that replays a Run in which nothing was shot would prove nothing at all.
#
# They run on the starter Map, which is what `DeterminismHarness.record` builds. They carry
# their own `Definitions` because the shipped bill opens a Run with no Ammunition at all, so
# a fixture about firing has to be handed rounds; `verify` compares the digest it recorded
# under before it compares a single tick, so the fixture cannot quietly pass against content
# that has since changed.

## Content for the fixtures: the shipped files — **including the shipped `gear.csv`**, so
## the recordings are of the real weapons rather than of this file's readable stand-ins —
## with a player armed and a Wave of Crawlers from a cold start so something arrives inside
## a few hundred ticks.
func _fixture_content() -> Definitions:
	return _content(
		MANY_CRAWLERS,
		[["crawler_speed_metres_per_second = 0.03", "crawler_speed_metres_per_second = 3"]],
		_read("res://content/gear.csv"),
		SHIPPED_DELIVERIES
	)


## The script every firing fixture replays: call the Wave, hold the trigger down through it,
## and keep walking so the Run is not a player standing still.
func _firing_script(extra: Array = []) -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.call_wave_early(0)])
	script.add_tick([InputAction.equip_weapon(0, _fixture_content().gear_index("drum_autocannon"))])
	for action: InputAction in extra:
		script.add_tick([action])
	script.add_idle_ticks(60)
	for burst: int in range(600):
		script.add_tick([InputAction.fire(0), InputAction.look(0, Fixed.from_int(2), 0)])
	return script


func test_determinism_a_weapon_firing_and_killing_a_crawler_replays_identically() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(
		_firing_script(), 11, 1, _fixture_content()
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_firing_fixture_really_did_kill_something() -> void:
	# The fixture's own honesty check. Without this, a replay of a Run in which the weapon
	# never fired would read as a passing determinism test.
	var sim: Simulation = Simulation.new(11, 1, _fixture_content())
	var script: InputScript = _firing_script()
	# Read after the weapon is in the player's hands: `query_player_ammunition` is about the
	# weapon being held, and the Pneumatic Wrench a Run opens with spends nothing.
	var rounds: int = 0
	var seen: int = 0
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		if tick == 2:
			rounds = sim.query_player_ammunition(0)
		seen = maxi(seen, sim.query_enemy_count())
	assert_true(rounds > 0, "the fixture's bill armed the player")
	assert_true(seen > 0, "a Wave arrived")
	assert_true(
		rounds - sim.query_player_ammunition(0) > 0, "and the player spent rounds on it"
	)
	assert_true(
		sim.query_player_last_shot_tick(0) != -1, "which means the weapon actually fired"
	)


## How many ticks of forward throttle put the player exactly on the Breach-to-Nest lane of
## the starter Map, and how far that is.
##
## A worked example rather than a number somebody tuned until it passed. The starter Map's
## Nest is at tile (-6, -6) and its Breach at (16, -6), so the lane between them is the
## centre of tile row z = -6, which is z = -11 metres. `player.walk_speed_metres_per_second`
## is 4 and `walk_acceleration` is 24, which is 0.4 m/s a tick — so a player holding forward
## reaches full speed in exactly ten ticks having covered (0.4 + 0.8 + … + 4.0) / 60 =
## 11/30 m, and then covers 1/15 m a tick. Ten ticks plus a hundred and sixty is
## 11/30 + 32/3 = 11.03 metres: the lane, to within three centimetres.
const TICKS_TO_THE_LANE: int = 170


## The script the mortality fixture replays: walk out of the Nest and stand in the road.
##
## A player who has sent no `MOVE` stands at the origin, which on the starter Map is eleven
## metres off the lane a Wave walks — so a fixture about being eaten has to put itself in
## the way. That is also the honest shape for one: being killed is something a player does
## to themselves by standing somewhere, and the recording says so.
func _mortality_script() -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.call_wave_early(0)])
	for tick: int in range(TICKS_TO_THE_LANE):
		script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(3600)
	return script


func test_determinism_a_player_going_down_and_respawning_replays_identically() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(
		_mortality_script(), 11, 2, _mortality_content()
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


## Content for the mortality fixture: a fragile player and Crawlers walking at them.
func _mortality_content() -> Definitions:
	return _content(
		MANY_CRAWLERS,
		[
			["crawler_speed_metres_per_second = 0.03", "crawler_speed_metres_per_second = 3"],
			["health = 150", "health = 20"],
			["respawn_delay_seconds = 8", "respawn_delay_seconds = 2"],
			["downed_bleed_out_seconds = 20", "downed_bleed_out_seconds = 3"],
		],
		_read("res://content/gear.csv"),
		SHIPPED_DELIVERIES
	)


func test_the_mortality_fixture_really_did_put_somebody_down() -> void:
	var sim: Simulation = Simulation.new(11, 2, _mortality_content())
	var script: InputScript = _mortality_script()
	var was_downed: bool = false
	var was_dead: bool = false
	var came_back: bool = false
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		if sim.query_player_is_downed(0):
			was_downed = true
		if sim.query_player_is_dead(0):
			was_dead = true
		if was_dead and sim.query_player_is_alive(0):
			came_back = true
	assert_true(was_downed, "a player went down rather than dying outright")
	assert_true(was_dead, "bled out")
	assert_true(came_back, "and respawned at the Nest")


func test_determinism_a_component_changing_weapon_behaviour_replays_identically() -> void:
	var definitions: Definitions = _fixture_content()
	var barrel: int = definitions.gear_index("heavy_barrel")
	var slot: int = definitions.gear_slot_index("barrel")
	var script: InputScript = _firing_script([InputAction.fit_component(0, slot, barrel)])
	var recording: ReplayRecording = DeterminismHarness.record(script, 11, 1, definitions)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_component_fixture_really_did_change_the_weapon() -> void:
	# The fixture is only worth recording if the barrel measurably changed the Run, so this
	# runs the same script with and without the fitting and compares what came of it.
	var definitions: Definitions = _fixture_content()
	var barrel: int = definitions.gear_index("heavy_barrel")
	var slot: int = definitions.gear_slot_index("barrel")

	var bare: Simulation = Simulation.new(11, 1, _fixture_content())
	var fitted: Simulation = Simulation.new(11, 1, _fixture_content())
	var bare_script: InputScript = _firing_script()
	var fitted_script: InputScript = _firing_script(
		[InputAction.fit_component(0, slot, barrel)]
	)
	for tick: int in range(bare_script.tick_count()):
		bare.step(bare_script.actions_at(tick))
	for tick: int in range(fitted_script.tick_count()):
		fitted.step(fitted_script.actions_at(tick))

	assert_eq(bare.query_player_weapon_damage(0), 12, "the shipped Drum Autocannon")
	assert_eq(
		fitted.query_player_weapon_damage(0), 16, "and +40% of it behind a Heavy Barrel"
	)
	assert_ne(
		bare.hash(), fitted.hash(), "which makes two measurably different Runs"
	)
