## Throwaway: prints the numbers #79's report has to quote. Deleted before the branch lands.
extends TestCase

const POSES: int = 3
const KINDS: Array = [
	Simulation.ENEMY_KIND_CRAWLER,
	Simulation.ENEMY_KIND_BREAKER,
	Simulation.ENEMY_KIND_SIEGE_HULK,
]


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
	var sim: Simulation = Simulation.new(1, 1, definitions)
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(4 * Simulation.TICKS_PER_SECOND):
		sim.step([])
	return sim


func test_zz_report_the_numbers() -> void:
	var sim: Simulation = _a_wave_of_every_kind()
	var heights: Dictionary = {}
	for index: int in range(sim.query_enemy_count()):
		heights[sim.query_enemy_kind(index)] = Fixed.to_float(
			sim.query_enemy_hit_height_metres(index)
		)
	var bodies: EnemyBodies = EnemyBodies.new()
	var outlines: Dictionary = {}
	for kind: int in KINDS:
		var body: EnemyBodies.Body = bodies.body_for(kind)
		if body == null or not heights.has(kind):
			continue
		print(
			"REPORT body kind=%d bones=%d rows=%d vent=%v height=%.2f surfaces=%d"
			% [
				kind, body.bone_count, body.frame_total, body.vent_offset,
				heights[kind], body.mesh.get_surface_count(),
			]
		)
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
		outlines[kind] = poses

	for left: int in range(KINDS.size()):
		for right: int in range(left + 1, KINDS.size()):
			var a: int = KINDS[left]
			var b: int = KINDS[right]
			if not (outlines.has(a) and outlines.has(b)):
				continue
			var worst: float = 1.0
			for one: Dictionary in outlines[a]:
				for two: Dictionary in outlines[b]:
					worst = minf(worst, EnemyBodies.separation(one, two))
			print(
				"REPORT separation %s vs %s = %.3f"
				% [EnemyKind.KIND_NAMES[a], EnemyKind.KIND_NAMES[b], worst]
			)

	var view: WorldView = WorldView.new()
	view.sync(sim)
	for kind: int in KINDS:
		var names: Array = []
		for surface: int in range(view.enemy_surface_count(kind)):
			names.append(view.enemy_surface_name(kind, surface))
		print(
			"REPORT surface kind=%d metallic=%.2f roughness=%.2f names=%s"
			% [
				kind, view.enemy_surface_metallic(kind),
				view.enemy_surface_roughness(kind), str(names),
			]
		)
	view.free()
	assert_true(true, "a report, not a gate")
