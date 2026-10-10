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
## the things the opening loop is made of — something that mines, something that crafts, a
## Belt between them, and a Belt into the Nest — and the keys that do them.
##
## **The one exception is #71's last step, and it is an exception to the wording and not to
## the rule.** The step that pays for a Run is about the Item the open Delivery tier is
## waiting for, and a *role* cannot name the Machine that makes it: coal and ore are both
## mined, plate and Ammunition are both crafted. So that step prints a display name — read
## off `Definitions` for the row `BuildChain` chose, exactly as a picker cell reads it, and
## still with no id written down anywhere in this file.
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
	match _step(sim, player_id):
		Step.MINE:
			return _with_the_build_gun(
				sim,
				player_id,
				"Place a Miner %s%s, then left click" % [
					_where_the_ore_is(sim, player_id), _the_key_for_this_step(sim, player_id)
				]
			)
		Step.CRAFT:
			return _with_the_build_gun(
				sim,
				player_id,
				"Place a Smelter on clear ground nearby%s; it turns ore into ingots"
					% _the_key_for_this_step(sim, player_id)
			)
		Step.BELT:
			return _with_the_build_gun(
				sim,
				player_id,
				_with_the_belt_tool(
					sim, player_id, "Drag from the orange arrow to the blue one"
				)
			)
		Step.UNSTARVE:
			return "Something is starved — a Belt starts past an output arrow and ends at an input"
		Step.PRODUCE:
			return _with_the_build_gun(sim, player_id, _the_thing_that_makes_it(sim, player_id))
		Step.DELIVER:
			return _with_the_build_gun(sim, player_id, _the_belt_into_the_nest(sim, player_id))
	return ""


## Which cell of the hotbar this step is about, in the Build Gun's own selection space: a
## Machine's definition index, or `machine_count()` for the Belt tool, or -1 for a step that
## is not about placing anything.
##
## **#53's "say what is next", and the only version worth having is one fact drawn twice.**
## The line names the act and this names the cell, and they read the same `_step` — so a
## hotbar that marked one Machine while the line named another is not a thing this file can
## express. The selection space is the one `query_player_selected_machine_index` and the
## picker's own highlight already live in, so the renderer needs no third convention.
##
## **Which Miner and which Smelter is a question for the content, not for this file.**
## `BuildChain.first_unlocked_of_role` answers it off the chain order, so a Map whose Delivery
## chain opens with a different Miner points at that one, and nothing here names a row.
static func pointed_at(sim: Simulation, player_id: int) -> int:
	match _step(sim, player_id):
		Step.MINE:
			return BuildChain.first_unlocked_of_role(sim, MachineDefinition.Role.MINER)
		Step.CRAFT:
			return BuildChain.first_unlocked_of_role(sim, MachineDefinition.Role.CRAFTER)
		Step.BELT, Step.DELIVER:
			# The Belt is not a Machine, so it has no definition index — and the cell past
			# the end of the Machine list is exactly how the picker already names it.
			return sim.query_definitions().machine_count()
		Step.PRODUCE:
			return BuildChain.first_unlocked_producer_of(sim, _what_the_nest_wants(sim))
	return -1


## The steps, in the order they are walked.
##
## Spelled as an enum rather than left implicit in a chain of early returns, because #53 made
## the step something **two** readings have to agree about. A step is a fact about the Run;
## the sentence and the marked cell are both presentation of it.
enum Step {
	## Nothing is on ground it can work.
	MINE,
	## Nothing turns one good into another.
	CRAFT,
	## No Belt is both fed and landing somewhere.
	BELT,
	## Something is standing idle for want of a connection.
	UNSTARVE,
	## Nothing in the Factory makes what the open Delivery tier is waiting for.
	PRODUCE,
	## Something makes it, and nothing is carrying it to the Nest.
	DELIVER,
	## The opening has taught itself, or the Run is over.
	NOTHING,
}


## Which step the Run is on. Walked in order and the first unmet one wins, so the answer is
## always about the nearest thing between the player and a working production line.
static func _step(sim: Simulation, player_id: int) -> Step:
	if sim == null or sim.query_run_is_over():
		return Step.NOTHING
	# Once a tier has been delivered the loop has closed at least once: the player has
	# mined, crafted, moved goods and been paid for it, and has no further use for a
	# hint line taking up the top of their screen.
	if not sim.query_completed_deliveries().is_empty():
		return Step.NOTHING
	if not _something_is_mining(sim):
		return Step.MINE
	if not _something_crafts(sim):
		return Step.CRAFT
	if not _anything_is_belted(sim):
		return Step.BELT
	if _anything_is_starved(sim):
		return Step.UNSTARVE
	# **#71's two steps, and they are two because the fixes are two.** The open tier wants a
	# particular Item, and either the Factory does not make it yet or it does and nothing is
	# carrying it over. A single step could only have named one of those, which is how the
	# line came to name an act — carrying — that neither of them is.
	var wanted: int = _what_the_nest_wants(sim)
	if wanted == -1:
		return Step.NOTHING
	if not _something_produces(sim, wanted):
		return Step.PRODUCE
	if not _anything_feeds_the_nest(sim):
		return Step.DELIVER
	return Step.NOTHING


## The key that reaches the cell this step is about, as a clause for the middle of a
## sentence — " — key 2" — or "" for a cell no key reaches.
##
## **Derived from the chain and never typed**, which is the whole reason `BuildChain.key_label`
## is not in the renderer: the line and the cell print the same number because they read the
## same function, so a Machine added as a row moves both or neither.
##
## The empty case is not hypothetical furniture. The number row is ten keys and the wheel
## stopped being a picker when it was given the hologram to turn, so an eleventh Machine has
## no way to be reached at all — and a line naming a key that does not exist would be worse
## than one that names none. The step still says what to place.
static func _the_key_for_this_step(sim: Simulation, player_id: int) -> String:
	var phrase: String = BuildChain.key_phrase(sim.query_definitions(), pointed_at(sim, player_id))
	return "" if phrase.is_empty() else " — %s" % phrase


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


## The Belt step, with the key that puts the Belt tool on the gun on the front of it when it
## is not already there.
##
## **`_with_the_build_gun`'s shape one step further, and #67 is why it was needed.** Both of
## that ticket's survey shots said `Press C for the Belt tool` in a frame where the Belt tool
## was out and a route was mid-drag — an instruction to do a thing already done, which is
## exactly what `_with_the_build_gun` exists to stop happening to `B`. A tool is not a step:
## "press C" is not a thing to achieve, and a player who swaps back an hour in must get the
## key named again rather than be handed a tutorial step for it. So nothing is remembered
## here either — it is the same query the rest of this file is made of.
##
## The two clauses compose rather than racing, because they are about two different things:
## a player holding a rifle is told about the Build Gun first whatever tool is on it, and
## the capital is left to `_with_the_build_gun` to take back down.
##
## **`drag` is an argument since #71**, which gave this file a second step that is also a
## drag: the Nest is not port-enforced, so "into the Nest" is a different sentence from "to
## the blue one" and the two must not be one wording — but the *key* clause in front of them
## is the same fact about the same hand, and two copies of it is how a tool comes to be named
## while it is already out.
static func _with_the_belt_tool(sim: Simulation, player_id: int, drag: String) -> String:
	if sim.query_player_is_laying_belt(player_id):
		return drag
	return "Press C for the Belt tool, then %s" % (drag[0].to_lower() + drag.substr(1))


## What the open Delivery tier is still waiting for, as an Item index, or -1 when there is
## nothing to be waiting for.
##
## **Read off the tier rather than written down, and #71 is the whole argument for that.**
## The step used to say `Carry ingots to the Nest and press F`, and the shipped chain opens
## on **twenty coal** — so the line named one Item while the counter waited for another, and
## a player who did exactly what it said was refused `NOTHING_TO_DELIVER` and shown nothing.
## A sentence naming a good is a sentence that has to come out of `query_delivery_goods`, or
## it is a second copy of `content/deliveries.csv` written in GDScript.
##
## The **first** outstanding good rather than all of them, because one line is one act: a
## tier wanting plate and Ammunition is two Machines and two Belts, and naming both at once
## is the wall of text the brief HUD exists to avoid. The next one arrives by itself when
## the first is satisfied, which is how every other step here moves on.
static func _what_the_nest_wants(sim: Simulation) -> int:
	var tier: int = sim.query_next_delivery()
	if tier == -1:
		return -1
	for item_id: String in sim.query_delivery_goods(tier):
		var outstanding: int = (
			sim.query_delivery_goods_required(tier, item_id)
			- sim.query_delivery_goods_delivered(item_id)
		)
		if outstanding > 0:
			return sim.query_definitions().item_index(item_id)
	return -1


## Whether anything standing in the Factory puts that Item out. Not "could be built": a
## Machine a player has not placed yet makes nothing, and the step is about placing it.
static func _something_produces(sim: Simulation, item_index: int) -> bool:
	var definitions: Definitions = sim.query_definitions()
	for index: int in range(sim.query_machine_count()):
		var machine: MachineDefinition = definitions.machine(sim.query_machine_id(index))
		if machine == null:
			continue
		var recipe: RecipeDefinition = definitions.recipe_at(machine.recipe_index)
		if recipe == null:
			continue
		for slot: int in range(recipe.output_count()):
			if recipe.output_item(slot) == item_index:
				return true
	return false


## Whether any Belt is handing goods to the Nest.
##
## `query_belt_ends_at_the_nest` and not `query_belt_end_is_connected`, which is the whole
## distinction this step turns on: a Belt into a Machine is connected and is not a Delivery.
## The rule stays in the Simulation for the reason every other geometry question here does —
## working it out from a Belt's tiles and the Nest's footprint would be a second copy of
## `_hand_off`'s own clause.
static func _anything_feeds_the_nest(sim: Simulation) -> bool:
	for index: int in range(sim.query_belt_count()):
		if sim.query_belt_ends_at_the_nest(index):
			return true
	return false


## The step that builds what the Nest is waiting for.
##
## **It names a Machine the chain chose, which is not the same thing as naming a row.** Every
## other step here names a role — "a Miner", "a Smelter" — and a role cannot answer this one:
## coal and ore are both mined, plate and Ammunition are both crafted, and what separates the
## Machine a player needs from the one beside it is the Item it puts out.
## `BuildChain.first_unlocked_producer_of` is that question asked of the content, so a Map
## whose chain opens differently points at a different cell, nothing here spells an id, and
## the display name is read off `Definitions` exactly as the picker cell reads it.
##
## Falls back to naming the goods alone when no unlocked Machine makes them — a chain asking
## for something this Run cannot yet produce at all. Pointing at nothing is better than
## pointing at a cell that is not there.
static func _the_thing_that_makes_it(sim: Simulation, player_id: int) -> String:
	var bill: String = _the_bill(sim)
	var producer: int = BuildChain.first_unlocked_producer_of(sim, _what_the_nest_wants(sim))
	if producer == -1:
		return "The Nest wants %s — nothing you can build makes it yet" % bill
	var machine: MachineDefinition = sim.query_definitions().machine_at(producer)
	return "Place a %s%s; the Nest wants %s to pay for your first Delivery" % [
		machine.display_name, _the_key_for_this_step(sim, player_id), bill
	]


## The step that carries it over: a Belt, because a Belt is the only thing that can.
##
## **The Nest is deliberately not port-enforced (#47)** — it is not a Machine, so a Belt docks
## anywhere on its 4x4 wall and there is no input arrow on it to aim at. So the sentence names
## the orange arrow at the end that has one and says "into the Nest" at the end that does not,
## rather than reusing `Step.BELT`'s "to the blue one" and sending a player after a mark the
## renderer never draws.
static func _the_belt_into_the_nest(sim: Simulation, player_id: int) -> String:
	return _with_the_belt_tool(
		sim,
		player_id,
		"Drag a Belt from an orange arrow into the Nest — it wants %s" % _the_bill(sim)
	)


## What the Nest is still short of, as a phrase — "20 coal". The count is what is outstanding
## rather than what the tier asked for, so a bill half paid by a Belt already running says so.
static func _the_bill(sim: Simulation) -> String:
	var wanted: int = _what_the_nest_wants(sim)
	var item_id: String = sim.query_definitions().item_id(wanted)
	var tier: int = sim.query_next_delivery()
	var outstanding: int = (
		sim.query_delivery_goods_required(tier, item_id)
		- sim.query_delivery_goods_delivered(item_id)
	)
	return "%d %s" % [outstanding, item_id.replace("_", " ")]


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
## `_machine_has_its_inputs`. The scanner that pings the nearest ore goes quiet on that very
## same function, which is what stops a mark and a hint disagreeing about whether the opening
## has taught itself.
static func _something_is_mining(sim: Simulation) -> bool:
	return sim.query_anything_is_mining()


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


## Whether anything is stuck for want of a connection — which is **not** the same question
## as `query_machine_is_starved`, and #74 is the whole of the difference.
##
## That query is "does not hold a whole Recipe's worth right now", and it is exactly right
## for the Simulation: it is what the Power grid bills against, what stops a Machine banking
## progress, and what the amber tag over a Machine means. Read here on its own it was wrong,
## because **a line that is working is intermittently short**: the shipped Smelter smelts two
## ore every 3.2 s and the shipped Miner makes one every 1.5 s, so a saturated Smelter is
## empty-handed for the ticks between consuming one craft's ore and holding the next craft's.
## `Step.UNSTARVE` is walked ahead of the step below it, so a player who had built the line
## correctly was told, every few seconds, to apply a fix they had already applied — and the
## step that pays for their Run was hidden underneath it.
##
## So the step is about a Machine that is starved **and has nothing docked into a declared
## input port**, which is the population the sentence is actually about and the permanent case
## rather than the momentary one. `query_machine_is_fed` is the second half, and it is one
## clause of `_hand_off`'s own geometry read from the Machine's side — the shape
## `query_machine_branch_count` already took for outputs — so nothing here learns a new rule.
##
## **A Miner is why the pair is read rather than the feed alone.** A Miner's input is the
## ground, so it declares no input port and is never fed: one on bare rock, one over the
## wrong Resource and one on a seam deeper than its `max_depth` are all starved for ever
## with nothing to connect, and telling a player about *that* is this step earning its place.
## A predicate that required a missing Belt would have thrown all three away.
##
## **Counting ticks was the other candidate and is refused.** "Starved for N ticks running"
## would answer the same question and would need state in a file whose entire premise is that
## it has none — nothing remembered, nothing to skip, a pure function of the Run.
static func _anything_is_starved(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_starved(index) and not sim.query_machine_is_fed(index):
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
	var node: int = sim.query_nearest_workable_node(player_id)
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
