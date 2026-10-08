## One structure, as defined by one row of `content/structures.csv`: a Belt or a Wall.
##
## A structure is a thing a player builds that is **not a Machine** — DESIGN.md puts both
## outside the eight, and GLOSSARY.md keeps the words apart. It has no Recipe, no Power, no
## ports and no buffers, so the only thing a table has to say about one is what it costs,
## which is why this carries a cost and nothing else.
##
## The cost is **per tile**. A Belt is laid as a route of several tiles and a Wall one tile
## at a time, so per tile is the one reading that means the same thing for both — and it is
## the number a player decides on, because the length of a route is on screen before the
## drag is released.
##
## Immutable once loaded, like `MachineDefinition`: a hot-reload replaces the whole set.
class_name StructureDefinition
extends RefCounted

var id: String = ""
var display_name: String = ""

## What one tile costs, as parallel arrays sorted by Item id. Sorted for the reason a
## Machine's build cost is: the order the columns were written in must not reach the state
## hash. Empty is a structure that is free, which is legal and is what a caller supplying no
## structures table at all gets.
var build_cost_items: PackedStringArray = PackedStringArray()
var build_cost_counts: PackedInt64Array = PackedInt64Array()

## Which row of the file this came from, so a cross-table error can name it.
var source_row: int = -1


## Takes the cost as the file wrote it and holds it sorted by Item id.
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


## How many of an Item one tile costs. 0 for an Item it does not need.
func build_cost_of(item_id: String) -> int:
	var at: int = build_cost_items.find(item_id)
	if at == -1:
		return 0
	return build_cost_counts[at]


func is_free() -> bool:
	return build_cost_items.is_empty()


func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_text(display_name)
	hasher.feed_int(build_cost_items.size())
	for index: int in range(build_cost_items.size()):
		hasher.feed_text(build_cost_items[index])
		hasher.feed_int(build_cost_counts[index])


func _to_string() -> String:
	return "StructureDefinition(%s)" % id
