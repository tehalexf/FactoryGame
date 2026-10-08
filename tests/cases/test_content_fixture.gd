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
