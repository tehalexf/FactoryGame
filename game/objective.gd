## The one line that makes the opening five minutes teach itself.
##
## A Run opens on bare ground with 80 plate and no idea what to do. Everything a player
## needs is already a query — is a Miner on a Node, is a crafter starved, has anything
## reached the Nest — and until #36 none of it was ever put as an instruction. This is that
## instruction: **one line, which changes as things get done, and goes away when they are**.
##
## **Not a tutorial mode.** There is nothing to enter, nothing to skip and nothing to
## complete: the line is a pure function of the Run's current state, so a player who builds
## the whole line before reading it never sees a word of it, and a player who demolishes
## their Miner an hour in gets the first line back because the first thing is true again.
## Nothing is remembered, nothing is gated, and the Simulation does not know this exists.
##
## It lives in `game/` for the reason `BuildGun.refusal_text` does: a `Refusal` is a fact and
## a sentence about it is presentation. So is "you have not built a Miner yet".
##
## **The steps are read off roles and states rather than off ids.** Nothing here names
## `smelter_mk1`, because the set of Machines is `content/machines.csv`'s business and a line
## that named a row would be a second content table written in GDScript. What it names are
## the three things the opening loop is made of — something that mines, something that
## crafts, and a Belt between them — and the keys that do them.
class_name Objective
extends RefCounted


## What the player should do next, or "" when the opening has taught itself.
##
## Walked in order and the first unmet step wins, so the line is always about the nearest
## thing between the player and a working production line.
##
## **The player id is here because a Run opens with the weapon out** (#42). Every build step
## below ends in a click that only places with the Build Gun in hand, so a line that said
## "left click to place" to somebody holding a rifle would be telling them to shoot the
## ground. `_with_the_build_gun` names the key when it has to and says nothing when it does
## not — which is a step's *wording* changing rather than a step of its own, because
## "press B" is not a thing to achieve and a player who holsters an hour in must not be
## handed a tutorial line for it.
static func line(sim: Simulation, player_id: int) -> String:
	if sim == null or sim.query_run_is_over():
		return ""
	# Once a tier has been delivered the loop has closed at least once: the player has
	# mined, crafted, moved goods and been paid for it, and has no further use for a
	# hint line taking up the top of their screen.
	if not sim.query_completed_deliveries().is_empty():
		return ""

	if not _something_is_mining(sim):
		return _with_the_build_gun(
			sim, player_id, "Place a Miner %s — wheel or 1-9 to pick, left click to place"
				% _where_the_ore_is(sim, player_id)
		)
	if not _something_crafts(sim):
		return _with_the_build_gun(
			sim, player_id, "Place a Smelter on clear ground nearby — it turns ore into ingots"
		)
	if not _anything_is_belted(sim):
		return _with_the_build_gun(
			sim,
			player_id,
			"Press C for the Belt tool, then drag from the orange arrow to the blue one"
		)
	if _anything_is_starved(sim):
		return "Something is starved — a Belt starts past an output arrow and ends at an input"
	return "Carry ingots to the Nest and press F — delivering is how a Run gets better"


## A build step, with the key that puts the Build Gun in your hand on the front of it when
## it is not already there.
##
## A Run opens with the weapon out (#42), so the first line a player ever reads has to name
## `B` — and the moment they press it, the line stops naming it, because an instruction that
## stayed would be telling them to do something they have done. Nothing is remembered to
## make that happen: it is the same query the rest of this file is made of.
static func _with_the_build_gun(sim: Simulation, player_id: int, step: String) -> String:
	if sim.query_player_is_in_build_mode(player_id):
		return step
	var uncapitalised: String = step[0].to_lower() + step.substr(1)
	return "Press B for the Build Gun — then %s" % uncapitalised


## Whether a Miner is standing on ground it can actually work. Not "is a Miner built": a
## Miner on bare rock accumulates nothing at all (CLAUDE.md), and telling a player they have
## done the first step when they have not is worse than saying nothing.
##
## **`query_node_is_being_worked` is the question, and #52 is why it is not
## `query_node_under_machine`.** That query is geometry — the Node a footprint *covers* — and
## covering is only one of the three things a Miner needs. A Miner on coal mines iron, and a
## Mk1 on a Depth 2 seam cannot lift it; both cover a Node, both accumulate nothing, and both
## used to read here as the first step done. The projection asks it of the Node instead, off
## `query_machine_is_starved` — the Simulation's own answer to "would this Machine work" — so
## all three cases are one clause rather than a list this file has to keep in step with
## `_machine_has_its_inputs`. The beacon `WorldView` hangs over unworked ore goes quiet on the
## very same function, which is what stops a mark and a hint disagreeing.
static func _something_is_mining(sim: Simulation) -> bool:
	for node: int in range(sim.query_node_count()):
		if sim.query_node_is_being_worked(node):
			return true
	return false


## Whether anything that turns one good into another is standing. A crafter rather than a
## named Machine, so the line follows the content table rather than restating it.
static func _something_crafts(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		var definition: MachineDefinition = sim.query_definitions().machine(
			sim.query_machine_id(index)
		)
		if definition != null and definition.role == MachineDefinition.Role.CRAFTER:
			return true
	return false


## Whether any Belt is doing the job a Belt is for: fed at one end, and leading somewhere at
## the other. A Belt laid on open ground is not a connection, and a line that congratulated a
## player for laying one would be teaching the wrong thing.
static func _anything_is_belted(sim: Simulation) -> bool:
	for index: int in range(sim.query_belt_count()):
		if sim.query_belt_start_is_fed(index) and sim.query_belt_end_is_connected(index):
			return true
	return false


static func _anything_is_starved(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_starved(index):
			return true
	return false


## Where to go and find ore, as a phrase for the middle of the first step.
##
## **#52, and it is the first step reworded rather than a step of its own.** The playtest
## report was "I cant seem to find any ore in range for the miners": the nearest Node is
## about 28 m from where a Run starts a player, it is a 40 cm slab the colour of the ground,
## and the line named the act without naming the place. The beacons `WorldView` hangs over
## the ore are what make it visible once you are looking the right way; this is what makes
## you look the right way.
##
## It goes quiet by the same mechanism every step here does — the caller only asks while
## `_something_is_mining` is false — so there is nothing remembered, nothing to skip, and a
## player who finds the ore unaided reads no word of it.
##
## **A bearing relative to the player's own facing, not a compass.** This game draws no
## compass anywhere, so "north-east" is a word a player cannot act on, where "to your right"
## is one they can act on without being told the convention. Four quarters rather than eight
## points, split on which of the two components is larger: the words have to survive being
## glanced at mid-stride, and the beacon does the fine aiming once the turn is made.
##
## Falls back to naming the act when there is nothing to point at — a Map with no workable
## ore, or one whose every Node is built on. A direction to nowhere is worse than none.
static func _where_the_ore_is(sim: Simulation, player_id: int) -> String:
	var node: int = _nearest_ore_worth_walking_to(sim, player_id)
	if node == -1:
		return "near an ore node"

	var gap: FixedVec2 = _gap_to_node(sim, player_id, node)
	var metres: int = Fixed.floor_to_int(_length(gap))
	var resource: String = sim.query_node_resource(node).replace("_", " ")
	if metres <= AT_YOUR_FEET_METRES:
		return "on the %s at your feet" % resource
	return "on the %s %d m %s" % [resource, metres, _which_way(sim, player_id, gap)]


## How near is near enough that a direction would be noise rather than help, in metres. A
## Node is one 2 m tile and a Miner's footprint is 2x2, so a player within three metres of
## the middle of one is standing on the ground they are being told to build on.
const AT_YOUR_FEET_METRES: int = 3


## The nearest Node a Run could actually work and has not already built on, or -1.
##
## **Workability is the Simulation's answer and not this file's.** `query_node_is_workable_now`
## is the one place the unlock set, the Resource and the Depth tier are read together, and the
## beacons over the ore read the very same function — a line that pointed somewhere the mark
## called out of reach would be two opinions about one fact.
##
## Already built on is excluded because the step this phrase sits inside ends in a click: a
## Miner standing on ore it cannot work leaves the step unmet, and sending a player back to
## the tile it is occupying would be sending them somewhere nothing can be placed. The beacon
## `WorldView` hangs over free ore leaves on that very same question, so what is marked and
## what is pointed at are one set.
##
## Nearest by squared distance, so there is no square root and no rounding rule to decide a
## tie; Nodes are walked in index order, which is canonical tile order, so two Nodes exactly
## as far away hand the sentence to the earlier tile rather than to whichever the walk reached
## first. The same discipline a Turret's acquisition keeps.
static func _nearest_ore_worth_walking_to(sim: Simulation, player_id: int) -> int:
	var nearest: int = -1
	var nearest_squared: int = 0
	for node: int in range(sim.query_node_count()):
		if not sim.query_node_is_workable_now(node):
			continue
		if sim.query_node_is_built_on(node):
			continue
		var gap: FixedVec2 = _gap_to_node(sim, player_id, node)
		var squared: int = Fixed.mul(gap.x, gap.x) + Fixed.mul(gap.z, gap.z)
		if nearest == -1 or squared < nearest_squared:
			nearest = node
			nearest_squared = squared
	return nearest


## From the player to the middle of a Node's tile, in fixed-point metres.
static func _gap_to_node(sim: Simulation, player_id: int, node: int) -> FixedVec2:
	var centre: FixedVec2 = sim.query_tile_centre_metres(sim.query_node_tile(node))
	var at: FixedVec2 = sim.query_player_position(player_id)
	return FixedVec2.new(centre.x - at.x, centre.z - at.z)


## A gap put into the player's own frame and named.
##
## The forward axis is `query_player_facing` — the Simulation's own basis, so the word agrees
## with the direction the throttle walks them in — and the right axis is its perpendicular,
## which needs no second opinion because a quarter turn of a vector is determined. Dotting
## against both is the whole of it: no arc-tangent, which fixed point does not have, and the
## same reduction the Siege Hulk's weak point makes of "did that come from behind".
static func _which_way(sim: Simulation, player_id: int, gap: FixedVec2) -> String:
	var forward: FixedVec2 = sim.query_player_facing(player_id)
	var ahead: int = Fixed.mul(gap.x, forward.x) + Fixed.mul(gap.z, forward.z)
	# The player's right: the facing turned a quarter clockwise on the ground plane.
	var right: int = Fixed.mul(gap.x, -forward.z) + Fixed.mul(gap.z, forward.x)
	if absi(ahead) >= absi(right):
		return "ahead" if ahead >= 0 else "behind you"
	return "to your right" if right >= 0 else "to your left"


## The length of a vector in fixed-point metres. `Fixed.sqrt` floors, which is what every
## other lossy operation in this project does and is right for a figure a player reads.
static func _length(vector: FixedVec2) -> int:
	return Fixed.sqrt(Fixed.mul(vector.x, vector.x) + Fixed.mul(vector.z, vector.z))
