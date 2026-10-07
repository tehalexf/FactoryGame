## One Machine, as defined by one row of `content/machines.csv`.
##
## A Machine is a discrete building that consumes inputs and produces outputs per a
## Recipe, and is mortal (GLOSSARY.md). This holds what the file says about it and
## nothing the Simulation decides at runtime — no inventory, no health remaining,
## no position. Those belong to the Machine *instances* a later ticket adds; this
## is the definition they are built from, shared by every instance and never
## mutated.
##
## Immutable once loaded. Hot-reload replaces the whole definition set rather than
## editing one of these in place, which is what lets a definition be handed out by
## reference without a copy.
class_name MachineDefinition
extends RefCounted

## What a Machine does with its Recipe.
enum Role {
	## Extracts a Resource from the Node it stands on. Its Recipe has no inputs,
	## because the Node is the input.
	MINER = 0,
	## Consumes Belt-fed inputs. Its Recipe has at least one.
	CRAFTER = 1,
	## Burns a Belt-fed fuel and supplies the one Power grid. Its Recipe is the fuel
	## and the burn time; Power is not an Item, so the Recipe produces nothing.
	##
	## All three generator classes GLOSSARY.md names — Steam, Electric, Exotic — are
	## this one Role. They differ in their fuel chain and in how they fail, which are
	## a Recipe and a row in a table, not a second simulation.
	GENERATOR = 2,
	## Consumes Belt-fed Ammunition and its output is **damage** rather than an Item
	## (GLOSSARY.md). Its Recipe is the round it fires and the time between shots, so a
	## Turret holding no Ammunition does not fire — which is the whole of the keystone
	## loop: defence costs continuous production, never a one-time build.
	##
	## Not a separate combat subsystem. The same Recipe, inventory, Belt and Power rules
	## apply, and a Recipe that produces no Item is exactly the trick `GENERATOR` already
	## plays in the other direction. All three Turret classes DESIGN.md names — MG,
	## Cannon, Repair Pylon — are this one Role, differing in `range_tiles`, `damage`,
	## `repair` and their Recipe, which are a row in a table and not a second simulation.
	## A Repair Pylon is that same trick a third time: its output is repair, which is not
	## an Item either.
	TURRET = 3,
}

## Spelling of each Role in the file, indexed by the enum value.
const ROLE_NAMES: Array = ["miner", "crafter", "generator", "turret"]

## Largest footprint DESIGN.md allows, in tiles on the 2 m grid.
const MAX_FOOTPRINT_TILES: int = 4

var id: String = ""
var display_name: String = ""
var role: Role = Role.CRAFTER

## Tiles occupied on the 2 m grid.
var footprint_x: int = 0
var footprint_z: int = 0

## Demand on the one Power grid while running.
var power_draw_kw: int = 0

## What this Machine adds to the one Power grid while it is burning its fuel. 0 for
## anything that is not a generator — a Machine either feeds the grid or draws from
## it, never both, which is what keeps the grid a sum of two columns rather than a
## network of flows.
var power_supply_kw: int = 0

## Hit points before destruction.
var health: int = 0

## Deepest Node tier this Machine reaches. 0 for anything that is not a Miner.
var max_depth: int = 0

## How far a Turret reaches, in whole tiles on the 2 m grid, measured from the centre
## of its footprint. 0 for anything that is not a Turret.
##
## Tiles rather than metres because that is the unit a player lays a Factory out in, and
## because the Simulation converts it once, at the one place it is compared — a second
## copy in metres is a second number to disagree with this one.
var range_tiles: int = 0

## What one shot takes off an Enemy, in whole hit points. 0 for anything that is not a
## Turret.
##
## Whole points, like a Crawler's health and a Crawler's bite: damage is counted in them
## and never scaled, so there is no rounding rule anywhere in combat.
var damage: int = 0

## What one pulse puts back onto a damaged Machine or Wall, in whole hit points. 0 for
## anything that is not a Repair Pylon.
##
## The same column `damage` is, in the same units, because a Repair Pylon is a Turret
## whose output is repair rather than damage (GLOSSARY.md) and not a second kind of
## Machine. A Turret carries exactly one of the two: its product is damage or it is
## repair, never both and never neither, which is what `heals()` answers and what
## `Definitions` refuses a row for.
var repair: int = 0

## What this Machine costs to build, as parallel arrays of Item id and count, sorted
## by id so the order is a property of the content rather than of how the row was
## typed. Empty for a Machine that is free.
##
## Demolishing returns this in full. That is what makes iterating on a layout cheap,
## which is the whole point of a Build Gun that can take things back apart.
var build_cost_items: PackedStringArray = PackedStringArray()
var build_cost_counts: PackedInt64Array = PackedInt64Array()

## The Recipe this Machine runs, by id and — once the set is loaded — by index.
var recipe_id: String = ""
var recipe_index: int = -1

## Which row of the file this came from. Reporting only, and deliberately not
## hashed: moving a row must not change the Simulation.
var source_row: int = -1


## The spelling of a Role in the file, or "" for an unknown value.
static func role_name(value: Role) -> String:
	if value < 0 or value >= ROLE_NAMES.size():
		return ""
	return ROLE_NAMES[value]


## Parses a Role, or -1 when the text names no Role.
static func parse_role(text: String) -> int:
	return ROLE_NAMES.find(text)


## Sets the build cost, sorting by Item id so two rows that list the same cost in a
## different order are the same definition.
func set_build_cost(names: PackedStringArray, quantities: PackedInt64Array) -> void:
	var order: Array = []
	for index: int in range(names.size()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return names[a] < names[b])

	build_cost_items = PackedStringArray()
	build_cost_counts = PackedInt64Array()
	for index: int in order:
		build_cost_items.append(names[index])
		build_cost_counts.append(quantities[index])


## How many of an Item this Machine costs to build. 0 for an Item it does not need.
func build_cost_of(item_id: String) -> int:
	var at: int = build_cost_items.find(item_id)
	if at == -1:
		return 0
	return build_cost_counts[at]


func is_miner() -> bool:
	return role == Role.MINER


func is_generator() -> bool:
	return role == Role.GENERATOR


func is_turret() -> bool:
	return role == Role.TURRET


## Whether this Machine's shot mends rather than hurts — a Repair Pylon.
##
## A predicate on the row rather than a fifth Role, because GLOSSARY.md calls a Repair
## Pylon a Turret-class Machine and `Definitions` already guarantees a Turret carries
## exactly one of `damage` and `repair`. Everything else about it — the Recipe it spends,
## the input buffer it fills from a Belt, the Power it draws, the reach it measures from
## its footprint centre — is a Turret's, unchanged.
func heals() -> bool:
	return is_turret() and repair > 0


## Whether this Machine's Recipe is forbidden an output, because what the Machine
## produces is not an Item. True of a generator, whose product is Power, and of a Turret,
## whose product is damage. One predicate rather than two tests at every call site, so
## the next role whose output is not an Item joins the rule rather than forgetting it.
func produces_no_items() -> bool:
	return is_generator() or is_turret()


## Feeds this definition into a hash, in a fixed order. `recipe_id` goes in rather
## than `recipe_index` so the digest describes what the file says, not how the
## loader happened to number things.
func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_text(display_name)
	hasher.feed_int(role)
	hasher.feed_int(footprint_x)
	hasher.feed_int(footprint_z)
	hasher.feed_int(power_draw_kw)
	hasher.feed_int(power_supply_kw)
	hasher.feed_int(health)
	hasher.feed_int(max_depth)
	hasher.feed_int(range_tiles)
	hasher.feed_int(damage)
	hasher.feed_int(repair)
	hasher.feed_text(recipe_id)
	hasher.feed_int(build_cost_items.size())
	for index: int in range(build_cost_items.size()):
		hasher.feed_text(build_cost_items[index])
		hasher.feed_int(build_cost_counts[index])
