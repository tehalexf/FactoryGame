## One Delivery tier, as defined by one row of `content/deliveries.csv`.
##
## A Delivery is the act of bringing goods to the Nest to unlock the next tier of
## Machines, Gear components and Stratagems (GLOSSARY.md). There is no research menu
## and no science resource: progression is physical, so a tier is a bill of goods and
## a list of things it opens up, and nothing else.
##
## **There is no numeric column here, and that is the design.** An unlock changes what
## a player can *build*, never a number attached to something they already have — so
## this file offers nowhere to write "+10% mining speed" even if somebody wanted to.
## The acceptance criterion "unlocks are Machines, Gear components and Stratagems,
## never stat increases" is therefore a property of the schema rather than a rule
## somebody has to remember.
##
## Immutable once loaded, like every other definition: hot-reload replaces the whole
## set rather than editing one of these in place.
class_name DeliveryDefinition
extends RefCounted

var id: String = ""
var display_name: String = ""

## The Depth a Node has to be worked at before this tier can be delivered at all.
##
## Depth gates what is possible to deliver (GLOSSARY.md, DESIGN.md), and this is the
## whole of that gate. Compared against the deepest Node the Factory is actually
## mining, so reaching a tier means building a Miner that reaches it rather than
## ticking a box.
var min_depth: int = 0

## What the Nest wants, as parallel Item ids and counts — the same `item:count` form a
## Recipe's inputs and a Machine's build cost use, parsed by the same function, so the
## three cannot drift apart on what counts as well-formed.
var goods_items: PackedStringArray = PackedStringArray()
var goods_counts: PackedInt64Array = PackedInt64Array()

## The Machines this tier opens up, by id. Every one must name a row in
## `content/machines.csv` — a tier unlocking a Machine that does not exist is content
## somebody broke, not a tier that unlocks nothing.
##
## A Machine is locked **because some Delivery unlocks it**, which is why there is no
## `locked` column in `machines.csv`: the set of Machines a Run opens with is exactly
## the set no Delivery names. One authority, and adding a Machine to a tier here is
## what takes it off the opening Build Gun.
var unlocks_machines: PackedStringArray = PackedStringArray()

## The Gear components this tier opens up, by id. Gear is modular — a weapon frame
## accepting barrels, magazines and sights made on different production lines
## (GLOSSARY.md) — and the frames and components themselves are a later milestone, so
## these are identifiers the Simulation records as unlocked and nothing else reads yet.
## They are hashed and saved from the day they are earned, which is the half that cannot
## be retrofitted.
var unlocks_gear: PackedStringArray = PackedStringArray()

## The Stratagems this tier opens up, by id. Same standing as the Gear list: the Silo,
## the Charges and the Painting arrive later, and what a Run has unlocked is recorded
## now so that progression earned in a Run survives into the one that implements them.
var unlocks_stratagems: PackedStringArray = PackedStringArray()

## Which row of the file this came from. Reporting only, and not hashed.
var source_row: int = -1


func set_goods(items: PackedStringArray, counts: PackedInt64Array) -> void:
	goods_items = items.duplicate()
	goods_counts = counts.duplicate()


## How many of an Item this tier wants. Zero for an Item it does not ask for, which is
## what lets a caller ask about any Item without first checking the bill.
func goods_required(item_id: String) -> int:
	var slot: int = goods_items.find(item_id)
	if slot == -1:
		return 0
	return goods_counts[slot]


## Whether this tier is what unlocks a given Machine id.
func unlocks_machine(machine_id: String) -> bool:
	return unlocks_machines.find(machine_id) != -1


func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_int(min_depth)
	hasher.feed_int(goods_items.size())
	for slot: int in range(goods_items.size()):
		hasher.feed_text(goods_items[slot])
		hasher.feed_int(goods_counts[slot])
	_feed_list(hasher, unlocks_machines)
	_feed_list(hasher, unlocks_gear)
	_feed_list(hasher, unlocks_stratagems)


func _feed_list(hasher: StateHasher, ids: PackedStringArray) -> void:
	hasher.feed_int(ids.size())
	for entry: String in ids:
		hasher.feed_text(entry)
