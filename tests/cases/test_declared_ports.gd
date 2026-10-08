## Where a Belt is allowed to dock, through the Simulation façade.
##
## #47's half two. `content/machine_ports.csv` has declared an exact edge, tile and direction for
## every port since #19, and #36 drew an arrow on each one — while `_load_from_port` and
## `_hand_off` went on taking any footprint edge tile. A player was being shown a rule the
## Simulation did not enforce, which is worse than being shown nothing. These are the claims that
## make the arrow the rule.
extends TestCase

const GROUND: int = 0

## A Miner that gives its ore back on the middle of its southern face and nowhere else, and a
## Smelter that takes ore on the middle of its northern face and gives plate back on the middle
## of its southern one. **One tile per face rather than a whole face**, because what is under
## test is the rule and a single tile is the sharpest statement of it. The shipped table declares
## whole faces, for reasons `content/machine_ports.csv` gives and `test_machine_ports.gd` asserts.
const PORTS: String = """machine_id,port_id,direction,edge,tile,height_mm
miner_mk1,ore,output,south,1,900
smelter_mk1,ore,input,north,1,900
smelter_mk1,plate,output,south,1,900
"""

const MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
miner_mk1,Miner Mk1,miner,2,2,1.8,0,0,400,1,0,0,0,0,mine_iron_ore,
smelter_mk1,Smelter Mk1,crafter,3,3,1.5,0,0,500,0,0,0,0,0,smelt_iron_plate,
"""

const RECIPES: String = """id,display_name,inputs,outputs,seconds
mine_iron_ore,Mine Iron Ore,,iron_ore:1,0.2
smelt_iron_plate,Smelt Iron Plate,iron_ore:1,iron_plate:1,0.2
"""


func _run(sim: Simulation, ticks: int) -> void:
	for tick: int in range(ticks):
		sim.step([])


## Steps until the condition holds, reporting whether it ever did.
func _step_until(sim: Simulation, ticks: int, condition: Callable) -> bool:
	for tick: int in range(ticks):
		if condition.call():
			return true
		sim.step([])
	return condition.call()


## The shipped tuning, which these tests are not about. Read off disk rather than copied, so a
## tuning change cannot leave a stale copy here, with the opening bill written in the one Item
## these Recipes mention.
func _tuning() -> String:
	var file: FileAccess = FileAccess.open(
		"%s/%s" % [Definitions.CONTENT_DIR, Definitions.TUNING_FILE], FileAccess.READ
	)
	assert_not_null(file, "the shipped tuning file is readable")
	var text: String = file.get_as_text()
	file.close()
	return text.replace('starting_stock = "iron_plate:110"', 'starting_stock = "iron_ore:110"')


## Puts ore on the Belt the way the game does: a Miner on the Node at the origin, feeding its
## own declared port. 2x2 from (0, 0), so the port tile is (1, 1) and the dock is (1, 2) — which
## is where every Belt in the hand-off tests below starts.
func _give_the_belt_an_item(sim: Simulation) -> void:
	sim.step([InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0))])
	_run(sim, 120)


func _content(ports: String = PORTS) -> Definitions:
	return Definitions.parse(
		MACHINES, RECIPES, _tuning(), WAVES, DELIVERIES, GEAR, STRATAGEMS,
		Definitions.MACHINES_FILE, Definitions.RECIPES_FILE, Definitions.TUNING_FILE,
		Definitions.WAVES_FILE, Definitions.DELIVERIES_FILE, Definitions.GEAR_FILE,
		Definitions.STRATAGEMS_FILE, ports, Definitions.PORTS_FILE
	)


## A Map with one iron Node at the origin and no Breach, so every tile a test names is a small
## number and no Wave interrupts the arithmetic.
func _sim(content: Definitions) -> Simulation:
	var layout: MapLayout = MapLayout.empty()
	layout.add_node(Vector3i(0, GROUND, 0), "iron_ore", 1)
	layout.sort_nodes()
	return Simulation.new(1, 1, content, layout)


# ── Loading out of a declared output port ─────────────────────────────────────
# The Miner stands at the origin and is 2x2, so it covers (0,0) to (1,1). Its one output port is
# the middle of the south face, which for a 2-wide face is tile 1 — the (1, 1) corner — and the
# tile a Belt docks at is therefore (1, 2), running south.

func test_a_belt_off_the_declared_output_port_carries_what_the_machine_made() -> void:
	var sim: Simulation = _sim(_content())
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 6)),
	])
	_run(sim, 120)
	assert_true(sim.query_belt_item_count(0) > 0, "the declared port loads the Belt")
	assert_true(sim.query_belt_start_is_fed(0), "and the renderer says so at the same tile")


func test_a_belt_off_a_wall_that_declares_no_port_carries_nothing() -> void:
	# The same Miner, the same Belt, one tile along its own face: (0, 2) is on the south wall and
	# is not the declared port. Before #47 this loaded exactly as well as the port did, which is
	# how a player found out that the arrow meant nothing.
	var sim: Simulation = _sim(_content())
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_belt(0, Vector3i(0, GROUND, 2), Vector3i(0, GROUND, 6)),
	])
	_run(sim, 120)
	assert_eq(sim.query_belt_item_count(0), 0, "a blank wall is not a port")
	assert_false(sim.query_belt_start_is_fed(0), "and the red post stands where it is refused")
	assert_true(
		sim.query_machine_output(0, "iron_ore") > 0,
		"the ore is in the Miner, not destroyed — nothing is lost, it simply cannot leave"
	)


func test_a_belt_running_the_wrong_way_out_of_a_port_is_not_connected_to_it() -> void:
	# The declared direction is part of the rule, not only the tile. A port on the south face
	# faces south, so a Belt out of it runs south; one laid along the wall through the same tile
	# runs east, and is a Belt that happens to pass the port rather than one docked against it.
	var sim: Simulation = _sim(_content())
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(5, GROUND, 2)),
	])
	_run(sim, 120)
	assert_eq(sim.query_belt_item_count(0), 0, "the tile is right and the direction is not")


# ── Handing off into a declared input port ────────────────────────────────────

func test_a_belt_into_the_declared_input_port_feeds_the_machine() -> void:
	# A Miner on the Node at the origin runs ore out of its declared port into a Belt down x = 1,
	# and a Smelter at (0, 6) is 3x3 and takes ore on the middle of its north face — tile (1, 6)
	# — so the Belt ends at (1, 5) running south, which is exactly that port's dock tile.
	var sim: Simulation = _sim(_content())
	sim.step([InputAction.build_machine(0, 1, Vector3i(0, GROUND, 6))])
	sim.step([InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 5))])
	_give_the_belt_an_item(sim)
	assert_true(
		_step_until(sim, 400, func() -> bool: return sim.query_machine_input(0, "iron_ore") > 0),
		"the declared port takes the hand-off"
	)
	assert_true(sim.query_belt_end_is_connected(0), "and the renderer agrees it is joined")


func test_a_belt_into_a_wall_that_declares_no_port_is_refused_and_backs_up() -> void:
	# The same Belt against the same face, one tile along it: the Smelter is a tile further west,
	# so (1, 6) is the third tile of its north face rather than the middle one, and the Belt now
	# ends against a blank wall. The Items stay on the Belt, which is what a refusal looks like
	# everywhere else in this Simulation — nothing is destroyed and the queue a player sees is
	# the state.
	var sim: Simulation = _sim(_content())
	sim.step([InputAction.build_machine(0, 1, Vector3i(-1, GROUND, 6))])
	sim.step([InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 5))])
	_give_the_belt_an_item(sim)
	_run(sim, 400)
	assert_eq(sim.query_machine_input(0, "iron_ore"), 0, "a blank wall takes nothing")
	assert_true(sim.query_belt_item_count(0) > 0, "and the Items are still on the Belt")
	assert_false(sim.query_belt_end_is_connected(0), "marked at the end that leads nowhere")


# ── Turning a Machine turns where its Belts may dock ──────────────────────────

func test_turning_a_machine_moves_the_tile_its_belt_must_dock_at() -> void:
	# A half turn puts the Miner's south face north: the port tile goes from (1, 1) to (0, 0) and
	# the dock from (1, 2) to (0, -1). Which is the whole of why a declaration has to be rotated
	# rather than remembered.
	var sim: Simulation = _sim(_content())
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0), 2),
		InputAction.build_belt(0, Vector3i(0, GROUND, -1), Vector3i(0, GROUND, -5)),
		InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 6)),
	])
	_run(sim, 120)
	assert_true(sim.query_belt_item_count(0) > 0, "the turned port loads the Belt now at it")
	assert_eq(sim.query_belt_item_count(1), 0, "and the tile it used to be at loads nothing")


# ── A set with no declaration is the loose rule, and that is the seam ─────────

func test_a_machine_no_table_mentions_still_takes_a_belt_anywhere_on_its_edge() -> void:
	# **A declaration that does not exist cannot be enforced**, which is what keeps every test
	# that brings its own Machines working and is the same shape as a Machine with no generated
	# body drawing a box. The *shipped* content cannot reach this: the loader refuses a set where
	# a Machine that needs a Belt declares no port.
	var sim: Simulation = _sim(_content(""))
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_belt(0, Vector3i(0, GROUND, 2), Vector3i(0, GROUND, 6)),
	])
	_run(sim, 120)
	assert_true(
		sim.query_belt_item_count(0) > 0,
		"with no table at all, any footprint edge tile loads — the rule before #47"
	)


# ── What the loader refuses, and what it only warns about ─────────────────────

func test_a_machine_that_needs_a_belt_and_declares_no_port_is_refused_by_name() -> void:
	# The check with teeth, and the reason the Turret could not be forgotten: after #47 a Machine
	# with no declared port is a Machine no Belt can reach, which is a Machine that cannot work.
	var content: Definitions = _content(
		"""machine_id,port_id,direction,edge,tile,height_mm
miner_mk1,ore,output,south,1,900
"""
	)
	assert_true(content.has_errors(), "a Smelter with no ports is not a loadable content set")
	assert_true(
		content.describe_errors().contains("smelter_mk1"),
		"and the error names the Machine, got %s" % content.describe_errors()
	)


func test_a_machine_that_declares_only_the_wrong_flow_is_refused_too() -> void:
	# A Smelter with an output port and no input port is one nothing could ever feed. Both
	# directions are checked, because a Machine is unreachable either way round.
	var content: Definitions = _content(
		"""machine_id,port_id,direction,edge,tile,height_mm
miner_mk1,ore,output,south,1,900
smelter_mk1,plate,output,south,1,900
"""
	)
	assert_true(content.has_errors(), "an unfeedable Smelter is refused")
	assert_true(
		content.describe_errors().contains("input port"),
		"naming what is missing, got %s" % content.describe_errors()
	)


func test_a_port_declared_for_a_machine_nothing_defines_is_kept_and_kept_quiet() -> void:
	# **The one place the tightening stops, and the reason is that the file has another reader.**
	# `machine_ports.csv` is shared with the mesh generator, which reads it for bodies
	# `machines.csv` has not caught up with — `press_mk1` is one — and for the Nest and a Belt's
	# own two ends, which are not Machines at all. So a row this side cannot use is not a row
	# nothing uses, and saying "nothing reads this" would be false. A genuine typo is refused by
	# `machine_specs.load`, which is the side that can see both files.
	var content: Definitions = _content(
		PORTS + "press_mk1,ingot,input,north,0,900\nnest,delivery,input,south,1,900\n"
	)
	assert_false(content.has_errors(), content.describe_errors())
	assert_false(
		content.describe_warnings().contains("press_mk1"),
		"a body awaiting a Recipe is not a complaint, got %s" % content.describe_warnings()
	)
	assert_false(
		content.describe_warnings().contains("nest"),
		"and the Nest is not a Machine and never was, got %s" % content.describe_warnings()
	)
	assert_true(
		content.machine_ports().ports_of("press_mk1").size() == 1,
		"the row is kept, so the generator still has its declaration"
	)


# ── The ports are in the digest now ───────────────────────────────────────────

func test_moving_a_port_changes_the_digest_because_it_changes_the_run() -> void:
	# Out of the digest until #47 and in it since, and the reason is exactly the change: while
	# the ports were drawn and nothing else, a client whose table differed drew different arrows
	# and simulated the same Run. A client whose table differs now carries goods across a
	# different wall.
	var here: Definitions = _content()
	var moved: Definitions = _content(PORTS.replace("miner_mk1,ore,output,south,1", "miner_mk1,ore,output,south,0"))
	assert_false(here.has_errors(), here.describe_errors())
	assert_false(moved.has_errors(), moved.describe_errors())
	assert_ne(here.digest(), moved.digest(), "a moved port is a different Run")


# ── Determinism ───────────────────────────────────────────────────────────────

func test_determinism_a_line_docked_against_its_declared_ports_replays_identically() -> void:
	var content: Definitions = _content()
	var script: InputScript = InputScript.new()
	script.add_tick([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_machine(0, 1, Vector3i(0, GROUND, 4)),
	])
	# One docked against the declared port and one against the blank wall beside it, so the
	# fixture carries both answers and a replay has to reproduce both.
	script.add_tick([
		InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 3)),
		InputAction.build_belt(0, Vector3i(0, GROUND, 2), Vector3i(0, GROUND, 3)),
	])
	script.add_idle_ticks(400)

	var recording: ReplayRecording = DeterminismHarness.record(script, 9, 1, content)
	var divergence: DeterminismHarness.Divergence = DeterminismHarness.verify(recording)
	assert_true(divergence.is_identical, divergence.describe())


func test_determinism_the_docking_fixture_really_did_dock_one_belt_and_refuse_the_other() -> void:
	# **The honesty check beside the fixture.** A replay of a Run in which both Belts carried
	# nothing reads as a passing determinism test, and the failure is silent. So the same script
	# is driven again and the two answers asserted apart.
	var sim: Simulation = _sim(_content())
	sim.step([
		InputAction.build_machine(0, 0, Vector3i(0, GROUND, 0)),
		InputAction.build_machine(0, 1, Vector3i(0, GROUND, 4)),
	])
	sim.step([
		InputAction.build_belt(0, Vector3i(1, GROUND, 2), Vector3i(1, GROUND, 3)),
		InputAction.build_belt(0, Vector3i(0, GROUND, 2), Vector3i(0, GROUND, 3)),
	])
	_run(sim, 400)
	assert_true(sim.query_belt_start_is_fed(0), "the docked Belt really is fed")
	assert_false(sim.query_belt_start_is_fed(1), "and the other really is not")
	assert_true(
		sim.query_machine_input(1, "iron_ore") > 0 or sim.query_machine_output(1, "iron_plate") > 0,
		"and the ore really reached the Smelter through the declared port"
	)



const WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,6,1200,40
"""

const GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""

const STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""

const DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_ore:1,,placeholder_gear,
"""
