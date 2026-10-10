## The positive signal: that a production line is connected and carrying.
##
## Everything this project draws about a line is a complaint — a red post where a Belt leads
## nowhere, an amber tag over a starved Machine, a post at a blocked branch, a sentence about
## a bad dock. Nothing said the line *works*, and "no red posts" is not a signal, it is the
## lack of one. These are the tests for the three far-end projections that say what a Belt
## reaches, for `LineWorks`, which assembles those answers into a chain, and for the renderer
## that draws one completing and then stops.
extends TestCase


func _miner_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("miner_mk1")


func _smelter_index(sim: Simulation) -> int:
	return sim.query_definitions().machine_index("smelter_mk1")


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


## A Run on a Map with one iron ore Node at the origin, for the reason `test_belts` asks for
## one: a test about what a Belt reaches should not also be a test about where the Map put
## its ore.
func _sim_on_one_node() -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, 0), "iron_ore", 1)
	layout.sort_nodes()
	return Simulation.new(1, 1, null, layout)


## A Miner on that Node, a four-tile Belt, and a Smelter the Belt runs into. The Smelter
## stands square and the line runs west to east, which is the arrangement its declared ports
## want: ore in on the western face.
func _mining_line(sim: Simulation) -> void:
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, 0)),
		InputAction.build_belt(0, Vector3i(2, 0, 0), Vector3i(5, 0, 0)),
		InputAction.build_machine(0, _smelter_index(sim), Vector3i(6, 0, 0)),
	])


# ── What a Belt's far end is ──────────────────────────────────────────────────

func test_a_belts_far_end_names_the_machine_the_hand_off_would_feed() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	assert_eq(sim.query_machine_id(1), "smelter_mk1", "the premise: the Smelter is Machine 1")
	assert_eq(
		sim.query_belt_feeds_machine(0),
		1,
		"the Belt ends against the Smelter's declared input port"
	)
	assert_eq(sim.query_belt_feeds_belt(0), -1, "and hands on to no other Belt")
	assert_false(sim.query_belt_feeds_the_nest(0), "and reaches no Nest")
	assert_true(sim.query_belt_end_is_connected(0), "so its far end leads somewhere")


func test_a_belts_far_end_names_the_belt_it_hands_on_to_and_the_nest_it_reaches() -> void:
	var sim: Simulation = Simulation.new(1, 1, null, MapLayout.empty())
	# The Nest's 4x4 is anchored at (-6, -6), so it covers x -6..-3 on z -6..-3. A run from
	# (-1, -4) westward to (-2, -4) ends pointing at (-3, -4), which is its eastern wall.
	sim.step([
		InputAction.build_belt(0, Vector3i(1, 0, -4), Vector3i(0, 0, -4)),
		InputAction.build_belt(0, Vector3i(-1, 0, -4), Vector3i(-2, 0, -4)),
	])
	assert_eq(sim.query_belt_count(), 2, "the premise: two runs end to end")

	assert_eq(sim.query_belt_feeds_belt(0), 1, "the first run hands on to the second")
	assert_eq(sim.query_belt_feeds_machine(0), -1, "and reaches no Machine")
	assert_false(sim.query_belt_feeds_the_nest(0), "and no Nest")

	assert_true(sim.query_belt_feeds_the_nest(1), "the second ends at the Nest's wall")
	assert_eq(sim.query_belt_feeds_belt(1), -1, "and hands on to no Belt")
	assert_true(sim.query_belt_end_is_connected(1))


func test_asking_what_a_belts_far_end_is_leaves_the_run_exactly_where_it_was() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	_run(sim, 400)
	var before: int = sim.hash()
	for index: int in range(sim.query_belt_count()):
		sim.query_belt_feeds_machine(index)
		sim.query_belt_feeds_belt(index)
		sim.query_belt_feeds_the_nest(index)
		sim.query_belt_end_is_connected(index)
	assert_eq(sim.hash(), before, "a projection the Simulation never reads back")


# ── What a chain is, and when it is whole ─────────────────────────────────────

func _whole_chains(sim: Simulation) -> Array:
	var whole: Array = []
	for chain: LineWorks.Chain in LineWorks.chains(sim):
		if chain.is_whole:
			whole.append(chain)
	return whole


func test_a_mining_line_carrying_ore_reads_as_one_whole_chain() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	# The second ore reaches the Smelter on tick 407, which is the tick it stops being
	# starved — see `test_belts`. Before that the line is connected and not yet working.
	_run(sim, 406)
	assert_true(_whole_chains(sim).is_empty(), "a starved Smelter is not a working line")

	_run(sim, 1)
	var whole: Array = _whole_chains(sim)
	if not assert_eq(whole.size(), 1, "the Miner, the Belt and the Smelter are one chain"):
		return
	var chain: LineWorks.Chain = whole[0]
	assert_eq(chain.machines, PackedInt64Array([0, 1]), "both Machines are in it")
	assert_eq(chain.belts, PackedInt64Array([0]), "and the one Belt between them")
	assert_eq(chain.links.size(), 1, "joined by one link")
	assert_false(chain.reaches_the_nest, "no Belt of it points at the Nest")


func test_a_chain_with_a_dangling_belt_off_one_of_its_machines_is_not_whole() -> void:
	# A positive signal must never contradict a complaint: a line standing next to a red post
	# is not a line that works, even when the rest of it is carrying.
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	_run(sim, 407)
	if not assert_eq(_whole_chains(sim).size(), 1, "the premise: it was whole"):
		return

	# A second Belt out of the Miner's eastern face, pointed at nothing.
	sim.step([InputAction.build_belt(0, Vector3i(0, 0, 2), Vector3i(0, 0, 4))])
	_run(sim, 200)
	assert_eq(sim.query_belt_count(), 2, "the premise: the second run laid")
	assert_false(sim.query_belt_end_is_connected(1), "and leads nowhere")
	assert_true(
		_whole_chains(sim).is_empty(),
		"so the chain its Miner is in does not claim to work"
	)


func test_a_chain_whose_belt_is_empty_is_connected_and_not_yet_carrying() -> void:
	# The condition that makes this a statement about a line that is *running* rather than
	# about one that is merely wired up. Ore takes 90 ticks to mine and the Belt is empty
	# until the first lump is on it.
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	_run(sim, 30)
	assert_eq(sim.query_belt_item_count(0), 0, "the premise: nothing on the Belt yet")
	assert_true(sim.query_belt_end_is_connected(0), "though it is wired up")
	assert_true(sim.query_belt_start_is_fed(0))
	assert_true(_whole_chains(sim).is_empty(), "a line carrying nothing is not working")


func test_a_miner_belting_ore_to_the_nest_is_a_chain_of_its_own() -> void:
	# The opening Delivery, which is the first thing a Run is told to build and which has one
	# Machine in it — so a chain is a set of *ends* joined by runs, not a count of Machines.
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, 0, -4), "iron_ore", 1)
	layout.sort_nodes()
	var sim: Simulation = Simulation.new(1, 1, null, layout)
	sim.step([
		InputAction.build_machine(0, _miner_index(sim), Vector3i(0, 0, -4)),
		InputAction.build_belt(0, Vector3i(-1, 0, -4), Vector3i(-2, 0, -4)),
	])
	_run(sim, 200)
	var whole: Array = _whole_chains(sim)
	if not assert_eq(whole.size(), 1, "one Miner and one run into the Nest is a chain"):
		return
	var chain: LineWorks.Chain = whole[0]
	assert_eq(chain.machines, PackedInt64Array([0]))
	assert_true(chain.reaches_the_nest, "and the Nest is the end it joins")
	assert_eq(chain.signature(), "0,0,-4|nest", "which its signature says")


func test_asking_what_the_chains_are_leaves_the_run_exactly_where_it_was() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	_run(sim, 407)
	var before: int = sim.hash()
	LineWorks.chains(sim)
	assert_eq(sim.hash(), before, "the Simulation does not know this file exists")


# ── Drawing one completing, and watching it subside ───────────────────────────

## Steps the Simulation with the view watching every tick, which is what the game does and
## what a change-detector needs: the signal fires on the frame a chain *becomes* whole, so a
## test that stepped a hundred ticks and then synced once would be asking a different
## question.
func _watch(sim: Simulation, view: WorldView, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])
		view.sync(sim)


func test_a_line_that_starts_working_lights_up_and_then_goes_quiet() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	_watch(sim, view, 406)
	assert_eq(view.line_works_tag_count(), 0, "nothing claims to work while it is starved")

	# Tick 407 is the one the Smelter stops being starved on, and the signal is a change.
	_watch(sim, view, 1)
	assert_eq(view.line_works_tag_count(), 2, "a tag over each of the chain's two Machines")
	assert_true(view.line_works_pulse_count() > 0, "and goods running down the Belt")

	# It is a moment rather than a condition: the line is still working and the mark has had
	# its say. A signal that stayed on would be the hedge #66 took off the port arrows.
	_watch(sim, view, WorldView.LINE_WORKS_TICKS)
	assert_true(_whole_chains(sim).size() == 1, "the line is still working")
	assert_eq(view.line_works_tag_count(), 0, "and the signal has subsided")
	assert_eq(view.line_works_pulse_count(), 0)
	view.free()


func test_the_signal_is_timed_by_the_tick_so_a_frame_that_stepped_nothing_draws_the_same() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	_watch(sim, view, 420)
	if not assert_true(view.line_works_pulse_count() > 0, "the premise: it is lit"):
		view.free()
		return

	var pulses: int = view.line_works_pulse_count()
	var where: Vector3 = view.line_works_pulse_position(0)
	view.sync(sim)
	assert_eq(view.line_works_pulse_count(), pulses, "nothing moved because no tick passed")
	assert_true(
		view.line_works_pulse_position(0).is_equal_approx(where),
		"and the lights are where they were"
	)
	view.free()


func test_the_signal_adds_no_node_per_belt_or_per_machine() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var quiet: int = view.get_child_count()
	# Whole on tick 407, so eighteen ticks later the train's head is three tiles down a
	# four-tile run and two of its lights are lit at `LINE_WORKS_PULSE_GAP_TILES` apart.
	_watch(sim, view, 425)
	assert_eq(view.line_works_pulse_count(), 2, "the premise: two lights are drawn")
	assert_eq(view.line_works_tag_count(), 2, "and a tag over each Machine")
	assert_eq(
		view.get_child_count(),
		quiet,
		"instances of two meshes, not a node a mark"
	)
	view.free()


func test_a_chain_tag_clears_the_body_a_player_can_see_not_the_housing_underneath_it() -> void:
	# #41, #48 and #50's defect, which this file has now paid for four times: a Smelter's
	# housing is 1.5 m and its flue reaches about 7.75, so a tag placed off the declaration
	# is inside the chimney — drawn, the right colour, and invisible.
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	_watch(sim, view, 407)
	if not assert_eq(view.line_works_tag_count(), 2, "the premise: both Machines are marked"):
		view.free()
		return

	assert_eq(
		view.line_works_tether_count(),
		view.line_works_tag_count(),
		"and every tag is joined to the body it is about (#66)"
	)
	for machine: int in range(2):
		var roof: float = view.machine_drawn_roof_metres(sim, machine)
		var tag: Vector3 = view.line_works_tag_position(machine)
		assert_true(
			tag.y > roof,
			"%s's tag at %.2f must clear its own drawn body at %.2f"
				% [sim.query_machine_id(machine), tag.y, roof]
		)
		var tether: Vector3 = view.line_works_tether_position(machine)
		assert_true(
			tether.y > roof and tether.y < tag.y,
			"and its tether spans the gap: roof %.2f, tether %.2f, tag %.2f"
				% [roof, tether.y, tag.y]
		)
	view.free()


func test_the_brief_hud_says_the_line_is_running_only_while_the_signal_is_up() -> void:
	var sim: Simulation = _sim_on_one_node()
	_mining_line(sim)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	_watch(sim, view, 406)
	assert_false(view.hud_brief_text().contains("LINE RUNNING"))

	_watch(sim, view, 1)
	assert_true(
		view.hud_brief_text().contains("LINE RUNNING"),
		"the acknowledgement the opening minutes never had: %s" % view.hud_brief_text()
	)

	_watch(sim, view, WorldView.LINE_WORKS_TICKS)
	assert_false(
		view.hud_brief_text().contains("LINE RUNNING"),
		"and it goes with the mark rather than staying"
	)
	view.free()
