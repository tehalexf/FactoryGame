## Composes a screenshot of a round actually being fired, and writes it to a PNG.
##
##   SHOT_SCRIPT=tools/visual/compose_gunfire_shot.gd bash tools/visual/shot.sh out.png [preset]
##
## A tool, not part of the game, and it exists because #69's acceptance criterion is written as
## a picture: *a player can see their own shot connect, and can see a Turret firing from thirty
## metres, judged by rendered shots through the player's own camera.* No count can settle that
## and no test can either — a mark can be drawn, be the right colour, be in the right place
## horizontally and still be invisible, which is exactly what #50 found out about a starved
## Miner's tag by looking at one of these.
##
## **Every other composer in this directory frames a Factory that is standing still.** None of
## them can take this picture, and the reason is not the vantage: a Turret only fires while it
## is holding a round *and* has something in reach, so a shot is a two-tick window in a Run
## that has to have built a whole production chain first. `compose_wave_shot.gd` builds a
## Turret and never feeds it, so its Turret has never fired in any image this project has
## committed.
##
## Presets:
##
## * `turret` — the documented `competent` Factory, fed, with a Wave on its lane, framed at the
##   **thirty metres** the ticket names. The default.
## * `hit` — the player's own round reaching a Breaker, through the **player's own camera**,
##   because that is the only form of evidence that a thing in a first-person frame is visible
##   at all. `compose_swing_shot.gd`'s lesson: a state machine with no nodes proves the role
##   and only a render proves the frame.
##
## Three extra words: `hud` keeps the overlay, `bare` hides the set dressing, and `plain` hides
## the first-person arms. `bare` is what the committed images use, because the yard is drawn out of
## the **purchased** packs and a render of those may not be published.
extends SceneTree

const FRAMES_TO_SETTLE: int = 40

## Where the Turret stands in the documented Factory, and the last tile of the Belt that feeds
## it. `tests/cases/test_turrets.gd` is the authority on both and on the four Machines between:
## this is that Factory, because the claim being photographed is about the Factory the balance
## table measures rather than about an arrangement invented for a photograph.
const TURRET_TILE: Vector3i = Vector3i(2, 0, -7)
const LAST_BELT_TILE: Vector3i = Vector3i(1, 0, -6)

## How far the camera stands off its subject for the `turret` preset. The distance #38 and #49
## both found is the one that matters: close enough to make out a Machine, far enough that
## anything relying on detail has already lost.
const THIRTY_METRES: float = 30.0

## Crawlers and Breakers at Heat 0, so the lane has something on it within a few seconds. No
## Siege Hulk: it outranges every Turret by content rule, so it would stand off and shell
## rather than give the gun anything to shoot at.
const EARLY_TIERS: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,0,6
shock_breakers,breaker,0,2,0,2
"""

## How long to wait for a production chain to put a round in a Turret. The documented Factory
## takes thousands of ticks to smelt its first plate and press it into ammunition; this is a
## bound so a broken Factory ends the render rather than hanging it.
const TICKS_TO_WAIT: int = 12000

## Pixels of mouse travel per turn of yaw, at the shipped
## `player.look_sensitivity_turns_per_1000_pixels` of 0.2. Aiming is done the way a player aims
## — by sending `LOOK` and letting the Simulation hold the angle — rather than by writing a
## yaw into the Simulation, which nothing outside it is allowed to do.
const PIXELS_PER_TURN: float = 5000.0


func _initialize() -> void:
	var given: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if given.size() < 1 else given[0]
	var arguments: PackedStringArray = PackedStringArray()
	for word: String in " ".join(given.slice(1)).split(" ", false):
		arguments.append(word)
	var preset: String = "turret" if arguments.size() < 1 else arguments[0]

	var sim: Simulation = Simulation.new(7, 1, _content(), MapLayout.starter())
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_build_the_documented_factory(sim)

	var report: String = ""
	if preset == "hit":
		report = _take_the_shot(sim, view)
	else:
		report = _wait_for_the_turret_to_fire(sim, view)

	var camera: Camera3D = _camera_of(view)
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		# The Simulation is **not** stepped through the settle, because the subject is one
		# two-tick window held still. Every mark a shot leaves is a function of `query_tick`
		# minus the tick the shot was stamped on, so a frame that steps nothing draws it at
		# exactly the same age — which is what makes a still of a transient possible at all.
		view.sync(sim)
		if preset != "hit":
			_frame_the_turret(camera, sim)
		if not arguments.has("hud"):
			_hide_the_overlay(view, preset, arguments.has("plain"))
		if arguments.has("bare"):
			_hide_the_yard(view)

	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out_path)
	# What was actually drawn, counted rather than squinted at. Guarded, because the `before`
	# half of a before-and-after pair runs this same composer against a `WorldView` that has
	# none of these — and the guard is itself the statement of what was missing.
	var marks: String = "no shot marks: this build does not draw one"
	if view.has_method("muzzle_flash_count"):
		marks = "%d flashes, %d tracers, %d impacts" % [
			view.call("muzzle_flash_count"),
			view.call("tracer_count"),
			view.call("impact_count"),
		]
	print("wrote %s (%dx%d): %s; %s" % [
		out_path, image.get_width(), image.get_height(), report, marks
	])
	quit()


## The shipped content, with the Wave table replaced and the Telegraph shortened so one pull of
## the lever puts Crawlers on the lane in half a second. The opening stock is raised because
## this Factory is six Machines and six Belts and a Run does not open able to afford it — the
## same substitution `compose_wave_shot.gd` makes, for the same reason.
func _content() -> Definitions:
	return Definitions.parse(
		_read("res://content/machines.csv"),
		_read("res://content/recipes.csv"),
		_read("res://content/tuning.toml")
			.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
			# The first Wave held well out of the way, because the Factory needs thousands of
			# ticks to smelt its first plate and press it into a round — and a Wave that
			# arrived first ate the Turret before it had anything to fire. The Wave is then
			# brought on with the lever, which is the same code path a player uses.
			.replace(
				"first_wave_interval_seconds = 90", "first_wave_interval_seconds = 900"
			)
			.replace('starting_stock = "iron_plate:110"', 'starting_stock = "iron_plate:400;ammunition:200"'),
		EARLY_TIERS,
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


## The `competent` Factory of the balance table: an iron line into an Ammo Press, the Power
## that pays for it, and an MG Turret on the Nest's lane fed by a Belt all the way round.
##
## The Belts land a tick after the Machines, because a Belt is refused on a tile a Machine
## already stands on and the two arriving in one tick would depend on the order within it.
func _build_the_documented_factory(sim: Simulation) -> void:
	var definitions: Definitions = sim.query_definitions()
	var ground: int = WorldGrid.GROUND_LAYER
	sim.step([
		InputAction.build_machine(0, definitions.machine_index("miner_mk1"), Vector3i(4, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("smelter_mk1"), Vector3i(8, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("ammo_press_mk1"), Vector3i(8, ground, 9)),
		InputAction.build_machine(0, definitions.machine_index("coal_miner_mk1"), Vector3i(12, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("steam_boiler_mk1"), Vector3i(16, ground, 4)),
		InputAction.build_machine(0, definitions.machine_index("mg_turret_mk1"), TURRET_TILE),
	])
	sim.step([
		InputAction.build_belt(0, Vector3i(6, ground, 4), Vector3i(7, ground, 4)),
		InputAction.build_belt(0, Vector3i(8, ground, 7), Vector3i(8, ground, 8)),
		InputAction.build_belt(0, Vector3i(14, ground, 4), Vector3i(15, ground, 4)),
		InputAction.build_belt(0, Vector3i(7, ground, 9), Vector3i(1, ground, 9)),
		InputAction.build_belt(0, Vector3i(0, ground, 9), Vector3i(0, ground, -5)),
		InputAction.build_belt(0, Vector3i(0, ground, -6), LAST_BELT_TILE),
	])


## Steps the Run until the Turret has fired on the tick just gone, so every mark the shot
## leaves is one tick old when the picture is taken.
##
## **Driven off the Simulation's own queries and not off the view**, which matters more than it
## looks: the `before` half of a before-and-after pair is rendered with this same composer
## against a `WorldView` that has none of #69's accessors, so a loop that watched the drawing
## could not take the picture that proves the drawing was missing.
func _wait_for_the_turret_to_fire(sim: Simulation, view: WorldView) -> String:
	var turret: int = _turret_index(sim)
	# **Fed before hunted, and that order is a finding rather than a convenience.** Called
	# first, the Wave arrived while the chain was still smelting its first plate and ate the
	# Turret: "the Turret was destroyed before it fired" is what the composer reported, which
	# is also a fair statement of what a player who builds a gun before a feed gets.
	for tick: int in range(TICKS_TO_WAIT):
		if sim.query_turret_ammunition(turret) > 0:
			break
		sim.step([])
		turret = _turret_index(sim)
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(TICKS_TO_WAIT):
		if sim.query_turret_target_serial(turret) != -1:
			break
		sim.step([])
		turret = _turret_index(sim)
		if turret == -1:
			return "the Turret was destroyed before it acquired anything"
	# From here the view is synced every tick, because the marks are derived from a diff of
	# consecutive observations and one that straddled the shot would miss it.
	view.sync(sim)
	for tick: int in range(TICKS_TO_WAIT):
		sim.step([])
		view.sync(sim)
		turret = _turret_index(sim)
		if turret == -1:
			return "the Turret was destroyed before it fired"
		if sim.query_turret_last_shot_tick(turret) == sim.query_tick() - 1:
			return "%d enemies, the Turret fired on tick %d" % [
				sim.query_enemy_count(), sim.query_turret_last_shot_tick(turret)
			]
	return "the Turret never fired"


## Arms the player, walks them onto the lane, aims at the nearest Enemy and pulls the trigger —
## the way a player does, through Input Actions, with the Simulation holding the angle.
func _take_the_shot(sim: Simulation, view: WorldView) -> String:
	sim.step([
		InputAction.set_build_mode(0, false),
		InputAction.equip_weapon(0, sim.query_definitions().gear_index("bolt_rifle")),
	])
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(TICKS_TO_WAIT):
		if sim.query_enemy_count() > 0:
			break
		sim.step([])
	if sim.query_enemy_count() == 0:
		return "no Enemy ever arrived"

	# Walk towards whatever came out, so the shot is taken at a distance a player would take
	# one at rather than from across the Map.
	for tick: int in range(8 * Simulation.TICKS_PER_SECOND):
		var target: int = _nearest_enemy(sim)
		if target == -1 or _gap_metres(sim, target) < 14.0:
			break
		_aim_at(sim, target)
		sim.step([InputAction.move(0, Fixed.ONE, 0), InputAction.sprint(0, true)])

	var enemy: int = _nearest_enemy(sim)
	if enemy == -1:
		return "nothing left to shoot at"
	_aim_at(sim, enemy)
	var whole: int = sim.query_enemy_health(enemy)
	var at: FixedVec2 = sim.query_enemy_position_metres(enemy)
	# Observed once before the trigger, because the first observation of a Run establishes the
	# snapshot and reports nothing — a round fired on the very first synced tick would leave
	# a flash and no tracer.
	view.sync(sim)
	sim.step([InputAction.fire(0)])
	view.sync(sim)
	var left: int = sim.query_enemy_health(enemy) if enemy < sim.query_enemy_count() else 0
	return "fired at %.1f m, %d hit points of %d left" % [
		_gap_metres_to(sim, at), left, whole
	]


## Turns the view onto an Enemy, in yaw and in pitch, by sending the mouse travel that gets
## there. `query_player_facing` is the convention and `query_player_camera_pitch_turns` the
## current pitch, so nothing here owns a second copy of either.
func _aim_at(sim: Simulation, enemy: int) -> void:
	var at: FixedVec2 = sim.query_player_position(0)
	var to: FixedVec2 = sim.query_enemy_position_metres(enemy)
	var along: Vector2 = Vector2(
		Fixed.to_float(to.x) - Fixed.to_float(at.x), Fixed.to_float(to.z) - Fixed.to_float(at.z)
	)
	if along.length() < 0.01:
		return
	# `_facing` is (-sin yaw, -cos yaw), so the yaw that points along a direction is the
	# arc-tangent of its negation. A float, which is fine: what crosses into the Simulation is
	# a whole number of pixels, which is the one crossing `InputQuantiser` sanctions.
	var wanted: float = atan2(-along.x, -along.y) / TAU
	var turn: float = wrapf(wanted - Fixed.to_float(sim.query_player_yaw_turns(0)), -0.5, 0.5)

	var rise: float = (
		Fixed.to_float(sim.query_enemy_hit_height_metres(enemy)) * 0.5
		# The camera height rather than `query_player_eye_height_metres`, which is the same
		# number while nobody is surveying and is a query the pre-#69 build does not have —
		# and this composer has to run against that build to take the `before` half of the
		# pair.
		- Fixed.to_float(sim.query_player_camera_height_metres(0))
	)
	var wanted_pitch: float = atan2(rise, along.length()) / TAU
	var lift: float = wanted_pitch - Fixed.to_float(sim.query_player_camera_pitch_turns(0))

	# **Right is a decrease in yaw** — `_apply_look` subtracts the travel, so a positive
	# number of pixels to the right turns the view left. Getting that backwards is what the
	# first `hit` render reported as "30 hit points of 30 left": the shot was taken, the round
	# left the barrel, and it went the other way.
	sim.step([
		InputAction.look(
			0,
			Fixed.from_decimal_string("%.4f" % (-turn * PIXELS_PER_TURN)),
			Fixed.from_decimal_string("%.4f" % (-lift * PIXELS_PER_TURN))
		)
	])


func _nearest_enemy(sim: Simulation) -> int:
	var best: int = -1
	var nearest: float = 1e9
	for index: int in range(sim.query_enemy_count()):
		var gap: float = _gap_metres(sim, index)
		if gap < nearest:
			nearest = gap
			best = index
	return best


func _gap_metres(sim: Simulation, enemy: int) -> float:
	return _gap_metres_to(sim, sim.query_enemy_position_metres(enemy))


func _gap_metres_to(sim: Simulation, to: FixedVec2) -> float:
	var at: FixedVec2 = sim.query_player_position(0)
	return Vector2(
		Fixed.to_float(to.x) - Fixed.to_float(at.x), Fixed.to_float(to.z) - Fixed.to_float(at.z)
	).length()


func _turret_index(sim: Simulation) -> int:
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_turret(index) and not sim.query_machine_is_repair_pylon(index):
			return index
	return -1


## Stands thirty metres off, square to the line of fire, looking at the middle of it — so the
## gun is at one edge of frame and what it is shooting at is at the other.
##
## **Square to the line rather than down it, and that is a finding.** A tracer seen exactly end
## on is a tracer seen as a dot, and the question this picture has to answer is whether a round
## is visible crossing the gap.
##
## **And on the side away from the Nest**, which is the second thing the first render caught: a
## camera placed by arithmetic without that clause stood behind the Nest's four-by-four
## ziggurat, which filled half the frame and left the Turret a hundred pixels wide on the far
## edge. #56's lesson about a composer, met again — a vantage derived from the Simulation's own
## answers still has to be derived from the right ones.
func _frame_the_turret(camera: Camera3D, sim: Simulation) -> void:
	var turret: int = _turret_index(sim)
	if camera == null or turret == -1:
		return
	var gun: Vector3 = _machine_centre(sim, turret)
	var mark: Vector3 = _what_it_is_shooting_at(sim, turret)
	var along: Vector3 = mark - gun
	along.y = 0.0
	if along.length() < 0.5:
		along = Vector3.FORWARD
	along = along.normalized()

	var aside: Vector3 = Vector3(-along.z, 0.0, along.x)
	if aside.dot(gun - _nest_centre(sim)) < 0.0:
		aside = -aside
	# Thirty metres **from the gun**, which is the distance the ticket names, and about forty
	# degrees off its line of fire — far enough round that the round crossing the gap is not
	# seen end on, near enough along it that what is being shot at is in the same frame.
	var stand: Vector3 = (aside * 0.8 - along * 0.6).normalized()
	camera.position = gun + stand * THIRTY_METRES + Vector3.UP * 1.7
	# Aimed at the gun rather than at the middle of the shot, which was tried and is worse:
	# turning onto the midpoint swings the Turret towards the edge and takes the whole Factory
	# with it, so the subject ends up smaller in a frame that is already mostly ground.
	camera.look_at(gun + Vector3.UP * 1.2, Vector3.UP)


## Where the Turret's own target is standing, or the middle of the swarm when its target died
## with the shot that is being photographed.
func _what_it_is_shooting_at(sim: Simulation, turret: int) -> Vector3:
	var enemy: int = sim.query_enemy_index_of_serial(sim.query_turret_target_serial(turret))
	if enemy == -1:
		return _swarm_centre(sim)
	var at: FixedVec2 = sim.query_enemy_position_metres(enemy)
	return Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))


func _nest_centre(sim: Simulation) -> Vector3:
	var tile: Vector3i = sim.query_nest_tile()
	var size: float = float(WorldGrid.TILE_SIZE_METRES)
	var span: Vector2i = sim.query_nest_footprint()
	return Vector3(
		(float(tile.x) + float(span.x) * 0.5) * size,
		0.0,
		(float(tile.z) + float(span.y) * 0.5) * size
	)


func _machine_centre(sim: Simulation, index: int) -> Vector3:
	var tile: Vector3i = sim.query_machine_tile(index)
	var footprint: Vector2i = sim.query_machine_footprint(index)
	var size: float = float(WorldGrid.TILE_SIZE_METRES)
	return Vector3(
		(float(tile.x) + float(footprint.x) * 0.5) * size,
		0.0,
		(float(tile.z) + float(footprint.y) * 0.5) * size
	)


func _swarm_centre(sim: Simulation) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var counted: int = 0
	for index: int in range(sim.query_enemy_count()):
		var at: FixedVec2 = sim.query_enemy_position_metres(index)
		total += Vector3(Fixed.to_float(at.x), 0.0, Fixed.to_float(at.z))
		counted += 1
	if counted == 0:
		return Vector3.ZERO
	return total / float(counted)


## Hides the set dressing, which is decoration and carries no collider — so taking it out of
## frame changes nothing about where anything is, only what is in front of it. It is also a
## licensing requirement for anything bound for `docs/images/`: the yard is drawn out of the
## purchased packs.
func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false


## Hides the HUD, and the first-person arms with it for every preset but `hit`, where what is
## in the player's hands is half the subject.
##
## **`plain` hides them even there, and that is a licensing requirement rather than a
## composition choice** — `compose_death_shot.gd`'s own word, for its own reason: a render of
## the purchased RgsDev viewmodels is as non-redistributable as the FBX they came from, so
## anything bound for `docs/images/` in a public repository has to be able to leave them out.
func _hide_the_overlay(view: WorldView, preset: String, plain: bool) -> void:
	for child: Node in view.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	if preset == "hit" and not plain:
		return
	var weapon: WeaponViewmodel = view.weapon_viewmodel()
	if weapon != null:
		weapon.visible = false


func _camera_of(view: WorldView) -> Camera3D:
	for child: Node in view.get_children():
		if child is Camera3D:
			return child
	push_error("the view drew no camera")
	return null
