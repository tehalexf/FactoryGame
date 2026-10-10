## The one positive thing this game says about a production line: **it works.**
##
## Everything else drawn about a line is a complaint. A red post stands where a Belt leads
## nowhere (#36), an amber tag hangs over a starved Machine (#36), a post marks a blocked
## branch (#48), and since #56 the HUD says in words why a Belt will not dock. A player who
## has just laid their first Miner-to-Smelter-to-Press chain had to infer success from the
## **absence** of marks — and absence is exactly what this project has twice found a player
## cannot read: #52's ore was invisible because nothing marked it, and #41's gauge was
## unreadable because a mark with no owner says nothing. "No red posts" is not a signal.
##
## What did not exist was the notion of a **chain** — a Machine, the Belts off it, and what
## they reach — and whether it is whole. That is the whole of this file.
##
## It lives in `game/` for the reason `Objective` and `BuildChain` do: whether a Belt hands an
## Item over is a fact the Simulation owns, and "these four things are one line and it is
## running" is a sentence about those facts. The Simulation does not know this file exists,
## and asking any of it leaves the state hash where it was.
##
## **Nothing here is a second opinion about connectedness.** Every question it asks is one of
## the projections the hand-off itself goes through — `query_belt_feeds_machine`,
## `query_belt_feeds_belt` and `query_belt_feeds_the_nest` are one line each over
## `_machine_a_belt_feeds`, `_belt_downstream` and `_hand_off`'s Nest clause;
## `query_machine_branch_belt` is the same rule asked per Machine; and `query_machine_is_starved`
## is the Simulation's own answer about whether a Machine is doing anything. So a line cannot
## read as working and starve.
class_name LineWorks
extends RefCounted


## A maximal group of Machines joined by Belt runs, plus whether that group reaches the Nest.
##
## It carries two lists of Belts on purpose. `links` are the runs that **join** two ends of the
## chain, in flow order, which is what a travelling mark runs along; `belts` is every Belt that
## touches any of the chain's Machines at either end, which is what wholeness is judged over —
## a chain with a dangling Belt hanging off one of its Machines is a chain standing next to a
## red post, and a positive signal must never contradict a complaint.
class Chain:
	extends RefCounted

	var machines: PackedInt64Array = PackedInt64Array()
	var tiles: Array[Vector3i] = []
	var links: Array[PackedInt64Array] = []
	var belts: PackedInt64Array = PackedInt64Array()
	var reaches_the_nest: bool = false
	var is_whole: bool = false

	## What identifies this chain across frames, for a renderer that wants to know when one
	## *became* whole.
	##
	## **Geography, not indices.** A Machine index shifts the moment anything is destroyed —
	## `_remove_machine` closes the gap — so a chain keyed by index would change identity
	## because something else fell over. Its Machines' anchor tiles cannot move: a Machine is
	## built on a tile or it is gone. Adding a Machine to a line is therefore a *different*
	## chain, which is the right answer rather than a quirk — extending your line is a new
	## thing to be told about.
	func signature() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for tile: Vector3i in tiles:
			parts.append("%d,%d,%d" % [tile.x, tile.y, tile.z])
		if reaches_the_nest:
			parts.append("nest")
		return "|".join(parts)


## Every chain on the Map, in ascending order of their first Machine.
##
## O(Machines + Belts) with one walk down each link, which is why it is safe to ask every
## frame — `_mark_obstructions`' lesson about per-thing questions over a whole Factory.
static func chains(sim: Simulation) -> Array[Chain]:
	var machine_count: int = sim.query_machine_count()
	var belt_count: int = sim.query_belt_count()

	# Which Machine loads each Belt, read off the Machine's own branch list rather than asked
	# per Belt, so the membership is exactly the group `_load_the_ports` serves in rotation.
	var loader: PackedInt64Array = PackedInt64Array()
	loader.resize(belt_count)
	loader.fill(-1)
	for machine: int in range(machine_count):
		for which: int in range(sim.query_machine_branch_count(machine)):
			var belt: int = sim.query_machine_branch_belt(machine, which)
			if belt >= 0 and belt < belt_count:
				loader[belt] = machine

	# One extra member for the Nest, so a Miner belting ore straight to the counter is a
	# chain rather than a lone Machine. That is the opening Delivery, which is the first
	# thing a Run is told to build.
	var nest_member: int = machine_count
	var parent: PackedInt64Array = PackedInt64Array()
	parent.resize(machine_count + 1)
	for member: int in range(parent.size()):
		parent[member] = member

	var links: Array[PackedInt64Array] = []
	var link_owner: PackedInt64Array = PackedInt64Array()
	for belt: int in range(belt_count):
		if loader[belt] == -1:
			continue
		var run: PackedInt64Array = _follow(sim, belt, belt_count)
		var last: int = run[run.size() - 1]
		var reached: int = -1
		if sim.query_belt_feeds_machine(last) != -1:
			reached = sim.query_belt_feeds_machine(last)
		elif sim.query_belt_feeds_the_nest(last):
			reached = nest_member
		if reached == -1:
			continue
		_union(parent, loader[belt], reached)
		links.append(run)
		link_owner.append(loader[belt])

	# A Belt belongs to the chain of whichever end of it is attached. Both ends dangling is a
	# Belt that belongs to nobody — it wears two red posts and is nothing's line.
	var belt_member: PackedInt64Array = PackedInt64Array()
	belt_member.resize(belt_count)
	for belt: int in range(belt_count):
		if loader[belt] != -1:
			belt_member[belt] = loader[belt]
		else:
			belt_member[belt] = sim.query_belt_feeds_machine(belt)

	# Grouped only once every union is done. Grouping inside the loop above would key a chain
	# on a root that a later link then merged away, and the chain whose first Machine is
	# earliest would not be the one holding the links.
	var by_root: Dictionary = {}
	var roots: PackedInt64Array = PackedInt64Array()
	for link: int in range(links.size()):
		var root: int = _find(parent, link_owner[link])
		if not by_root.has(root):
			by_root[root] = Chain.new()
			roots.append(root)
		var chain: Chain = by_root[root]
		chain.links.append(links[link])

	roots.sort()
	var answer: Array[Chain] = []
	for root: int in roots:
		var chain: Chain = by_root[root]
		for machine: int in range(machine_count):
			if _find(parent, machine) == root:
				chain.machines.append(machine)
				chain.tiles.append(sim.query_machine_tile(machine))
		chain.reaches_the_nest = _find(parent, nest_member) == root
		for belt: int in range(belt_count):
			if belt_member[belt] != -1 and _find(parent, belt_member[belt]) == root:
				chain.belts.append(belt)
		chain.tiles.sort_custom(MapLayout.tile_precedes)
		chain.is_whole = _is_whole(sim, chain)
		answer.append(chain)
	return answer


## Whether a chain is connected and carrying — the whole of what the signal claims.
##
## Four conditions, each read off the Simulation's own answer:
##
## - it joins at least two ends, which `links` being non-empty already says;
## - **every** Belt touching it is fed at its entry and connected at its far end, so a chain
##   cannot read as working while one of its Machines wears a red post;
## - every one of those Belts is **carrying at least one Item**, which is the literal content
##   of "carrying goods" and the one condition that makes this a statement about a line that
##   is running rather than about one that is merely wired up;
## - and no Machine in it is starved.
##
## **`query_belt_is_stalled` is deliberately not consulted**, which is #48's note read the
## other way round. A healthy saturated Belt feeding a slower consumer is stalled on most
## ticks — that is what back-pressure *is* — so requiring "not stalled" would switch the
## signal off on exactly the lines that are working hardest.
static func _is_whole(sim: Simulation, chain: Chain) -> bool:
	if chain.links.is_empty():
		return false
	for belt: int in chain.belts:
		if not sim.query_belt_start_is_fed(belt):
			return false
		if not sim.query_belt_end_is_connected(belt):
			return false
		if sim.query_belt_item_count(belt) == 0:
			return false
	for machine: int in chain.machines:
		if sim.query_machine_is_starved(machine):
			return false
	return true


## The run of Belts from one a Machine loads down to wherever it ends, in flow order.
##
## Bounded by the Belt count rather than trusting the chase to terminate: a Belt loop has no
## downstream-most member, and the update order cuts one by fiat (see CLAUDE.md) where this
## has no standing to.
static func _follow(sim: Simulation, from: int, belt_count: int) -> PackedInt64Array:
	var run: PackedInt64Array = PackedInt64Array([from])
	var at: int = from
	for step: int in range(belt_count):
		var onward: int = sim.query_belt_feeds_belt(at)
		if onward == -1 or run.has(onward):
			break
		run.append(onward)
		at = onward
	return run


static func _find(parent: PackedInt64Array, member: int) -> int:
	var at: int = member
	while parent[at] != at:
		at = parent[at]
	return at


static func _union(parent: PackedInt64Array, left: int, right: int) -> void:
	var a: int = _find(parent, left)
	var b: int = _find(parent, right)
	if a == b:
		return
	# The smaller index wins, so a chain's root is its earliest member and the order chains
	# come back in is a property of the Factory rather than of the order they were walked.
	if a < b:
		parent[b] = a
	else:
		parent[a] = b
