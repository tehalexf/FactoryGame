## Every Item the shipped Recipes mention has a picture, and nothing in the hotbar is blank.
##
## **#59, and it is the gate the asset suite already has for Machine meshes pointed at the
## other kind of generated art.** A mesh that disagrees with the Simulation about a footprint
## fails `tools/assets/run_tests.sh`; an Item that has outgrown the generated icon set failed
## nothing at all, which is how `iron_plate` came to have no picture through four tickets of
## the hotbar being worked on. #53's cells draw what a Machine eats and what it makes, so the
## missing one was not a cosmetic gap in a corner: the Smelter's output slot and the Ammo
## Press's input slot were **both** blank, which are precisely the two cells a player reads to
## learn that the Smelter feeds the Press.
##
## **Why it is here and not in the asset suite, which is the ticket's open question.** Three
## reasons, and the third is the one that decides it:
##
## - **The Item set has one authority and it is `Definitions`.** There is no Item table —
##   the set of Items is exactly what the Recipes mention, interned in sorted order — so a
##   Python check would have to re-implement the interning against `content/recipes.csv`,
##   which is a second opinion about the one thing this project is most careful to keep
##   singular. Here the list is simply `definitions.item_ids()`.
## - **The resolution has one authority too**, `WorldView.icon_path_for_item`, which is the
##   very function the cells call. The check and the hotbar cannot disagree about what
##   resolves, which is the arrangement `query_build_refusal` has with the hologram.
## - **`ResourceLoader.exists` is a strictly stronger question than a file check**, and only
##   the engine can ask it. A committed `.png` whose `.import` sidecar was not committed is
##   present on disk and **invisible to the game** — a blank cell with the file sitting right
##   there, which is the exact failure mode this test exists for and the one a Python
##   `os.path.exists` would wave through.
##
## **It cannot fire on a clone that legitimately has no generated art, because there is no
## such clone.** `assets/generated/` is **committed** — it is not the gitignored quarantine
## the weapon viewmodels, the audio cues and the set-dressing props live in, and it is not
## covered by `tools/assets/asset_staleness.py`, which dates gitignored output precisely
## because no commit can see it. #57's rule is "where the output is committed, prove it;
## where it is gitignored, date it", and an icon is on the committed side. So absence here is
## never "the packs are not linked"; it is always a missing picture, and this is an
## unconditional assertion rather than a skip.
extends TestCase


## The acceptance criterion, in one sentence.
func test_every_item_the_recipes_mention_has_an_icon() -> void:
	var definitions: Definitions = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	assert_false(definitions.has_errors(), definitions.describe_errors())

	var blank: PackedStringArray = PackedStringArray()
	for item: int in range(definitions.item_count()):
		if WorldView.icon_path_for_item(definitions, item).is_empty():
			blank.append(definitions.item_id(item))

	assert_eq(
		", ".join(blank),
		"",
		(
			"these Items have no icon the hotbar can resolve — add a row to"
			+ " tools/aigen/prompts/icons.yaml and regenerate (see tools/aigen/README.md)"
		)
	)
	# And the set is not empty, or the loop above asserts nothing about anything. The
	# shipped Recipes mention exactly four: ammunition, coal, iron_ore and iron_plate.
	assert_eq(definitions.item_count(), 4, "the shipped Recipes intern four Items")


## The gap #59 closed, named so that losing the file again is a failure rather than a silence.
##
## The general test above would catch it, but it would catch it as "some Item somewhere", and
## this one says which — and says it about the two cells the ticket was actually opened over.
func test_the_smelters_output_and_the_ammo_presses_input_are_both_pictured() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var view: WorldView = WorldView.new()
	view.sync(sim)
	var definitions: Definitions = sim.query_definitions()

	var smelter: int = BuildChain.cell_of(definitions, definitions.machine_index("smelter_mk1"))
	var press: int = BuildChain.cell_of(definitions, definitions.machine_index("ammo_press_mk1"))
	assert_true(
		view.machine_picker_icon_path(smelter).contains("iron_plate"),
		"a Smelter makes plate: %s" % view.machine_picker_icon_path(smelter)
	)
	assert_true(
		view.machine_picker_input_icon_path(press).contains("iron_plate"),
		"and an Ammo Press eats it: %s" % view.machine_picker_input_icon_path(press)
	)
	view.free()


## Asking leaves the Run exactly where it was, which is the rule every projection here obeys.
##
## `icon_path_for_item` reads the definition set and the filesystem and nothing else, so this
## is cheap insurance rather than a live worry — but a renderer question that moved the state
## hash is the one category of bug this project has decided to assert against by hand.
func test_asking_which_items_have_icons_leaves_the_run_exactly_where_it_was() -> void:
	var sim: Simulation = Simulation.new(1, 1)
	var definitions: Definitions = sim.query_definitions()
	var before: int = sim.hash()
	for item: int in range(definitions.item_count()):
		WorldView.icon_path_for_item(definitions, item)
	assert_eq(sim.hash(), before, "asking about an icon is a read")
