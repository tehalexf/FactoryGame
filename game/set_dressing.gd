## The yard the Factory stands in: pipe runs, catwalks, crates, fences, lights and
## a skyline past the Map's edge.
##
## **None of it is Simulation state and none of it can become any.** A Run's hash
## does not know this file exists; the layout is a pure function of
## `query_seed()`, the grid's size and the tile size, so two clients draw the same
## yard without a byte crossing between them and a replay looks like itself. It is
## decoration, and decoration that could be built on, walked through or shot would
## be a second opinion about the Map — so nothing here is told to the Simulation
## and nothing here carries a collider.
##
## ── Three things it is careful about ─────────────────────────────────────────
##
## **It gets out of the player's way.** Everything inside the Map sits on a tile,
## and a tile the Simulation reports as built on — a Machine, a Belt, a Wall, a
## Node, the Nest — loses its prop on the next sync. That is not a nicety: the
## buildable area is the whole Map, so decoration that stayed would be decoration
## standing inside a Smelter. It reads, usefully, as clearing the ground to build.
##
## **The purchased props are loaded at runtime from outside the repository, and
## are usually not there.** They are non-redistributable (docs/ASSETS.md), so
## `tools/assets/convert_props.sh` writes them into `PROP_DIRECTORY` — gitignored,
## outside the shipping tree — and this file draws **self-authored stand-ins** in
## the same places when it finds nothing. A clone without the packs gets a yard
## built out of boxes and cylinders wearing the Machines' own materials: plainer,
## but a place rather than a plane, and a game that builds and tests.
##
## **It is a handful of draw calls, not four hundred nodes.** Every prop kind is
## one `MultiMeshInstance3D`, and the whole heyheythere set shares one material
## over one atlas, so the yard costs about as much as the Factory standing in it.
class_name SetDressing
extends Node3D

## Where a converted prop lives: `<prop id>.glb`, beside the `atlas.png` they all
## wear. Outside the shipping tree, gitignored, and usually absent — an ordinary
## state, not a warning. `tools/assets/convert_props.sh` is what writes it.
const PROP_DIRECTORY: String = "res://assets_licensed/generated/props/"

## The committed Machine palette, which is what the stand-ins are made of. Using
## the Machines' own materials is the point: a yard that has to stand in for the
## purchased one should at least belong to the same world as the thing it is
## standing around.
const MATERIAL_DIRECTORY: String = "res://assets/machines/materials/"

## What each kind of dressing may be, best first. A kind is the *role* — a thing
## on the ground, a span of pipe, a fence panel — and the list is the purchased
## props that can play it. The layout picks a variant per placement and keeps it,
## so a crate does not change into a drum when a Belt is built across the yard.
##
## **The kind is what the stand-ins are built from too**, which is why the roles
## are named for what they do rather than for what the pack calls them: a clone
## with no packs walks the same layout and gets `_stand_in_for(kind)`.
const KINDS: Dictionary = {
	"clutter": [
		"crate_large", "crate_small", "pallet", "pallet_boxes", "pallet_sacks",
		"pallet_stack", "drum_steel_blue", "drum_steel_red", "drum_steel_open",
		"drum_plastic", "cardboard_heap", "ibc_tote", "cable_drum", "cable_coil",
		"tyre_stack", "tool_chest", "wheelie_bin", "hand_truck", "pallet_jack",
		"traffic_cone", "spill_kit", "gas_cylinder_rack", "debris_pile",
		"rubble_spread", "oil_spill",
	],
	"yard_gear": [
		"workbench", "shelving_steel", "racking_bay_loaded", "waste_skip",
		"work_light_tripod", "pressure_vessel", "hopper",
	],
	"stain": ["oil_spill", "rubble_spread", "debris_pile", "cable_coil", "traffic_cone"],
	"pipe_leg": ["pipe_rack"],
	"pipe_span": ["pipe_straight", "pipe_lagged", "tray_straight"],
	"pipe_riser": ["pipe_riser"],
	"pipe_elbow": ["pipe_elbow"],
	"lamp": ["lamp_high_bay", "floodlight_wall"],
	"catwalk_span": ["catwalk_straight"],
	"catwalk_leg": ["catwalk_support"],
	"railing": ["railing_2m"],
	"fence": ["mesh_fence"],
	"barrier": ["jersey_barrier"],
	"bollard": ["bollard"],
	"mast": ["yard_floodlight", "yard_light"],
	"skyline": [
		"yard_silo", "yard_water_tank", "yard_container", "tank_vertical",
		"tank_horizontal",
	],
}

## How far from the Nest, and from each Node, the yard keeps clear, in tiles. A
## player's first act is to put a Miner on a Node and their Factory grows out of
## the Nest, so those two are where dressing is most in the way and least wanted.
const NEST_CLEARANCE_TILES: int = 8
const NODE_CLEARANCE_TILES: int = 4

## How many piles of clutter, and how many props in one. Clustered rather than
## sprinkled, because sprinkled reads as confetti and clustered reads as a place
## where somebody put something down and then put something else down beside it.
##
## **Counted per anchor rather than per Map**, which is the correction a render
## forced. Spread evenly over a 129-tile square, two hundred props is one prop
## every eighty tiles — statistically a yard and visibly an empty plain, because
## a player spends a Run inside a thirty-metre circle around their own Factory
## and nothing was ever in it. Anchoring the scatter on the Nest, the Nodes and
## the Breaches puts the yard where the game is played and leaves the far corners
## of the Map thin, which is also what a real yard looks like.
const CLUSTERS_PER_ANCHOR: int = 9
const CLUSTER_SIZE_LOW: int = 3
const CLUSTER_SIZE_HIGH: int = 8
const CLUSTER_SPREAD_TILES: int = 2
## How far from its anchor a cluster may fall, in tiles. The low end is outside the
## clearance, so a pile never lands on the Node a Miner wants.
const CLUSTER_RADIUS_LOW_TILES: int = 6
const CLUSTER_RADIUS_HIGH_TILES: int = 26
## Piles with no anchor at all, spread over the whole Map, so the far ground is
## worked rather than empty.
const LOOSE_CLUSTER_COUNT: int = 40

## Stains, spills and spread rubble: flat things, placed close in and densely.
##
## **They are what keeps the ground from reading as paper right where the player
## is standing.** Everything else in the yard keeps a wide berth of the Nest and
## the Nodes, because a crate in the middle of where somebody wants a Smelter is
## an annoyance — but a spill is two centimetres tall and a player builds straight
## over it, so it can come right up to the footprint and break up the one part of
## the ground a crate is not allowed to.
const STAINS_PER_ANCHOR: int = 22
const STAIN_RADIUS_LOW_TILES: int = 2
const STAIN_RADIUS_HIGH_TILES: int = 20

## The overhead services. The heyheythere pack's own datums do this work: its pipe
## sections are modelled at 3.0 m, its racks stand 3.37 m, and its catwalk decks
## are a storey up — so a run is the pack's pieces at the pack's heights, and
## nothing here invents a number the art does not already agree with.
const PIPE_RUNS_PER_ANCHOR: int = 1
const PIPE_RUN_TILES_LOW: int = 8
const PIPE_RUN_TILES_HIGH: int = 14
const CATWALK_RUNS_PER_ANCHOR: int = 1
const CATWALK_RUN_TILES_LOW: int = 5
const CATWALK_RUN_TILES_HIGH: int = 11
const CATWALK_DECK_METRES: float = 3.8

## Loose yard gear — a bench, a rack, a skip — placed on its own rather than in a
## pile.
const YARD_GEAR_PER_ANCHOR: int = 4

## The perimeter, in tiles beyond the Map's own edge. The Map stops being
## buildable at `query_grid_half_extent_tiles()`; a fence there is what tells a
## player that, and it is a great deal more honest than the ground running out.
const PERIMETER_OFFSET_TILES: int = 2
const PERIMETER_MAST_EVERY_PANELS: int = 11
const PERIMETER_GAP_IN: int = 17

## What is past the fence. Big, sparse, and far enough out that the depth fog has
## it: the question "what is beyond the buildable area" wants an answer a player
## can see without being an answer they can reach.
const SKYLINE_COUNT: int = 70
const SKYLINE_NEAR_TILES: int = 6
const SKYLINE_FAR_TILES: int = 56

## Floats in one MultiMesh instance transform. Row-major, which is the layout
## `MultiMesh.TRANSFORM_3D` expects.
const FLOATS_PER_INSTANCE: int = 12

## One placement: `{kind, variant, where, yaw, scale, tile, tiled}`. Built once per
## seed and then only filtered, never regenerated — regenerating it on a build
## would make the yard shuffle itself every time a player placed a Belt.
var _placements: Array = []
var _laid_out_for_seed: int = -1
var _laid_out_for_extent: int = -1

## Group key — a prop id, or `stand-in:<kind>` — to the node and mesh drawing it.
var _pools: Dictionary = {}
var _group_meshes: Dictionary = {}
## Prop id -> Mesh, or null for one that is not on disk. Loaded once.
var _prop_meshes: Dictionary = {}
var _shared_material: StandardMaterial3D = null
var _material_cache: Dictionary = {}
var _stand_in_cache: Dictionary = {}
## What the Factory looked like when the pools were last filled. Rebuilding every
## frame would be four hundred tile lookups a frame to answer a question that
## changes when somebody builds something.
var _drawn_for: int = -1
## The placements that survived the last filter, in no particular order. The
## readable record of what is on screen; see `instance_position`.
var _drawn: Array = []


## Draw the yard for this Run, and clear whatever has been built on.
func sync(sim: Simulation) -> void:
	_lay_out(sim)
	var signature: int = _occupancy_signature(sim)
	if signature == _drawn_for:
		return
	_drawn_for = signature
	_fill_pools(sim)


## How many props are on screen. The test seam: a clone with no packs draws the
## same count out of stand-ins, which is the whole claim this file makes.
func instance_count() -> int:
	return _drawn.size()


## Where one of them stands, and what role it is playing.
##
## A MultiMesh keeps its instances on the rendering server, where a headless test
## cannot see them — `get_instance_transform` hands back the identity under the
## dummy driver — so this side keeps the readable record. The same arrangement
## `WorldView._wall_transforms` has, for the same reason.
func instance_position(index: int) -> Vector3:
	if index < 0 or index >= _drawn.size():
		return Vector3.ZERO
	return (_drawn[index] as Dictionary)["where"]


func instance_kind(index: int) -> String:
	if index < 0 or index >= _drawn.size():
		return ""
	return (_drawn[index] as Dictionary)["kind"]


## Whether any purchased prop was found. False on a clone without the packs, which
## is the ordinary case and not a failure.
func uses_purchased_props() -> bool:
	for key: String in _group_meshes:
		if not key.begins_with("stand-in:"):
			return true
	return false


## How many distinct meshes the yard is drawn from — which is also, near enough,
## its draw call count, because each is one MultiMesh.
func group_count() -> int:
	return _group_meshes.size()


# ── The layout ────────────────────────────────────────────────────────────────


func _lay_out(sim: Simulation) -> void:
	var seed_value: int = sim.query_seed()
	var extent: int = sim.query_grid_half_extent_tiles()
	if seed_value == _laid_out_for_seed and extent == _laid_out_for_extent:
		return
	_laid_out_for_seed = seed_value
	_laid_out_for_extent = extent
	_placements = []
	_drawn_for = -1

	# A stream of its own, mixed off the Run's seed. Not the Simulation's
	# generator and never drawn from it: a decoration that consumed a draw would
	# change the Wave after it.
	var rng: DeterministicRng = DeterministicRng.new(seed_value ^ 0x5E7D_8E55)
	var tile_size: float = Fixed.to_float(sim.query_tile_size_metres())
	var keep_clear: Dictionary = _keep_clear(sim, extent)
	var anchors: Array = _anchors(sim)

	_lay_out_stains(rng, sim, extent, tile_size, anchors)
	_lay_out_clusters(rng, sim, extent, tile_size, keep_clear, anchors)
	_lay_out_yard_gear(rng, sim, extent, tile_size, keep_clear, anchors)
	_lay_out_pipe_runs(rng, sim, extent, tile_size, keep_clear, anchors)
	_lay_out_catwalks(rng, sim, extent, tile_size, keep_clear, anchors)
	_lay_out_perimeter(rng, extent, tile_size)
	_lay_out_skyline(rng, extent, tile_size)


## The places a Run happens around: the Nest, every Node, and every Breach a Run
## opens with. The yard is laid out around these rather than over the Map, because
## a player spends their Run inside a short walk of them and a prop they never get
## near is a prop that was never drawn for them.
func _anchors(sim: Simulation) -> Array:
	var places: Array = []
	var nest: Vector3i = sim.query_nest_tile()
	var footprint: Vector2i = sim.query_nest_footprint()
	places.append(Vector2i(nest.x + footprint.x / 2, nest.z + footprint.y / 2))
	for index: int in range(sim.query_node_count()):
		var node: Vector3i = sim.query_node_tile(index)
		places.append(Vector2i(node.x, node.z))
	for index: int in range(sim.query_breach_count()):
		var breach: Vector3i = sim.query_breach_tile(index)
		places.append(Vector2i(breach.x, breach.z))
	return places


## A tile a given distance out from an anchor, in a direction drawn off the stream.
## The ring rather than a square, so the density around an anchor does not pile up
## in its corners.
func _near(rng: DeterministicRng, anchor: Vector2i, low: int, high: int, extent: int) -> Vector2i:
	var angle: float = float(rng.next_below(3600)) / 3600.0 * TAU
	var radius: float = float(rng.next_range(low, high))
	return Vector2i(
		clampi(anchor.x + int(round(cos(angle) * radius)), -extent + 2, extent - 2),
		clampi(anchor.y + int(round(sin(angle) * radius)), -extent + 2, extent - 2)
	)


## The tiles the yard refuses to stand on whatever else happens: the Nest and its
## apron, and a ring around every Node. Computed once per layout, because a Node
## does not move and neither does the Nest.
func _keep_clear(sim: Simulation, extent: int) -> Dictionary:
	var clear: Dictionary = {}
	var nest: Vector3i = sim.query_nest_tile()
	var footprint: Vector2i = sim.query_nest_footprint()
	for x: int in range(
		nest.x - NEST_CLEARANCE_TILES, nest.x + footprint.x + NEST_CLEARANCE_TILES
	):
		for z: int in range(
			nest.z - NEST_CLEARANCE_TILES, nest.z + footprint.y + NEST_CLEARANCE_TILES
		):
			clear[Vector2i(x, z)] = true
	for index: int in range(sim.query_node_count()):
		var node: Vector3i = sim.query_node_tile(index)
		for x: int in range(node.x - NODE_CLEARANCE_TILES, node.x + NODE_CLEARANCE_TILES + 1):
			for z: int in range(
				node.z - NODE_CLEARANCE_TILES, node.z + NODE_CLEARANCE_TILES + 1
			):
				clear[Vector2i(x, z)] = true
	# The Map's own rim, so a fence panel and a crate never share a tile.
	for along: int in range(-extent, extent + 1):
		clear[Vector2i(along, extent)] = true
		clear[Vector2i(along, -extent)] = true
		clear[Vector2i(extent, along)] = true
		clear[Vector2i(-extent, along)] = true
	return clear


## Flat ground marks, close in. Nothing is kept clear of but the Nest's own footprint
## and the Node tiles themselves — see `STAINS_PER_ANCHOR`.
func _lay_out_stains(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	anchors: Array
) -> void:
	var taken: Dictionary = {}
	for anchor: Vector2i in anchors:
		for which: int in range(STAINS_PER_ANCHOR):
			var tile: Vector2i = _near(
				rng, anchor, STAIN_RADIUS_LOW_TILES, STAIN_RADIUS_HIGH_TILES, extent
			)
			if taken.has(tile):
				continue
			taken[tile] = true
			_place_on_tile(rng, sim, "stain", tile, tile_size, 0.0)


func _lay_out_clusters(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	anchors: Array
) -> void:
	var centres: Array = []
	for anchor: Vector2i in anchors:
		for which: int in range(CLUSTERS_PER_ANCHOR):
			centres.append(
				_near(rng, anchor, CLUSTER_RADIUS_LOW_TILES, CLUSTER_RADIUS_HIGH_TILES, extent)
			)
	for which: int in range(LOOSE_CLUSTER_COUNT):
		centres.append(
			Vector2i(
				rng.next_range(-extent + 2, extent - 2), rng.next_range(-extent + 2, extent - 2)
			)
		)

	var taken: Dictionary = {}
	for centre: Vector2i in centres:
		var wanted: int = rng.next_range(CLUSTER_SIZE_LOW, CLUSTER_SIZE_HIGH)
		for which: int in range(wanted):
			var tile: Vector2i = centre + Vector2i(
				rng.next_range(-CLUSTER_SPREAD_TILES, CLUSTER_SPREAD_TILES),
				rng.next_range(-CLUSTER_SPREAD_TILES, CLUSTER_SPREAD_TILES)
			)
			if keep_clear.has(tile) or taken.has(tile) or absi(tile.x) > extent or absi(tile.y) > extent:
				continue
			taken[tile] = true
			_place_on_tile(rng, sim, "clutter", tile, tile_size, 0.0)


func _lay_out_yard_gear(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	anchors: Array
) -> void:
	for anchor: Vector2i in anchors:
		for which: int in range(YARD_GEAR_PER_ANCHOR):
			var tile: Vector2i = _near(
				rng, anchor, CLUSTER_RADIUS_LOW_TILES, CLUSTER_RADIUS_HIGH_TILES, extent
			)
			if keep_clear.has(tile):
				continue
			_place_on_tile(rng, sim, "yard_gear", tile, tile_size, 0.0)


## A run of overhead pipe: a rack every two tiles with a section spanning between
## them, straight along one axis. The pieces carry their own heights, so the run
## is at the height the pack drew it at.
func _lay_out_pipe_runs(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	anchors: Array
) -> void:
	var runs: Array = []
	for anchor: Vector2i in anchors:
		for which: int in range(PIPE_RUNS_PER_ANCHOR):
			runs.append(
				_near(rng, anchor, CLUSTER_RADIUS_LOW_TILES, CLUSTER_RADIUS_HIGH_TILES, extent)
			)
	for start_at: Vector2i in runs:
		var along_x: bool = rng.next_below(2) == 0
		var length: int = rng.next_range(PIPE_RUN_TILES_LOW, PIPE_RUN_TILES_HIGH)
		var start: Vector2i = Vector2i(
			clampi(start_at.x, -extent + 2, extent - length - 2),
			clampi(start_at.y, -extent + 2, extent - length - 2)
		)
		var yaw: float = 0.0 if along_x else TAU * 0.25
		for step: int in range(length):
			var tile: Vector2i = start + (
				Vector2i(step, 0) if along_x else Vector2i(0, step)
			)
			if keep_clear.has(tile):
				continue
			_place_on_tile(rng, sim, "pipe_span", tile, tile_size, yaw)
			if step % 2 == 0:
				_place_on_tile(rng, sim, "pipe_leg", tile, tile_size, yaw)
			# A run comes up out of the ground at one end and turns at the other, so
			# it reads as plumbing rather than as a length of pipe lying in the air.
			if step == 0:
				_place_on_tile(rng, sim, "pipe_riser", tile, tile_size, yaw)
			elif step == length - 1:
				_place_on_tile(rng, sim, "pipe_elbow", tile, tile_size, yaw)
			# A lamp every eight metres of pipe rack. They are the one thing in the
			# yard that is lit by its own emission map rather than by the sun, which
			# is what makes dusk read as dusk rather than as underexposure.
			if step % 4 == 2:
				_place_on_tile(rng, sim, "lamp", tile, tile_size, yaw)


func _lay_out_catwalks(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	anchors: Array
) -> void:
	var runs: Array = []
	for anchor: Vector2i in anchors:
		for which: int in range(CATWALK_RUNS_PER_ANCHOR):
			runs.append(
				_near(rng, anchor, CLUSTER_RADIUS_LOW_TILES, CLUSTER_RADIUS_HIGH_TILES, extent)
			)
	for start_at: Vector2i in runs:
		var along_x: bool = rng.next_below(2) == 0
		var length: int = rng.next_range(CATWALK_RUN_TILES_LOW, CATWALK_RUN_TILES_HIGH)
		var start: Vector2i = Vector2i(
			clampi(start_at.x, -extent + 2, extent - length - 2),
			clampi(start_at.y, -extent + 2, extent - length - 2)
		)
		# The pack's catwalk deck runs along its own +Z, so a run along X is the
		# quarter turn and a run along Z is none.
		var yaw: float = TAU * 0.25 if along_x else 0.0
		for step: int in range(length):
			var tile: Vector2i = start + (
				Vector2i(step, 0) if along_x else Vector2i(0, step)
			)
			if keep_clear.has(tile):
				continue
			_place_on_tile(rng, sim, "catwalk_span", tile, tile_size, yaw, CATWALK_DECK_METRES)
			_place_on_tile(rng, sim, "railing", tile, tile_size, yaw, CATWALK_DECK_METRES)
			if step % 3 == 1:
				_place_on_tile(rng, sim, "catwalk_leg", tile, tile_size, yaw)


## The fence, the bollards and the lamp masts, just outside the last buildable
## tile. Untiled: nothing can be built out here, so nothing clears it.
func _lay_out_perimeter(rng: DeterministicRng, extent: int, tile_size: float) -> void:
	var edge: float = float(extent + PERIMETER_OFFSET_TILES) * tile_size
	var panels: int = (extent + PERIMETER_OFFSET_TILES)
	var sides: Array = [
		{"normal": Vector3(0.0, 0.0, -1.0), "yaw": 0.0},
		{"normal": Vector3(0.0, 0.0, 1.0), "yaw": PI},
		{"normal": Vector3(-1.0, 0.0, 0.0), "yaw": TAU * 0.25},
		{"normal": Vector3(1.0, 0.0, 0.0), "yaw": -TAU * 0.25},
	]
	for side: Dictionary in sides:
		var normal: Vector3 = side["normal"]
		var across: Vector3 = Vector3(-normal.z, 0.0, normal.x)
		for panel: int in range(-panels, panels):
			# A gate's worth of gap now and then, so the fence is a boundary rather
			# than a wall and the eye has somewhere to go through it.
			if posmod(panel, PERIMETER_GAP_IN) == 0:
				continue
			var at: Vector3 = normal * edge + across * (float(panel) * tile_size + tile_size * 0.5)
			_place_loose(rng, "fence", at, side["yaw"], 1.0)
			if posmod(panel, PERIMETER_MAST_EVERY_PANELS) == 0:
				_place_loose(rng, "mast", at - normal * 1.6, side["yaw"], 1.0)
			elif posmod(panel, 5) == 0:
				_place_loose(rng, "bollard", at - normal * 1.6, side["yaw"], 1.0)
			elif posmod(panel, 13) == 3:
				_place_loose(rng, "barrier", at - normal * 2.4, side["yaw"], 1.0)


## Big shapes past the fence. Scaled up a little and jittered, because five
## repeats of one silo at one size reads as wallpaper.
func _lay_out_skyline(rng: DeterministicRng, extent: int, tile_size: float) -> void:
	var inner: float = float(extent + PERIMETER_OFFSET_TILES + SKYLINE_NEAR_TILES) * tile_size
	var outer: float = float(extent + PERIMETER_OFFSET_TILES + SKYLINE_FAR_TILES) * tile_size
	for which: int in range(SKYLINE_COUNT):
		var angle: float = float(rng.next_below(36000)) / 36000.0 * TAU
		var radius: float = inner + (outer - inner) * (float(rng.next_below(1000)) / 1000.0)
		var at: Vector3 = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		# A square yard with a round fence would be odd, so the ring is pushed out
		# to the fence's own corner distance before it is used.
		if absi(int(at.x)) < int(inner) and absi(int(at.z)) < int(inner):
			continue
		var turn: float = float(rng.next_below(4)) * TAU * 0.25
		_place_loose(rng, "skyline", at, turn, 1.0 + float(rng.next_below(120)) / 100.0)


## One prop standing on a tile inside the Map, which means it is cleared when that
## tile is built on.
func _place_on_tile(
	rng: DeterministicRng,
	sim: Simulation,
	kind: String,
	tile: Vector2i,
	tile_size: float,
	yaw: float,
	lift: float = 0.0
) -> void:
	var centre: FixedVec2 = sim.query_tile_centre_metres(Vector3i(tile.x, 0, tile.y))
	var at: Vector3 = Vector3(
		Fixed.to_float(centre.x), lift, Fixed.to_float(centre.z)
	)
	# A quarter turn off the grid for anything scattered, so a yard of crates does
	# not read as a lattice. A run keeps the yaw it was given.
	var turn: float = yaw
	if kind == "clutter" or kind == "yard_gear" or kind == "stain":
		turn = float(rng.next_below(4)) * TAU * 0.25
	_placements.append({
		"kind": kind,
		"variant": _pick_variant(rng, kind),
		"where": at,
		"yaw": turn,
		"scale": 1.0,
		"tile": Vector3i(tile.x, 0, tile.y),
		"tiled": true,
	})


func _place_loose(
	rng: DeterministicRng, kind: String, at: Vector3, yaw: float, scale: float
) -> void:
	_placements.append({
		"kind": kind,
		"variant": _pick_variant(rng, kind),
		"where": at,
		"yaw": yaw,
		"scale": scale,
		"tile": Vector3i.ZERO,
		"tiled": false,
	})


func _pick_variant(rng: DeterministicRng, kind: String) -> String:
	var variants: Array = KINDS[kind]
	return variants[rng.next_below(variants.size())]


# ── Drawing ───────────────────────────────────────────────────────────────────


## What the Factory covers, as one number. Cheap to compute and it changes exactly
## when something is built or destroyed, which is exactly when the yard has to be
## filtered again.
func _occupancy_signature(sim: Simulation) -> int:
	return (
		sim.query_machine_count() * 1_000_003
		+ sim.query_belt_count() * 10_007
		+ sim.query_wall_count() * 101
		+ sim.query_breach_count()
	)


func _fill_pools(sim: Simulation) -> void:
	var built_on: Dictionary = _built_on(sim)
	var grouped: Dictionary = {}
	for placement: Dictionary in _placements:
		if placement["tiled"] and built_on.has(placement["tile"]):
			continue
		var key: String = _group_key(placement)
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(placement)

	_drawn = []
	for key: String in _pools:
		var pool: MultiMeshInstance3D = _pools[key]
		var entries: Array = grouped.get(key, [])
		_write_pool(pool, entries)
		_drawn.append_array(entries)
	for key: String in grouped:
		if _pools.has(key):
			continue
		var pool: MultiMeshInstance3D = _make_pool(key)
		if pool == null:
			continue
		_write_pool(pool, grouped[key])
		_drawn.append_array(grouped[key] as Array)


## Every tile the Factory stands on, as a set.
##
## **Walked from the Factory rather than asked per prop**, which is the lesson
## `Simulation._mark_obstructions` already wrote down and this file re-learned by
## measuring. Asking `query_machine_at_tile` once per placement is
## O(props x Machines) — fifteen hundred props against thirty Machines, fifty
## Walls and a Belt each — and it cost **39 ms on the frame after a build**, which
## is a two-frame hitch every time a player puts something down. Building the set
## first is O(Machines + Belts + Walls) once and a Dictionary lookup per prop.
func _built_on(sim: Simulation) -> Dictionary:
	var taken: Dictionary = {}
	for index: int in range(sim.query_machine_count()):
		var anchor: Vector3i = sim.query_machine_tile(index)
		var declared: Vector2i = sim.query_machine_footprint(index)
		var covered: Vector2i = WorldGrid.rotated_footprint(
			declared.x, declared.y, sim.query_machine_rotation(index)
		)
		for x: int in range(covered.x):
			for z: int in range(covered.y):
				taken[anchor + Vector3i(x, 0, z)] = true
	for index: int in range(sim.query_belt_count()):
		for step: int in range(sim.query_belt_length_tiles(index)):
			taken[sim.query_belt_tile(index, step)] = true
	for index: int in range(sim.query_wall_count()):
		taken[sim.query_wall_tile(index)] = true
	for index: int in range(sim.query_node_count()):
		taken[sim.query_node_tile(index)] = true
	var nest: Vector3i = sim.query_nest_tile()
	var footprint: Vector2i = sim.query_nest_footprint()
	for x: int in range(footprint.x):
		for z: int in range(footprint.y):
			taken[nest + Vector3i(x, 0, z)] = true
	return taken


## The group a placement draws in: its own purchased prop if that prop is on disk,
## and the kind's stand-in if it is not. Resolving per *placement* rather than per
## kind is what lets a partial conversion work — a pack that is there and a pack
## that is not, in the same yard.
func _group_key(placement: Dictionary) -> String:
	if _prop_mesh(placement["variant"]) != null:
		return placement["variant"]
	return "stand-in:%s" % placement["kind"]


func _make_pool(key: String) -> MultiMeshInstance3D:
	var mesh: Mesh = null
	var material: Material = null
	if key.begins_with("stand-in:"):
		var built: Array = _stand_in_for(key.substr("stand-in:".length()))
		mesh = built[0]
		material = built[1]
	else:
		mesh = _prop_mesh(key)
		material = _purchased_material()
	if mesh == null:
		return null

	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var instanced: MultiMesh = MultiMesh.new()
	instanced.transform_format = MultiMesh.TRANSFORM_3D
	instanced.mesh = mesh
	node.multimesh = instanced
	node.material_override = material
	# Decoration does not get to cast the shadow that tells a player where a
	# Machine is, but it does get to receive one, and it casts onto the ground —
	# which is most of what stops a crate looking like a sticker.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node)
	_pools[key] = node
	_group_meshes[key] = mesh
	return node


func _write_pool(pool: MultiMeshInstance3D, entries: Array) -> void:
	pool.multimesh.instance_count = entries.size()
	pool.visible = entries.size() > 0
	if entries.is_empty():
		return
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(entries.size() * FLOATS_PER_INSTANCE)
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		_write_instance(
			buffer, index, entry["where"], entry["yaw"], float(entry["scale"])
		)
	pool.multimesh.buffer = buffer


static func _write_instance(
	buffer: PackedFloat32Array, instance: int, where: Vector3, yaw: float, scale: float
) -> void:
	var base: int = instance * FLOATS_PER_INSTANCE
	var along: float = sin(yaw) * scale
	var across: float = cos(yaw) * scale
	buffer[base + 0] = across
	buffer[base + 1] = 0.0
	buffer[base + 2] = along
	buffer[base + 3] = where.x
	buffer[base + 4] = 0.0
	buffer[base + 5] = scale
	buffer[base + 6] = 0.0
	buffer[base + 7] = where.y
	buffer[base + 8] = -along
	buffer[base + 9] = 0.0
	buffer[base + 10] = across
	buffer[base + 11] = where.z


# ── The purchased props ───────────────────────────────────────────────────────


## One prop's mesh, loaded once. `null` — and cached as null — when the file is
## not there, which on a clone without the packs is every one of them.
func _prop_mesh(prop_id: String) -> Mesh:
	if _prop_meshes.has(prop_id):
		return _prop_meshes[prop_id]
	_prop_meshes[prop_id] = null
	var path: String = "%s%s.glb" % [PROP_DIRECTORY, prop_id]
	if not FileAccess.file_exists(path):
		return null
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		push_warning("set dressing %s did not parse as glTF" % path)
		return null
	var loaded: Node = document.generate_scene(state)
	if loaded == null:
		push_warning("set dressing %s carried no scene" % path)
		return null
	var merged: ArrayMesh = ArrayMesh.new()
	_collect(loaded, Transform3D.IDENTITY, merged)
	loaded.queue_free()
	if merged.get_surface_count() == 0:
		return null
	_prop_meshes[prop_id] = merged
	return merged


## Flatten a loaded prop into one mesh in its own space. A pack's prop is a few
## nodes with transforms on them; a MultiMesh draws one mesh, so the transforms
## have to be baked in rather than carried.
func _collect(node: Node, parent: Transform3D, into: ArrayMesh) -> void:
	var here: Transform3D = parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	if node is MeshInstance3D:
		var source: Mesh = (node as MeshInstance3D).mesh
		if source != null:
			for surface: int in range(source.get_surface_count()):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.append_from(source, surface, here)
				tool.commit(into)
	for child: Node in node.get_children():
		_collect(child, here, into)


## The one material every purchased prop wears.
##
## The heyheythere pack bakes its occlusion into vertex colours and puts every one
## of its 213 props on a single 2048 atlas with a second map for the things that
## glow, so one material over that pair draws the whole yard. The conversion
## stripped the image out of each GLB precisely so this could be built once here
## rather than forty times by the importer.
func _purchased_material() -> StandardMaterial3D:
	if _shared_material != null:
		return _shared_material
	_shared_material = StandardMaterial3D.new()
	_shared_material.vertex_color_use_as_albedo = true
	_shared_material.roughness = 1.0
	_shared_material.metallic = 0.0
	_shared_material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	)
	var albedo: Texture2D = _runtime_texture("atlas.png")
	if albedo != null:
		_shared_material.albedo_texture = albedo
	var glow: Texture2D = _runtime_texture("atlas_glow.png")
	if glow != null:
		# The lamps in the pack are lit by this map and nothing else. A yard lamp
		# that is dark at dusk is a yard lamp that reads as scenery rather than as
		# a light, and the glow map costs one texture for the whole set.
		_shared_material.emission_enabled = true
		_shared_material.emission_texture = glow
		# **Multiply, not add.** Godot's default emission operator *adds* the colour to
		# the map, so a warm tint with a mostly-black glow atlas does not light the
		# lamps — it lights the whole yard, every crate and pallet glowing cream at an
		# albedo the sun then cannot darken. Multiplying makes the tint what the lit
		# texels are coloured *by*, which is what a glow map is for, and leaves every
		# black texel at zero.
		_shared_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_shared_material.emission_energy_multiplier = 2.2
		_shared_material.emission = Color(1.0, 0.86, 0.62)
	return _shared_material


## Load a PNG from the gitignored prop directory. `load()` cannot: the importer
## never saw these files, because Godot is kept out of the quarantine entirely.
func _runtime_texture(file_name: String) -> Texture2D:
	var path: String = PROP_DIRECTORY + file_name
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.new()
	# `Image.load` wants a path on the filesystem. `res://` resolves for it while the
	# project is running from a directory and does not once it is packed, and this
	# directory is outside the pack either way — so the path is globalised, which is the
	# honest form of what is being asked for: a file beside the game rather than in it.
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		push_warning("set dressing could not read %s" % path)
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# ── The stand-ins ─────────────────────────────────────────────────────────────


## What a kind looks like with no pack behind it: a mesh and one of the Machines'
## own materials.
##
## Deliberately plain. The claim this file makes is that a clone without the packs
## is *coherent*, not that it is as good — so a crate is a crate-sized box in
## olive drab, a pipe is a pipe-sized cylinder in oiled steel, and the yard has
## the same shape, the same density and the same silhouette as the purchased one.
func _stand_in_for(kind: String) -> Array:
	if _stand_in_cache.has(kind):
		return _stand_in_cache[kind]
	var built: Array = [null, null]
	match kind:
		"clutter":
			built = [_box(Vector3(0.95, 0.8, 0.95), 0.4), _material("CastIron")]
		"stain":
			built = [_box(Vector3(1.7, 0.02, 1.7), 0.01), _material("Soot")]
		"yard_gear":
			built = [_box(Vector3(1.7, 1.1, 0.9), 0.55), _material("OxideRed")]
		"pipe_leg":
			built = [_box(Vector3(0.3, 3.3, 0.3), 1.65), _material("WeldedSteel")]
		"pipe_span":
			built = [_pipe(0.17, 2.0, 3.15), _material("OiledSteel")]
		"pipe_riser":
			built = [_pipe(0.2, 4.0, 2.0, true), _material("OiledSteel")]
		"pipe_elbow":
			built = [_box(Vector3(0.36, 0.36, 0.36), 3.15), _material("OiledSteel")]
		"lamp":
			built = [_box(Vector3(0.5, 0.3, 0.5), 2.95), _material("HazardYellow")]
		"railing":
			built = [_box(Vector3(0.06, 1.1, 2.0), 0.55), _material("WeldedSteel")]
		"catwalk_span":
			built = [_box(Vector3(1.1, 0.12, 2.0), 0.06), _material("HazardYellow")]
		"catwalk_leg":
			built = [_box(Vector3(0.22, 3.8, 0.22), 1.9), _material("WeldedSteel")]
		"fence":
			built = [_box(Vector3(2.0, 2.0, 0.08), 1.0), _material("WeldedSteel")]
		"barrier":
			built = [_box(Vector3(2.0, 0.9, 0.6), 0.45), _material("HazardYellow")]
		"bollard":
			built = [_pipe(0.14, 1.1, 0.55, true), _material("HazardYellow")]
		"mast":
			built = [_box(Vector3(0.26, 6.0, 0.26), 3.0), _material("CastIron")]
		"skyline":
			built = [_pipe(1.7, 7.0, 3.5, true), _material("CastIron")]
		_:
			built = [_box(Vector3(1.0, 1.0, 1.0), 0.5), _material("CastIron")]
	_stand_in_cache[kind] = built
	return built


## A box standing on the ground, `lift` metres from its own centre to its feet.
func _box(size: Vector3, lift: float) -> Mesh:
	var block: BoxMesh = BoxMesh.new()
	block.size = size
	return _lifted(block, lift)


## A cylinder, upright or lying along X, with its centre `lift` above the ground.
func _pipe(radius: float, length: float, lift: float, upright: bool = false) -> Mesh:
	var tube: CylinderMesh = CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = length
	tube.radial_segments = 10
	tube.rings = 1
	var placed: Transform3D = Transform3D.IDENTITY
	if not upright:
		placed = placed.rotated(Vector3.FORWARD, TAU * 0.25)
	placed.origin = Vector3(0.0, lift, 0.0)
	return _baked(tube, placed)


func _lifted(mesh: Mesh, lift: float) -> Mesh:
	return _baked(mesh, Transform3D(Basis.IDENTITY, Vector3(0.0, lift, 0.0)))


## Bake a transform into a mesh's vertices. A MultiMesh instance carries a yaw and
## a uniform scale and nothing else, so anything that has to be tipped on its side
## or stood on its feet has to arrive that way.
func _baked(mesh: Mesh, placed: Transform3D) -> Mesh:
	var out: ArrayMesh = ArrayMesh.new()
	for surface: int in range(mesh.get_surface_count()):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.append_from(mesh, surface, placed)
		tool.commit(out)
	return out


func _material(name: String) -> Material:
	if _material_cache.has(name):
		return _material_cache[name]
	var loaded: Material = load("%s%s.tres" % [MATERIAL_DIRECTORY, name]) as Material
	_material_cache[name] = loaded
	return loaded
