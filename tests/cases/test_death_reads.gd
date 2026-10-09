## What dying looks like, and what it still costs.
##
## #54's complaint was the player's own: *"when the player dies its not fleshed out"*. You
## stood bolt upright at full eye height, one line of small type appeared in the gear block
## of the HUD, and the only thing in the whole game that acknowledged the most consequential
## event in a Run was the weapon dropping out of frame.
##
## This file stands behind four claims, and the first two are the ones that make the rest
## safe:
##
## * **The gesture costs nothing.** `player.respawn_delay_seconds` is the entire price of
##   dying (GLOSSARY.md, DESIGN.md), and `_respawn` touches position, health and the clock
##   and nothing else. So the collapse has to be unable to lengthen the wait *by
##   construction* rather than by its tuned length happening to be shorter — which is why
##   `test_the_collapse_cannot_lengthen_the_wait_however_long_it_is_tuned` sets it to
##   a hundred seconds against an eight-second respawn and asserts the clock does not care.
## * **Everything new is a projection.** Three queries were added and not one byte of state,
##   so asking any of them leaves `hash()` exactly where it was and a Run that is watched is
##   the Run that would have happened unwatched. Asserted both ways: the hash does not move
##   for being asked, and no property of the Simulation mentions the collapse at all.
## * **A Downed player and a dead one are distinguishable by the view alone**, because what
##   a player should do about the two is different: one is waiting for a teammate and the
##   other for a clock. That is a posture rather than a line of text.
## * **A solo death makes a noise.** It did not, and that is a bug this ticket found rather
##   than a feature it added — `PLAYER_DOWN` fired on `query_player_is_downed`, which is
##   **never true on a solo Run** (GLOSSARY.md), so the thud #54's own description credits
##   the game with had never once played.
##
## What this file deliberately cannot say is whether any of it *reads as dying*. That is
## `tools/visual/compose_death_shot.gd` and a pair of committed images, and in the end it is
## a question for somebody who has died in the game.
extends TestCase

# ── The fixture ───────────────────────────────────────────────────────────────
#
# A player who can be killed in two bites by a Crawler walking straight over where they are
# standing, which is `test_gear.gd`'s `_hunted_sim` — the Breach two tiles south, the Nest
# four tiles north, so the only way from one to the other is through the player. Borrowed
# rather than generalised: these are two files asking different questions of the same
# geography, and a shared helper would make each of them harder to read on its own.
#
# The content comes through `ContentFixture` (#51), so every number not named here is the
# number the game ships and a key added to `content/tuning.toml` costs this file nothing.

const GROUND: int = WorldGrid.GROUND_LAYER

## One Crawler a Breach and never any more, so there is exactly one thing coming.
const ONE_CRAWLER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

## A Delivery tier the player can pay off by hand, so that what a death does to the counter
## is observable. One plate, out of the opening bill.
const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_munitions,Munitions Licence,1,iron_plate:4,,mg_drum_magazine,
"""

## Twenty hit points, so a test about mortality is not a test about patience: a Crawler
## bites ten a second.
const FRAGILE: Array = [["health = 150", "health = 20"]]

## A Telegraph short enough to live inside a test.
const QUICK_TELEGRAPH: Array = [["telegraph_seconds = 12", "telegraph_seconds = 0.5"]]

## Ticks to allow for a Crawler to cross two tiles and bite twice. Generous: the assertion
## is that it happened, and `_step_until` reports -1 rather than hanging if it did not.
const TICKS_TO_DIE: int = 2400


func _fixture(overrides: Array = []) -> ContentFixture:
	var substitutions: Array = []
	substitutions.append_array(FRAGILE)
	substitutions.append_array(QUICK_TELEGRAPH)
	substitutions.append_array(overrides)
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = ONE_CRAWLER
	fixture.deliveries = DELIVERIES
	return fixture.tune(substitutions)


func _content(overrides: Array = []) -> Definitions:
	return _fixture(overrides).definitions()


## The Map: one Breach two tiles south of where a Run starts the player, and the Nest four
## tiles north of them. Far enough north that the Crawler reaches the player *first* — an
## Enemy stops the moment it has anything at all to bite.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, GROUND, 4)
	layout.add_node(Vector3i(14, GROUND, 6), "iron_ore", 1)
	layout.add_breach(Vector3i(0, GROUND, -2))
	layout.sort_breaches()
	layout.sort_nodes()
	return layout


func _sim(players: int = 1, overrides: Array = []) -> Simulation:
	var sim: Simulation = Simulation.new(11, players, _content(overrides), _layout())
	sim.step([InputAction.call_wave_early(0)])
	return sim


func _step(sim: Simulation, ticks: int) -> void:
	for i: int in range(ticks):
		sim.step([])


## Steps until `predicate` holds and reports how many ticks that took, or -1 if it never did
## inside `limit`. Bounded, so a broken Simulation fails rather than hangs.
func _step_until(sim: Simulation, limit: int, predicate: Callable) -> int:
	for tick: int in range(limit):
		if predicate.call():
			return tick
		sim.step([])
	return -1 if not predicate.call() else limit


## Steps until the player has left their feet, and asserts that they did.
func _kill(sim: Simulation) -> int:
	var ticks: int = _step_until(
		sim, TICKS_TO_DIE, func() -> bool: return not sim.query_player_is_alive(0)
	)
	assert_true(ticks != -1, "a Crawler walked over the player and took twenty hit points")
	return ticks


func _blend(sim: Simulation) -> float:
	return Fixed.to_float(sim.query_player_collapse_blend(0))


func _drop(sim: Simulation) -> float:
	return Fixed.to_float(sim.query_player_view_collapse_metres(0))


## The directors this file has built, freed in `after_each`.
##
## `AudioDirector` is a `Node3D`, so one left behind is a leaked `ObjectDB` instance the
## runner reports at exit — the arrangement `test_game_audio.gd` already has, borrowed
## rather than reinvented.
var _directors: Array[AudioDirector] = []


func after_each() -> void:
	for director: AudioDirector in _directors:
		director.free()
	_directors.clear()


## A director that has already seen this Run, so the next `cues_for_frame` reports changes
## rather than the whole world arriving at once.
func _primed(sim: Simulation) -> AudioDirector:
	var director: AudioDirector = AudioDirector.new()
	_directors.append(director)
	director.cues_for_frame(sim)
	return director


func _roll(sim: Simulation) -> float:
	return Fixed.to_float(sim.query_player_view_collapse_roll_turns(0))


# ── The collapse: a body goes over ────────────────────────────────────────────

func test_a_run_opens_on_its_feet_rather_than_getting_up_off_the_floor() -> void:
	# The fact that says so is `_player_life_since_tick` being 0 at construction: a player
	# cannot have got up on tick 0, because nothing had happened to them yet. Without that
	# clause the rise plays itself on the opening half-second of every Run.
	var sim: Simulation = _sim()
	assert_eq(sim.query_player_collapse_blend(0), 0, "standing, on the first tick")
	assert_eq(sim.query_player_view_collapse_metres(0), 0, "and the view has not fallen")
	assert_eq(sim.query_player_view_collapse_roll_turns(0), 0, "and has not banked")

	_step(sim, 60)
	assert_eq(sim.query_player_collapse_blend(0), 0, "nor a second later")


func test_a_killed_player_goes_over_and_settles_on_the_deck() -> void:
	var sim: Simulation = _sim()
	_kill(sim)
	assert_true(sim.query_player_is_dead(0), "solo play has no Downed state (GLOSSARY.md)")

	# `player.collapse_seconds` is 0.45, which `_seconds_in_ticks` rounds to 27 ticks. One
	# tick in, the body has barely begun; the gesture is eased, so most of the fall is in
	# the middle of it.
	var opening: float = _blend(sim)
	assert_true(opening > 0.0, "the fall has begun on the tick after the bite")
	assert_true(opening < 0.1, "but it has barely begun: eased, not snapped (%f)" % opening)

	_step(sim, 13)
	var halfway: float = _blend(sim)
	assert_true(
		halfway > 0.35 and halfway < 0.65,
		"about half over, half way through the gesture (%f)" % halfway
	)

	_step(sim, 14)
	assert_eq(
		sim.query_player_collapse_blend(0),
		Fixed.ONE,
		"and all the way over by the end of it, exactly rather than nearly"
	)

	# `death_view_drop_metres` is 1.42 against a 1.7 m eye height — a head on the floor.
	# Quoted from the key rather than from a second copy of its number.
	var definitions: Definitions = sim.query_definitions()
	assert_eq(
		sim.query_player_view_collapse_metres(0),
		definitions.player_death_view_drop,
		"the drop is the whole of player.death_view_drop_metres"
	)
	assert_true(_drop(sim) > 1.4, "which is well over a metre (%f)" % _drop(sim))


func test_the_view_banks_over_as_it_falls_and_the_list_is_proportional_to_the_drop() -> void:
	# One key, `collapse_roll_degrees`, scaled by the same blend as the drop — so a body that
	# goes over further lists further, out of one number rather than two that can disagree.
	var sim: Simulation = _sim()
	_kill(sim)
	assert_true(_roll(sim) > 0.0, "the view has begun to bank on the way down")

	_step(sim, 40)
	var definitions: Definitions = sim.query_definitions()
	# 20 degrees is 20/360 of a turn. Positive banks to the player's right, which is the sign
	# convention `query_player_view_roll_turns` already uses.
	assert_eq(
		sim.query_player_view_collapse_roll_turns(0),
		Fixed.div(definitions.player_collapse_roll_degrees, Fixed.from_int(360)),
		"settled at the whole of player.collapse_roll_degrees, in turns"
	)
	assert_true(_roll(sim) > 0.0, "and it banks one way rather than the other")


func test_a_downed_player_is_propped_up_and_a_dead_one_is_not() -> void:
	# **The acceptance criterion that is about co-op**, and the reason the two postures are
	# two keys: what a player should do about the two states is different, so a player
	# looking at the screen has to be able to tell them apart without reading a word.
	var pair: Simulation = _sim(2)
	_kill(pair)
	assert_true(pair.query_player_is_downed(0), "with a teammate on the Map, they go down")

	_step(pair, 40)
	var downed_drop: float = _drop(pair)
	var downed_roll: float = _roll(pair)

	var solo: Simulation = _sim()
	_kill(solo)
	assert_true(solo.query_player_is_dead(0))
	_step(solo, 40)

	assert_true(
		downed_drop > 0.0,
		"a Downed player has gone over too — they are at zero health on the ground"
	)
	assert_true(
		downed_drop < _drop(solo),
		"but not as far: propped on an elbow against a head on the deck (%f against %f)"
		% [downed_drop, _drop(solo)]
	)
	# The roll is the drop's own fraction, so the shallower posture lists less **for free**
	# rather than out of a second key somebody has to keep in step with the first.
	assert_true(
		downed_roll > 0.0 and downed_roll < _roll(solo),
		"and the list comes out proportionally smaller with it (%f against %f)"
		% [downed_roll, _roll(solo)]
	)
	# Stated against the two keys, so a tuner who moves either can see what this test means.
	# Stated against the key, within a unit of fixed point: the Downed fall is the death
	# fall's own fraction, so it is a divide and a multiply and each of them floors.
	var definitions: Definitions = pair.query_definitions()
	assert_true(
		absi(pair.query_player_view_collapse_metres(0) - definitions.player_downed_view_drop) <= 1,
		"a Downed player's eye falls player.downed_view_drop_metres and no further: %d against %d"
		% [pair.query_player_view_collapse_metres(0), definitions.player_downed_view_drop]
	)


func test_a_downed_player_who_bleeds_out_goes_the_rest_of_the_way_down() -> void:
	# `_lives` restamps `_player_life_since_tick` when a Downed player dies, so the gesture
	# plays again from where it is — the elbow gives way. That falls out of the blend being a
	# function of the state and the tick it began, rather than being a case anybody wrote.
	var sim: Simulation = _sim(2)
	_kill(sim)
	_step(sim, 40)
	var propped: int = sim.query_player_collapse_blend(0)
	assert_true(propped < Fixed.ONE, "propped up, not flat")

	var died: int = _step_until(
		sim, 2400, func() -> bool: return sim.query_player_is_dead(0)
	)
	assert_true(died != -1, "and they bled out: twenty seconds of it")
	_step(sim, 40)
	assert_eq(
		sim.query_player_collapse_blend(0),
		Fixed.ONE,
		"the elbow gave way and the rest of the fall happened"
	)


func test_the_same_gesture_runs_backwards_when_a_player_gets_up() -> void:
	# **The one acknowledgement that a respawn happened.** Before #54 a player appeared on
	# the Nest's crown mid-stride with nothing on either side of the cut. It adds no state and
	# no tuning key: a player who is alive and has been for less than the gesture's length is
	# one rising off the deck.
	var sim: Simulation = _sim()
	_kill(sim)
	var back: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_player_is_alive(0)
	)
	assert_true(back != -1, "they came back")

	var rising: float = _blend(sim)
	assert_true(
		rising > 0.9,
		"and they are still on the floor on the tick they came back (%f)" % rising
	)
	# **Alive and in control throughout**, which is what keeps this out of the price of dying:
	# the player can walk, look and build while the view comes up.
	assert_true(sim.query_player_is_alive(0), "on their feet as far as every refusal is concerned")

	_step(sim, 13)
	var halfway: float = _blend(sim)
	assert_true(
		halfway > 0.2 and halfway < 0.8, "coming up through the middle of it (%f)" % halfway
	)

	_step(sim, 14)
	assert_eq(sim.query_player_collapse_blend(0), 0, "and upright, exactly")
	assert_eq(sim.query_player_view_collapse_metres(0), 0)
	assert_eq(sim.query_player_view_collapse_roll_turns(0), 0)


# ── It costs nothing ──────────────────────────────────────────────────────────

func test_the_collapse_cannot_lengthen_the_wait_however_long_it_is_tuned() -> void:
	# **The hard constraint, asserted by construction rather than by arithmetic.** It would
	# be easy to write a test that passed only because 0.45 s happens to be shorter than 8 s;
	# this one tunes the gesture to a hundred seconds — twelve times the respawn — and
	# asserts the clock is not interested. `_lives` reads `_respawn_ticks` and has never heard
	# of the collapse, and this is what would notice if that ever stopped being true.
	var absurd: Simulation = _sim(1, [["collapse_seconds = 0.45", "collapse_seconds = 100"]])
	_kill(absurd)
	assert_eq(
		absurd.query_player_respawn_ticks_remaining(0),
		479,
		"player.respawn_delay_seconds is 8, less the tick they died on"
	)
	var back: int = _step_until(
		absurd, 1200, func() -> bool: return absurd.query_player_is_alive(0)
	)
	assert_eq(back, 480, "and they come back to the tick, with the fall still in progress")
	assert_true(
		absurd.query_player_collapse_blend(0) > 0,
		"the gesture is still running, and nobody is waiting for it"
	)


func test_the_wait_is_the_same_whether_the_gesture_is_on_or_off() -> void:
	# The same claim from the other end, and the cheap one: two Runs identical but for the
	# collapse come back on the same tick.
	var shipped: Simulation = _sim()
	var still: Simulation = _sim(
		1, [["death_view_drop_metres = 1.42", "death_view_drop_metres = 0"]]
	)
	_kill(shipped)
	_kill(still)
	var shipped_back: int = _step_until(
		shipped, 1200, func() -> bool: return shipped.query_player_is_alive(0)
	)
	var still_back: int = _step_until(
		still, 1200, func() -> bool: return still.query_player_is_alive(0)
	)
	assert_eq(shipped_back, 480)
	assert_eq(still_back, shipped_back, "the gesture is not part of what dying costs")


func test_a_death_leaves_the_stock_the_components_and_the_delivery_counter_alone() -> void:
	# **#54's own acceptance criterion**, and the one GLOSSARY.md and DESIGN.md both insist
	# on: death costs tempo and nothing else. `_respawn` touches position, health and the
	# clock, and there is nowhere in it for a penalty to be added without somebody arguing
	# for it first. This is that sentence as a test.
	var sim: Simulation = _sim()
	var definitions: Definitions = sim.query_definitions()

	# Fit a component and pay part of a Delivery tier, so there is something to lose.
	var component: GearDefinition = definitions.gear("heavy_barrel")
	sim.step([
		InputAction.fit_component(
			0,
			definitions.gear_slot_index(component.slot_id()),
			definitions.gear_index("heavy_barrel")
		)
	])
	assert_eq(
		sim.query_player_component(0, definitions.gear_slot_index(component.slot_id())),
		"heavy_barrel",
		"fitted"
	)

	var plate_before: int = sim.query_player_item(0, "iron_plate")
	assert_true(plate_before > 0, "the opening bill is plate")
	var weapon_before: String = sim.query_player_weapon(0)
	var components_before: PackedStringArray = sim.query_player_components(0)
	var delivered_before: int = sim.query_delivery_goods_delivered("iron_plate")
	var completed_before: PackedStringArray = sim.query_completed_deliveries()

	_kill(sim)
	var back: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_player_is_alive(0)
	)
	assert_true(back != -1, "they came back")

	assert_eq(sim.query_player_item(0, "iron_plate"), plate_before, "not a plate")
	assert_eq(sim.query_player_weapon(0), weapon_before, "not the weapon in their hands")
	assert_eq(
		sim.query_player_components(0), components_before, "not a component on the frame"
	)
	assert_eq(
		sim.query_delivery_goods_delivered("iron_plate"),
		delivered_before,
		"not the Delivery counter"
	)
	assert_eq(
		sim.query_completed_deliveries(), completed_before, "not what the Run has unlocked"
	)
	assert_eq(
		sim.query_player_health(0), definitions.player_health, "whole, which is the one change"
	)


# ── Everything new is a projection ────────────────────────────────────────────

func test_asking_what_dying_looks_like_leaves_the_run_exactly_where_it_was() -> void:
	# The rule every reading in this project keeps: a query is a projection the Simulation
	# never reads back, so a Run that is watched is the Run that would have happened
	# unwatched. Asserted on each of the three states the gesture has — standing, down, and
	# getting up — because a query that moved the hash would only do it in one of them.
	var sim: Simulation = _sim()
	_assert_asking_is_free(sim, "standing")

	_kill(sim)
	_step(sim, 10)
	_assert_asking_is_free(sim, "on the way down")

	_step_until(sim, 1200, func() -> bool: return sim.query_player_is_alive(0))
	_assert_asking_is_free(sim, "getting back up")


func _assert_asking_is_free(sim: Simulation, when: String) -> void:
	var before: int = sim.hash()
	for repeat: int in range(3):
		sim.query_player_collapse_blend(0)
		sim.query_player_view_collapse_metres(0)
		sim.query_player_view_collapse_roll_turns(0)
	assert_eq(sim.hash(), before, "asking %s moved the state hash" % when)


func test_the_collapse_is_not_state_and_nothing_in_the_simulation_reads_it() -> void:
	# **The mechanical half.** #54's criterion was that anything read out of the Simulation
	# is a projection "or say why it had to be state", and the honest way to assert that is
	# to look at the Simulation's own property list rather than to trust a sentence. The
	# collapse is a function of `_player_life_state` and `_player_life_since_tick`, both of
	# which were hashed and saved before this ticket, so it needed nothing of its own.
	var sim: Simulation = _sim()
	var names: PackedStringArray = RunSave.state_property_names(sim)
	for property_name: String in names:
		assert_false(
			property_name.contains("collapse"),
			"the collapse added hashed state: %s" % property_name
		)
	assert_true(names.has("_player_life_state"), "the two facts it is derived from")
	assert_true(names.has("_player_life_since_tick"))


func test_a_saved_run_comes_back_to_the_same_posture() -> void:
	# A derived view has to be derivable from what was saved, and the whole of what the
	# collapse is derived from is in `hash()` already — so a Run written out mid-fall and read
	# back is standing in exactly the same place. The one comparison `RunSave` exists for,
	# pointed at this.
	var sim: Simulation = _sim()
	_kill(sim)
	_step(sim, 9)
	var mid_fall: int = sim.query_player_collapse_blend(0)
	assert_true(mid_fall > 0 and mid_fall < Fixed.ONE, "part way over")

	var text: String = RunSave.serialise(sim)
	var restored: RunSave.Load = RunSave.deserialise(
		text, _content(), Simulation.new(11, 1, _content(), _layout())
	)
	assert_false(restored.has_errors(), restored.describe_errors())
	var resumed: Simulation = restored.simulation
	assert_not_null(resumed, "a Run came back")
	assert_eq(resumed.hash(), sim.hash(), "the round trip is exact")
	assert_eq(
		resumed.query_player_collapse_blend(0),
		mid_fall,
		"and the body is exactly as far over as it was"
	)
	assert_eq(
		resumed.query_player_view_collapse_metres(0),
		sim.query_player_view_collapse_metres(0)
	)


# ── Switching it off ──────────────────────────────────────────────────────────

func test_setting_the_death_view_drop_to_zero_turns_the_whole_gesture_off() -> void:
	# **The master switch, and it is the drop rather than a key of its own.** This is the
	# largest camera movement in the game and somebody prone to motion sickness is entitled
	# to turn it off, which is the rule every other camera key in `[player]` already obeys —
	# the bob, the dip and the lean all take 0 as off. The roll goes with it because the roll
	# is scaled by the fall: a drop of nothing is a fall of nothing to be a fraction of.
	var sim: Simulation = _sim(
		1, [["death_view_drop_metres = 1.42", "death_view_drop_metres = 0"]]
	)
	_kill(sim)
	for step: int in [1, 13, 27, 60]:
		_step(sim, step)
		assert_eq(
			sim.query_player_collapse_blend(0), 0, "no fall, %d ticks in" % step
		)
		assert_eq(sim.query_player_view_collapse_metres(0), 0, "and no drop")
		assert_eq(
			sim.query_player_view_collapse_roll_turns(0),
			0,
			"and the roll goes with it, out of the one key"
		)


func test_a_downed_player_goes_nowhere_either_when_the_gesture_is_off() -> void:
	# The switch has to cover both states, or a co-op Run would still tilt.
	var sim: Simulation = _sim(
		2, [["death_view_drop_metres = 1.42", "death_view_drop_metres = 0"]]
	)
	_kill(sim)
	assert_true(sim.query_player_is_downed(0))
	_step(sim, 40)
	assert_eq(sim.query_player_collapse_blend(0), 0, "propped up at full eye height")
	assert_eq(sim.query_player_view_collapse_metres(0), 0)


func test_a_zero_second_collapse_is_a_hard_cut_rather_than_nothing() -> void:
	# `collapse_seconds = 0` is a legal value and it means "down, instantly" — the shape
	# `player.holster_seconds = 0` already has. Distinct from the switch above, which means
	# "not down at all".
	var sim: Simulation = _sim(1, [["collapse_seconds = 0.45", "collapse_seconds = 0"]])
	_kill(sim)
	assert_eq(
		sim.query_player_collapse_blend(0), Fixed.ONE, "flat on the tick after the bite"
	)
	var back: int = _step_until(
		sim, 1200, func() -> bool: return sim.query_player_is_alive(0)
	)
	assert_eq(back, 480)
	assert_eq(sim.query_player_collapse_blend(0), 0, "and up on the tick they come back")


# ── What the content loader refuses ───────────────────────────────────────────

func test_a_fall_longer_than_the_body_it_belongs_to_is_refused_by_name() -> void:
	# Both falls are bounded by the eye height in both directions, because a view that dropped
	# further than it stands is a camera under the floor and a negative fall is a view that
	# *rose* when its owner was killed. Checked after the eye height for that reason — it is
	# the figure both are bounded by.
	var through_the_floor: Definitions = _content(
		[["death_view_drop_metres = 1.42", "death_view_drop_metres = 2.4"]]
	)
	assert_true(
		through_the_floor.has_errors(), "2.4 m is further than a 1.7 m eye has to fall"
	)
	assert_true(
		through_the_floor.describe_errors().contains("death_view_drop_metres"),
		"and the error names the key: %s" % through_the_floor.describe_errors()
	)

	var upward: Definitions = _content(
		[["downed_view_drop_metres = 0.9", "downed_view_drop_metres = -0.5"]]
	)
	assert_true(upward.has_errors(), "and a fall is not a negative quantity")
	assert_true(upward.describe_errors().contains("downed_view_drop_metres"))


func test_a_downed_player_cannot_be_tuned_to_fall_further_than_a_dead_one() -> void:
	# The two postures are what tells a player waiting for a teammate from one waiting for a
	# clock, so an ordering that made the Downed fall the *deeper* of the two would make the
	# view say the opposite of what it means. An error naming the key, like every other
	# malformed value in `content/`.
	var inverted: Definitions = _content(
		[["downed_view_drop_metres = 0.9", "downed_view_drop_metres = 1.5"]]
	)
	assert_true(inverted.has_errors(), "1.5 m is a deeper fall than the dead posture's 1.42")
	assert_true(
		inverted.describe_errors().contains("downed_view_drop_metres"),
		"and the error names it: %s" % inverted.describe_errors()
	)


func test_the_collapse_is_in_the_definition_digest() -> void:
	# A hot-reload that moved any of the four has to move the digest, for the reason every
	# other tuning value does: the digest is the set of numbers a Run is playing by, and a
	# replay compares it before it compares a single tick.
	var shipped: Definitions = _content()
	assert_false(shipped.has_errors(), shipped.describe_errors())
	for override: Array in [
		["collapse_seconds = 0.45", "collapse_seconds = 0.6"],
		["death_view_drop_metres = 1.42", "death_view_drop_metres = 1.3"],
		["downed_view_drop_metres = 0.9", "downed_view_drop_metres = 0.8"],
		["collapse_roll_degrees = 20", "collapse_roll_degrees = 25"],
	]:
		var moved: Definitions = _content([override])
		assert_false(moved.has_errors(), moved.describe_errors())
		assert_ne(
			moved.digest(),
			shipped.digest(),
			"changing %s left the digest where it was" % override[0]
		)


# ── A solo death makes a noise ────────────────────────────────────────────────

func test_a_solo_death_thuds_which_it_never_did_before() -> void:
	# **The bug this ticket found.** `PLAYER_DOWN` fired on `query_player_is_downed`, which is
	# never true on a solo Run (GLOSSARY.md) — so the branch fired on no solo death ever and
	# the most consequential event in a Run was completely silent. #54's own description
	# credits the game with a thud it had never once made.
	var sim: Simulation = _sim()
	var director: AudioDirector = _primed(sim)

	var heard: PackedStringArray = PackedStringArray()
	for tick: int in range(TICKS_TO_DIE):
		sim.step([])
		for cue: AudioDirector.Cue in director.cues_for_frame(sim):
			heard.append(cue.name)
		if sim.query_player_is_dead(0):
			break
	assert_true(sim.query_player_is_dead(0), "the player died, solo")
	assert_true(
		heard.has(SoundBank.PLAYER_DOWN),
		"and the body hit the deck audibly. heard: %s" % ", ".join(heard)
	)


func test_a_body_hits_the_deck_once_however_it_got_there() -> void:
	# One edge covers both states, which is also the right thing to say about it: a player
	# who goes Downed and *then* bleeds out has fallen once, so they thud once. The fact the
	# cue fires on is leaving your feet, which `query_player_is_alive` is the predicate for.
	var sim: Simulation = _sim(2)
	var director: AudioDirector = _primed(sim)

	var thuds: int = 0
	for tick: int in range(TICKS_TO_DIE + 1800):
		sim.step([])
		for cue: AudioDirector.Cue in director.cues_for_frame(sim):
			if cue.name == SoundBank.PLAYER_DOWN:
				thuds += 1
		if sim.query_player_is_dead(0):
			break
	assert_true(sim.query_player_is_dead(0), "Downed, and then bled out")
	assert_eq(thuds, 1, "and they went to the ground once")


func test_getting_up_is_silent() -> void:
	# A respawn is not a fall, so it makes no thud: the cue fires on an *edge* — leaving your
	# feet — rather than on the level. Watched for two seconds past the revival, which is well
	# past the gesture's own length.
	var sim: Simulation = _sim()
	var director: AudioDirector = _primed(sim)

	var thuds: int = 0
	var revived: int = -1
	for tick: int in range(TICKS_TO_DIE):
		var was_dead: bool = sim.query_player_is_dead(0)
		sim.step([])
		for cue: AudioDirector.Cue in director.cues_for_frame(sim):
			if cue.name == SoundBank.PLAYER_DOWN:
				thuds += 1
		if was_dead and sim.query_player_is_alive(0):
			revived = tick
			assert_eq(thuds, 1, "the fall thudded once")
		if revived != -1 and tick - revived > 120:
			break
	assert_true(revived != -1, "they died and came back")
	assert_eq(thuds, 1, "and coming back up made no noise of its own")


# ── At a glance, without reading a line of small type ─────────────────────────

func test_a_dead_player_is_told_so_in_type_they_cannot_miss() -> void:
	# **#54's first acceptance criterion.** The HUD line stays — it is the post-mortem — and
	# this is the glance: one word, in 54-pixel type, over a tint that comes up with the fall.
	var sim: Simulation = _sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_false(view.mortality_overlay_is_up(), "nothing over a living player's view")
	assert_eq(view.mortality_caption(), "")

	_kill(sim)
	_step(sim, 40)
	view.sync(sim)
	assert_true(view.mortality_overlay_is_up())
	assert_eq(view.mortality_caption(), "DEAD", "one word, and it is the state")
	assert_true(
		view.mortality_detail().contains("Nest"),
		"with the countdown under it: %s" % view.mortality_detail()
	)
	view.free()


func test_a_downed_player_reads_differently_from_a_dead_one() -> void:
	# What a player should do about the two is different — wait for a teammate, or wait out a
	# clock — so the overlay says different words over a different tint. The posture is the
	# first half of telling them apart and this is the second.
	var pair: Simulation = _sim(2)
	_kill(pair)
	_step(pair, 40)
	var downed_view: WorldView = WorldView.new()
	downed_view.sync(pair)

	var solo: Simulation = _sim()
	_kill(solo)
	_step(solo, 40)
	var dead_view: WorldView = WorldView.new()
	dead_view.sync(solo)

	assert_eq(downed_view.mortality_caption(), "DOWN")
	assert_eq(dead_view.mortality_caption(), "DEAD")
	assert_true(
		downed_view.mortality_detail().contains("teammate"),
		"a bleeding player is waiting for somebody: %s" % downed_view.mortality_detail()
	)
	assert_ne(
		downed_view.mortality_detail(),
		dead_view.mortality_detail(),
		"and the two lines say different things"
	)
	# **A Downed player must still be able to read the Map**, because watching for a teammate
	# coming is the only useful thing they can do. So the lighter tint is not a preference.
	assert_true(
		downed_view.mortality_tint_alpha() < dead_view.mortality_tint_alpha(),
		"the Downed tint is the lighter of the two (%f against %f)"
		% [downed_view.mortality_tint_alpha(), dead_view.mortality_tint_alpha()]
	)
	downed_view.free()
	dead_view.free()


func test_the_tint_comes_up_with_the_fall_rather_than_flashing() -> void:
	# The player has rejected four separate attempts at sound in this project for being too
	# loud, and a sudden full-screen red is the visual form of exactly that. One number drives
	# the view, the tint and the caption, so nothing is ever more tinted than the body is
	# down.
	var sim: Simulation = _sim()
	var view: WorldView = WorldView.new()
	view.sync(sim)
	_kill(sim)

	view.sync(sim)
	var opening: float = view.mortality_tint_alpha()
	assert_true(opening > 0.0, "the tint has begun")
	assert_true(opening < 0.1, "but it is not a flash (%f)" % opening)

	_step(sim, 13)
	view.sync(sim)
	var halfway: float = view.mortality_tint_alpha()
	assert_true(halfway > opening, "it comes up with the fall (%f)" % halfway)

	_step(sim, 40)
	view.sync(sim)
	var settled: float = view.mortality_tint_alpha()
	assert_true(settled > halfway, "and settles with it (%f)" % settled)
	assert_true(settled < 1.0, "over a scene that stays visible")
	view.free()


func test_the_overlay_clears_itself_when_the_player_is_upright_again() -> void:
	# There is no state here and no tween, so nothing has to be told to put it away: the
	# overlay is a function of the blend, and the blend runs to 0 by itself.
	var sim: Simulation = _sim()
	var view: WorldView = WorldView.new()
	_kill(sim)
	_step_until(sim, 1200, func() -> bool: return sim.query_player_is_alive(0))
	view.sync(sim)
	assert_true(view.mortality_overlay_is_up(), "still up through the rise")
	assert_eq(
		view.mortality_caption(),
		"BACK AT THE NEST",
		"which is the one acknowledgement that a respawn happened"
	)

	_step(sim, 40)
	view.sync(sim)
	assert_false(view.mortality_overlay_is_up(), "and gone, with nothing to dismiss")
	assert_eq(view.mortality_caption(), "", "cleared rather than left stale")
	view.free()


func test_showing_and_hiding_the_overlay_does_not_grow_the_scene_tree() -> void:
	# The rule every other thing in `world_view.gd` obeys: built once, then shown, hidden and
	# recoloured. A Run that kills a player over and over must not accumulate overlays.
	#
	# Driven by alternating two Simulations rather than by killing one player four times, and
	# that is deliberate rather than a shortcut: a respawn puts a player on the Nest's crown
	# and the Crawler that killed them walks on to the Nest, so a second death is not
	# something a scripted Run can reliably arrange. What the rule is about is the renderer,
	# and the renderer cannot tell the difference.
	var dead: Simulation = _sim()
	_kill(dead)
	_step(dead, 40)
	var alive: Simulation = _sim()

	var view: WorldView = WorldView.new()
	view.sync(alive)
	var standing: int = view.get_child_count()
	view.sync(dead)
	assert_true(view.mortality_overlay_is_up(), "the overlay is up and counted")
	var settled: int = view.get_child_count()
	assert_eq(settled, standing, "the overlay was built with the HUD rather than on first use")

	for cycle: int in range(4):
		view.sync(alive)
		assert_false(view.mortality_overlay_is_up(), "away again, cycle %d" % cycle)
		view.sync(dead)
		assert_true(view.mortality_overlay_is_up(), "and back, cycle %d" % cycle)
		assert_eq(
			view.get_child_count(), settled, "and not one node was added, cycle %d" % cycle
		)
	view.free()


func test_the_renderer_holds_no_opinion_about_whether_the_player_is_dead() -> void:
	# A view that had been watching a death and one that had not must draw the same thing,
	# because the overlay is read off three queries every frame and remembers nothing.
	var sim: Simulation = _sim()
	var watching: WorldView = WorldView.new()
	watching.sync(sim)
	_kill(sim)
	for tick: int in range(40):
		sim.step([])
		watching.sync(sim)

	var fresh: WorldView = WorldView.new()
	fresh.sync(sim)
	assert_eq(fresh.mortality_caption(), watching.mortality_caption())
	assert_eq(fresh.mortality_detail(), watching.mortality_detail())
	assert_eq(fresh.mortality_tint_alpha(), watching.mortality_tint_alpha())
	watching.free()
	fresh.free()


func test_a_frame_that_stepped_nothing_draws_the_same_collapse_twice() -> void:
	# Nothing presentational in this project is timed by a clock: the audio director varies
	# takes with `tick % count`, the scanner sweep is a count of ticks, and the viewmodel
	# seeks its clip explicitly. The collapse is a function of the tick and the tick the state
	# began on, so two syncs with no step between them are identical.
	var sim: Simulation = _sim()
	var view: WorldView = WorldView.new()
	_kill(sim)
	_step(sim, 9)
	view.sync(sim)
	var first: float = view.mortality_tint_alpha()
	var blend: int = sim.query_player_collapse_blend(0)
	var hashed: int = sim.hash()

	view.sync(sim)
	assert_eq(view.mortality_tint_alpha(), first, "a frame that stepped nothing changed nothing")
	assert_eq(
		sim.query_player_collapse_blend(0),
		blend,
		"and drawing it did not advance the gesture it is drawing"
	)
	assert_eq(sim.hash(), hashed, "nor the Run")
	view.free()


# ── The gesture is cosmetic, and that is measured rather than argued ──────────

func test_switching_the_gesture_off_changes_nothing_the_run_depends_on() -> void:
	# **The strongest statement that the collapse is presentation**, and it has to be made in
	# observable Run facts rather than in `hash()`: the definition digest is itself hashed, so
	# two Runs playing by different tuning differ in hash from tick 0 whether or not a single
	# Item moved. That is the same trap `BalanceProbe` names about two seeds.
	#
	# So this walks two Runs side by side — one with the gesture and one with
	# `death_view_drop_metres = 0` — and compares, every tick, everything a player's Run
	# actually depends on.
	var with_it: Simulation = _sim()
	var without: Simulation = _sim(
		1, [["death_view_drop_metres = 1.42", "death_view_drop_metres = 0"]]
	)
	var saw_a_death: bool = false
	for tick: int in range(1200):
		with_it.step([])
		without.step([])
		if with_it.query_player_is_dead(0):
			saw_a_death = true
		if not _same_run(with_it, without, tick):
			return
	assert_true(saw_a_death, "the window contained a death, so the comparison means something")
	assert_true(
		with_it.query_player_collapse_blend(0) != without.query_player_collapse_blend(0)
		or with_it.query_player_is_alive(0),
		"and the two Runs really were tuned differently"
	)


## Everything about a Run a player depends on, compared between two Simulations. Fails once
## and returns false rather than printing twelve hundred times.
func _same_run(a: Simulation, b: Simulation, tick: int) -> bool:
	var left: PackedStringArray = _run_facts(a)
	var right: PackedStringArray = _run_facts(b)
	if left == right:
		return true
	# Reported once and then false, unconditionally: `assert_eq` returns whether it passed, so
	# handing its result straight back would say "the same" on the very tick they differed and
	# print twelve hundred more of them.
	assert_eq(left, right, "the Runs parted company on tick %d" % tick)
	return false


func _run_facts(sim: Simulation) -> PackedStringArray:
	var at: FixedVec2 = sim.query_player_position(0)
	return PackedStringArray([
		str(sim.query_tick()),
		str(at.x),
		str(at.z),
		str(sim.query_player_camera_height_metres(0)),
		str(sim.query_player_yaw_turns(0)),
		str(sim.query_player_camera_pitch_turns(0)),
		str(sim.query_player_health(0)),
		str(sim.query_player_is_alive(0)),
		str(sim.query_player_is_dead(0)),
		str(sim.query_player_respawn_ticks_remaining(0)),
		str(sim.query_player_item(0, "iron_plate")),
		str(sim.query_enemy_count()),
		str(sim.query_heat()),
	])


# ── And the Run replays through a death ───────────────────────────────────────

## The fixture runs on the starter Map, which is what `DeterminismHarness.record` builds, so
## the player has to walk into the road to be eaten — eleven metres north of the origin, which
## is `test_gear.gd`'s worked example of the same walk. Being killed is something a player does
## to themselves by standing somewhere, and the recording says so.
const TICKS_TO_THE_LANE: int = 170

## Several Crawlers a Breach, walking, at a fragile player, with the clocks shortened so a
## death and a respawn both fit inside a fixture. The shipped `gear.csv` and the shipped
## Delivery chain, so the recording is of the real weapons.
const FIXTURE_TUNING: Array = [
	["health = 150", "health = 20"],
	["respawn_delay_seconds = 8", "respawn_delay_seconds = 2"],
]

const MANY_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
"""


func _fixture_content() -> Definitions:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = MANY_CRAWLERS
	var substitutions: Array = []
	substitutions.append_array(QUICK_TELEGRAPH)
	substitutions.append_array(FIXTURE_TUNING)
	return fixture.tune(substitutions).definitions()


func _mortality_script() -> InputScript:
	var script: InputScript = InputScript.new()
	script.add_tick([InputAction.call_wave_early(0)])
	for tick: int in range(TICKS_TO_THE_LANE):
		script.add_tick([InputAction.move(0, Fixed.ONE, 0)])
	script.add_idle_ticks(2400)
	return script


func test_determinism_a_run_in_which_the_player_dies_and_comes_back_replays() -> void:
	var recording: ReplayRecording = DeterminismHarness.record(
		_mortality_script(), 11, 1, _fixture_content()
	)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_the_fixture_really_did_kill_the_player_and_put_them_on_the_deck() -> void:
	# The honesty check beside the fixture, which is the half that stops a replay of a Run in
	# which nobody died from reading as a passing determinism test. It asserts the *gesture*
	# too, because that is what #54 is about: a dead player whose view never moved would
	# satisfy every other assertion in this file's fixture.
	var sim: Simulation = Simulation.new(11, 1, _fixture_content())
	var script: InputScript = _mortality_script()
	var flattest: int = 0
	var died: bool = false
	var came_back: bool = false
	for tick: int in range(script.tick_count()):
		sim.step(script.actions_at(tick))
		flattest = maxi(flattest, sim.query_player_collapse_blend(0))
		if sim.query_player_is_dead(0):
			died = true
		if died and sim.query_player_is_alive(0):
			came_back = true
	assert_true(died, "a Crawler ate the player in the road")
	assert_true(came_back, "and they got up again at the Nest")
	assert_eq(flattest, Fixed.ONE, "and went all the way over on the way down")
