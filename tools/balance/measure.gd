## Plays every balance scenario on every seed and prints the table.
##
##     tools/balance/measure.sh                       # every scenario, three seeds
##     tools/balance/measure.sh --seeds 7,11,29
##     tools/balance/measure.sh --scenario competent --verbose
##
## Prints a one-line row per Run and, with `--verbose`, the per-minute trace behind it. The
## table is the artefact: #26's whole complaint was that the recorded figures came from a
## schedule that no longer exists and nobody could re-derive them, so this is the thing that
## makes the next balance change checkable rather than arguable.
##
## Not a test and deliberately outside `tests/cases/` — it takes minutes of wall clock and
## reports rather than asserts. `tests/cases/test_balance.gd` is the part that fails the
## suite when the loop stops landing.
extends SceneTree

## Seeds the table is built on by default. Three, because one is an anecdote.
##
## They are also a demonstration rather than a sample, which is worth knowing before anybody
## quotes a variance off this table: the Map is handcrafted, the Wave schedule is a function
## of Heat, and the only consumer of the seeded RNG anywhere in the Simulation is
## `Simulation._scatter` — the spread on a ranged shot. Every row below is therefore the same
## on all three seeds, down to which Machines were lost in which order.
const DEFAULT_SEEDS: Array = [7, 11, 29]


func _initialize() -> void:
	var seeds: Array = DEFAULT_SEEDS
	var only: String = ""
	var verbose: bool = false
	var cap_minutes: int = 60

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var arg: String = args[index]
		if arg == "--verbose":
			verbose = true
		elif arg == "--scenario" and index + 1 < args.size():
			index += 1
			only = args[index]
		elif arg == "--seeds" and index + 1 < args.size():
			index += 1
			seeds = []
			for text: String in args[index].split(","):
				seeds.append(text.strip_edges().to_int())
		elif arg == "--cap-minutes" and index + 1 < args.size():
			index += 1
			cap_minutes = maxi(args[index].to_int(), 1)
		else:
			printerr("unrecognised argument: %s" % arg)
			quit(2)
			return
		index += 1

	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	if definitions.has_errors():
		printerr("content definitions failed to load:\n%s" % definitions.describe_errors())
		quit(1)
		return

	print("DEEP FOUNDRY — balance measurement")
	print("Map: starter (one Breach, two Hives). Content: content/ as shipped.")
	print(
		"Wave baseline %ds, floor %ds, a second sooner per %d Heat; decay %d/min less %d/min per Hive."
		% [
			Fixed.floor_to_int(definitions.heat_wave_interval_baseline_seconds),
			Fixed.floor_to_int(definitions.heat_wave_interval_minimum_seconds),
			definitions.heat_per_second_sooner,
			definitions.heat_decay_per_minute,
			definitions.hive_heat_shadow_per_minute,
		]
	)
	print("Cap: %d minutes of game time.\n" % cap_minutes)

	var rows: PackedStringArray = PackedStringArray()
	for scenario: BalanceScenario in BalanceScenarios.all():
		if only != "" and scenario.id != only:
			continue
		print("%s — %s" % [scenario.id, scenario.summary])
		for world_seed: int in seeds:
			var report: BalanceProbe.Report = BalanceProbe.play(
				scenario, world_seed, cap_minutes * 60 * Simulation.TICKS_PER_SECOND
			)
			rows.append(report.row())
			if verbose:
				print(report.describe())
			else:
				print("  " + report.row())
		print("")

	if rows.is_empty():
		printerr("no scenario matched %s" % only)
		quit(1)
		return

	print("── Table ────────────────────────────────────────────────────────────")
	for row: String in rows:
		print(row)
	quit(0)
