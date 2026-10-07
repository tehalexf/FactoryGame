## One Recipe, as defined by one row of `content/recipes.csv`.
##
## A Recipe is a declarative input→output transformation with a rate, defined as
## data and never as code (GLOSSARY.md). Inputs and outputs are held as parallel
## arrays of Item index and quantity rather than as a list of pairs, because a tick
## reading them wants integers in index order and nothing else.
##
## Item ids become indices at load time. The set of Items is exactly the set the
## Recipes mention, interned in sorted order by `Definitions`, so adding an Item
## means naming it in a Recipe and nothing more — there is no Item table to keep in
## step.
##
## `duration_seconds` is fixed-point. The file writes `3.2`, because that is how a
## human reasons about a rate; the conversion is exact and floor-rounded, and no
## float exists at any point (ADR 0002).
class_name RecipeDefinition
extends RefCounted

var id: String = ""
var display_name: String = ""

## How long one craft takes, in fixed-point seconds of game time.
var duration_seconds: int = 0

## Which row of the file this came from. Reporting only, and not hashed.
var source_row: int = -1

var _input_items: PackedInt64Array = PackedInt64Array()
var _input_quantities: PackedInt64Array = PackedInt64Array()
var _output_items: PackedInt64Array = PackedInt64Array()
var _output_quantities: PackedInt64Array = PackedInt64Array()

## Item ids as written, kept so `Definitions` can intern them and resolve the
## indices above. Not part of the loaded definition's meaning once resolved.
var _input_names: PackedStringArray = PackedStringArray()
var _output_names: PackedStringArray = PackedStringArray()


## Arity comes from the quantities, which are set as soon as the row is read.
## The Item *indices* are only resolved once the whole set has been interned, so
## counting those would make a Recipe look empty during loading — which is exactly
## when the loader needs to know whether it has any.
func input_count() -> int:
	return _input_quantities.size()


## Item index of the nth input. -1 when out of range.
func input_item(index: int) -> int:
	return _at(_input_items, index)


func input_quantity(index: int) -> int:
	return _at(_input_quantities, index)


func output_count() -> int:
	return _output_quantities.size()


func output_item(index: int) -> int:
	return _at(_output_items, index)


func output_quantity(index: int) -> int:
	return _at(_output_quantities, index)


## Every Item id this Recipe mentions, inputs then outputs, as written.
func mentioned_items() -> PackedStringArray:
	var mentioned: PackedStringArray = _input_names.duplicate()
	mentioned.append_array(_output_names)
	return mentioned


# ── Loading ───────────────────────────────────────────────────────────────────
# Called by `Definitions` while it builds the set, and by nothing else.

func set_inputs(names: PackedStringArray, quantities: PackedInt64Array) -> void:
	_input_names = names
	_input_quantities = quantities


func set_outputs(names: PackedStringArray, quantities: PackedInt64Array) -> void:
	_output_names = names
	_output_quantities = quantities


## Turns the Item ids into indices into the interned Item list.
func resolve_items(item_ids: PackedStringArray) -> void:
	_input_items = _resolve(_input_names, item_ids)
	_output_items = _resolve(_output_names, item_ids)


## Feeds this definition into a hash, in a fixed order. Item *ids* go in rather
## than indices, for the same reason `MachineDefinition` hashes its `recipe_id`:
## the digest describes the content, not the loader's numbering.
func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_text(display_name)
	hasher.feed_int(duration_seconds)
	_feed_items(hasher, _input_names, _input_quantities)
	_feed_items(hasher, _output_names, _output_quantities)


func _feed_items(hasher: StateHasher, names: PackedStringArray, quantities: PackedInt64Array) -> void:
	hasher.feed_int(names.size())
	for index: int in range(names.size()):
		hasher.feed_text(names[index])
		hasher.feed_int(quantities[index])


func _resolve(names: PackedStringArray, item_ids: PackedStringArray) -> PackedInt64Array:
	var resolved: PackedInt64Array = PackedInt64Array()
	for name: String in names:
		resolved.append(item_ids.find(name))
	return resolved


func _at(values: PackedInt64Array, index: int) -> int:
	if index < 0 or index >= values.size():
		return -1
	return values[index]
