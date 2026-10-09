## Composes a strip of screenshots **through the swing** of the weapon in the player's
## hands, and writes one PNG per sample.
##
##   SHOT_SCRIPT=tools/visual/compose_swing_shot.gd bash tools/visual/shot.sh out.png fire
##
## Writes `out.png` for the first sample and `out_NN.png` for the rest, NN being the
## number of ticks since the trigger went.
##
## A tool, not part of the game, and the instrument the viewmodel never had. Every other
## claim about the thing in a player's hands is assertable headless — `WeaponAnimator` is
## a `RefCounted` with no nodes and `test_weapon_viewmodel.gd` drives the whole state
## machine — and **none of those assertions can see whether the model is in frame.** The
## Pneumatic Wrench's swing ran in full and off screen for two years behind a green suite,
## and was reported three times. This is what closes that gap: one picture per tick of a
## swing, which is the only form of evidence that a swing is visible.
extends SceneTree

const FRAMES_TO_SETTLE: int = 12

## Which ticks relative to the trigger to photograph; -1 is the frame before it, which is
## the carriage the swing has to be legible against.  The Pneumatic Wrench's `Knife_Attack_1_Anim`
## is 0.53 s, which is 32 ticks, so these walk it end to end.
const SAMPLES: Array = [-1, 4, 8, 12, 16, 20, 24, 28, 31]


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = "shot.png" if arguments.size() < 1 else arguments[0]
	var weapon: String = "" if arguments.size() < 2 or arguments[1] == "fire" else arguments[1]

	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	root.add_child(view)

	# A weapon in hand rather than the Build Gun, which is the default since #42 — stated
	# rather than assumed, because the whole point of the shot is what is in frame.
	if sim.query_player_is_in_build_mode(0):
		sim.step([InputAction.set_build_mode(0, false)])
	if not weapon.is_empty():
		sim.step([InputAction.equip_weapon(0, sim.query_definitions().gear_index(weapon))])
	# Long enough that the draw is over and the carriage has settled, so what the samples
	# below show is the swing and not the end of a draw.
	for tick: int in range(90):
		sim.step([])

	# Settle the *renderer* as well as the Run: the viewmodel's draw begins on the first
	# frame it is synced, so a strip taken straight after construction opens on a draw
	# rather than on the carriage a player is actually standing in.
	for frame: int in range(60):
		await process_frame
		sim.step([])
		view.sync(sim)

	# The trigger goes on the tick before sample 0, so sample -1 is the carriage and
	# every later one is a known number of ticks into the swing. The Simulation stamps
	# the shot with the tick it was *acting* on, which is the one before the step lands.
	var trigger: int = sim.query_tick()
	var swing: int = trigger + 1
	var fired: bool = false
	for sample: int in SAMPLES:
		while sim.query_tick() < swing + sample:
			sim.step([InputAction.fire(0)] if sim.query_tick() == trigger else [])
			fired = fired or sim.query_player_last_shot_tick(0) == trigger
		for frame: int in range(FRAMES_TO_SETTLE):
			await process_frame
			view.sync(sim)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = out_path if sample == SAMPLES[0] else "%s_%02d.%s" % [
			out_path.get_basename(), sample, out_path.get_extension()
		]
		image.save_png(path)
		var role: String = view.weapon_clip_role()
		print("wrote %s — tick %d, %+d from the trigger, role %s, clip %s" % [
			path, sim.query_tick(), sample, role,
			view.weapon_viewmodel().clip_name(role)
		])
	print("the trigger went at tick %d: %s" % [trigger, "yes" if fired else "NO"])
	quit()
