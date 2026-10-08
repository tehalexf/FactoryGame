## What the weapon in the player's hands should be doing this tick.
##
## One question, asked once a frame: given what the Simulation says — the weapon
## held, the tick a shot last left it, how fast the player is moving, how many
## rounds are in their pockets — which animation clip should be playing, which
## weapon's model should be on screen, and how far into the clip are we.
##
## **It holds no opinion about the Run.** Every input arrives in a `Facts`, every
## one of whose fields is a Simulation query, so the model follows the Run and
## never the other way round. What it *does* remember is when a transition began,
## because a draw is a thing with a length and "how far into the draw are we" is
## not a question any query answers.
##
## It touches no node, loads no file and knows no asset. Clip lengths are told to
## it (`set_clip_lengths`) by whoever loaded the model, and anything it is not
## told falls back to `DEFAULT_SECONDS` — so the whole state machine runs, and is
## testable, on a machine with none of the purchased arms on it.
class_name WeaponAnimator
extends RefCounted

## The roles a clip can play. A converted pack names its takes its own way —
## `Shoot` here, `Knife_Attack_1_Anim` there, `PutAway` against `Holster` — so a
## role is what the game asks for and `WeaponViewmodel` is what resolves it to a
## name the GLB actually has.
const IDLE: String = "idle"
const WALK: String = "walk"
const RUN: String = "run"
const FIRE: String = "fire"
## The bolt or the pump: the action that readies the next round, after the shot
## and before the weapon is usable again. Only played by a weapon slow enough to
## have room for it between shots, which is exactly the weapons that have one.
const CYCLE: String = "cycle"
const RELOAD_START: String = "reload_start"
const RELOAD: String = "reload"
const RELOAD_END: String = "reload_end"
const DRAW: String = "draw"
const HOLSTER: String = "holster"

## How long a clip lasts when the model on screen has not told us — a placeholder,
## or a GLB missing that take. Pure feel, and the point of them is that absence of
## the purchased packs changes what is *drawn* and not what *happens*.
const DEFAULT_SECONDS: Dictionary = {
	IDLE: 1.0,
	WALK: 0.5,
	RUN: 0.4,
	FIRE: 0.18,
	CYCLE: 0.45,
	RELOAD_START: 0.3,
	RELOAD: 0.9,
	RELOAD_END: 0.3,
	DRAW: 0.4,
	HOLSTER: 0.3,
}

## Below this, in metres per second, a player is standing still. A hair above zero
## rather than zero, because velocity decays towards it asymptotically and a
## weapon that keeps walking for a second after the player stopped reads as lag.
const STILL_SPEED: float = 0.15


## Everything about the Run that decides what the weapon is doing. Every field is
## a Simulation query; none is a remembered copy.
class Facts extends RefCounted:
	## `query_tick`.
	var tick: int = 0
	## `query_player_weapon` — empty when the player is holding nothing.
	var weapon: String = ""
	## `query_player_is_alive`.
	var alive: bool = true
	## Length of `query_player_velocity`, in metres per second.
	var speed: float = 0.0
	## `query_player_is_sprinting`.
	var sprinting: bool = false
	## `query_player_last_shot_tick`, or -1 when nothing has been fired.
	var last_shot_tick: int = -1
	## `query_player_weapon_interval_ticks` — how long until this weapon may fire
	## again, which is what decides whether there is room to work the bolt.
	var interval_ticks: int = 1
	## `query_player_shots_remaining`. A ranged weapon with nothing in its pockets
	## reads 0; the tick this rises off 0 is the tick a magazine went in.
	var shots_remaining: int = 0
	## `query_player_weapon_is_melee`. A swing never reloads and never cycles.
	var is_melee: bool = false
	## `query_player_weapon_range_metres` and `query_player_survey_blend`. These
	## two decide where the thing is *drawn* rather than what it is doing, so the
	## state machine ignores them — they are here so that putting something in a
	## player's hands is one struct and one call rather than two.
	var reach_metres: float = 0.0
	var survey_blend: float = 0.0
	## `player.holster_seconds`, out of `query_definitions`: how long the **whole**
	## visible swap may take, in seconds, counting the stow and the draw together.
	##
	## **A budget, not a duration.** The clips decide the shape of a swap and this
	## decides how long a player waits for it, which is why it is a ceiling on each
	## half rather than a replacement for either: a pack whose `PutAway` is already
	## brisk is left alone, and the 0.66 s stows the purchased packs ship are cut to
	## fit. #35's playtest asked for an instant swap, reached for this key, and got
	## nothing — because #28 had timed the swap off the clip lengths alone and left
	## the key read by nobody on this side of the boundary. 0 is a hard cut.
	##
	## Negative means "no budget, the clips decide", which is what a `Facts` nobody
	## filled in says — so `WeaponAnimator`'s own tests still measure clip lengths.
	var swap_seconds: float = -1.0


## What should be on screen.
class Cue extends RefCounted:
	## One of the role constants above, or empty when nothing should play.
	var role: String = ""
	## How far into the clip, in seconds.
	var seconds: float = 0.0
	## Whether it should run round again when it reaches the end.
	var loop: bool = false
	## Which weapon's *model* belongs on screen. Not always `Facts.weapon`: a
	## weapon change holsters the one going away before the new one is drawn, and
	## you cannot holster a model that has already been swapped out.
	var weapon: String = ""


var _lengths: Dictionary = {}

# What a cue cannot be derived from a query alone: when the current transition
# began, and which weapon it is a transition away from.
var _role: String = ""
var _role_started_tick: int = 0
var _shown_weapon: String = ""
# The reload: which phase of the chain is running, when it began, and whether a
# shot broke out of it and left the action still open.
var _reload_phase: String = ""
var _reload_started_tick: int = 0
var _reload_end_owed: bool = false
var _shots_remaining: int = -1


## Tell the animator how long this model's clips are, in seconds, keyed by role.
## Roles the model does not have are simply absent, and the animator will not
## choose them — a weapon with no `cycle` take never works a bolt.
func set_clip_lengths(lengths: Dictionary) -> void:
	_lengths = lengths.duplicate()


## How long a role's clip is, in seconds. Falls back to `DEFAULT_SECONDS` so the
## placeholder weapon runs the same state machine the converted one does.
func clip_seconds(role: String) -> float:
	if _lengths.has(role):
		return float(_lengths[role])
	return float(DEFAULT_SECONDS.get(role, 0.0))


## Whether this model actually has a clip for a role.
func has_clip(role: String) -> bool:
	return _lengths.has(role)


## How long one half of a swap may run for, in seconds: the clip's own length, or half
## the tuned budget when that is shorter.
##
## Half each, and evenly, because a holster is symmetric — one thing goes down and the
## other comes up, and `query_player_holster_blend` already describes the same transition
## with one number for both halves for the same reason. Splitting it by the clips'
## relative lengths would make the swap's *timing* depend on which pack is installed,
## which is exactly what #35 found intolerable.
func _swap_half_seconds(role: String, facts: Facts) -> float:
	var clip: float = clip_seconds(role)
	if facts.swap_seconds < 0.0:
		return clip
	return minf(clip, facts.swap_seconds * 0.5)


## What the weapon should be doing this tick.
func cue(facts: Facts) -> Cue:
	if facts.weapon.is_empty():
		_shown_weapon = ""
		_role = ""
		return _cue("", 0.0, false)

	# A weapon change is two clips and a model swap between them. The holster
	# belongs to the weapon going away, so `_shown_weapon` lags `facts.weapon`
	# until it is over — otherwise the player watches an autocannon perform a
	# rifle's stow.
	if _shown_weapon != facts.weapon:
		if _shown_weapon.is_empty():
			_shown_weapon = facts.weapon
			_begin(DRAW, facts.tick)
		elif _role != HOLSTER:
			_begin(HOLSTER, facts.tick)
	if _role == HOLSTER:
		var stowing: float = _seconds_since(facts.tick, _role_started_tick)
		if stowing < _swap_half_seconds(HOLSTER, facts):
			return _cue(HOLSTER, stowing, false)
		_shown_weapon = facts.weapon
		_begin(DRAW, facts.tick)
	if _role == DRAW:
		var drawing: float = _seconds_since(facts.tick, _role_started_tick)
		if drawing < _swap_half_seconds(DRAW, facts):
			return _cue(DRAW, drawing, false)

	_note_the_magazine(facts)

	var fired: float = _seconds_since(facts.tick, facts.last_shot_tick)
	var since_a_shot: bool = facts.last_shot_tick >= 0 and fired >= 0.0
	if since_a_shot and fired < clip_seconds(FIRE):
		# The trigger beats a reload outright, which is what the Shotgun's
		# `Reload_Start` / `reload` / `Reload_End` split is for: break out of the
		# loop, shoot, and close the action afterwards rather than resuming it.
		if not _reload_phase.is_empty():
			_reload_end_owed = _reload_phase != RELOAD_END and has_clip(RELOAD_END)
			_reload_phase = ""
		_role = FIRE
		return _cue(FIRE, fired, false)
	if since_a_shot and _reload_end_owed:
		_reload_end_owed = false
		_begin_reload(RELOAD_END, facts.tick)

	var reloading: Cue = _reload_cue(facts)
	if reloading != null:
		return reloading

	# The bolt or the pump, which only a weapon whose own fire interval leaves room
	# for it ever performs — a weapon cycling slower than it fires would be a model
	# disagreeing with the Simulation about when it may shoot.
	if since_a_shot:
		var cycling: float = fired - clip_seconds(FIRE)
		if (
			has_clip(CYCLE)
			and cycling < clip_seconds(CYCLE)
			and _seconds(facts.interval_ticks) >= clip_seconds(FIRE) + clip_seconds(CYCLE)
		):
			_role = CYCLE
			return _cue(CYCLE, cycling, false)

	var carriage: String = IDLE
	if facts.speed > STILL_SPEED:
		carriage = RUN if facts.sprinting else WALK
	if _role != carriage:
		_begin(carriage, facts.tick)
	return _cue(carriage, _seconds_since(facts.tick, _role_started_tick), true)


## Watch the magazine, and start a reload the tick it fills.
##
## The Simulation has no reload — a round leaves the player's pockets the tick the
## trigger goes — so there is nothing here to read except the one event that *is* a
## reload: a player who was dry and now is not. A player who banks a second round
## while holding one has not reloaded, and a melee weapon has no magazine at all.
func _note_the_magazine(facts: Facts) -> void:
	var before: int = _shots_remaining
	_shots_remaining = facts.shots_remaining
	if facts.is_melee or before != 0 or facts.shots_remaining <= 0:
		return
	_begin_reload(RELOAD_START if has_clip(RELOAD_START) else RELOAD, facts.tick)


## The reload chain, or null when none is running. Whichever of the three clips
## the model carries, in order: a pack that ships one `reload` take plays one clip,
## and the Shotgun's split plays three.
func _reload_cue(facts: Facts) -> Cue:
	while not _reload_phase.is_empty():
		var elapsed: float = _seconds_since(facts.tick, _reload_started_tick)
		if elapsed < clip_seconds(_reload_phase):
			_role = _reload_phase
			return _cue(_reload_phase, elapsed, false)
		_begin_reload(_next_reload_phase(), facts.tick)
	return null


func _next_reload_phase() -> String:
	if _reload_phase == RELOAD_START:
		return RELOAD
	if _reload_phase == RELOAD and has_clip(RELOAD_END):
		return RELOAD_END
	return ""


func _begin_reload(phase: String, tick: int) -> void:
	_reload_phase = phase
	_reload_started_tick = tick


func _cue(role: String, seconds: float, loop: bool) -> Cue:
	var result: Cue = Cue.new()
	result.role = role
	result.seconds = seconds
	result.loop = loop
	result.weapon = _shown_weapon
	return result


func _begin(role: String, tick: int) -> void:
	_role = role
	_role_started_tick = tick


func _seconds_since(tick: int, started: int) -> float:
	return _seconds(tick - started)


## Ticks as seconds. The Simulation counts in ticks and an AnimationPlayer in
## seconds, and `TICKS_PER_SECOND` is the whole of the conversion.
func _seconds(ticks: int) -> float:
	return float(ticks) / float(Simulation.TICKS_PER_SECOND)
