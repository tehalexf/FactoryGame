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

## Leaving the ground. **Held**, like the throttle: the Simulation consumes and clears the
## intent every tick, and the absence of it is what re-arms the jump, so a key held through
## a landing does not bounce (`player.jump_repeats_while_held`).
const KEY_JUMP: Key = KEY_SPACE

## Swapping between the Build Gun and the weapon. **An edge, and a toggle** — one press is
## one swap, and holding it must not swap sixty times a second.
##
## This is what #15's note said the real answer was: a hand, holding one thing or the other,
## so that left mouse can place in build mode and fire in combat mode without the two acts
## fighting over one button. It took `B` off the Belt key, which moved to `KEY_BELT` below,
## and it retired `KEY_PLACE` (E) altogether.
##
## **It is not a mode in the gating sense.** Nothing in the Simulation consults it — not a
## refusal, not the build path, not `_fight`. What it decides is which Input Action this
## file produces from a click and which object `WorldView` draws in the player's hands.
## Switching is instant, unlimited, and works mid-Wave, mid-burst and in Survey View
## (GLOSSARY.md, DESIGN.md).
const KEY_BUILD_MODE: Key = KEY_B

## Putting the Belt tool on the Build Gun, and taking it back off. **Moved off `B`**, which
## is now the holster, and it belongs here anyway: Belt routing is a build act and lives in
## build mode, which is where this key is read.
##
## **It no longer lays anything.** Before #36 one press stamped a fixed four-tile run from
## the aimed tile along the player's facing, which the code called a stopgap and was: there
## was no dragging, no routing, no corner and no preview. What it does now is swap the
## **tool**, and the primary button is what lays Belt — press, drag, release. An edge and a
## toggle, like the holster: one press is one swap.
const KEY_BELT: Key = KEY_C

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

## **The number row reads both ways, and which one it means is what the hand decides.**
##
## With the Build Gun out, `1` to `9` and `0` put the first ten Machines on it — the Machine
## picker along the bottom of the screen is that row, with the key printed on each cell. With
## the weapon out, the same keys are the weapon and Gear-slot keys below.
##
## That is the arrangement the primary button already has: `sample_devices` cannot know which
## mode anybody is in, so it records the *digit*, and `actions_for_tick` decides what it
## meant. Machine selection used to be blind mouse-wheeling through a list; the wheel still
## works and always will, and this is the way to reach a Machine without hunting for it.
##
## Ten, because the shipped Machine list is ten long and ten is as many as a hand reaches
## without looking. An eleventh Machine is a scroll away, which is where every Machine was.
const PICK_KEY_COUNT: int = 10

## The tenth picker key, which is `0` rather than a tenth digit: the row runs `1` to `9` and
## then wraps to the key at the end of it, the way every hotbar has since Doom.
const KEY_PICK_TENTH: Key = KEY_0

## Showing the rest of the HUD. Gathered here with the rest so the rebinding ticket has one
## file to change, and deliberately **not** read by `sample_devices` — `Main._input` handles
## it where it handles Escape and the save keys.
##
## Not an Input Action, for the reason saving is not one: it does nothing to the Run, it
## leaves the hash where it was, and a replay has nothing to reproduce. What it changes is
## how much of what the HUD could say is on the screen.
const KEY_HUD_DETAIL: Key = KEY_H

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
##
## **Moved off `T`, which is the revive key.** `T` was bound to both from the moment this
## key landed, so pressing it next to a Downed teammate withdrew *and* revived — a latent
## collision #29 found and this merge fixes, because #29 retired `KEY_PLACE` (E) and left a
## key free next to `KEY_DELIVER`. Withdrawing and delivering are the same act in opposite
## directions, so `E` and `F` are the pair that belong together.
const KEY_WITHDRAW: Key = KEY_E

## The Silo's dial, and the designator.
##
## **These four are the diegetic controls DESIGN.md names first**, and they are keys for the
## same reason the call-Wave lever is: the physical mechanism and its hero sound are an art
## pass, and DESIGN.md is explicit that each diegetic control needs that sound before it
## ships. What is already true of them is the half that matters — they are weighty,
## infrequent and irreversible, and none of them is a menu.
##
## `KEY_SILO_SHELL` and `KEY_SILO_CHARGES` wind the two halves of the dial, each cycling
## through its positions with a wrap at the end, because a dial has stops and not a text
## field. Neither commits anything: they move a reading the Simulation holds, which the HUD
## shows and `KEY_LOAD_SILO` sends. The cycles hold no state here — where each one is comes
## out of `query_player_dial_*` and what is in it comes out of the definition set, which is
## the arrangement the Machine wheel and the Gear slots already have.
##
## **The charge counter moved off `C`, which is now the Belt key.** #29 took `B` for the
## holster and moved the Belt to `C`, which collided with this; the Belt stays, because the
## bottom row `X` `C` `V` `B` — demolish, Belt, Wall, holster — is the build cluster and
## pulling one key out of the middle of it would be the worse trade. `K` is free and sits
## next to `KEY_LOAD_SILO` (`L`), so the counter and the commit are now under the same
## finger, which is the pairing that actually gets used: wind the count, then load.
const KEY_SILO_SHELL: Key = KEY_Z
const KEY_SILO_CHARGES: Key = KEY_K

## Committing the dial into the Silo the player is standing at. **An edge, and the one
## irreversible act a player can perform**: there is no unload intent, and a Silo already
## loaded refuses this rather than replacing what is in the tube. The HUD reads
## `query_load_silo_refusal` so the reason — out of reach, not enough Charges, already
## loaded — is on screen before the key goes down, which is what makes the irreversibility
## fair rather than cruel.
const KEY_LOAD_SILO: Key = KEY_L

## Painting a target. **Held**, like the wrench and the trigger, because a Painting is a
## channel: letting go is itself the act of interrupting, and the Charges are gone either
## way. While it is down the player is rooted and every other intent is refused, which is
## the price of a Stratagem and the reason this is the best co-op moment the design has.
##
## No aim crosses here. The tile painted is the tile the player is *standing on* — a player
## must stand at the target (GLOSSARY.md) — and where they stand is authoritative fixed-point
## Simulation state already, so the intent is derived from a query rather than from a camera
## ray. That is the float-to-fixed rule honoured rather than dodged, exactly as `FIRE` honours
## it by carrying nothing at all.
const KEY_PAINT: Key = KEY_P

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

## **The primary button does both, and which one it does is what build mode decides.** In
## build mode a click places what is on the Build Gun; in combat mode holding it fires.
## That is what the player asked for, and it is why there is a holster key at all — #15 put
## the trigger here and shoved placing onto `E`, which its own author called ugly.
##
## It is read *both* ways, every tick, because the two acts want different readings and the
## polling must not know which mode anybody is in: **an edge** (gathered from events, in
## `note_event`) because one click is one Machine, and **a held state** (polled, in
## `sample_devices`) because a weapon fires as often as its interval allows for as long as
## the trigger is down. Which of the two becomes an Input Action is decided in
## `actions_for_tick`, where the Simulation is there to be asked.
const BUTTON_PRIMARY: MouseButton = MOUSE_BUTTON_LEFT
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
	## Both readings of the sprint key, because which one matters is
	## `player.sprint_is_toggle`: the held state for a hold, the rising edge for a toggle.
	## Sampling both keeps `sample_devices` free of the setting.
	var sprint_held: bool = false
	var sprint_clicked: bool = false
	## Whether the jump key is down this tick. Held, not an edge: the Simulation needs to
	## know "still holding it", because the absence of the intent is what re-arms a jump.
	var jump_held: bool = false
	## Edges, not held states: one click is one Machine, not one a tick.
	var place_clicked: bool = false
	## The primary button coming back *up*. The other end of a drag: with the Belt tool out
	## the press anchors a route and this is what commits it, so a drag is two edges of one
	## button rather than a held state. With the Machine tool out it means nothing at all.
	var primary_released: bool = false
	## One press is one swap of what is in the player's hands.
	var build_mode_clicked: bool = false
	var demolish_clicked: bool = false
	## One press is one swap of the tool on the Build Gun, Machine for Belt or back.
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
	## Edges: one press is one click of the dial, and one commitment.
	var silo_shell_cycled: bool = false
	var silo_charges_cycled: bool = false
	var load_silo_clicked: bool = false
	## Held, not an edge: a Painting is a channel, and letting go interrupts it.
	var paint_held: bool = false
	## Which weapon frame was asked for this tick, as an index into the definition set's
	## weapon frames, or -1. An edge: one press is one swap.
	var weapon_chosen: int = -1
	## Which cell of the Machine picker was asked for this tick, as an index into the
	## definition set's Machines, or -1. An edge, and **the same keypresses `weapon_chosen`
	## and `slot_cycled` carry**: the polling cannot know which hand the player is in, so it
	## records all three readings and `actions_for_tick` picks. The primary button's two
	## readings are the same arrangement.
	var machine_picked: int = -1
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
var _place_released: bool = false
var _build_mode_clicked: bool = false
var _sprint_clicked: bool = false
var _demolish_clicked: bool = false
var _belt_clicked: bool = false
var _call_wave_clicked: bool = false
var _deliver_clicked: bool = false
var _withdraw_clicked: bool = false
var _wall_clicked: bool = false
var _weapon_chosen: int = -1
var _slot_cycled: int = -1
var _machine_picked: int = -1
var _silo_shell_cycled: bool = false
var _silo_charges_cycled: bool = false
var _load_silo_clicked: bool = false

## The drag in flight: where the primary button went down with the Belt tool out, whether
## it is still down, and how many times the player has flipped the corner since.
##
## **The same category of thing as the mouse buffer and the sprint latch** — a reading on
## its way in, not a fact about the world. Nothing authoritative is here: the route is
## *decided* on release, it crosses as one `BUILD_BELT` intent, and the Simulation is the
## only thing that knows a Belt was laid. A replay reproduces the route without reproducing
## the drag, which is the same bargain the sprint latch strikes.
##
## Abandoned the moment the Belt tool leaves the player's hands, because a drag whose tool
## is gone is a drag the player changed their mind about.
var _belt_dragging: bool = false
var _belt_drag_anchor: Vector3i = Vector3i.ZERO
var _belt_corner_flips: int = 0

## Whether a toggled sprint is currently latched on. Only read when
## `player.sprint_is_toggle` is true; see `_sprinting`, which is where the whole argument
## for this living here rather than in the Simulation is written.
var _sprint_latched: bool = false


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
			# The only release this layer reads, and it is the other end of a Belt drag.
			if button.button_index == BUTTON_PRIMARY:
				_place_released = true
			return
		match button.button_index:
			BUTTON_PRIMARY:
				# The *edge*. The held reading of the same button is polled in
				# `sample_devices`; which one becomes an intent is build mode's business.
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
			elif key.keycode == KEY_WITHDRAW:
				_withdraw_clicked = true
			elif key.keycode == KEY_WALL:
				_wall_clicked = true
			elif key.keycode == KEY_BUILD_MODE:
				_build_mode_clicked = true
			elif key.keycode == KEY_SPRINT:
				_sprint_clicked = true
			elif key.keycode == KEY_SILO_SHELL:
				_silo_shell_cycled = true
			elif key.keycode == KEY_SILO_CHARGES:
				_silo_charges_cycled = true
			elif key.keycode == KEY_LOAD_SILO:
				_load_silo_clicked = true
			elif key.keycode >= KEY_WEAPON_FIRST and key.keycode < KEY_WEAPON_FIRST + WEAPON_KEY_COUNT:
				_weapon_chosen = key.keycode - KEY_WEAPON_FIRST
			elif key.keycode >= KEY_SLOT_FIRST and key.keycode < KEY_SLOT_FIRST + SLOT_KEY_COUNT:
				_slot_cycled = key.keycode - KEY_SLOT_FIRST
			# The second reading of the number row, recorded whatever the first one made of
			# it, because the polling must not know which hand the player is in.
			if key.keycode == KEY_PICK_TENTH:
				_machine_picked = PICK_KEY_COUNT - 1
			elif key.keycode >= KEY_1 and key.keycode < KEY_1 + PICK_KEY_COUNT - 1:
				_machine_picked = key.keycode - KEY_1


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
	sample.jump_held = Input.is_key_pressed(KEY_JUMP)
	# Polled rather than gathered from events, because it is a held state and not a click.
	# The *edge* of the same button is gathered in `note_event`; build mode decides which
	# of the two readings becomes an Input Action, and this function does not know.
	sample.fire_held = Input.is_mouse_button_pressed(BUTTON_PRIMARY)
	sample.paint_held = Input.is_key_pressed(KEY_PAINT)

	sample.mouse_motion = _unsent_mouse_motion
	sample.rotate_steps = _unsent_rotate_steps
	sample.machine_steps = _unsent_machine_steps
	sample.place_clicked = _place_clicked
	sample.primary_released = _place_released
	sample.build_mode_clicked = _build_mode_clicked
	sample.sprint_clicked = _sprint_clicked
	sample.demolish_clicked = _demolish_clicked
	sample.belt_clicked = _belt_clicked
	sample.call_wave_clicked = _call_wave_clicked
	sample.deliver_clicked = _deliver_clicked
	sample.withdraw_clicked = _withdraw_clicked
	sample.wall_clicked = _wall_clicked
	sample.weapon_chosen = _weapon_chosen
	sample.slot_cycled = _slot_cycled
	sample.machine_picked = _machine_picked
	sample.silo_shell_cycled = _silo_shell_cycled
	sample.silo_charges_cycled = _silo_charges_cycled
	sample.load_silo_clicked = _load_silo_clicked

	_unsent_mouse_motion = Vector2.ZERO
	_unsent_rotate_steps = 0
	_unsent_machine_steps = 0
	_place_clicked = false
	_place_released = false
	_build_mode_clicked = false
	_sprint_clicked = false
	_demolish_clicked = false
	_belt_clicked = false
	_call_wave_clicked = false
	_deliver_clicked = false
	_withdraw_clicked = false
	_wall_clicked = false
	_weapon_chosen = -1
	_slot_cycled = -1
	_machine_picked = -1
	_silo_shell_cycled = false
	_silo_charges_cycled = false
	_load_silo_clicked = false

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

	# The holster comes first, and the rest of this function routes by the mode the player
	# will be in once it has applied — the same rule that puts `select_machine` before
	# `build_machine` and makes a scroll-and-click place what the player scrolled to.
	var in_build_mode: bool = sim.query_player_is_in_build_mode(player_id)
	if sample.build_mode_clicked:
		in_build_mode = not in_build_mode
		actions.append(InputAction.set_build_mode(player_id, in_build_mode))

	# **Whether the Build Gun is in hand, asked once, through the rule the renderer
	# also asks.** #35's playtest found the hologram drawn and green over a click that
	# did nothing: every build act below tested `in_build_mode` inline and
	# `_sync_hologram` tested something else, which is exactly the disagreement
	# `query_build_refusal` exists to prevent. `BuildGun.hand_refusal` is now the one
	# answer and both sides read it.
	#
	# It is resolved here, beside the holster and ahead of the tool, because every act
	# in this function that needs it needs the mode the player will be in once *this*
	# tick's `B` has applied — the same rule that makes a scroll-and-click place what
	# the player scrolled to.
	var gun_in_hand: bool = BuildGun.hand_refusal(in_build_mode) == Simulation.Refusal.NONE

	if sample.mouse_motion != Vector2.ZERO:
		actions.append(
			InputAction.look(
				player_id,
				InputQuantiser.pixels_to_fixed(sample.mouse_motion.x),
				InputQuantiser.pixels_to_fixed(sample.mouse_motion.y)
			)
		)

	# **Which tool is on the Build Gun, resolved before anything that depends on it**, for
	# the reason the holster is resolved first: a player who presses the Belt key and clicks
	# in the same tick gets the act of the tool they are swapping *to*.
	var build_tool: int = sim.query_player_build_tool(player_id)
	if sample.belt_clicked and gun_in_hand:
		build_tool = (
			Simulation.BUILD_TOOL_MACHINE if build_tool == Simulation.BUILD_TOOL_BELT
			else Simulation.BUILD_TOOL_BELT
		)
		actions.append(InputAction.set_build_tool(player_id, build_tool))

	# The number row, with the Build Gun out. Before the wheel and before the click, so a
	# player who presses a key and clicks in one tick places what they pressed — the rule
	# that already makes a scroll-and-click place what the player scrolled to.
	if (
		sample.machine_picked != -1
		and gun_in_hand
		and sample.machine_picked < sim.query_definitions().machine_count()
	):
		actions.append(InputAction.select_machine(player_id, sample.machine_picked))
		build_tool = Simulation.BUILD_TOOL_MACHINE

	# **The wheel reads by hand, exactly as the number row above it does.** A player
	# holding a rifle who scrolls is not choosing a Machine — they have no hologram to
	# aim and nothing on screen would change, so the only effect was to silently
	# re-point the Build Gun they would draw next. That is the same disagreement #35
	# found between the hologram and the four inline build-mode tests: a reading that
	# is gated on one side and not the other.
	if sample.machine_steps != 0 and gun_in_hand:
		var chosen: int = _stepped_machine(sim, player_id, sample.machine_steps)
		if chosen != -1:
			actions.append(InputAction.select_machine(player_id, chosen))
			# Choosing a Machine is the Simulation's way of putting the Machine tool back,
			# so the reading used for the rest of this tick follows it.
			build_tool = Simulation.BUILD_TOOL_MACHINE

	# A drag whose tool has left the player's hands is a drag they changed their mind
	# about. Dropped here rather than refused later, because an intent nobody is still
	# asking for should never cross at all.
	if build_tool != Simulation.BUILD_TOOL_BELT:
		_belt_dragging = false

	if sample.rotate_steps != 0:
		if build_tool == Simulation.BUILD_TOOL_BELT:
			# There is no hologram to turn with the Belt tool out, and the one thing about a
			# route a player chooses is which way it bends. The same button therefore does
			# the one useful thing in each hand — a tool deciding what the mouse means,
			# which is the only kind of mode this project has.
			_belt_corner_flips += sample.rotate_steps
		else:
			actions.append(InputAction.rotate_build(player_id, sample.rotate_steps))

	# **The four build acts, routed by what is in the player's hands.** A click with the
	# Build Gun out places; the same click with the weapon out fires, further down. Nothing
	# is being *forbidden* here and the Simulation has no opinion on any of it — this is one
	# button producing one of two intents, which is the whole of what build mode is.
	#
	# **The hand and the tool are two questions and both are asked.** `gun_in_hand` is
	# whether the Build Gun is out at all, through the one rule `_sync_hologram` reads;
	# `build_tool` is which tool #36 put on it. A click builds a Machine when the gun is
	# in hand *and* the Machine tool is on it, and the two compose rather than one
	# standing in for the other.
	if sample.place_clicked and gun_in_hand and build_tool == Simulation.BUILD_TOOL_MACHINE:
		# The rotation the player will be holding once this tick's rotate has applied,
		# so rotating and placing in the same tick places the Machine they can see.
		var rotation: int = WorldGrid.wrap_rotation(
			sim.query_player_build_rotation(player_id) + sample.rotate_steps
		)
		var machine: int = sim.query_player_selected_machine_index(player_id)
		# **Where the gun is pointing, which for a Miner is the Node it snapped to** (#42).
		# The same call the hologram makes, so the tile a player was shown and the tile in
		# the intent are one answer and cannot drift. See `BuildGun.snap_to_a_node` for why
		# the snap is the aim's job and not the Simulation's.
		var where: BuildGun.Placement = BuildGun.placement(sim, player_id, machine, rotation)
		# An aim with nowhere to put a Miner sends nothing, exactly as an aim past
		# `REACH_METRES` never sent a build at the horizon: this is the Build Gun deciding
		# where it is pointing, which it has always done, and the hologram has been red
		# with the reason written on it since before the button went down.
		if where.aim == BuildGun.Aim.ON_TARGET:
			actions.append(
				InputAction.build_machine(player_id, machine, where.tile, rotation)
			)

	# **Press, drag, release.** The press anchors and commits nothing; the release decides
	# the route and sends it as one intent. A press and a release in the same tick is a
	# click, which is one tile of Belt — so the cheap act and the considered one are the
	# same gesture at two speeds.
	#
	# #35's single-key Belt run is gone and that is #36's doing, not a casualty of this
	# merge: `belt_clicked` now swaps the tool rather than laying a fixed run, and the
	# route a player drags is strictly more than the four tiles straight ahead it
	# replaced. What #35 contributes here is the hand: `gun_in_hand` in place of the
	# inline `in_build_mode`, so a holstered player cannot start a drag the hologram is
	# not drawing.
	if build_tool == Simulation.BUILD_TOOL_BELT and gun_in_hand:
		if sample.place_clicked:
			_belt_dragging = true
			_belt_drag_anchor = BuildGun.aimed_tile(sim, player_id)
			_belt_corner_flips = 0
		if sample.primary_released and _belt_dragging:
			actions.append(
				InputAction.build_belt_route(
					player_id,
					_belt_drag_anchor,
					BuildGun.aimed_tile(sim, player_id),
					belt_corner_axis(sim, player_id)
				)
			)
			_belt_dragging = false

	if sample.wall_clicked and gun_in_hand:
		actions.append(InputAction.build_wall(player_id, BuildGun.aimed_tile(sim, player_id)))

	if sample.demolish_clicked and gun_in_hand:
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
	if sample.weapon_chosen != -1 and not in_build_mode:
		var weapon: int = sim.query_definitions().weapon_gear_index(sample.weapon_chosen)
		if weapon != -1:
			actions.append(InputAction.equip_weapon(player_id, weapon))

	if sample.slot_cycled != -1 and not in_build_mode:
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
	# The other half of the primary button. Held rather than an edge, because a weapon fires
	# as often as its interval allows for as long as the trigger is down — so the two
	# readings of one button are genuinely different readings and not one with a filter on.
	if sample.fire_held and not in_build_mode:
		actions.append(InputAction.fire(player_id))

	# The dial before the load, so a player who winds and commits in one tick commits what
	# they can see — the rule that puts `select_machine` before `build_machine` and a weapon
	# swap before the trigger.
	if sample.silo_shell_cycled or sample.silo_charges_cycled:
		var shell: int = _dial_shell(sim, player_id, sample.silo_shell_cycled)
		if shell != -1:
			actions.append(
				InputAction.set_silo_dial(
					player_id, shell, _dial_charges(sim, player_id, sample.silo_charges_cycled)
				)
			)

	# Sent whatever the Simulation makes of it, exactly as a misaimed build intent is. Whether
	# it lands — the reach, the stockpile, whether the tube is already full — is the
	# Simulation's decision, and the HUD reads `query_load_silo_refusal` so a player knows
	# which of them is in the way before they press a key they cannot take back.
	if sample.load_silo_clicked:
		var committed: int = sim.query_player_dial_stratagem_index(player_id)
		if committed != -1:
			actions.append(
				InputAction.load_silo(
					player_id,
					silo_tile_for_loading(sim, player_id),
					committed,
					sim.query_player_dial_charges(player_id)
				)
			)

	# Sent every tick the key is down and never on the edge, because the Simulation consumes
	# and clears the intent each tick: "still on it, still that tile" is what it needs to know,
	# and letting go is how a player interrupts themselves.
	#
	# The tile is the one the player is standing on, read back out of the Simulation. A player
	# must stand at the target (GLOSSARY.md), so there is nothing here for a camera ray to
	# decide and no float to cross.
	if sample.paint_held:
		actions.append(InputAction.paint(player_id, _standing_on(sim, player_id)))

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

	# Sent only while the key is down, like `MOVE`, because the Simulation consumes and
	# clears the intent every tick — and because the *absence* of it is what re-arms the
	# jump, so a key held through a landing does not bounce.
	if sample.jump_held:
		actions.append(InputAction.jump(player_id, true))

	# Sent every tick rather than on the edges, because the Simulation counts ticks of
	# transition and "still held" is the thing it needs to know.
	actions.append(InputAction.survey_view(player_id, sample.survey_held))
	actions.append(InputAction.sprint(player_id, _sprinting(sim, player_id, sample)))

	return actions


## Whether a Belt drag is in flight. **Read by the renderer to draw the preview**, which is
## what makes the previewed route and the route that crosses the same route: one anchor, one
## aim, one `BeltRoute` call, asked by the drawing and by the intent.
func is_dragging_a_belt() -> bool:
	return _belt_dragging


## The tile the primary button went down on, which is the end Items will enter the route
## from. Only meaningful while `is_dragging_a_belt`.
func belt_drag_anchor() -> Vector3i:
	return _belt_drag_anchor


## Which way the route in flight bends: the longer leg first, flipped once per click of the
## right button since the press.
##
## The default is `BeltRoute.natural_corner_axis`, which lives in `sim/` precisely so the
## preview and the intent cannot have different opinions about what "the natural way round"
## was. The flip count is a device reading, like the mouse buffer.
func belt_corner_axis(sim: Simulation, player_id: int) -> int:
	var natural: int = BeltRoute.natural_corner_axis(
		_belt_drag_anchor, BuildGun.aimed_tile(sim, player_id)
	)
	if posmod(_belt_corner_flips, 2) == 0:
		return natural
	return BeltRoute.ALONG_Z if natural == BeltRoute.ALONG_X else BeltRoute.ALONG_X


## Whether to tell the Simulation this player is sprinting, under whichever reading of the
## sprint key `player.sprint_is_toggle` asks for.
##
## **Toggle-versus-hold is an interpretation of a device, so it belongs here**, next to the
## mouse buffer, and not in the Simulation. What crosses the boundary is the same intent
## either way — "this player is sprinting" — so the Simulation keeps knowing only the fact
## the movement code needs, and a replay reproduces either reading identically because what
## was recorded is the resulting intent and not the keypress.
##
## The latch is the one piece of remembered state in this file besides the device buffer,
## and it is the same category of thing: a reading on its way in, not a fact about the
## world. **The Simulation stays the authority on what is true** — the latch is sent every
## tick and never consulted about anything.
##
## A latched sprint does **not** survive going down: the latch is cleared whenever the
## Simulation says this player is not on their feet, so a player comes back at the Nest
## walking. The alternative — respawning already at a run because of a key pressed before
## you died — is a control the player did not give.
func _sprinting(sim: Simulation, player_id: int, sample: DeviceSample) -> bool:
	if not sim.query_definitions().player_sprint_is_toggle:
		_sprint_latched = false
		return sample.sprint_held

	if not sim.query_player_is_alive(player_id):
		_sprint_latched = false
	elif sample.sprint_clicked:
		_sprint_latched = not _sprint_latched
	return _sprint_latched


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


## Which Silo the load key would commit to, as a tile.
##
## **Shared with the HUD, which is the whole point of it being here.** A load cannot be taken
## back, so the reason it would be refused has to be on screen before the key goes down — and
## that is only true if the line a player reads and the intent the key sends are about the same
## Silo. One function, called by both, in `game/` because *which* Silo a key means is
## presentation in exactly the way `_withdrawals_for_the_build_gun`'s choice of amount is.
##
## The Silo the player is looking at, if they are looking at one: the **tool** aim rather than
## the Build Gun's, for the reason a wrench uses it — a dial is on the side of a four-metre
## body, and aiming down the ground plane means looking at your own feet to work something at
## chest height.
##
## Otherwise the first Silo in reach, walked in index order, because standing at a Silo is what
## working its dial means and a player stood next to one should not have to hunt for its flank
## with a crosshair. **Reach is the Simulation's answer, not this layer's** — it is asked
## through `query_load_silo_refusal`, so there is no second opinion about how far an arm goes.
## Failing that the first Silo at all, so the HUD says "stand at the silo" rather than "no silo
## there"; failing even that, the aimed tile, which refuses by naming exactly what is wrong.
static func silo_tile_for_loading(sim: Simulation, player_id: int) -> Vector3i:
	var aimed: Vector3i = BuildGun.aimed_tool_tile(sim, player_id)
	var under_the_crosshair: int = sim.query_machine_at_tile(aimed)
	if under_the_crosshair != -1 and sim.query_machine_is_silo(under_the_crosshair):
		return aimed

	var shell: int = sim.query_player_dial_stratagem_index(player_id)
	var charges: int = sim.query_player_dial_charges(player_id)
	var fallback: Vector3i = aimed
	var found_one: bool = false
	for index: int in range(sim.query_machine_count()):
		if not sim.query_machine_is_silo(index):
			continue
		var tile: Vector3i = sim.query_machine_tile(index)
		if not found_one:
			fallback = tile
			found_one = true
		if (
			sim.query_load_silo_refusal(player_id, tile, shell, charges)
			!= Simulation.Refusal.OUT_OF_REACH
		):
			return tile
	return fallback


## The Stratagem index the dial should read after this tick, or -1 when the content declares
## none at all.
##
## Cycles through the Stratagems the Run has **unlocked**, in index order, wrapping — so the
## ring is only ever positions a Silo would accept, which is the same courtesy the Build Gun's
## opening Machine is. Holds no state: where the dial is now comes out of
## `query_player_dial_stratagem_index` and what is in the ring comes out of the definition
## set.
func _dial_shell(sim: Simulation, player_id: int, step_it: bool) -> int:
	var ring: PackedInt64Array = PackedInt64Array()
	for index: int in range(sim.query_stratagem_count()):
		if sim.query_stratagem_is_unlocked(index):
			ring.append(index)
	if ring.is_empty():
		return -1

	var at: int = ring.find(sim.query_player_dial_stratagem_index(player_id))
	if at == -1:
		return ring[0]
	if not step_it:
		return ring[at]
	return ring[(at + 1) % ring.size()]


## The charge count the dial should read after this tick: one more, wrapping back to one past
## the Simulation's own stop.
##
## A wrap rather than a clamp, because this is a counter a player clicks round rather than a
## number they type — and because the Simulation clamps anyway, so a wrap here cannot send
## something it would refuse.
func _dial_charges(sim: Simulation, player_id: int, step_it: bool) -> int:
	var held: int = maxi(sim.query_player_dial_charges(player_id), 1)
	if not step_it:
		return held
	var stop: int = maxi(sim.query_max_charges_per_load(), 1)
	return 1 if held >= stop else held + 1


## The tile a player is standing on, out of the Simulation's own fixed-point position.
##
## Not a camera ray and not a float: where a player stands is authoritative state, so a
## Painting's target is something the Simulation already knows exactly. The same argument
## `FIRE` makes for carrying no aim at all.
func _standing_on(sim: Simulation, player_id: int) -> Vector3i:
	var here: FixedVec2 = sim.query_player_position(player_id)
	return WorldGrid.tile_at_metres(here.x, here.z)


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
