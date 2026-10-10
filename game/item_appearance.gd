class_name ItemAppearance
extends RefCounted

## What one Item riding a Belt looks like, derived from the definition set.
##
## **There is no Item table in this project and this is not one.** The set of Items is exactly
## what the Recipes mention, interned in sorted order, and nothing in `sim/` names an Item — so
## a look that lived in a list of ids with colours against them would be the second content
## table the whole design refuses. What is derived instead is an Item's **standing**: what the
## Factory does with it. Fired, burned, dug, or made out of something else — four facts about
## the Recipes, the Machine roles and the Gear table, and nothing about any Item's name.
##
## Add an Item to `content/recipes.csv` and it gets a form from how it is produced and consumed,
## with no edit here and none in `game/world_view.gd`.
##
## It lives in `game/` for the reason `Objective`, `BuildChain` and `BuildGun.refusal_text` do: a
## Recipe's inputs are a fact, and "this is what that looks like" is presentation. The Simulation
## does not know the file exists, and asking any of it leaves the state hash where it was.
##
## Every function is static. `RefCounted` with no nodes and no state about the Run at all — one
## step stronger than `EnemyAnimator`, which at least reads a tick.

# ── The forms ─────────────────────────────────────────────────────────────────
# **A closed set, and closed on purpose.** `WorldView` builds one MultiMesh per form, eagerly,
# before anything is on a Belt — so a form is a node and the count has to be a constant rather
# than a function of how many Items the content mentions. That is the bargain
# `EnemyKind.KIND_NAMES` strikes for the swarm: bounded by a constant, so `test_world_view` can
# assert *zero* node growth rather than "no more than one per Item".
#
# Four, because there are four things this Factory does with a solid, and the shipped content
# lands one Item in each — which is what makes a Belt readable rather than merely painted.
# `test_the_shipped_items_land_one_in_each_form` is that claim.
#
# The order is the precedence `form_of` asks them in, and it is load-bearing: see the note on
# each clause.

## Fired: an Item a weapon frame names in its `ammunition_item` column. Brass-cased rounds.
const FORM_MUNITION: int = 0

## Burned: an Item some `role=generator` Machine's Recipe eats. A generator is a crafter that
## makes nothing, so "a generator eats it" is the whole definition of fuel and it needs no
## column of its own. Black lumps.
const FORM_FUEL: int = 1

## Dug: an Item every Recipe that yields it yields out of nothing. A Miner's input is the ground
## under it, so a mining Recipe has no inputs at all, and that *absence* is the definition —
## nothing here reads the word "ore". Rust-red rubble.
const FORM_ORE: int = 2

## Made: an Item some Recipe produces out of something else. Stacked steel plate.
const FORM_STOCK: int = 3

const FORM_COUNT: int = 4

## The palette materials each form wears, indexed by form.
##
## **The palette's own entries, by name, and not colours written here.** `dieselpunk_palette.json`
## is this project's colour authority and `assets/machines/materials/*.tres` is that authority
## compiled into resources the engine can draw — the very files the Walls and every generated
## Machine body already use. So cargo is surfaced out of the same eleven materials the Factory
## is, which is what keeps it in the world rather than on top of it.
##
## **Why a material rather than a per-instance colour**, which is what #73 asked for as its
## minimum. A `MultiMesh` instance colour multiplies *albedo* and carries nothing else, and the
## generated surfaces are physically based and mostly metal: the lighting takes ambient and
## reflections off the sky precisely because a metal lit by an ambient colour has nothing to
## reflect and renders as a dark smear whatever its albedo says. Brass has to be metallic and
## smooth and soot has to be matte and black, and only `metallic` and `roughness` can say so. A
## material per form says all three; an instance colour would have said a third of it.
##
## The four are chosen as the palette entry that is *true* of the form rather than as four
## things that happen to differ: `OxideRed` is the non-metallic rust a raw seam actually is,
## `Soot` is what coal looks like, `DullBrass` is what a cased round is made of, and
## `WeldedSteel` is the plate every build cost in the game is denominated in. That they also
## separate — a near-black, a red, a yellow metal and a neutral metal — is checked rather than
## assumed, by `test_no_two_forms_wear_the_same_surface`.
const FORM_MATERIALS: Array[String] = [
	"DullBrass",  # FORM_MUNITION
	"Soot",  # FORM_FUEL
	"OxideRed",  # FORM_ORE
	"WeldedSteel",  # FORM_STOCK
]

## Where those compiled materials live. The Walls read the same directory.
const MATERIAL_DIRECTORY: String = "res://assets/machines/materials"


## Which of the four forms an Item rides as.
##
## The clauses are asked in `FORM_*` order and the precedence is the design rather than an
## accident — an Item can legitimately answer to more than one standing, and in every case the
## **later** use is the one a player is looking at on the Belt:
##
## - What a weapon fires is a round however the Factory came by it, so a content set that mined
##   its ammunition out of the ground still draws rounds.
## - What a Boiler burns is fuel however it was made, so a content set that *manufactures* its
##   coal still draws black lumps rather than stock.
##
## The shipped content exercises the second pair silently — coal is both dug and burned, and
## one answer is right for two reasons — which is why `test_being_burned_outranks_being_dug`
## removes the dug clause rather than trusting the overlap.
static func form_of(definitions: Definitions, item: int) -> int:
	if definitions == null or item < 0 or item >= definitions.item_count():
		return FORM_STOCK
	var item_id: String = definitions.item_id(item)
	if _is_fired(definitions, item_id):
		return FORM_MUNITION
	if _is_burned(definitions, item):
		return FORM_FUEL
	return FORM_ORE if _comes_out_of_the_ground(definitions, item) else FORM_STOCK


## The palette material a form wears, as a loadable path.
##
## One function rather than a constant per form, so `WorldView` can build its MultiMeshes by
## walking `FORM_COUNT` and never names a form by hand.
static func material_path_of(form: int) -> String:
	var name: String = FORM_MATERIALS[clampi(form, 0, FORM_COUNT - 1)]
	return "%s/%s.tres" % [MATERIAL_DIRECTORY, name]


## Whether any weapon frame spends this Item a shot.
##
## Walks the weapon frames through `weapon_gear_index`, which is the same door
## `PlayerController`'s weapon keys go through, so a fourth weapon is a row here too.
static func _is_fired(definitions: Definitions, item_id: String) -> bool:
	for nth: int in range(definitions.weapon_count()):
		var frame: GearDefinition = definitions.gear_at(definitions.weapon_gear_index(nth))
		if frame != null and frame.ammunition_item == item_id:
			return true
	return false


## Whether some generator's Recipe eats this Item.
##
## Asked of the **Machines** rather than of the Recipes, because fuel is a fact about what burns
## it: `role=generator` is the one thing that distinguishes a Boiler's Recipe from a Smelter's,
## and a Recipe with inputs and no outputs is a Turret's as readily as a generator's.
static func _is_burned(definitions: Definitions, item: int) -> bool:
	for index: int in range(definitions.machine_count()):
		var machine: MachineDefinition = definitions.machine_at(index)
		if machine == null or not machine.is_generator():
			continue
		var recipe: RecipeDefinition = definitions.recipe(machine.recipe_id)
		if recipe == null:
			continue
		for slot: int in range(recipe.input_count()):
			if recipe.input_item(slot) == item:
				return true
	return false


## Whether every Recipe that yields this Item yields it out of nothing.
##
## An Item no Recipe produces at all answers true, and that is right rather than a hole: an Item
## the Factory cannot make is one that arrived from outside it, which is the same claim as coming
## out of the ground and wants the same raw rubble drawn for it.
static func _comes_out_of_the_ground(definitions: Definitions, item: int) -> bool:
	for index: int in range(definitions.recipe_count()):
		var recipe: RecipeDefinition = definitions.recipe_at(index)
		if recipe == null:
			continue
		for slot: int in range(recipe.output_count()):
			if recipe.output_item(slot) == item and recipe.input_count() > 0:
				return false
	return true
