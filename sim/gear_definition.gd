## One piece of Gear, as defined by one row of `content/gear.csv`.
##
## Gear is **modular**: a single weapon frame accepts components — barrels, magazines,
## sights — each made on a different production line, and power comes from combination
## rather than from tiers (GLOSSARY.md). There is no Rifle Mk2, and there is nowhere in
## this schema to write one: a row is either a weapon or a component, and a component
## only ever says what it does to the frame holding it.
##
## **The slot a component occupies is its `kind`, and the set of slots is exactly the set
## of kinds the table mentions.** That is the same arrangement the Items have — the set of
## Items is exactly the set the Recipes mention, and there is no Item table — and it buys
## the same thing: a fourth slot is a row, not an enum somebody has to extend. `weapon` is
## the one reserved kind, because a weapon is the frame rather than something fitted into
## it.
##
## Every number here is whole, or fixed point parsed from a decimal. Combat resolution is
## integer arithmetic inside the Simulation and only its presentation is float, so there
## is no float on this object at any point.
##
## Immutable once loaded, like every other definition: a hot-reload builds a new set
## rather than editing one of these in place — which is what makes every number below a
## thing you can tune with the game running.
class_name GearDefinition
extends RefCounted

## The one reserved `kind`. Everything else the table names is a slot a component fits.
const WEAPON_KIND: String = "weapon"

## How a weapon reaches what it is aimed at.
##
## Two values and deliberately not three: a weapon either throws something down the line
## of aim or it swings at what is in front of you, and which one it is decides whether it
## spends Ammunition and how far it carries. Both resolve against the same Enemy
## positions in the same fixed point.
enum Attack {
	## Swung at whatever is in front of the player, inside `range_metres`. Spends no
	## Ammunition: the Pneumatic Wrench is the melee weapon and it is also what repairs
	## (DESIGN.md), and what it costs is a player's presence rather than materials.
	MELEE = 0,
	## Fired down the line of aim, with `spread_degrees` of scatter, spending
	## `ammunition_per_shot` of `ammunition_item` out of the player's own pockets.
	RANGED = 1,
}

const ATTACK_NAMES: Array = ["melee", "ranged"]

var id: String = ""
var display_name: String = ""

## `weapon`, or the slot this component fits. See the note at the top of this file: the
## slots are interned from this column rather than declared anywhere.
var kind: String = ""

## How a weapon reaches, or -1 on a component, which reaches nothing by itself.
var attack: int = -1

## What one hit takes off an Enemy, in whole hit points — the same units a Turret's
## `damage` column is in, because an Enemy's health is whole points and a fraction of a
## hit point is a rounding rule nobody needs.
var damage: int = 0

## How far the weapon carries, in fixed-point metres. A melee weapon's reach.
var range_metres: int = 0

## How far off the line of aim a shot may scatter, in fixed-point degrees. Zero is exact.
## This is what separates the Bolt Rifle from the Drum Autocannon more than damage does.
var spread_degrees: int = 0

## How long between one shot and the next, in fixed-point seconds. Turned into a whole
## number of ticks by the Simulation, so a rate is exact rather than emergent.
var seconds_per_shot: int = 0

## The Item a shot spends, or empty for a melee weapon. Must be an Item some Recipe
## mentions, because that is the only way an Item comes to exist.
var ammunition_item: String = ""

## How many of it one shot spends.
var ammunition_per_shot: int = 0

# ── What a component does to the frame ────────────────────────────────────────
# Whole percentages, added together across every fitted component and applied to the
# weapon's own quoted figure. Additive rather than multiplicative so that two components
# can be reasoned about in either order and so that the arithmetic is one integer
# multiply and one floor — a chain of fixed-point multiplications would round at every
# link and make the order they were fitted in reach the state hash.
#
# A weapon row must leave all of these at zero: a frame states what it is, and a
# modifier on a frame would be a tier in disguise.

## Percent added to the frame's `damage`.
var damage_percent: int = 0

## Percent added to the frame's `range_metres`.
var range_percent: int = 0

## Percent added to the frame's `spread_degrees`. Negative is tighter.
var spread_percent: int = 0

## Percent added to the frame's `seconds_per_shot`. Negative is faster.
var interval_percent: int = 0

## Percent added to the frame's `ammunition_per_shot`. Negative is cheaper.
var ammunition_percent: int = 0

## Percent added to the damage the player *takes*. Negative is armour. The one modifier
## that is not about the weapon, and the reason this table is Gear rather than Weapons:
## GLOSSARY.md says Gear is "weapons and equipment".
var damage_taken_percent: int = 0

## Which row of the file this came from. Reporting only, and not hashed.
var source_row: int = -1


static func parse_attack(text: String) -> int:
	return ATTACK_NAMES.find(text.strip_edges())


func is_weapon() -> bool:
	return kind == WEAPON_KIND


func is_melee() -> bool:
	return is_weapon() and attack == Attack.MELEE


func is_ranged() -> bool:
	return is_weapon() and attack == Attack.RANGED


## The slot this fits, or empty for a weapon frame.
func slot_id() -> String:
	return "" if is_weapon() else kind


## Whether this row changes anything at all about the frame it is fitted to. A component
## that does not is refused by the loader: a component that measurably changes nothing is
## a Delivery tier a player paid for and got nothing from.
func changes_anything() -> bool:
	return (
		damage_percent != 0
		or range_percent != 0
		or spread_percent != 0
		or interval_percent != 0
		or ammunition_percent != 0
		or damage_taken_percent != 0
	)


func feed_into(hasher: StateHasher) -> void:
	hasher.feed_text(id)
	hasher.feed_text(display_name)
	hasher.feed_text(kind)
	hasher.feed_int(attack)
	hasher.feed_int(damage)
	hasher.feed_int(range_metres)
	hasher.feed_int(spread_degrees)
	hasher.feed_int(seconds_per_shot)
	hasher.feed_text(ammunition_item)
	hasher.feed_int(ammunition_per_shot)
	hasher.feed_int(damage_percent)
	hasher.feed_int(range_percent)
	hasher.feed_int(spread_percent)
	hasher.feed_int(interval_percent)
	hasher.feed_int(ammunition_percent)
	hasher.feed_int(damage_taken_percent)
