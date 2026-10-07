## Reduces Simulation state to one integer, so two Simulations can be compared
## cheaply and exactly.
##
## This is the instrument the determinism promise is measured with. If the hash
## is insensitive to some part of the state, a desync in that part is invisible —
## so the rule is that everything the Simulation can act on gets fed, in a fixed
## order, every tick.
##
## Algorithm: two independent FNV-1a lanes over the bytes, combined into one
## 63-bit digest. Two lanes because a single 32-bit lane collides about once in
## four billion comparisons, which over a long replay is not comfortable odds;
## 64-bit FNV is not an option because its prime overflows a signed 64-bit
## multiply. Both lane multipliers are below 2^31, so every intermediate product
## fits and nothing relies on overflow behaviour.
##
## Not cryptographic, and not meant to be. It detects accidental divergence, not
## a forged save.
class_name StateHasher
extends RefCounted

const MASK_32: int = 0xFFFFFFFF

const LANE_A_OFFSET: int = 2166136261
const LANE_A_PRIME: int = 16777619

const LANE_B_OFFSET: int = 2654435769
const LANE_B_PRIME: int = 1000000007
## Lane B sees every byte flipped against this, so the two lanes never walk the
## same trajectory even for inputs made entirely of zeroes.
const LANE_B_SALT: int = 0x5A

var _lane_a: int = LANE_A_OFFSET
var _lane_b: int = LANE_B_OFFSET


## Feeds a 64-bit integer, low byte first.
##
## `>>` on a negative value is arithmetic on every platform Godot targets, but
## this does not depend on that: sign extension only ever touches bits above the
## byte being masked out, so the eight bytes recovered here are the value's
## two's-complement bytes either way.
func feed_int(value: int) -> StateHasher:
	for byte_index: int in range(8):
		_absorb((value >> (byte_index * 8)) & 0xFF)
	return self


func feed_bool(value: bool) -> StateHasher:
	return feed_int(1 if value else 0)


## Feeds a whole array: its length first, then its elements in order. The length
## goes in so that [1, 2] and [1, 2, 0] cannot hash alike.
func feed_ints(values: PackedInt64Array) -> StateHasher:
	feed_int(values.size())
	for value: int in values:
		feed_int(value)
	return self


## The combined digest. A pure read — it can be called repeatedly and more state
## can be fed afterwards.
##
## Lane A contributes 31 bits rather than 32 so the result stays inside a
## non-negative signed 64-bit integer, which keeps digests comfortable in logs,
## save files and test output.
func digest() -> int:
	return ((_lane_a & 0x7FFFFFFF) << 32) | _lane_b


func _absorb(byte_value: int) -> void:
	_lane_a = ((_lane_a ^ byte_value) * LANE_A_PRIME) & MASK_32
	_lane_b = ((_lane_b ^ (byte_value ^ LANE_B_SALT)) * LANE_B_PRIME) & MASK_32
