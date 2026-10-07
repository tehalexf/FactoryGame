## What collision costs a tick, measured rather than estimated.
##
## Not part of the suite: it reports a wall-clock number, and nothing that reads a clock
## belongs in a determinism suite. Run it when the per-tick budget is in question.
##
##     godot --headless --path . --script tools/bench_collision.gd
extends SceneTree


func _init() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	if definitions.has_errors():
		print(definitions.describe_errors())
		quit(1)
		return

	# Walls rather than Machines: a Wall is free, is one tile, and does nothing at all on a
	# tick — so the difference between 0 and 4000 of them is the height field and the height
	# field alone, where a Factory of Smelters would also be measuring crafts, Power and
	# Heat. 4000 is far past the "hundreds of Machines" the ticket worries about.
	for walls: int in [0, 200, 4000]:
		var sim: Simulation = Simulation.new(7, 1, definitions, MapLayout.empty())
		var built: int = 0
		var row: int = 0
		while built < walls:
			var actions: Array = []
			for column: int in range(64):
				if built >= walls:
					break
				actions.append(
					InputAction.build_wall(
						0, Vector3i(column - 32, WorldGrid.GROUND_LAYER, 10 + row)
					)
				)
				built += 1
			sim.step(actions)
			row += 1
		# Warm every derived field, so the measurement is of a tick that moves a player
		# rather than of one that rebuilds a Factory.
		sim.step([InputAction.move(0, Fixed.ONE, 0)])

		var ticks: int = 20000
		var started: int = Time.get_ticks_usec()
		for _i: int in range(ticks):
			sim.step([InputAction.move(0, Fixed.ONE, Fixed.ONE)])
		var spent: int = Time.get_ticks_usec() - started
		print(
			"%5d Walls: %6.2f us a tick (%d standing)"
			% [walls, float(spent) / float(ticks), sim.query_wall_count()]
		)
	# And how it scales with players, which is the other axis the ticket names: collision is
	# resolved once per player per tick, so four players in co-op is four times the work of
	# one — and the difference between one and four is a direct reading of what a player's
	# own share of a tick is.
	for players: int in [1, 4]:
		var sim: Simulation = Simulation.new(7, players, definitions, MapLayout.empty())
		sim.step([InputAction.move(0, Fixed.ONE, 0)])
		var moves: Array = []
		for player_id: int in range(players):
			moves.append(InputAction.move(player_id, Fixed.ONE, Fixed.ONE))
		var ticks: int = 20000
		var started: int = Time.get_ticks_usec()
		for _i: int in range(ticks):
			var copied: Array = []
			for action: InputAction in moves:
				copied.append(action)
			sim.step(copied)
		var spent: int = Time.get_ticks_usec() - started
		print(
			"%d player(s) walking: %6.2f us a tick"
			% [players, float(spent) / float(ticks)]
		)
	# And what a repaint costs, which is the only part of this that grows with the Factory.
	# Paid on a tick that built or lost something and never on a tick that merely moved
	# somebody, so the figure to compare it against is how often a player places a Wall.
	var crowded: Simulation = Simulation.new(7, 1, definitions, MapLayout.empty())
	var standing: int = 0
	var line: int = 0
	while standing < 3000:
		var actions: Array = []
		for column: int in range(60):
			actions.append(
				InputAction.build_wall(0, Vector3i(column - 30, WorldGrid.GROUND_LAYER, line))
			)
			standing += 1
		crowded.step(actions)
		line += 1
	crowded.step([InputAction.move(0, Fixed.ONE, 0)])

	var repaints: int = 200
	var repaint_started: int = Time.get_ticks_usec()
	for index: int in range(repaints):
		# One Wall built and demolished alternately, so every one of these ticks really does
		# invalidate the field and the next read really does repaint it.
		crowded.step([
			InputAction.build_wall(0, Vector3i(40, WorldGrid.GROUND_LAYER, 40))
			if index % 2 == 0
			else InputAction.demolish(0, Vector3i(40, WorldGrid.GROUND_LAYER, 40)),
			InputAction.move(0, Fixed.ONE, Fixed.ONE),
		])
	var repaint_spent: int = Time.get_ticks_usec() - repaint_started
	print(
		"a repaint over %d structures: %6.2f us a tick"
		% [crowded.query_wall_count(), float(repaint_spent) / float(repaints)]
	)
	quit(0)
