## The contract of what an Item riding a Belt looks like.
##
## `ItemAppearance` has a contract of its own for the reason `BuildChain` and `WeaponAnimator`
## do: it is a leaf in `game/` with no nodes and no state, and what would go wrong with it is
## **silence**. A form that collapsed every Item onto one answer, or four names that resolved
## to the same grey, would draw exactly what shipped before #73 and nothing would go red.
##
## The thing these assertions are really guarding is that **there is no Item table**. Every
## answer below is derived from the definition set the Run is playing by, so the expectations
## are written as the *standing* an Item has — fired, burned, dug, made — rather than as a
## list of ids with looks attached, which is the second content table this must never become.
extends TestCase


func _shipped() -> Definitions:
	return ContentFixture.for_case(self).definitions()


func test_an_item_a_weapon_fires_is_a_munition() -> void:
	# Both ranged frames name `ammunition` in their `ammunition_item` column, and that is what
	# this reads. Nothing here spells the id.
	var content: Definitions = _shipped()
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("ammunition")),
		ItemAppearance.FORM_MUNITION,
		"what a weapon fires rides as a munition"
	)


func test_an_item_a_generator_burns_is_fuel() -> void:
	# `steam_boiler_mk1` is `role=generator` and its Recipe's one input is coal. A generator is
	# a crafter that makes nothing (the Steam Boiler's whole trick), so "some generator eats
	# it" is the definition of fuel and it needs no column of its own.
	var content: Definitions = _shipped()
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("coal")),
		ItemAppearance.FORM_FUEL,
		"what a Boiler burns rides as fuel"
	)


func test_an_item_that_comes_out_of_the_ground_is_ore() -> void:
	# A Miner's input is the ground under it, so a Recipe that yields ore has no inputs at all
	# — that absence is the whole definition, and it is a fact about the Recipe rather than
	# about the word "ore".
	var content: Definitions = _shipped()
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("iron_ore")),
		ItemAppearance.FORM_ORE,
		"iron ore is dug, so it rides as a raw mineral"
	)


func test_an_item_a_recipe_makes_out_of_something_else_is_stock() -> void:
	var content: Definitions = _shipped()
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("iron_plate")),
		ItemAppearance.FORM_STOCK,
		"plate is smelted out of ore, so it rides as finished stock"
	)


func test_the_shipped_items_land_one_in_each_form() -> void:
	# The strongest single assertion here, because it is what makes a Belt readable at all: the
	# four Items the shipped Recipes mention take **four different** forms, so no two lines in
	# the game carry cargo that looks alike. A derivation that collapsed any pair would pass
	# every test above and fail this one.
	var content: Definitions = _shipped()
	var seen: Dictionary = {}
	for item: int in range(content.item_count()):
		var form: int = ItemAppearance.form_of(content, item)
		assert_true(
			form >= 0 and form < ItemAppearance.FORM_COUNT,
			"%s landed outside the forms, at %d" % [content.item_id(item), form]
		)
		assert_false(
			seen.has(form),
			"%s and %s both ride as form %d" % [seen.get(form, ""), content.item_id(item), form]
		)
		seen[form] = content.item_id(item)
	assert_eq(seen.size(), 4, "four shipped Items, four forms")


func test_being_fired_outranks_being_burned_and_being_dug() -> void:
	# The precedence is deliberate and this is the only place it can be asserted: what a weapon
	# fires is a munition whatever else the Factory does with it. Pointed at `coal`, which the
	# shipped Boiler burns — so without the precedence it comes back `FORM_FUEL`, and this is
	# the one override that can tell the two rules apart.
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.gear = ContentFixture.shipped(Definitions.GEAR_FILE).replace(
		"ranged,30,60,0.4,0.8,ammunition,1", "ranged,30,60,0.4,0.8,coal,1"
	)
	var content: Definitions = fixture.definitions()
	assert_false(content.has_errors(), content.describe_errors())
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("coal")),
		ItemAppearance.FORM_MUNITION,
		"a lump a rifle fires is a round, whatever else burns it"
	)


func test_being_burned_outranks_being_dug() -> void:
	# Coal is *both* produced out of nothing and burned by a generator, so the shipped content
	# already exercises this pair — but it exercises it silently, because one answer is right
	# for two reasons. Pointing the Boiler at **iron ore** instead isolates it: ore is dug by
	# the shipped Miner, so without the precedence it comes back `FORM_ORE`.
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.recipes = ContentFixture.shipped(Definitions.RECIPES_FILE).replace(
		"burn_coal,Burn Coal,coal:1,,2", "burn_coal,Burn Coal,iron_ore:1,,2"
	)
	var content: Definitions = fixture.definitions()
	assert_false(content.has_errors(), content.describe_errors())
	assert_eq(
		ItemAppearance.form_of(content, content.item_index("iron_ore")),
		ItemAppearance.FORM_FUEL,
		"ore a Boiler burns is fuel, dug or not"
	)


# ── The surface ───────────────────────────────────────────────────────────────
# A form wears one of the palette's own materials, by name, through the committed `.tres`
# files the Walls and the Machines already draw. **Not a colour and not per-instance**, which
# is the half of #73 that measurement decided: see `item_appearance.gd`'s own note on why the
# committed icons cannot carry this and why albedo alone could not either.


func test_every_form_names_a_committed_palette_material() -> void:
	# The gate that stops a renamed palette entry becoming an invisible fallback. A form whose
	# material does not resolve would draw Godot's default white, which against this palette is
	# the brightest thing in the frame — #42's Wall, a fifth time.
	for form: int in range(ItemAppearance.FORM_COUNT):
		var path: String = ItemAppearance.material_path_of(form)
		assert_true(
			ResourceLoader.exists(path), "form %d names %s, which does not resolve" % [form, path]
		)
		var skin: StandardMaterial3D = load(path) as StandardMaterial3D
		assert_true(skin != null, "%s is not a StandardMaterial3D" % path)


func test_no_two_forms_wear_the_same_surface() -> void:
	# Four distinct names is the cheap half; four distinct *albedos* is the half that decides
	# whether a player can read the line, because two palette entries could legitimately be
	# renamings of one colour.
	var seen: Dictionary = {}
	for form: int in range(ItemAppearance.FORM_COUNT):
		var path: String = ItemAppearance.material_path_of(form)
		var albedo: Color = (load(path) as StandardMaterial3D).albedo_color
		for other: int in seen:
			var apart: float = (
				absf(albedo.r - (seen[other] as Color).r)
				+ absf(albedo.g - (seen[other] as Color).g)
				+ absf(albedo.b - (seen[other] as Color).b)
			)
			assert_true(
				apart > 0.05,
				"forms %d and %d wear the same colour, %s" % [other, form, albedo]
			)
		seen[form] = albedo


func test_asking_what_an_item_looks_like_names_no_item_id() -> void:
	# The criterion written as the absence of code, the way build mode's is. If this file ever
	# spells an Item id, the thing it is deriving has become a table with two entries.
	var source: String = FileAccess.get_file_as_string("res://game/item_appearance.gd")
	assert_false(source.is_empty(), "the premise: the file is readable")
	var code: String = ""
	for line: String in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	# Quoted, because an Item id would have to be a string literal to be compared against one.
	# `ammunition_item` is a *field* of a Gear row and legitimately appears as bare code — the
	# thing this forbids is the id itself, which is what a table would be made of.
	for named: String in ["iron_ore", "coal", "iron_plate", "ammunition"]:
		assert_false(
			code.contains('"%s"' % named),
			"item_appearance.gd names the Item %s outside a comment" % named
		)
