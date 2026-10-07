## Turns a tick's worth of device state into Input Actions. Nothing else.
##
## ADR 0001 makes the Godot layer an input producer and a state reader, and this is the
## input producer. Every single thing a player does with a mouse and four keys leaves here
## as an `InputAction` — there is no second channel, no method on the Simulation it calls,
## and nothing it writes.
##
## It holds no authoritative state. What it does hold is a *device buffer*: mouse travel
## and button presses arrive as engine events at whatever rate the window produces them,
## and a tick needs them gathered up. That is the same category of thing as `TickPump`'s
## leftover frame time — a reading on its way in, not a fact about the world. Everything a
## decision depends on is read back out of the Simulation with a query: which Machine is
## on the Build Gun, which way it is turned, which way the player is facing, where the
## camera is.
##
## The split that makes it testable: `sample_devices` polls the engine and nothing else,
## and `actions_for_tick` is a pure function of a sample and a Simulation. A test builds a
## sample by hand and asserts on the actions, which is the behaviour worth asserting; the
## polling has nothing to assert about headless, where no key is ever down.
class_name PlayerController
extends RefCounted

# Controls. Polled directly rather than through Godot's InputMap, as the layer already
# did before the Build Gun arrived: an InputMap in `project.godot` is the right home for
# these once they are rebindable, and rebinding is a settings-menu ticket. They are
# gathered here so that ticket has one file to change.
const KEY_FORWARD: Key = KEY_W
const KEY_BACK: Key = KEY_S
const KEY_STRAFE_LEFT: Key = KEY_A
const KEY_STRAFE_RIGHT: Key = KEY_D
const KEY_SURVEY: Key = KEY_Q
const KEY_SPRINT: Key = KEY_SHIFT
const KEY_DEMOLISH: Key = KEY_X
const KEY_BELT: Key = KEY_B

## The lever that calls the next Wave early (GLOSSARY.md, DESIGN.md).
##
## A key for now, and a diegetic lever on the Nest when the art pass gets there — DESIGN.md
## is explicit that each diegetic control needs its hero sound, and this one needs the
## klaxon that goes with it. It is an edge rather than a held state because pulling a lever
## is one act; holding it down must not call a Wave a tick.
const KEY_CALL_WAVE: Key = KEY_G

## Handing a Delivery over to the Nest (GLOSSARY.md: progression is physical).
##
## A key now and a diegetic act at the Nest when the art pass gets there, for the reason the
## lever is. An edge rather than a held state: handing goods over is one act, and holding the
## key down must not empty a player's pockets a tick at a time.
const KEY_DELIVER: Key = KEY_F

## Saving and resuming a Run. Gathered here with the rest so the rebinding ticket has
## one file to change, but deliberately **not** read by `sample_devices` and never
## turned into an Input Action — `Main._input` handles them where it handles Escape.
##
## Saving is a window-management concern for the same reason Escape is: it does nothing
## to the Run. It is a pure read of the Simulation, it leaves the hash where it was, and
## a replay has nothing to reproduce.
##
## **Loading is not an Input Action either, and for a stronger reason: it could not be
## one.** An Input Action is an intent `step` applies *to* a Simulation. A load does not
## change a Simulation — it replaces it, and a method on an object cannot swap the object
## out from under its caller. Nor could it replay: a recording is one Simulation evolving
## from a known starting state, and an action that substitutes a different starting state
## mid-script has no meaning there. Resuming a Run is the same category of act as
## constructing one, which ADR 0002 already puts outside `step`. Contrast
## `RELOAD_DEFINITIONS`, which *is* an action: it mutates the Simulation that exists, at
## a known tick, and must be ordered against the other intents of that tick. In co-op
## the distinction is the same one — a load is the session starting again from a state
## everybody adopts, not a tick-level intent the Host broadcasts.
const KEY_SAVE: Key = KEY_F5
const KEY_LOAD: Key = KEY_F9

## How many tiles of Belt one press lays.
##
## Belts have no row in `content/machines.csv` — a Belt is not a Machine, and GLOSSARY.md
## keeps the two apart — so they cannot sit on the Build Gun's Machine list. Until the Belt
## routing UI arrives, and DESIGN.md puts routing in a menu rather than in the world, one
## key lays a fixed run from the aimed tile along the player's facing. Four tiles: long
## enough that a line is a few presses rather than a dozen, short enough to aim.
const BELT_RUN_TILES: int = 4

## Primary places, secondary rotates — the issue's words, and the genre's convention.
const BUTTON_PLACE: MouseButton = MOUSE_BUTTON_LEFT
const BUTTON_ROTATE: MouseButton = MOUSE_BUTTON_RIGHT


## One tick's worth of device readings, gathered from however many engine events and
## frames fell inside it.
##
## A plain bag of values with no behaviour, so a test can build one by hand. Nothing here
## is authoritative: it is all consumed into Input Actions and thrown away.
class DeviceSample extends RefCounted:
	## Throttle in the player's own frame, each in [-1, 1].
	var forward: float = 0.0
	var strafe: float = 0.0
	## Mouse travel in pixels since the last tick, right and down positive.
	var mouse_motion: Vector2 = Vector2.ZERO
	## Whether Survey View is being held down this tick.
	var survey_held: bool = false
	var sprint_held: bool = false
	## Edges, not held states: one click is one Machine, not one a tick.
	var place_clicked: bool = false
	var demolish_clicked: bool = false
	var belt_clicked: bool = false
	var call_wave_clicked: bool = false
	var deliver_clicked: bool = false
	## Signed quarter turns of hologram rotation asked for this tick.
	var rotate_steps: int = 0
	## Signed steps through the Machine list, from the mouse wheel.
	var machine_steps: int = 0


## Device readings gathered since the last tick was produced. Drained by
## `sample_devices`, so a mouse movement is spent exactly once.
var _unsent_mouse_motion: Vector2 = Vector2.ZERO
var _unsent_rotate_steps: int = 0
var _unsent_machine_steps: int = 0
var _place_clicked: bool = false
var _demolish_clicked: bool = false
var _belt_clicked: bool = false
var _call_wave_clicked: bool = false
var _deliver_clicked: bool = false


# ── Gathering device events ───────────────────────────────────────────────────
# Called from `Main._input`, because mouse travel and key presses arrive as events
# between frames and a tick has to add up whatever fell inside it.

func note_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_unsent_mouse_motion += (event as InputEventMouseMotion).relative
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			return
		match button.button_index:
			BUTTON_PLACE:
				_place_clicked = true
			BUTTON_ROTATE:
				_unsent_rotate_steps += 1
			MOUSE_BUTTON_WHEEL_UP:
				_unsent_machine_steps += 1
			MOUSE_BUTTON_WHEEL_DOWN:
				_unsent_machine_steps -= 1
		return

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo:
			if key.keycode == KEY_DEMOLISH:
				_demolish_clicked = true
			elif key.keycode == KEY_BELT:
				_belt_clicked = true
			elif key.keycode == KEY_CALL_WAVE:
				_call_wave_clicked = true
			elif key.keycode == KEY_DELIVER:
				_deliver_clicked = true


## Reads the devices for one tick and drains the buffer, so nothing is spent twice.
##
## The one function here that touches the engine. Everything below it is arithmetic over
## what this returns, which is why the arithmetic is the part with tests.
func sample_devices() -> DeviceSample:
	var sample: DeviceSample = DeviceSample.new()

	if Input.is_key_pressed(KEY_FORWARD):
		sample.forward += 1.0
	if Input.is_key_pressed(KEY_BACK):
		sample.forward -= 1.0
	if Input.is_key_pressed(KEY_STRAFE_RIGHT):
		sample.strafe += 1.0
	if Input.is_key_pressed(KEY_STRAFE_LEFT):
		sample.strafe -= 1.0
	sample.survey_held = Input.is_key_pressed(KEY_SURVEY)
	sample.sprint_held = Input.is_key_pressed(KEY_SPRINT)

	sample.mouse_motion = _unsent_mouse_motion
	sample.rotate_steps = _unsent_rotate_steps
	sample.machine_steps = _unsent_machine_steps
	sample.place_clicked = _place_clicked
	sample.demolish_clicked = _demolish_clicked
	sample.belt_clicked = _belt_clicked
	sample.call_wave_clicked = _call_wave_clicked
	sample.deliver_clicked = _deliver_clicked

	_unsent_mouse_motion = Vector2.ZERO
	_unsent_rotate_steps = 0
	_unsent_machine_steps = 0
	_place_clicked = false
	_demolish_clicked = false
	_belt_clicked = false
	_call_wave_clicked = false
	_deliver_clicked = false

	return sample


# ── Turning a sample into intents ─────────────────────────────────────────────

## The Input Actions one tick of device readings amounts to, in the order they are meant
## to apply in.
##
## Looking comes first, so a build later in the same tick is aimed with the turn the
## player just made. Choosing and rotating come before building, so a player who scrolls
## and clicks in one tick places what they scrolled to. Walking and Survey View come last
## because nothing else depends on them.
##
## Every decision in here is read out of `sim` rather than remembered: what is on the
## Build Gun, which way it is turned, where the camera is pointing. That is what makes
## this a translator rather than a second copy of the game state.
func actions_for_tick(sim: Simulation, player_id: int, sample: DeviceSample) -> Array:
	var actions: Array = []

	if sample.mouse_motion != Vector2.ZERO:
		actions.append(
			InputAction.look(
				player_id,
				InputQuantiser.pixels_to_fixed(sample.mouse_motion.x),
				InputQuantiser.pixels_to_fixed(sample.mouse_motion.y)
			)
		)

	if sample.machine_steps != 0:
		var chosen: int = _stepped_machine(sim, player_id, sample.machine_steps)
		if chosen != -1:
			actions.append(InputAction.select_machine(player_id, chosen))

	if sample.rotate_steps != 0:
		actions.append(InputAction.rotate_build(player_id, sample.rotate_steps))

	if sample.place_clicked:
		# The rotation the player will be holding once this tick's rotate has applied,
		# so rotating and placing in the same tick places the Machine they can see.
		var rotation: int = WorldGrid.wrap_rotation(
			sim.query_player_build_rotation(player_id) + sample.rotate_steps
		)
		actions.append(
			InputAction.build_machine(
				player_id,
				sim.query_player_selected_machine_index(player_id),
				BuildGun.aimed_tile(sim, player_id),
				rotation
			)
		)

	if sample.belt_clicked:
		var entry: Vector3i = BuildGun.aimed_tile(sim, player_id)
		# The direction comes from the yaw the *Simulation* is holding, rounded to the
		# nearest of the grid's four, so there is no second opinion about which way the
		# player is looking.
		var step: Vector3i = WorldGrid.direction_step(
			WorldGrid.direction_from_turns(sim.query_player_yaw_turns(player_id))
		)
		actions.append(
			InputAction.build_belt(player_id, entry, entry + step * (BELT_RUN_TILES - 1))
		)

	if sample.demolish_clicked:
		actions.append(InputAction.demolish(player_id, BuildGun.aimed_tile(sim, player_id)))

	# Sent whatever the Simulation would make of it, exactly as a misaimed build intent is.
	# Whether the lever moves is the Simulation's decision and not this layer's; the HUD
	# reads `query_call_wave_early_refusal` so a player knows before they press it.
	if sample.call_wave_clicked:
		actions.append(InputAction.call_wave_early(player_id))

	# Sent whatever the Simulation would make of it, for the reason the lever is. Standing
	# close enough, holding anything the Nest wants, and the Depth the open tier is gated at
	# are all the Simulation's decisions; the HUD reads `query_delivery_refusal` so a player
	# knows which of them is in the way before they press it.
	if sample.deliver_clicked:
		actions.append(InputAction.deliver_to_nest(player_id))

	if sample.forward != 0.0 or sample.strafe != 0.0:
		actions.append(
			InputAction.move(
				player_id,
				InputQuantiser.throttle_to_fixed(sample.forward),
				InputQuantiser.throttle_to_fixed(sample.strafe)
			)
		)

	# Sent every tick rather than on the edges, because the Simulation counts ticks of
	# transition and "still held" is the thing it needs to know.
	actions.append(InputAction.survey_view(player_id, sample.survey_held))
	actions.append(InputAction.sprint(player_id, sample.sprint_held))

	return actions


## The Machine `steps` along from the one on the Build Gun, wrapping at both ends, or -1
## when the definitions carry no Machines to step through.
func _stepped_machine(sim: Simulation, player_id: int, steps: int) -> int:
	var count: int = sim.query_definitions().machine_count()
	if count == 0:
		return -1
	var current: int = sim.query_player_selected_machine_index(player_id)
	if current == -1:
		current = 0
	return posmod(current + steps, count)
