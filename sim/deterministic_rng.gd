## The Simulation's only source of randomness.
##
## ADR 0002 forbids unseeded randomness anywhere in the Simulation: every client
## in lockstep must draw the same numbers in the same order, so the stream has to
## be a function of the seed and nothing else. Godot's `randi()` and
## `RandomNumberGenerator` are both unsuitable — the former draws from a global
## stream seeded at engine startup, and neither is contractually frozen across
## engine versions. This generator is written out in full so the stream is a
## property of this repository rather than of the engine build.
##
## Algorithm: a 32-bit PCG (RXS-M-XS output over an LCG state). Chosen because it
## is a dozen lines, needs no 64-bit overflow tricks, and passes the statistical
## tests that matter for Wave composition and damage rolls. `state` is the whole
## of its memory, so saving a Run means saving one integer.
##
## Every arithmetic step is masked to 32 bits and every intermediate product fits
## inside a signed 64-bit integer, so nothing here depends on overflow behaviour.
class_name DeterministicRng
extends RefCounted

const MASK_32: int = 0xFFFFFFFF
const LCG_MULTIPLIER: int = 747796405
const LCG_INCREMENT: int = 2891336453
const OUTPUT_MULTIPLIER: int = 277803737

## The generator's entire memory. Read it to checkpoint, assign it to resume.
var state: int = 0:
	set(value):
		state = value & MASK_32


func _init(seed_value: int = 0) -> void:
	# Mixing the seed before first use stops neighbouring seeds (1, 2, 3 — the
	# kind a tuning file or a test will actually use) from producing visibly
	# related streams.
	state = seed_value & MASK_32
	_advance()
	state = (state + (seed_value & MASK_32)) & MASK_32
	_advance()


## A uniform draw in [0, 2^32).
func next_uint32() -> int:
	var previous: int = state
	_advance()

	var shift: int = ((previous >> 28) + 4)
	var word: int = ((previous >> shift) ^ previous) * OUTPUT_MULTIPLIER & MASK_32
	return (word >> 22) ^ word


## A uniform draw in [0, bound). Returns 0 for a bound of 1 or less, so a Recipe
## or Wave table with a degenerate count degrades instead of hanging.
##
## Rejection sampling, not a bare modulo: `next_uint32() % bound` is biased toward
## low values whenever bound does not divide 2^32, which would skew Wave
## composition. Rejection consumes a variable number of draws, which is still
## perfectly deterministic — every client rejects the same values.
func next_below(bound: int) -> int:
	if bound <= 1:
		return 0
	var reject_below: int = (MASK_32 + 1) % bound
	while true:
		var drawn: int = next_uint32()
		if drawn >= reject_below:
			return drawn % bound
	return 0


## A uniform draw in [low, high], both ends included. An inverted range yields
## `low`.
func next_range(low: int, high: int) -> int:
	if high <= low:
		return low
	return low + next_below(high - low + 1)


## A uniform fixed-point draw in [0, Fixed.ONE) — that is, [0, 1).
##
## Takes the high 16 bits of one draw rather than the low ones. 2^32 divides
## evenly by 2^16, so there is no bias either way, but the high bits of an
## LCG-derived word are the better-mixed half.
func next_fixed() -> int:
	return next_uint32() / Fixed.ONE


func _advance() -> void:
	state = (state * LCG_MULTIPLIER + LCG_INCREMENT) & MASK_32
