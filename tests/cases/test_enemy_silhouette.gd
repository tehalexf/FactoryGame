## Every Enemy kind must be identifiable from its outline alone, at the range a player
## triages a Wave from.
##
## **This is a gameplay gate and not a polish one**, and it is the argument
## `tools/assets/machine_silhouette.py` already makes about Machines, pointed at the things
## a player spends a Run shooting at. A player's correct answer to Chaff and to a Breaker are
## different: a Breaker preferentially eats Machines and is the threat, where Chaff is the
## *sense* of threat. #34 spent a whole ticket making a Breaker's approach legible — it
## marches the Nest's own lane under fire and turns on the Factory where a player can watch
## it — and #34 taught the Telegraph to name what is coming for the same reason. All of that
## is spent if the two cannot be told apart once they arrive.
##
## **It exists because a documented claim is what failed here.** #38 cast the characters onto
## the kinds and recorded that the glowing eyes would be the readability aid; the eyes render
## nothing, and nothing in the suite noticed, because the claim was a sentence. So it is a
## number now, and a later casting or content change that makes two kinds converge fails
## here rather than being discovered by somebody playing.
##
## The seam is `EnemyBodies.body_for(kind)` and `query_enemy_hit_height_metres` — the baked
## body a `MultiMesh` really draws, posed on a row of the pose texture the shader really
## samples, at the height the Simulation really says. Nothing here reads a rest pose or a
## constant, because none of those is what a player is looking at.
extends TestCase


## How far apart two kinds' outlines must be, as 1 - intersection over union of their
## occupancy grids in the better of two views, at the worst pose either is caught in.
##
## **Where the number comes from, measured rather than chosen.** On the casting #38 shipped,
## the Crawler and the Breaker sat at **0.42**, against 0.83 and 0.79 for either of them
## against the Siege Hulk — the Minion and the Warrior were the same KayKit rig at the same
## declared 1.6 m, so they had the same arm span, the same shoulders and the same head, and
## what separated them was armour that is gone by about twelve metres. #49 gave the Breaker
## its own 2.2 m and the three pairs measured **0.58, 0.83 and 0.67**.
##
## 0.50 is below the closest of those with room to tune a kind, and well above the 0.42 this
## gate was written to reject — so it fails the geometry it was written against and passes
## the geometry that replaced it, which is the only way a threshold means anything.
##
## **#79 replaced the cast with three generated insects and this gate is why it could be
## trusted to.** Three bugs are far more alike than a skeleton, a knight and a golem, so the
## declaration separates them by gross form on purpose — leg count, how high the body is
## slung, and where the mass sits — rather than by detail that distance takes first. The
## measured figures are in CLAUDE.md; what matters here is that the threshold did not move
## for the new bodies, because a gate rewritten to admit what it was measuring is not a gate.
const MINIMUM_SEPARATION: float = 0.50

## How many poses of each kind's walk are measured. A silhouette is a moving thing, so one
## frame is a claim about one instant: the separation reported is the **worst** over every
## pose of one kind against every pose of the other, which is the frame a player could
## actually catch them in. Three is the cheapest number that samples a stride at its
## extremes and in the middle.
const POSES: int = 3

const KINDS: Array = [
	Simulation.ENEMY_KIND_CRAWLER,
	Simulation.ENEMY_KIND_BREAKER,
	Simulation.ENEMY_KIND_SIEGE_HULK,
]


func test_every_pair_of_enemy_kinds_casts_a_different_shadow() -> void:
	# The acceptance criterion, as a number. A failure names the pair, and the fix is to
	# change one of their gross forms — height, bulk, proportion, what it carries — rather
	# than to brighten one or to add detail to either. Emission is specifically not the
	# answer: #38 tried it and the glow geometry on these skulls renders nothing.
	var outlines: Dictionary = _outlines()
	if outlines.is_empty():
		assert_true(false, "no Enemy kind baked a body; the gate measured nothing")
		return
	var measured: int = 0
	for left: int in range(KINDS.size()):
		for right: int in range(left + 1, KINDS.size()):
			var a: int = KINDS[left]
			var b: int = KINDS[right]
			if not (outlines.has(a) and outlines.has(b)):
				continue
			measured += 1
			var apart: float = _separation(outlines[a], outlines[b])
			assert_true(
				apart >= MINIMUM_SEPARATION,
				(
					"%s and %s are the same shape to within %.2f; they will not be told "
					+ "apart across a Wave. Vary the gross form, not the detailing."
				) % [EnemyKind.KIND_NAMES[a], EnemyKind.KIND_NAMES[b], apart]
			)
	assert_eq(measured, 3, "all three pairs were measured")


func test_the_gate_covers_every_kind_the_waves_can_send() -> void:
	# A gate is worthless if it quietly stops covering a kind. The set it measured must be
	# the set `EnemyKind` declares — so adding a fourth kind with a character cast onto it
	# fails here until it is measured against the three that exist.
	var outlines: Dictionary = _outlines()
	var cast: Array = []
	for kind: int in range(EnemyKind.KIND_NAMES.size()):
		if EnemyBodies.recipe_for(kind) != null:
			cast.append(kind)
	cast.sort()
	var measured: Array = outlines.keys()
	measured.sort()
	assert_eq(
		measured,
		cast,
		"every kind with a character cast onto it is measured by this gate"
	)


func test_a_crawler_and_a_breaker_are_told_apart_by_being_different_sizes() -> void:
	# The *mechanism*, asserted separately from the threshold, because the threshold alone
	# would pass if somebody got the separation back by some other means and this file's
	# reasoning would then be a lie. A Breaker is the threat and it is bigger; the Simulation
	# is the one authority on how big, through the capsule a round is resolved against, so
	# the renderer scales by `query_enemy_hit_height_metres` and holds no second opinion.
	var sim: Simulation = _a_wave_of_every_kind()
	var heights: Dictionary = _heights(sim)
	assert_true(
		heights.has(Simulation.ENEMY_KIND_CRAWLER)
		and heights.has(Simulation.ENEMY_KIND_BREAKER),
		"the premise: a Crawler and a Breaker are both on the Map"
	)
	var crawler: float = heights[Simulation.ENEMY_KIND_CRAWLER]
	var breaker: float = heights[Simulation.ENEMY_KIND_BREAKER]
	assert_true(
		breaker > crawler * 1.25,
		(
			"a Breaker stands at least a quarter taller than a Crawler, so it reads as "
			+ "bigger at any range: %.2f m against %.2f m"
		) % [breaker, crawler]
	)
	assert_true(
		breaker < heights[Simulation.ENEMY_KIND_SIEGE_HULK],
		"and still visibly short of the boss, which is the top of the scale"
	)


## Every cast kind's outline, in both views, over `POSES` frames of its walk.
##
## Cached across the methods that read it, the way `test_balance.gd` caches a played Run and
## for the same reason: this skins about five thousand vertices and rasterises about six
## thousand triangles eighteen times over, which is worth paying once.
static var _cached_outlines: Dictionary = {}


func _outlines() -> Dictionary:
	if not _cached_outlines.is_empty():
		return _cached_outlines
	_cached_outlines = _measure_outlines()
	return _cached_outlines


func _measure_outlines() -> Dictionary:
	var sim: Simulation = _a_wave_of_every_kind()
	var heights: Dictionary = _heights(sim)
	var bodies: EnemyBodies = EnemyBodies.new()
	var out: Dictionary = {}
	for kind: int in KINDS:
		var body: EnemyBodies.Body = bodies.body_for(kind)
		if body == null or not heights.has(kind):
			continue
		var frames: int = body.frames_of(EnemyAnimator.MOVE)
		var poses: Array = []
		for pose: int in range(POSES):
			var row: int = body.row_of(EnemyAnimator.MOVE, pose * frames / POSES)
			poses.append({
				EnemyBodies.VIEW_FRONT:
					body.silhouette(row, heights[kind], EnemyBodies.VIEW_FRONT),
				EnemyBodies.VIEW_SIDE:
					body.silhouette(row, heights[kind], EnemyBodies.VIEW_SIDE),
			})
		out[kind] = poses
	return out


## The worst a pair gets: the closest any pose of one comes to any pose of the other.
func _separation(left: Array, right: Array) -> float:
	var worst: float = 1.0
	for a: Dictionary in left:
		for b: Dictionary in right:
			worst = minf(worst, EnemyBodies.separation(a, b))
	return worst


## How tall the Simulation says each kind on the Map is, in metres — the number the renderer
## scales each body by, read through the façade rather than off the tuning file.
func _heights(sim: Simulation) -> Dictionary:
	var out: Dictionary = {}
	for index: int in range(sim.query_enemy_count()):
		out[sim.query_enemy_kind(index)] = Fixed.to_float(
			sim.query_enemy_hit_height_metres(index)
		)
	return out


## A Wave carrying one of every kind at once, on the shipped Map and the shipped tuning, so
## the heights measured are the heights a Run draws. The Wave table is replaced because the
## shipped one gates the Breaker at 5200 Heat and the boss at 6400, which is twenty-odd
## minutes of Factory this test has no reason to play.
func _a_wave_of_every_kind() -> Simulation:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff_crawlers,crawler,0,1,0,1\n"
		+ "shock_breakers,breaker,0,1,0,1\n"
		+ "siege_hulks,siege_hulk,0,1,0,1\n"
	)
	var definitions: Definitions = (
		fixture.tune([["telegraph_seconds = 12", "telegraph_seconds = 0.5"]]).definitions()
	)
	assert_false(definitions.has_errors(), definitions.describe_errors())
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(4 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	return sim


## The measurement's own contract. A gate that cannot fail is not a gate, so these are
## asserted against hand-built grids rather than against meshes — the shape
## `test_machine_silhouettes.py`'s `TheMeasurementItself` has.
func _grid(filled: Array) -> PackedByteArray:
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(EnemyBodies.SILHOUETTE_CELLS * EnemyBodies.SILHOUETTE_CELLS)
	grid.fill(0)
	for cell: int in filled:
		grid[cell] = 1
	return grid


func test_the_measure_calls_an_outline_identical_to_itself_zero_apart() -> void:
	var shape: PackedByteArray = _grid(range(40))
	assert_eq(EnemyBodies.jaccard_distance(shape, shape), 0.0)


func test_the_measure_calls_two_outlines_sharing_no_cell_one_apart() -> void:
	assert_eq(
		EnemyBodies.jaccard_distance(_grid(range(0, 10)), _grid(range(10, 20))), 1.0
	)


func test_the_measure_scores_half_overlap_at_a_third() -> void:
	# Two ten-cell shapes sharing five cells intersect in 5 and unite in 15, so the distance
	# is 1 - 5/15. A worked example, not a recomputation of what the code does.
	assert_true(
		absf(
			EnemyBodies.jaccard_distance(_grid(range(0, 10)), _grid(range(5, 15)))
			- 2.0 / 3.0
		) < 0.000001
	)


func test_the_measure_reports_the_view_that_tells_two_kinds_apart() -> void:
	# A player moves around a Wave. Two kinds identical head-on but obviously different in
	# profile are still tellable apart, so the separation is the best view's.
	var same: PackedByteArray = _grid(range(0, 10))
	var other: PackedByteArray = _grid(range(10, 20))
	assert_eq(
		EnemyBodies.separation(
			{EnemyBodies.VIEW_FRONT: same, EnemyBodies.VIEW_SIDE: same},
			{EnemyBodies.VIEW_FRONT: same, EnemyBodies.VIEW_SIDE: other}
		),
		1.0
	)


func test_a_silhouette_stands_on_the_ground_and_fills_a_plausible_share_of_its_frame() -> void:
	# An outline that is nearly empty, or that fills its whole frame, is a measurement that
	# went wrong in a way the separation figures cannot show — two such grids would score
	# far apart while meaning nothing.
	var outlines: Dictionary = _outlines()
	var cells: int = EnemyBodies.SILHOUETTE_CELLS * EnemyBodies.SILHOUETTE_CELLS
	var checked: int = 0
	for kind: int in outlines:
		for pose: Dictionary in outlines[kind]:
			for view: int in pose:
				var grid: PackedByteArray = pose[view]
				var filled: int = 0
				for cell: int in range(grid.size()):
					filled += grid[cell]
				checked += 1
				assert_true(
					filled > 20,
					"%s drew almost nothing: %d cells" % [
						EnemyKind.KIND_NAMES[kind], filled
					]
				)
				assert_true(
					filled < cells / 2,
					"%s fills its whole frame: %d of %d cells" % [
						EnemyKind.KIND_NAMES[kind], filled, cells
					]
				)
				# Near the ground rather than *on* it: a run cycle has an airborne phase,
				# so insisting on row 0 would be insisting a Crawler never leaves the
				# floor. What this catches is a body that floats or sinks — a pose
				# composed against the wrong rest, which is the failure
				# `drawn_extent_metres` guards from the other side.
				var lowest: int = EnemyBodies.SILHOUETTE_CELLS
				for cell: int in range(grid.size()):
					if grid[cell] != 0:
						lowest = cell / EnemyBodies.SILHOUETTE_CELLS
						break
				assert_true(
					lowest < EnemyBodies.SILHOUETTE_CELLS / 4,
					"%s stands near the ground rather than floating: lowest row %d" % [
						EnemyKind.KIND_NAMES[kind], lowest
					]
				)
	assert_true(checked > 0, "something was measured")
