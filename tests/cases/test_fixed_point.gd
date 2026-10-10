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


# ── Parsing decimals from content files ───────────────────────────────────────
# Tuning files and Recipe tables are written by a human in decimal. The crossing
# from that text into a Simulation quantity has to be exact and float-free, so it
# gets the same scrutiny as the arithmetic.

func test_a_whole_decimal_string_parses_exactly() -> void:
	assert_eq(Fixed.from_decimal_string("4"), 4 * 65536)
	assert_eq(Fixed.from_decimal_string("0"), 0)


func test_a_dyadic_decimal_string_parses_exactly() -> void:
	# 1.5 and 0.25 are exactly representable in 16 fractional bits.
	assert_eq(Fixed.from_decimal_string("1.5"), 98304)
	assert_eq(Fixed.from_decimal_string("0.25"), 16384)


func test_a_repeating_decimal_string_floors() -> void:
	# 3.2 is 16/5, so 3.2 * 65536 is 1048576/5 = 209715.2, which floors to 209715.
	assert_eq(Fixed.from_decimal_string("3.2"), 209715)


func test_a_negative_decimal_string_floors_toward_negative_infinity() -> void:
	# -3.2 * 65536 is -209715.2. Flooring is sign-independent, so this is -209716,
	# one unit below the negation of 3.2 — the documented rounding rule, applied
	# without exception.
	assert_eq(Fixed.from_decimal_string("-3.2"), -209716)
	assert_eq(Fixed.from_decimal_string("-1.5"), -98304)


func test_a_leading_plus_is_accepted() -> void:
	assert_eq(Fixed.from_decimal_string("+2.5"), 163840)


func test_surrounding_whitespace_is_ignored() -> void:
	assert_eq(Fixed.from_decimal_string("  1.5  "), 98304)


func test_decimal_strings_are_recognised_before_they_are_parsed() -> void:
	# The recogniser exists so a loader can reject junk by name rather than have a
	# typo silently parse as zero.
	assert_true(Fixed.is_decimal_string("12"))
	assert_true(Fixed.is_decimal_string("-0.125"))
	assert_true(Fixed.is_decimal_string("+7.0"))
	assert_false(Fixed.is_decimal_string(""))
	assert_false(Fixed.is_decimal_string("1.2.3"))
	assert_false(Fixed.is_decimal_string("1,5"))
	assert_false(Fixed.is_decimal_string("fast"))
	assert_false(Fixed.is_decimal_string("1."))
	assert_false(Fixed.is_decimal_string(".5"))
	assert_false(Fixed.is_decimal_string("-"))
	assert_false(Fixed.is_decimal_string("1 5"))


# ── Smooth interpolation ──────────────────────────────────────────────────────

func test_smoothstep_is_flat_at_both_ends_and_half_in_the_middle() -> void:
	assert_eq(Fixed.smoothstep_fixed(0), 0)
	assert_eq(Fixed.smoothstep_fixed(Fixed.ONE), Fixed.ONE)
	assert_eq(Fixed.smoothstep_fixed(Fixed.HALF), Fixed.HALF, "symmetric about the middle")


func test_smoothstep_starts_slower_than_a_straight_line() -> void:
	# At a quarter of the way through, t²(3 - 2t) is 0.0625 × 2.5 = 0.15625, which is
	# 10240 in 16 fractional bits — well short of the 16384 a straight line gives.
	assert_eq(Fixed.smoothstep_fixed(Fixed.QUARTER_TURN), 10240)


func test_smoothstep_clamps_outside_its_range() -> void:
	assert_eq(Fixed.smoothstep_fixed(-Fixed.ONE), 0, "nothing before the start")
	assert_eq(Fixed.smoothstep_fixed(Fixed.from_int(4)), Fixed.ONE, "nothing after the end")


# ── Trigonometry ──────────────────────────────────────────────────────────────
# Angles are measured in *turns*, so one full revolution is Fixed.ONE and the
# quadrant boundaries are exact values a reader can check by eye. Expected values
# come from the mathematics, not from the table: sin(0) is 0, sin(quarter turn) is
# 1, sin(eighth turn) is the square root of a half.

func test_a_turn_is_one_whole_revolution() -> void:
	assert_eq(Fixed.TURN, Fixed.ONE, "a full revolution is 1.0 turns")
	assert_eq(Fixed.QUARTER_TURN, 16384, "a quarter of 65536")


func test_sine_is_exact_at_the_quadrant_boundaries() -> void:
	assert_eq(Fixed.sin_turns(0), 0)
	assert_eq(Fixed.sin_turns(Fixed.QUARTER_TURN), Fixed.ONE, "sin 90 degrees is 1")
	assert_eq(Fixed.sin_turns(Fixed.HALF), 0, "sin 180 degrees is 0")
	assert_eq(Fixed.sin_turns(3 * Fixed.QUARTER_TURN), -Fixed.ONE, "sin 270 degrees is -1")


func test_cosine_is_exact_at_the_quadrant_boundaries() -> void:
	assert_eq(Fixed.cos_turns(0), Fixed.ONE)
	assert_eq(Fixed.cos_turns(Fixed.QUARTER_TURN), 0)
	assert_eq(Fixed.cos_turns(Fixed.HALF), -Fixed.ONE)
	assert_eq(Fixed.cos_turns(3 * Fixed.QUARTER_TURN), 0)


func test_sine_of_an_eighth_turn_is_the_root_of_a_half() -> void:
	# sin 45 degrees is 0.7071067811..., which is 46341 in 16 fractional bits.
	assert_eq(Fixed.sin_turns(Fixed.ONE / 8), 46341)
	assert_eq(Fixed.cos_turns(Fixed.ONE / 8), 46341, "at 45 degrees the two agree")


func test_sine_is_accurate_between_the_sampled_angles() -> void:
	# A twelfth of a turn is 30 degrees, where sine is exactly a half. The angle
	# falls between two table entries, so this is the interpolation being measured
	# rather than a stored value being read back.
	var thirty_degrees: int = Fixed.ONE / 12
	assert_true(
		absi(Fixed.sin_turns(thirty_degrees) - Fixed.HALF) <= Fixed.SIN_TOLERANCE,
		"sin 30 degrees should be 0.5, got %d" % Fixed.sin_turns(thirty_degrees)
	)
	# And 60 degrees, where it is 0.8660254... = 56755.
	assert_true(
		absi(Fixed.sin_turns(Fixed.ONE / 6) - 56755) <= Fixed.SIN_TOLERANCE,
		"sin 60 degrees should be 56755, got %d" % Fixed.sin_turns(Fixed.ONE / 6)
	)


func test_angles_wrap_so_a_player_may_spin_forever() -> void:
	# Yaw accumulates without bound as a player turns, so every angle has to be
	# reducible. Three and a quarter turns is a quarter turn.
	assert_eq(Fixed.sin_turns(3 * Fixed.TURN + Fixed.QUARTER_TURN), Fixed.ONE)
	assert_eq(Fixed.sin_turns(-Fixed.QUARTER_TURN), -Fixed.ONE, "and backwards too")
	assert_eq(Fixed.wrap_turns(3 * Fixed.TURN + Fixed.QUARTER_TURN), Fixed.QUARTER_TURN)
	assert_eq(Fixed.wrap_turns(-Fixed.QUARTER_TURN), 3 * Fixed.QUARTER_TURN)


func test_the_facing_vector_stays_very_nearly_unit_length() -> void:
	# Walking speed is the length of this vector times the tuned speed, so a
	# facing that is short in some directions would make a player faster when
	# facing north than when facing north-east. Checked at an awkward angle.
	var angle: int = Fixed.ONE / 7
	var length: int = Fixed.sqrt(
		Fixed.mul(Fixed.sin_turns(angle), Fixed.sin_turns(angle))
		+ Fixed.mul(Fixed.cos_turns(angle), Fixed.cos_turns(angle))
	)
	assert_true(
		absi(length - Fixed.ONE) <= Fixed.SIN_TOLERANCE,
		"expected unit length, got %d" % length
	)
