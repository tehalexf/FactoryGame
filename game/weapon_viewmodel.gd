## The weapon in frame: the model, the arms, and the clip that is playing on them.
##
## Parented to the camera, so it inherits the view's yaw and pitch — including the
## recoil `query_player_camera_pitch_turns` carries, which is the point: the model
## and the aim climb together because they are the same number.
##
## **Everything it draws is absent-tolerant.** The purchased first-person arms are
## non-redistributable (docs/ASSETS.md), so they are converted out of the
## quarantine into `WEAPON_BODY_DIRECTORY` — a gitignored path *outside* the
## shipping tree that on most clones does not exist at all. When a weapon has no
## GLB there, two boxes stand in for it and the rest of this file behaves
## identically: the same `WeaponAnimator`, the same sway, the same kick, the same
## queries. A clone without the packs is a playable, testable game.
##
## **The Build Gun is the exception and it is the licence that makes it one** (#64).
## It is not a weapon, no pack ships one, and it is generated from a declaration
## rather than converted from anything — so its model is *committed*, in
## `TOOL_BODY_DIRECTORY`, inside the shipping tree, and present in every clone.
## Absence-tolerance still holds for it in the sense that matters (delete the file
## and two boxes stand in), but nothing has to be installed for a player to hold
## the real tool.
##
## Three things it is careful about:
##
## * **Nothing here is a second opinion about the Run.** Sway comes off
##   `query_player_velocity`, the kick off `query_player_last_shot_tick`, the clip
##   off `WeaponAnimator` — which is itself only told query results. The clip's
##   *time* is computed from ticks and seeked explicitly rather than left to the
##   engine's clock, so what is on screen is a function of Simulation state and a
##   replay looks the same twice.
## * **A pack names its takes its own way.** `Shoot` against `Knife_Attack_1_Anim`,
##   `PutAway` against `Holster`. `CLIP_NEEDLES` is the whole of the translation,
##   and a weapon whose model lacks a take simply never plays that role.
## * **One model is built per weapon, once.** A weapon change hides one and shows
##   another; nothing is loaded twice and the scene tree does not grow as a Run
##   goes on.
class_name WeaponViewmodel
extends Node3D

## Where a **self-authored** held object's model lives: `<id>.glb`, committed, in
## the shipping tree, present in every clone. The Build Gun is the only one, and
## `tools/assets/generate_build_gun.sh` is what writes it — out of the same parts
## kit and the same palette the Machines are generated from, which is why it can
## be committed at all: nothing in it derives from a purchased pack.
const TOOL_BODY_DIRECTORY: String = "res://assets/gear/"

## Where a converted first-person weapon model lives: `<weapon id>.glb`. Outside
## the shipping tree, gitignored, and usually not there — which is an ordinary
## state and not a warning, exactly as a Machine with no `.glb` is.
## `tools/assets/convert_weapons.sh` is what writes it.
const WEAPON_BODY_DIRECTORY: String = "res://assets_licensed/generated/gear/"

## Where `_load` looks, in order, and the order is a decision rather than a list.
##
## **The committed directory is asked first, because it is the one with a proof
## behind it.** #57's rule is that where output is committed you prove it and
## where it is gitignored you date it, and the Build Gun's mesh is regenerated
## and compared byte for byte by the asset suite. A `build_gun.glb` appearing in
## the quarantine would be a second answer to what the tool looks like with no
## proof under it, and the louder failure by far is a developer who regenerates
## the committed model, renders it, and sees no change.
const BODY_DIRECTORIES: Array = [TOOL_BODY_DIRECTORY, WEAPON_BODY_DIRECTORY]

## How far down, right and forward of the camera the **placeholder** sits, in
## metres. A converted model needs none of this: it is baked into the camera space
## its own authoring camera defined, so it arrives already in frame.
const PLACEHOLDER_OFFSET: Vector3 = Vector3(0.22, -0.20, -0.45)

## How far the weapon drops out of frame while a player is Downed or dead, in
## metres. Far enough to be gone, because a weapon still in frame while bleeding
## out reads as a bug.
const STOWED_METRES: float = 0.9

## How far the weapon swings as a player walks, in metres per metre per second of
## their own speed, and the cap on it. Driven by `query_player_velocity` rather
## than by a clock, so a player standing still has a steady weapon.
const SWAY_PER_SPEED: float = 0.012
const SWAY_LIMIT_METRES: float = 0.06

## How far the weapon recoils towards the camera on a shot, in metres, and how many
## ticks it takes to come back. Separate from the Simulation's own view kick — that
## one moves the *aim* and is authoritative; this one moves the model.
const RECOIL_METRES: float = 0.09
const RECOIL_TICKS: int = 8

## How a role finds its clip in a model that has never heard of this game's
## vocabulary. Each role lists the fragments a take's name might contain, best
## first; matching is case-insensitive, and where several names match the
## **shortest** wins, so `Shoot` beats `Shoot2`.
##
## Resolution order matters and is `_resolve_clips`': `reload_start` and
## `reload_end` are claimed before `reload`, or the plain `reload` needle would
## swallow all three.
const CLIP_NEEDLES: Dictionary = {
	WeaponAnimator.RELOAD_START: ["reload_start"],
	WeaponAnimator.RELOAD_END: ["reload_end"],
	WeaponAnimator.RELOAD: ["reload"],
	WeaponAnimator.CYCLE: ["chamber", "pump"],
	WeaponAnimator.FIRE: ["shoot", "fire", "attack"],
	WeaponAnimator.DRAW: ["draw"],
	WeaponAnimator.HOLSTER: ["putaway", "put_away", "holster"],
	WeaponAnimator.RUN: ["run"],
	WeaponAnimator.WALK: ["walk"],
	WeaponAnimator.IDLE: ["idle"],
}

## A take the vendor ships as a convenience: every action end to end on one
## timeline (docs/LICENSED_ASSETS.md). The converter drops it; this is the belt to
## that braces, because playing it would look like the weapon having a seizure.
const IGNORED_CLIPS: Array = ["default", "baselayer"]

var _animator: WeaponAnimator = WeaponAnimator.new()
var _placeholder: Node3D = null
var _placeholder_barrel: MeshInstance3D = null
## Weapon id -> the loaded model's root. A weapon with no GLB is absent from it
## and never looked up again.
var _models: Dictionary = {}
## Weapon id -> AnimationPlayer inside that model.
var _players: Dictionary = {}
## Weapon id -> role -> clip name, resolved once when the model is loaded.
var _clips: Dictionary = {}
var _shown_weapon: String = ""
var _role: String = ""


func _init() -> void:
	_placeholder = Node3D.new()
	_placeholder.position = PLACEHOLDER_OFFSET
	add_child(_placeholder)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(0.07, 0.11, 0.34)
	body.material_override = _unshaded(Color(0.21, 0.22, 0.20))
	_placeholder.add_child(body)
	_placeholder_barrel = MeshInstance3D.new()
	_placeholder_barrel.mesh = BoxMesh.new()
	(_placeholder_barrel.mesh as BoxMesh).size = Vector3(0.035, 0.035, 0.40)
	_placeholder_barrel.material_override = _unshaded(Color(0.14, 0.14, 0.15))
	_placeholder.add_child(_placeholder_barrel)


## Put the weapon where the Simulation says it should be, playing what the
## Simulation says it should be playing.
func sync(sim: Simulation, player_id: int) -> void:
	show_held(held_facts(sim, player_id))


## What the Simulation says about the thing in this player's hands.
##
## Public because **the thing in a player's hands is not always their weapon**: a
## holster that swaps between a weapon and the Build Gun is one field of this
## struct, not a second view model. Take these, change `weapon` to the id of
## whatever is being held, hand them back to `show_held`, and the holster, the
## model swap and the draw all happen for free — those are already first-class
## roles here rather than a special case, because `Draw` and `PutAway` are
## first-class takes in the packs.
func held_facts(sim: Simulation, player_id: int) -> WeaponAnimator.Facts:
	return _facts(sim, player_id)


## Put one held object in frame, playing what these facts say it should be
## playing. `facts.weapon` is an id and nothing more: whatever `<id>.glb` the
## directory holds is what is drawn, and the placeholder stands in when it holds
## nothing.
func show_held(facts: WeaponAnimator.Facts) -> void:
	visible = not facts.weapon.is_empty() and facts.alive

	# Load the new weapon's model now and *show* it later: the holster belongs to
	# the weapon leaving frame, so what is on screen is the cue's weapon rather
	# than the one in the player's hands, and the clip lengths the animator works
	# from have to be the outgoing model's for exactly as long as that lasts.
	_ensure_loaded(facts.weapon)
	var measured: String = _shown_weapon if not _shown_weapon.is_empty() else facts.weapon
	_animator.set_clip_lengths(_clip_lengths(measured))
	var cue: WeaponAnimator.Cue = _animator.cue(facts)
	_show(cue.weapon)
	_play(cue)
	_role = cue.role

	# A melee weapon is short and a rifle is long, read off the weapon's own reach
	# rather than off a table here — so a fourth weapon looks different without
	# this file changing.
	(_placeholder_barrel.mesh as BoxMesh).size = Vector3(
		0.035, 0.035, clampf(0.12 + facts.reach_metres * 0.006, 0.12, 0.55)
	)
	_placeholder_barrel.position = Vector3(
		0.0, 0.0, -(_placeholder_barrel.mesh as BoxMesh).size.z * 0.6
	)

	var sway: float = minf(facts.speed * SWAY_PER_SPEED, SWAY_LIMIT_METRES)
	var recoil: float = 0.0
	if facts.last_shot_tick >= 0:
		var since: int = facts.tick - facts.last_shot_tick
		if since >= 0 and since < RECOIL_TICKS:
			recoil = RECOIL_METRES * (1.0 - float(since) / float(RECOIL_TICKS))
	var stowed: float = 0.0 if facts.alive else STOWED_METRES
	# Survey View lifts the camera to read the Factory, so the weapon comes down
	# out of the way of the thing the player raised the camera to look at.
	stowed += STOWED_METRES * facts.survey_blend

	position = Vector3(sway, -sway - stowed, recoil)


## Whether a converted model is on screen rather than the placeholder.
func has_model() -> bool:
	return _models.has(_shown_weapon)


## Which weapon's model is in frame. Lags what the player is holding for exactly as
## long as the holster takes.
func model_weapon() -> String:
	return _shown_weapon


## Which role is playing. For the smoke test, and for anybody wondering why the
## arms are doing that.
func clip_role() -> String:
	return _role


## The clip name the model on screen resolved a role to, or empty when it has no
## take for it. Empty for every role while the placeholder is up.
func clip_name(role: String) -> String:
	if not _clips.has(_shown_weapon):
		return ""
	return String((_clips[_shown_weapon] as Dictionary).get(role, ""))


func _facts(sim: Simulation, player_id: int) -> WeaponAnimator.Facts:
	var facts: WeaponAnimator.Facts = WeaponAnimator.Facts.new()
	facts.tick = sim.query_tick()
	facts.weapon = sim.query_player_weapon(player_id)
	facts.alive = sim.query_player_is_alive(player_id)
	var velocity: FixedVec2 = sim.query_player_velocity(player_id)
	facts.speed = Vector2(
		Fixed.to_float(velocity.x), Fixed.to_float(velocity.z)
	).length()
	facts.sprinting = sim.query_player_is_sprinting(player_id)
	facts.last_shot_tick = sim.query_player_last_shot_tick(player_id)
	facts.interval_ticks = sim.query_player_weapon_interval_ticks(player_id)
	facts.shots_remaining = sim.query_player_shots_remaining(player_id)
	facts.is_melee = sim.query_player_weapon_is_melee(player_id)
	facts.reach_metres = Fixed.to_float(sim.query_player_weapon_range_metres(player_id))
	facts.survey_blend = Fixed.to_float(sim.query_player_survey_blend(player_id))
	# The one figure here that is tuning rather than a per-player query, and it is read
	# through `query_definitions` like every other number this layer needs: a swap is the
	# same length for everybody in the Run.
	facts.swap_seconds = Fixed.to_float(sim.query_definitions().player_holster_seconds)
	return facts


## Load a weapon's model if it has one and this is the first time it is wanted.
## Separate from showing it so a weapon change does not hitch half way through
## the holster, which is the one frame it would be visible in.
func _ensure_loaded(weapon_id: String) -> void:
	if weapon_id.is_empty() or _models.has(weapon_id) or _clips.has(weapon_id):
		return
	_load(weapon_id)
	# Remembered either way: a weapon with no GLB must not be looked for again
	# every frame for the rest of the Run.
	if not _clips.has(weapon_id):
		_clips[weapon_id] = {}


## Bring one weapon's model into frame.
func _show(weapon_id: String) -> void:
	if weapon_id == _shown_weapon:
		return
	_shown_weapon = weapon_id
	_ensure_loaded(weapon_id)
	for id: String in _models:
		(_models[id] as Node3D).visible = id == weapon_id
	_placeholder.visible = not _models.has(weapon_id)


## Load `<weapon id>.glb` if it is there, and do nothing at all if it is not.
##
## Absence is an ordinary state, and the whole licence rule rests on it staying
## that way: nothing non-redistributable may be committed, and nothing may be
## *required* either.
func _load(weapon_id: String) -> void:
	var path: String = ""
	for directory: String in BODY_DIRECTORIES:
		var candidate: String = "%s%s.glb" % [directory, weapon_id]
		if FileAccess.file_exists(candidate):
			path = candidate
			break
	if path.is_empty():
		return
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		push_warning("weapon viewmodel %s did not parse as glTF" % path)
		return
	# `remove_immutable_tracks` is **off**, and the default being on is a trap with a
	# measured bite (#64). Godot drops an animation track whose value never changes,
	# which leaves an animation that is nothing but such tracks existing and empty —
	# and `_play` below then "plays" it and moves nothing, so the model stays frozen
	# in whatever pose the *previous* clip left it in. The Build Gun's `Idle` is one
	# key at rest on purpose, so it is exactly that animation: the tool loaded, both
	# swap takes resolved, `has_model` was true, and the thing on screen sat half a
	# metre under the bottom of the frame at `Draw`'s stowed opening key. Every
	# purchased weapon ships a breathing idle, which is why nothing had ever met it.
	#
	# Blender optimises the same track away on the way *out* for the same reason, so
	# this is one half of a pair — `generate_build_gun.py` passes
	# `export_optimize_animation_keep_anim_object` for the other.
	var loaded: Node = document.generate_scene(state, 30.0, false, false)
	if loaded == null or not loaded is Node3D:
		push_warning("weapon viewmodel %s carried no 3D scene" % path)
		return
	add_child(loaded)
	_models[weapon_id] = loaded as Node3D
	var player: AnimationPlayer = _animation_player(loaded)
	if player != null:
		_players[weapon_id] = player
		# We seek the clip ourselves every frame, from the tick count, so the
		# engine's own clock must not also advance it.
		player.speed_scale = 0.0
		_clips[weapon_id] = _resolve_clips(player)
	else:
		_clips[weapon_id] = {}


func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _animation_player(child)
		if found != null:
			return found
	return null


## Match each role against the names this model actually carries.
func _resolve_clips(player: AnimationPlayer) -> Dictionary:
	var available: PackedStringArray = PackedStringArray()
	for name: String in player.get_animation_list():
		if not IGNORED_CLIPS.has(name.to_lower()):
			available.append(name)
	var resolved: Dictionary = {}
	var claimed: Dictionary = {}
	for role: String in CLIP_NEEDLES:
		for needle: String in CLIP_NEEDLES[role]:
			var best: String = ""
			for name: String in available:
				if claimed.has(name) or not name.to_lower().contains(needle):
					continue
				# The shortest match, so `Shoot` wins over `Shoot2`.
				if best.is_empty() or name.length() < best.length():
					best = name
			if not best.is_empty():
				resolved[role] = best
				claimed[best] = true
				break
	return resolved


## How long each role's clip is on the model in frame, in seconds. Empty for the
## placeholder, which is what makes `WeaponAnimator` fall back to its own lengths.
func _clip_lengths(weapon_id: String) -> Dictionary:
	if not _players.has(weapon_id):
		return {}
	var player: AnimationPlayer = _players[weapon_id]
	var lengths: Dictionary = {}
	for role: String in _clips[weapon_id]:
		var animation: Animation = player.get_animation(_clips[weapon_id][role])
		if animation != null and animation.length > 0.0:
			lengths[role] = animation.length
	return lengths


## Put the cue on the model: the right clip, at the time the tick count says.
func _play(cue: WeaponAnimator.Cue) -> void:
	if not _players.has(_shown_weapon):
		return
	var player: AnimationPlayer = _players[_shown_weapon]
	var name: String = clip_name(cue.role)
	if name.is_empty():
		# A model with no take for this role falls back to standing there rather
		# than freezing on whatever pose it was last left in.
		name = clip_name(WeaponAnimator.IDLE)
		if name.is_empty():
			return
	if player.current_animation != name:
		player.play(name)
	var animation: Animation = player.get_animation(name)
	var at: float = cue.seconds
	if cue.loop and animation.length > 0.0:
		at = fmod(at, animation.length)
	player.seek(minf(at, maxf(animation.length - 0.0001, 0.0)), true)


## An unshaded material. A placeholder at eye level is lit by nothing in
## particular, so one that took the directional light would vanish whenever a
## player faced away from the sun.
func _unshaded(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
