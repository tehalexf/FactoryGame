## Composes a screenshot of a Wave arriving on a working Factory, and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_wave_shot.gd bash tools/visual/shot.sh out.png [preset]
##
## A tool, not part of the game, and it exists for the reason `compose_shot.gd` does: the only
## honest way to judge how the thing a player spends a whole Run shooting at *looks* is to look
## at it. Render, read the image, change something, render again. #38 was judged this way and
## three of its decisions came out of an image rather than out of reasoning.
##
## It drives the real `Simulation` with real Input Actions and lets the real `WorldView` draw
## it. The only two things it does that the game does not are move the camera — a composed shot
## wants a chosen vantage, where the Simulation's camera follows the player — and replace the
## Wave table, so that Crawlers, Breakers and a Siege Hulk are all on the Map at once instead
## of at the twenty-six and thirty-odd minutes their Heat thresholds put them at.
##
## Presets:
##
## * `swarm` — a mixed Wave at head height, close enough to read a gait. The default, and the
##   one that answers "does a Crawler read as a scuttling thing rather than a box".
## * `pair` — a Crawler and a Breaker side by side, filling the frame. The one that answers
##   "are these two distinguishable at a glance", which is the acceptance criterion a wide
##   shot cannot settle.
## * `boss` — a Siege Hulk from behind and to one side, which is where its glowing vent is.
## * `distance` — the whole yard with the Wave crossing it, at the thirty metres a player
##   actually triages from.
## * `crush` — a Wave that has been **shot at**, framed on the spot where the last Enemy fell,
##   at thirty metres. #70's preset, and the only one in which anything on the Map has taken a
##   round: see `_shoot_the_wave`.
##
## Three extra words on the command line: `hud` keeps the overlay, `bare` hides the set
## dressing, and `near` brings `crush`'s camera in to ten metres — the diagnostic beside the
## thirty the criterion names, because a picture that shows nothing at thirty cannot say
## whether a mark is too small or is not being drawn.
##
## `bare` is for the close-ups only, and it earns its place honestly: the yard is
## dense enough that a camera placed by arithmetic ends up behind a pipe rack about half the
## time, and "is this character posed and scaled correctly" is not a question about the yard.
## Judge the *grade* on a dressed shot; judge the *geometry* on a bare one.
extends SceneTree

const FRAMES_TO_SETTLE: int = 40

## Every tier at Heat 0 and a short Telegraph, so one call of the lever puts the whole bestiary
## on the Map. The shipped thresholds are 0, 5200 and 6400, which is minute one, minute
## twenty-six and a Run better than any the balance harness has measured.
const EVERY_TIER: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
shock_breakers,breaker,0,2,0,2
siege_hulks,siege_hulk,0,1,0,1
"""


func _initialize() -> void:
	var given: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if given.size() < 1 else given[0]
	# `shot.sh` forwards exactly two arguments, so the extra words ride in on the second one
	# separated by spaces: `shot.sh out.png "pair bare"`. Split rather than add a third
	# parameter to a script four other composers already share.
	var arguments: PackedStringArray = PackedStringArray()
	for word: String in " ".join(given.slice(1)).split(" ", false):
		arguments.append(word)
	var preset: String = "swarm" if arguments.size() < 1 else arguments[0]

	var sim: Simulation = Simulation.new(1, 1, _content(preset))
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_build_a_factory(sim)
	sim.step([InputAction.call_wave_early(0)])
	# Long enough for every tier to have trickled out of its Breach and taken a few strides,
	# and short enough that they are still bunched together near it — which is what makes a
	# close shot of two kinds side by side possible at all. A scenario cannot place an Enemy;
	# the only lever on where they are is how long you wait.
	# `crush` waits far longer, and the reason is composition rather than patience: a Wave
	# trickles out of one Breach, so at seven seconds every kind is standing in one heap and a
	# render of it is a render of a pile. Thirty seconds at the slowed speeds below is enough
	# for the release order to become a column several metres long — which is what lets a hurt
	# Breaker, a fresh one and the spot a Crawler fell on be three separate things in a frame.
	var settle: int = (30 if preset == "crush" else 7) * Simulation.TICKS_PER_SECOND
	for tick: int in range(settle):
		sim.step([])
	view.sync(sim)
	var struck: Vector3 = Vector3.ZERO
	if preset == "crush":
		struck = _shoot_the_wave(sim, view)

	var camera: Camera3D = _camera_of(view)
	_frame(camera, sim, preset, struck, arguments.has("near"))
	if not arguments.has("hud"):
		_hide_the_overlay(view)
	if arguments.has("bare"):
		_hide_the_yard(view)

	# The sky, the reflections, SSAO and the four shadow cascades all take a frame or two, so
	# a shot taken on frame one is a shot of a half-built frame. The Simulation is *not*
	# stepped through the settle, because the point is one pose held still — a swarm that
	# walked out of the frame while the renderer warmed up would be a shot of the ground.
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		view.sync(sim)
		_frame(camera, sim, preset, struck, arguments.has("near"))
		if not arguments.has("hud"):
			_hide_the_overlay(view)
		if arguments.has("bare"):
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	print("wrote %s (%dx%d): %d enemies" % [
		out_path, image.get_width(), image.get_height(), sim.query_enemy_count()
	])
	quit()


## The shipped content with three substitutions, and the third one only for `crush`.
##
## `crush` needs a player who can shoot and a Wave that will hold still long enough to be shot
## at **from thirty metres** — which is the one distance this ticket is judged at, and a Wave
## at its shipped speed crosses it in about fifteen seconds. So the two Chaff speeds come down
## and the opening bill carries rounds, exactly as `test_world_view`'s own rifleman fixture
## slows a Breaker to hold it still for an aimed shot. Neither reaches any other preset.
func _content(preset: String) -> Definitions:
	var stock: String = "iron_plate:400"
	var tuning: String = (
		_read("res://content/tuning.toml")
			.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
	)
	if preset == "crush":
		stock = "ammunition:400;iron_plate:400"
		tuning = (
			tuning
			. replace(
				"crawler_speed_metres_per_second = 3",
				"crawler_speed_metres_per_second = 0.5"
			)
			. replace(
				"breaker_speed_metres_per_second = 2",
				"breaker_speed_metres_per_second = 0.45"
			)
		)
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		tuning.replace(
			'starting_stock = "iron_plate:110"', 'starting_stock = "%s"' % stock
		),
		EVERY_TIER,
		_read("res://content/deliveries.csv"),
		_read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv",
		"recipes.csv",
		"tuning.toml",
		"waves.csv",
		"deliveries.csv",
		"gear.csv",
		"stratagems.csv"
	)


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## The same small complete Factory `compose_shot.gd` builds — ore out of the ground, along a
## Belt, into a Smelter, with a Boiler on the grid and a Turret facing the Breach — because the
## question here is how the Enemies read *against the Factory*, not against bare ground.
func _build_a_factory(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	var node_tile: Vector3i = sim.query_node_tile(0)
	var miner: int = definitions.machine_index("miner_mk1")
	var smelter: int = definitions.machine_index("smelter_mk1")
	var boiler: int = definitions.machine_index("steam_boiler_mk1")
	var turret: int = definitions.machine_index("mg_turret_mk1")

	sim.step([InputAction.build_machine(0, miner, node_tile)])
	var smelter_tile: Vector3i = node_tile + Vector3i(6, 0, 0)
	sim.step([InputAction.build_machine(0, smelter, smelter_tile)])
	sim.step([
		InputAction.build_belt(
			0, node_tile + Vector3i(2, 0, 0), smelter_tile - Vector3i(1, 0, 0)
		)
	])
	sim.step([InputAction.build_machine(0, boiler, node_tile + Vector3i(0, 0, 5))])
	sim.step([InputAction.build_machine(0, turret, node_tile + Vector3i(6, 0, 5))])


## Puts rounds into the Wave until something has died **this very tick**, and hands back where
## it was standing when it did.
##
## #70's subject is a Wave that has been shot at, and nothing else in this file produces one:
## the Factory a composer builds has no Ammunition chain, so its Turret is dry from the first
## frame to the last. The player is the only gun on the Map that can be made to go off, so the
## shot is composed the way `test_world_view`'s rifleman fixture is driven — aim by sending the
## pixels that close the bearing, fire, and read the result back out of the queries rather than
## assuming it.
##
## **The last kill is timed rather than merely achieved.** Every mark #70 draws is aged by
## subtracting the tick it happened on from `query_tick`, so a death four seconds before the
## shutter is a death with nothing on screen. The loop therefore kills its Crawler last and
## stops six ticks later, which is inside the burst's own quarter of a second and outside
## #69's three-tick tracer.
func _shoot_the_wave(sim: Simulation, view: WorldView) -> Vector3:
	sim.step([InputAction.equip_weapon(0, sim.query_definitions().gear_index("bolt_rifle"))])
	# **Five rounds into one Breaker and none into the other**, which is the composition the
	# ticket asks for rather than a convenience: "a damaged Enemy is distinguishable from a
	# fresh one" is a claim about two bodies in one frame, so the shot has to contain both.
	# Five rounds of thirty take 150 of a Breaker's 240 and leave it on 90, and the second
	# Breaker stands beside it untouched. Measured rather than intended: the Wave stands in a
	# heap at its Breach, so every round aimed over the Chaff lands on whichever Breaker is
	# nearest, and a loop that meant to hurt both killed one and never touched the other.
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_BREAKER:
			continue
		for round_number: int in range(5):
			_put_one_round_into(sim, index, 1.15)
		break
	# And the last round of all into a Crawler, so the death is six ticks old when the camera
	# looks at it rather than minutes.
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_CRAWLER:
			continue
		var at: Vector3 = _enemy_at(sim, index)
		var serial: int = sim.query_enemy_serial(index)
		# The snapshot `CombatEvents` diffs against has to be taken **before** the killing
		# step: a serial never observed alive cannot be observed to have gone.
		_aim_at(sim, index)
		view.sync(sim)
		sim.step([InputAction.fire(0)])
		# A few ticks on, and only a render says why: #69's tracer is a rod from the muzzle
		# to the body, and a camera standing thirty metres off the subject rather than behind
		# the eye sees it side on — a cream ramp across half the frame, which is the loudest
		# thing in a picture that is supposed to be about an Enemy. Three ticks is its whole
		# life, so six puts the shot away and leaves the death.
		for tick: int in range(6):
			view.sync(sim)
			sim.step([])
		if sim.query_enemy_index_of_serial(serial) == -1:
			return at
		return Vector3.ZERO
	return Vector3.ZERO


## Aims and fires once, then waits out the weapon's own interval.
func _put_one_round_into(sim: Simulation, index: int, up: float) -> void:
	_aim_at(sim, index, up)
	sim.step([InputAction.fire(0)])
	for tick: int in range(sim.query_player_weapon_interval_ticks(0) + 1):
		sim.step([])


## Turns the player onto an Enemy's own hit volume, in one `LOOK` intent.
##
## `up` lifts the aim as a fraction of the target's own height, and it is how a Breaker gets
## shot at all: a Wave trickles out of one Breach and stands in a heap, so a round aimed at a
## 2.2 m Breaker's middle meets the 1.6 m Crawler in front of it every time — measured, the
## first version put twenty-four rounds into Chaff and left both Breakers on full health.
## 0.92 of a Breaker's height is still 2.02 m and a Crawler's capsule **top** is its 1.6 m plus
## its 0.6 m radius, so the second attempt missed for the same reason as the first. Above 1.0
## is therefore correct rather than a mistake: 1.15 is 2.53 m, over a Crawler and under a
## Breaker's own 3.0 m top.
func _aim_at(sim: Simulation, index: int, up: float = 0.5) -> void:
	var height: float = Fixed.to_float(sim.query_enemy_hit_height_metres(index))
	var aim: Vector2i = _pixels_onto(sim, _enemy_at(sim, index), height * up)
	sim.step([InputAction.look(0, Fixed.from_int(aim.x), Fixed.from_int(aim.y))])


func _enemy_at(sim: Simulation, index: int) -> Vector3:
	var at: FixedVec2 = sim.query_enemy_position_metres(index)
	return Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))


## The mouse travel that closes the bearing from where the player is looking onto a point, in
## the pixels a `LOOK` intent carries — `look_sensitivity_turns_per_1000_pixels` is the
## Simulation's own, so this is the same arithmetic `InputQuantiser` does inverted.
func _pixels_onto(sim: Simulation, to: Vector3, height: float) -> Vector2i:
	var at: FixedVec2 = sim.query_player_position(0)
	var facing: FixedVec2 = sim.query_player_facing(0)
	var want: Vector3 = to - Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
	var bearing: float = atan2(want.x, -want.z)
	var looking: float = atan2(Fixed.to_float(facing.x), -Fixed.to_float(facing.z))
	var turns: float = wrapf((bearing - looking) / TAU, -0.5, 0.5)
	# A round leaves at eye height and travels along the pitch, so a Crawler 1.6 m tall at
	# thirty metres is **under** a level aim by its own half-height. Only a miss said so: the
	# first version of this sent no pitch at all and put sixty rounds over the Wave's heads.
	var eye: float = Fixed.to_float(sim.query_player_eye_height_metres(0))
	var drop: float = atan2(eye - height, Vector2(want.x, want.z).length()) / TAU
	drop += Fixed.to_float(sim.query_player_camera_pitch_turns(0))
	var sensitivity: float = Fixed.to_float(sim.query_definitions().player_look_sensitivity)
	if sensitivity <= 0.0:
		return Vector2i.ZERO
	return Vector2i(
		int(round(turns * 1000.0 / sensitivity)), int(round(drop * 1000.0 / sensitivity))
	)


## Where to stand, and every preset is aimed at a question rather than at a view.
##
## Every one of them frames on something the Simulation put there — an Enemy, or the Breach
## they came out of — rather than on a hand-written coordinate, because the Wave walks and a
## fixed vantage is a shot of the ground it has left.
func _frame(
	camera: Camera3D, sim: Simulation, preset: String, struck: Vector3, near: bool
) -> void:
	camera.fov = 70.0

	if preset == "crush":
		# **The spot where the last Enemy fell, at thirty metres, square on from the player's
		# own side of it** — so what is in frame is a death that has just happened and the
		# survivors standing round it that the same rifle has already hurt. The camera is on
		# the player's side rather than anywhere prettier because every one of these marks is
		# about what the person holding the trigger can see.
		var at: FixedVec2 = sim.query_player_position(0)
		var player: Vector3 = Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
		# The spot the last Enemy fell on, or failing that whatever is still standing — never
		# the Crawler swarm's centre, which is the origin once the last Crawler is dead and
		# which framed one render on the Nest with the subject behind the camera.
		var subject: Vector3 = struck
		if subject == Vector3.ZERO:
			subject = _enemy_at(sim, 0) if sim.query_enemy_count() > 0 else _breach_centre(sim)
		var towards: Vector3 = player - subject
		if towards.length() < 0.01:
			towards = Vector3.BACK
		# Thirty metres is the distance the criterion names and `near` is the diagnostic beside
		# it: #49 needed `triage` because `pair` and `distance` both framed past its subject,
		# and a wound has the same problem in reverse — at thirty metres a Crawler is
		# thirty-seven pixels tall, so a picture that shows nothing there cannot say whether
		# the mark is too small or is not being drawn at all.
		camera.fov = 75.0
		camera.look_at_from_position(
			subject + towards.normalized() * (10.0 if near else 30.0) + Vector3(0.0, 1.7, 0.0),
			subject + Vector3(0.0, 1.0, 0.0),
			Vector3.UP
		)
		return

	if preset == "pair":
		# Close enough that the two kinds fill the frame, because "distinguishable at a
		# glance" is a claim about silhouette and surface that a wide shot cannot settle.
		# Aimed between the nearest Crawler to the nearest Breaker, and the distance is
		# **clamped**: an unclamped "back off until both fit" is how the first attempt
		# rendered two four-pixel figures in the middle of a yard.
		# The **closest** Crawler-and-Breaker pair anywhere on the Map, not the first
		# Breaker's nearest Crawler: the starter Map has several Breaches, so the first
		# Breaker and the first Crawler are routinely forty metres and two holes apart, and
		# a camera at the midpoint of that sees neither of them. Another one a render caught.
		var pair: Array = _closest_pair(sim)
		var crawler: Vector3 = pair[0]
		var breaker: Vector3 = pair[1]
		var between: Vector3 = (crawler + breaker) * 0.5
		var apart: float = crawler.distance_to(breaker)
		var back: float = clampf(apart * 1.1 + 4.5, 6.0, 12.0)
		# Square on to the line between them, so neither hides the other. That put the
		# camera inside a stack of pipe the first time — which is the whole reason `bare`
		# exists, and why this preset is a bare-only diagnostic: judge the *geometry* here
		# and the *grade* on `swarm`, which stands on the clear lane with the yard dressed.
		var across: Vector3 = (breaker - crawler)
		if across.length() < 0.01:
			across = Vector3.RIGHT
		var facing: Vector3 = across.normalized().cross(Vector3.UP)
		camera.fov = 48.0
		camera.look_at_from_position(
			between + facing * back + Vector3(0.0, 1.5, 0.0),
			between + Vector3(0.0, 0.9, 0.0),
			Vector3.UP
		)
		return

	if preset == "triage":
		# **`pair`'s subject at `distance`'s range**, and the question #49 is about: a player
		# holding a lane sees a Crawler and a Breaker side by side at thirty metres and has
		# to know which is which, because the right answer to each is a different one.
		#
		# Neither of the other two presets asks it. `pair` stands six to twelve metres off,
		# which is inside the range where #38 measured the two separating anyway; `distance`
		# frames the swarm's *centre*, so the two kinds are wherever the Wave happened to put
		# them and the Factory is in front of them. Here the camera is square on to the line
		# between the closest pair, at the one distance the ticket names, so what the image
		# answers is the question that was asked.
		var pair: Array = _closest_pair(sim)
		var crawler: Vector3 = pair[0]
		var breaker: Vector3 = pair[1]
		var between: Vector3 = (crawler + breaker) * 0.5
		var across: Vector3 = (breaker - crawler)
		if across.length() < 0.01:
			across = Vector3.RIGHT
		var facing: Vector3 = across.normalized().cross(Vector3.UP)
		# Eye height and the player's own field of view, both of them deliberately: this is
		# the one preset whose whole claim is "what a player sees from where a player stands",
		# so a cinematic focal length would be measuring a lens rather than the game.
		camera.fov = 75.0
		camera.look_at_from_position(
			between + facing * 30.0 + Vector3(0.0, 1.7, 0.0),
			between + Vector3(0.0, 1.0, 0.0),
			Vector3.UP
		)
		return

	if preset == "boss":
		var hulk: Vector3 = _first(sim, Simulation.ENEMY_KIND_SIEGE_HULK)
		var facing: Vector3 = _hulk_facing(sim)
		# Behind it and off to one side, which is where the vent is and where a player who
		# has worked out that the front is the wrong end ends up standing.
		camera.fov = 55.0
		camera.look_at_from_position(
			hulk - facing * 9.0 + facing.cross(Vector3.UP) * 3.5 + Vector3(0.0, 3.2, 0.0),
			hulk + Vector3(0.0, 2.2, 0.0),
			Vector3.UP
		)
		return

	if preset == "distance":
		# **Thirty metres, at eye height, standing on the lane** — which is the view a
		# player holding that lane actually triages from. An earlier version put the camera
		# nine metres up looking down, and that is not a view anybody has: it compresses the
		# Wave into the ground clutter and answers a question nobody asked. Survey View is
		# the overhead one and it has its own preset in `compose_shot.gd`.
		var far: Vector3 = _swarm_centre(sim, Simulation.ENEMY_KIND_CRAWLER)
		var road: Vector3 = (_nest_centre(sim) - far)
		if road.length() < 0.01:
			road = Vector3.BACK
		# Beside the lane by ten metres as well as thirty back, because thirty metres along
		# this lane from where a Wave forms lands *inside the Nest* — the ziggurat is eight
		# metres across and the render came back as a wall of its own paint.
		camera.fov = 62.0
		camera.look_at_from_position(
			far + road.normalized() * 30.0 + road.normalized().cross(Vector3.UP) * 10.0
				+ Vector3(0.0, 1.7, 0.0),
			far + Vector3(0.0, 1.0, 0.0),
			Vector3.UP
		)
		return

	# `swarm`: head height, down the lane, looking back into the Wave as it comes out of its
	# Breach — the view a player holding that lane actually has. On the lane for the reason
	# `pair` is: it is the ground #42's set dressing keeps clear.
	var breach: Vector3 = _breach_centre(sim)
	var lead: Vector3 = _nearest(sim, Simulation.ENEMY_KIND_CRAWLER, breach)
	var lane: Vector3 = (_nest_centre(sim) - breach)
	if lane.length() < 0.01:
		lane = Vector3.BACK
	# Beside the lane rather than in it, by about the width of one, because a Wave marches
	# down a lane in single file and a camera standing on it is a camera standing inside the
	# leading Crawler. Beside it is also where a player holding that lane would be.
	var aside: Vector3 = lane.normalized().cross(Vector3.UP) * 4.0
	camera.fov = 62.0
	camera.look_at_from_position(
		lead + lane.normalized() * 8.0 + aside + Vector3(0.0, 1.7, 0.0),
		lead + Vector3(0.0, 0.9, 0.0),
		Vector3.UP
	)


## The middle of the Nest, in metres. The far end of every lane the set dressing keeps clear,
## and the thing every Wave is walking at.
func _nest_centre(sim: Simulation) -> Vector3:
	var tile: Vector3i = sim.query_nest_tile()
	var footprint: Vector2i = sim.query_nest_footprint()
	var size: float = Fixed.to_float(sim.query_tile_size_metres())
	return Vector3(
		(float(tile.x) + float(footprint.x) * 0.5) * size,
		0.0,
		(float(tile.z) + float(footprint.y) * 0.5) * size
	)


## Where the Breaches are, averaged. The Wave comes out of them, so it is the one anchor that
## is where the Enemies are without being a moving target.
func _breach_centre(sim: Simulation) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for index: int in range(sim.query_breach_count()):
		var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_breach_tile(index))
		total += Vector3(Fixed.to_float(centre.x), 0.0, Fixed.to_float(centre.z))
		count += 1
	if count == 0:
		return Vector3.ZERO
	return total / float(count)


## The Crawler and the Breaker standing closest to one another, as `[crawler, breaker]`.
func _closest_pair(sim: Simulation) -> Array:
	var best: Array = [_breach_centre(sim), _breach_centre(sim)]
	var closest: float = INF
	for left: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(left) != Simulation.ENEMY_KIND_CRAWLER:
			continue
		var crawler_at: FixedVec2 = sim.query_enemy_position_metres(left)
		var crawler: Vector3 = Vector3(
			Fixed.to_float(crawler_at.x), 0.0, Fixed.to_float(crawler_at.z)
		)
		for right: int in range(sim.query_enemy_count()):
			if sim.query_enemy_kind(right) != Simulation.ENEMY_KIND_BREAKER:
				continue
			var breaker_at: FixedVec2 = sim.query_enemy_position_metres(right)
			var breaker: Vector3 = Vector3(
				Fixed.to_float(breaker_at.x), 0.0, Fixed.to_float(breaker_at.z)
			)
			var gap: float = crawler.distance_to(breaker)
			if gap < closest:
				closest = gap
				best = [crawler, breaker]
	return best


## Where the first Enemy of a kind is standing, or the Breaches if there is none.
func _first(sim: Simulation, kind: int) -> Vector3:
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != kind:
			continue
		var at: FixedVec2 = sim.query_enemy_position_metres(index)
		return Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
	return _breach_centre(sim)


func _swarm_centre(sim: Simulation, kind: int) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != kind:
			continue
		var at: FixedVec2 = sim.query_enemy_position_metres(index)
		total += Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
		count += 1
	if count == 0:
		return Vector3.ZERO
	return total / float(count)


func _nearest(sim: Simulation, kind: int, to: Vector3) -> Vector3:
	var best: Vector3 = to
	var closest: float = INF
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != kind:
			continue
		var at: FixedVec2 = sim.query_enemy_position_metres(index)
		var where: Vector3 = Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
		var gap: float = where.distance_to(to)
		if gap < closest:
			closest = gap
			best = where
	return best


func _hulk_facing(sim: Simulation) -> Vector3:
	for index: int in range(sim.query_enemy_count()):
		if sim.query_enemy_kind(index) != Simulation.ENEMY_KIND_SIEGE_HULK:
			continue
		var at: FixedVec2 = sim.query_enemy_position_metres(index)
		var point: FixedVec2 = sim.query_enemy_facing_point_metres(index)
		var gap: Vector3 = Vector3(
			Fixed.to_float(point.x) - Fixed.to_float(at.x),
			0.0,
			Fixed.to_float(point.z) - Fixed.to_float(at.z)
		)
		if gap.length() > 0.001:
			return gap.normalized()
	return Vector3.FORWARD


## Hides the set dressing, which is decoration and carries no collider — so taking it out of
## frame changes nothing about where anything is, only what is in front of it.
func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false


func _hide_the_overlay(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var weapon: WeaponViewmodel = view.weapon_viewmodel()
	if weapon != null:
		weapon.visible = false


func _camera_of(view: WorldView) -> Camera3D:
	for child: Node in view.get_children():
		if child is Camera3D:
			return child
	push_error("the view drew no camera")
	return null
