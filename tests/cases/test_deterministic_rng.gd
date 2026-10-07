## The seeded random stream contract.
##
## These assert reproducibility properties rather than specific outputs, because
## what the Simulation needs from randomness is not a particular sequence but the
## guarantee that the sequence is the same everywhere. The one pinned-value test
## exists to catch an accidental change to the algorithm, which would silently
## invalidate every recorded replay fixture in the repo.
extends TestCase


func test_the_same_seed_gives_the_same_sequence() -> void:
	var a: DeterministicRng = DeterministicRng.new(12345)
	var b: DeterministicRng = DeterministicRng.new(12345)
	for i: int in range(64):
		if not assert_eq(a.next_uint32(), b.next_uint32(), "draw %d must match" % i):
			return


func test_different_seeds_give_different_sequences() -> void:
	var a: DeterministicRng = DeterministicRng.new(1)
	var b: DeterministicRng = DeterministicRng.new(2)
	var differences: int = 0
	for i: int in range(32):
		if a.next_uint32() != b.next_uint32():
			differences += 1
	assert_true(differences > 24, "expected mostly different draws, got %d of 32" % differences)


func test_draws_stay_inside_thirty_two_bits() -> void:
	var rng: DeterministicRng = DeterministicRng.new(99)
	for i: int in range(256):
		var value: int = rng.next_uint32()
		if not assert_true(value >= 0 and value <= 0xFFFFFFFF, "draw %d out of range: %d" % [i, value]):
			return


func test_the_stream_does_not_stall() -> void:
	var rng: DeterministicRng = DeterministicRng.new(7)
	var previous: int = rng.next_uint32()
	var repeats: int = 0
	for i: int in range(128):
		var value: int = rng.next_uint32()
		if value == previous:
			repeats += 1
		previous = value
	assert_eq(repeats, 0, "consecutive identical draws suggest a degenerate generator")


# ── Bounded draws ─────────────────────────────────────────────────────────────

func test_bounded_draws_stay_below_the_bound() -> void:
	var rng: DeterministicRng = DeterministicRng.new(4242)
	for i: int in range(512):
		var value: int = rng.next_below(10)
		if not assert_true(value >= 0 and value < 10, "draw %d out of range: %d" % [i, value]):
			return


func test_bounded_draws_reach_every_value() -> void:
	var rng: DeterministicRng = DeterministicRng.new(8080)
	var seen: Dictionary = {}
	for i: int in range(1000):
		seen[rng.next_below(6)] = true
	assert_eq(seen.size(), 6, "a six-sided draw should produce all six values in 1000 rolls")


func test_a_bound_of_one_always_gives_zero() -> void:
	var rng: DeterministicRng = DeterministicRng.new(5)
	assert_eq(rng.next_below(1), 0)


func test_a_nonsensical_bound_gives_zero() -> void:
	var rng: DeterministicRng = DeterministicRng.new(5)
	assert_eq(rng.next_below(0), 0, "a zero bound must not hang or crash")
	assert_eq(rng.next_below(-3), 0, "a negative bound must not hang or crash")


func test_range_draws_stay_within_bounds() -> void:
	var rng: DeterministicRng = DeterministicRng.new(31337)
	for i: int in range(512):
		var value: int = rng.next_range(-5, 5)
		if not assert_true(value >= -5 and value <= 5, "draw %d out of range: %d" % [i, value]):
			return


# ── Fixed-point draws ─────────────────────────────────────────────────────────

func test_fixed_draws_fall_in_the_unit_interval() -> void:
	var rng: DeterministicRng = DeterministicRng.new(2024)
	for i: int in range(512):
		var value: int = rng.next_fixed()
		if not assert_true(
			value >= 0 and value < Fixed.ONE,
			"draw %d outside [0, ONE): %d" % [i, value]
		):
			return


# ── State, for saving and hashing ─────────────────────────────────────────────

func test_restoring_state_resumes_the_same_stream() -> void:
	var rng: DeterministicRng = DeterministicRng.new(555)
	for i: int in range(10):
		rng.next_uint32()

	var checkpoint: int = rng.state
	var expected: PackedInt64Array = PackedInt64Array()
	for i: int in range(8):
		expected.append(rng.next_uint32())

	var resumed: DeterministicRng = DeterministicRng.new(0)
	resumed.state = checkpoint
	var actual: PackedInt64Array = PackedInt64Array()
	for i: int in range(8):
		actual.append(resumed.next_uint32())

	assert_eq(actual, expected, "state is the whole of the generator's memory")


func test_state_advances_with_every_draw() -> void:
	var rng: DeterministicRng = DeterministicRng.new(17)
	var before: int = rng.state
	rng.next_uint32()
	assert_ne(rng.state, before, "a draw must consume state, or replays would not line up")


## Pinned regression vector. These numbers are not derived from first principles;
## they were captured from this generator and are frozen deliberately. If a change
## to the algorithm makes this fail, that is the point — every recorded replay
## fixture in the repo depends on this exact stream, so the change must be a
## conscious decision with the fixtures regenerated.
func test_the_stream_is_pinned() -> void:
	var rng: DeterministicRng = DeterministicRng.new(1)
	var drawn: PackedInt64Array = PackedInt64Array()
	for i: int in range(6):
		drawn.append(rng.next_uint32())
	assert_eq(drawn, PINNED_SEED_ONE)


const PINNED_SEED_ONE: Array = [
	450641110, 3948090984, 1005257433, 1979191175, 4147702564, 122435621,
]
