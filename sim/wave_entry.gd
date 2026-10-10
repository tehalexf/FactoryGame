## One tier of Wave composition, as defined by one row of `content/waves.csv`.
##
## A Wave is not a choice between rows: it is **every row the Factory's Heat has
## reached**, each contributing its own count. So this is a tier rather than a template,
## and adding an Enemy to the Waves is a row rather than a branch in `_waves`.
##
## Everything here is a whole number of Enemies or of heat units. There is no fixed point
## in Wave composition at all — a count of Enemies is a count, and the one division
## involved (`heat_per_extra`) is integer and happens once per Wave rather than once per
## tick.
class_name WaveEntry
extends RefCounted

var id: String = ""

## Which Enemy this tier sends, as the Simulation's own `ENEMY_KIND_*` integer. Resolved
## from the name in the file at load time, so a kind the Simulation does not implement is
## an error naming the row rather than an Enemy nothing can draw.
var enemy_kind: int = -1

## The Heat at which this tier starts contributing.
var min_heat: int = 0

## How many of this Enemy each Breach releases at exactly `min_heat`.
var count_per_breach: int = 0

## How much further Heat buys one more per Breach. 0 means the count never grows.
var heat_per_extra: int = 0

## The most of this Enemy one Breach releases in one Wave, however hot the Factory gets.
var max_per_breach: int = 0

## Which row of the file this came from. Reporting only, and not hashed.
var source_row: int = -1


## How many of this Enemy one Breach releases at a given Heat. Zero below the threshold,
## so a tier that has not been unlocked contributes nothing rather than a minimum.
##
## One integer division, performed once when a Wave is composed. Nothing accumulates
## here, so there is no remainder to carry and nothing to drift.
func count_at_heat(heat: int) -> int:
	if heat < min_heat:
		return 0
	var extra: int = 0
	if heat_per_extra > 0:
		@warning_ignore("integer_division")
		extra = (heat - min_heat) / heat_per_extra
	return mini(count_per_breach + extra, max_per_breach)


func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_int(enemy_kind)
	hasher.feed_int(min_heat)
	hasher.feed_int(count_per_breach)
	hasher.feed_int(heat_per_extra)
	hasher.feed_int(max_per_breach)
