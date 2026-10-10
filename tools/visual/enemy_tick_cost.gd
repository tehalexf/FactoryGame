## What one Simulation tick costs with a crowd on the Map.
##
##   ENEMY_COUNT=1000 godot --headless --path . --script res://tools/visual/enemy_tick_cost.gd
##
## **`frame_cost.gd`'s sibling, and the difference is which half of a frame it measures.** That
## one times `WorldView.sync` — the renderer, the queries and the buffers it rebuilds — and is
## the right instrument for anything about drawing. This times `Simulation.step`, which is the
## half #76's separation pass lives in and the half `frame_cost.gd` cannot see.
##
## **It is built so a crowd can actually reach the Chaff tier's numbers**, which is the whole
## reason it is not a flag on the other tool. `frame_cost.gd` stands up a full Factory, so its
## Turrets kill Enemies as fast as the Breaches release them and `ENEMY_COUNT=600` plateaus at
## about seventy on the Map. Here there is **no Factory at all, so nothing kills anything**, a
## Nest with enough hit points that the Run cannot end under the Wave, and eight Breaches so a
## Wave is released in parallel rather than in single file.
##
## The figure to read is the mean. Compare two builds rather than quoting one: an absolute
## number off a contended developer machine is worth very little, and a delta measured back to
## back is worth a lot.
extends SceneTree

const WARMUP: int = 60
const SAMPLES: int = 400
const BREACHES: int = 8


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _content(count: int) -> Definitions:
	@warning_ignore("integer_division")
	var each: int = maxi(count / BREACHES / 3, 1)
	var waves: String = (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff_crawlers,crawler,0,%d,0,%d\n" % [each * 2, each * 2]
		+ "shock_breakers,breaker,0,%d,0,%d\n" % [each, each]
	)
	var tuning: String = (
		_read("res://content/tuning.toml")
		.replace("telegraph_seconds = 12", "telegraph_seconds = 0.5")
		.replace("spawn_interval_seconds = 0.5", "spawn_interval_seconds = 0.01")
		.replace("health = 6000", "health = 1000000000")
	)
	return Definitions.parse(
		_read("res://content/machines.csv"), _read("res://content/recipes.csv"), tuning,
		waves, _read("res://content/deliveries.csv"), _read("res://content/gear.csv"),
		_read("res://content/stratagems.csv"),
		"machines.csv", "recipes.csv", "tuning.toml", "waves.csv",
		"deliveries.csv", "gear.csv", "stratagems.csv"
	)


## A Nest at the origin and a row of Breaches well out, so a Wave walks a long way through a
## crowd of its own kind before it reaches anything.
func _layout() -> MapLayout:
	var layout: MapLayout = MapLayout.new()
	layout.nest_tile = Vector3i(0, WorldGrid.GROUND_LAYER, 0)
	for i: int in range(BREACHES):
		layout.add_breach(Vector3i(40, WorldGrid.GROUND_LAYER, i * 3 - 10))
	layout.sort_breaches()
	return layout


func _initialize() -> void:
	var asked: int = maxi(int(OS.get_environment("ENEMY_COUNT")), 20)
	var content: Definitions = _content(asked)
	if content.has_errors():
		push_error(content.describe_errors())
		quit()
		return
	var sim: Simulation = Simulation.new(1, 1, content, _layout())
	sim.step([InputAction.call_wave_early(0)])
	for tick: int in range(30000):
		sim.step([])
		if sim.query_enemy_count() >= asked:
			break

	var on_map: int = sim.query_enemy_count()
	for warm: int in range(WARMUP):
		sim.step([])

	var worst: int = 0
	var total: int = 0
	for sample: int in range(SAMPLES):
		var began: int = Time.get_ticks_usec()
		sim.step([])
		var took: int = Time.get_ticks_usec() - began
		total += took
		worst = maxi(worst, took)
	print("SEP=%s enemies=%d step mean %.3f ms worst %.3f ms" % [
		"off" if OS.get_environment("NO_SEPARATION") != "" else "on",
		on_map, float(total) / float(SAMPLES) / 1000.0, float(worst) / 1000.0
	])
	quit()
