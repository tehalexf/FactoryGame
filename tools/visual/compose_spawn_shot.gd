## Composes a screenshot of **what a player sees the moment a Run starts**, and writes it
## to a PNG.
##
##   bash tools/visual/shot.sh out.png spawn   SHOT_SCRIPT=tools/visual/compose_spawn_shot.gd
##
## A tool, not part of the game, and the third sibling of `compose_shot.gd` and
## `compose_building_shot.gd`. Those two frame the Factory — one from a chosen vantage to
## judge how the world looks, one through the Build Gun to judge what a player is told while
## they work — and both of them stand the player somewhere useful first. **This one refuses
## to.** The subject is the opening thirty seconds, which is the one view no existing composer
## framed and the one #52 is about: a player on the Nest's crown, pointed where a Run points
## them, asked to go and find ore they have never seen.
##
## So nothing here walks, lifts or aims unless the preset says so. The camera is wherever
## `_respawn` put it, which is the middle of the Nest's footprint, and the yaw is 0 because a
## Run starts looking down -z. **A composer that improved the vantage would be answering a
## question nobody asked.**
##
## Three presets:
##
##   spawn    tick 0, where a Run puts you, looking where a Run points you. The defect.
##   turned   the same spot, turned to face the nearest shallow ore. Can you see it?
##   survey   the same spot in Survey View, which is where the whole Map's ore is readable
##            at once — including the deep seams a Mk1 cannot lift.
##
## The HUD is **left on**, as in `compose_building_shot.gd`: the objective line is half the
## subject, because #52's second part is the line that points you.
extends SceneTree

const FRAMES_TO_SETTLE: int = 30

## Whether every tick this tool steps is a tick with Survey View held. Held, so a tick that
## forgot the intent is a tick the camera spent coming back down.
var _surveying: bool = false


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	var preset: String = "spawn" if arguments.size() < 2 else arguments[1]

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	# A few ticks so the set dressing and the lighting have been synced and the player has
	# settled onto the Nest's crown. Deliberately short: a Run has not had time to do
	# anything, which is the state this shot is about.
	for tick: int in range(6):
		_step(sim, [])

	# Both of these turn first, and the survey preset turning is a finding rather than a
	# convenience: Survey View looks the way the player is looking, so a lift taken at the
	# spawn yaw frames the empty ground north of the Nest and every Node on this Map is south
	# or east of it. The first survey render showed no ore at all and the mark was innocent.
	if preset != "spawn":
		_turn_towards(sim, _nearest_shallow_ore(sim))
	if preset == "survey":
		_lift_into_survey(sim)

	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		_step(sim, [])
		view.sync(sim)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print(
		"wrote %s (%dx%d) — %s, %s"
		% [
			out_path,
			image.get_width(),
			image.get_height(),
			preset,
			Objective.line(sim, 0)
		]
	)
	quit()


## The nearest Depth 1 Node to the player, by resource and tier rather than by index, so a
## Map change moves the shot rather than breaking it.
##
## Deliberately **not** `query_node_is_workable_now`: this tool has to be runnable against the
## tree as it was before #52 to produce the "before" half of a pair, and a composer that only
## compiles against the change it is illustrating cannot illustrate it.
func _nearest_shallow_ore(sim: Simulation) -> Vector3:
	var here: FixedVec2 = sim.query_player_position(0)
	var best: Vector3 = Vector3.ZERO
	var best_gap: float = -1.0
	for index: int in range(sim.query_node_count()):
		if sim.query_node_depth(index) != 1:
			continue
		var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_node_tile(index))
		var at: Vector3 = Vector3(Fixed.to_float(centre.x), 1.0, Fixed.to_float(centre.z))
		var gap: float = (
			Vector2(at.x, at.z) - Vector2(Fixed.to_float(here.x), Fixed.to_float(here.z))
		).length()
		if best_gap < 0.0 or gap < best_gap:
			best_gap = gap
			best = at
	return best


## One tick, with Survey View carried along if it is up.
func _step(sim: Simulation, actions: Array) -> void:
	var carried: Array = actions.duplicate()
	carried.append(InputAction.survey_view(0, _surveying))
	sim.step(carried)


func _lift_into_survey(sim: Simulation) -> void:
	_surveying = true
	for tick: int in range(90):
		_step(sim, [])


## Turns the player on the spot until they are looking at a point. The yaw only — the pitch
## stays where a Run left it, because what is under test is whether ore is findable by
## *turning round*, which is the one thing the objective line asks a player to do.
func _turn_towards(sim: Simulation, target: Vector3) -> void:
	var sensitivity: float = Fixed.to_float(sim.query_definitions().player_look_sensitivity)
	if is_zero_approx(sensitivity):
		return
	for attempt: int in range(12):
		var ground: FixedVec2 = sim.query_player_camera_ground_metres(0)
		var want: Vector3 = (
			target - Vector3(Fixed.to_float(ground.x), target.y, Fixed.to_float(ground.z))
		).normalized()
		var wanted_yaw: float = atan2(-want.x, -want.z) / TAU
		var gap: float = _shortest_turn(
			wanted_yaw - Fixed.to_float(sim.query_player_yaw_turns(0))
		)
		if absf(gap) < 0.0005:
			return
		# Right is a decrease in yaw, so the sign flips.
		_step(sim, [
			InputAction.look(0, InputQuantiser.pixels_to_fixed(-gap / sensitivity * 1000.0), 0)
		])


## A turn difference brought into [-0.5, 0.5], so turning never takes the long way round.
func _shortest_turn(turns: float) -> float:
	var wrapped: float = fposmod(turns, 1.0)
	return wrapped - 1.0 if wrapped > 0.5 else wrapped
