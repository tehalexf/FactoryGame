## Plays a `BalanceScenario` to the end of its Run and reports what happened.
##
## The instrument #26 is for. Every figure anybody quotes about how long a Run lasts comes
## out of here, so the next balance change is *checked* rather than argued about: change a
## number in `content/`, run `tools/balance/measure.sh`, read the table.
##
## It reads the Simulation only through `query_*`, exactly as a test does, and it issues
## nothing but Input Actions — so a measurement is a session the game could have had, and a
## scenario that scores well here is one a player could actually play.
##
## **What it is not**: it is not a judge. It records facts — the tick the Nest fell, which
## Wave was on the Map, how long the Turrets stood empty, which Machines went missing — and
## derives a cause from them with the thresholds spelled out in `Report.cause`. A reader who
## disagrees with the label still has the facts it was derived from.
class_name BalanceProbe
extends RefCounted

## Where a Run is cut off if the Nest has not fallen. An hour of game time: well past the
## 20-40 minutes the spec asks a competent Factory for, so a Run that reaches it is a
## finding ("nothing in this scenario can lose") rather than a timeout.
const DEFAULT_TICK_CAP: int = 60 * 60 * Simulation.TICKS_PER_SECOND

## How much of the end of a Run the dryness verdict looks at. Two minutes, because a Turret
## that was empty for the last two minutes lost to Ammunition whatever else was also true.
const ENDGAME_SECONDS: int = 120

## The share of the endgame the **whole Factory** has to have spent holding no Ammunition for
## "ran dry" to be the cause. Two fifths: enough that an ordinary gap between a craft and a
## Belt arriving cannot reach it, low enough that a Factory keeping up for half the time is
## still losing the arithmetic.
##
## Measured on the Factory rather than on the Turrets, and that is not a detail: a Turret that
## has been *destroyed* holds no rounds and has no ticks, so a per-Turret ratio reports 0% for
## the Run where the Breakers ate the Turret after the Ammunition ran out — which is the most
## common way a Run actually ends. "The Factory had nothing to shoot with" survives losing the
## thing that was shooting.
const DRY_ENDGAME_PERCENT: int = 40

## The share of the Run the one Power grid has to have spent short before the brown-out is
## called out. Half, for the same reason: a grid that was briefly over-committed while a
## Boiler relit is an ordinary Factory, and one that was short for most of a Run is a Factory
## that was never really running.
const POWER_DEFICIT_PERCENT: int = 50


## One sample of the Run, taken once a game minute. What makes a report a story rather than
## an epitaph: it is the trace that says whether the Factory was overwhelmed all along or
## fell off a cliff at minute 23.
class Sample extends RefCounted:
	var minute: int = 0
	var wave: int = 0
	var heat: int = 0
	var wave_interval_seconds: int = 0
	var enemies_alive: int = 0
	var nest_health: int = 0
	var ammunition_in_the_factory: int = 0
	var turret_count: int = 0
	var machine_count: int = 0

	func describe() -> String:
		return (
			"  %3d min  wave %-3d heat %-6d gap %3ds  enemies %-4d nest %-5d ammo %-5d"
			% [
				minute, wave, heat, wave_interval_seconds, enemies_alive, nest_health,
				ammunition_in_the_factory,
			]
		)


## Everything one measured Run is known to have done.
class Report extends RefCounted:
	var scenario_id: String = ""
	var summary: String = ""
	var world_seed: int = 0

	## The tick the Run ended on, whether by the Nest falling or by the cap.
	var end_tick: int = 0
	## True when the Nest fell. False means the cap was reached with the Nest standing.
	var nest_fell: bool = false
	var wave_number: int = 0
	var nest_health: int = 0
	var nest_max_health: int = 0

	var heat: int = 0
	## The most Heat the Factory ever carried. The figure the Wave tiers in `content/waves.csv`
	## have to be set against: a tier whose `min_heat` is above this never arrives at all.
	var most_heat_at_once: int = 0
	var heat_per_minute: int = 0
	var heat_decay_per_minute: int = 0
	var wave_interval_seconds: int = 0
	var ticks_at_the_interval_floor: int = 0

	var breach_count: int = 0
	var hives_standing: int = 0
	var depth_reached: int = 0

	var enemies_alive: int = 0
	var crawlers_alive: int = 0
	var breakers_alive: int = 0
	var siege_hulks_alive: int = 0
	var most_enemies_at_once: int = 0
	## Whether a Siege Hulk was ever on the Map, which is the Heat tier that changes a Run's
	## character rather than its difficulty.
	var a_siege_hulk_arrived: bool = false
	var a_breaker_arrived: bool = false

	var machines_built: int = 0
	var machines_standing: int = 0
	## Machine ids that vanished without the scenario demolishing them, in the order they
	## were lost. The answer to "what did it feel like to lose".
	var machines_lost: PackedStringArray = PackedStringArray()

	var turrets_built: int = 0
	var shots_fired: int = 0
	## Turret-ticks spent holding nothing, over the whole Run. Reported beside the dryness
	## verdict rather than being it — see `DRY_ENDGAME_PERCENT`.
	var dry_turret_ticks: int = 0
	## Ticks of the last `ENDGAME_SECONDS` in which there was no Ammunition anywhere in the
	## Factory, and how many ticks that endgame was.
	var starved_ticks_in_the_endgame: int = 0
	var endgame_ticks: int = 0

	var ammunition_in_the_factory: int = 0
	var most_ammunition_at_once: int = 0
	var iron_plate_in_the_factory: int = 0

	## The Silo, measured: how many stood, the deepest the stockpile ever got, and what was
	## actually called in.
	##
	## **#26 could not measure any of this**, and said so as a finding rather than an omission:
	## the opening Factory draws 660 kW of the 900 one Steam Boiler and the Nest's baseline
	## plant supply, and a Silo asks for 400 more. #37's acceptance criterion is that a
	## competently built Factory can power, load and fire a Silo **within a Run**, demonstrated
	## here rather than asserted — so these four figures are what demonstrates it, and
	## `stratagems_fired` is the one that cannot be faked by a Factory that merely built a Silo.
	var silos_standing: int = 0
	var most_charges_banked: int = 0
	var stratagems_fired: int = 0
	var charges_fired: int = 0
	var charges_wasted: int = 0

	## Which Stratagems were actually called in, in the order they fired, and which ones the
	## Run had unlocked by the end.
	##
	## **#60 needed both and a count could not carry either.** `stratagems_fired` says one was
	## called and says nothing about *which*, and a scenario that asks for an Artillery Barrage
	## and settles for a Supply Drop because the Delivery chain never reached `t03_deep_survey`
	## reports exactly the same integer either way. The unlock set is what says whether the
	## Barrage was ever on the table at all, which is a claim about the chain rather than about
	## the Silo.
	var stratagems_called: PackedStringArray = PackedStringArray()
	var stratagems_unlocked: PackedStringArray = PackedStringArray()

	## The Walls, measured: how many were ever stood up, how many were still standing, and the
	## hit points they absorbed between them.
	##
	## **The damage is the figure the Wall exists to be judged on**, and it is the one a count
	## cannot carry. `wall.health` is priced against `enemy.breaker_damage`, so what a Wall is
	## worth is what it soaked — and a Wall that was never bitten reports zero here however many
	## tiles of it a player paid for, which is a finding rather than a gap. Totalled as
	## `built * max_health` less what the survivors are still holding, because a Wall that was
	## chewed all the way through absorbed every one of its hit points on the way.
	var walls_built: int = 0
	var walls_standing: int = 0
	var wall_hit_points_absorbed: int = 0

	var player_deaths: int = 0

	## The Simulation's state hash at the end of the Run.
	##
	## **Not evidence of anything about the seed**, and worth saying so because it looks like
	## it should be: `Simulation.hash()` feeds `_rng.state`, which is seeded from the world
	## seed, so two seeds differ in hash from tick 0 whether or not a single draw is ever
	## taken. Kept on the report because it identifies a Run exactly, which is what a
	## regression wants; the seed question is answered by comparing the *figures*.
	var state_hash: int = 0

	## Which Delivery tiers the Run finished, and the deepest Node any Miner worked. The two
	## halves of "did this Factory ever grow".
	var deliveries_completed: PackedStringArray = PackedStringArray()

	var power_supply_kw: int = 0
	var power_demand_kw: int = 0
	## Ticks the one Power grid spent short of what the Factory was asking for. A Factory in
	## deficit is a Factory crafting slowly, which is a different failure from running dry and
	## has to be distinguishable from it.
	var ticks_in_power_deficit: int = 0

	var samples: Array = []

	func seconds() -> int:
		@warning_ignore("integer_division")
		return end_tick / Simulation.TICKS_PER_SECOND

	func clock() -> String:
		@warning_ignore("integer_division")
		var minutes: int = seconds() / 60
		return "%dm%02ds" % [minutes, seconds() - minutes * 60]

	func dry_endgame_percent() -> int:
		if endgame_ticks <= 0:
			return 0
		@warning_ignore("integer_division")
		return starved_ticks_in_the_endgame * 100 / endgame_ticks

	func power_deficit_percent() -> int:
		if end_tick <= 0:
			return 0
		@warning_ignore("integer_division")
		return ticks_in_power_deficit * 100 / end_tick

	func pinned_interval_percent() -> int:
		if end_tick <= 0:
			return 0
		@warning_ignore("integer_division")
		return ticks_at_the_interval_floor * 100 / end_tick

	## The named pressure this Run lost to, as a short phrase.
	##
	## Named rather than scored, because the acceptance criterion is that a player can *say*
	## what killed them. The clauses are ordered by what a player would blame first, and
	## every threshold they use is a constant at the top of this file:
	##
	## 1. **Nothing was defending.** No Turret ever stood, so there is no arithmetic to
	##    discuss — this is the few-minutes Run the spec wants a bare Nest to have.
	## 2. **It ran dry.** There was no Ammunition anywhere in the Factory for at least
	##    `DRY_ENDGAME_PERCENT` of the last `ENDGAME_SECONDS`. Production lost to consumption,
	##    which is the pressure the whole game is about.
	## 3. **The Factory was taken.** Machines went missing. Named individually, because
	##    losing a Boiler and losing a Belt-fed Smelter are different lessons.
	## 4. **A Siege Hulk arrived.** The Heat tier that outranges everything a Mk1 Factory
	##    owns. If one was on the Map at the end it is the answer.
	## 5. **Swarmed.** Ammunition was not what ran out: there were simply more Enemies at the
	##    gate than the Turrets could convert. Said alongside the clauses above rather than
	##    only instead of them, because "they took the Factory first" and "there were more of
	##    them than two Turrets convert" are both true of the same Run.
	##
	## Then two standing conditions, appended to whatever the above said, because each one is
	## a *choice the player made* rather than a way the Run ended:
	##
	## - **Browned out**, if the Power grid was short for `POWER_DEFICIT_PERCENT` of the Run.
	## - **Dug too deep**, if more than one Breach was open. Only deep mining opens one.
	##
	## **There is deliberately no "over-produced" clause**, and that is a finding rather than
	## an omission. Every Run that lasts past about twenty minutes spends more than half of
	## itself at `heat.wave_interval_minimum_seconds`, because the net Heat of any working
	## Factory outruns what the Nest can hide — so the label fired on the careful Factory and
	## the careless one alike and said nothing. Over-production is visible in the *Run length*
	## instead: `over_producer` is a quarter shorter than `competent`, and that is the whole of
	## what the player is being told. `pinned_interval_percent` is still reported.
	func cause() -> String:
		if not nest_fell:
			return "survived the cap with the Nest standing"

		var clauses: PackedStringArray = PackedStringArray()
		if turrets_built == 0:
			clauses.append("undefended — nothing ever shot at a Wave")
		elif dry_endgame_percent() >= BalanceProbe.DRY_ENDGAME_PERCENT:
			clauses.append(
				"ran dry — no Ammunition anywhere in the Factory for %d%% of the last %ds"
				% [dry_endgame_percent(), BalanceProbe.ENDGAME_SECONDS]
			)
		if machines_lost.size() > 0:
			clauses.append("lost %d Machines (%s)" % [machines_lost.size(), _lost_summary()])
		if siege_hulks_alive > 0:
			clauses.append("a Siege Hulk was standing")
		# Said whenever Ammunition was *not* what ran out, rather than only when nothing else
		# was wrong: "there were more of them than two Turrets convert" and "they took the
		# Factory first" are both true of the same Run and a reader needs both.
		if turrets_built > 0 and dry_endgame_percent() < BalanceProbe.DRY_ENDGAME_PERCENT:
			clauses.append(
				"swarmed — %d Enemies at the gate with %d rounds still in the Factory"
				% [enemies_alive, ammunition_in_the_factory]
			)
		if clauses.is_empty():
			clauses.append("the Nest fell with nothing else to report")
		if power_deficit_percent() >= BalanceProbe.POWER_DEFICIT_PERCENT:
			clauses.append(
				"browned out — the Power grid was short for %d%% of the Run"
				% power_deficit_percent()
			)
		if breach_count > 1:
			clauses.append("dug too deep — %d Breaches were open" % breach_count)
		# A third standing condition, said only by a Run that built Walls, because the figure a
		# Wall is judged on is what it soaked and it reads as nothing anywhere else. Zero is a
		# finding rather than a blank: it says the Wave routed round rather than chewing.
		if walls_built > 0:
			clauses.append(
				"%d Walls built, %d standing, absorbing %d hit points"
				% [walls_built, walls_standing, wall_hit_points_absorbed]
			)
		return "; ".join(clauses)

	func _lost_summary() -> String:
		var seen: PackedStringArray = PackedStringArray()
		for id: String in machines_lost:
			if not seen.has(id):
				seen.append(id)
		return ", ".join(seen)

	## The one-line row this Run contributes to the report table.
	func row() -> String:
		return (
			"%-14s seed %-3d %-8s wave %-3d peak heat %-6d gap %3ds  %s"
			% [
				scenario_id, world_seed, clock(), wave_number, most_heat_at_once,
				wave_interval_seconds, cause(),
			]
		)

	## Every measured figure, as one line. What two seeds are compared on, because the state
	## hash cannot answer that question: it differs by seed from tick 0 regardless.
	func figures() -> String:
		return (
			"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d [%s] [%s] [%s]"
			% [
				end_tick, wave_number, most_heat_at_once, nest_health, machines_built,
				machines_standing, turrets_built, shots_fired, dry_turret_ticks,
				most_ammunition_at_once, breach_count, hives_standing,
				most_charges_banked, stratagems_fired, charges_wasted,
				walls_built, walls_standing, wall_hit_points_absorbed,
				", ".join(machines_lost),
				", ".join(stratagems_called),
				", ".join(stratagems_unlocked),
			]
		)

	func describe() -> String:
		var lines: PackedStringArray = PackedStringArray()
		lines.append("── %s (seed %d) ─────────────────────────────" % [scenario_id, world_seed])
		lines.append("   %s" % summary)
		lines.append(
			"   lasted %s (%d ticks), reached Wave %d, Nest %d/%d"
			% [clock(), end_tick, wave_number, nest_health, nest_max_health]
		)
		lines.append(
			"   Heat %d (peak %d), making %d/min against %d/min of decay, Wave gap %ds (floor for %d%%)"
			% [
				heat, most_heat_at_once, heat_per_minute, heat_decay_per_minute,
				wave_interval_seconds, pinned_interval_percent(),
			]
		)
		lines.append(
			"   %d Machines built, %d standing, %d lost%s"
			% [
				machines_built, machines_standing, machines_lost.size(),
				(" (%s)" % _lost_summary()) if machines_lost.size() > 0 else "",
			]
		)
		lines.append(
			"   %d Turrets fired %d shots, spending %d Turret-ticks empty; the Factory held no"
			% [turrets_built, shots_fired, dry_turret_ticks]
		)
		lines.append("   Ammunition at all for %d%% of the endgame" % dry_endgame_percent())
		lines.append(
			"   ammunition %d held, %d peak; iron plate %d held"
			% [ammunition_in_the_factory, most_ammunition_at_once, iron_plate_in_the_factory]
		)
		lines.append(
			"   %d Breaches, %d Hives standing, Depth %d reached, %d player deaths"
			% [breach_count, hives_standing, depth_reached, player_deaths]
		)
		lines.append(
			"   Power %d kW supplied against %d kW asked; in deficit for %d%% of the Run"
			% [power_supply_kw, power_demand_kw, power_deficit_percent()]
		)
		lines.append(
			"   %d Silos standing, %d Charges banked at the peak, %d Stratagems fired on"
			% [silos_standing, most_charges_banked, stratagems_fired]
		)
		lines.append(
			"   %d Charges, %d Charges lost to an interrupted Painting"
			% [charges_fired, charges_wasted]
		)
		lines.append(
			"   Stratagems called: %s; unlocked by the end: %s"
			% [
				", ".join(stratagems_called) if stratagems_called.size() > 0 else "none",
				", ".join(stratagems_unlocked) if stratagems_unlocked.size() > 0 else "none",
			]
		)
		lines.append(
			"   %d Walls built, %d standing, %d hit points absorbed between them"
			% [walls_built, walls_standing, wall_hit_points_absorbed]
		)
		lines.append(
			"   Deliveries finished: %s; Breaker arrived %s, Siege Hulk arrived %s"
			% [
				", ".join(deliveries_completed) if deliveries_completed.size() > 0 else "none",
				"yes" if a_breaker_arrived else "no",
				"yes" if a_siege_hulk_arrived else "no",
			]
		)
		lines.append(
			"   %d Enemies alive (%d Crawlers, %d Breakers, %d Siege Hulks), %d at the peak"
			% [
				enemies_alive, crawlers_alive, breakers_alive, siege_hulks_alive,
				most_enemies_at_once,
			]
		)
		lines.append("   cause: %s" % cause())
		for sample: Sample in samples:
			lines.append(sample.describe())
		return "\n".join(lines)


## Plays one scenario on one seed and reports it.
##
## `definitions` is the content the Run uses; null reads `content/` off disk, which is what
## a balance measurement wants — the point is to measure the shipped numbers.
static func play(
	scenario: BalanceScenario,
	world_seed: int = 0,
	tick_cap: int = DEFAULT_TICK_CAP,
	definitions: Definitions = null,
	layout: MapLayout = null
) -> Report:
	var map: MapLayout = layout if layout != null else MapLayout.starter()
	var sim: Simulation = Simulation.new(world_seed, 1, definitions, map)

	var report: Report = Report.new()
	report.scenario_id = scenario.id
	report.summary = scenario.summary
	report.world_seed = world_seed
	report.nest_max_health = sim.query_nest_max_health()

	# `heat.wave_interval_minimum_seconds` is a fixed-point quantity of *seconds*, the way
	# every decimal in tuning.toml is, so it goes through the same conversion the Simulation
	# uses rather than being multiplied as if it were a whole number.
	var interval_floor_ticks: int = maxi(
		Fixed.floor_to_int(
			Fixed.mul(
				sim.query_definitions().heat_wave_interval_minimum_seconds,
				Fixed.from_int(Simulation.TICKS_PER_SECOND)
			)
		),
		1
	)

	# Cached because finding the Turrets means walking the Machines, and the Machine table
	# only changes when something is built or destroyed. Recomputing it every tick for an
	# hour of game time is the difference between a measurement that runs and one nobody runs.
	var turret_indices: PackedInt64Array = PackedInt64Array()
	var last_shot_tick: PackedInt64Array = PackedInt64Array()
	var machine_ids: PackedStringArray = PackedStringArray()
	var machine_count: int = -1

	var endgame_starved: PackedInt64Array = PackedInt64Array()
	var endgame_lived: PackedInt64Array = PackedInt64Array()
	# The endgame is the last two minutes of whatever the Run turned out to be, which is not
	# known until it ends — so both are accumulated per second and the tail is summed at the
	# end. A ring of per-second buckets, one per second of the endgame.
	endgame_starved.resize(ENDGAME_SECONDS + 1)
	endgame_lived.resize(ENDGAME_SECONDS + 1)
	endgame_starved.fill(0)
	endgame_lived.fill(0)
	var bucket_second: int = -1

	var was_alive: bool = true

	# The Walls, tracked by tile rather than by index, because `_remove_wall` closes the gap
	# exactly as `_remove_machine` does — so an index says nothing about which Wall it was.
	# Skipped entirely while no Wall has ever stood, which is every scenario but two.
	var wall_health_by_tile: Dictionary = {}

	# Which Stratagem is in the channel, remembered from the tick before it lands: the Painting
	# is cleared on the tick it completes, so the id has to be caught on the way past.
	var painting_stratagem: String = ""
	var stratagems_fired_so_far: int = 0

	for tick: int in range(tick_cap):
		sim.step(scenario.actions_at(tick))

		if sim.query_machine_count() != machine_count:
			machine_count = sim.query_machine_count()
			var present: PackedStringArray = PackedStringArray()
			for index: int in range(machine_count):
				present.append(sim.query_machine_id(index))
			for id: String in machine_ids:
				var slot: int = present.find(id)
				if slot == -1:
					report.machines_lost.append(id)
				else:
					present.remove_at(slot)
			# Whatever is left in `present` is newly built.
			report.machines_built += present.size()
			machine_ids = PackedStringArray()
			for index: int in range(machine_count):
				machine_ids.append(sim.query_machine_id(index))

			turret_indices = PackedInt64Array()
			for index: int in range(machine_count):
				if sim.query_machine_is_turret(index) and sim.query_machine_id(index) != "repair_pylon_mk1":
					turret_indices.append(index)
			report.turrets_built = maxi(report.turrets_built, turret_indices.size())
			last_shot_tick.resize(machine_count)

		@warning_ignore("integer_division")
		var second: int = tick / Simulation.TICKS_PER_SECOND
		var slot_index: int = second % (ENDGAME_SECONDS + 1)
		if second != bucket_second:
			bucket_second = second
			endgame_starved[slot_index] = 0
			endgame_lived[slot_index] = 0

		for index: int in turret_indices:
			if sim.query_turret_ammunition(index) <= 0:
				report.dry_turret_ticks += 1
			var shot: int = sim.query_turret_last_shot_tick(index)
			if shot != -1 and shot != last_shot_tick[index]:
				report.shots_fired += 1
				last_shot_tick[index] = shot

		if sim.query_wave_interval_ticks() <= interval_floor_ticks:
			report.ticks_at_the_interval_floor += 1
		if sim.query_power_is_in_deficit():
			report.ticks_in_power_deficit += 1

		var banked: int = 0
		for index: int in range(machine_count):
			if sim.query_machine_is_silo(index):
				banked += sim.query_silo_charges(index)
		report.most_charges_banked = maxi(report.most_charges_banked, banked)

		report.most_enemies_at_once = maxi(report.most_enemies_at_once, sim.query_enemy_count())
		report.most_heat_at_once = maxi(report.most_heat_at_once, sim.query_heat())
		var ammunition: int = sim.query_item_total("ammunition")
		report.most_ammunition_at_once = maxi(report.most_ammunition_at_once, ammunition)
		endgame_lived[slot_index] += 1
		if ammunition <= 0:
			endgame_starved[slot_index] += 1
		for index: int in range(sim.query_enemy_count()):
			var kind: int = sim.query_enemy_kind(index)
			if kind == EnemyKind.BREAKER:
				report.a_breaker_arrived = true
			elif kind == EnemyKind.SIEGE_HULK:
				report.a_siege_hulk_arrived = true

		if sim.query_wall_count() > 0 or not wall_health_by_tile.is_empty():
			var standing: Dictionary = {}
			for index: int in range(sim.query_wall_count()):
				standing[sim.query_wall_tile(index)] = sim.query_wall_health(index)
			for tile: Vector3i in wall_health_by_tile:
				var was: int = wall_health_by_tile[tile]
				# A Wall that is gone was chewed all the way through, so it absorbed whatever
				# it was still holding. Nothing in these scenarios demolishes one.
				var now: int = standing[tile] if standing.has(tile) else 0
				report.wall_hit_points_absorbed += maxi(was - now, 0)
			for tile: Vector3i in standing:
				if not wall_health_by_tile.has(tile):
					report.walls_built += 1
			wall_health_by_tile = standing

		var fired: int = sim.query_player_stratagems_fired(0)
		while stratagems_fired_so_far < fired:
			report.stratagems_called.append(painting_stratagem)
			stratagems_fired_so_far += 1
		var in_the_channel: String = sim.query_player_paint_stratagem(0)
		if in_the_channel != "":
			painting_stratagem = in_the_channel

		var alive: bool = sim.query_player_is_alive(0)
		if was_alive and not alive:
			report.player_deaths += 1
		was_alive = alive

		if tick % Simulation.TICKS_PER_MINUTE == Simulation.TICKS_PER_MINUTE - 1:
			report.samples.append(_sample(sim, ammunition, turret_indices.size()))

		if sim.query_run_is_over():
			break

	report.end_tick = sim.query_tick()
	report.nest_fell = sim.query_run_is_over()
	report.wave_number = sim.query_wave_number()
	report.nest_health = sim.query_nest_health()
	report.heat = sim.query_heat()
	report.heat_per_minute = sim.query_heat_per_minute()
	report.heat_decay_per_minute = sim.query_heat_decay_per_minute()
	@warning_ignore("integer_division")
	report.wave_interval_seconds = sim.query_wave_interval_ticks() / Simulation.TICKS_PER_SECOND
	report.breach_count = sim.query_breach_count()
	report.hives_standing = sim.query_hive_count()
	report.depth_reached = sim.query_depth_reached()
	report.enemies_alive = sim.query_enemy_count()
	report.machines_standing = sim.query_machine_count()
	report.ammunition_in_the_factory = sim.query_item_total("ammunition")
	report.iron_plate_in_the_factory = sim.query_item_total("iron_plate")
	report.deliveries_completed = sim.query_completed_deliveries()
	report.power_supply_kw = sim.query_power_supply_kw()
	report.power_demand_kw = sim.query_power_demand_kw()
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_silo(index):
			report.silos_standing += 1
	report.stratagems_fired = sim.query_player_stratagems_fired(0)
	report.charges_fired = sim.query_player_charges_fired(0)
	report.charges_wasted = sim.query_player_charges_wasted(0)
	report.stratagems_unlocked = sim.query_unlocked_stratagems()
	report.walls_standing = sim.query_wall_count()
	report.state_hash = sim.hash()
	for index: int in range(sim.query_enemy_count()):
		var kind: int = sim.query_enemy_kind(index)
		if kind == EnemyKind.CRAWLER:
			report.crawlers_alive += 1
		elif kind == EnemyKind.BREAKER:
			report.breakers_alive += 1
		elif kind == EnemyKind.SIEGE_HULK:
			report.siege_hulks_alive += 1

	# The endgame is the last ENDGAME_SECONDS of per-second buckets, walked back from the
	# second the Run ended on.
	@warning_ignore("integer_division")
	var final_second: int = maxi(report.end_tick - 1, 0) / Simulation.TICKS_PER_SECOND
	for back: int in range(mini(ENDGAME_SECONDS, final_second + 1)):
		var index: int = (final_second - back) % (ENDGAME_SECONDS + 1)
		report.starved_ticks_in_the_endgame += endgame_starved[index]
		report.endgame_ticks += endgame_lived[index]

	return report


static func _sample(sim: Simulation, ammunition: int, turrets: int) -> Sample:
	var sample: Sample = Sample.new()
	@warning_ignore("integer_division")
	sample.minute = (sim.query_tick() + 1) / Simulation.TICKS_PER_MINUTE
	sample.wave = sim.query_wave_number()
	sample.heat = sim.query_heat()
	@warning_ignore("integer_division")
	sample.wave_interval_seconds = sim.query_wave_interval_ticks() / Simulation.TICKS_PER_SECOND
	sample.enemies_alive = sim.query_enemy_count()
	sample.nest_health = sim.query_nest_health()
	sample.ammunition_in_the_factory = ammunition
	sample.turret_count = turrets
	sample.machine_count = sim.query_machine_count()
	return sample
