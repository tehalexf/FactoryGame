## Composes a strip of screenshots **through a player's own death**, and writes one PNG per
## sample.
##
##   SHOT_SCRIPT=tools/visual/compose_death_shot.gd bash tools/visual/shot.sh out.png dead
##
## Writes `out.png` for the first sample and `out_NN.png` for the rest, NN being the number
## of ticks since the bite that killed them.
##
## A tool, not part of the game, and a sibling of `compose_swing_shot.gd` rather than of
## `compose_mark_shot.gd`: the subject is **a gesture over half a second**, so one still
## frame cannot settle it and the camera cannot be placed, because what is under test is
## where the Simulation put the camera. Everything here is read through the player's own
## eyes for exactly the reason #54 exists — "a player who dies can tell at a glance" is a
## claim about one viewpoint and no other.
##
## Four presets:
##
##   dead      a solo death, the whole fall, with the overlay (#54's after)
##   before    the same death with `player.death_view_drop_metres = 0` (#54's before)
##   downed    a co-op Downed player, propped on an elbow rather than flat
##   bare      an extra word, not a preset: hides the yard
##   plain     an extra word: hides the first-person arms
##
## **`plain` is a licensing requirement rather than a composition choice, and the committed
## pair uses it.** The arms are the purchased RgsDev viewmodels, and a render of them is
## exactly as non-redistributable as the FBX they came from (docs/ASSETS.md) — which is why
## `compose_swing_shot.gd` says its own strip may never be committed. What #54 is about is
## where the camera is and what is over it, so taking the hands out costs the picture
## nothing it was being used to judge. Render without it to see what a player sees.
##
## **`before` is honest rather than reconstructed, and that is a property of the design
## rather than a trick of the tool.** The overlay is driven by the very same
## `query_player_collapse_blend` the view is, so a drop of zero turns off the fall, the
## bank and the tint together and leaves exactly what shipped before this ticket: upright
## at full eye height, with `DEAD — back at the Nest in 7s` in the HUD's gear block in the
## same small type as `power 660/900 kW`.
extends SceneTree

const FRAMES_TO_SETTLE: int = 12

## Which ticks after the killing bite to photograph. `player.collapse_seconds` is 0.45,
## which is 27 ticks, so these walk the gesture end to end and then stand well past it: 27
## is the settled posture, and 120 is two seconds into the wait, which is what a player
## actually spends the respawn looking at.
##
## **The upright frame is taken separately and earlier**, on the *first* bite rather than
## on the killing one, and that is forced rather than chosen: the tool cannot step
## backwards, so a negative sample would photograph somebody already on their way down. A
## fragile player takes two bites, so the first is about a second before the second — which
## makes the standing frame a player under attack and still on their feet, which is the
## right thing for the fall to read against anyway.
const SAMPLES: Array = [3, 9, 15, 21, 27, 120]

## How far north of the origin the starter Map's Breach-to-Nest lane runs, in ticks of held
## forward throttle. `test_gear.gd`'s worked example, borrowed with its arithmetic: the Nest
## is at tile (-6, -6) and the Breach at (16, -6), so the lane is the centre of row z = -6,
## eleven metres from where a Run starts the player — and `player.walk_speed_metres_per_second`
## is 4 off an acceleration of 24, so ten ticks to full speed and a sixtieth of 4 m a tick
## after it puts 170 ticks within three centimetres of the lane.
##
## Being killed is something a player does to themselves by standing somewhere, and the tool
## says so rather than teleporting anybody.
const TICKS_TO_THE_LANE: int = 170

## Six Crawlers a Breach, flat, so something arrives from a cold start and keeps arriving.
const MANY_CRAWLERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
"""

## Twenty hit points against a Crawler's ten a bite, so the render is of a death rather than
## of a siege, and a Telegraph short enough that the called Wave is on its way immediately.
const OVERRIDES: Array = [
	["health = 150", "health = 20"],
	["telegraph_seconds = 12", "telegraph_seconds = 0.5"],
]

## What `before` changes, and the whole of it.
const GESTURE_OFF: Array = [["death_view_drop_metres = 1.42", "death_view_drop_metres = 0"]]

## What the upright frame is named. Written as if it were a sample so the strip reads in
## order and the first frame keeps the plain `out.png` name every composer here writes.
const STANDING_LABEL: int = 0

## How long to wait for a Crawler to cross eight tiles and bite twice. Bounded, because a
## tool that hangs is worse than one that renders the wrong frame.
const TICKS_TO_WAIT: int = 2400


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	var words: String = "dead" if arguments.size() < 2 else arguments[1]
	var preset: String = "before" if words.contains("before") else (
		"downed" if words.contains("downed") else "dead"
	)
	var bare: bool = words.contains("bare")
	var plain: bool = words.contains("plain")

	var players: int = 2 if preset == "downed" else 1
	var sim: Simulation = Simulation.new(11, players, _content(preset))
	var view: WorldView = WorldView.new()
	root.add_child(view)

	# A weapon in hand rather than the Build Gun, which is what a Run opens with since #42 —
	# stated rather than assumed, because what drops out of frame on a death is half of what
	# the before picture already had.
	if sim.query_player_is_in_build_mode(0):
		sim.step([InputAction.set_build_mode(0, false)])
	sim.step([InputAction.call_wave_early(0)])

	# Settle the renderer before anything happens, so the strip opens on the carriage a player
	# is standing in rather than on the end of a draw.
	for frame: int in range(40):
		await process_frame
		sim.step([])
		view.sync(sim)

	_walk_into_the_road(sim)

	# The upright frame first, on the *first* bite: a player under attack and still standing.
	if not _wait_for(sim, func() -> bool: return (
		sim.query_player_health(0) < sim.query_player_max_health(0)
	)):
		push_error("nothing reached the player inside %d ticks" % TICKS_TO_WAIT)
		quit(1)
		return
	await _photograph(sim, view, out_path, STANDING_LABEL, bare, plain)

	if not _wait_for(sim, func() -> bool: return not sim.query_player_is_alive(0)):
		push_error("nothing killed the player inside %d ticks" % TICKS_TO_WAIT)
		quit(1)
		return
	var bite: int = sim.query_tick()

	for sample: int in SAMPLES:
		while sim.query_tick() < bite + sample:
			sim.step([])
		await _photograph(sim, view, out_path, sample, bare, plain)
	print(
		"%s: the bite landed on tick %d; down=%s dead=%s"
		% [
			preset,
			bite,
			str(sim.query_player_is_downed(0)),
			str(sim.query_player_is_dead(0)),
		]
	)
	quit()


## The shipped content, with the Waves flattened and the player made fragile — and for
## `before`, with the gesture switched off at its one key.
func _content(preset: String) -> Definitions:
	var tuning: String = ContentFixture.shipped(Definitions.TUNING_FILE)
	var substitutions: Array = []
	substitutions.append_array(OVERRIDES)
	if preset == "before":
		substitutions.append_array(GESTURE_OFF)
	for pair: Array in substitutions:
		if not tuning.contains(str(pair[0])):
			push_error("the tuning override '%s' matched nothing" % pair[0])
		tuning = tuning.replace(str(pair[0]), str(pair[1]))
	return Definitions.parse(
		ContentFixture.shipped(Definitions.MACHINES_FILE),
		ContentFixture.shipped(Definitions.RECIPES_FILE),
		tuning,
		MANY_CRAWLERS,
		ContentFixture.shipped(Definitions.DELIVERIES_FILE),
		ContentFixture.shipped(Definitions.GEAR_FILE),
		ContentFixture.shipped(Definitions.STRATAGEMS_FILE),
		Definitions.MACHINES_FILE,
		Definitions.RECIPES_FILE,
		Definitions.TUNING_FILE,
		Definitions.WAVES_FILE,
		Definitions.DELIVERIES_FILE,
		Definitions.GEAR_FILE,
		Definitions.STRATAGEMS_FILE,
		ContentFixture.shipped(Definitions.PORTS_FILE),
		Definitions.PORTS_FILE,
		ContentFixture.shipped(Definitions.STRUCTURES_FILE),
		Definitions.STRUCTURES_FILE
	)


## Holds the forward throttle until the player is standing in the lane a Wave walks.
func _walk_into_the_road(sim: Simulation) -> void:
	for tick: int in range(TICKS_TO_THE_LANE):
		sim.step([InputAction.move(0, Fixed.ONE, 0)])


## Steps until `condition` holds, and reports whether it ever did. Bounded, because a tool
## that hangs is worse than one that renders the wrong frame.
func _wait_for(sim: Simulation, condition: Callable) -> bool:
	for tick: int in range(TICKS_TO_WAIT):
		if condition.call():
			return true
		sim.step([])
	return false


## Settles the renderer, writes one frame, and prints every number the picture is about.
##
## The numbers matter as much as the image: #42 spent three renders separating "the maths is
## too subtle to see" from "the plumbing does not work", and those two look identical in a
## picture. A drop of 1.42 m printed beside a frame that looks unchanged is the first; a drop
## of 0.00 is the second.
func _photograph(
	sim: Simulation, view: WorldView, out_path: String, sample: int, bare: bool, plain: bool
) -> void:
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		if bare:
			_hide_the_yard(view)
		if plain:
			view.weapon_viewmodel().visible = false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = out_path if sample == STANDING_LABEL else "%s_%02d.%s" % [
		out_path.get_basename(), sample, out_path.get_extension()
	]
	image.save_png(path)
	# One string literal rather than two concatenated: `%` binds tighter than `+`, so a split
	# format string formats the second half and glues the first one in front of the result.
	print(
		"wrote %s — tick %+d, eye %.2f m, drop %.2f m, bank %.1f deg, blend %.2f, tint %.2f, caption '%s'" % [
			path,
			sample,
			Fixed.to_float(sim.query_player_camera_height_metres(0)),
			Fixed.to_float(sim.query_player_view_collapse_metres(0)),
			Fixed.to_float(sim.query_player_view_collapse_roll_turns(0)) * 360.0,
			Fixed.to_float(sim.query_player_collapse_blend(0)),
			view.mortality_tint_alpha(),
			view.mortality_caption(),
		]
	)


## `bare` hides the yard, for the reason `compose_mark_shot.gd` has it: a prop standing in
## front of a mark and a mark that was never drawn look identical in a picture.
func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false
