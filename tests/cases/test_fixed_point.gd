## Fixed-point arithmetic contract.
##
## Expected values here are worked out independently of the implementation —
## 16 fractional bits means ONE is 65536, so 1.5 is 98304 and one third floors
## to 21845. Never assert `Fixed.mul(a, b) == (a * b) >> 16`; that would restate
## the code and could never disagree with it.
extends TestCase


# ── Representation ────────────────────────────────────────────────────────────

func test_one_is_two_to_the_sixteenth() -> void:
	assert_eq(Fixed.ONE, 65536, "16 fractional bits")
	assert_eq(Fixed.HALF, 32768, "a half is half of ONE")


func test_whole_numbers_scale_by_one() -> void:
	assert_eq(Fixed.from_int(0), 0)
	assert_eq(Fixed.from_int(1), 65536)
	assert_eq(Fixed.from_int(3), 196608)
	assert_eq(Fixed.from_int(-2), -131072)


func test_rationals_are_exact_when_the_denominator_is_a_power_of_two() -> void:
	assert_eq(Fixed.from_rational(1, 2), 32768, "one half")
	assert_eq(Fixed.from_rational(3, 4), 49152, "three quarters")
	assert_eq(Fixed.from_rational(-1, 4), -16384, "minus one quarter")


func test_rationals_floor_when_inexact() -> void:
	# 65536 / 3 = 21845.33…
	assert_eq(Fixed.from_rational(1, 3), 21845, "one third floors")
	# -65536 / 3 = -21845.33… and flooring goes away from zero
	assert_eq(Fixed.from_rational(-1, 3), -21846, "minus one third floors downward")


func test_from_rational_with_a_zero_denominator_is_zero() -> void:
	assert_eq(Fixed.from_rational(5, 0), 0, "division by zero is defined as zero, never a crash")


# ── Back to integers ──────────────────────────────────────────────────────────

func test_floor_to_int_rounds_toward_negative_infinity() -> void:
	assert_eq(Fixed.floor_to_int(Fixed.from_int(7)), 7)
	assert_eq(Fixed.floor_to_int(Fixed.from_rational(7, 2)), 3, "3.5 floors to 3")
	assert_eq(Fixed.floor_to_int(Fixed.from_rational(-7, 2)), -4, "-3.5 floors to -4")


func test_ceil_to_int_rounds_toward_positive_infinity() -> void:
	assert_eq(Fixed.ceil_to_int(Fixed.from_int(7)), 7, "an exact whole number is unchanged")
	assert_eq(Fixed.ceil_to_int(Fixed.from_rational(7, 2)), 4, "3.5 ceils to 4")
	assert_eq(Fixed.ceil_to_int(Fixed.from_rational(-7, 2)), -3, "-3.5 ceils to -3")


func test_round_to_int_rounds_halves_upward() -> void:
	assert_eq(Fixed.round_to_int(Fixed.from_rational(7, 2)), 4, "3.5 rounds up")
	assert_eq(Fixed.round_to_int(Fixed.from_rational(-7, 2)), -3, "-3.5 rounds up too, by rule")
	assert_eq(Fixed.round_to_int(Fixed.from_rational(5, 4)), 1, "1.25 rounds down")
	assert_eq(Fixed.round_to_int(Fixed.from_rational(7, 4)), 2, "1.75 rounds up")


func test_fractional_part_is_always_non_negative() -> void:
	assert_eq(Fixed.fract(Fixed.from_rational(7, 2)), Fixed.HALF, "3.5 has fraction .5")
	assert_eq(
		Fixed.fract(Fixed.from_rational(-7, 2)),
		Fixed.HALF,
		"-3.5 is -4 + .5, so its fraction is .5"
	)
	assert_eq(Fixed.fract(Fixed.from_int(9)), 0, "a whole number has no fraction")


# ── Addition is plain integer addition, which is the point ───────────────────

func test_values_add_as_integers() -> void:
	var a: int = Fixed.from_rational(1, 4)
	var b: int = Fixed.from_rational(1, 2)
	assert_eq(a + b, Fixed.from_rational(3, 4), "quarter plus half is three quarters")


# ── Multiplication ────────────────────────────────────────────────────────────

func test_multiplying_whole_numbers() -> void:
	assert_eq(Fixed.mul(Fixed.from_int(3), Fixed.from_int(4)), Fixed.from_int(12))
	assert_eq(Fixed.mul(Fixed.from_int(-3), Fixed.from_int(4)), Fixed.from_int(-12))
	assert_eq(Fixed.mul(Fixed.from_int(-3), Fixed.from_int(-4)), Fixed.from_int(12))


func test_multiplying_by_one_is_identity() -> void:
	var value: int = Fixed.from_rational(7, 3)
	assert_eq(Fixed.mul(value, Fixed.ONE), value)


func test_multiplying_by_a_half_halves() -> void:
	assert_eq(Fixed.mul(Fixed.from_int(9), Fixed.HALF), Fixed.from_rational(9, 2))


func test_multiplication_is_commutative() -> void:
	var a: int = Fixed.from_rational(5, 7)
	var b: int = Fixed.from_rational(11, 13)
	assert_eq(Fixed.mul(a, b), Fixed.mul(b, a), "operand order must not matter")


func test_multiplication_floors_rather_than_truncating() -> void:
	# A third of a third is a ninth. 65536 / 9 = 7281.77…, so it floors to 7281.
	var third: int = Fixed.from_rational(1, 3)
	assert_eq(Fixed.mul(third, third), 7281, "positive result floors downward")
	# Negating one operand puts the exact result at -7281.77…, which floors to -7282.
	assert_eq(Fixed.mul(-third, third), -7282, "negative result also floors downward")


# ── Division ──────────────────────────────────────────────────────────────────

func test_dividing_whole_numbers() -> void:
	assert_eq(Fixed.div(Fixed.from_int(12), Fixed.from_int(4)), Fixed.from_int(3))
	assert_eq(Fixed.div(Fixed.from_int(-12), Fixed.from_int(4)), Fixed.from_int(-3))


func test_division_produces_fractions() -> void:
	assert_eq(Fixed.div(Fixed.from_int(1), Fixed.from_int(2)), Fixed.HALF)
	assert_eq(Fixed.div(Fixed.from_int(1), Fixed.from_int(3)), 21845, "one third, floored")


func test_division_inverts_multiplication_for_exact_values() -> void:
	var a: int = Fixed.from_rational(7, 4)
	var b: int = Fixed.from_rational(1, 2)
	assert_eq(Fixed.div(Fixed.mul(a, b), b), a, "exact in binary, so it round-trips")


func test_dividing_by_zero_is_zero() -> void:
	assert_eq(Fixed.div(Fixed.from_int(5), 0), 0, "a zero divisor must not crash the Run")


# ── Square root ───────────────────────────────────────────────────────────────

func test_square_root_of_perfect_squares() -> void:
	assert_eq(Fixed.sqrt(Fixed.from_int(0)), 0)
	assert_eq(Fixed.sqrt(Fixed.from_int(1)), Fixed.from_int(1))
	assert_eq(Fixed.sqrt(Fixed.from_int(4)), Fixed.from_int(2))
	assert_eq(Fixed.sqrt(Fixed.from_int(144)), Fixed.from_int(12))


func test_square_root_of_a_quarter_is_a_half() -> void:
	assert_eq(Fixed.sqrt(Fixed.from_rational(1, 4)), Fixed.HALF)


func test_square_root_floors() -> void:
	# sqrt(2) = 1.41421356…, and 1.41421356… * 65536 = 92681.9…
	assert_eq(Fixed.sqrt(Fixed.from_int(2)), 92681, "root two, floored")


func test_square_root_of_a_negative_is_zero() -> void:
	assert_eq(Fixed.sqrt(Fixed.from_int(-9)), 0, "no imaginary numbers in the Simulation")


## The defining property of a floored integer root, checked against the
## inequality rather than against a recomputation of the algorithm.
func test_integer_square_root_satisfies_its_defining_inequality() -> void:
	var probes: PackedInt64Array = PackedInt64Array([
		0, 1, 2, 3, 4, 5, 8, 9, 10, 15, 16, 17, 99, 100, 101,
		65535, 65536, 65537, 999983, 1073741824, 4611686014132420609,
	])
	for value: int in probes:
		var root: int = Fixed.isqrt(value)
		if not assert_true(root * root <= value, "isqrt(%d) = %d is too large" % [value, root]):
			continue
		assert_true(
			(root + 1) * (root + 1) > value,
			"isqrt(%d) = %d is too small" % [value, root]
		)


# ── Interpolation and bounds ──────────────────────────────────────────────────

func test_lerp_hits_both_endpoints() -> void:
	var a: int = Fixed.from_int(10)
	var b: int = Fixed.from_int(20)
	assert_eq(Fixed.lerp_fixed(a, b, 0), a, "t = 0 gives the start")
	assert_eq(Fixed.lerp_fixed(a, b, Fixed.ONE), b, "t = 1 gives the end")


func test_lerp_midpoint() -> void:
	assert_eq(
		Fixed.lerp_fixed(Fixed.from_int(10), Fixed.from_int(20), Fixed.HALF),
		Fixed.from_int(15)
	)


func test_clamp_bounds_a_value() -> void:
	var low: int = Fixed.from_int(2)
	var high: int = Fixed.from_int(8)
	assert_eq(Fixed.clamp_fixed(Fixed.from_int(5), low, high), Fixed.from_int(5), "inside")
	assert_eq(Fixed.clamp_fixed(Fixed.from_int(1), low, high), low, "below")
	assert_eq(Fixed.clamp_fixed(Fixed.from_int(9), low, high), high, "above")
