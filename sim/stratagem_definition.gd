## One Stratagem, as defined by one row of `content/stratagems.csv`.
##
## A Stratagem is a player-called intervention from outside the Map, drawn from a
## stockpile of Charges (GLOSSARY.md). Factory output is therefore combat power in the
## most literal arithmetic the project has: a Silo assembles Charges from Belt-fed
## inputs, and **more production means more artillery, full stop** (docs/DESIGN.md).
##
## **A fourth Stratagem is a row here.** Nothing in `sim/` names one, exactly as nothing
## names a Machine, a Recipe, a weapon or a Gear slot. What `sim/` knows is the three
## *effects* a row may choose between — shelling ground, dropping goods, dropping a
## Turret — and each effect reads only the columns that belong to it, which is what makes
## a second Barrage with a wider radius and a longer channel a row rather than a code
## change.
##
## **A Charge is a multiplier, not a second Stratagem.** The dial on a Silo chooses a
## shell type and a *count*, and the count scales whichever magnitude this row quotes:
## `damage_per_charge` for a Barrage, `goods_per_charge` for a Supply or a Sentry's
## magazine. One rule for all three, so loading four Charges means the same thing
## whatever is in the tube.
##
## Immutable once loaded, like every other definition: a hot-reload builds a new set
## rather than editing one of these in place.
class_name StratagemDefinition
extends RefCounted

## How a Stratagem resolves once a Painting completes. Three, because DESIGN.md's
## Milestone 1 caps the Stratagems at three and each of them answers a different problem:
## a Barrage is for what is already on top of you, a Supply Drop is for having run out,
## and a Sentry Drop is for ground you did not fortify.
##
## An effect rather than a per-row script, because the Simulation is data-oriented and a
## Stratagem that carried behaviour would be the one definition in the project that did.
enum Effect {
	## Shells the painted ground: `damage_per_charge` times the Charges loaded, taken off
	## every Enemy within `radius_tiles` of the target. Answers a breakthrough.
	BARRAGE = 0,
	## Drops `goods_per_charge` times the Charges loaded into the painting player's own
	## pockets — the same pockets the Build Gun spends from and a weapon fires out of.
	## Answers having run out.
	SUPPLY = 1,
	## Puts `sentry_machine` on the painted tile for `sentry_seconds`, arriving with
	## `goods_per_charge` times the Charges loaded already in its input buffer — which is
	## the whole of what "needs no Belt" means. Answers unfortified ground.
	SENTRY = 2,
}

## Spelling of each Effect in the file, indexed by the enum value.
const EFFECT_NAMES: Array = ["barrage", "supply", "sentry"]

var id: String = ""
var display_name: String = ""
var effect: Effect = Effect.BARRAGE

## How long a player must stand at the target and channel, in fixed-point seconds.
##
## The price of every Stratagem and the reason Painting is the best co-op moment the
## design has: one player is committed and helpless while the others cover them
## (GLOSSARY.md: exposed and unable to act). Zero is refused by the loader — a Painting
## with no channel is not a Painting.
var paint_seconds: int = 0

## How far a Barrage reaches from the painted tile, in whole tiles on the 2 m grid. 0 on
## anything that is not a Barrage.
##
## Tiles rather than metres for the reason a Turret's `range_tiles` is in tiles: that is
## the unit a player lays ground out in, and the Simulation converts it once, at the one
## place it is compared.
var radius_tiles: int = 0

## What one Charge of a Barrage takes off every Enemy in that radius, in whole hit points.
## 0 on anything that is not a Barrage.
##
## The same units a Turret's `damage` column and a weapon's are in, because an Enemy's
## health is whole points and a fraction of one is a rounding rule nobody needs.
var damage_per_charge: int = 0

## What one Charge delivers, as parallel Item ids and counts in the same `item:count` form
## a Recipe's inputs, a Machine's `build_cost` and a Delivery's bill use. Empty on a
## Barrage.
##
## Two destinations, one column: a Supply Drop hands it to the player who painted, and a
## Sentry Drop loads it into the Turret it drops. Same parse, same meaning — "this is what
## arrives" — so a Sentry that needs no Belt is not a second mechanism for getting goods
## onto the Map.
var goods_items: PackedStringArray = PackedStringArray()
var goods_counts: PackedInt64Array = PackedInt64Array()

## The Machine a Sentry Drop places, by id. Must name a Turret row in
## `content/machines.csv`. Empty on anything that is not a Sentry Drop.
##
## An existing row rather than a Stratagem-only Turret, so a Sentry is an ordinary Machine
## in every respect a player can observe — it aims, it spends rounds, it can be chewed
## down — and a Sentry Drop that places a Cannon instead is this column and nothing else.
var sentry_machine: String = ""

## How long a Sentry Drop's Turret stands, in whole seconds. 0 on anything that is not a
## Sentry Drop.
##
## Whole seconds rather than fixed point, because this is a countdown a player reads off
## the HUD rather than a rate anything is derived from, and because a temporary Machine
## wants a tick it expires on and not a fraction of one.
var sentry_seconds: int = 0

## Which row of the file this came from. Reporting only, and not hashed.
var source_row: int = -1


## The spelling of an Effect in the file, or "" for an unknown value.
static func effect_name(value: Effect) -> String:
	if value < 0 or value >= EFFECT_NAMES.size():
		return ""
	return EFFECT_NAMES[value]


## Parses an Effect, or -1 when the text names no Effect.
static func parse_effect(text: String) -> int:
	return EFFECT_NAMES.find(text.strip_edges())


func is_barrage() -> bool:
	return effect == Effect.BARRAGE


func is_supply() -> bool:
	return effect == Effect.SUPPLY


func is_sentry() -> bool:
	return effect == Effect.SENTRY


## Whether this Stratagem delivers goods at all — a Supply Drop into a player's pockets or
## a Sentry Drop into the Turret it places. One predicate rather than two tests at every
## call site, the way `MachineDefinition.produces_no_items` is one.
func delivers_goods() -> bool:
	return is_supply() or is_sentry()


## Sets what one Charge delivers, sorting by Item id so two rows that list the same goods
## in a different order are the same definition. `MachineDefinition.set_build_cost` does
## the same thing for the same reason.
func set_goods(names: PackedStringArray, quantities: PackedInt64Array) -> void:
	var order: Array = []
	for index: int in range(names.size()):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool: return names[a] < names[b])

	goods_items = PackedStringArray()
	goods_counts = PackedInt64Array()
	for index: int in order:
		goods_items.append(names[index])
		goods_counts.append(quantities[index])


## How many of an Item one Charge delivers. 0 for an Item it does not deliver, which is
## what lets a caller ask about any Item without first checking the row.
func goods_of(item_id: String) -> int:
	var at: int = goods_items.find(item_id)
	if at == -1:
		return 0
	return goods_counts[at]


func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_text(display_name)
	hasher.feed_int(effect)
	hasher.feed_int(paint_seconds)
	hasher.feed_int(radius_tiles)
	hasher.feed_int(damage_per_charge)
	hasher.feed_text(sentry_machine)
	hasher.feed_int(sentry_seconds)
	hasher.feed_int(goods_items.size())
	for slot: int in range(goods_items.size()):
		hasher.feed_text(goods_items[slot])
		hasher.feed_int(goods_counts[slot])
