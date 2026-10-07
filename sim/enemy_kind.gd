## The roster of Enemy kinds, and the one place a kind's name and its integer agree.
##
## An Enemy is an index into parallel integer arrays and its kind is one of those
## integers (ADR 0001), so the Simulation only ever handles the number. But
## `content/waves.csv` has to name a kind in words — a table a designer edits cannot be
## written in enum ordinals — so the name and the number meet exactly here, and nowhere
## else. `Simulation.ENEMY_KIND_*` are aliases of these constants rather than a second
## copy of them, which is what stops the table and the Simulation from drifting apart.
##
## Adding an Enemy kind is a constant and a name in `KIND_NAMES` at the matching index,
## plus whatever behaviour the Simulation gives it. The Wave table then reaches it without
## further change.
class_name EnemyKind
extends RefCounted

## Chaff: the weakest Enemy, which swarms toward the Nest (GLOSSARY.md). The only kind
## Milestone 1 ships.
const CRAWLER: int = 0

## Every kind's name, **indexed by the kind's own integer**. The order is therefore the
## kind numbering and not a list that happens to be sorted; `index_of` is the only way
## round that is read, and it is the inverse by construction.
const KIND_NAMES: Array = ["crawler"]


## The kind a name means, or -1 for a name no kind answers to. -1 rather than a
## plausible-looking 0, so a typo in the Wave table is an error naming the row instead of
## a Wave quietly made of Crawlers.
static func index_of(name: String) -> int:
	return KIND_NAMES.find(name)


## What a kind is called, or an empty string for a kind that does not exist.
static func name_of(kind: int) -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return ""
	return KIND_NAMES[kind]


## Every name a Wave row may use, in kind order. For an error message that tells the
## reader what they could have written.
static func every_name() -> String:
	return ", ".join(PackedStringArray(KIND_NAMES))
