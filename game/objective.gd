## The one line that makes the opening five minutes teach itself.
##
## A Run opens on bare ground with 80 plate and no idea what to do. Everything a player
## needs is already a query — is a Miner on a Node, is a crafter starved, has anything
## reached the Nest — and until #36 none of it was ever put as an instruction. This is that
## instruction: **one line, which changes as things get done, and goes away when they are**.
##
## **Not a tutorial mode.** There is nothing to enter, nothing to skip and nothing to
## complete: the line is a pure function of the Run's current state, so a player who builds
## the whole line before reading it never sees a word of it, and a player who demolishes
## their Miner an hour in gets the first line back because the first thing is true again.
## Nothing is remembered, nothing is gated, and the Simulation does not know this exists.
##
## It lives in `game/` for the reason `BuildGun.refusal_text` does: a `Refusal` is a fact and
## a sentence about it is presentation. So is "you have not built a Miner yet".
##
## **The steps are read off roles and states rather than off ids.** Nothing here names
## `smelter_mk1`, because the set of Machines is `content/machines.csv`'s business and a line
## that named a row would be a second content table written in GDScript. What it names are
## the three things the opening loop is made of — something that mines, something that
## crafts, and a Belt between them — and the keys that do them.
class_name Objective
extends RefCounted


## What the player should do next, or "" when the opening has taught itself.
##
## Walked in order and the first unmet step wins, so the line is always about the nearest
## thing between the player and a working production line.
static func line(sim: Simulation) -> String:
	if sim == null or sim.query_run_is_over():
		return ""
	# Once a tier has been delivered the loop has closed at least once: the player has
	# mined, crafted, moved goods and been paid for it, and has no further use for a
	# hint line taking up the top of their screen.
	if not sim.query_completed_deliveries().is_empty():
		return ""

	if not _something_is_mining(sim):
		return "Place a Miner on an ore node — wheel or 1-9 to pick, left click to place"
	if not _something_crafts(sim):
		return "Place a Smelter on clear ground nearby — it turns ore into ingots"
	if not _anything_is_belted(sim):
		return "Press C for the Belt tool, then drag from the orange arrow to the blue one"
	if _anything_is_starved(sim):
		return "Something is starved — a Belt starts past an output arrow and ends at an input"
	return "Carry ingots to the Nest and press F — delivering is how a Run gets better"


## Whether a Miner is standing on ground it can actually work. Not "is a Miner built": a
## Miner on bare rock accumulates nothing at all (CLAUDE.md), and telling a player they have
## done the first step when they have not is worse than saying nothing.
static func _something_is_mining(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		var definition: MachineDefinition = sim.query_definitions().machine(
			sim.query_machine_id(index)
		)
		if definition == null or not definition.is_miner():
			continue
		if sim.query_node_under_machine(index) != -1:
			return true
	return false


## Whether anything that turns one good into another is standing. A crafter rather than a
## named Machine, so the line follows the content table rather than restating it.
static func _something_crafts(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		var definition: MachineDefinition = sim.query_definitions().machine(
			sim.query_machine_id(index)
		)
		if definition != null and definition.role == MachineDefinition.Role.CRAFTER:
			return true
	return false


## Whether any Belt is doing the job a Belt is for: fed at one end, and leading somewhere at
## the other. A Belt laid on open ground is not a connection, and a line that congratulated a
## player for laying one would be teaching the wrong thing.
static func _anything_is_belted(sim: Simulation) -> bool:
	for index: int in range(sim.query_belt_count()):
		if sim.query_belt_start_is_fed(index) and sim.query_belt_end_is_connected(index):
			return true
	return false


static func _anything_is_starved(sim: Simulation) -> bool:
	for index: int in range(sim.query_machine_count()):
		if sim.query_machine_is_starved(index):
			return true
	return false
