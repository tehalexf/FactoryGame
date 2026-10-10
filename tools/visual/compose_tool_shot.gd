## Composes a shot of **what is in the player's hands**, through the player's own camera.
##
##   SHOT_SCRIPT=tools/visual/compose_tool_shot.gd bash tools/visual/shot.sh out.png tool
##   SHOT_SCRIPT=tools/visual/compose_tool_shot.gd bash tools/visual/shot.sh out.png draw
##   SHOT_SCRIPT=tools/visual/compose_tool_shot.gd bash tools/visual/shot.sh out.png compare
##
## A tool, not part of the game, and #64's instrument. `compose_swing_shot.gd` is its
## sibling and exists for the same reason — every other claim about the thing in a player's
## hands is assertable headless and **none of those assertions can see whether the model is
## in frame** — but it photographs a *swing*, which is a weapon's question. This one
## photographs a **silhouette at rest**, which is the Build Gun's: the whole of what a
## holster buys is that a player who pressed `B` can see that they pressed it.
##
## Three presets, and the third one may not be committed:
##
##   tool      the Build Gun at rest, which is what a player looks at while building
##   draw      one frame per sample through the `Draw` take, so the swing-up is visible
##   compare   the Build Gun and every weapon frame in turn, one PNG each
##
## **`compare` is the one that answers the acceptance criterion and the one that cannot
## be published.** "Distinguishable from every weapon frame at a glance" is a claim about
## a set, so it has to be judged as a set — and with the purchased packs linked, the
## weapon panels are renders of the RgsDev arms and are as non-redistributable as the FBX
## they came from. `compose_swing_shot.gd` carries the same rule and
## `compose_death_shot.gd`'s `plain` preset is the other half of it. So `compare` is for
## looking at locally; `tool` and `draw` are the committable pair, because the Build Gun is
## this project's own work.
##
## `bare` hides the yard, for the reason every other composer carries it: the props are
## purchased too.
extends SceneTree

## Long enough for the Run's opening draw and the swap to be over, so what is photographed
## is the carriage a player actually stands in rather than the end of an animation.
##
## **Ticks and frames are stepped together rather than one after the other**, which is the
## one thing this file had to learn the hard way: a swap is the renderer's, timed off the
## clip lengths of the model on screen, so a hundred ticks with no `sync` between them
## advance the Run and not the holster. The first `compare` strip came out labelled
## `bolt_rifle` with the Build Gun still in frame for exactly that reason.
const TICKS_TO_SETTLE: int = 90
const FRAMES_TO_SETTLE: int = 12

## Which ticks of the `Draw` take to photograph. `build_gun_recipe.TAKE_SECONDS` is 0.22,
## which is about 13 ticks, and `player.holster_seconds` caps each half of a swap well
## under that — so these walk the whole gesture and then some, and the last sample is the
## tool at rest, which is what the movement has to be legible against.
const DRAW_SAMPLES: Array = [0, 1, 2, 3, 5, 7, 10, 20]

## Whether the yard is hidden. Held rather than threaded through five signatures, which is
## the one thing this file does differently from `compose_death_shot.gd` and only because
## it photographs in three shapes rather than one.
var _bare: bool = false


func _initialize() -> void:
	var given: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if given.size() < 1 else given[0]
	# `shot.sh` passes everything past the output path as one argument, so the extra words
	# arrive glued together: `shot.sh out.png "compare bare"`. Split rather than add a third
	# parameter to a script six composers already share — `compose_building_shot.gd`'s note.
	var arguments: PackedStringArray = PackedStringArray()
	for word: String in " ".join(given.slice(1)).split(" ", false):
		arguments.append(word)
	var preset: String = "tool" if arguments.size() < 1 else arguments[0]
	var bare: bool = arguments.has("bare")

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	_bare = bare
	# A Run opens with the weapon out (#42), so the Build Gun has to be *asked for* — and
	# that keypress is the whole subject here, so it is stated rather than assumed.
	sim.step([InputAction.set_build_mode(0, true)])
	await _settle(sim, view)

	match preset:
		"draw":
			await _strip_through_a_draw(sim, view, out_path)
		"compare":
			await _one_panel_per_held_object(sim, view, out_path)
		_:
			await _one_shot(sim, view, out_path, "the Build Gun at rest")
	quit()


## One frame per sample through a fresh `Draw`, which is what a `B` looks like.
func _strip_through_a_draw(sim: Simulation, view: WorldView, out_path: String) -> void:
	# Holster and settle, so the draw being photographed starts from stowed rather than
	# from wherever the opening gesture happened to leave the model.
	sim.step([InputAction.set_build_mode(0, false)])
	await _settle(sim, view)

	var pressed: int = sim.query_tick()
	sim.step([InputAction.set_build_mode(0, true)])
	for sample: int in DRAW_SAMPLES:
		while sim.query_tick() < pressed + 1 + sample:
			sim.step([])
		# Frames without ticks: the sample *is* a tick count from the keypress, so letting
		# `_settle` step the Run would photograph a different moment from the one labelled.
		for frame: int in range(FRAMES_TO_SETTLE):
			await process_frame
			view.sync(sim)
			if _bare:
				_hide_the_yard(view)
		await _write(view, out_path if sample == DRAW_SAMPLES[0] else "%s_%02d.%s" % [
			out_path.get_basename(), sample, out_path.get_extension()
		], "%+d ticks from the B" % sample)


## One PNG per held object: the tool, then every weapon frame in the shipped table.
##
## The set is read off `Definitions` rather than written here, so a fourth weapon joins the
## comparison without this file changing — the rule `KEY_1`-`KEY_3` already obeys.
func _one_panel_per_held_object(sim: Simulation, view: WorldView, out_path: String) -> void:
	await _one_shot(sim, view, out_path, "build_gun")

	sim.step([InputAction.set_build_mode(0, false)])
	var definitions: Definitions = sim.query_definitions()
	for nth: int in range(definitions.weapon_count()):
		var gear_index: int = definitions.weapon_gear_index(nth)
		sim.step([InputAction.equip_weapon(0, gear_index)])
		await _settle(sim, view)
		await _write(view, "%s_%02d.%s" % [
			out_path.get_basename(), nth + 1, out_path.get_extension()
		], definitions.gear_ids()[gear_index])


func _one_shot(sim: Simulation, view: WorldView, out_path: String, note: String) -> void:
	await _settle(sim, view)
	await _write(view, out_path, note)


## `compose_death_shot.gd`'s, and the same reason: the yard is drawn out of the purchased
## packs when they are linked, so a shot bound for a public repository has to leave it out.
func _hide_the_yard(view: WorldView) -> void:
	for child: Node in view.get_children():
		if child is SetDressing:
			(child as SetDressing).visible = false


## Let the renderer catch up, hiding the yard as it goes rather than once at the end: a
## single hide followed by one frame photographs the frame *before* it took effect, which
## is how the first render of this came out with a purchased yard in it.
func _settle(sim: Simulation, view: WorldView) -> void:
	for frame: int in range(FRAMES_TO_SETTLE):
		await process_frame
		for tick: int in range(TICKS_TO_SETTLE / FRAMES_TO_SETTLE):
			sim.step([])
		view.sync(sim)
		if _bare:
			_hide_the_yard(view)


func _write(view: WorldView, path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	var role: String = view.weapon_clip_role()
	print("wrote %s — %s: model %s, has_model %s, role %s, clip %s" % [
		path, note, view.weapon_model_id(), view.weapon_has_model(), role,
		view.weapon_viewmodel().clip_name(role)
	])
