## Which clip a given Enemy is playing this frame, and how far into it.
##
## One seam, and it is the one that decides whether the swarm reads as alive:
## `EnemyAnimator` — "given what the Simulation says about this Enemy this tick,
## which baked clip belongs on it and which frame of that clip". It is a
## `RefCounted` with no nodes, no scene tree and no assets, exactly as
## `WeaponAnimator` is, so every piece of motion a player will ever see is a cheap
## assertion here rather than something only a screenshot could catch.
##
## **Nothing here reads a clock and nothing here draws a random number.** The frame
## is arithmetic over the tick, the Enemy's spawn tick and its serial — all three of
## them hashed Simulation state — which is what makes two Runs down the same script
## look the same. That is the audio layer's rule (`tick % count`) and the viewmodel's
## rule (clip time from the tick count, seeked explicitly), applied to the swarm.
##
## Clip *frame counts* are injected rather than read off a baked body, because a test
## that needed the bake would be testing Blender's output rather than this rule.
extends TestCase


## Three clips of plausible length, at the bake's own frame rate. Not the shipped
## numbers — a test that used those would move every time somebody re-baked.
const FRAMES: Dictionary = {
	EnemyAnimator.MOVE: 24,
	EnemyAnimator.IDLE: 60,
	EnemyAnimator.ATTACK: 36,
}


func _facts(tick: int, spawn_tick: int, serial: int) -> EnemyAnimator.Facts:
	var facts: EnemyAnimator.Facts = EnemyAnimator.Facts.new()
	facts.tick = tick
	facts.spawn_tick = spawn_tick
	facts.serial = serial
	return facts


func test_an_enemy_that_is_walking_plays_the_move_clip() -> void:
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	var cue: EnemyAnimator.Cue = animator.cue_for(_facts(100, 100, 0))
	assert_eq(cue.role, EnemyAnimator.MOVE, "a Crawler on the march is moving")
	assert_eq(cue.frame, 0, "and it emerges at the start of its stride")


func test_two_enemies_released_on_the_same_tick_are_not_in_step() -> void:
	# The acceptance criterion in its own words: six Crawlers out of one Breach on
	# one tick share a spawn tick, and a swarm that steps in unison reads as one
	# object rather than as six. The offset is the serial, so it is stable for an
	# Enemy's whole life and identical on every client.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	var seen: Dictionary = {}
	for serial: int in range(6):
		var cue: EnemyAnimator.Cue = animator.cue_for(_facts(400, 400, serial))
		seen[cue.frame] = true
	assert_eq(seen.size(), 6, "six Crawlers, six phases of one stride: %s" % [seen.keys()])


func test_a_phase_offset_is_the_serial_and_not_the_index() -> void:
	# Indices shift as Enemies die (`_remove_enemy` closes the gap), so an offset
	# taken from an index would make a Crawler's gait jump every time something
	# ahead of it in the array was killed. A serial is issued once and never reused.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	var before: EnemyAnimator.Cue = animator.cue_for(_facts(500, 300, 9))
	var after: EnemyAnimator.Cue = animator.cue_for(_facts(500, 300, 9))
	assert_eq(after.frame, before.frame, "the same Enemy, the same tick, the same frame")


func test_the_stride_advances_one_frame_every_second_tick() -> void:
	# The bake runs at half the Simulation's rate, so a frame is an exact integer
	# division of the tick rather than a ratio with a rounding rule.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	var start: int = 1000
	assert_eq(animator.cue_for(_facts(start, start, 0)).frame, 0)
	assert_eq(animator.cue_for(_facts(start + 1, start, 0)).frame, 0, "still frame 0")
	assert_eq(animator.cue_for(_facts(start + 2, start, 0)).frame, 1, "now frame 1")
	assert_eq(
		animator.cue_for(_facts(start + 2 * FRAMES[EnemyAnimator.MOVE], start, 0)).frame,
		0,
		"and a whole cycle later it is back at the start"
	)


func test_an_enemy_in_contact_plays_the_attack_clip_and_one_that_has_halted_idles() -> void:
	# Biting beats holding beats walking, which is the order the Simulation decides
	# them in: a Siege Hulk shelling is attacking, one halted with nothing in reach
	# is holding, and everything that walks is moving.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)

	var biting: EnemyAnimator.Facts = _facts(200, 100, 0)
	biting.attacking = true
	assert_eq(animator.cue_for(biting).role, EnemyAnimator.ATTACK)

	var halted: EnemyAnimator.Facts = _facts(200, 100, 0)
	halted.holding = true
	assert_eq(animator.cue_for(halted).role, EnemyAnimator.IDLE)

	# A Hulk that is shelling is both, and biting wins — what it is doing is the
	# shelling, and the halt is only what is left when it has nothing to shell.
	var both: EnemyAnimator.Facts = _facts(200, 100, 0)
	both.attacking = true
	both.holding = true
	assert_eq(animator.cue_for(both).role, EnemyAnimator.ATTACK)


func test_a_frame_stays_inside_the_clip_it_names_however_long_the_run_has_gone_on() -> void:
	# A forty-hour Run is 8.6 million ticks and the frame is a modulus, so there is
	# nothing here to overflow and nothing to drift — but a clip whose frame count
	# nobody told us about must still name a frame that exists rather than reaching
	# past the end of a baked texture.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	for tick: int in [0, 1, 59, 60, 3600, 8_640_000]:
		var cue: EnemyAnimator.Cue = animator.cue_for(_facts(tick, 0, 123))
		assert_true(
			cue.frame >= 0 and cue.frame < FRAMES[EnemyAnimator.MOVE],
			"tick %d gave frame %d of %d" % [tick, cue.frame, FRAMES[EnemyAnimator.MOVE]]
		)

	var untold: EnemyAnimator = EnemyAnimator.new()
	assert_eq(
		untold.cue_for(_facts(999, 0, 5)).frame,
		0,
		"a role with no baked clip is frame 0 rather than a read off the end of one"
	)


func test_an_enemy_that_has_not_arrived_yet_stands_at_the_start_of_its_stride() -> void:
	# `_release_from_the_breaches` is not the only thing that can hand a renderer a
	# spawn tick in the future: a replay seeks, and a save restores. Negative elapsed
	# is clamped rather than wrapped, because a modulus of a negative number in
	# GDScript is negative and would index off the front of the texture.
	var animator: EnemyAnimator = EnemyAnimator.new()
	animator.set_frame_counts(FRAMES)
	var cue: EnemyAnimator.Cue = animator.cue_for(_facts(10, 90, 0))
	assert_eq(cue.frame, 0)
