## Fixed-point arithmetic. Every quantity inside the Simulation is one of these.
##
## A value is a plain 64-bit `int` holding a number scaled by `ONE`, i.e. 16
## fractional bits. 1.0 is 65536, 0.5 is 32768, -0.25 is -16384. Addition,
## subtraction and comparison are therefore ordinary integer operations and need
## no helper; multiplication, division and roots need the rescaling below.
##
## Why not floats: ADR 0002 puts every client on deterministic lockstep, and
## floats are not reproducible across machines, compilers or optimisation
## levels. One stray float desyncs co-op months later with no obvious cause.
## Integers are exactly reproducible everywhere, so the Simulation is integers
## all the way down. Conversion to float happens only at the rendering boundary
## via `to_float`, and never inward.
##
## Rounding rule: every operation that loses precision floors — rounds toward
## negative infinity — rather than truncating toward zero, so the sign of an
## operand never changes the rule being applied. `round_to_int` is the one
## exception and rounds halves upward, which is also sign-independent.
##
## Deliberately no bit shifts: `>>` on a negative signed integer is
## implementation-defined in C++, and lockstep cannot afford an operation whose
## result depends on the host's compiler. Explicit floored division costs a
## branch and buys platform independence.
##
## Ranges, in whole units:
##   representable   ±1.4e14 ....... any value
##   `mul` operands  ±46,341 ....... their product must fit in a signed 64-bit int
##   `div` dividend  ±2.1e9 ........ it is rescaled by ONE before dividing
## A 2 m grid map stays far inside all three.
class_name Fixed
extends RefCounted

## Number of fractional bits.
const FRACTIONAL_BITS: int = 16

## The fixed-point representation of 1.
const ONE: int = 1 << FRACTIONAL_BITS

## The fixed-point representation of 0.5.
const HALF: int = ONE >> 1

## Largest magnitude both operands of `mul` may have. isqrt(2^63 - 1).
const MUL_OPERAND_LIMIT: int = 3037000499


# ── Construction ──────────────────────────────────────────────────────────────

## Exact: converts a whole number to fixed point.
static func from_int(whole: int) -> int:
	return whole * ONE


## The canonical way to write a non-whole constant. `from_rational(1, 3)` rather
## than a float literal, so no float ever enters the Simulation. Floors when the
## denominator is not a power of two. A zero denominator yields 0 instead of
## crashing, because a Recipe or tuning file with a zero rate should degrade
## rather than take the Run down.
static func from_rational(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return 0
	return floor_div(numerator * ONE, denominator)


# ── Conversion back to integers ───────────────────────────────────────────────

## Rounds toward negative infinity.
static func floor_to_int(value: int) -> int:
	return floor_div(value, ONE)


## Rounds toward positive infinity.
static func ceil_to_int(value: int) -> int:
	return -floor_div(-value, ONE)


## Rounds to nearest, halves upward.
static func round_to_int(value: int) -> int:
	return floor_div(value + HALF, ONE)


## The value with its fractional part removed, still in fixed point.
static func floor_value(value: int) -> int:
	return floor_to_int(value) * ONE


## The fractional part, always in [0, ONE). `fract(-3.5)` is 0.5, because -3.5 is
## -4 plus 0.5 — a consequence of flooring rather than truncating.
static func fract(value: int) -> int:
	return value - floor_value(value)


# ── Floored integer division ──────────────────────────────────────────────────

## Integer division rounding toward negative infinity. GDScript's `/` truncates
## toward zero, which would make rounding depend on sign. A zero divisor yields
## 0 rather than crashing.
static func floor_div(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return 0
	var quotient: int = numerator / denominator
	if numerator % denominator != 0 and (numerator < 0) != (denominator < 0):
		quotient -= 1
	return quotient


# ── Multiplication and division ───────────────────────────────────────────────

## Multiplies two fixed-point values. The product carries 32 fractional bits, so
## it is rescaled back down by ONE. Both operands must be within
## ±MUL_OPERAND_LIMIT or the intermediate product overflows a signed 64-bit int.
static func mul(a: int, b: int) -> int:
	return floor_div(a * b, ONE)


## Divides two fixed-point values. The dividend is rescaled up by ONE first, so
## it must be within ±2^47. A zero divisor yields 0 rather than crashing.
static func div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return floor_div(a * ONE, b)


## Square root, floored. Negative input yields 0: the Simulation has no use for
## imaginary numbers, and a crash mid-Run is worse than a clamp.
static func sqrt(value: int) -> int:
	if value <= 0:
		return 0
	return isqrt(value * ONE)


## Integer square root by Newton's method, floored. Exact for every non-negative
## input and free of any floating-point step.
static func isqrt(value: int) -> int:
	if value < 2:
		return maxi(value, 0)

	# Seed above the true root so the iteration descends monotonically to it.
	var guess: int = value
	var shift: int = 1
	while (guess >> shift) > 0 and shift < 64:
		shift += 1
	guess = 1 << ((shift + 1) / 2)

	while true:
		var next: int = (guess + value / guess) / 2
		if next >= guess:
			break
		guess = next
	return guess


# ── Interpolation and bounds ──────────────────────────────────────────────────

## Linear interpolation from `a` to `b` by `t`, where `t` is fixed-point and
## normally in [0, ONE]. Values outside that range extrapolate.
##
## Named `lerp_fixed` rather than `lerp` because GDScript's global `lerp` is
## float-based, and a name collision here is exactly the kind of accident that
## smuggles a float into the Simulation.
static func lerp_fixed(a: int, b: int, t: int) -> int:
	return a + mul(b - a, t)


## Smooth interpolation of `t` in [0, ONE]: flat at both ends, steepest in the
## middle. The classic `t² (3 - 2t)`, in fixed point.
##
## Where a plain `lerp_fixed` makes a camera transition start and stop abruptly, this
## makes it ease in and out, which is the difference between a lift that feels like a
## camera move and one that feels like a glitch. Symmetric, so halfway through the
## time is exactly halfway through the distance.
static func smoothstep_fixed(t: int) -> int:
	var clamped: int = clamp_fixed(t, 0, ONE)
	return mul(mul(clamped, clamped), from_int(3) - mul(from_int(2), clamped))


## Constrains a value to [low, high]. Named `clamp_fixed` for the same reason as
## `lerp_fixed` — these are plain integers, so `clampi` would also work, but a
## single vocabulary for Simulation quantities is worth more than brevity.
static func clamp_fixed(value: int, low: int, high: int) -> int:
	return mini(maxi(value, low), high)


# ── Angles and trigonometry ───────────────────────────────────────────────────
# Angles are measured in **turns**, not radians: one full revolution is `TURN`,
# which is `ONE`. Radians would need PI, and PI is a float — banned inside the
# Simulation, and not exactly representable anyway. Turns also make the values a
# reader can check by eye exact: a quarter turn is 16384 and nothing else.
#
# Sine comes from a quarter-wave table of 65 samples with linear interpolation
# between them. Integer-only, so it is bit-identical on every machine, which is
# the whole reason a lookup table is preferred here to any series expansion in
# floating point. The quadrant boundaries are exact; everything between them is
# within `SIN_TOLERANCE` of the true value, which at a 4 m/s walking speed is an
# error of under a millimetre per second.

## One full revolution.
const TURN: int = ONE

## A quarter of a revolution — 90 degrees.
const QUARTER_TURN: int = ONE >> 2

## How far `sin_turns` and `cos_turns` may be from the true value, in fixed-point
## units. Stated rather than discovered, so a change to the table has to either
## keep this promise or change it deliberately.
const SIN_TOLERANCE: int = 8

## Angle between adjacent samples of the quarter-wave table.
const SIN_TABLE_STEP: int = QUARTER_TURN / (SIN_TABLE_SAMPLES - 1)

## How many samples the quarter-wave table holds, counting both ends.
const SIN_TABLE_SAMPLES: int = 65

## sin(k / 256 of a turn) for k = 0 to 64, scaled by ONE and rounded to nearest.
## A quarter wave is enough: the other three quadrants are reflections of it.
const SIN_TABLE: Array = [
	0, 1608, 3216, 4821, 6424, 8022, 9616, 11204,
	12785, 14359, 15924, 17479, 19024, 20557, 22078, 23586,
	25080, 26558, 28020, 29466, 30893, 32303, 33692, 35062,
	36410, 37736, 39040, 40320, 41576, 42806, 44011, 45190,
	46341, 47464, 48559, 49624, 50660, 51665, 52639, 53581,
	54491, 55368, 56212, 57022, 57798, 58538, 59244, 59914,
	60547, 61145, 61705, 62228, 62714, 63162, 63572, 63944,
	64277, 64571, 64827, 65043, 65220, 65358, 65457, 65516,
	65536,
]


## Reduces an angle to [0, TURN). Yaw accumulates without bound as a player keeps
## turning, so every angle has to be reducible; flooring makes the reduction
## sign-independent, so turning left past north lands on the same angle as turning
## right past it.
static func wrap_turns(angle: int) -> int:
	return angle - floor_div(angle, TURN) * TURN


## Sine of an angle in turns.
static func sin_turns(angle: int) -> int:
	var reduced: int = wrap_turns(angle)
	var quadrant: int = reduced / QUARTER_TURN
	var into: int = reduced % QUARTER_TURN

	match quadrant:
		0:
			return _quarter_wave(into)
		1:
			return _quarter_wave(QUARTER_TURN - into)
		2:
			return -_quarter_wave(into)
		_:
			return -_quarter_wave(QUARTER_TURN - into)


## Cosine of an angle in turns. Sine a quarter turn ahead, so there is one table
## and one interpolation rule rather than two that could disagree.
static func cos_turns(angle: int) -> int:
	return sin_turns(angle + QUARTER_TURN)


## The quarter wave at `into` turns, where `into` is in [0, QUARTER_TURN].
## Linearly interpolated between the two nearest samples.
static func _quarter_wave(into: int) -> int:
	var sample: int = into / SIN_TABLE_STEP
	if sample >= SIN_TABLE_SAMPLES - 1:
		return ONE
	var remainder: int = into % SIN_TABLE_STEP
	var low: int = SIN_TABLE[sample]
	var high: int = SIN_TABLE[sample + 1]
	return low + floor_div((high - low) * remainder, SIN_TABLE_STEP)


# ── The rendering boundary ────────────────────────────────────────────────────

## Converts to float for display. The ONLY sanctioned crossing, and it goes one
## way: Godot-side code calls this to position a mesh or fill a gauge. Nothing
## converts a float back into a Simulation quantity, because the moment a float
## influences Simulation state, lockstep determinism is gone.
static func to_float(value: int) -> float:  # purity-ok: the rendering boundary, outbound only
	return float(value) / float(ONE)  # purity-ok: the rendering boundary, outbound only


# ── Parsing from content files ─────────────────────────────────────────────────
# Definition tables and the tuning file are written by hand in decimal, because
# "3.2 seconds" is a rate a human can reason about and `from_rational(16, 5)` is
# not. The crossing happens exactly once, here, and never touches a float: the
# text is split into an integer numerator over a power of ten and handed to
# `from_rational`, so the result floors like every other lossy operation and is
# bit-identical on every machine.

## True when `text` is a decimal this module will parse: optional sign, at least
## one digit, and at most one point with digits on both sides of it. Deliberately
## strict — a loader calls this to reject a typo'd rate by name instead of
## letting it parse as zero.
static func is_decimal_string(text: String) -> bool:
	var body: String = text.strip_edges()
	if body.begins_with("-") or body.begins_with("+"):
		body = body.substr(1)
	if body.is_empty():
		return false

	var parts: PackedStringArray = body.split(".")
	if parts.size() > 2:
		return false
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
	return true


## Converts a decimal string to fixed point, exactly. Returns 0 for anything
## `is_decimal_string` rejects, so callers must check first rather than trust a
## zero — a rate that quietly becomes zero is the failure this whole module is
## arranged to prevent.
static func from_decimal_string(text: String) -> int:
	if not is_decimal_string(text):
		return 0

	var body: String = text.strip_edges()
	var negative: bool = body.begins_with("-")
	if negative or body.begins_with("+"):
		body = body.substr(1)

	var parts: PackedStringArray = body.split(".")
	var digits: String = parts[0]
	var denominator: int = 1
	if parts.size() == 2:
		digits += parts[1]
		for i: int in range(parts[1].length()):
			denominator *= 10

	var numerator: int = digits.to_int()
	if negative:
		numerator = -numerator
	return from_rational(numerator, denominator)
