## The content definitions a Simulation is built from: Machines, Recipes, Items and
## tuning, loaded from files in `content/`.
##
## Why this exists: so that every later content ticket is additive rather than
## structural. Adding a Machine is a row in `machines.csv`; adding a Recipe is a row
## in `recipes.csv`; changing balance is a number in `tuning.toml`. No code change,
## no registry, no enum to extend — and the person tuning balance never has to be
## the person editing code.
##
## Three properties this module owes the rest of the project:
##
## **Deterministic.** Loading is part of Simulation construction, so the same files
## must produce the same `digest()` on every machine and in every process. Machines,
## Recipes and Items are therefore sorted by id, and tuning keys are sorted too, so
## the order rows happen to be written in — which drifts every time a human edits a
## table — cannot reach the state hash. Comments and blank lines cannot either.
##
## **Loud.** Every malformed value is an error naming the file, the row and the
## column. There are no defaults: a typo'd rate does not become 0, a missing tuning
## key does not become 0, a Machine pointing at a Recipe that does not exist is not
## quietly Recipe-less. And a set with any error at all carries *no* definitions,
## because half a definition set is more dangerous than none — it looks usable.
##
## **Immutable.** Nothing mutates a loaded set. Hot-reload builds a new one and
## swaps it in via an Input Action (see `InputAction.Kind.RELOAD_DEFINITIONS`), so
## the swap is ordered, visible in the state hash, and reproducible in a replay.
##
## Usage:
##
##     var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
##     if definitions.has_errors():
##         push_error(definitions.describe_errors())   # and do not start a Run
##     var sim: Simulation = Simulation.new(seed, players, definitions)
class_name Definitions
extends RefCounted

## Where the shipped content lives. `content/.gdignore` keeps Godot's importer out
## of it — left to itself, it claims every `.csv` as a translation table.
const CONTENT_DIR: String = "res://content"

const MACHINES_FILE: String = "machines.csv"
const RECIPES_FILE: String = "recipes.csv"
const TUNING_FILE: String = "tuning.toml"
const WAVES_FILE: String = "waves.csv"
const DELIVERIES_FILE: String = "deliveries.csv"
const GEAR_FILE: String = "gear.csv"

const MACHINE_COLUMNS: Array = [
	"id",
	"display_name",
	"role",
	"footprint_x",
	"footprint_z",
	"power_draw_kw",
	"power_supply_kw",
	"health",
	"max_depth",
	"range_tiles",
	"damage",
	"repair",
	"recipe_id",
	"build_cost",
]

const RECIPE_COLUMNS: Array = ["id", "display_name", "inputs", "outputs", "seconds"]

const WAVE_COLUMNS: Array = [
	"id",
	"enemy_kind",
	"min_heat",
	"count_per_breach",
	"heat_per_extra",
	"max_per_breach",
]

const DELIVERY_COLUMNS: Array = [
	"id",
	"display_name",
	"min_depth",
	"goods",
	"unlocks_machines",
	"unlocks_gear",
	"unlocks_stratagems",
]

const GEAR_COLUMNS: Array = [
	"id",
	"display_name",
	"kind",
	"attack",
	"damage",
	"range_metres",
	"spread_degrees",
	"seconds_per_shot",
	"ammunition_item",
	"ammunition_per_shot",
	"damage_percent",
	"range_percent",
	"spread_percent",
	"interval_percent",
	"ammunition_percent",
	"damage_taken_percent",
]

## Tuning keys the Simulation reads. Each must be present.
const TUNING_PLAYER_SPRINT_MULTIPLIER: String = "player.sprint_speed_multiplier"
const TUNING_PLAYER_WALK_SPEED: String = "player.walk_speed_metres_per_second"
const TUNING_PLAYER_WALK_ACCELERATION: String = (
	"player.walk_acceleration_metres_per_second_squared"
)
const TUNING_PLAYER_LOOK_SENSITIVITY: String = (
	"player.look_sensitivity_turns_per_1000_pixels"
)
const TUNING_PLAYER_EYE_HEIGHT: String = "player.eye_height_metres"
const TUNING_PLAYER_STARTING_STOCK: String = "player.starting_stock"
const TUNING_PLAYER_HEALTH: String = "player.health"
const TUNING_PLAYER_DOWNED_SECONDS: String = "player.downed_bleed_out_seconds"
const TUNING_PLAYER_RESPAWN_SECONDS: String = "player.respawn_delay_seconds"
const TUNING_PLAYER_REVIVE_SECONDS: String = "player.revive_seconds"
const TUNING_PLAYER_REVIVE_REACH: String = "player.revive_reach_metres"
const TUNING_PLAYER_STARTING_WEAPON: String = "player.starting_weapon"
const TUNING_GEAR_ENEMY_HIT_RADIUS: String = "gear.enemy_hit_radius_metres"
const TUNING_GEAR_ENEMY_HIT_HEIGHT: String = "gear.enemy_hit_height_metres"
const TUNING_GEAR_VIEW_KICK_DEGREES: String = "gear.view_kick_degrees_per_shot"
const TUNING_GEAR_VIEW_KICK_RECOVER_SECONDS: String = "gear.view_kick_recover_seconds"
const TUNING_ENEMY_BITE_REACH: String = "enemy.player_bite_reach_metres"
const TUNING_SURVEY_HEIGHT: String = "survey.height_metres"
const TUNING_SURVEY_TRANSITION_SECONDS: String = "survey.transition_seconds"
const TUNING_SURVEY_PITCH_DEGREES: String = "survey.pitch_degrees"
const TUNING_BELT_ITEMS_PER_SECOND: String = "belt.items_per_second"
const TUNING_BELT_ITEMS_PER_TILE: String = "belt.items_per_tile"
const TUNING_MACHINE_INPUT_BUFFER_CRAFTS: String = "machine.input_buffer_crafts"
const TUNING_WALL_HEALTH: String = "wall.health"
const TUNING_WRENCH_REPAIR_POINTS_PER_SECOND: String = "wrench.repair_points_per_second"
const TUNING_WRENCH_REACH_METRES: String = "wrench.reach_metres"
const TUNING_POWER_BASELINE_SUPPLY_KW: String = "power.baseline_supply_kw"
const TUNING_NEST_HEALTH: String = "nest.health"
const TUNING_NEST_DELIVERY_REACH: String = "nest.delivery_reach_metres"
const TUNING_NEST_STORE_CAPACITY: String = "nest.store_capacity_per_item"
const TUNING_WAVE_TELEGRAPH_SECONDS: String = "wave.telegraph_seconds"
const TUNING_WAVE_SPAWN_INTERVAL_SECONDS: String = "wave.spawn_interval_seconds"
const TUNING_WAVE_CALL_EARLY_BOUNTY: String = "wave.call_early_bounty_per_item"
const TUNING_HEAT_PER_CRAFT: String = "heat.per_craft"
const TUNING_HEAT_PER_CRAFT_PER_DEPTH: String = "heat.per_craft_per_depth"
const TUNING_HEAT_DECAY_PER_MINUTE: String = "heat.decay_per_minute"
const TUNING_HEAT_WAVE_INTERVAL_BASELINE: String = "heat.wave_interval_baseline_seconds"
const TUNING_HEAT_WAVE_INTERVAL_MINIMUM: String = "heat.wave_interval_minimum_seconds"
const TUNING_HEAT_PER_SECOND_SOONER: String = "heat.per_second_sooner"
const TUNING_DEPTH_DRAW_PERCENT: String = "depth.draw_percent_per_depth"
const TUNING_DEPTH_BREACH_TIER: String = "depth.breach_tier"
const TUNING_DEPTH_BREACH_CRAFTS: String = "depth.breach_crafts"
const TUNING_DEPTH_BREACH_OFFSET_TILES: String = "depth.breach_offset_tiles"
const TUNING_DEPTH_BREACH_TELEGRAPH_SECONDS: String = "depth.breach_telegraph_seconds"
const TUNING_CRAWLER_HEALTH: String = "enemy.crawler_health"
const TUNING_CRAWLER_SPEED: String = "enemy.crawler_speed_metres_per_second"
const TUNING_CRAWLER_DAMAGE: String = "enemy.crawler_damage"
const TUNING_CRAWLER_ATTACK_INTERVAL_SECONDS: String = (
	"enemy.crawler_attack_interval_seconds"
)
const TUNING_BREAKER_HEALTH: String = "enemy.breaker_health"
const TUNING_BREAKER_SPEED: String = "enemy.breaker_speed_metres_per_second"
const TUNING_BREAKER_DAMAGE: String = "enemy.breaker_damage"
const TUNING_BREAKER_ATTACK_INTERVAL_SECONDS: String = (
	"enemy.breaker_attack_interval_seconds"
)
const TUNING_SIEGE_HULK_HEALTH: String = "siege_hulk.health"
const TUNING_SIEGE_HULK_SPEED: String = "siege_hulk.speed_metres_per_second"
const TUNING_SIEGE_HULK_RANGE: String = "siege_hulk.range_metres"
const TUNING_SIEGE_HULK_SHELL_DAMAGE: String = "siege_hulk.shell_damage"
const TUNING_SIEGE_HULK_BLAST_RADIUS: String = "siege_hulk.shell_blast_radius_metres"
const TUNING_SIEGE_HULK_SHELL_INTERVAL: String = "siege_hulk.shell_interval_seconds"
const TUNING_SIEGE_HULK_SHELL_FLIGHT: String = "siege_hulk.shell_flight_seconds"
const TUNING_SIEGE_HULK_STOMP_DAMAGE: String = "siege_hulk.stomp_damage"
const TUNING_SIEGE_HULK_ARMOUR_PERCENT: String = "siege_hulk.frontal_armour_percent"
const TUNING_SIEGE_HULK_HIT_RADIUS: String = "siege_hulk.hit_radius_metres"
const TUNING_SIEGE_HULK_HIT_HEIGHT: String = "siege_hulk.hit_height_metres"
const TUNING_HIVE_HEALTH: String = "hive.health"
const TUNING_HIVE_HEAT_SHADOW: String = "hive.heat_shadow_per_minute"
const TUNING_HIVE_HIT_RADIUS: String = "hive.hit_radius_metres"
const TUNING_HIVE_HIT_HEIGHT: String = "hive.hit_height_metres"

## Every problem that makes this set unusable, each naming the file and the row.
var errors: PackedStringArray = PackedStringArray()

## Problems that do not make the set unusable but mislead whoever is reading the
## files — chiefly a tuning key nothing reads.
var warnings: PackedStringArray = PackedStringArray()

## How fast a player walks, in fixed-point metres per second.
var player_walk_speed: int = 0

## How much faster a sprinting player moves. Multiplies walk speed.
var player_sprint_multiplier: int = 0

## How hard a player accelerates towards the walking speed, in fixed-point metres
## per second squared. The same figure decelerates them when they let go.
var player_walk_acceleration: int = 0

## How far a player turns per 1000 pixels of mouse travel, in fixed-point turns.
## The Simulation applies this to the pixel count an Input Action carries, so the
## sensitivity is authoritative rather than something a client chooses.
var player_look_sensitivity: int = 0

## How high a player's eyes are off the ground, in fixed-point metres.
var player_eye_height: int = 0

## What a player starts a Run carrying, as parallel Item ids and counts.
##
## An explicit bill rather than a count of everything, which is what it used to be —
## `player.starting_stock_per_item` granted 200 of every Item in the game and said in its
## own comment that it was a scaffold for Delivery progression to replace. It is replaced:
## a Run now opens with exactly the materials for its opening line, and everything past
## that is unlocked at the Nest.
##
## Written in the same `item:count` form a Recipe's inputs and a Machine's `build_cost`
## use, and parsed by the same function, so there is one answer to what well-formed means.
## Empty is legal and means a Run opens empty-handed.
var player_starting_stock_items: PackedStringArray = PackedStringArray()
var player_starting_stock_counts: PackedInt64Array = PackedInt64Array()

## A player's hit points. Whole points, exactly as a Machine's and the Nest's are:
## damage is counted in them and a fraction of a hit point is a rounding rule nobody
## needs. The number that decides how long a player survives standing in the open, which
## is the thing hand repair spends.
var player_health: int = 0

## How long a Downed player bleeds out before dying, in fixed-point seconds. The window
## a teammate has to reach them. **Solo play has no Downed state at all** (GLOSSARY.md) —
## there is nobody to revive you — so on a one-player Run this number is never consulted.
var player_downed_bleed_out_seconds: int = 0

## How long a dead player waits before respawning at the Nest, in fixed-point seconds.
## The whole of what death costs: tempo, never progress and never resources.
var player_respawn_delay_seconds: int = 0

## How long one teammate takes to bring a Downed player back up, in fixed-point seconds.
## Spent as an integer credit against the tick rate, so the total is exact.
var player_revive_seconds: int = 0

## How close a teammate has to stand to revive, in fixed-point metres.
var player_revive_reach_metres: int = 0

## The Gear a Run opens holding, by id. Must name a `weapon` row in `content/gear.csv`.
##
## A tuning key rather than a constant in `sim/`, for the reason `starting_stock` is one:
## naming a piece of Gear in the Simulation is the thing this project does not do. Which
## weapon a Run starts with is a balance decision, and a fourth weapon becoming the
## opening one must be an edit to a file.
var player_starting_weapon: String = ""

## How far from the line of a shot an Enemy may stand and still be hit, in fixed-point
## metres, and how tall its hit volume is.
##
## An Enemy is a point in the Simulation (#9: a position and a kind, never a node), so a
## shot needs a volume to resolve against and these two are it: a capsule of this radius
## standing this tall on the Enemy's tile. **Both are pure feel.** Too thin and a swarm is
## unhittable at twenty metres; too fat and spread stops meaning anything.
var gear_enemy_hit_radius_metres: int = 0
var gear_enemy_hit_height_metres: int = 0

## How far a shot kicks the view up, in fixed-point degrees, and how long the kick takes
## to come back down, in fixed-point seconds.
##
## Recoil is Simulation state because it moves where the *next* shot goes, not merely
## where the camera points — a kick that only the renderer knew about would be a lie
## about aiming. Both are the most feel-critical numbers in this file after the weapons'
## own spread.
var gear_view_kick_degrees_per_shot: int = 0
var gear_view_kick_recover_seconds: int = 0

## How high the Survey View camera rises to, in fixed-point metres.
var survey_height: int = 0

## How long the Survey View lift takes each way, in fixed-point seconds.
var survey_transition_seconds: int = 0

## How far down the Survey View camera tilts at the top, in fixed-point degrees.
var survey_pitch_degrees: int = 0

## The Nest's hit points. The Run ends when these reach zero, and nothing else ends
## it. Whole points rather than fixed point: damage is counted in them.
var nest_health: int = 0

## How close a player stands to the Nest's footprint to hand a Delivery over, in
## fixed-point metres. The same reach a withdrawal is made from: banking and spending
## happen at one counter, so there is one distance to stand at and not two.
var nest_delivery_reach: int = 0

## How many of **each** Item the Nest's store will hold, in whole Items.
##
## Per Item rather than one total across all of them, and no Item is named: the set of
## Items is whatever the Recipes mention, so a per-Item key would be a second Item table
## (the argument `player.starting_stock` makes). One number applied to each Item
## independently also keeps a Belt of coal from crowding plate out of the store, which
## would be a cross-Item interaction nobody tuned and whose outcome depended on arrival
## order.
var nest_store_capacity_per_item: int = 0

## How long the Telegraph runs in front of a Wave, in fixed-point seconds. A floor on
## the warning rather than a target for it: no Wave arrives before it has been
## telegraphed this long, including one called early.
var wave_telegraph_seconds: int = 0

## How long between one Enemy of a Wave emerging and the next, in fixed-point seconds.
var wave_spawn_interval_seconds: int = 0

## How many of every Item calling a Wave early grants the player who pulled the lever.
var wave_call_early_bounty: int = 0

## How much Heat one completed craft adds, in whole heat units. Heat is made of crafts
## because a craft is the one event in the Factory that is unambiguously throughput and
## that a player watched themselves cause.
var heat_per_craft: int = 0

## How much more Heat a craft adds per tier of Depth the Resource came from.
var heat_per_craft_per_depth: int = 0

## How much Heat the Nest sheds per minute, in whole heat units. Flat rather than
## proportional: a proportional decay is a per-tick ratio, which is the shape that drifts
## over a forty-hour Run, and it would give the Factory an equilibrium Heat.
var heat_decay_per_minute: int = 0

## How long between Waves on a cold Factory, in fixed-point seconds. Also how far away
## the first Wave of a Run is, because a Run opens cold.
var heat_wave_interval_baseline_seconds: int = 0

## The shortest the interval between Waves ever gets, in fixed-point seconds.
var heat_wave_interval_minimum_seconds: int = 0

## How much Heat shaves one second off the interval between Waves.
var heat_per_second_sooner: int = 0

## How much more Power a Miner draws per tier of Depth past the first, as a whole
## percentage of its own quoted draw. A percentage of the Machine rather than a flat
## surcharge, so the cost scales with the Miner.
var depth_draw_percent_per_depth: int = 0

## The shallowest Depth whose extraction opens Breaches. Depth 1 is the ore a Run opens
## on, so the opening Factory is not a transgression.
var depth_breach_tier: int = 0

## How many completed crafts from one deep Node open a Breach near it. Per Node rather
## than per Miner: the geography is what did it.
var depth_breach_crafts: int = 0

## How far from the mine a newly opened Breach lands, in tiles of Chebyshev distance.
var depth_breach_offset_tiles: int = 0

## How long a newly opened Breach is telegraphed before it first lets anything out, in
## fixed-point seconds. Load-bearing exactly as `wave_telegraph_seconds` is.
var depth_breach_telegraph_seconds: int = 0

## A Crawler's hit points.
var crawler_health: int = 0

## How fast a Crawler moves, in fixed-point metres per second.
var crawler_speed: int = 0

## How much damage one Crawler does to the Nest per bite, in whole hit points.
var crawler_damage: int = 0

## How long between one Crawler's bites, in fixed-point seconds.
var crawler_attack_interval_seconds: int = 0

## A Breaker's hit points.
var breaker_health: int = 0

## How fast a Breaker moves, in fixed-point metres per second.
var breaker_speed: int = 0

## How much damage one Breaker bite does to whatever it is chewing, in whole hit points.
var breaker_damage: int = 0

## How long between one Breaker's bites, in fixed-point seconds.
var breaker_attack_interval_seconds: int = 0

## A Siege Hulk's hit points.
var siege_hulk_health: int = 0

## How fast a Siege Hulk walks, in fixed-point metres per second.
var siege_hulk_speed: int = 0

## How far a Siege Hulk shells, in fixed-point metres — **and therefore where it stands**.
##
## One number for both, because the Hulk advances until something it can shell is inside this
## radius and then holds: the stand-off is the reach, so there is no second figure that could
## disagree with it. `_check_siege_hulk_outranges_every_turret` refuses a set where this does
## not exceed every Turret's reach, which is what makes "it bombards from beyond Turret range"
## a property of the content rather than a hope about it.
var siege_hulk_range_metres: int = 0

## What one shell takes off whatever is at the impact point, in whole hit points.
var siege_hulk_shell_damage: int = 0

## How far from the impact point a shell is felt, in fixed-point metres.
var siege_hulk_shell_blast_radius_metres: int = 0

## How long between one shell and the next, in fixed-point seconds. Shared with the stomp, so
## a player standing at the Hulk's feet is a player stopping the bombardment.
var siege_hulk_shell_interval_seconds: int = 0

## How long a shell is in the air, in fixed-point seconds. Load-bearing exactly as
## `wave_telegraph_seconds` is: the impact point is marked on the ground for this long before
## anything happens there.
var siege_hulk_shell_flight_seconds: int = 0

## What a Siege Hulk does to a player within reach of it, in whole hit points.
var siege_hulk_stomp_damage: int = 0

## How much of a hit a Siege Hulk shrugs off from the front, as a whole percentage. The weak
## point is the absence of this behind it.
var siege_hulk_frontal_armour_percent: int = 0

## How wide and how tall a Siege Hulk's hit volume is, in fixed-point metres.
var siege_hulk_hit_radius_metres: int = 0
var siege_hulk_hit_height_metres: int = 0

## A Hive's hit points.
var hive_health: int = 0

## How much of the Nest's Heat shedding one living Hive drowns out, per minute, in whole heat
## units.
##
## **A Hive subtracts from the decay rather than adding to Heat**, which is the decision rather
## than an implementation detail. Adding would hunt an idle Run for standing still, and Heat is
## throughput in excess of what the Nest can hide (DESIGN.md) — a Factory producing nothing is
## owed its silence. Subtracting says the Nest hides less while these things are watching, so a
## Hive taxes *growth*, and clearing one gives the headroom back permanently and visibly, on the
## gauge `query_heat_decay_per_minute` already feeds.
var hive_heat_shadow_per_minute: int = 0

## How wide and how tall a Hive's hit volume is, in fixed-point metres.
var hive_hit_radius_metres: int = 0
var hive_hit_height_metres: int = 0

## How close an Enemy has to be to a player to bite them, in fixed-point metres.
##
## A distance rather than tile contact, unlike everything else an Enemy bites: the Nest,
## a Machine and a Wall all stand on tiles and a player does not — a player is a position
## in fixed-point metres, and asking which tile they are standing on would make a bite
## land or miss depending on which side of a tile boundary they were on.
var enemy_player_bite_reach_metres: int = 0

## A Wall's hit points. A Wall is not a Machine (DESIGN.md), so this is tuning rather
## than a row in `machines.csv`, exactly as a Belt's rating is.
var wall_health: int = 0

## How many hit points a held Pneumatic Wrench puts back per second, as a whole number.
## Spent as an integer credit against the tick rate rather than as a fixed-point fraction
## of a point per tick, so nothing drifts over a long Run.
var wrench_repair_points_per_second: int = 0

## How far a player may reach to repair, in fixed-point metres.
var wrench_reach_metres: int = 0

## A Belt's rated throughput, in fixed-point Items per second. The Simulation turns
## this into a whole number of ticks per Item, which is what makes the rate exact.
var belt_items_per_second: int = 0

## How many Items fit on one tile of Belt. A whole number, because it is a count of
## places rather than a measurement.
var belt_items_per_tile: int = 0

## How many crafts' worth of each input a Machine's input buffer holds.
var machine_input_buffer_crafts: int = 0

## What the one Power grid supplies before a single generator is built, in whole
## kilowatts. Whole, because every Power quantity in the Simulation is: the throttle
## is an exact integer ratio of supply to demand, and a fractional kilowatt would put
## a rounding decision in the one place that must not have one.
var power_baseline_supply_kw: int = 0

var _machines: Array = []
var _machine_ids: PackedStringArray = PackedStringArray()
var _recipes: Array = []
var _recipe_ids: PackedStringArray = PackedStringArray()
var _item_ids: PackedStringArray = PackedStringArray()
var _waves: Array = []
var _deliveries: Array = []
var _gear: Array = []
var _gear_ids: PackedStringArray = PackedStringArray()

## Every slot a component can be fitted into, sorted. **Interned from the Gear table's
## `kind` column rather than declared anywhere**, exactly as the Items are interned from
## what the Recipes mention: writing `barrel` in a row is what makes a barrel slot exist,
## so a fourth slot is a row and never a code change. Index order here is the slot index
## a `FIT_COMPONENT` intent carries.
var _gear_slot_ids: PackedStringArray = PackedStringArray()

## The Gear indices of the `weapon` rows, ascending. What the weapon-select keys step
## through, so a fourth weapon joins the list by being a row.
var _weapon_gear_indices: PackedInt64Array = PackedInt64Array()


# ── Loading ───────────────────────────────────────────────────────────────────

## Reads the three files out of a directory. A missing or unreadable file is an
## error naming the path, never an empty table.
static func load_from_directory(dir_path: String) -> Definitions:
	var missing: PackedStringArray = PackedStringArray()
	for file_name: String in [
		MACHINES_FILE, RECIPES_FILE, TUNING_FILE, WAVES_FILE, DELIVERIES_FILE, GEAR_FILE
	]:
		var path: String = "%s/%s" % [dir_path, file_name]
		if not FileAccess.file_exists(path):
			missing.append(path)

	if not missing.is_empty():
		var unreadable: Definitions = Definitions.new()
		for path: String in missing:
			unreadable.errors.append("%s: no such file" % path)
		return unreadable

	var machines: String = _read_file("%s/%s" % [dir_path, MACHINES_FILE])
	var recipes: String = _read_file("%s/%s" % [dir_path, RECIPES_FILE])
	var tuning: String = _read_file("%s/%s" % [dir_path, TUNING_FILE])
	var waves: String = _read_file("%s/%s" % [dir_path, WAVES_FILE])
	var deliveries: String = _read_file("%s/%s" % [dir_path, DELIVERIES_FILE])
	var gear: String = _read_file("%s/%s" % [dir_path, GEAR_FILE])

	var definitions: Definitions = parse(
		machines,
		recipes,
		tuning,
		waves,
		deliveries,
		gear,
		"%s/%s" % [dir_path, MACHINES_FILE],
		"%s/%s" % [dir_path, RECIPES_FILE],
		"%s/%s" % [dir_path, TUNING_FILE],
		"%s/%s" % [dir_path, WAVES_FILE],
		"%s/%s" % [dir_path, DELIVERIES_FILE],
		"%s/%s" % [dir_path, GEAR_FILE]
	)
	return definitions


## Builds a set from the file contents directly. The paths are used only to name
## errors, which is what lets a test exercise a malformed table without writing one
## to disk.
static func parse(
	machines_source: String,
	recipes_source: String,
	tuning_source: String,
	waves_source: String,
	deliveries_source: String,
	gear_source: String,
	machines_path: String = MACHINES_FILE,
	recipes_path: String = RECIPES_FILE,
	tuning_path: String = TUNING_FILE,
	waves_path: String = WAVES_FILE,
	deliveries_path: String = DELIVERIES_FILE,
	gear_path: String = GEAR_FILE
) -> Definitions:
	var definitions: Definitions = Definitions.new()

	var machines: CsvTable = CsvTable.parse(machines_source, machines_path, PackedStringArray(MACHINE_COLUMNS))
	var recipes: CsvTable = CsvTable.parse(recipes_source, recipes_path, PackedStringArray(RECIPE_COLUMNS))
	var tuning: TomlDocument = TomlDocument.parse(tuning_source, tuning_path)
	var waves: CsvTable = CsvTable.parse(waves_source, waves_path, PackedStringArray(WAVE_COLUMNS))
	var deliveries: CsvTable = CsvTable.parse(
		deliveries_source, deliveries_path, PackedStringArray(DELIVERY_COLUMNS)
	)
	var gear: CsvTable = CsvTable.parse(gear_source, gear_path, PackedStringArray(GEAR_COLUMNS))

	definitions._read_recipes(recipes)
	definitions._intern_items()
	definitions._read_machines(machines)
	definitions._check_machines_against_recipes(machines)
	# Gear before the Delivery table, because `unlocks_gear` has to name a Gear row — the
	# same rule `unlocks_machines` already obeys: one authority, checked rather than
	# assumed. And **tuning last**, because `player.starting_weapon` has to name a weapon
	# frame that no Delivery tier locks, which is a question only the two tables together
	# can answer. Nothing in the three tables reads a tuning value, so the order costs
	# nothing.
	definitions._read_gear(gear)
	definitions._read_waves(waves)
	definitions._read_deliveries(deliveries)
	definitions._read_tuning(tuning)

	# Errors are gathered in file order — machines, then Recipes, then tuning, then the
	# Wave table, the Delivery table and the Gear table — so the report reads like a list
	# of things to go and fix.
	definitions.errors.append_array(machines.errors)
	definitions.errors.append_array(recipes.errors)
	definitions.errors.append_array(tuning.errors)
	definitions.errors.append_array(waves.errors)
	definitions.errors.append_array(deliveries.errors)
	definitions.errors.append_array(gear.errors)

	if definitions.has_errors():
		definitions._discard_content()

	return definitions


## An empty set that is explicitly in error. What a caller gets when there is
## nothing to load, so that "no definitions" can never be mistaken for "loaded".
static func unloaded(reason: String) -> Definitions:
	var definitions: Definitions = Definitions.new()
	definitions.errors.append(reason)
	return definitions


# ── Verdict ───────────────────────────────────────────────────────────────────

func has_errors() -> bool:
	return not errors.is_empty()


func describe_errors() -> String:
	return "\n".join(errors)


func describe_warnings() -> String:
	return "\n".join(warnings)


# ── Machines ──────────────────────────────────────────────────────────────────

func machine_count() -> int:
	return _machines.size()


## Every Machine id, sorted. This is the index order the Simulation uses.
func machine_ids() -> PackedStringArray:
	return _machine_ids.duplicate()


func has_machine(id: String) -> bool:
	return _machine_ids.find(id) != -1


## The index of a Machine definition, or -1.
func machine_index(id: String) -> int:
	return _machine_ids.find(id)


func machine_at(index: int) -> MachineDefinition:
	if index < 0 or index >= _machines.size():
		return null
	return _machines[index]


## A Machine by id, or null. Null rather than a blank definition, so a mistyped id
## cannot be mistaken for a Machine with every value at zero.
func machine(id: String) -> MachineDefinition:
	return machine_at(machine_index(id))


# ── Recipes ───────────────────────────────────────────────────────────────────

func recipe_count() -> int:
	return _recipes.size()


func recipe_ids() -> PackedStringArray:
	return _recipe_ids.duplicate()


func has_recipe(id: String) -> bool:
	return _recipe_ids.find(id) != -1


func recipe_index(id: String) -> int:
	return _recipe_ids.find(id)


func recipe_at(index: int) -> RecipeDefinition:
	if index < 0 or index >= _recipes.size():
		return null
	return _recipes[index]


func recipe(id: String) -> RecipeDefinition:
	return recipe_at(recipe_index(id))


# ── Items ─────────────────────────────────────────────────────────────────────

func item_count() -> int:
	return _item_ids.size()


## Every Item id, sorted. Exactly the Items the Recipes mention.
func item_ids() -> PackedStringArray:
	return _item_ids.duplicate()


func item_index(id: String) -> int:
	return _item_ids.find(id)


func item_id(index: int) -> String:
	if index < 0 or index >= _item_ids.size():
		return ""
	return _item_ids[index]


# ── Wave composition ──────────────────────────────────────────────────────────
# The tiers a Wave is composed from, sorted by id. Index order is therefore the order
# Enemies are released in, and it is a property of the table rather than of the order
# somebody typed the rows in — which matters because that order reaches the state hash.

func wave_entry_count() -> int:
	return _waves.size()


func wave_entry_at(index: int) -> WaveEntry:
	if index < 0 or index >= _waves.size():
		return null
	return _waves[index]


# ── Deliveries ────────────────────────────────────────────────────────────────
# The tiers of progression, sorted by id. Index order is the order the chain is walked
# in, so it is a property of the table rather than of the order somebody typed the rows
# in — and it reaches the state hash, which is why it may not depend on row order.

func delivery_count() -> int:
	return _deliveries.size()


func delivery_at(index: int) -> DeliveryDefinition:
	if index < 0 or index >= _deliveries.size():
		return null
	return _deliveries[index]


func delivery_index(id: String) -> int:
	for index: int in range(_deliveries.size()):
		if _deliveries[index].id == id:
			return index
	return -1


func delivery(id: String) -> DeliveryDefinition:
	return delivery_at(delivery_index(id))


## Whether some Delivery tier is what unlocks a Machine — which is the same question as
## whether that Machine starts a Run locked.
##
## The one authority on it. There is no `locked` column in `machines.csv`, because the
## Machines a Run opens with are exactly the ones no tier names, and a second copy of
## that fact would fall out of step the first time a tier moved.
func locks_machine(machine_id: String) -> bool:
	for definition: DeliveryDefinition in _deliveries:
		if definition.unlocks_machine(machine_id):
			return true
	return false


## Whether some Delivery tier is what unlocks a piece of Gear — the same question as
## whether a Run starts without it. The Gear a Run opens with is exactly the Gear no tier
## names, which is why there is no `locked` column in `gear.csv` either.
func locks_gear(gear_id: String) -> bool:
	for definition: DeliveryDefinition in _deliveries:
		if definition.unlocks_gear.find(gear_id) != -1:
			return true
	return false


# ── Gear ──────────────────────────────────────────────────────────────────────
# Weapon frames and the components that fit them, sorted by id. Index order is what a
# `EQUIP_WEAPON` or `FIT_COMPONENT` intent carries, so — exactly as with the Machines —
# it is a property of the table rather than of the order somebody typed the rows in, and
# the Simulation stores the resolved *id* so a hot-reload cannot change what is in a
# player's hands.

func gear_count() -> int:
	return _gear.size()


func gear_ids() -> PackedStringArray:
	return _gear_ids.duplicate()


func has_gear(id: String) -> bool:
	return _gear_ids.find(id) != -1


func gear_index(id: String) -> int:
	return _gear_ids.find(id)


func gear_at(index: int) -> GearDefinition:
	if index < 0 or index >= _gear.size():
		return null
	return _gear[index]


## A piece of Gear by id, or null. Null rather than a blank definition, so a mistyped id
## cannot be mistaken for a weapon with every value at zero.
func gear(id: String) -> GearDefinition:
	return gear_at(gear_index(id))


## How many slots a weapon frame has. Exactly the number of distinct `kind` values the
## Gear table names other than `weapon`.
func gear_slot_count() -> int:
	return _gear_slot_ids.size()


func gear_slot_ids() -> PackedStringArray:
	return _gear_slot_ids.duplicate()


func gear_slot_id(index: int) -> String:
	if index < 0 or index >= _gear_slot_ids.size():
		return ""
	return _gear_slot_ids[index]


func gear_slot_index(slot_id: String) -> int:
	return _gear_slot_ids.find(slot_id)


## How many weapon frames there are, and the Gear index of the nth. What the weapon keys
## step through; a fourth weapon joins by being a row.
func weapon_count() -> int:
	return _weapon_gear_indices.size()


func weapon_gear_index(nth: int) -> int:
	if nth < 0 or nth >= _weapon_gear_indices.size():
		return -1
	return _weapon_gear_indices[nth]


# ── Hashing ───────────────────────────────────────────────────────────────────

## Reduces the whole definition set to one integer.
##
## Fed into `Simulation.hash()`, so the definitions a Run is using are part of its
## state hash. That is what makes a definition change visible rather than silent: a
## replay recorded under one set cannot pass under another, and a reload mid-Run
## changes the hash at the exact tick it is applied.
##
## Deliberately insensitive to file paths, row order, line numbers, comments and
## blank lines — a digest that changed when someone tidied a table would make the
## determinism guarantee unusable in practice.
func digest() -> int:
	var hasher: StateHasher = StateHasher.new()

	hasher.feed_int(_item_ids.size())
	for id: String in _item_ids:
		hasher.feed_text(id)

	hasher.feed_int(_recipes.size())
	for definition: RecipeDefinition in _recipes:
		definition.feed_into(hasher)

	hasher.feed_int(_machines.size())
	for definition: MachineDefinition in _machines:
		definition.feed_into(hasher)

	hasher.feed_int(_waves.size())
	for entry: WaveEntry in _waves:
		entry.feed_into(hasher)

	hasher.feed_int(_deliveries.size())
	for definition: DeliveryDefinition in _deliveries:
		definition.feed_into(hasher)

	hasher.feed_int(_gear.size())
	for definition: GearDefinition in _gear:
		definition.feed_into(hasher)
	# The slots too, even though they are derived from the rows above. They are the index
	# space a `FIT_COMPONENT` intent travels in, so a set that interned them differently
	# is a set a recorded script means something different under.
	hasher.feed_int(_gear_slot_ids.size())
	for slot_id: String in _gear_slot_ids:
		hasher.feed_text(slot_id)

	hasher.feed_int(player_walk_speed)
	hasher.feed_int(player_sprint_multiplier)
	hasher.feed_int(player_walk_acceleration)
	hasher.feed_int(player_look_sensitivity)
	hasher.feed_int(player_eye_height)
	hasher.feed_int(player_starting_stock_items.size())
	for slot: int in range(player_starting_stock_items.size()):
		hasher.feed_text(player_starting_stock_items[slot])
		hasher.feed_int(player_starting_stock_counts[slot])
	hasher.feed_int(survey_height)
	hasher.feed_int(survey_transition_seconds)
	hasher.feed_int(survey_pitch_degrees)
	hasher.feed_int(belt_items_per_second)
	hasher.feed_int(belt_items_per_tile)
	hasher.feed_int(machine_input_buffer_crafts)
	hasher.feed_int(power_baseline_supply_kw)
	hasher.feed_int(nest_health)
	hasher.feed_int(nest_delivery_reach)
	hasher.feed_int(nest_store_capacity_per_item)
	hasher.feed_int(wave_telegraph_seconds)
	hasher.feed_int(wave_spawn_interval_seconds)
	hasher.feed_int(wave_call_early_bounty)
	hasher.feed_int(heat_per_craft)
	hasher.feed_int(heat_per_craft_per_depth)
	hasher.feed_int(heat_decay_per_minute)
	hasher.feed_int(heat_wave_interval_baseline_seconds)
	hasher.feed_int(heat_wave_interval_minimum_seconds)
	hasher.feed_int(heat_per_second_sooner)
	hasher.feed_int(depth_draw_percent_per_depth)
	hasher.feed_int(depth_breach_tier)
	hasher.feed_int(depth_breach_crafts)
	hasher.feed_int(depth_breach_offset_tiles)
	hasher.feed_int(depth_breach_telegraph_seconds)
	hasher.feed_int(crawler_health)
	hasher.feed_int(crawler_speed)
	hasher.feed_int(crawler_damage)
	hasher.feed_int(crawler_attack_interval_seconds)
	hasher.feed_int(siege_hulk_health)
	hasher.feed_int(siege_hulk_speed)
	hasher.feed_int(siege_hulk_range_metres)
	hasher.feed_int(siege_hulk_shell_damage)
	hasher.feed_int(siege_hulk_shell_blast_radius_metres)
	hasher.feed_int(siege_hulk_shell_interval_seconds)
	hasher.feed_int(siege_hulk_shell_flight_seconds)
	hasher.feed_int(siege_hulk_stomp_damage)
	hasher.feed_int(siege_hulk_frontal_armour_percent)
	hasher.feed_int(siege_hulk_hit_radius_metres)
	hasher.feed_int(siege_hulk_hit_height_metres)
	hasher.feed_int(hive_health)
	hasher.feed_int(hive_heat_shadow_per_minute)
	hasher.feed_int(hive_hit_radius_metres)
	hasher.feed_int(hive_hit_height_metres)
	hasher.feed_int(breaker_health)
	hasher.feed_int(breaker_speed)
	hasher.feed_int(breaker_damage)
	hasher.feed_int(breaker_attack_interval_seconds)
	hasher.feed_int(wall_health)
	hasher.feed_int(wrench_repair_points_per_second)
	hasher.feed_int(wrench_reach_metres)
	hasher.feed_int(player_health)
	hasher.feed_int(player_downed_bleed_out_seconds)
	hasher.feed_int(player_respawn_delay_seconds)
	hasher.feed_int(player_revive_seconds)
	hasher.feed_int(player_revive_reach_metres)
	hasher.feed_text(player_starting_weapon)
	hasher.feed_int(gear_enemy_hit_radius_metres)
	hasher.feed_int(gear_enemy_hit_height_metres)
	hasher.feed_int(gear_view_kick_degrees_per_shot)
	hasher.feed_int(gear_view_kick_recover_seconds)
	hasher.feed_int(enemy_player_bite_reach_metres)

	# Errors are part of the verdict, not of the content, but a set that failed to
	# load must never share a digest with one that loaded empty.
	hasher.feed_int(errors.size())

	return hasher.digest()


# ── Reading the Recipe table ──────────────────────────────────────────────────

func _read_recipes(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: RecipeDefinition = RecipeDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.duration_seconds = table.require_fixed(row, "seconds")

		if definition.duration_seconds <= 0:
			table.report_row(
				row,
				'seconds: a Recipe must take more than no time, got "%s"'
				% table.value(row, "seconds")
			)

		_read_item_list(table, row, "inputs", definition, true)
		_read_item_list(table, row, "outputs", definition, false)

		# Deliberately *not* "must have an output". A generator's Recipe is a fuel and a
		# burn time, and what it produces is Power, which is not an Item — so which of
		# inputs and outputs a Recipe must fill depends on the Role of the Machine that
		# runs it, and `_check_machines_against_recipes` is where that is decided. What is
		# refused here is the only case no Role could rescue: a Recipe that neither
		# consumes nor produces anything is not a transformation.
		if definition.input_count() == 0 and definition.output_count() == 0:
			table.report_row(
				row, "a Recipe that consumes nothing and produces nothing is not a Recipe"
			)

		if definition.id.is_empty():
			continue
		if _recipe_ids.find(definition.id) != -1:
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_recipe_ids.append(definition.id)
		_recipes.append(definition)

	_sort_recipes()


## Reads an `item:count;item:count` list. An empty field is an empty list, which is
## legal for inputs and not for outputs.
func _read_item_list(
	table: CsvTable, row: int, column: String, definition: RecipeDefinition, is_input: bool
) -> void:
	var parsed: Array = _parse_item_list(table, row, column)
	if is_input:
		definition.set_inputs(parsed[0], parsed[1])
	else:
		definition.set_outputs(parsed[0], parsed[1])


## Parses an `item:count;item:count` field into [names, quantities], reporting every
## malformed entry against the row it came from. Shared by a Recipe's inputs and
## outputs and by a Machine's build cost, so the three cannot drift apart on what
## counts as well-formed.
func _parse_item_list(table: CsvTable, row: int, column: String) -> Array:
	var names: PackedStringArray = PackedStringArray()
	var quantities: PackedInt64Array = PackedInt64Array()
	var text: String = table.value(row, column).strip_edges()

	if text.is_empty():
		return [names, quantities]

	for entry: String in text.split(";"):
		var pair: PackedStringArray = entry.split(":")
		if pair.size() != 2:
			table.report_row(
				row, '%s: expected "item:count", got "%s"' % [column, entry.strip_edges()]
			)
			continue

		var item: String = pair[0].strip_edges()
		var quantity_text: String = pair[1].strip_edges()

		if not CsvTable.is_identifier(item):
			table.report_row(row, '%s: "%s" is not a valid Item id' % [column, item])
			continue
		if not quantity_text.is_valid_int() or quantity_text.to_int() <= 0:
			table.report_row(
				row,
				'%s: "%s" must be a positive whole quantity, got "%s"'
				% [column, item, quantity_text]
			)
			continue
		if names.has(item):
			table.report_row(row, '%s: "%s" appears twice' % [column, item])
			continue

		names.append(item)
		quantities.append(quantity_text.to_int())

	return [names, quantities]


## Reads a Machine's `build_cost` column. An empty field is a Machine that is free,
## which is legal and deliberate — the same way an empty `inputs` is a Miner's Recipe.
##
## The Item ids it names are checked against the interned Item set in
## `_check_machines_against_recipes`, because the Items do not exist until the Recipes
## have been read.
func _read_build_cost(table: CsvTable, row: int, definition: MachineDefinition) -> void:
	var parsed: Array = _parse_item_list(table, row, "build_cost")
	definition.set_build_cost(parsed[0], parsed[1])


## Collects every Item the Recipes mention, sorted, and hands each Recipe the
## indices. There is no Item table: naming an Item in a Recipe is how it comes to
## exist, which is one fewer file that can fall out of step.
func _intern_items() -> void:
	for definition: RecipeDefinition in _recipes:
		for item: String in definition.mentioned_items():
			if _item_ids.find(item) == -1:
				_item_ids.append(item)
	_item_ids.sort()

	for definition: RecipeDefinition in _recipes:
		definition.resolve_items(_item_ids)


# ── Reading the Machine table ─────────────────────────────────────────────────

func _read_machines(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: MachineDefinition = MachineDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.footprint_x = table.require_int(row, "footprint_x")
		definition.footprint_z = table.require_int(row, "footprint_z")
		definition.power_draw_kw = table.require_int(row, "power_draw_kw")
		definition.power_supply_kw = table.require_int(row, "power_supply_kw")
		definition.health = table.require_int(row, "health")
		definition.max_depth = table.require_int(row, "max_depth")
		definition.range_tiles = table.require_int(row, "range_tiles")
		definition.damage = table.require_int(row, "damage")
		definition.repair = table.require_int(row, "repair")
		definition.recipe_id = table.require_id(row, "recipe_id")
		_read_build_cost(table, row, definition)

		var role: int = MachineDefinition.parse_role(table.value(row, "role"))
		if role == -1:
			table.report_row(
				row,
				'role: expected one of %s, got "%s"'
				% [", ".join(PackedStringArray(MachineDefinition.ROLE_NAMES)), table.value(row, "role")]
			)
		else:
			definition.role = role

		_check_machine_values(table, row, definition, role)

		if definition.id.is_empty():
			continue
		if _machine_ids.find(definition.id) != -1:
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_machine_ids.append(definition.id)
		_machines.append(definition)

	_sort_machines()


func _check_machine_values(
	table: CsvTable, row: int, definition: MachineDefinition, role: int
) -> void:
	var limit: int = MachineDefinition.MAX_FOOTPRINT_TILES
	if definition.footprint_x < 1 or definition.footprint_x > limit:
		table.report_row(
			row, "footprint_x: must be 1 to %d tiles, got %d" % [limit, definition.footprint_x]
		)
	if definition.footprint_z < 1 or definition.footprint_z > limit:
		table.report_row(
			row, "footprint_z: must be 1 to %d tiles, got %d" % [limit, definition.footprint_z]
		)
	if definition.power_draw_kw < 0:
		table.report_row(row, "power_draw_kw: must not be negative")
	if definition.power_supply_kw < 0:
		table.report_row(row, "power_supply_kw: must not be negative")
	if definition.health < 1:
		table.report_row(row, "health: a Machine with no health is already destroyed")

	if role == MachineDefinition.Role.MINER:
		if definition.max_depth < 1:
			table.report_row(row, "max_depth: a Miner must reach at least Depth 1")
	elif role != -1:
		if definition.max_depth != 0:
			table.report_row(
				row, "max_depth: only a Miner reaches a Depth, so this must be 0"
			)

	# A Turret's reach and its hit are per-Machine numbers rather than tuning, because
	# that is what makes a Cannon Turret a row: it differs from an MG Turret in exactly
	# these two columns and its Recipe. Everything that is not a Turret must leave both
	# at zero, so a stray number cannot sit in the table looking meaningful.
	if role == MachineDefinition.Role.TURRET:
		if definition.range_tiles < 1:
			table.report_row(
				row, "range_tiles: a Turret that reaches nowhere can never fire"
			)
		# A Turret's output is damage or it is repair, **exactly one of the two**. That is
		# the one rule that makes a Repair Pylon a row rather than a fifth Role: it is a
		# Turret in every other respect (GLOSSARY.md), so the only thing the table has to
		# settle is which of the two columns its shot lands in. Neither filled in is a
		# Turret that does nothing at all; both filled in is a Turret with two outputs,
		# and `_fire` would have to pick one.
		if definition.damage < 1 and definition.repair < 1:
			table.report_row(
				row,
				(
					"damage/repair: a Turret's output is damage or repair, so exactly one of"
					+ " these must be set — a Turret that does neither is not a Turret"
				)
			)
		if definition.damage >= 1 and definition.repair >= 1:
			table.report_row(
				row,
				(
					"damage/repair: a Turret's output is damage or repair, never both — a"
					+ " Repair Pylon leaves damage at 0 and an MG Turret leaves repair at 0"
				)
			)
	elif role != -1:
		if definition.range_tiles != 0:
			table.report_row(
				row, "range_tiles: only a Turret has a reach, so this must be 0"
			)
		if definition.damage != 0:
			table.report_row(row, "damage: only a Turret deals damage, so this must be 0")
		if definition.repair != 0:
			table.report_row(row, "repair: only a Repair Pylon repairs, so this must be 0")

	# A Machine either feeds the one Power grid or draws from it. Allowing both would
	# make a generator's own throttle depend on its own output, and the grid stops being
	# a sum of two columns.
	if role == MachineDefinition.Role.GENERATOR:
		if definition.power_supply_kw < 1:
			table.report_row(
				row, "power_supply_kw: a generator that supplies no Power is not a generator"
			)
		if definition.power_draw_kw != 0:
			table.report_row(
				row,
				(
					"power_draw_kw: a generator feeds the grid rather than drawing from it,"
					+ " so this must be 0 — its fuel is its input"
				)
			)
	elif role != -1:
		if definition.power_supply_kw != 0:
			table.report_row(
				row, "power_supply_kw: only a generator supplies Power, so this must be 0"
			)


## The cross-checks between the two tables. Reported against the Machine's row,
## because the Machine is what declares the relationship.
func _check_machines_against_recipes(table: CsvTable) -> void:
	for definition: MachineDefinition in _machines:
		for item: String in definition.build_cost_items:
			if item_index(item) == -1:
				table.report_row(
					definition.source_row,
					(
						'build_cost: "%s" is not an Item — the Items that exist are exactly'
						+ " the ones the Recipes mention"
					) % item
				)

		if definition.recipe_id.is_empty():
			continue

		definition.recipe_index = recipe_index(definition.recipe_id)
		if definition.recipe_index == -1:
			table.report_row(
				definition.source_row,
				'recipe_id: "%s" matches no Recipe' % definition.recipe_id
			)
			continue

		var used: RecipeDefinition = recipe_at(definition.recipe_index)
		if definition.is_miner():
			if used.input_count() > 0:
				table.report_row(
					definition.source_row,
					(
						'"%s" is a Miner, so its Recipe "%s" must have no inputs — a Miner draws'
						+ " what it extracts from the ground it stands on, not from a Belt"
					) % [definition.id, used.id]
				)
		elif used.input_count() == 0:
			table.report_row(
				definition.source_row,
				'"%s" is a %s, so its Recipe "%s" must have at least one input'
				% [
					definition.id,
					MachineDefinition.role_name(definition.role),
					used.id,
				]
			)

		# What a Recipe must *produce* depends on the Role that runs it, which is why it
		# is checked here rather than against the Recipe table on its own. Power is not an
		# Item and never will be — there is no fluid and no steam on a Belt (DESIGN.md) —
		# so a generator's Recipe is a fuel and a burn time and has no output at all. A
		# Turret's Recipe is the same trick in the other direction: its product is damage.
		if definition.produces_no_items():
			if used.output_count() > 0:
				table.report_row(
					definition.source_row,
					(
						'"%s" is a %s, so its Recipe "%s" must have no outputs — what it produces'
						+ " is %s, which is not an Item"
					) % [
						definition.id,
						MachineDefinition.role_name(definition.role),
						used.id,
						"Power" if definition.is_generator() else "damage",
					]
				)
		elif used.output_count() == 0:
			table.report_row(
				definition.source_row,
				'"%s" is a %s, so its Recipe "%s" must produce something'
				% [
					definition.id,
					MachineDefinition.role_name(definition.role),
					used.id,
				]
			)


# ── Reading the Wave table ────────────────────────────────────────────────────

## Reads `content/waves.csv`: the tiers a Wave is composed from.
##
## An empty table is an **error**, not a quiet Run with no Waves. A Map with no Breach
## has no Waves because there is nowhere to enter — that is geography, and a legitimate
## thing for a Map to be. A Wave table with no rows is a content file somebody broke, and
## the symptom would be a Run that is never attacked, which is the hardest kind of bug to
## notice.
func _read_waves(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var entry: WaveEntry = WaveEntry.new()
		entry.source_row = row
		entry.id = table.require_id(row, "id")
		entry.min_heat = table.require_int(row, "min_heat")
		entry.count_per_breach = table.require_int(row, "count_per_breach")
		entry.heat_per_extra = table.require_int(row, "heat_per_extra")
		entry.max_per_breach = table.require_int(row, "max_per_breach")

		var kind_name: String = table.value(row, "enemy_kind")
		entry.enemy_kind = EnemyKind.index_of(kind_name)
		if entry.enemy_kind == -1:
			table.report_row(
				row,
				'enemy_kind: "%s" is not an Enemy the Simulation implements — it is one of %s'
				% [kind_name, EnemyKind.every_name()]
			)

		_check_wave_values(table, row, entry)

		if entry.id.is_empty():
			continue
		if _wave_id_taken(entry.id):
			table.report_row(row, 'id: "%s" is already defined' % entry.id)
			continue

		_waves.append(entry)

	_sort_waves()

	if table.row_count() == 0 and not table.has_errors():
		table.report_row(
			-1,
			(
				"the table has no rows — a Wave composed of nothing would make a Run that is"
				+ " never attacked, which is the hardest kind of bug to notice"
			)
		)


func _check_wave_values(table: CsvTable, row: int, entry: WaveEntry) -> void:
	if entry.min_heat < 0:
		table.report_row(row, "min_heat: Heat never goes below zero, so neither can a threshold")
	if entry.count_per_breach < 1:
		table.report_row(
			row, "count_per_breach: a tier that sends nothing at its own threshold sends nothing"
		)
	if entry.heat_per_extra < 0:
		table.report_row(row, "heat_per_extra: Heat buys more Enemies, never fewer")
	if entry.max_per_breach < entry.count_per_breach:
		table.report_row(
			row,
			(
				"max_per_breach: must be at least count_per_breach (%d), or the ceiling"
				+ " contradicts the opening count"
			) % entry.count_per_breach
		)


# ── Reading the Delivery table ─────────────────────────────────────────────────

## Reads `content/deliveries.csv`: the tiers of progression.
##
## An empty table is an **error**, for the reason an empty Wave table is: the symptom
## would be a Run with no progression at all, and the shipped file existing but having
## been emptied is a file somebody broke rather than a sandbox somebody chose.
##
## Read after the Machines and after the Items are interned, because every goods entry
## has to name an Item some Recipe mentions and every unlock has to name a Machine that
## exists — a tier promising a Machine the content does not define is content somebody
## broke, not a tier that unlocks nothing.
func _read_deliveries(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: DeliveryDefinition = DeliveryDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.min_depth = table.require_int(row, "min_depth")

		var goods: Array = _parse_item_list(table, row, "goods")
		definition.set_goods(goods[0], goods[1])

		definition.unlocks_machines = _read_id_list(table, row, "unlocks_machines")
		definition.unlocks_gear = _read_id_list(table, row, "unlocks_gear")
		definition.unlocks_stratagems = _read_id_list(table, row, "unlocks_stratagems")

		_check_delivery_values(table, row, definition)

		if definition.id.is_empty():
			continue
		if _delivery_id_taken(definition.id):
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_deliveries.append(definition)

	_sort_deliveries()
	_check_delivery_chain(table)

	if table.row_count() == 0 and not table.has_errors():
		table.report_row(
			-1,
			(
				"the table has no rows — a Run with no Delivery tiers has no progression at"
				+ " all, and the Nest is where progression happens"
			)
		)


## Reads a `;`-separated list of identifiers, reporting every malformed entry against the
## row it came from. An empty field is an empty list, which is legal for all three unlock
## columns on their own — `_check_delivery_values` is what refuses a row where all three
## are empty.
func _read_id_list(table: CsvTable, row: int, column: String) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	var text: String = table.value(row, column).strip_edges()
	if text.is_empty():
		return ids
	for entry: String in text.split(";"):
		var id: String = entry.strip_edges()
		if not CsvTable.is_identifier(id):
			table.report_row(row, '%s: "%s" is not a valid id' % [column, id])
			continue
		if ids.has(id):
			table.report_row(row, '%s: "%s" appears twice' % [column, id])
			continue
		ids.append(id)
	return ids


func _check_delivery_values(table: CsvTable, row: int, definition: DeliveryDefinition) -> void:
	if definition.min_depth < 1:
		table.report_row(
			row,
			(
				"min_depth: a tier is gated on how deep the Factory is mining, and the"
				+ " shallowest Depth there is sits at 1"
			)
		)
	if definition.goods_items.is_empty():
		table.report_row(
			row, "goods: a Delivery that costs nothing is not progression — name what the Nest wants"
		)
	for item: String in definition.goods_items:
		if _item_ids.find(item) == -1:
			table.report_row(
				row,
				(
					'goods: "%s" is not an Item any Recipe mentions, so nothing in the Factory'
					+ " could ever make one"
				) % item
			)
	for machine_id: String in definition.unlocks_machines:
		if _machine_ids.find(machine_id) == -1:
			table.report_row(
				row, 'unlocks_machines: "%s" is not a Machine in machines.csv' % machine_id
			)
	for gear_id: String in definition.unlocks_gear:
		if _gear_ids.find(gear_id) == -1:
			table.report_row(
				row, 'unlocks_gear: "%s" is not a piece of Gear in gear.csv' % gear_id
			)
	if (
		definition.unlocks_machines.is_empty()
		and definition.unlocks_gear.is_empty()
		and definition.unlocks_stratagems.is_empty()
	):
		table.report_row(
			row,
			(
				"a tier that unlocks nothing is a bill a player pays for nothing — name a"
				+ " Machine, a Gear component or a Stratagem"
			)
		)


## Checks the chain the sorted tiers form.
##
## Two things can only be seen across rows. A Machine unlocked by two tiers has an
## ambiguous price, and a tier whose Depth is shallower than the one before it could
## never be the thing holding the chain up — the chain is walked in id order and nothing
## is skipped, so a Depth that goes backwards is a file somebody misordered rather than
## a gate that does anything.
func _check_delivery_chain(table: CsvTable) -> void:
	var deepest_so_far: int = 0
	var claimed: PackedStringArray = PackedStringArray()
	var claimed_gear: PackedStringArray = PackedStringArray()
	for definition: DeliveryDefinition in _deliveries:
		if definition.min_depth < deepest_so_far:
			table.report_row(
				definition.source_row,
				(
					"min_depth: %d is shallower than the %d an earlier tier already demands —"
					+ " the chain is walked in id order, so a Depth that goes backwards gates"
					+ " nothing"
				) % [definition.min_depth, deepest_so_far]
			)
		deepest_so_far = maxi(deepest_so_far, definition.min_depth)
		for machine_id: String in definition.unlocks_machines:
			if claimed.has(machine_id):
				table.report_row(
					definition.source_row,
					'unlocks_machines: "%s" is already unlocked by an earlier tier' % machine_id
				)
				continue
			claimed.append(machine_id)
		for gear_id: String in definition.unlocks_gear:
			if claimed_gear.has(gear_id):
				table.report_row(
					definition.source_row,
					'unlocks_gear: "%s" is already unlocked by an earlier tier' % gear_id
				)
				continue
			claimed_gear.append(gear_id)


# ── Reading the Gear table ────────────────────────────────────────────────────

func _read_gear(table: CsvTable) -> void:
	for row: int in range(table.row_count()):
		var definition: GearDefinition = GearDefinition.new()
		definition.source_row = row
		definition.id = table.require_id(row, "id")
		definition.display_name = table.value(row, "display_name")
		definition.kind = table.require_id(row, "kind")
		definition.damage = table.require_int(row, "damage")
		definition.range_metres = table.require_fixed(row, "range_metres")
		definition.spread_degrees = table.require_fixed(row, "spread_degrees")
		definition.seconds_per_shot = table.require_fixed(row, "seconds_per_shot")
		definition.ammunition_item = table.value(row, "ammunition_item").strip_edges()
		definition.ammunition_per_shot = table.require_int(row, "ammunition_per_shot")
		definition.damage_percent = table.require_int(row, "damage_percent")
		definition.range_percent = table.require_int(row, "range_percent")
		definition.spread_percent = table.require_int(row, "spread_percent")
		definition.interval_percent = table.require_int(row, "interval_percent")
		definition.ammunition_percent = table.require_int(row, "ammunition_percent")
		definition.damage_taken_percent = table.require_int(row, "damage_taken_percent")

		_read_gear_attack(table, row, definition)
		_check_gear_values(table, row, definition)

		if definition.id.is_empty():
			continue
		if _gear_ids.find(definition.id) != -1:
			table.report_row(row, 'id: "%s" is already defined' % definition.id)
			continue

		_gear_ids.append(definition.id)
		_gear.append(definition)

	_sort_gear()
	_intern_gear_slots()

	if table.row_count() == 0 and not table.has_errors():
		table.report_row(
			-1,
			(
				"the table has no rows — a Run with no Gear is a Run with nothing to fight"
				+ " with, and first-person combat is a pillar rather than an option"
			)
		)
	elif _weapon_gear_indices.is_empty() and not table.has_errors():
		table.report_row(
			-1, 'the table names no row of kind "%s" — there is no frame to hold' % GearDefinition.WEAPON_KIND
		)


## Reads the `attack` column, which is required on a weapon and must be empty on a
## component. Empty-and-required and present-and-forbidden are two different mistakes and
## each gets its own sentence, because a loader that said only "bad attack" would leave
## the author guessing which.
func _read_gear_attack(table: CsvTable, row: int, definition: GearDefinition) -> void:
	var text: String = table.value(row, "attack").strip_edges()
	var is_weapon: bool = definition.kind == GearDefinition.WEAPON_KIND

	if text.is_empty():
		if is_weapon:
			table.report_row(
				row,
				"attack: a weapon has to reach somehow — expected one of %s"
				% ", ".join(PackedStringArray(GearDefinition.ATTACK_NAMES))
			)
		return

	if not is_weapon:
		table.report_row(
			row,
			(
				'attack: only a weapon frame reaches anything, and this row is a "%s"'
				+ " component — leave it empty"
			) % definition.kind
		)
		return

	var attack: int = GearDefinition.parse_attack(text)
	if attack == -1:
		table.report_row(
			row,
			'attack: expected one of %s, got "%s"'
			% [", ".join(PackedStringArray(GearDefinition.ATTACK_NAMES)), text]
		)
		return
	definition.attack = attack


## The whole of what a well-formed Gear row is, and the half of "there is no Rifle Mk2"
## that a schema can enforce: a weapon states what it is and carries no modifiers, and a
## component carries nothing but modifiers.
func _check_gear_values(table: CsvTable, row: int, definition: GearDefinition) -> void:
	if definition.kind.is_empty():
		return

	if definition.kind == GearDefinition.WEAPON_KIND:
		if definition.damage <= 0:
			table.report_row(row, "damage: a weapon that takes nothing off an Enemy is not a weapon")
		if definition.range_metres <= 0:
			table.report_row(row, "range_metres: a weapon that reaches nowhere hits nothing")
		if definition.spread_degrees < 0:
			table.report_row(row, "spread_degrees: a negative scatter is not tighter aim, it is nonsense")
		if definition.seconds_per_shot <= 0:
			table.report_row(
				row, "seconds_per_shot: a weapon that fires in no time does unbounded damage"
			)
		if definition.changes_anything():
			table.report_row(
				row,
				(
					"a weapon frame carries no modifiers — power comes from the components"
					+ " fitted to it, and a modifier here would be a tier in disguise"
				)
			)
		_check_gear_ammunition(table, row, definition)
		return

	# A component.
	if definition.damage != 0 or definition.range_metres != 0 or definition.spread_degrees != 0:
		table.report_row(
			row,
			(
				"damage, range_metres and spread_degrees belong to the frame — a component"
				+ " says what it does to those, in the percent columns"
			)
		)
	if definition.seconds_per_shot != 0:
		table.report_row(row, "seconds_per_shot: belongs to the frame — use interval_percent")
	if not definition.ammunition_item.is_empty() or definition.ammunition_per_shot != 0:
		table.report_row(
			row,
			(
				"ammunition_item and ammunition_per_shot belong to the frame — use"
				+ " ammunition_percent"
			)
		)
	if not definition.changes_anything():
		table.report_row(
			row,
			(
				"every modifier is 0, so fitting this changes nothing measurable — a"
				+ " component a player earned and cannot feel is a Delivery paid for nothing"
			)
		)


## Checks a weapon's Ammunition against the interned Items. A ranged weapon spends an
## Item out of the player's own pockets, and the Items that exist are exactly the ones
## some Recipe mentions — so a weapon firing `plasma` is content somebody broke rather
## than a weapon that never runs dry.
func _check_gear_ammunition(table: CsvTable, row: int, definition: GearDefinition) -> void:
	if definition.attack == GearDefinition.Attack.RANGED:
		if definition.ammunition_item.is_empty():
			table.report_row(
				row,
				(
					"ammunition_item: a ranged weapon spends something, because defence"
					+ " costing continuous production is the whole keystone loop"
				)
			)
		elif _item_ids.find(definition.ammunition_item) == -1:
			table.report_row(
				row,
				(
					'ammunition_item: "%s" is not an Item any Recipe mentions, so nothing'
					+ " in the Factory could ever make one"
				) % definition.ammunition_item
			)
		if definition.ammunition_per_shot < 1:
			table.report_row(
				row, "ammunition_per_shot: a ranged weapon spends at least one round a shot"
			)
		return

	if not definition.ammunition_item.is_empty():
		table.report_row(
			row, "ammunition_item: a melee weapon spends a player's presence, not an Item"
		)
	if definition.ammunition_per_shot != 0:
		table.report_row(row, "ammunition_per_shot: a melee weapon spends no rounds")


## Collects the slots out of the Gear table's own `kind` column, sorted, and records
## which rows are weapon frames.
##
## There is no slot table, for the reason there is no Item table: writing `barrel` in a
## row is what makes a barrel slot exist. A kind nothing uses therefore cannot exist, and
## a fourth slot is a row.
func _intern_gear_slots() -> void:
	_gear_slot_ids.clear()
	_weapon_gear_indices.clear()
	for index: int in range(_gear.size()):
		var definition: GearDefinition = _gear[index]
		if definition.is_weapon():
			_weapon_gear_indices.append(index)
			continue
		if _gear_slot_ids.find(definition.kind) == -1:
			_gear_slot_ids.append(definition.kind)
	_gear_slot_ids.sort()


func _delivery_id_taken(id: String) -> bool:
	for definition: DeliveryDefinition in _deliveries:
		if definition.id == id:
			return true
	return false


func _wave_id_taken(id: String) -> bool:
	for entry: WaveEntry in _waves:
		if entry.id == id:
			return true
	return false


# ── Reading the tuning file ───────────────────────────────────────────────────

func _read_tuning(tuning: TomlDocument) -> void:
	player_walk_speed = tuning.require_fixed(TUNING_PLAYER_WALK_SPEED)
	player_sprint_multiplier = tuning.require_fixed(TUNING_PLAYER_SPRINT_MULTIPLIER)
	player_walk_acceleration = tuning.require_fixed(TUNING_PLAYER_WALK_ACCELERATION)
	player_look_sensitivity = tuning.require_fixed(TUNING_PLAYER_LOOK_SENSITIVITY)
	player_eye_height = tuning.require_fixed(TUNING_PLAYER_EYE_HEIGHT)
	_read_starting_stock(tuning)
	survey_height = tuning.require_fixed(TUNING_SURVEY_HEIGHT)
	survey_transition_seconds = tuning.require_fixed(TUNING_SURVEY_TRANSITION_SECONDS)
	survey_pitch_degrees = tuning.require_fixed(TUNING_SURVEY_PITCH_DEGREES)
	belt_items_per_second = tuning.require_fixed(TUNING_BELT_ITEMS_PER_SECOND)
	belt_items_per_tile = tuning.require_int(TUNING_BELT_ITEMS_PER_TILE)
	machine_input_buffer_crafts = tuning.require_int(TUNING_MACHINE_INPUT_BUFFER_CRAFTS)
	power_baseline_supply_kw = tuning.require_int(TUNING_POWER_BASELINE_SUPPLY_KW)
	nest_health = tuning.require_int(TUNING_NEST_HEALTH)
	nest_delivery_reach = tuning.require_fixed(TUNING_NEST_DELIVERY_REACH)
	nest_store_capacity_per_item = tuning.require_int(TUNING_NEST_STORE_CAPACITY)
	wave_telegraph_seconds = tuning.require_fixed(TUNING_WAVE_TELEGRAPH_SECONDS)
	wave_spawn_interval_seconds = tuning.require_fixed(TUNING_WAVE_SPAWN_INTERVAL_SECONDS)
	wave_call_early_bounty = tuning.require_int(TUNING_WAVE_CALL_EARLY_BOUNTY)
	heat_per_craft = tuning.require_int(TUNING_HEAT_PER_CRAFT)
	heat_per_craft_per_depth = tuning.require_int(TUNING_HEAT_PER_CRAFT_PER_DEPTH)
	heat_decay_per_minute = tuning.require_int(TUNING_HEAT_DECAY_PER_MINUTE)
	heat_wave_interval_baseline_seconds = tuning.require_fixed(TUNING_HEAT_WAVE_INTERVAL_BASELINE)
	heat_wave_interval_minimum_seconds = tuning.require_fixed(TUNING_HEAT_WAVE_INTERVAL_MINIMUM)
	heat_per_second_sooner = tuning.require_int(TUNING_HEAT_PER_SECOND_SOONER)
	depth_draw_percent_per_depth = tuning.require_int(TUNING_DEPTH_DRAW_PERCENT)
	depth_breach_tier = tuning.require_int(TUNING_DEPTH_BREACH_TIER)
	depth_breach_crafts = tuning.require_int(TUNING_DEPTH_BREACH_CRAFTS)
	depth_breach_offset_tiles = tuning.require_int(TUNING_DEPTH_BREACH_OFFSET_TILES)
	depth_breach_telegraph_seconds = tuning.require_fixed(
		TUNING_DEPTH_BREACH_TELEGRAPH_SECONDS
	)
	crawler_health = tuning.require_int(TUNING_CRAWLER_HEALTH)
	crawler_speed = tuning.require_fixed(TUNING_CRAWLER_SPEED)
	crawler_damage = tuning.require_int(TUNING_CRAWLER_DAMAGE)
	crawler_attack_interval_seconds = tuning.require_fixed(
		TUNING_CRAWLER_ATTACK_INTERVAL_SECONDS
	)
	breaker_health = tuning.require_int(TUNING_BREAKER_HEALTH)
	breaker_speed = tuning.require_fixed(TUNING_BREAKER_SPEED)
	breaker_damage = tuning.require_int(TUNING_BREAKER_DAMAGE)
	breaker_attack_interval_seconds = tuning.require_fixed(
		TUNING_BREAKER_ATTACK_INTERVAL_SECONDS
	)
	siege_hulk_health = tuning.require_int(TUNING_SIEGE_HULK_HEALTH)
	siege_hulk_speed = tuning.require_fixed(TUNING_SIEGE_HULK_SPEED)
	siege_hulk_range_metres = tuning.require_fixed(TUNING_SIEGE_HULK_RANGE)
	siege_hulk_shell_damage = tuning.require_int(TUNING_SIEGE_HULK_SHELL_DAMAGE)
	siege_hulk_shell_blast_radius_metres = tuning.require_fixed(TUNING_SIEGE_HULK_BLAST_RADIUS)
	siege_hulk_shell_interval_seconds = tuning.require_fixed(TUNING_SIEGE_HULK_SHELL_INTERVAL)
	siege_hulk_shell_flight_seconds = tuning.require_fixed(TUNING_SIEGE_HULK_SHELL_FLIGHT)
	siege_hulk_stomp_damage = tuning.require_int(TUNING_SIEGE_HULK_STOMP_DAMAGE)
	siege_hulk_frontal_armour_percent = tuning.require_int(TUNING_SIEGE_HULK_ARMOUR_PERCENT)
	siege_hulk_hit_radius_metres = tuning.require_fixed(TUNING_SIEGE_HULK_HIT_RADIUS)
	siege_hulk_hit_height_metres = tuning.require_fixed(TUNING_SIEGE_HULK_HIT_HEIGHT)
	hive_health = tuning.require_int(TUNING_HIVE_HEALTH)
	hive_heat_shadow_per_minute = tuning.require_int(TUNING_HIVE_HEAT_SHADOW)
	hive_hit_radius_metres = tuning.require_fixed(TUNING_HIVE_HIT_RADIUS)
	hive_hit_height_metres = tuning.require_fixed(TUNING_HIVE_HIT_HEIGHT)
	wall_health = tuning.require_int(TUNING_WALL_HEALTH)
	wrench_repair_points_per_second = tuning.require_int(
		TUNING_WRENCH_REPAIR_POINTS_PER_SECOND
	)
	wrench_reach_metres = tuning.require_fixed(TUNING_WRENCH_REACH_METRES)
	player_health = tuning.require_int(TUNING_PLAYER_HEALTH)
	player_downed_bleed_out_seconds = tuning.require_fixed(TUNING_PLAYER_DOWNED_SECONDS)
	player_respawn_delay_seconds = tuning.require_fixed(TUNING_PLAYER_RESPAWN_SECONDS)
	player_revive_seconds = tuning.require_fixed(TUNING_PLAYER_REVIVE_SECONDS)
	player_revive_reach_metres = tuning.require_fixed(TUNING_PLAYER_REVIVE_REACH)
	player_starting_weapon = tuning.require_string(TUNING_PLAYER_STARTING_WEAPON).strip_edges()
	gear_enemy_hit_radius_metres = tuning.require_fixed(TUNING_GEAR_ENEMY_HIT_RADIUS)
	gear_enemy_hit_height_metres = tuning.require_fixed(TUNING_GEAR_ENEMY_HIT_HEIGHT)
	gear_view_kick_degrees_per_shot = tuning.require_fixed(TUNING_GEAR_VIEW_KICK_DEGREES)
	gear_view_kick_recover_seconds = tuning.require_fixed(TUNING_GEAR_VIEW_KICK_RECOVER_SECONDS)
	enemy_player_bite_reach_metres = tuning.require_fixed(TUNING_ENEMY_BITE_REACH)

	# A rate or a capacity of zero is not a slow Belt, it is a Belt that cannot work.
	# Refused by name rather than accepted and puzzled over later.
	if not tuning.has_errors():
		if player_sprint_multiplier < Fixed.ONE:
			errors.append("%s must be at least 1: sprinting is not slower than walking" % TUNING_PLAYER_SPRINT_MULTIPLIER)
		if player_walk_speed <= 0:
			_report_tuning(tuning, TUNING_PLAYER_WALK_SPEED, "a player who cannot walk is stuck")
		if player_walk_acceleration <= 0:
			_report_tuning(
				tuning,
				TUNING_PLAYER_WALK_ACCELERATION,
				"a player who cannot accelerate never starts walking"
			)
		if player_look_sensitivity <= 0:
			_report_tuning(
				tuning, TUNING_PLAYER_LOOK_SENSITIVITY, "a player who cannot turn cannot aim"
			)
		if player_eye_height <= 0:
			_report_tuning(tuning, TUNING_PLAYER_EYE_HEIGHT, "a player has to see from somewhere")
		if survey_height <= player_eye_height:
			_report_tuning(
				tuning,
				TUNING_SURVEY_HEIGHT,
				"Survey View has to be above eye level or it surveys nothing"
			)
		if survey_transition_seconds < 0:
			_report_tuning(
				tuning, TUNING_SURVEY_TRANSITION_SECONDS, "a transition cannot take negative time"
			)
		if survey_pitch_degrees < 0 or survey_pitch_degrees > Fixed.from_int(90):
			_report_tuning(
				tuning, TUNING_SURVEY_PITCH_DEGREES, "must be 0 to 90 degrees below level"
			)
		if belt_items_per_second <= 0:
			_report_tuning(tuning, TUNING_BELT_ITEMS_PER_SECOND, "must be more than nothing")
		if belt_items_per_tile < 1:
			_report_tuning(tuning, TUNING_BELT_ITEMS_PER_TILE, "must be at least one Item")
		if machine_input_buffer_crafts < 1:
			_report_tuning(
				tuning, TUNING_MACHINE_INPUT_BUFFER_CRAFTS, "must be at least one craft"
			)
		if power_baseline_supply_kw < 0:
			_report_tuning(
				tuning, TUNING_POWER_BASELINE_SUPPLY_KW, "a grid cannot supply less than nothing"
			)
		if nest_delivery_reach <= 0:
			_report_tuning(
				tuning,
				TUNING_NEST_DELIVERY_REACH,
				"a reach of nothing is a Delivery nobody can hand over"
			)
		if nest_store_capacity_per_item < 1:
			_report_tuning(
				tuning,
				TUNING_NEST_STORE_CAPACITY,
				"a store that holds nothing is a Nest nothing can be banked at"
			)
		if nest_health <= 0:
			_report_tuning(
				tuning, TUNING_NEST_HEALTH, "a Nest that starts destroyed ends the Run at tick 0"
			)
		if wave_telegraph_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_WAVE_TELEGRAPH_SECONDS,
				"a Wave with no Telegraph is the ambush the core loop must never be"
			)
		if wave_call_early_bounty < 0:
			_report_tuning(
				tuning,
				TUNING_WAVE_CALL_EARLY_BOUNTY,
				"a reward that takes materials away is a penalty"
			)
		if heat_per_craft < 0:
			_report_tuning(
				tuning, TUNING_HEAT_PER_CRAFT, "producing cannot make a Factory quieter"
			)
		if heat_per_craft_per_depth < 0:
			_report_tuning(
				tuning, TUNING_HEAT_PER_CRAFT_PER_DEPTH, "deeper ore is louder, never quieter"
			)
		if heat_decay_per_minute < 0:
			_report_tuning(
				tuning, TUNING_HEAT_DECAY_PER_MINUTE, "Heat cannot bleed upward on its own"
			)
		if heat_wave_interval_baseline_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_HEAT_WAVE_INTERVAL_BASELINE,
				"Waves with no gap are one endless Wave"
			)
		if heat_wave_interval_minimum_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_HEAT_WAVE_INTERVAL_MINIMUM,
				"Waves with no gap are one endless Wave"
			)
		if heat_wave_interval_minimum_seconds > heat_wave_interval_baseline_seconds:
			_report_tuning(
				tuning,
				TUNING_HEAT_WAVE_INTERVAL_MINIMUM,
				(
					"must not exceed %s — Heat shortens the interval, so a minimum above the"
					+ " baseline would make a hot Factory hunted later"
				) % TUNING_HEAT_WAVE_INTERVAL_BASELINE
			)
		if heat_wave_interval_minimum_seconds < wave_telegraph_seconds:
			_report_tuning(
				tuning,
				TUNING_HEAT_WAVE_INTERVAL_MINIMUM,
				(
					"must be at least %s — a gap shorter than the Telegraph would leave no"
					+ " quiet tick for a player to read the warning in"
				) % TUNING_WAVE_TELEGRAPH_SECONDS
			)
		if heat_per_second_sooner <= 0:
			_report_tuning(
				tuning,
				TUNING_HEAT_PER_SECOND_SOONER,
				"Heat that buys no time is Heat that does not drive the schedule"
			)
		if wave_spawn_interval_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_WAVE_SPAWN_INTERVAL_SECONDS,
				"a whole Wave arriving in no time is a stack of Enemies on one tile"
			)
		if depth_draw_percent_per_depth < 0:
			_report_tuning(
				tuning,
				TUNING_DEPTH_DRAW_PERCENT,
				"deeper ore costs more Power, never less"
			)
		if depth_breach_tier < 2:
			_report_tuning(
				tuning,
				TUNING_DEPTH_BREACH_TIER,
				(
					"must be at least 2 — Depth 1 is the ore a Run opens on, and a Map that"
					+ " punishes the opening Factory teaches nothing"
				)
			)
		if depth_breach_crafts < 1:
			_report_tuning(
				tuning,
				TUNING_DEPTH_BREACH_CRAFTS,
				"a Breach opened by no extraction at all would open before the Miner runs"
			)
		if depth_breach_offset_tiles < 1:
			_report_tuning(
				tuning,
				TUNING_DEPTH_BREACH_OFFSET_TILES,
				"a Breach on the mine itself is a Breach underneath the Miner"
			)
		if depth_breach_telegraph_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_DEPTH_BREACH_TELEGRAPH_SECONDS,
				"a Breach that opens unannounced is the ambush the Telegraph exists to prevent"
			)
		if crawler_health <= 0:
			_report_tuning(tuning, TUNING_CRAWLER_HEALTH, "an Enemy has to be able to take a hit")
		if crawler_speed <= 0:
			_report_tuning(tuning, TUNING_CRAWLER_SPEED, "a Crawler that cannot move never arrives")
		if crawler_damage <= 0:
			_report_tuning(tuning, TUNING_CRAWLER_DAMAGE, "an Enemy that does no damage is scenery")
		if crawler_attack_interval_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_CRAWLER_ATTACK_INTERVAL_SECONDS,
				"a bite that takes no time does unbounded damage"
			)
		if breaker_health <= 0:
			_report_tuning(tuning, TUNING_BREAKER_HEALTH, "an Enemy has to be able to take a hit")
		if breaker_speed <= 0:
			_report_tuning(
				tuning, TUNING_BREAKER_SPEED, "a Breaker that cannot move never reaches a Machine"
			)
		if breaker_damage <= 0:
			_report_tuning(tuning, TUNING_BREAKER_DAMAGE, "an Enemy that does no damage is scenery")
		if breaker_attack_interval_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_BREAKER_ATTACK_INTERVAL_SECONDS,
				"a bite that takes no time does unbounded damage"
			)
		if siege_hulk_health <= 0:
			_report_tuning(
				tuning, TUNING_SIEGE_HULK_HEALTH, "an Enemy has to be able to take a hit"
			)
		if siege_hulk_speed <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_SPEED,
				"a Siege Hulk that cannot move never reaches its stand-off"
			)
		if siege_hulk_shell_damage <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_SHELL_DAMAGE,
				"a bombardment that does no damage is weather"
			)
		if siege_hulk_shell_blast_radius_metres <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_BLAST_RADIUS,
				"a shell with no blast cannot land on anything"
			)
		if siege_hulk_shell_interval_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_SHELL_INTERVAL,
				"a shell that takes no time does unbounded damage"
			)
		if siege_hulk_shell_flight_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_SHELL_FLIGHT,
				"a shell that lands the tick it was fired is the ambush the Telegraph forbids"
			)
		if siege_hulk_stomp_damage <= 0:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_STOMP_DAMAGE,
				"a Siege Hulk a player can stand on top of for nothing is not a boss"
			)
		if siege_hulk_frontal_armour_percent < 0 or siege_hulk_frontal_armour_percent >= 100:
			_report_tuning(
				tuning,
				TUNING_SIEGE_HULK_ARMOUR_PERCENT,
				"armour is a percentage taken off a hit: 100 would make the front invulnerable"
			)
		if siege_hulk_hit_radius_metres <= 0:
			_report_tuning(
				tuning, TUNING_SIEGE_HULK_HIT_RADIUS, "an Enemy with no width cannot be hit"
			)
		if siege_hulk_hit_height_metres <= 0:
			_report_tuning(
				tuning, TUNING_SIEGE_HULK_HIT_HEIGHT, "an Enemy with no height cannot be aimed at"
			)
		if hive_health <= 0:
			_report_tuning(
				tuning,
				TUNING_HIVE_HEALTH,
				"a Hive that starts destroyed adds no pressure there is any point removing"
			)
		if hive_heat_shadow_per_minute < 0:
			_report_tuning(
				tuning, TUNING_HIVE_HEAT_SHADOW, "a Hive cannot help the Nest hide"
			)
		if hive_hit_radius_metres <= 0:
			_report_tuning(tuning, TUNING_HIVE_HIT_RADIUS, "a Hive with no width cannot be hit")
		if hive_hit_height_metres <= 0:
			_report_tuning(
				tuning, TUNING_HIVE_HIT_HEIGHT, "a Hive with no height cannot be aimed at"
			)
		_check_siege_hulk_outranges_every_turret(tuning)
		if wall_health <= 0:
			_report_tuning(
				tuning, TUNING_WALL_HEALTH, "a Wall that starts destroyed cannot be built"
			)
		if wrench_repair_points_per_second <= 0:
			_report_tuning(
				tuning,
				TUNING_WRENCH_REPAIR_POINTS_PER_SECOND,
				"a wrench that mends nothing is not a repair tool"
			)
		if wrench_reach_metres <= 0:
			_report_tuning(
				tuning,
				TUNING_WRENCH_REACH_METRES,
				"a wrench a player cannot reach anything with mends nothing"
			)
		if player_health <= 0:
			_report_tuning(
				tuning, TUNING_PLAYER_HEALTH, "a player who starts at zero is Downed on tick 0"
			)
		if player_downed_bleed_out_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_PLAYER_DOWNED_SECONDS,
				(
					"a Downed player who dies instantly gives a teammate no window at all,"
					+ " and the window is the whole of what Downed is"
				)
			)
		if player_respawn_delay_seconds < 0:
			_report_tuning(
				tuning, TUNING_PLAYER_RESPAWN_SECONDS, "a delay cannot be negative time"
			)
		if player_revive_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_PLAYER_REVIVE_SECONDS,
				"an instant revive costs the rescuer nothing, and what it should cost is exposure"
			)
		if player_revive_reach_metres <= 0:
			_report_tuning(
				tuning, TUNING_PLAYER_REVIVE_REACH, "a revive is done standing over somebody"
			)
		if gear_enemy_hit_radius_metres <= 0:
			_report_tuning(
				tuning,
				TUNING_GEAR_ENEMY_HIT_RADIUS,
				"an Enemy with no width is a point no shot can ever meet"
			)
		if gear_enemy_hit_height_metres <= 0:
			_report_tuning(
				tuning, TUNING_GEAR_ENEMY_HIT_HEIGHT, "an Enemy with no height cannot be aimed at"
			)
		if gear_view_kick_degrees_per_shot < 0:
			_report_tuning(
				tuning,
				TUNING_GEAR_VIEW_KICK_DEGREES,
				"recoil pushes the view up, never down — 0 is a weapon that does not kick"
			)
		if gear_view_kick_recover_seconds <= 0:
			_report_tuning(
				tuning,
				TUNING_GEAR_VIEW_KICK_RECOVER_SECONDS,
				"a kick that never comes back down walks the view off the top of the Map"
			)
		if enemy_player_bite_reach_metres <= 0:
			_report_tuning(
				tuning,
				TUNING_ENEMY_BITE_REACH,
				"an Enemy that cannot reach a player is an Enemy a player cannot lose to"
			)
		_check_starting_weapon(tuning)

	# Checked after every read, so this names exactly the keys nothing asked for.
	for key: String in tuning.unread_keys():
		warnings.append(
			"%s:%d: nothing in the Simulation reads \"%s\""
			% [tuning.source_path, tuning.line_of(key), key]
		)


## Records a tuning value that parsed but makes no sense, naming its key and line.
## Refuses a definition set in which a Turret could reach a Siege Hulk where it stands.
##
## **This is the acceptance criterion "it cannot be defeated by Turrets alone" written as a
## content check.** A Hulk holds at `siege_hulk.range_metres` from the nearest thing it can
## shell, so a Turret whose `range_tiles` covered that distance would quietly turn the one
## threat the Factory cannot answer into one it can — and that is an edit somebody would make
## by adding a Cannon Turret row without ever realising what it cost.
##
## A cross-table check, which this file is already arranged for: tuning is read **last**, after
## `machines.csv`, for exactly this kind of question. The comparison is in metres on both
## sides, with the tile count converted rather than the reach rounded, and it must be strictly
## greater — a Hulk exactly on a Turret's boundary is a Hulk whose fate a rounding rule
## decides.
func _check_siege_hulk_outranges_every_turret(tuning: TomlDocument) -> void:
	var tile: int = WorldGrid.tile_size_metres()
	for index: int in range(machine_count()):
		var definition: MachineDefinition = machine_at(index)
		if definition == null or not definition.is_turret():
			continue
		if siege_hulk_range_metres > definition.range_tiles * tile:
			continue
		_report_tuning(
			tuning,
			TUNING_SIEGE_HULK_RANGE,
			(
				"%s reaches %d tiles, which covers where a Siege Hulk stands — a Siege Hulk"
				% [definition.id, definition.range_tiles]
				+ " bombards from beyond Turret range and must not be answerable by defences"
			)
		)
		return


## Reads `player.starting_stock`: what a Run opens with, as an `item:count` list.
##
## A quoted string rather than a key per Item, because naming an Item in `sim/` is exactly
## what the project does not do — the set of Items is whatever the Recipes mention, and a
## tuning key called `starting_iron_plate` would be a second Item table. The list is
## checked against the interned Items, so a typo is an error naming the key rather than a
## Run that silently opens empty-handed.
func _read_starting_stock(tuning: TomlDocument) -> void:
	var text: String = tuning.require_string(TUNING_PLAYER_STARTING_STOCK).strip_edges()
	if text.is_empty():
		return
	for entry: String in text.split(";"):
		var pair: PackedStringArray = entry.split(":")
		if pair.size() != 2:
			_report_tuning(
				tuning,
				TUNING_PLAYER_STARTING_STOCK,
				'expected "item:count", got "%s"' % entry.strip_edges()
			)
			continue
		var item: String = pair[0].strip_edges()
		var count_text: String = pair[1].strip_edges()
		if _item_ids.find(item) == -1:
			_report_tuning(
				tuning,
				TUNING_PLAYER_STARTING_STOCK,
				'"%s" is not an Item any Recipe mentions' % item
			)
			continue
		if not count_text.is_valid_int() or count_text.to_int() <= 0:
			_report_tuning(
				tuning,
				TUNING_PLAYER_STARTING_STOCK,
				'"%s" must be a positive whole quantity, got "%s"' % [item, count_text]
			)
			continue
		if player_starting_stock_items.has(item):
			_report_tuning(
				tuning, TUNING_PLAYER_STARTING_STOCK, '"%s" appears twice' % item
			)
			continue
		# Inserted in sorted order, not file order, so what a Run opens holding is a
		# property of the content rather than of how somebody typed the list — the same
		# rule the Machines, the Recipes and the Items obey.
		var slot: int = player_starting_stock_items.bsearch(item)
		player_starting_stock_items.insert(slot, item)
		player_starting_stock_counts.insert(slot, count_text.to_int())


## Checks `player.starting_weapon` against the Gear table.
##
## Two separate mistakes with two separate sentences: an id no row answers to, and an id
## that names a *component* rather than a frame. The second is the likelier one and the
## more confusing to debug, because the row exists.
func _check_starting_weapon(tuning: TomlDocument) -> void:
	if player_starting_weapon.is_empty():
		_report_tuning(
			tuning,
			TUNING_PLAYER_STARTING_WEAPON,
			"a Run has to open holding something — name a weapon row in gear.csv"
		)
		return
	var definition: GearDefinition = gear(player_starting_weapon)
	if definition == null:
		_report_tuning(
			tuning,
			TUNING_PLAYER_STARTING_WEAPON,
			'"%s" is not a row in gear.csv' % player_starting_weapon
		)
		return
	if not definition.is_weapon():
		_report_tuning(
			tuning,
			TUNING_PLAYER_STARTING_WEAPON,
			(
				'"%s" is a "%s" component rather than a weapon frame — a component is fitted'
				+ " to a weapon, not held instead of one"
			) % [player_starting_weapon, definition.kind]
		)
		return
	if locks_gear(player_starting_weapon):
		_report_tuning(
			tuning,
			TUNING_PLAYER_STARTING_WEAPON,
			(
				'"%s" is unlocked by a Delivery tier, so a Run cannot open holding it —'
				+ " the Gear a Run opens with is exactly the Gear no tier names"
			) % player_starting_weapon
		)


func _report_tuning(tuning: TomlDocument, key: String, detail: String) -> void:
	errors.append("%s:%d: %s: %s" % [tuning.source_path, tuning.line_of(key), key, detail])


# ── Ordering and discarding ───────────────────────────────────────────────────
# Sorted by id so the index space is a function of the content and not of the order
# someone happened to type the rows in. Ids are unique by the time these run, so the
# order is total and does not depend on the sort being stable.

func _sort_machines() -> void:
	_machines.sort_custom(
		func(a: MachineDefinition, b: MachineDefinition) -> bool: return a.id < b.id
	)
	_machine_ids.clear()
	for definition: MachineDefinition in _machines:
		_machine_ids.append(definition.id)


func _sort_recipes() -> void:
	_recipes.sort_custom(
		func(a: RecipeDefinition, b: RecipeDefinition) -> bool: return a.id < b.id
	)
	_recipe_ids.clear()
	for definition: RecipeDefinition in _recipes:
		_recipe_ids.append(definition.id)


func _sort_gear() -> void:
	_gear.sort_custom(func(a: GearDefinition, b: GearDefinition) -> bool: return a.id < b.id)
	_gear_ids.clear()
	for definition: GearDefinition in _gear:
		_gear_ids.append(definition.id)


func _sort_waves() -> void:
	_waves.sort_custom(func(a: WaveEntry, b: WaveEntry) -> bool: return a.id < b.id)


func _sort_deliveries() -> void:
	_deliveries.sort_custom(
		func(a: DeliveryDefinition, b: DeliveryDefinition) -> bool: return a.id < b.id
	)


## Throws away everything a broken load managed to read. Half a definition set is
## more dangerous than none, because it looks usable.
func _discard_content() -> void:
	_machines.clear()
	_machine_ids.clear()
	_recipes.clear()
	_recipe_ids.clear()
	_item_ids.clear()
	_waves.clear()
	_deliveries.clear()
	_gear.clear()
	_gear_ids.clear()
	_gear_slot_ids.clear()
	_weapon_gear_indices.clear()
	player_walk_speed = 0
	player_sprint_multiplier = 0
	player_walk_acceleration = 0
	player_look_sensitivity = 0
	player_eye_height = 0
	player_starting_stock_items.clear()
	player_starting_stock_counts.clear()
	survey_height = 0
	survey_transition_seconds = 0
	survey_pitch_degrees = 0
	belt_items_per_second = 0
	belt_items_per_tile = 0
	machine_input_buffer_crafts = 0
	power_baseline_supply_kw = 0
	nest_health = 0
	nest_delivery_reach = 0
	nest_store_capacity_per_item = 0
	wave_telegraph_seconds = 0
	wave_spawn_interval_seconds = 0
	wave_call_early_bounty = 0
	heat_per_craft = 0
	heat_per_craft_per_depth = 0
	heat_decay_per_minute = 0
	heat_wave_interval_baseline_seconds = 0
	heat_wave_interval_minimum_seconds = 0
	heat_per_second_sooner = 0
	depth_draw_percent_per_depth = 0
	depth_breach_tier = 0
	depth_breach_crafts = 0
	depth_breach_offset_tiles = 0
	depth_breach_telegraph_seconds = 0
	crawler_health = 0
	crawler_speed = 0
	crawler_damage = 0
	crawler_attack_interval_seconds = 0
	siege_hulk_health = 0
	siege_hulk_speed = 0
	siege_hulk_range_metres = 0
	siege_hulk_shell_damage = 0
	siege_hulk_shell_blast_radius_metres = 0
	siege_hulk_shell_interval_seconds = 0
	siege_hulk_shell_flight_seconds = 0
	siege_hulk_stomp_damage = 0
	siege_hulk_frontal_armour_percent = 0
	siege_hulk_hit_radius_metres = 0
	siege_hulk_hit_height_metres = 0
	hive_health = 0
	hive_heat_shadow_per_minute = 0
	hive_hit_radius_metres = 0
	hive_hit_height_metres = 0
	breaker_health = 0
	breaker_speed = 0
	breaker_damage = 0
	breaker_attack_interval_seconds = 0
	wall_health = 0
	wrench_repair_points_per_second = 0
	wrench_reach_metres = 0
	player_health = 0
	player_downed_bleed_out_seconds = 0
	player_respawn_delay_seconds = 0
	player_revive_seconds = 0
	player_revive_reach_metres = 0
	player_starting_weapon = ""
	gear_enemy_hit_radius_metres = 0
	gear_enemy_hit_height_metres = 0
	gear_view_kick_degrees_per_shot = 0
	gear_view_kick_recover_seconds = 0
	enemy_player_bite_reach_metres = 0


static func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		# `load_from_directory` checks existence first, so this is the rarer case of a
		# file that exists and cannot be read. The parser will report it as an empty
		# table, naming the path.
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
