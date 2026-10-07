## The hash contract.
##
## The determinism harness compares Simulations by hash, so a hash that misses a
## difference silently defeats the whole guarantee. These tests are mostly about
## sensitivity: every byte fed must be capable of changing the digest, and order
## must matter.
extends TestCase


func _fed(values: Array) -> int:
	var hasher: StateHasher = StateHasher.new()
	for value: Variant in values:
		if value is bool:
			hasher.feed_bool(value)
		else:
			hasher.feed_int(value)
	return hasher.digest()


func test_an_empty_hasher_has_a_stable_nonzero_digest() -> void:
	var first: int = StateHasher.new().digest()
	var second: int = StateHasher.new().digest()
	assert_eq(first, second, "the empty digest must be reproducible")
	assert_ne(first, 0, "a zero digest would collide with a cleared field")


func test_identical_input_gives_an_identical_digest() -> void:
	assert_eq(_fed([1, 2, 3, -4]), _fed([1, 2, 3, -4]))


func test_different_input_gives_a_different_digest() -> void:
	assert_ne(_fed([1, 2, 3]), _fed([1, 2, 4]))


func test_order_changes_the_digest() -> void:
	assert_ne(_fed([1, 2]), _fed([2, 1]), "an unordered iteration must not hash the same")


func test_length_changes_the_digest() -> void:
	assert_ne(_fed([1, 2]), _fed([1, 2, 0]), "a trailing zero is still a field")


func test_a_single_bit_anywhere_in_a_value_changes_the_digest() -> void:
	# Every byte of a 64-bit value must reach the digest, including the top one.
	for bit: int in range(63):
		var changed: int = 1 << bit
		if not assert_ne(_fed([0]), _fed([changed]), "bit %d is not hashed" % bit):
			return


func test_sign_changes_the_digest() -> void:
	assert_ne(_fed([5]), _fed([-5]), "negative values must hash distinctly")


func test_booleans_are_distinguished() -> void:
	assert_ne(_fed([true]), _fed([false]))


func test_the_digest_is_a_non_negative_sixty_three_bit_value() -> void:
	# Negative or oversized digests make logs and save files awkward, and a digest
	# that overflowed would depend on wrap-around behaviour.
	for i: int in range(200):
		var digest: int = _fed([i, i * 7919, -i])
		if not assert_true(
			digest >= 0 and digest <= 0x7FFFFFFFFFFFFFFF,
			"digest out of range for input %d: %d" % [i, digest]
		):
			return


func test_many_distinct_inputs_produce_distinct_digests() -> void:
	# Not a proof of collision resistance, but a lane that had collapsed to
	# something near-constant would show up here immediately.
	var seen: Dictionary = {}
	for i: int in range(4000):
		seen[_fed([i])] = true
	assert_eq(seen.size(), 4000, "collision among 4000 small integers")


func test_feeding_an_array_matches_feeding_its_elements() -> void:
	var packed: StateHasher = StateHasher.new()
	packed.feed_ints(PackedInt64Array([7, 8, 9]))

	var one_by_one: StateHasher = StateHasher.new()
	one_by_one.feed_int(3)
	one_by_one.feed_int(7)
	one_by_one.feed_int(8)
	one_by_one.feed_int(9)

	assert_eq(
		packed.digest(),
		one_by_one.digest(),
		"feed_ints must hash the length then the elements"
	)


func test_feeding_an_array_is_sensitive_to_element_order() -> void:
	var forward: StateHasher = StateHasher.new()
	forward.feed_ints(PackedInt64Array([1, 2, 3]))
	var backward: StateHasher = StateHasher.new()
	backward.feed_ints(PackedInt64Array([3, 2, 1]))
	assert_ne(forward.digest(), backward.digest())


func test_digest_does_not_consume_the_hasher() -> void:
	var hasher: StateHasher = StateHasher.new()
	hasher.feed_int(42)
	assert_eq(hasher.digest(), hasher.digest(), "digest must be a pure read")
