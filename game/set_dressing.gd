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
## ── Four things it is careful about ──────────────────────────────────────────
##
## **It is arranged, not scattered** (#42). The layout decides where the *roads*
## are first — a lane from the Nest to every Node and every Breach — and places
## everything else with respect to them: bays at the kerb with their long side
## running with the traffic and every prop in one facing the same way, pipe runs
## and catwalks *along* a lane rather than across it, and the lanes themselves
## kept clear. See the lane and bay constants below for the argument. A yard is
## not a distribution of props, and the first pass was exactly that.
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

## The purchased props that are *painted*, and the only hazard colour in the
## yard. Small, free-standing, and the two kinds whose stand-ins already wear the
## palette's `HazardYellow` — see `_hazard_material` for why the list is two
## entries long and not twenty.
const HAZARD_PROPS: Array = ["bollard", "jersey_barrier"]

## How much brighter than the palette's own hazard material a painted prop is
## multiplied, because the graded atlas underneath it is darker than the tread
## plate that material was written for.
const HAZARD_GAIN: float = 2.4

## How far from the Nest, and from each Node, the yard keeps clear, in tiles. A
## player's first act is to put a Miner on a Node and their Factory grows out of
## the Nest, so those two are where dressing is most in the way and least wanted.
const NEST_CLEARANCE_TILES: int = 8
const NODE_CLEARANCE_TILES: int = 4

## ── Lanes: what the yard is arranged *along* (#42) ──────────────────────────
##
## The playtest's words were *"please clean up the world so it isn\'t just
## scattered objects"*, and scattered is exactly what the first pass was: every
## pile fell at a random angle and a random radius from its anchor, so the yard
## had density and no **arrangement**. A real site is not a distribution of props.
## Things line up along something, they cluster for a reason, and the reason is
## almost always a route: stock goes down the side of the road it arrived on,
## pipes run beside the way rather than across it, and the middle stays empty
## because that is where the traffic is.
##
## So the layout now starts by deciding where the **roads** are. A lane runs from
## the Nest to each Node and each Breach, cornered like a Belt route because the
## grid has four directions and a diagonal road on a 2 m grid is a lie. They are
## the one thing in this file that is kept clear outright, and everything else is
## placed *with respect to* them — which is what turns two hundred props from a
## scatter into a yard.
##
## They are also, straightforwardly, the paths a player walks. The Nest is where a
## Run starts and the Nodes are where it goes first, so a clear axis-aligned route
## between them is the ground a player was going to need anyway.
const LANE_HALF_WIDTH_TILES: int = 2

## How far to the side of a lane a bay stands, in tiles, measured from the lane's
## centre line. Just outside the clear width, so stock is stacked at the kerb.
const BAY_OFFSET_LOW_TILES: int = 3
const BAY_OFFSET_HIGH_TILES: int = 6

## ── Bays: a cluster with a shape and a reason ───────────────────────────────
##
## A bay is a filled rectangle of tiles, **aligned to the grid**, with its long
## side parallel to the lane it stands beside and every prop in it sharing one
## yaw. That last clause is most of the effect: a pile of crates each turned a
## different quarter reads as spill, and the same crates all facing the same way
## read as stock. The first pass turned every scattered prop at random for the
## stated reason that a lattice reads as a lattice, which is true of a prop every
## eighty tiles and false of six crates against a kerb.
##
## The rows are **sorted by height**, tall at the back. A bay's far row from the
## lane takes `yard_gear` — racking, shelving, a skip, a pressure vessel — and the
## rows in front take `clutter`. That is the whole of "clusters with a reason":
## you can see what the bay is for, because you can see what is stored at the back
## of it and what is being worked at the front.
const BAYS_PER_LANE: int = 4
const BAY_WIDTH_LOW_TILES: int = 3
const BAY_WIDTH_HIGH_TILES: int = 6
## One or two tiles deep. **A rack is a line, not a block** — a render of the first
## attempt put a three-deep bay in the near field and it read as a wall of boxes
## across the view, which is a different way of being in the player's way.
const BAY_DEPTH_LOW_TILES: int = 1
const BAY_DEPTH_HIGH_TILES: int = 2
## How many tiles of a bay are left empty, as a share of its area rather than a
## flat count, so a six-wide bay is as loosely packed as a three-wide one. A third:
## a solid rectangle reads as a wall and a rectangle with holes in it reads as a
## rack somebody has been taking things off.
const BAY_EMPTY_IN: int = 3

## How often a bay reaches past its own primary prop for something else, as one in
## N. **A bay is mostly one thing**, which is the "cluster by purpose" half: a bay
## of drums reads as drums waiting to go somewhere, and the same tiles drawn one
## each from twenty-five kinds read as the scatter this is replacing. The minority
## matters too — a rack with nothing but drums on it is a texture.
const BAY_ODD_ONE_OUT_IN: int = 4

## Bays with no lane: out in the far ground, aligned to the grid\'s own axes rather
## than to a route, because the far corners of a Map have no traffic to line up
## with and an axis-aligned pile still reads as placed.
const LOOSE_BAY_COUNT: int = 26

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
## **Per lane rather than per anchor, and fewer of them** (#42). A run used to start at
## a random bearing from an anchor and take a random axis, so half of them crossed the
## way a player walks and one of them was usually doing it in the opening frame. They now
## run beside a lane and with it — see `_lay_out_pipe_runs` — and a number that was
## tuned to fill an empty plain is too high once they are all lined up along the roads.
const PIPE_RUNS_PER_LANE: int = 1
const PIPE_RUN_TILES_LOW: int = 6
const PIPE_RUN_TILES_HIGH: int = 13
const CATWALK_RUNS_PER_LANE: int = 1
const CATWALK_RUN_TILES_LOW: int = 5
const CATWALK_RUN_TILES_HIGH: int = 11
const CATWALK_DECK_METRES: float = 3.8

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
var _hazard_shared_material: StandardMaterial3D = null
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


## Which way it is facing, in radians. The readable half of #42's arrangement: a yard
## where everything in a bay faces one way is the claim, and a yaw a test cannot see is
## a claim nobody can assert.
func instance_yaw(index: int) -> float:
	if index < 0 or index >= _drawn.size():
		return 0.0
	return (_drawn[index] as Dictionary)["yaw"]


## The tiles the yard keeps clear for traffic: the lanes from the Nest to every Node and
## every Breach, out to `LANE_HALF_WIDTH_TILES` either side.
##
## Public because it is a fact about the yard worth asserting and worth reading — "where
## has this left room to walk" is the half of the arrangement a player feels rather than
## sees. A pure function of the Map, like everything else here, and it tells the
## Simulation nothing.
func clear_lane_tiles(sim: Simulation) -> Array:
	var extent: int = sim.query_grid_half_extent_tiles()
	var tiles: Array = []
	for lane: Dictionary in _lanes(sim, extent, _anchors(sim)):
		tiles.append_array(_lane_tiles(lane, LANE_HALF_WIDTH_TILES))
	return tiles


## Whether any purchased prop was found. False on a clone without the packs, which
## is the ordinary case and not a failure.
func uses_purchased_props() -> bool:
	for key: String in _group_meshes:
		if not key.begins_with("stand-in:"):
			return true
	return false


## Whether the purchased props' shared atlas resolved, so the yard is textured
## rather than vertex-coloured.
##
## The companion to `uses_purchased_props`, and it is a *separate* question from
## it: the meshes come out of GLB files and the atlas out of two PNGs, by two
## different loaders, and one of those routes can fail while the other does not —
## which is exactly what an exported build did until `_runtime_texture` stopped
## globalising its path. A yard built out of purchased props wearing no texture is
## the degraded build this is here to make visible, so `tools/release/`'s
## verification pass asserts this and not only the meshes.
func uses_purchased_atlas() -> bool:
	var material: StandardMaterial3D = _purchased_material()
	return material.albedo_texture != null and material.emission_texture != null


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
	var anchors: Array = _anchors(sim)
	# **The roads come first and everything else is placed against them.** See the
	# lane constants: this is the one ordering decision that turns the scatter into
	# an arrangement, because a bay, a pipe run and a catwalk all want to know which
	# way the traffic goes before they know where they stand.
	var lanes: Array = _lanes(sim, extent, anchors)
	var keep_clear: Dictionary = _keep_clear(sim, extent, lanes)

	_lay_out_stains(rng, sim, extent, tile_size, anchors)
	_lay_out_bays(rng, sim, extent, tile_size, keep_clear, lanes)
	_lay_out_pipe_runs(rng, sim, extent, tile_size, keep_clear, lanes)
	_lay_out_catwalks(rng, sim, extent, tile_size, keep_clear, lanes)
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


## The roads: one route from the Nest to every other anchor, cornered on the grid.
##
## **This is what the yard is arranged along** (#42) — see the lane constants. The route
## is an L rather than a diagonal for the reason a Belt route is: the grid has four
## directions and a diagonal road on a 2 m grid is a thing a player cannot walk straight
## down.
##
## A segment is `{from, to, along_x}`, with `from` and `to` sharing the axis the run is
## *not* along. Only non-empty segments are kept, so an anchor that happens to share a row
## with the Nest produces one leg rather than two and a zero-length one.
func _lanes(sim: Simulation, extent: int, anchors: Array) -> Array:
	if anchors.is_empty():
		return []
	var from_nest: Vector2i = anchors[0]
	var routes: Array = []
	for index: int in range(1, anchors.size()):
		var to: Vector2i = anchors[index]
		# Which leg runs first — the one choice a route has. Read off the anchor's own
		# coordinates rather than off the stream, because this is geography: two Nodes on
		# the same bearing should not get different answers, and a yard whose roads were
		# rolled for reads as rolled for.
		var corner_first_along_x: bool = ((to.x + to.y) & 1) == 0
		var corner: Vector2i = (
			Vector2i(to.x, from_nest.y) if corner_first_along_x
			else Vector2i(from_nest.x, to.y)
		)
		_add_lane(routes, from_nest, corner, extent)
		_add_lane(routes, corner, to, extent)
	return routes


## One leg, clamped to the Map and dropped if it has no length.
func _add_lane(routes: Array, from_tile: Vector2i, to_tile: Vector2i, extent: int) -> void:
	var a: Vector2i = Vector2i(
		clampi(from_tile.x, -extent, extent), clampi(from_tile.y, -extent, extent)
	)
	var b: Vector2i = Vector2i(
		clampi(to_tile.x, -extent, extent), clampi(to_tile.y, -extent, extent)
	)
	if a == b:
		return
	routes.append({"from": a, "to": b, "along_x": a.y == b.y})


## Every tile a lane covers, out to `half_width` either side of its centre line.
func _lane_tiles(lane: Dictionary, half_width: int) -> Array:
	var a: Vector2i = lane["from"]
	var b: Vector2i = lane["to"]
	var along_x: bool = lane["along_x"]
	var low: int = mini(a.x, b.x) if along_x else mini(a.y, b.y)
	var high: int = maxi(a.x, b.x) if along_x else maxi(a.y, b.y)
	var across: int = a.y if along_x else a.x
	var tiles: Array = []
	for along: int in range(low, high + 1):
		for side: int in range(-half_width, half_width + 1):
			tiles.append(
				Vector2i(along, across + side) if along_x
				else Vector2i(across + side, along)
			)
	return tiles


## Somewhere alongside a lane, facing it: where a bay, a pipe run or a catwalk is built
## from.
##
## Returns `{at, along_x, facing}` — where it stands, which way the traffic runs past it,
## and the yaw that turns a prop towards the road. **`facing` is the point.** A crate
## turned towards the road reads as stock waiting to be picked up; the same crate turned
## at random reads as something that fell off a lorry, and two hundred of those read as
## the complaint this ticket is answering.
func _beside_a_lane(rng: DeterministicRng, lanes: Array, extent: int) -> Dictionary:
	var lane: Dictionary = lanes[rng.next_below(lanes.size())]
	var a: Vector2i = lane["from"]
	var b: Vector2i = lane["to"]
	var along_x: bool = lane["along_x"]
	var low: int = mini(a.x, b.x) if along_x else mini(a.y, b.y)
	var high: int = maxi(a.x, b.x) if along_x else maxi(a.y, b.y)
	var across: int = a.y if along_x else a.x
	var along: int = rng.next_range(low, high)
	var side: int = 1 if rng.next_below(2) == 0 else -1
	var offset: int = side * rng.next_range(BAY_OFFSET_LOW_TILES, BAY_OFFSET_HIGH_TILES)
	var at: Vector2i = (
		Vector2i(along, across + offset) if along_x else Vector2i(across + offset, along)
	)
	# Facing back at the lane: a run along X is looked at from the north or the south, a
	# run along Z from the east or the west.
	var facing: float = 0.0
	if along_x:
		facing = 0.0 if side > 0 else TAU * 0.5
	else:
		facing = TAU * 0.25 if side > 0 else TAU * 0.75
	return {
		"at": Vector2i(
			clampi(at.x, -extent + 2, extent - 2), clampi(at.y, -extent + 2, extent - 2)
		),
		"along_x": along_x,
		"facing": facing,
	}


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
func _keep_clear(sim: Simulation, extent: int, lanes: Array) -> Dictionary:
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
	# **The lanes.** Kept clear outright, which is the half of #42's "clear ground
	# where a player works" that no amount of better scattering would have bought:
	# a route is only a route if it is empty, and a player walking the Nest-to-Node
	# line is the single commonest thing anybody does in a Run.
	for lane: Dictionary in lanes:
		for tile: Vector2i in _lane_tiles(lane, LANE_HALF_WIDTH_TILES):
			clear[tile] = true
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


## The yard's stock, in bays rather than in piles.
##
## A bay is a filled rectangle of tiles aligned to the grid, standing at the kerb of a
## lane with every prop in it sharing one yaw. See the bay constants for why that is most
## of the effect; what follows is how it is built.
##
## - **The long side runs with the traffic.** A bay beside an east-west lane is wide
##   east-west, because that is how a rack is set down beside a road and because a bay
##   lying across the road would read as a blockage.
## - **Tall at the back.** The row furthest from the lane takes `yard_gear` — racking,
##   shelving, a skip, a pressure vessel — and the rows in front take `clutter`. That is
##   the whole of "clusters with a reason": what the bay is for is visible from the road.
## - **Gaps, counted rather than rolled per tile.** A solid rectangle of boxes reads as a
##   wall; a rectangle with three holes in it reads as a rack somebody has been taking
##   things off.
## - **Nothing lands on a kept-clear tile**, which now includes the lanes themselves, so a
##   bay can never close the road it is standing beside.
func _lay_out_bays(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	lanes: Array
) -> void:
	var taken: Dictionary = {}
	for lane: Dictionary in lanes:
		for which: int in range(BAYS_PER_LANE):
			var spot: Dictionary = _beside_a_lane(rng, lanes, extent)
			_lay_out_one_bay(
				rng, sim, extent, tile_size, keep_clear, taken,
				spot["at"], spot["along_x"], spot["facing"]
			)
	# The far ground. No lane to line up with out here, so the bays take the grid's own
	# axes — which still reads as placed, because the thing the eye objects to is not
	# regularity but its absence.
	for which: int in range(LOOSE_BAY_COUNT):
		var at: Vector2i = Vector2i(
			rng.next_range(-extent + 4, extent - 4), rng.next_range(-extent + 4, extent - 4)
		)
		var along_x: bool = rng.next_below(2) == 0
		var facing: float = float(rng.next_below(2)) * TAU * 0.5
		if not along_x:
			facing += TAU * 0.25
		_lay_out_one_bay(
			rng, sim, extent, tile_size, keep_clear, taken, at, along_x, facing
		)


## One bay: a `width` x `depth` rectangle from `at`, filled row by row, tall row first.
func _lay_out_one_bay(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	taken: Dictionary,
	at: Vector2i,
	along_x: bool,
	facing: float
) -> void:
	var width: int = rng.next_range(BAY_WIDTH_LOW_TILES, BAY_WIDTH_HIGH_TILES)
	var depth: int = rng.next_range(BAY_DEPTH_LOW_TILES, BAY_DEPTH_HIGH_TILES)
	var cells: int = maxi(width * depth, 1)
	# Which cells are empty, drawn before the walk so the number of gaps is a number.
	# Rolling per tile instead would make it a thing to hope for, and a bay that came up
	# solid is the wall of boxes this is here to prevent.
	@warning_ignore("integer_division")
	var gaps: int = maxi(cells / BAY_EMPTY_IN, 1)
	var skipped: Dictionary = {}
	for which: int in range(gaps):
		skipped[rng.next_below(cells)] = true

	# **What this bay is mostly made of.** One draw per bay rather than one per tile —
	# see `BAY_ODD_ONE_OUT_IN`.
	var mostly_clutter: String = _pick_variant(rng, "clutter")
	var mostly_gear: String = _pick_variant(rng, "yard_gear")

	# The long side runs with the traffic; the depth runs away from the lane. `backwards`
	# is which way "away" is, read off the facing, so the tall row is the far one.
	var along: Vector2i = Vector2i(1, 0) if along_x else Vector2i(0, 1)
	var backwards: Vector2i = (
		Vector2i(0, 1) if along_x else Vector2i(1, 0)
	) * (1 if (facing < TAU * 0.25 or facing > TAU * 0.6) else -1)

	var cell: int = -1
	for row: int in range(depth):
		# The back row is the deep one, and it is where the tall stock goes.
		var kind: String = "yard_gear" if row == depth - 1 and depth > 1 else "clutter"
		for column: int in range(width):
			cell += 1
			if skipped.has(cell):
				continue
			var tile: Vector2i = at + along * column + backwards * row
			if (
				keep_clear.has(tile)
				or taken.has(tile)
				or absi(tile.x) > extent
				or absi(tile.y) > extent
			):
				continue
			taken[tile] = true
			var primary: String = mostly_gear if kind == "yard_gear" else mostly_clutter
			_place_on_tile(
				rng,
				sim,
				kind,
				tile,
				tile_size,
				facing,
				0.0,
				"" if rng.next_below(BAY_ODD_ONE_OUT_IN) == 0 else primary
			)


## A run of overhead pipe: a rack every two tiles with a section spanning between them,
## straight along one axis. The pieces carry their own heights, so the run is at the
## height the pack drew it at.
##
## **It runs beside a lane, parallel to it, and it starts from the kerb** (#42). The old
## version took a random point on a ring around an anchor and a random axis, which meant
## that about half of them ran *across* the way a player was walking — and since the
## anchors include the Nest, the commonest single thing in the opening frame of a Run was
## a bright pipe run crossing it at head height. #39 closed with exactly that note and
## called it layout rather than palette. This is that note acted on: a service runs the
## length of a road, on one side of it, because that is where you put one and because it
## leaves the view down the road clear.
func _lay_out_pipe_runs(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	lanes: Array
) -> void:
	if lanes.is_empty():
		return
	for which: int in range(PIPE_RUNS_PER_LANE * lanes.size()):
		var spot: Dictionary = _beside_a_lane(rng, lanes, extent)
		var along_x: bool = spot["along_x"]
		var length: int = rng.next_range(PIPE_RUN_TILES_LOW, PIPE_RUN_TILES_HIGH)
		var step_by: Vector2i = Vector2i(1, 0) if along_x else Vector2i(0, 1)
		# The pack's pipe sections are modelled running along +X, so a run along Z is the
		# quarter turn. Not `spot["facing"]`, which turns a prop to *look at* the lane —
		# a pipe is laid along it.
		var yaw: float = 0.0 if along_x else TAU * 0.25
		var start_at: Vector2i = spot["at"]
		for step: int in range(length):
			var tile: Vector2i = start_at + step_by * step
			if keep_clear.has(tile) or absi(tile.x) > extent or absi(tile.y) > extent:
				continue
			_place_on_tile(rng, sim, "pipe_span", tile, tile_size, yaw)
			if step % 2 == 0:
				_place_on_tile(rng, sim, "pipe_leg", tile, tile_size, yaw)
			# A run comes up out of the ground at one end and turns at the other, so it
			# reads as plumbing rather than as a length of pipe lying in the air.
			if step == 0:
				_place_on_tile(rng, sim, "pipe_riser", tile, tile_size, yaw)
			elif step == length - 1:
				_place_on_tile(rng, sim, "pipe_elbow", tile, tile_size, yaw)
			# A lamp every eight metres of pipe rack. They are the one thing in the yard
			# lit by its own emission map rather than by the sun, which is what makes dusk
			# read as dusk rather than as underexposure — and strung along a road they
			# light the road, which is what yard lighting is for.
			if step % 4 == 2:
				_place_on_tile(rng, sim, "lamp", tile, tile_size, yaw)


## A catwalk: a deck a storey up with a railing on it, on legs. Beside a lane and running
## with it, for the reason a pipe run is — and a catwalk across a road at 3.8 m is the one
## prop in the set that can hide a Machine behind it.
func _lay_out_catwalks(
	rng: DeterministicRng,
	sim: Simulation,
	extent: int,
	tile_size: float,
	keep_clear: Dictionary,
	lanes: Array
) -> void:
	if lanes.is_empty():
		return
	for which: int in range(CATWALK_RUNS_PER_LANE * lanes.size()):
		var spot: Dictionary = _beside_a_lane(rng, lanes, extent)
		var along_x: bool = spot["along_x"]
		var length: int = rng.next_range(CATWALK_RUN_TILES_LOW, CATWALK_RUN_TILES_HIGH)
		var step_by: Vector2i = Vector2i(1, 0) if along_x else Vector2i(0, 1)
		# The pack's catwalk deck runs along its own +Z, so a run along X is the quarter
		# turn and a run along Z is none — the opposite of the pipe sections above.
		var yaw: float = TAU * 0.25 if along_x else 0.0
		for step: int in range(length):
			var tile: Vector2i = spot["at"] + step_by * step
			if keep_clear.has(tile) or absi(tile.x) > extent or absi(tile.y) > extent:
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
	lift: float = 0.0,
	variant: String = ""
) -> void:
	var centre: FixedVec2 = sim.query_tile_centre_metres(Vector3i(tile.x, 0, tile.y))
	var at: Vector3 = Vector3(
		Fixed.to_float(centre.x), lift, Fixed.to_float(centre.z)
	)
	# **A stain, and nothing else, takes a random quarter turn.** Clutter and yard gear
	# used to take one too, on the argument that a yard of crates all facing one way reads
	# as a lattice. That was right about a prop every eighty tiles and wrong about six
	# crates in a bay: #42's complaint was that the world is *scattered*, and a pile whose
	# every member faces a different way is the most scattered thing it is possible to
	# draw. They now keep the yaw their bay was given, which is what turns a pile into
	# stock. A spill has no front, so it keeps the turn.
	var turn: float = yaw
	if kind == "stain":
		turn = float(rng.next_below(4)) * TAU * 0.25
	# A caller that already knows what it wants — a bay, which is mostly one prop — says
	# so; everything else takes a fresh draw. The draw happens either way, so that passing
	# a variant does not change the stream and move every prop placed after it.
	var drawn: String = _pick_variant(rng, kind)
	_placements.append({
		"kind": kind,
		"variant": drawn if variant.is_empty() else variant,
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
		material = _hazard_material() if key in HAZARD_PROPS else _purchased_material()
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
	# **The yard is made of steel, and the light has to agree.** This started at
	# metallic 0 and roughness 1 — a perfect Lambertian — which is the one surface
	# in this world that takes the sun full in the face. Every Machine is
	# `metallic = 1.0`, so a Machine is lit by what it *reflects* and comes out of
	# a filmic tonemap dark; a diffuse crate beside it under a 3.2-energy sun and a
	# 1.7-energy sky comes out near twice as bright from the same albedo. Grading
	# the atlas into the palette's values (`tools/assets/prop_grade.py`) fixed the
	# colour and could not fix that, because it is the BRDF and not the texture:
	# the props were the brightest things in frame for the same reason a white
	# plastic bucket is the brightest thing on a scrapyard.
	#
	# The atlas carries no metallic mask and one number has to do for a pallet and
	# a pipe, so this is a compromise aimed at the pipes, the racking, the drums,
	# the fencing and the catwalks — which is most of the set by area. It puts the
	# props on the same response curve as the Machines, which is what lets the
	# palette's values mean the same thing on both.
	_shared_material.roughness = 0.60
	_shared_material.metallic = 0.72
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


## The shared material again, in the palette's own hazard yellow.
##
## `tools/assets/prop_grade.py` takes the safety yellow out of the atlas
## wholesale — eleven per cent of it was high-visibility yellow, which is a real
## aesthetic and is a present-day refinery's rather than a 1930s yard's. But the
## answer to that is not *no* hazard colour: interwar industry painted bollards
## and kerbs, and a yellow stripe reads as period when everything round it is
## filthy. What was wrong was that the yellow was everywhere and uniformly
## bright, so there was nothing for it to be brighter *than*.
##
## So it comes back here, on `HAZARD_PROPS` and nowhere else, out of the
## palette's own `HazardYellow` — which is the same material the stand-in for
## these kinds already wears, so the two paths now agree about where in a yard
## hazard colour belongs instead of only one of them having an opinion.
func _hazard_material() -> StandardMaterial3D:
	if _hazard_shared_material != null:
		return _hazard_shared_material
	var shared: StandardMaterial3D = _purchased_material()
	_hazard_shared_material = shared.duplicate() as StandardMaterial3D
	var palette: StandardMaterial3D = _material("HazardYellow") as StandardMaterial3D
	if palette == null:
		return _hazard_shared_material
	# `albedo_color` multiplies the atlas, exactly as the palette's own hazard
	# material multiplies the tread plate it is painted over, and for the same
	# reason: the texture carries the surface and the colour carries the paint.
	# The gain is because the graded atlas is darker than that tread plate and a
	# bollard that is merely a browner bollard has not been painted.
	_hazard_shared_material.albedo_color = palette.albedo_color * HAZARD_GAIN
	return _hazard_shared_material


## Load a PNG from the gitignored prop directory. `load()` cannot: the importer
## never saw these files, because Godot is kept out of the quarantine entirely.
##
## **`Image.load_from_file`, not `Image.load` on a globalised path.** The earlier
## form took `ProjectSettings.globalize_path(path)` on the reasoning that the
## quarantine is a directory beside the game rather than something inside the
## pack. A release is where that stops being true: `tools/release/` bundles these
## two atlases *into* the PCK, because the licence permits use in a shipped game
## and forbids shipping the assets loose for extraction — so the atlas is at
## `res://…` and nowhere on the filesystem, `globalize_path` names a file that does
## not exist, and every purchased prop in the exported build renders untextured
## while this function returns null and nothing says a word. `load_from_file` goes
## through `FileAccess`, which resolves a packed path and a loose one alike.
func _runtime_texture(file_name: String) -> Texture2D:
	var path: String = PROP_DIRECTORY + file_name
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.load_from_file(path)
	if image == null:
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
