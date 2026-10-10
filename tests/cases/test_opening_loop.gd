## **Follow the objective line and the Run gets better. Verified rather than argued.**
##
## #71 is the ticket this file exists for, and the report is the strongest kind there is: a
## player read the line, did what it said, and was stuck anyway. *"its not clear how to carry
## ingots to the nest... the smelter works but idk what next"*. The line said `Carry ingots to
## the Nest and press F`; there is no intent anywhere that moves goods out of a Machine's
## output buffer into a player's hands, and the tier the Nest was actually waiting on wanted
## **coal**. Every individual claim the line made was assertable and none of them was asserted
## together — so the one thing that would have caught it is a test that *obeys* the line and
## checks where obeying it lands.
##
## **What makes this end to end rather than a replay of a plan somebody wrote down.** Nothing
## here knows the sequence of steps. The loop asks `Objective.pointed_at` which cell the line
## is about and `Objective.line` what the act is, does that, and asks again — so a step that
## named an impossible act would leave the loop with nothing to do, and a step that named the
## wrong Machine would build the wrong Machine. The sequence, the Machines, the keys and the
## stopping condition are all read out of the objective line.
##
## **The one seam it does not drive is the aim**, and that is deliberate rather than a gap.
## Where to point a Build Gun is `BuildGun.aimed_tile`'s answer from a yaw and a pitch, and
## `test_recorded_session.gd` is the fixture that proves a mouse reaches a tile. What this
## file substitutes is the *same query the line's own wording is derived from* —
## `query_nearest_workable_node` is where "on the iron ore 12 m behind you" comes from — so
## the tile a step is obeyed at is the tile the step named, and nothing in between is invented.
extends TestCase

## A compact Map: the Nest where it always is, iron where a Run can see it, coal a short walk
## the other way.
##
## **Compact rather than the shipped Map, which is `test_nest_store`'s precedent and reason.**
## The starter Map's coal Node is a forty-tile haul from the Nest — a real and interesting
## decision, and a lesson in Belt routing rather than a statement about whether the opening
## line teaches itself. The *content* is the shipped content, unaltered, because the whole
## claim here is about what the shipped Delivery chain asks for.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.add_node(Vector3i(0, 0, -6), "coal", 1)
	layout.sort_nodes()
	return layout


## Where the Smelter goes: clear ground near the Miner, which is what the step says.
const CRAFTER_TILE: Vector3i = Vector3i(0, 0, 5)

## The Belt that joins the two Machines of the opening line, and the Belt that pays for the
## Run. Both are a straight run on one axis, so the only thing a route has to get right is
## which tile it starts on — a Belt is loaded from the tile *past* a Machine's output port
## and ends pointing at an input, and getting that off by one is the commonest mistake there
## is, which is why the fixture spells both ends out.
const LINE_BELT: Array = [Vector3i(1, 0, 2), Vector3i(1, 0, 4)]
const NEST_BELT: Array = [Vector3i(-1, 0, -6), Vector3i(-2, 0, -6)]


## How many ticks the loop is allowed. Twenty coal at a Coal Miner's rate is about half a
## minute of game time, and three Machines against a baseline plant tuned for two means the
## grid is throttling throughout — so the bound is generous and failing it is a real failure
## rather than a slow machine.
const TICK_BUDGET: int = 6000


func test_a_player_who_does_what_the_line_says_completes_a_delivery() -> void:
	var sim: Simulation = Simulation.new(1, 1, null, _layout())
	# A Run opens with the weapon out (#42) and the line's first word is `B`.
	sim.step([InputAction.set_build_mode(0, true)])

	var acts: PackedStringArray = PackedStringArray()
	for tick: int in range(TICK_BUDGET):
		if not sim.query_completed_deliveries().is_empty():
			break
		var act: String = _obey(sim)
		if not act.is_empty():
			acts.append(act)
		sim.step([])

	assert_false(
		sim.query_completed_deliveries().is_empty(),
		"following the line paid for a tier; what it did instead: %s" % ", ".join(acts)
	)
	# And it got there by being told to, not by the loop guessing: a Miner, a crafter, the
	# Belt between them, the Machine that makes what the Nest wants, and the Belt that
	# carries it over.
	assert_eq(acts.size(), 5, ", ".join(acts))
	assert_eq(sim.query_completed_deliveries()[0], "t01_munitions", ", ".join(acts))


func test_the_line_goes_quiet_once_it_has_been_obeyed() -> void:
	# The other half of "the opening teaches itself": a player who has done every step is
	# left alone. Asserted on the same Run, because a line that went quiet on a Run that
	# never got anywhere would be the bug rather than the fix.
	var sim: Simulation = Simulation.new(1, 1, null, _layout())
	sim.step([InputAction.set_build_mode(0, true)])
	for tick: int in range(TICK_BUDGET):
		if not sim.query_completed_deliveries().is_empty():
			break
		_obey(sim)
		sim.step([])
	assert_false(sim.query_completed_deliveries().is_empty(), "the premise")
	assert_eq(Objective.line(sim, 0), "", Objective.line(sim, 0))


func test_the_line_never_names_an_act_the_simulation_has_no_intent_for() -> void:
	# The acceptance criterion as a sentence about every line the Run ever shows, rather than
	# about the one step the report was stuck on. `F` hands over what is *in a player's
	# pockets* and nothing fills those from a Machine, so a step naming a carry is a step
	# naming an act that does not exist — whatever Item it names.
	var sim: Simulation = Simulation.new(1, 1, null, _layout())
	sim.step([InputAction.set_build_mode(0, true)])
	var seen: int = 0
	for tick: int in range(TICK_BUDGET):
		var line: String = Objective.line(sim, 0).to_lower()
		if not line.is_empty():
			seen += 1
			assert_false(line.contains("carry"), line)
			assert_false(line.contains("press f"), line)
		if not sim.query_completed_deliveries().is_empty():
			break
		_obey(sim)
		sim.step([])
	assert_true(seen > 0, "the Run did show a line at some point")


## Does whatever the line is currently asking for, and names what it did — or returns "" on a
## tick where the line is asking for nothing a player can act on this instant.
##
## `pointed_at` is the branch rather than the prose, which is #53's arrangement working for
## us: the cell and the sentence come out of one `_step`, so acting on the cell is acting on
## the sentence. The Belt cell is the one that needs the words as well, because there are two
## different drags — one between two Machines and one into the Nest — and the line is what
## says which.
func _obey(sim: Simulation) -> String:
	var cell: int = Objective.pointed_at(sim, 0)
	if cell == -1:
		return ""
	var definitions: Definitions = sim.query_definitions()
	if cell == definitions.machine_count():
		var into_the_nest: bool = Objective.line(sim, 0).contains("into the Nest")
		var route: Array = NEST_BELT if into_the_nest else LINE_BELT
		if sim.query_belt_at_tile(route[0]) != -1:
			return ""
		sim.step([InputAction.build_belt(0, route[0], route[1])])
		return "belt into the Nest" if into_the_nest else "belt along the line"

	var machine: MachineDefinition = definitions.machine_at(cell)
	if not machine.is_miner():
		if sim.query_machine_at_tile(CRAFTER_TILE) != -1:
			return ""
		sim.step([InputAction.build_machine(0, cell, CRAFTER_TILE)])
		return machine.display_name

	# "Place a Miner on the iron ore 12 m behind you" — the bearing in that sentence is
	# computed from this very query, so this is the tile the step named.
	var node: int = sim.query_nearest_workable_node(0)
	if node == -1:
		return ""
	sim.step([InputAction.build_machine(0, cell, sim.query_node_tile(node))])
	return machine.display_name
