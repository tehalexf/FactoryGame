## The first-person weapon in frame: which clip plays, and what happens when the
## purchased arms are not on this machine.
##
## Two seams, and nothing between them:
##
## * `WeaponAnimator` — "given what the Simulation says this tick, what should be
##   playing and how far into it". It is a `RefCounted` with no nodes, no scene
##   tree and no assets, so every transition a player will ever see is a cheap
##   assertion here rather than something only a screenshot can catch.
## * `WorldView`'s weapon accessors — `weapon_is_visible`, `weapon_offset`,
##   `weapon_clip_role`, `weapon_model_id`, `weapon_has_model`. These assert the
##   thing the licence makes load-bearing: **the viewmodels are converted outside
##   this repository and are usually absent**, and the game has to be exactly as
##   playable and exactly as testable without them.
##
## Clip *lengths* are injected rather than read off a GLB, because a test that
## needed the purchased packs would be a test nobody but this machine could run.
extends TestCase


func _facts(tick: int, weapon: String = "bolt_rifle") -> WeaponAnimator.Facts:
	var facts: WeaponAnimator.Facts = WeaponAnimator.Facts.new()
	facts.tick = tick
	facts.weapon = weapon
	facts.alive = true
	facts.shots_remaining = 10
	facts.interval_ticks = 48
	return facts


## A full clip set, in seconds, of the shape a converted `Weapon pack` GLB has.
func _lengths() -> Dictionary:
	return {
		WeaponAnimator.IDLE: 1.0,
		WeaponAnimator.WALK: 0.4,
		WeaponAnimator.RUN: 0.3,
		WeaponAnimator.FIRE: 0.25,
		WeaponAnimator.CYCLE: 0.5,
		WeaponAnimator.DRAW: 0.4,
		WeaponAnimator.HOLSTER: 0.3,
		WeaponAnimator.RELOAD: 1.2,
	}


# ── Carriage: standing, walking, running ──────────────────────────────────────

func test_a_still_player_idles_and_a_moving_one_does_not() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())

	var standing: WeaponAnimator.Facts = _facts(0)
	standing.speed = 0.0
	# The draw at the start of a Run has to finish before anything else is asked.
	animator.cue(standing)
	standing.tick = 120
	assert_eq(animator.cue(standing).role, WeaponAnimator.IDLE, "stood still, so idle")

	var walking: WeaponAnimator.Facts = _facts(121)
	walking.speed = 3.0
	assert_eq(animator.cue(walking).role, WeaponAnimator.WALK, "moving, so carried")

	var sprinting: WeaponAnimator.Facts = _facts(122)
	sprinting.speed = 7.0
	sprinting.sprinting = true
	assert_eq(animator.cue(sprinting).role, WeaponAnimator.RUN, "sprinting, so run")


func test_the_carriage_loops_and_a_shot_does_not() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	var facts: WeaponAnimator.Facts = _facts(200)
	animator.cue(facts)
	facts.tick = 260
	assert_true(animator.cue(facts).loop, "a player stands there for minutes")

	facts.tick = 261
	facts.last_shot_tick = 261
	var fired: WeaponAnimator.Cue = animator.cue(facts)
	assert_eq(fired.role, WeaponAnimator.FIRE)
	assert_false(fired.loop, "a shot happens once")


# ── Changing weapons: holster the old one, then draw the new ───────────────────

func test_a_run_opens_by_drawing_what_the_player_is_holding() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	var opening: WeaponAnimator.Cue = animator.cue(_facts(0))
	assert_eq(opening.role, WeaponAnimator.DRAW, "nothing was in hand, so nothing is put away")
	assert_eq(opening.weapon, "bolt_rifle")


func test_a_weapon_change_puts_the_old_one_away_before_the_new_one_is_drawn() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_facts(0))
	animator.cue(_facts(60))

	# Tick 60: the player presses 2.
	var changing: WeaponAnimator.Cue = animator.cue(_facts(60, "drum_autocannon"))
	assert_eq(changing.role, WeaponAnimator.HOLSTER)
	assert_eq(
		changing.weapon,
		"bolt_rifle",
		"the model going away is the model being put away — you cannot holster a rifle "
		+ "that has already been swapped for an autocannon"
	)

	# Half way through the 0.3 s holster it is still the rifle leaving frame.
	assert_eq(animator.cue(_facts(69, "drum_autocannon")).weapon, "bolt_rifle")

	# And once it is gone, the autocannon is drawn.
	var drawing: WeaponAnimator.Cue = animator.cue(_facts(60 + 19, "drum_autocannon"))
	assert_eq(drawing.role, WeaponAnimator.DRAW)
	assert_eq(drawing.weapon, "drum_autocannon")

	var settled: WeaponAnimator.Cue = animator.cue(_facts(60 + 19 + 25, "drum_autocannon"))
	assert_eq(settled.role, WeaponAnimator.IDLE)
	assert_eq(settled.weapon, "drum_autocannon")


func test_a_weapon_being_put_away_cannot_be_fired() -> void:
	# A holster and a draw are the two clips a player must not be able to shoot
	# through: the trigger is still held from the shot before the change.
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_facts(0))
	animator.cue(_facts(60))
	var facts: WeaponAnimator.Facts = _facts(61, "drum_autocannon")
	facts.last_shot_tick = 61
	assert_eq(animator.cue(facts).role, WeaponAnimator.HOLSTER)


# ── Working the bolt ──────────────────────────────────────────────────────────
# `L96_animation.fbx` carries a take called `Chamber` and `Shotgun_animation.fbx`
# one called `Pump` (docs/LICENSED_ASSETS.md). Both are the same thing — the
# action that readies the next round — and both only have anywhere to go on a
# weapon whose own `seconds_per_shot` leaves room for them.

func test_a_slow_weapon_works_its_bolt_between_shots() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_facts(0))

	# The Bolt Rifle fires every 48 ticks. A 0.25 s shot and a 0.5 s chamber is 45
	# ticks of the 48, so there is room.
	var facts: WeaponAnimator.Facts = _facts(100)
	facts.last_shot_tick = 100
	assert_eq(animator.cue(facts).role, WeaponAnimator.FIRE)

	facts.tick = 120
	assert_eq(animator.cue(facts).role, WeaponAnimator.CYCLE, "the shot is over; work the bolt")

	facts.tick = 147
	assert_eq(animator.cue(facts).role, WeaponAnimator.IDLE, "and then wait for the trigger")


func test_a_fast_weapon_has_no_room_to_work_a_bolt_and_does_not_try() -> void:
	# The Drum Autocannon fires eight times a second: 7 ticks between shots, which
	# is less than the shot clip itself. Playing a chamber there would be a weapon
	# that visibly cycles slower than it fires.
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_facts(0, "drum_autocannon"))
	var facts: WeaponAnimator.Facts = _facts(100, "drum_autocannon")
	facts.interval_ticks = 7
	facts.last_shot_tick = 100
	facts.tick = 120
	assert_ne(animator.cue(facts).role, WeaponAnimator.CYCLE)


func test_a_weapon_whose_model_has_no_chamber_take_never_plays_one() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	var without: Dictionary = _lengths()
	without.erase(WeaponAnimator.CYCLE)
	animator.set_clip_lengths(without)
	animator.cue(_facts(0))
	var facts: WeaponAnimator.Facts = _facts(100)
	facts.last_shot_tick = 100
	facts.tick = 120
	assert_eq(animator.cue(facts).role, WeaponAnimator.IDLE)


# ── Reloading ─────────────────────────────────────────────────────────────────
# The Simulation has no reload: a round is spent out of the player's own pockets
# the tick the trigger goes (CLAUDE.md, "Firing, and where the aim comes from").
# So a reload is not invented here either — it is the one moment that *is* a
# reload and that a query can see: `query_player_shots_remaining` rising off zero,
# which is a player who was dry and now is not.

func _dry(tick: int) -> WeaponAnimator.Facts:
	var facts: WeaponAnimator.Facts = _facts(tick)
	facts.shots_remaining = 0
	return facts


func test_a_magazine_arriving_in_an_empty_weapon_is_a_reload() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_dry(0))
	assert_eq(animator.cue(_dry(60)).role, WeaponAnimator.IDLE, "dry, and nothing to load")

	# Tick 61: the Ammo Press's output reaches the player's pockets.
	assert_eq(animator.cue(_facts(61)).role, WeaponAnimator.RELOAD)
	assert_eq(animator.cue(_facts(100)).role, WeaponAnimator.RELOAD, "and it takes 1.2 s")
	assert_eq(animator.cue(_facts(140)).role, WeaponAnimator.IDLE, "and then it is over")


func test_a_weapon_that_was_never_dry_does_not_reload() -> void:
	# A player who banks a second round while holding one has not reloaded.
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	animator.cue(_facts(0))
	var facts: WeaponAnimator.Facts = _facts(60)
	facts.shots_remaining = 40
	assert_eq(animator.cue(facts).role, WeaponAnimator.IDLE)


func test_a_melee_weapon_never_reloads() -> void:
	# A Pneumatic Wrench spends no Ammunition, so `shots_remaining` says nothing
	# about it and must not be read as a magazine going in.
	var animator: WeaponAnimator = WeaponAnimator.new()
	animator.set_clip_lengths(_lengths())
	var dry: WeaponAnimator.Facts = _dry(0)
	dry.weapon = "pneumatic_wrench"
	dry.is_melee = true
	animator.cue(dry)
	dry.tick = 60
	animator.cue(dry)

	var armed: WeaponAnimator.Facts = _facts(61, "pneumatic_wrench")
	armed.is_melee = true
	assert_eq(animator.cue(armed).role, WeaponAnimator.IDLE)


func test_a_pump_reload_can_be_interrupted_by_the_trigger() -> void:
	# This is what `Shotgun_animation.fbx`'s Reload_Start / reload / Reload_End
	# split is for (docs/LICENSED_ASSETS.md): a player who has fed one shell in and
	# needs to shoot *now* breaks out of the loop and closes the action afterwards.
	var animator: WeaponAnimator = WeaponAnimator.new()
	var split: Dictionary = _lengths()
	split[WeaponAnimator.RELOAD_START] = 0.3
	split[WeaponAnimator.RELOAD] = 0.5
	split[WeaponAnimator.RELOAD_END] = 0.3
	animator.set_clip_lengths(split)

	animator.cue(_dry(0))
	animator.cue(_dry(60))
	assert_eq(animator.cue(_facts(61)).role, WeaponAnimator.RELOAD_START, "the action opens")
	assert_eq(animator.cue(_facts(85)).role, WeaponAnimator.RELOAD, "shells go in")

	# Tick 90: the trigger, mid-reload.
	var shooting: WeaponAnimator.Facts = _facts(90)
	shooting.last_shot_tick = 90
	assert_eq(animator.cue(shooting).role, WeaponAnimator.FIRE, "the shot wins outright")

	shooting.tick = 108
	assert_eq(
		animator.cue(shooting).role,
		WeaponAnimator.RELOAD_END,
		"and the action closes afterwards rather than the loop resuming"
	)
	shooting.tick = 140
	assert_eq(animator.cue(shooting).role, WeaponAnimator.IDLE)


func test_a_reload_runs_through_its_whole_split_when_nothing_interrupts_it() -> void:
	var animator: WeaponAnimator = WeaponAnimator.new()
	var split: Dictionary = _lengths()
	split[WeaponAnimator.RELOAD_START] = 0.3
	split[WeaponAnimator.RELOAD] = 0.5
	split[WeaponAnimator.RELOAD_END] = 0.3
	animator.set_clip_lengths(split)
	animator.cue(_dry(0))
	animator.cue(_dry(60))
	animator.cue(_facts(61))
	var seen: Dictionary = {}
	for tick: int in range(61, 140):
		seen[animator.cue(_facts(tick)).role] = true
	assert_true(seen.has(WeaponAnimator.RELOAD_START), "opened")
	assert_true(seen.has(WeaponAnimator.RELOAD), "fed")
	assert_true(seen.has(WeaponAnimator.RELOAD_END), "closed")


# ── Without the purchased packs ───────────────────────────────────────────────
# The licence rule (docs/ASSETS.md) is that nothing non-redistributable may be
# committed — and the half of it that is easy to break is that nothing may be
# *required* either. `WeaponViewmodel.WEAPON_BODY_DIRECTORY` is outside the
# shipping tree and gitignored, so on a fresh clone it does not exist. These
# assert what that clone gets, and they are the reason the converted GLBs can stay
# out of git without the game going with them.

func test_the_weapon_directory_is_outside_the_shipping_tree() -> void:
	# If this ever points inside `assets/`, a converted viewmodel would be
	# committable and the licence guard would start failing on a clean checkout.
	assert_true(
		WeaponViewmodel.WEAPON_BODY_DIRECTORY.begins_with("res://assets_licensed/"),
		WeaponViewmodel.WEAPON_BODY_DIRECTORY
	)


func test_a_clone_with_no_converted_models_still_puts_a_weapon_in_frame() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	# A Run opens with the Build Gun in hand (#29), so the weapon has to be asked for and
	# the swap has to finish before the weapon is the model in frame.
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(_settle(sim, view), "the weapon is out")

	if view.weapon_has_model():
		# This machine has the purchased packs converted. The claim this test makes
		# is about the absence of them, so assert the other half instead: a model
		# that loaded resolved at least an idle.
		assert_ne(view.weapon_model_id(), "", "a loaded model is the weapon it was named for")
		view.free()
		return

	assert_true(view.weapon_is_visible(), "placeholder or not, there is a weapon in frame")
	assert_eq(
		view.weapon_model_id(),
		sim.query_player_weapon(0),
		"and the viewmodel knows which weapon it is standing in for"
	)
	view.free()


func test_the_clip_follows_the_run_whether_a_model_loaded_or_not() -> void:
	# The animation state machine runs on `DEFAULT_SECONDS` when no GLB told it
	# otherwise, so absence of the packs changes what is *drawn* and not what
	# *happens*. What it must never depend on is how long a particular pack's
	# clips happen to be, so the waits here are "until it settles" rather than a
	# count of ticks.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	assert_eq(view.weapon_clip_role(), WeaponAnimator.DRAW, "a Run opens by drawing")

	assert_true(_settle(sim, view), "the draw ends and the weapon is carried")
	assert_eq(view.weapon_clip_role(), WeaponAnimator.IDLE, "and then stands there")

	for tick: int in range(30):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
		view.sync(sim)
	assert_eq(view.weapon_clip_role(), WeaponAnimator.WALK, "walking carries it")

	sim.step([InputAction.fire(0)])
	view.sync(sim)
	assert_eq(
		view.weapon_clip_role(),
		WeaponAnimator.FIRE,
		"and the trigger beats the carriage"
	)
	view.free()


func test_a_weapon_change_in_a_real_run_holsters_and_draws() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	var opening: String = sim.query_player_weapon(0)
	# Out of build mode first: a Run opens holding the Build Gun (#29), and a weapon change
	# while the Build Gun is in frame changes nothing the player can see.
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(_settle(sim, view), "the Run's opening draw and the holster finish")
	assert_eq(view.weapon_model_id(), opening, "the weapon is the thing in frame")

	var other: String = "drum_autocannon" if opening != "drum_autocannon" else "bolt_rifle"
	sim.step([
		InputAction.equip_weapon(0, sim.query_definitions().gear_index(other))
	])
	view.sync(sim)
	assert_ne(sim.query_player_weapon(0), opening, "the player is holding the other one")
	assert_eq(view.weapon_clip_role(), WeaponAnimator.HOLSTER)
	assert_eq(view.weapon_model_id(), opening, "and the old one is still the one leaving")

	assert_true(_settle(sim, view), "the change finishes")
	assert_eq(view.weapon_model_id(), sim.query_player_weapon(0), "then the new one is up")
	view.free()


## Steps the Run until the weapon is being carried rather than drawn or stowed,
## and reports whether it got there. Bounded, because a test that hangs is worse
## than one that fails.
func _settle(sim: Simulation, view: WorldView) -> bool:
	for tick: int in range(600):
		sim.step([])
		view.sync(sim)
		var role: String = view.weapon_clip_role()
		if role == WeaponAnimator.IDLE or role == WeaponAnimator.WALK:
			return true
	return false


# ── Anything in the hands, not only a weapon ──────────────────────────────────

func test_the_view_model_will_hold_whatever_it_is_handed() -> void:
	# The thing in a player's hands is not only their weapon: #29's holster swaps
	# between a weapon and the Build Gun, and it is one field of `Facts` rather
	# than a second view model — the holster, the model swap and the draw come for
	# free because `draw` and `holster` are first-class roles here rather than a
	# special case. `WorldView._sync_weapon` is the production caller; this is the
	# seam itself, asserted directly and with the same id.
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var viewmodel: WeaponViewmodel = view.weapon_viewmodel()
	# Out of build mode, so the thing in frame is the weapon: `WorldView._sync_weapon` is
	# itself a caller of this seam now and hands over the Build Gun's id in build mode, so
	# handing it that same id here would be handing it what it already has.
	sim.step([InputAction.set_build_mode(0, false)])
	assert_true(_settle(sim, view), "the Run's opening draw and the holster finish")

	var facts: WeaponAnimator.Facts = viewmodel.held_facts(sim, 0)
	var weapon: String = facts.weapon
	facts.weapon = "build_gun"
	viewmodel.show_held(facts)
	assert_eq(
		viewmodel.clip_role(),
		WeaponAnimator.HOLSTER,
		"handing it a different id puts the old thing away"
	)
	assert_eq(viewmodel.model_weapon(), weapon, "and the old thing is still on screen")

	for tick: int in range(120):
		sim.step([])
		facts = viewmodel.held_facts(sim, 0)
		facts.weapon = "build_gun"
		viewmodel.show_held(facts)
	assert_eq(viewmodel.model_weapon(), "build_gun", "then the new thing is up")
	# And since #64 it is up as a *model* rather than as two boxes, because the Build Gun is
	# the one held object this project authored itself and so the one whose GLB is committed.
	# The claim this test makes is about the seam taking any id at all, which is why the id it
	# hands over is still the production one rather than an invented one.
	assert_true(viewmodel.has_model(), "with the committed Build Gun model (#64)")
	view.free()


# ── The Build Gun, which is self-authored and therefore committed ─────────────
# Every weapon frame in this game arrives from a purchased pack, so its model is
# gitignored and usually absent. **The Build Gun is the one held object this
# project authored itself** — `tools/assets/generate_build_gun.sh` builds it out
# of the same parts kit and the same palette the Machines are built from — so it
# is committed, it is in the shipping tree, and a clone with no packs at all sees
# the real article rather than two boxes. These assert that difference, because it
# is the whole of what #64 bought.

func test_the_build_gun_is_committed_and_inside_the_shipping_tree() -> void:
	# The counterpart to `test_the_weapon_directory_is_outside_the_shipping_tree`,
	# and the two have to stay opposites: a purchased weapon may never be
	# committable, and the self-authored tool may never be *required* to be absent.
	assert_true(
		WeaponViewmodel.TOOL_BODY_DIRECTORY.begins_with("res://assets/"),
		WeaponViewmodel.TOOL_BODY_DIRECTORY
	)
	assert_true(
		FileAccess.file_exists(
			"%s%s.glb" % [WeaponViewmodel.TOOL_BODY_DIRECTORY, WorldView.BUILD_GUN_HELD_ID]
		),
		"the Build Gun's model is committed, so every clone has it"
	)


func test_the_build_gun_draws_a_model_rather_than_the_placeholder_boxes() -> void:
	# #29's Build Gun read as a *tool* at a glance and #28 cost it that, which is
	# the ticket. The silhouette itself is judged by rendering; what is assertable
	# here is that the model loads at all and that it carries the two takes a
	# holster is made of, because a swap times itself off their lengths.
	var viewmodel: WeaponViewmodel = WeaponViewmodel.new()
	var facts: WeaponAnimator.Facts = _facts(0, WorldView.BUILD_GUN_HELD_ID)
	facts.is_melee = true
	facts.reach_metres = 0.0
	viewmodel.show_held(facts)
	assert_true(viewmodel.has_model(), "the committed Build Gun model is in frame")
	assert_ne(viewmodel.clip_name(WeaponAnimator.DRAW), "", "it carries a Draw take")
	assert_ne(viewmodel.clip_name(WeaponAnimator.HOLSTER), "", "and a PutAway take")
	viewmodel.free()
