## One player intent, and the only thing that may cross the network wire.
##
## ADR 0002 puts the game on deterministic lockstep: clients exchange intents, not
## world state, and each one simulates every tick identically. So an Input Action
## is the sole way anything outside the Simulation can affect what is inside it.
## The Godot-side layer translates devices into these and hands them to `step`;
## it never writes Simulation state itself.
##
## The encoding is deliberately generic — a kind, the player who intended it, and
## an ordered list of integer arguments whose meaning each kind defines. That
## keeps hashing, comparison and (later) serialisation written once, so adding a
## kind never touches this file's plumbing. Build intents, Recipe selections, Silo
## loads and lever pulls all fit the same shape — and #17 proved it: the dial, the
## irreversible load and the Painting are three kinds, three constructors and three
## accessors, with nothing in the plumbing touched.
##
## Construct these through the named static functions rather than by hand, so
## argument layouts stay in one place.
class_name InputAction
extends RefCounted

enum Kind {
	## Does nothing. Useful as an explicit "this player sent no intent this tick".
	NONE = 0,
	## Movement intent. args = [forward, strafe], fixed-point, each clamped to
	## [-ONE, ONE]. A throttle in the player's *own* frame, not a destination and not
	## a world-space direction: the Simulation owns the walking speed, so a client
	## cannot move faster by sending a larger number, and it owns the yaw the throttle
	## is rotated by, so a client cannot walk somewhere other than where the
	## Simulation says it is facing.
	##
	## Per tick. Sending no `MOVE` is how a player stands still, so an idle tick is a
	## tick spent slowing down rather than one spent coasting on a stale throttle.
	MOVE = 1,
	## Replace the Simulation's content definitions. args = [digest of the new set].
	## The set itself travels in `payload`.
	##
	## A reload is an Input Action rather than a method on the façade for three
	## reasons: it is ordered with every other intent, so the tick it lands on is
	## unambiguous; it appears in a recorded script, so a replay reproduces it; and
	## in co-op it is the Host's intent broadcast like any other, which is where the
	## digest earns its place — every client reloads its own copy of the files, and a
	## client whose copy hashes differently can refuse instead of desyncing silently.
	RELOAD_DEFINITIONS = 2,
	## Build a Machine. args = [machine definition index, tile x, tile y, tile z,
	## rotation in quarter turns].
	##
	## The Machine travels as an index into the definition set's sorted Machine ids
	## rather than as a string, because an intent on the wire is integers; the
	## Simulation resolves it to an id at the moment it builds, and holds the id
	## afterwards so a hot-reload that renumbers the table cannot renumber a Factory
	## that is already standing.
	BUILD_MACHINE = 3,
	## Lay a Belt route. args = [from x, y, z, to x, y, z, corner axis].
	##
	## Both ends travel because a Belt is a run rather than a tile: a player presses,
	## drags and releases, and sending the whole route as one intent means a dragged
	## route either lands or is refused, never half-lands. **The route is what crosses**
	## — not the drag that produced it, and not the tiles the mouse happened to pass
	## over.
	##
	## The seventh argument is the corner: `BeltRoute.ALONG_X` travels along x before
	## turning, `BeltRoute.ALONG_Z` along z. A route is an L, so it becomes one Belt or
	## two, and a route that is already straight means the same thing under either
	## reading. The argument was **added** rather than replacing the action, so every
	## recorded script written when a Belt was a straight run still means what it meant:
	## an absent seventh argument reads as 0, which is `ALONG_X`.
	##
	## Two identical tiles are a drag that never moved, which is one tile of Belt aimed
	## along the player's own facing — authoritative Simulation state, so nothing crosses
	## here that was not already a fact about the Run. The argument `PAINT` makes for
	## carrying no aim at all.
	##
	## No Belt definition index travels. Unlike a Machine, a Belt has no row in
	## `content/machines.csv`: it is not a Machine (GLOSSARY.md keeps the two apart),
	## it runs no Recipe, and its one tier's rating lives in `content/tuning.toml`.
	BUILD_BELT = 4,
	## Mouse look. args = [pixels right, pixels down], fixed-point counts of pixels
	## of mouse travel.
	##
	## Pixels, not an angle: the mouse is the one genuinely continuous device the game
	## reads, and the sensitivity that turns its travel into an angle is a tuning value
	## the Simulation owns — the same arrangement as `MOVE`, where the intent is a
	## throttle and the speed belongs to the Simulation. A client therefore cannot turn
	## faster by sending a bigger number, and the angle a player is facing is
	## authoritative state rather than something the camera remembers.
	##
	## The float-to-fixed crossing happens before this is constructed, in
	## `game/input_quantiser.gd`, which is the only place in the project where a float
	## device reading becomes a Simulation quantity.
	LOOK = 5,
	## Hold or release Survey View. args = [1 while held, 0 once released].
	##
	## Held rather than toggled, and sent every tick it is held, so the camera's
	## position is a function of how long the key has been down rather than of a latch
	## somebody has to remember to clear. It is state in the Simulation because the
	## *transition* is: a lift caught halfway is a different state from one at either
	## end, and the camera is told where to be rather than deciding.
	##
	## This is not a build mode. Building works identically at either height
	## (DESIGN.md, GLOSSARY.md), and nothing in the Simulation consults it to decide
	## whether an intent is allowed.
	SURVEY_VIEW = 6,

	## Whether the player is sprinting. Held, like SURVEY_VIEW: the Simulation keeps
	## the flag so letting go of the key is itself an action with a tick attached.
	SPRINT = 10,
	## Put a Machine on the Build Gun. args = [machine definition index].
	##
	## What a player is about to place is Simulation state rather than something the
	## controller remembers, because the controller is forbidden to hold anything
	## authoritative — and because in co-op what another player is lining up is worth
	## drawing. The Simulation stores the resolved *id*, so a hot-reload that resorts
	## the table cannot change what is on the Build Gun under a player's hands.
	SELECT_MACHINE = 7,
	## Turn the Build Gun's hologram. args = [quarter turns, signed].
	##
	## The rotation persists until changed, so a player lines a Machine up once and
	## places several. It travels in the build intent as well, which keeps that intent
	## self-contained: a recorded script describes what was placed and which way round
	## without having to be replayed from the beginning to find out.
	ROTATE_BUILD = 8,
	## Take a Machine or a Belt back apart. args = [tile x, tile y, tile z].
	##
	## A tile rather than an index, because a player aims a Build Gun at a thing and not
	## at a position in an array — and because an index into the Simulation's Machine
	## arrays is not something anything outside it may hold.
	##
	## Everything comes back: a Machine's build cost in full, whatever it was holding,
	## and the Items riding a Belt. Demolishing destroys nothing, which is what makes
	## iterating on a layout cheap (issue #1, user story 7).
	DEMOLISH = 9,
	## Pull the lever that calls the next Wave early. args = [].
	##
	## No arguments: the lever has one position and the Wave it summons is whatever the
	## Factory's Heat says the next Wave is. A count or a difficulty would be a second
	## number to tune and a second thing for a player to be wrong about; the only choice on
	## offer is *when*, which is the whole of what makes it a throttle.
	##
	## An Input Action and not a method, like everything else, so a called Wave has a tick
	## attached, appears in a recorded script, and in co-op is one player's intent that the
	## other three see land. Pulled while a Wave is already coming it is refused as a silent
	## no-op; `Simulation.query_call_wave_early_refusal` is what says why, beforehand.
	CALL_WAVE_EARLY = 11,
	## Hand what you are carrying over to the Nest, against the Delivery it is waiting on.
	## args = [].
	##
	## No arguments, for the reason the lever has none: there is one Delivery open at a
	## time and one bill to pay, so the only thing a player chooses is *when* to walk over
	## — and what crosses the counter is everything the open tier is still waiting for and
	## the player is carrying, clamped to the bill. A count would be a second thing for a
	## player to get wrong about an act that is already physical.
	##
	## Progression is physical (GLOSSARY.md): there is no research menu and no science
	## resource, so unlocking the next tier of Machines, Gear components and Stratagems is
	## this intent, performed standing at the Nest. Handed over out of reach, with nothing
	## the Nest wants, or at a Depth the next tier is gated above, it is refused as a
	## silent no-op; `Simulation.query_delivery_refusal` is what says why, beforehand.
	DELIVER_TO_NEST = 12,
	## Build one tile of Wall. args = [tile x, tile y, tile z].
	##
	## One tile rather than a run, unlike `BUILD_BELT`. A Belt is a run because Items travel
	## along it and the run is the thing a player drags out; a Wall is a tile because the only
	## question it answers is whether *this* tile is walkable, and because a Wall chewed
	## through in the middle of a line has to leave the rest of the line standing.
	##
	## No definition index travels, for the reason none travels with a Belt: a Wall has no row
	## in `content/machines.csv`. It is not a Machine (DESIGN.md lists it alongside the Nest
	## and the Belt), it runs no Recipe, and its one tier's hit points live in
	## `content/tuning.toml`.
	BUILD_WALL = 13,
	## Hold the Pneumatic Wrench on whatever is standing on a tile, mending it.
	## args = [tile x, tile y, tile z].
	##
	## **Held, and sent every tick it is held**, like `SURVEY_VIEW` and `MOVE`: a repair is
	## restoration over time, so what the Simulation needs to know each tick is "still on it,
	## still that tile". An intent that latched would mend a Factory the player had walked away
	## from, and the whole point of hand repair is that it costs a player's presence and
	## attention mid-Wave rather than materials.
	##
	## A tile rather than an index, exactly as `DEMOLISH` carries one: a player aims a tool at
	## a thing, and an index into the Simulation's arrays is not something anything outside it
	## may hold. Any tile of a Machine's footprint will do, and a Wall occupies one tile.
	REPAIR = 14,
	## Take goods back out of the Nest's store. args = [Item definition index, count].
	##
	## The symmetric half of `DELIVER_TO_NEST`: a Belt running into the Nest banks what the
	## open Delivery's bill does not want, and this is how it comes back into a player's
	## hands. Without it materials only ever left a player's pockets, and a Run could not
	## fund a second Ammo Press out of its own output (issue #27).
	##
	## **Two arguments where the hand-over has none, and that asymmetry is deliberate.** A
	## hand-over has one open bill and one answer to what the Nest wants, so the only thing
	## a player chooses is when to walk over. A withdrawal has neither: the store holds
	## several Items at once, and a player who had to take all of one to get any of it could
	## never put the rest back — nothing deposits by hand. So the intent names what and how
	## much, and the Simulation clamps the count to what is actually there, exactly as a
	## hand-over is clamped to the bill.
	##
	## The Item travels as an index into the definition set's sorted Item ids rather than as
	## a string, for the reason a Machine does in `BUILD_MACHINE`: an intent on the wire is
	## integers. An index naming no Item is refused, as is a withdrawal made out of reach,
	## from an empty store or after the Nest has fallen — a silent no-op in every case, and
	## `Simulation.query_withdraw_refusal` is what says why, beforehand.
	WITHDRAW_FROM_NEST = 15,
	## Pull the trigger on whatever the player is holding. args = [].
	##
	## **No aim travels, and that is the strongest version of the rule rather than an
	## omission.** The float-to-fixed boundary exists because a mouse reports pixels and a
	## camera ray is float arithmetic — but a player's yaw and pitch are already
	## authoritative fixed-point Simulation state (#6), put there by `LOOK`, which is
	## itself the quantised intent. So where a shot goes is something the Simulation
	## already knows exactly; a tile or a direction carried here would be a *second*
	## opinion about the aim, derived from a float, and the first thing to disagree in
	## co-op. Combat resolution reads `_player_yaw` and `_player_pitch` and nothing else.
	##
	## **Held, and sent every tick it is held**, like `REPAIR` and `MOVE`: a weapon with an
	## interval between shots fires as often as that interval allows for as long as the
	## trigger is down, so automatic fire is the absence of letting go rather than a second
	## intent. The Simulation consumes and clears it every tick.
	##
	## One intent for all three weapons, because there is one frame. Whether this swings a
	## Pneumatic Wrench at what is in front of the player or sends a round down the line of
	## aim is `content/gear.csv`'s `attack` column and nothing here — which is what makes a
	## fourth weapon a row.
	FIRE = 16,
	## Put a weapon frame in the player's hands. args = [Gear definition index].
	##
	## An index into the definition set's sorted Gear ids, for the reason `SELECT_MACHINE`
	## carries one: an intent on the wire is integers. The Simulation resolves it to an id
	## at the moment it equips and holds the id afterwards, so a hot-reload that resorts the
	## table cannot change what is in a player's hands.
	##
	## An index naming a component rather than a frame, or a piece of Gear no Delivery has
	## unlocked, is refused as a silent no-op and the previous weapon stands.
	EQUIP_WEAPON = 17,
	## Fit a component to the weapon frame. args = [slot index, Gear definition index].
	##
	## **Both travel**, which is what makes the intent self-contained and what makes
	## *clearing* a slot expressible: a Gear index of -1 empties the named slot. The slot is
	## also derivable from the component's own row, and the Simulation refuses a pairing
	## where the two disagree rather than quietly preferring one — a recorded script has to
	## describe what was fitted and where without being replayed to find out.
	##
	## The slot index is into the definition set's interned slots, which are exactly the
	## `kind` values `content/gear.csv` names other than `weapon`. So a fourth slot is a row
	## and this intent does not change.
	FIT_COMPONENT = 18,
	## Hold a revive on a Downed teammate. args = [the player being revived].
	##
	## **Held, and sent every tick it is held**, exactly like `REPAIR`, and it is the same
	## trade in a different currency: what it costs is a player standing still, in the open,
	## during a Wave, doing nothing else. A rescuer who stops sending it stops reviving and
	## banks nothing, for the reason a wrench banks nothing.
	##
	## A player id rather than a position, because a player is not a tile — the Simulation
	## already knows where everybody is, and an intent carrying a position would be a second
	## opinion about it.
	##
	## Meaningless on a solo Run and refused there, because **solo play has no Downed state**
	## (GLOSSARY.md): there is nobody to revive you, so a player at zero health dies.
	REVIVE = 19,
	## Set the dial a player is carrying to a Silo. args = [Stratagem definition index,
	## charge count].
	##
	## **The dial, not the load.** Nothing is committed by this and nothing is irreversible
	## about it: it is where a player has wound the shell selector and the charge counter
	## before they walk over, and it is Simulation state for both of the reasons
	## `SELECT_MACHINE` is — the controller is forbidden to hold anything authoritative, and
	## in co-op what somebody else is winding up is worth drawing.
	##
	## Absolute rather than a step, exactly as `SELECT_MACHINE` carries the Machine it wants
	## rather than a scroll direction. Where the cycle is now is a query the controller reads;
	## what it does with a key press is presentation.
	##
	## The Stratagem travels as an index into the definition set's sorted Stratagem ids,
	## because an intent on the wire is integers. The charge count is clamped by the
	## Simulation to between one and `silo.max_charges_per_load`, so a client cannot wind a
	## bigger strike by sending a bigger number.
	SET_SILO_DIAL = 20,
	## Commit the dial into a Silo. args = [tile x, tile y, tile z, Stratagem definition
	## index, charge count].
	##
	## **This is the irreversible one** (GLOSSARY.md: committing a Charge is irreversible).
	## There is no unload intent and there will not be one: a Silo that is already loaded
	## refuses a second load rather than replacing the first, so a player who picked the
	## wrong shell lives with it or fires it away. That is the whole of what makes the
	## decision weighty, and it is why DESIGN.md puts Silo loading on the diegetic list — the
	## friction is problem-solving under pressure rather than transcription.
	##
	## A tile rather than a Machine index, exactly as `DEMOLISH` and `REPAIR` carry one: a
	## player works a dial on a Machine in front of them, and an index into the Simulation's
	## arrays is not something anything outside it may hold. Any tile of the Silo's footprint
	## will do.
	##
	## The shell type and the count travel **as well as** living on the dial, for the reason a
	## `BUILD_MACHINE` intent carries its rotation: the intent has to describe the commitment
	## completely, so a recorded script says what went into the tube without being replayed
	## from the beginning to find out.
	LOAD_SILO = 21,
	## Paint a target, calling in whatever a Silo is loaded with. args = [tile x, tile y,
	## tile z].
	##
	## **Held, and sent every tick it is held**, like `REPAIR`, `REVIVE` and `FIRE`: a
	## Painting is a channel, so what the Simulation needs each tick is "still on it, still
	## that tile". Letting go is itself the act of interrupting, and **an interrupted Painting
	## consumes the Charge and produces nothing** (GLOSSARY.md) — the Charges leave the Silo
	## on the tick the channel begins, which is what makes that true by construction rather
	## than by a rule somebody has to remember.
	##
	## The tile has to be the one the player is standing on, because **a player must stand at
	## the target** (GLOSSARY.md). A tile travels anyway rather than nothing at all, for the
	## reason a repair carries one: the intent describes what is being done, and a recorded
	## script that said only "painting" would not say where.
	##
	## While it is in flight the player is **unable to act** — see `Refusal.PLAYER_IS_PAINTING`
	## — and cannot walk. That is the price of every Stratagem and the best co-op moment the
	## design has: one player committed and helpless while the others cover them.
	PAINT = 22,
	## Leave the ground. args = [1 while the key is held, 0 once released].
	##
	## **Held and sent every tick it is held**, like `MOVE` and `FIRE`, and consumed and
	## cleared every tick — so the absence of this intent is how a player lets go of the
	## key, and an idle tick in a recorded script is a tick with the key up. That matters
	## here more than it does for a throttle: `player.jump_repeats_while_held` is false by
	## default, so what re-arms a jump *is* the absence of the intent.
	##
	## No height and no impulse travels. How high a jump clears and how hard gravity brings
	## it back are tuning the Simulation owns — the arrangement `MOVE` has, where the intent
	## is a throttle and the speed belongs to the Simulation — so a client cannot jump higher
	## by sending a bigger number, and jump height is a value somebody tuning the game can
	## change mid-Run.
	JUMP = 23,
	## Put the Build Gun or a weapon in the player's hands. args = [1 for the Build Gun,
	## 0 for the weapon].
	##
	## **The resulting mode travels, not a flip.** A recorded script therefore describes
	## what the player ended up holding without having to be replayed from the beginning to
	## find out, and two intents arriving in one tick cannot cancel each other out. The
	## controller reads the mode it is in out of `query_player_is_in_build_mode` and sends
	## the opposite, which is the same arrangement the Machine wheel and the Gear slot ring
	## have: the controller translates, it does not remember.
	##
	## **This is not a mode in the gating sense, and nothing in the Simulation consults it.**
	## Building is never gated (GLOSSARY.md, DESIGN.md) and neither is firing: what the flag
	## decides is which intent the *controller* produces from a left click and which object
	## the renderer draws in the player's hands. It is Simulation state because what somebody
	## is holding is a fact about them worth drawing, worth saving and worth replaying — and
	## because in co-op it is worth seeing — not because anything asks it for permission.
	## Switching is instant, unlimited, and works mid-Wave; `player.holster_seconds` delays
	## only the animation.
	SET_BUILD_MODE = 24,
	## Puts the Machine tool or the Belt tool on a player's Build Gun. args = [tool].
	##
	## A Belt is not a Machine and has no row in `content/machines.csv`, so it cannot be
	## one more position on the Machine list — but a player laying one still has to be able
	## to say so and have the mouse mean it. That is what a *tool* is: with the Machine tool
	## out a click places what the Build Gun is holding, and with the Belt tool out a press,
	## a drag and a release lay a route.
	##
	## **The resulting tool travels rather than a flip**, for the three reasons
	## `SET_BUILD_MODE` carries a mode: a recorded script describes what the player ended up
	## holding without being replayed to find out, two intents in one tick cannot cancel
	## out, and asking for the tool already in hand is a no-op whose hash does not move.
	##
	## **It is not a gate.** Nothing in the Simulation consults it — no refusal, no build
	## path. A `BUILD_BELT` sent with the Machine tool out lays Belt and a `BUILD_MACHINE`
	## sent with the Belt tool out places a Machine, exactly as build mode forbids nothing.
	SET_BUILD_TOOL = 25,
}

## Most pixels of mouse travel one `LOOK` action may carry on either axis. Far more
## than any real frame produces at any sensitivity, and finite, which is what matters:
## an unbounded intent is an unbounded turn.
const MAX_LOOK_PIXELS: int = 10000 * Fixed.ONE

var kind: Kind = Kind.NONE
var player_id: int = 0
var args: PackedInt64Array = PackedInt64Array()

## Out-of-band payload, used by `RELOAD_DEFINITIONS` and nothing else. The one
## action whose subject is a blob rather than a handful of integers: a definition
## set is the same kind of thing as the world state transferred on join, not an
## intent. It is not hashed directly — `args[0]` holds its digest, and that is what
## goes into the hash — so the generic encoding above stays the whole wire format.
var payload: RefCounted = null


func _init(action_kind: Kind = Kind.NONE, acting_player: int = 0, action_args: PackedInt64Array = PackedInt64Array()) -> void:
	kind = action_kind
	player_id = acting_player
	args = action_args


static func none(acting_player: int = 0) -> InputAction:
	return InputAction.new(Kind.NONE, acting_player)


## Walks a player. `forward` is positive towards whatever they are looking at and
## `strafe` is positive to their right; both are throttles clamped to full.
static func move(acting_player: int, forward: int, strafe: int) -> InputAction:
	return InputAction.new(
		Kind.MOVE,
		acting_player,
		PackedInt64Array([
			Fixed.clamp_fixed(forward, -Fixed.ONE, Fixed.ONE),
			Fixed.clamp_fixed(strafe, -Fixed.ONE, Fixed.ONE),
		])
	)


## Turns the view by a count of pixels of mouse travel: `pixels_right` turns the
## player clockwise, `pixels_down` pitches the view downward. Both are fixed-point,
## and both are clamped to a sane sweep so a malformed or hostile intent cannot spin
## the view arbitrarily far in one tick.
static func look(acting_player: int, pixels_right: int, pixels_down: int) -> InputAction:
	return InputAction.new(
		Kind.LOOK,
		acting_player,
		PackedInt64Array([
			Fixed.clamp_fixed(pixels_right, -MAX_LOOK_PIXELS, MAX_LOOK_PIXELS),
			Fixed.clamp_fixed(pixels_down, -MAX_LOOK_PIXELS, MAX_LOOK_PIXELS),
		])
	)


## Holds or releases Survey View for a player. Sent every tick the key is held.
static func survey_view(acting_player: int, held: bool) -> InputAction:
	return InputAction.new(
		Kind.SURVEY_VIEW, acting_player, PackedInt64Array([1 if held else 0])
	)


## Puts a tool on a player's Build Gun: `Simulation.BUILD_TOOL_MACHINE` or
## `Simulation.BUILD_TOOL_BELT`. The resulting tool travels rather than a flip, for the
## reason the resulting mode does.
static func set_build_tool(acting_player: int, tool_kind: int) -> InputAction:
	return InputAction.new(Kind.SET_BUILD_TOOL, acting_player, PackedInt64Array([tool_kind]))


## Replaces the Simulation's content definitions with `definitions`.
##
## The digest goes into `args` so that the action's hash describes the set it
## carries. A Simulation refuses the action if the payload is missing, failed to
## load, or does not hash to the digest claimed here.
static func sprint(acting_player: int, held: bool) -> InputAction:
	return InputAction.new(Kind.SPRINT, acting_player, PackedInt64Array([1 if held else 0]))


## Holds or releases the jump key for a player. Sent every tick the key is held; the
## absence of it is the release, exactly as the absence of a `MOVE` is standing still.
static func jump(acting_player: int, held: bool) -> InputAction:
	return InputAction.new(Kind.JUMP, acting_player, PackedInt64Array([1 if held else 0]))


## Puts the Build Gun (`true`) or the weapon (`false`) in a player's hands. The resulting
## mode travels rather than a flip, so the intent describes the swap completely.
static func set_build_mode(acting_player: int, build: bool) -> InputAction:
	return InputAction.new(
		Kind.SET_BUILD_MODE, acting_player, PackedInt64Array([1 if build else 0])
	)


## Replaces the Simulation's content definitions with `definitions`.
##
## The digest goes into `args` so that the action's hash describes the set it
## carries. A Simulation refuses the action if the payload is missing, failed to
## load, or does not hash to the digest claimed here.
static func reload_definitions(acting_player: int, definitions: Definitions) -> InputAction:
	var digest: int = 0 if definitions == null else definitions.digest()
	var action: InputAction = InputAction.new(
		Kind.RELOAD_DEFINITIONS, acting_player, PackedInt64Array([digest])
	)
	action.payload = definitions
	return action


## Builds a Machine at a tile. The tile is the footprint's anchor, and the footprint
## grows along +x and +z from it by whatever `content/machines.csv` says — that file
## is the only authority for a footprint.
## `rotation` is in quarter turns and is carried in the intent rather than read from
## the player's Build Gun, so the intent describes the placement completely.
static func build_machine(
	acting_player: int, machine_index: int, tile: Vector3i, rotation: int = 0
) -> InputAction:
	return InputAction.new(
		Kind.BUILD_MACHINE,
		acting_player,
		PackedInt64Array([
			machine_index, tile.x, tile.y, tile.z, WorldGrid.wrap_rotation(rotation)
		])
	)


## Takes apart whatever is standing on a tile. Any tile of a Machine's footprint will
## do, and any tile of a Belt's run takes the whole run.
## Calls the next Wave early for the player who pulled the lever. Carries nothing: the
## Wave is whatever the Factory's Heat has earned, and the only thing being chosen is when.
static func call_wave_early(acting_player: int) -> InputAction:
	return InputAction.new(Kind.CALL_WAVE_EARLY, acting_player)


## Hands a player's goods over to the Nest, against the Delivery it is waiting on.
static func deliver_to_nest(acting_player: int) -> InputAction:
	return InputAction.new(Kind.DELIVER_TO_NEST, acting_player)


## Takes `count` of an Item back out of the Nest's store, by index into the definition set's
## sorted Item ids. Clamped by the Simulation to what the store is holding, so asking for
## more than is there takes what is there rather than being refused.
static func withdraw_from_nest(acting_player: int, item_index: int, count: int) -> InputAction:
	return InputAction.new(
		Kind.WITHDRAW_FROM_NEST, acting_player, PackedInt64Array([item_index, maxi(count, 0)])
	)


## The Item definition index a `WITHDRAW_FROM_NEST` action names.
func withdraw_item_index() -> int:
	return _arg(0)


## How many of it a `WITHDRAW_FROM_NEST` action asks for.
func withdraw_count() -> int:
	return _arg(1)


static func demolish(acting_player: int, tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.DEMOLISH, acting_player, PackedInt64Array([tile.x, tile.y, tile.z])
	)


## Puts a Machine on a player's Build Gun, by index into the definition set's sorted
## Machine ids. An index naming no Machine is refused and the previous choice stands.
static func select_machine(acting_player: int, machine_index: int) -> InputAction:
	return InputAction.new(Kind.SELECT_MACHINE, acting_player, PackedInt64Array([machine_index]))


## Turns a player's Build Gun by `quarter_turns`, which may be negative.
static func rotate_build(acting_player: int, quarter_turns: int) -> InputAction:
	return InputAction.new(Kind.ROTATE_BUILD, acting_player, PackedInt64Array([quarter_turns]))


## Lays a Belt along the straight run from one tile to another, both ends included.
## The Items travel from `from_tile` towards `to_tile`, so the aim is also the
## direction of flow.
##
## Kept for the runs that really are straight — a fixture, a test, a recorded script
## older than the drag. It is `build_belt_route` with the corner left at its default,
## which a straight route ignores.
static func build_belt(acting_player: int, from_tile: Vector3i, to_tile: Vector3i) -> InputAction:
	return build_belt_route(acting_player, from_tile, to_tile, BeltRoute.ALONG_X)


## Lays a Belt route: a run along one axis, a corner, a run along the other.
##
## What a released drag sends. `corner_axis` is `BeltRoute.ALONG_X` or
## `BeltRoute.ALONG_Z` and decides which leg comes first — the one thing about the
## shape a player chooses, and therefore the one thing that has to travel so a replay
## lays the route they saw rather than the route the arithmetic would have picked.
static func build_belt_route(
	acting_player: int, from_tile: Vector3i, to_tile: Vector3i, corner_axis: int
) -> InputAction:
	return InputAction.new(
		Kind.BUILD_BELT,
		acting_player,
		PackedInt64Array([
			from_tile.x, from_tile.y, from_tile.z,
			to_tile.x, to_tile.y, to_tile.z,
			corner_axis,
		])
	)


## The tile a `BUILD_BELT` action starts its run at — the end Items enter from.
func belt_from_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## The tile a `BUILD_BELT` action ends its run at — the end Items leave from.
func belt_to_tile() -> Vector3i:
	return Vector3i(_arg(3), _arg(4), _arg(5))


## Which way a `BUILD_BELT` action's route bends. 0 — `BeltRoute.ALONG_X` — for an
## action recorded before routes had a corner, which is the same thing a straight run
## means under either reading.
func belt_corner_axis() -> int:
	return _arg(6)


## The Machine definition index a `BUILD_MACHINE` action names.
func build_machine_index() -> int:
	return _arg(0)


## The tile a `BUILD_MACHINE` action anchors its footprint at.
func build_tile() -> Vector3i:
	return Vector3i(_arg(1), _arg(2), _arg(3))


## How many quarter turns a `BUILD_MACHINE` action turns its footprint by.
func build_rotation() -> int:
	return _arg(4)


## The tile a `DEMOLISH` action is aimed at.
func demolish_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## Builds one tile of Wall. No definition index, because a Wall has no row in
## `content/machines.csv` — it is not a Machine (DESIGN.md).
static func build_wall(acting_player: int, tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.BUILD_WALL, acting_player, PackedInt64Array([tile.x, tile.y, tile.z])
	)


## The tile a `BUILD_WALL` action would stand a Wall on.
func wall_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## Holds the Pneumatic Wrench on whatever is standing on a tile. Sent every tick it is held;
## not sending it is how a player stops repairing.
static func repair(acting_player: int, tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.REPAIR, acting_player, PackedInt64Array([tile.x, tile.y, tile.z])
	)


## The tile a `REPAIR` action is aimed at.
func repair_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## Pulls the trigger on whatever the player is holding. Sent every tick it is held; not
## sending it is how a player stops firing. Carries no aim — see `Kind.FIRE`.
static func fire(acting_player: int) -> InputAction:
	return InputAction.new(Kind.FIRE, acting_player)


## Puts a weapon frame in a player's hands, by index into the definition set's sorted Gear
## ids. An index naming no Gear, naming a component, or naming Gear no Delivery has
## unlocked is refused and the previous weapon stands.
static func equip_weapon(acting_player: int, gear_index: int) -> InputAction:
	return InputAction.new(Kind.EQUIP_WEAPON, acting_player, PackedInt64Array([gear_index]))


## Fits a component into one of the weapon frame's slots, or — with `gear_index` of -1 —
## empties that slot.
static func fit_component(
	acting_player: int, slot_index: int, gear_index: int
) -> InputAction:
	return InputAction.new(
		Kind.FIT_COMPONENT, acting_player, PackedInt64Array([slot_index, gear_index])
	)


## The Gear definition index an `EQUIP_WEAPON` or `FIT_COMPONENT` action names. -1 on a
## `FIT_COMPONENT` empties the slot.
func gear_index() -> int:
	return _arg(0) if kind == Kind.EQUIP_WEAPON else _arg(1)


## The slot a `FIT_COMPONENT` action names.
func gear_slot_index() -> int:
	return _arg(0)


## Sets a player's dial: which Stratagem, and how many Charges of it one load commits.
## Clamped by the Simulation to a count a load may actually carry.
static func set_silo_dial(
	acting_player: int, stratagem_index: int, charges: int
) -> InputAction:
	return InputAction.new(
		Kind.SET_SILO_DIAL, acting_player, PackedInt64Array([stratagem_index, charges])
	)


## The Stratagem definition index a `SET_SILO_DIAL` action winds the dial to.
func dial_stratagem_index() -> int:
	return _arg(0)


## How many Charges a `SET_SILO_DIAL` action winds the counter to.
func dial_charges() -> int:
	return _arg(1)


## Commits a load into the Silo standing on a tile. **Irreversible**: there is no intent
## that takes it back out, and a Silo already loaded refuses this rather than replacing what
## is in the tube.
static func load_silo(
	acting_player: int, tile: Vector3i, stratagem_index: int, charges: int
) -> InputAction:
	return InputAction.new(
		Kind.LOAD_SILO,
		acting_player,
		PackedInt64Array([tile.x, tile.y, tile.z, stratagem_index, charges])
	)


## The tile a `LOAD_SILO` action is working the dial on. Any tile of the Silo's footprint.
func load_silo_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## The Stratagem definition index a `LOAD_SILO` action commits.
func load_stratagem_index() -> int:
	return _arg(3)


## How many Charges a `LOAD_SILO` action commits.
func load_charges() -> int:
	return _arg(4)


## Paints a target, channelling whatever a Silo is loaded with. Sent every tick it is held;
## not sending it is how a player interrupts themselves, and the Charge is gone either way.
static func paint(acting_player: int, tile: Vector3i) -> InputAction:
	return InputAction.new(
		Kind.PAINT, acting_player, PackedInt64Array([tile.x, tile.y, tile.z])
	)


## The tile a `PAINT` action is being held on.
func paint_tile() -> Vector3i:
	return Vector3i(_arg(0), _arg(1), _arg(2))


## Holds a revive on a Downed teammate. Sent every tick it is held.
static func revive(acting_player: int, downed_player: int) -> InputAction:
	return InputAction.new(Kind.REVIVE, acting_player, PackedInt64Array([downed_player]))


## The player a `REVIVE` action is being held on.
func revive_target() -> int:
	return _arg(0)


## The Machine definition index a `SELECT_MACHINE` action names.
func selected_machine_index() -> int:
	return _arg(0)


## How many quarter turns a `ROTATE_BUILD` action turns the Build Gun by, signed.
func rotation_quarter_turns() -> int:
	return _arg(0)


## The definition set a `RELOAD_DEFINITIONS` action carries, or null.
func reload_payload() -> Definitions:
	if payload is Definitions:
		return payload
	return null


## The digest the action claims its payload has.
func declared_digest() -> int:
	return _arg(0)


## Whether a `SURVEY_VIEW` action is holding the camera up or letting it down.
func survey_is_held() -> bool:
	return _arg(0) != 0


## Whether a `SPRINT` action is holding the sprint on or letting it go.
func sprint_is_held() -> bool:
	return args.size() > 0 and args[0] != 0


## Whether a `JUMP` action is holding the key down or letting it up.
func jump_is_held() -> bool:
	return args.size() > 0 and args[0] != 0


## Whether a `SET_BUILD_MODE` action asks for the Build Gun or for the weapon.
func build_mode_is_wanted() -> bool:
	return args.size() > 0 and args[0] != 0


## Which tool a `SET_BUILD_TOOL` action asks for.
func build_tool_wanted() -> int:
	return _arg(0)


## Pixels of rightward mouse travel a `LOOK` action carries, fixed-point.
func look_pixels_right() -> int:
	return _arg(0)


## Pixels of downward mouse travel a `LOOK` action carries, fixed-point.
func look_pixels_down() -> int:
	return _arg(1)


## Fixed-point forward throttle, positive towards what the player is looking at.
## Zero for any other kind.
func move_intent_forward() -> int:
	return _arg(0)


## Fixed-point strafe throttle, positive to the player's right. Zero for any other
## kind.
func move_intent_strafe() -> int:
	return _arg(1)


## Feeds this action into a hash. Recordings are compared by hash too, so a
## replay cannot quietly be fed different inputs than the ones recorded.
func feed_into(hasher: StateHasher) -> void:
	hasher.feed_int(kind)
	hasher.feed_int(player_id)
	hasher.feed_ints(args)


func equals(other: InputAction) -> bool:
	if other == null:
		return false
	return kind == other.kind and player_id == other.player_id and args == other.args


## A copy. The payload is shared rather than copied, which is safe because a loaded
## definition set is immutable — hot-reload builds a new one instead of editing one.
func duplicate_action() -> InputAction:
	var copy: InputAction = InputAction.new(kind, player_id, args.duplicate())
	copy.payload = payload
	return copy


## A missing argument reads as zero rather than crashing. A malformed action
## should degrade to a no-op, because in lockstep a crash takes down the Run.
func _arg(index: int) -> int:
	if index < 0 or index >= args.size():
		return 0
	return args[index]


func _to_string() -> String:
	var kind_name: String = Kind.keys()[kind]  # purity-ok: enum keys are declaration-ordered
	return "InputAction(%s, player %d, %s)" % [kind_name, player_id, args]
