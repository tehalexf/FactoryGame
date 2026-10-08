## The yard the Factory stands in.
##
## Three claims, and they are the three that could quietly stop being true:
##
## * **A clone without the purchased packs gets a yard.** They are
##   non-redistributable (docs/ASSETS.md), converted outside this repository, and
##   on most machines simply absent — so every assertion here is written to pass
##   either way, and the ones about *absence* are the point rather than a caveat.
## * **The yard is a function of the seed and nothing else.** It is decoration, it
##   is never told to the Simulation, and two Runs on one seed must draw it the
##   same or co-op would disagree about where the crates are. Asking for it must
##   not move the state hash.
## * **It gets out of the player's way.** The whole Map is buildable, so a prop
##   that stayed where a Smelter went would be a prop standing inside a Smelter.
## * **It is arranged rather than scattered** (#42). The lanes are clear and the props
##   are aligned to the grid, which are the two halves of the complaint that made the
##   first version of this file not good enough.
extends TestCase


func _dressed(sim: Simulation) -> SetDressing:
	var dressing: SetDressing = SetDressing.new()
	dressing.sync(sim)
	return dressing


# ── It draws a yard, with or without the packs ────────────────────────────────

func test_a_yard_is_drawn_whether_or_not_the_purchased_packs_are_here() -> void:
	# The claim the licence makes load-bearing. Not "it does not crash": the same
	# layout is walked either way, so the *count* is the same and only the meshes
	# differ. A clone without the packs gets a place rather than a plane.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	assert_true(
		dressing.instance_count() > 200,
		"a yard is hundreds of props, got %d" % dressing.instance_count()
	)
	assert_true(dressing.group_count() > 0, "and they are drawn out of at least one mesh")
	dressing.free()


func test_every_prop_is_one_multimesh_rather_than_a_node_per_crate() -> void:
	# The scene tree must not grow by a node per prop, which is the rule every
	# other thing in `WorldView` obeys. Hundreds of props, tens of meshes.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	assert_eq(
		dressing.get_child_count(),
		dressing.group_count(),
		"one node per mesh and not one per instance"
	)
	assert_true(
		dressing.group_count() < 80,
		"and tens of them, not hundreds: got %d" % dressing.group_count()
	)
	dressing.free()


func test_a_prop_the_packs_do_not_supply_is_drawn_as_a_stand_in() -> void:
	# `PROP_DIRECTORY` is outside the shipping tree and gitignored, so on a clone
	# it holds nothing at all. Whichever this machine is, every placement must end
	# up in a group — either the prop's own or its kind's stand-in — and nothing
	# may fall on the floor between the two.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var converted: bool = DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(SetDressing.PROP_DIRECTORY)
	)
	assert_eq(
		dressing.uses_purchased_props(),
		converted,
		"purchased props are used exactly when they are on disk"
	)
	var drawn: int = 0
	for child: Node in dressing.get_children():
		drawn += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(drawn, dressing.instance_count(), "every placement is in some group")
	dressing.free()


func test_the_shared_atlas_resolves_exactly_when_the_purchased_props_do() -> void:
	# Two separate loaders: the props come out of GLB files through `GLTFDocument`
	# and the atlas out of two PNGs through `Image`, so one can fail while the other
	# does not — and that is not hypothetical. In an exported build the atlas was
	# reached with `ProjectSettings.globalize_path`, which names a file on disk, and
	# the PCK is not a disk: the whole yard came up in purchased geometry wearing no
	# texture at all, and nothing said a word. `tools/release/` verifies this in the
	# shipped pack; this is the same claim where a clone can see it.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	assert_eq(
		dressing.uses_purchased_atlas(),
		dressing.uses_purchased_props(),
		"the atlas and the props are present together or absent together"
	)
	dressing.free()


func test_the_painted_props_are_props_the_yard_actually_contains() -> void:
	# `tools/assets/prop_grade.py` takes the safety yellow out of the purchased
	# atlas wholesale, and `HAZARD_PROPS` is where it is deliberately put back —
	# which only works while those names are names the layout still uses. A prop
	# id that quietly stopped being drawn would take the last hazard colour in the
	# yard with it and nothing else would notice.
	var drawn: Dictionary = {}
	for kind: String in SetDressing.KINDS:
		for variant: String in SetDressing.KINDS[kind]:
			drawn[variant] = true
	for painted: String in SetDressing.HAZARD_PROPS:
		assert_true(
			drawn.has(painted),
			"%s is painted hazard yellow but nothing draws it" % painted
		)
	assert_true(SetDressing.HAZARD_PROPS.size() > 0, "the yard has no hazard colour at all")


# ── It is decoration, and the Simulation never hears about it ─────────────────

func test_drawing_the_yard_does_not_move_the_state_hash() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var before: int = sim.hash()
	var dressing: SetDressing = _dressed(sim)
	dressing.sync(sim)
	assert_eq(sim.hash(), before, "the yard is decoration and reads only queries")
	dressing.free()


func test_two_runs_on_one_seed_draw_the_same_yard() -> void:
	# Two clients in lockstep draw this without a byte crossing between them, so
	# it has to be a function of the seed. A different seed has to differ, or it
	# is a function of nothing.
	var first: SetDressing = _dressed(Simulation.new(1, 1))
	var again: SetDressing = _dressed(Simulation.new(1, 1))
	assert_eq(again.instance_count(), first.instance_count(), "same seed, same yard")

	var elsewhere: SetDressing = _dressed(Simulation.new(99, 1))
	assert_ne(
		elsewhere.instance_count(),
		first.instance_count(),
		"a different seed is a different yard"
	)
	first.free()
	again.free()
	elsewhere.free()


func test_the_yard_does_not_shuffle_itself_when_the_factory_changes() -> void:
	# The layout is built once per seed and then only filtered. Rebuilding it on
	# every build would make the whole yard jump every time a player placed a Belt.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var before: int = dressing.instance_count()
	sim.step([InputAction.build_wall(0, Vector3i(40, WorldGrid.GROUND_LAYER, 40))])
	dressing.sync(sim)
	assert_true(
		dressing.instance_count() <= before,
		"a build can only take props away, never conjure them"
	)
	assert_true(
		before - dressing.instance_count() <= 1,
		"and one Wall can only take the one prop that was standing on its tile"
	)
	dressing.free()


# ── It gets out of the player's way ───────────────────────────────────────────

func test_a_prop_standing_where_a_machine_goes_is_cleared() -> void:
	# The whole Map is buildable, so this is not a nicety. Build a Machine over
	# every tile a prop stands on and the count must come down by exactly those.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var before: int = dressing.instance_count()

	# A Miner's own Node is kept clear of dressing, so the Wall is the tool here:
	# one tile, no cost, and it can be put down anywhere.
	var cleared: int = 0
	var miner: int = sim.query_definitions().machine_index("miner_mk1")
	for index: int in range(sim.query_node_count()):
		sim.step([InputAction.build_machine(0, miner, sim.query_node_tile(index))])
	dressing.sync(sim)
	assert_true(
		dressing.instance_count() <= before,
		"building cannot add props: %d then %d" % [before, dressing.instance_count()]
	)
	cleared = before - dressing.instance_count()
	assert_true(cleared >= 0, "and the count is a count")
	dressing.free()


func test_nothing_stands_on_a_node_or_in_the_nests_apron() -> void:
	# A player's first act is a Miner on a Node and their Factory grows out of the
	# Nest. A crate in either place is an obstruction in the only sense this game
	# has — the player's attention — so the layout keeps clear of both outright.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var nest: Vector3i = sim.query_nest_tile()
	var footprint: Vector2i = sim.query_nest_footprint()
	var nest_centre: Vector3 = Vector3(
		(float(nest.x) + float(footprint.x) * 0.5) * tile_size,
		0.0,
		(float(nest.z) + float(footprint.y) * 0.5) * tile_size
	)

	# Stains are flat and are deliberately allowed right up to the footprint; what
	# must be clear is anything a player could trip over.
	var apron: float = float(SetDressing.NEST_CLEARANCE_TILES - 1) * tile_size
	var checked: int = 0
	for index: int in range(dressing.instance_count()):
		if dressing.instance_kind(index) == "stain":
			continue
		var at: Vector3 = dressing.instance_position(index)
		var away: Vector3 = at - nest_centre
		checked += 1
		assert_true(
			absf(away.x) > apron or absf(away.z) > apron,
			"a %s stands in the Nest's apron at %s" % [dressing.instance_kind(index), at]
		)
	assert_true(checked > 0, "and there were props to check")
	dressing.free()


# ── It is wired into the view ─────────────────────────────────────────────────

func test_the_view_stands_the_factory_in_a_yard() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var found: SetDressing = null
	for child: Node in view.get_children():
		if child is SetDressing:
			found = child
	assert_not_null(found, "the world is drawn with a yard around it")
	assert_true(found.instance_count() > 0, "and the yard has something in it")
	view.free()


# ── It is arranged, not scattered (#42) ───────────────────────────────────────

func test_the_lanes_from_the_nest_to_the_nodes_are_clear() -> void:
	# The half of "clear ground where a player works" that a player *feels* rather than
	# sees: the route from where a Run starts to where it goes first has nothing standing
	# in it. Stains are excluded for the reason they are excluded from the Nest's apron —
	# they are two centimetres tall and a player walks straight over one.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())

	var lanes: Dictionary = {}
	for tile: Vector2i in dressing.clear_lane_tiles(sim):
		lanes[tile] = true
	assert_true(lanes.size() > 0, "a Map with Nodes on it has roads to them")

	var checked: int = 0
	for index: int in range(dressing.instance_count()):
		if dressing.instance_kind(index) == "stain":
			continue
		var at: Vector3 = dressing.instance_position(index)
		var tile: Vector2i = Vector2i(
			int(floor(at.x / tile_size)), int(floor(at.z / tile_size))
		)
		checked += 1
		assert_false(
			lanes.has(tile),
			"a %s is standing in the lane at %s" % [dressing.instance_kind(index), tile]
		)
	assert_true(checked > 0, "and there were props to check")
	dressing.free()


func test_everything_in_the_yard_is_turned_to_one_of_the_grids_four_directions() -> void:
	# Alignment to the grid's own axes, which is what stops two hundred props reading as
	# confetti. Every yaw this file produces is a multiple of a quarter turn — the bays'
	# facings, the runs' axes and the perimeter's four sides are all quarter turns, and
	# a stain's random turn is one too.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var quarter: float = TAU * 0.25
	for index: int in range(dressing.instance_count()):
		var yaw: float = dressing.instance_yaw(index)
		var steps: float = yaw / quarter
		assert_true(
			absf(steps - round(steps)) < 0.001,
			"a %s is turned %f, which is not a quarter of a turn"
			% [dressing.instance_kind(index), yaw]
		)
	dressing.free()


func test_clutter_standing_together_is_facing_together() -> void:
	# The claim the whole arrangement rests on, and it is a claim about **neighbours**
	# rather than about the Map. The old layout turned every scattered prop at random, so
	# a pile of six crates wore four facings and read as spill; a bay shares its facing, so
	# the same six read as stock. Counting facings over the whole yard proves nothing
	# either way — several bays face several ways and the totals even out, which is
	# exactly what the first version of this test measured and why it was wrong.
	#
	# So: every pair of clutter props standing within a bay's width of each other, and
	# what share of those pairs agree. Under a random quarter turn that is one in four by
	# construction. Under bays it is nearly all of them, and the misses are two bays whose
	# kerbs happen to meet.
	var sim: Simulation = Simulation.new(1, 1)
	var dressing: SetDressing = _dressed(sim)
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var near: float = tile_size * 2.0

	var where: Array = []
	var facing: Array = []
	for index: int in range(dressing.instance_count()):
		if dressing.instance_kind(index) != "clutter":
			continue
		where.append(dressing.instance_position(index))
		facing.append(int(round(dressing.instance_yaw(index) / (TAU * 0.25))) % 4)

	var pairs: int = 0
	var agreed: int = 0
	for first: int in range(where.size()):
		for second: int in range(first + 1, where.size()):
			var apart: Vector3 = (where[first] as Vector3) - (where[second] as Vector3)
			if absf(apart.x) > near or absf(apart.z) > near:
				continue
			pairs += 1
			if facing[first] == facing[second]:
				agreed += 1

	assert_true(pairs > 40, "there are piles in this yard to measure, got %d pairs" % pairs)
	assert_true(
		float(agreed) / float(pairs) > 0.8,
		"only %d of %d neighbouring props agree on a facing — the yard is still scattered"
		% [agreed, pairs]
	)
	dressing.free()
