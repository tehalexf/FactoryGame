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

## One tile of Wall on the aimed tile. An edge, like the Belt key: one press is one Wall.
##
## A key rather than a slot on the Build Gun's Machine list, for the reason the Belt key is
## one: a Wall has no row in `content/machines.csv` and is not a Machine (DESIGN.md lists it
## alongside the Nest and the Belt), so it cannot sit in a list of Machine definition indices.
const KEY_WALL: Key = KEY_V

## The Pneumatic Wrench, held on whatever the Build Gun is aimed at.
##
## **Held rather than an edge**, unlike every other key here: a repair is restoration over
## time, and the Simulation wants to know "still on it" each tick. Letting go is itself the
## act of stopping, which is why the intent is only sent while the key is down — the
## Simulation clears it every tick and a player who walks away stops mending.
const KEY_REPAIR: Key = KEY_R

## Placing a Machine. **Moved off the left mouse button**, which became the trigger when
## there was something to pull it with.
##
## Not a happy binding and not a permanent one. The real answer is a hand — a holster that
## puts either the Build Gun or a weapon in front of the player — and DESIGN.md already
## says where the Gear and Recipe interfaces go: a menu. Until that ticket, a key, because
## the alternative was making the two acts fight over one button and the first thing a
## player would discover is that shooting builds a Smelter.
##
## It is deliberately *not* a mode: nothing in the Simulation asks whether building is
## allowed, and the Build Gun still works mid-Wave, mid-burst and in Survey View
## (GLOSSARY.md, DESIGN.md).
const KEY_PLACE: Key = KEY_E

## Picking a Downed teammate up. **Held**, like the wrench, and for the same reason: a
## revive is restoration over time and what it costs the rescuer is standing still in the
## open. Does nothing on a solo Run — solo play has no Downed state (GLOSSARY.md).
const KEY_REVIVE: Key = KEY_T

## The weapon keys. One per weapon frame `content/gear.csv` declares, in the sorted order
## the table interns them in, so a fourth weapon becomes the fourth key without this file
## changing.
const KEY_WEAPON_FIRST: Key = KEY_1

## How many weapon keys there are. Three because `KEY_1` to `KEY_3` is what a hand reaches
## without looking; a fifth weapon would want the Gear menu rather than `KEY_5`.
const WEAPON_KEY_COUNT: int = 3

## The slot keys. One per interned Gear slot, in the sorted order the table interns them
## in, each cycling through the components that fit it — so `KEY_4` is the first slot,
## `KEY_5` the second, and a fourth slot added as a row gets `KEY_7` for free.
##
## A key that cycles rather than a key per component, because Gear assembly is a *menu*
## (DESIGN.md puts routine high-frequency choices in menus and keeps diegetic controls for
## weighty infrequent ones), and the menu is a later ticket. Cycling holds no state here:
## what comes next is a function of what the Simulation says is fitted and what the
## definition set says exists.
const KEY_SLOT_FIRST: Key = KEY_4

## How many slot keys there are. Four, which is one more than the three slots
## `content/gear.csv` ships, so adding a slot does not immediately need this file.
const SLOT_KEY_COUNT: int = 4

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

## Taking materials back out of the Nest's store (issue #27).
##
## An edge rather than a held state, for the reason handing a Delivery over is one. What it
## asks for is **the shortfall on the Build Gun's current Machine**: stand at the Nest
## holding the thing you want to build and press this until the hologram stops complaining.
##
## That choice is *presentation* and lives here rather than in the Simulation, which is the
## same split `BuildGun.refusal_text` makes. `WITHDRAW_FROM_NEST` names an Item and a count
## because the store holds several Items and nothing deposits by hand, so a player who had to
## take all of one to get any of it could never put the rest back; what this key does is pick
## the one amount a player actually wants, which is what the Build Gun is already holding.
## A different UI — a counter with a row per Item — would send the same intent with different
## numbers, and the Simulation would not know the difference.
const KEY_WITHDRAW: Key = KEY_T

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

## Primary fires, secondary rotates the hologram. The primary was the place button until
## there was a weapon to put on it; see `KEY_PLACE`.
##
## **Held, not an edge**, unlike every other mouse action here: a weapon with an interval
## between shots fires as often as that interval allows for as long as the trigger is down,
## so automatic fire is the absence of letting go rather than a second control. Polled in
## `sample_devices` rather than gathered from events, for that reason — an edge counted
## between frames is a click, and a trigger is not a click.
const BUTTON_FIRE: MouseButton = MOUSE_BUTTON_LEFT
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
	var withdraw_clicked: bool = false
	var wall_clicked: bool = false
	## Held, not an edge: a wrench mends for as long as it is on the Machine.
	var repair_held: bool = false
	## Held, not an edge: a weapon fires as often as its interval allows while the trigger
	## is down, so automatic fire is one reading rather than a stream of clicks.
	var fire_held: bool = false
	## Held, not an edge: a revive is restoration over time, like a wrench.
	var revive_held: bool = false
	## Which weapon frame was asked for this tick, as an index into the definition set's
	## weapon frames, or -1. An edge: one press is one swap.
	var weapon_chosen: int = -1
	## Which Gear slot's component was cycled this tick, as a slot index, or -1. An edge.
	var slot_cycled: int = -1
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
var _withdraw_clicked: bool = false
var _wall_clicked: bool = false
var _weapon_chosen: int = -1
var _slot_cycled: int = -1


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
			elif key.keycode == KEY_WITHDRAW:
				_withdraw_clicked = true
			elif key.keycode == KEY_WALL:
				_wall_clicked = true
			elif key.keycode == KEY_PLACE:
				_place_clicked = true
			elif key.keycode >= KEY_WEAPON_FIRST and key.keycode < KEY_WEAPON_FIRST + WEAPON_KEY_COUNT:
				_weapon_chosen = key.keycode - KEY_WEAPON_FIRST
			elif key.keycode >= KEY_SLOT_FIRST and key.keycode < KEY_SLOT_FIRST + SLOT_KEY_COUNT:
				_slot_cycled = key.keycode - KEY_SLOT_FIRST


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
	sample.repair_held = Input.is_key_pressed(KEY_REPAIR)
	sample.revive_held = Input.is_key_pressed(KEY_REVIVE)
	# Polled rather than gathered from events, because it is a held state and not a click.
	sample.fire_held = Input.is_mouse_button_pressed(BUTTON_FIRE)

	sample.mouse_motion = _unsent_mouse_motion
	sample.rotate_steps = _unsent_rotate_steps
	sample.machine_steps = _unsent_machine_steps
	sample.place_clicked = _place_clicked
	sample.demolish_clicked = _demolish_clicked
	sample.belt_clicked = _belt_clicked
	sample.call_wave_clicked = _call_wave_clicked
	sample.deliver_clicked = _deliver_clicked
	sample.withdraw_clicked = _withdraw_clicked
	sample.wall_clicked = _wall_clicked
	sample.weapon_chosen = _weapon_chosen
	sample.slot_cycled = _slot_cycled

	_unsent_mouse_motion = Vector2.ZERO
	_unsent_rotate_steps = 0
	_unsent_machine_steps = 0
	_place_clicked = false
	_demolish_clicked = false
	_belt_clicked = false
	_call_wave_clicked = false
	_deliver_clicked = false
	_withdraw_clicked = false
	_wall_clicked = false
	_weapon_chosen = -1
	_slot_cycled = -1

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

	if sample.wall_clicked:
		actions.append(InputAction.build_wall(player_id, BuildGun.aimed_tile(sim, player_id)))

	if sample.demolish_clicked:
		actions.append(InputAction.demolish(player_id, BuildGun.aimed_tile(sim, player_id)))

	# Sent every tick the key is down and never on the edge, because the Simulation consumes
	# and clears the intent each tick: "still holding it" is the thing it needs to know.
	# Sent whatever the Simulation would make of it, exactly as a misaimed build intent is —
	# the HUD reads `query_repair_refusal` so a player knows before they hold it.
	if sample.repair_held:
		# The *tool* aim, not the Build Gun's: a wrench is held against a Machine's body,
		# and aiming it down the ground plane means looking at your own feet to mend
		# something at eye level. See `BuildGun.aimed_tool_tile`.
		actions.append(InputAction.repair(player_id, BuildGun.aimed_tool_tile(sim, player_id)))

	# Gear comes before the trigger, so a player who swaps and shoots in one tick shoots
	# what they swapped to — the same rule that puts `select_machine` before `build_machine`.
	if sample.weapon_chosen != -1:
		var weapon: int = sim.query_definitions().weapon_gear_index(sample.weapon_chosen)
		if weapon != -1:
			actions.append(InputAction.equip_weapon(player_id, weapon))

	if sample.slot_cycled != -1:
		var next_component: int = _next_component(sim, player_id, sample.slot_cycled)
		if next_component != -2:
			actions.append(
				InputAction.fit_component(player_id, sample.slot_cycled, next_component)
			)

	# Sent every tick the trigger is down and never on the edge, because the Simulation
	# consumes and clears the intent each tick: "still holding it" is the thing it needs to
	# know, and the weapon's own interval is what decides how often that becomes a shot.
	# Sent whatever the Simulation would make of it, exactly as a misaimed build intent is —
	# the HUD reads `query_fire_refusal`, so a player reads `DRY` rather than guessing.
	if sample.fire_held:
		actions.append(InputAction.fire(player_id))

	if sample.revive_held:
		var downed: int = _nearest_downed(sim, player_id)
		if downed != -1:
			actions.append(InputAction.revive(player_id, downed))

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

	# Sent whatever the Simulation makes of it, for the reason the hand-over is. One intent
	# per Item the Machine on the Build Gun still needs, because a Machine may cost several
	# and a withdrawal names one Item: standing at the Nest, that is a player saying "the
	# rest of what this costs, please". Whether any of them lands — the reach, the store's
	# contents, whether the Run is still going — is the Simulation's decision, and the HUD
	# reads `query_withdraw_refusal` so a player knows before they press it.
	if sample.withdraw_clicked:
		actions.append_array(_withdrawals_for_the_build_gun(sim, player_id))

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


## The Gear index of the next component to fit into a slot, -1 to empty it, or **-2** when
## there is nothing to cycle through at all and no intent is worth sending.
##
## Cycles through the components that fit the slot *and that the Run has unlocked*, in Gear
## index order, with "nothing fitted" as one more position in the ring — so the ring is
## fit, fit, fit, empty, fit, and a player can always get back to a bare frame.
##
## Holds no state: where the cycle is now comes out of `query_player_component` and what is
## in it comes out of the definition set. That is the rule the Machine wheel obeys too, and
## it is what keeps this a translator rather than a second copy of the Run.
func _next_component(sim: Simulation, player_id: int, slot_index: int) -> int:
	var definitions: Definitions = sim.query_definitions()
	var slot_id: String = definitions.gear_slot_id(slot_index)
	if slot_id.is_empty():
		return -2

	# The ring, in Gear index order, with -1 (nothing fitted) last.
	var ring: PackedInt64Array = PackedInt64Array()
	for index: int in range(definitions.gear_count()):
		var definition: GearDefinition = definitions.gear_at(index)
		if definition.slot_id() != slot_id:
			continue
		if not sim.query_gear_is_unlocked(index):
			continue
		ring.append(index)
	if ring.is_empty():
		return -2
	ring.append(-1)

	var fitted: String = sim.query_player_component(player_id, slot_index)
	var at: int = ring.find(definitions.gear_index(fitted)) if not fitted.is_empty() else ring.size() - 1
	if at == -1:
		at = ring.size() - 1
	return ring[(at + 1) % ring.size()]


## The nearest Downed teammate to a player, or -1. Walked in player id order so a tie goes
## to the lowest id, which is the order the Simulation would pick too.
##
## The *choice* of who to pick up is made here because a revive intent names a player and
## something has to name one; whether that player can actually be reached is the
## Simulation's decision, and the HUD reads `query_revive_refusal` to say so.
func _nearest_downed(sim: Simulation, player_id: int) -> int:
	var here: FixedVec2 = sim.query_player_position(player_id)
	var best: int = -1
	var best_gap: int = 0
	for other: int in range(sim.query_player_count()):
		if other == player_id or not sim.query_player_is_downed(other):
			continue
		var there: FixedVec2 = sim.query_player_position(other)
		var gap_x: int = there.x - here.x
		var gap_z: int = there.z - here.z
		var squared: int = gap_x * gap_x + gap_z * gap_z
		if best != -1 and squared >= best_gap:
			continue
		best = other
		best_gap = squared
	return best


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


## One `WITHDRAW_FROM_NEST` intent per Item the Machine on the Build Gun is still short of,
## for exactly the shortfall. Empty when the Build Gun holds nothing, when the Machine is
## free, or when the player can already afford it — pressing the key then is a no-op rather
## than a withdrawal of something nobody asked for.
##
## Build costs are the only sink for materials in the game, so "what the thing I am holding
## still costs" is the amount a player wants every time. This is a presentation decision and
## it is allowed to be one: the Simulation's intent takes any Item and any count, clamps to
## what the store holds, and refuses for its own reasons.
func _withdrawals_for_the_build_gun(sim: Simulation, player_id: int) -> Array:
	var withdrawals: Array = []
	var definitions: Definitions = sim.query_definitions()
	var machine: MachineDefinition = definitions.machine(
		sim.query_player_selected_machine(player_id)
	)
	if machine == null:
		return withdrawals

	for slot: int in range(machine.build_cost_items.size()):
		var item_id: String = machine.build_cost_items[slot]
		var short: int = (
			machine.build_cost_counts[slot] - sim.query_player_item(player_id, item_id)
		)
		if short > 0:
			withdrawals.append(
				InputAction.withdraw_from_nest(player_id, definitions.item_index(item_id), short)
			)
	return withdrawals
