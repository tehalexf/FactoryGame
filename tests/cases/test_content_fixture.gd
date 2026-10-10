## `ContentFixture`: the one shared definition-set fixture the suite builds content out of.
##
## It is test infrastructure rather than game code, so it gets a contract of its own for
## the reason `Fixed` and `InputQuantiser` do — its behaviour is not observable through
## the Simulation façade, and the thing that would go wrong with it is **silence**.
##
## The claim this file stands behind: a test that asks the fixture to change one tuning
## value gets content in which that value changed, and a test whose override no longer
## matches the shipped file is **told**. Before this fixture existed, eleven copies of
## `content/tuning.toml` lived in ten test files, and one new required key put about 156
## failures across nine of them — because `Definitions` requires every key and a set with
## any error carries no definitions at all. That rule is right; the duplication was not.
extends TestCase


## Deliberately *not* `ContentFixture.read`. This file is the fixture's contract, so the
## reader it compares against has to be an independent one — asking the thing under test to
## read the file it is being checked against would assert nothing.
func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


## The whole point of the fixture: a test names nothing and gets the content the game
## ships, loaded, with no errors. That is what makes a new required tuning key free — the
## fixture reads the file the key was added to.
func test_a_fixture_that_overrides_nothing_is_the_shipped_content() -> void:
	var fixture: ContentFixture = ContentFixture.for_case(self)

	assert_eq(
		fixture.tuning,
		_read("res://content/tuning.toml"),
		"an un-overridden fixture must be the shipped tuning file, character for character"
	)
	assert_eq(fixture.definitions().errors, PackedStringArray(), "the shipped content must load")


## A test that asks for a different walking speed gets one. The assertion is the
## *difference*, not a literal, because a literal would pin the shipped value and this
## test is about the override working rather than about what 4 m/s is.
func test_an_override_reaches_the_definition_set() -> void:
	var shipped: Definitions = ContentFixture.for_case(self).definitions()
	var tuned: Definitions = (
		ContentFixture
		. for_case(self)
		. tune([["walk_speed_metres_per_second = 4", "walk_speed_metres_per_second = 9"]])
		. definitions()
	)

	assert_eq(tuned.errors, PackedStringArray(), "an overridden fixture must still load")
	assert_eq(
		tuned.player_walk_speed,
		Fixed.from_int(9),
		"the override must be the speed the definition set carries"
	)
	assert_ne(
		tuned.player_walk_speed, shipped.player_walk_speed, "and must differ from the shipped one"
	)


## The failure this file exists to make impossible. An override whose left-hand text the
## shipped file no longer contains changes nothing, and `String.replace` says so by
## returning the string unaltered — so a renamed key would silently leave every test that
## overrode it asserting against content it did not choose, with nothing going red. That is
## worse than the cascade this fixture replaced, because the cascade was at least loud.
func test_an_override_that_matches_nothing_is_reported_rather_than_ignored() -> void:
	var case: TestCase = TestCase.new()
	case.current_test = "a test with a stale override"

	var fixture: ContentFixture = ContentFixture.for_case(case).tune(
		[["no_such_key_lives_here = 1", "no_such_key_lives_here = 2"]]
	)

	assert_eq(fixture.unmatched, PackedStringArray(["no_such_key_lives_here = 1"]))
	assert_eq(case.failures.size(), 1, "the fixture must record the miss against its case")
	assert_true(
		case.failures[0].contains("no_such_key_lives_here = 1"),
		"and must name the override that missed: %s" % case.failures[0]
	)


## A matching override records nothing, so the check above cannot be the kind of guard
## that always fires.
func test_a_matching_override_records_no_failure() -> void:
	var case: TestCase = TestCase.new()
	case.current_test = "a test with a live override"

	ContentFixture.for_case(case).tune(
		[["walk_speed_metres_per_second = 4", "walk_speed_metres_per_second = 9"]]
	)

	assert_eq(case.failures, PackedStringArray(), "a live override is not a complaint")


## `stock` replaces whatever bill the shipped file carries rather than a literal copy of
## it. Ten files used to name `starting_stock = "iron_plate:110"` by hand, which is the
## same defect as the tuning copies one line long: the day the opening bill is retuned,
## every one of them would have gone quietly un-overridden.
func test_the_starting_stock_is_replaced_without_naming_the_shipped_bill() -> void:
	var definitions: Definitions = (
		ContentFixture.for_case(self).stock("iron_plate:7;coal:3").definitions()
	)

	assert_eq(definitions.errors, PackedStringArray(), "a restocked fixture must load")
	assert_eq(definitions.player_starting_stock_items, PackedStringArray(["coal", "iron_plate"]))
	assert_eq(definitions.player_starting_stock_counts, PackedInt64Array([3, 7]))


## `starting_machine` is `stock`'s twin and #63 is the ticket that noticed it was missing.
## #55 added `player.starting_machine`, which names a **row** rather than a number — so a
## fixture that brings its own `machines.csv` has to point it at a row it actually has, or
## the whole set is an error carrying no definitions at all. Four files grew a hand-copy of
## `starting_machine = "miner_mk1"` to do that, which is the same defect `stock` exists to
## remove.
func test_the_starting_machine_is_replaced_without_naming_the_shipped_row() -> void:
	var definitions: Definitions = (
		_own_tables().starting_machine("plate_seam_mk1").definitions()
	)

	assert_eq(definitions.errors, PackedStringArray(), "a re-pointed fixture must load")
	assert_eq(
		definitions.player_starting_machine,
		"plate_seam_mk1",
		"and must open pointed at the row it was given"
	)


## The other half of the same claim: a table with no shipped id in it and no override is an
## error, by name. That is `Definitions` working rather than failing — a Build Gun pointed at
## a Machine the content does not define is not a thing to let through quietly — and it is
## why four files needed the override at all.
func test_a_table_with_no_shipped_row_and_no_override_is_an_error_naming_the_key() -> void:
	var definitions: Definitions = _own_tables().definitions()

	assert_true(definitions.has_errors(), "a set pointed at a row it has not got is an error")
	assert_true(
		definitions.describe_errors().contains("player.starting_machine"),
		definitions.describe_errors()
	)


## A complete definition set whose Machine table holds nothing the shipped
## `player.starting_machine` names, which is the shape every fixture that brings its own
## Machines has. Every table that names a Machine or an Item has to come along, because the
## shipped ones name rows and Items this one does not have — which is the same cross-table
## rule from the other side.
func _own_tables() -> ContentFixture:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.machines = OWN_MACHINES
	fixture.recipes = OWN_RECIPES
	fixture.waves = OWN_WAVES
	fixture.deliveries = OWN_DELIVERIES
	fixture.gear = OWN_GEAR
	fixture.stratagems = OWN_STRATAGEMS
	return fixture.stock("iron_plate:10")


const OWN_MACHINES: String = """id,display_name,role,footprint_x,footprint_z,height_metres,power_draw_kw,power_supply_kw,health,max_depth,range_tiles,damage,repair,charge_capacity,recipe_id,build_cost
plate_seam_mk1,Plate Seam,miner,2,2,2,0,0,400,1,0,0,0,0,dig_plate,
"""

const OWN_RECIPES: String = """id,display_name,inputs,outputs,seconds
dig_plate,Dig Plate,,iron_plate:1,0.5
"""

const OWN_WAVES: String = """id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach
chaff_crawlers,crawler,0,1,0,1
"""

const OWN_DELIVERIES: String = """id,display_name,min_depth,goods,unlocks_machines,unlocks_gear,unlocks_stratagems
t01_opening,Opening Licence,1,iron_plate:1,,placeholder_gear,
"""

const OWN_GEAR: String = """id,display_name,kind,attack,damage,range_metres,spread_degrees,seconds_per_shot,ammunition_item,ammunition_per_shot,damage_percent,range_percent,spread_percent,interval_percent,ammunition_percent,damage_taken_percent
pneumatic_wrench,Pneumatic Wrench,weapon,melee,55,4,0,0.6,,0,0,0,0,0,0,0
placeholder_gear,Placeholder Barrel,barrel,,0,0,0,0,,0,10,0,0,0,0,0
"""

const OWN_STRATAGEMS: String = """id,display_name,effect,paint_seconds,radius_tiles,damage_per_charge,goods_per_charge,sentry_machine,sentry_seconds
artillery_barrage,Artillery Barrage,barrage,5,6,150,,,0
"""


## `tune_key` names the key and not the value it is replacing, which is what makes "0 turns
## the bob off" a claim about the key. Two files carried a private copy of this rewrite; the
## assertion is the *difference* rather than a literal, for `tune`'s reason.
func test_a_key_is_retuned_by_name_without_naming_the_shipped_value() -> void:
	var shipped: Definitions = ContentFixture.for_case(self).definitions()
	var tuned: Definitions = (
		ContentFixture.for_case(self).tune_key("bob_vertical_metres", "0").definitions()
	)

	assert_eq(tuned.errors, PackedStringArray(), "a retuned fixture must still load")
	assert_true(shipped.player_bob_vertical != 0, "the premise: the shipped bob is on")
	assert_eq(tuned.player_bob_vertical, 0, "and naming the key alone turns it off")


## A key that is not there is a failure naming it, like a stale `tune` pair — because a
## rewrite that matched nothing changes nothing and says nothing.
func test_retuning_a_key_the_file_does_not_declare_is_reported() -> void:
	var case: TestCase = TestCase.new()
	case.current_test = "a test retuning a key that is gone"

	ContentFixture.for_case(case).tune_key("no_such_key_lives_here", "1")

	assert_eq(case.failures.size(), 1, "a missing key is one complaint")
	assert_true(
		case.failures[0].contains("no_such_key_lives_here"),
		"and it names the key: %s" % case.failures[0]
	)


## A source a test brings itself wins over the shipped file, which is the ability the
## duplication was protecting: a test that studies the Factory wants Recipes it controls.
func test_a_table_a_test_supplies_itself_replaces_the_shipped_one() -> void:
	var fixture: ContentFixture = ContentFixture.for_case(self)
	fixture.waves = (
		"id,enemy_kind,min_heat,count_per_breach,heat_per_extra,max_per_breach\n"
		+ "chaff_crawlers,crawler,0,1,0,1\n"
	)

	var definitions: Definitions = fixture.definitions()

	assert_eq(definitions.errors, PackedStringArray(), "a fixture with its own Waves must load")
	assert_eq(definitions.wave_entry_count(), 1, "and must carry the one tier it was given")
