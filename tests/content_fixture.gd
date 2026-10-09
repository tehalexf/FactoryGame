## The suite's one definition-set fixture: the shipped content in `content/`, with
## whatever a particular test means to change and nothing else.
##
## **Why this exists.** `Definitions` requires every tuning key, and a definition set with
## any error carries *no* definitions at all. That rule is deliberate and right — half a
## definition set is more dangerous than none, because it looks usable. But eleven copies
## of `content/tuning.toml` once lived inside ten test files, so adding one required key
## put about 156 failures across nine of them: the rule working exactly as designed
## against a duplication that should never have been there. Adding a key now costs
## nothing, because there is one reader of that file.
##
## **What it is not.** It is not a way to stop a test choosing its own content. A test that
## studies the Factory wants Recipes it controls, and several want a Delivery chain that
## locks nothing and a stock that pays for anything, precisely so the chain is not what
## they are asserting. Every source is a plain field: assign one and the shipped file is
## not read for it.
##
## The shape is `test_machine_mortality.gd`'s, generalised — it never carried a copy, and
## substituted against the shipped file with pairs like
## `["breaker_damage = 60", "breaker_damage = 10000"]`.
##
## ```gdscript
## var content: Definitions = (
##     ContentFixture
##     . for_case(self)
##     . tune([["decay_per_minute = 240", "decay_per_minute = 0"]])
##     . stock("iron_plate:400")
##     . definitions()
## )
## ```
class_name ContentFixture
extends RefCounted

## The directory the shipped content lives in. One place, so a test never spells a path.
const CONTENT_DIR: String = "res://content"

## The one key `stock` rewrites, matched by name rather than by a copy of its value — ten
## files used to name `starting_stock = "iron_plate:110"` by hand, which is the same defect
## as a full copy, one line long.
const STARTING_STOCK_KEY: String = "starting_stock"

## The one key `starting_machine` rewrites, matched by name for the reason above. #55 added
## it, and four files that bring their own `machines.csv` immediately grew a hand-copy of its
## shipped value beside their `SHIPPED_STOCK` one — because a key naming a **row** is an
## error for any fixture whose table has no such row, and a replaced table is a door
## `tune` cannot cover.
const STARTING_MACHINE_KEY: String = "starting_machine"

## Every source `Definitions.parse` takes, each defaulting to the shipped file. Assign one
## to replace that table wholesale; leave it alone to get the content the game ships.
var machines: String = ""
var recipes: String = ""
var tuning: String = ""
var waves: String = ""
var deliveries: String = ""
var gear: String = ""
var stratagems: String = ""

## The two optional tables, which default to **absent** rather than to the shipped file,
## because `Definitions.parse` does: no ports source draws no port arrows, and no
## structures source means every structure is free, which is what an empty `build_cost`
## column already means for a Machine. A fixture that quietly supplied them would change
## what every existing test means.
var ports: String = ""
var structures: String = ""

## Overrides whose left-hand text the tuning source did not contain, in the order they were
## asked for. Each is also recorded as a failure against the case, which is the loud half;
## this is the half a test can assert on.
var unmatched: PackedStringArray = PackedStringArray()

## The case to report a stale override against. Never null in the suite.
var _case: TestCase = null


## Builds a fixture that reports a stale override as a failure of `case`.
##
## The dependency runs this way round on purpose: a fixture knows about the test base, and
## the test base knows nothing about content. An override that matched nothing changes
## nothing and `String.replace` does not say so, so without a case to complain to, a
## renamed key would leave a test asserting against content it did not choose with nothing
## going red. That is a worse failure than the cascade this class replaced, because the
## cascade was at least loud.
static func for_case(case: TestCase) -> ContentFixture:
	var fixture: ContentFixture = ContentFixture.new()
	fixture._case = case
	fixture.machines = shipped(Definitions.MACHINES_FILE)
	fixture.recipes = shipped(Definitions.RECIPES_FILE)
	fixture.tuning = shipped(Definitions.TUNING_FILE)
	fixture.waves = shipped(Definitions.WAVES_FILE)
	fixture.deliveries = shipped(Definitions.DELIVERIES_FILE)
	fixture.gear = shipped(Definitions.GEAR_FILE)
	fixture.stratagems = shipped(Definitions.STRATAGEMS_FILE)
	return fixture


## Reads one of the shipped content files by its own file name.
static func shipped(file_name: String) -> String:
	return read("%s/%s" % [CONTENT_DIR, file_name])


## Reads a file whole. Public because a test that builds its own table out of the shipped
## one needs the same reader, and ten files had a private copy of it.
static func read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Applies plain-text substitutions to the tuning source, as `[from, to]` pairs. Every
## number not named stays the shipped file's, so a test that cares about one key is still
## reading the balance the game ships.
func tune(overrides: Array) -> ContentFixture:
	for pair: Variant in overrides:
		var from: String = str(pair[0])
		var to: String = str(pair[1])
		if not tuning.contains(from):
			unmatched.append(from)
			if _case != null:
				_case.fail("the tuning override '%s' matched nothing in content/tuning.toml" % from)
			continue
		tuning = tuning.replace(from, to)
	return self


## Replaces `player.starting_stock` with `bill`, in the `item:count;item:count` form the
## key already takes. Matched by key name, so it survives a change to the shipped bill —
## which is the whole difference between this and a substitution naming the shipped value.
func stock(bill: String) -> ContentFixture:
	return _rewrite_quoted_key(STARTING_STOCK_KEY, bill)


## Replaces `player.starting_machine` with `machine_id`. Matched by key name, like `stock`,
## and for a sharper reason: a fixture that brings its own `machines.csv` *must* name a row
## it actually has, or the whole definition set is an error and carries no definitions at
## all. The value it is replacing is therefore never the interesting half, and naming it by
## hand is how four files came to hold a copy of `miner_mk1`.
func starting_machine(machine_id: String) -> ContentFixture:
	return _rewrite_quoted_key(STARTING_MACHINE_KEY, machine_id)


## Rewrites one tuning key to `value`, by key name, leaving the quoting to the caller — so
## `tune_key("bob_amplitude_metres", "0")` writes a number and `stock` writes a string. Two
## files carried a private copy of exactly this loop, each with its own `assert_true(found)`;
## this is that loop with the fixture's own complaint instead.
##
## Use it over `tune` wherever the *key* is what a test is asserting about rather than the
## value it is replacing — "0 turns the bob off" is a claim about the key, and a pair naming
## the shipped amplitude would make it a claim about one number as well.
func tune_key(key: String, value: String) -> ContentFixture:
	return _rewrite_key(key, "%s = %s" % [key, value])


## Rewrites the whole line of a `key = "value"` tuning entry, by key. Absence is a failure
## naming the key, for `tune`'s reason: a rewrite that matched nothing changes nothing and
## says nothing.
func _rewrite_quoted_key(key: String, value: String) -> ContentFixture:
	return _rewrite_key(key, '%s = "%s"' % [key, value])


## The line rewrite both of those share. Absence is a failure naming the key.
func _rewrite_key(key: String, replacement: String) -> ContentFixture:
	var lines: PackedStringArray = tuning.split("\n")
	var found: bool = false
	for index: int in range(lines.size()):
		if lines[index].begins_with("%s = " % key):
			lines[index] = replacement
			found = true
	if not found:
		unmatched.append(replacement)
		if _case != null:
			_case.fail("content/tuning.toml declares no %s to replace" % key)
		return self
	tuning = "\n".join(lines)
	return self


## The definition set these sources describe. Paths are the shipped file names, so an error
## reads as it would against `content/` itself.
func definitions() -> Definitions:
	return Definitions.parse(
		machines,
		recipes,
		tuning,
		waves,
		deliveries,
		gear,
		stratagems,
		Definitions.MACHINES_FILE,
		Definitions.RECIPES_FILE,
		Definitions.TUNING_FILE,
		Definitions.WAVES_FILE,
		Definitions.DELIVERIES_FILE,
		Definitions.GEAR_FILE,
		Definitions.STRATAGEMS_FILE,
		ports,
		Definitions.PORTS_FILE,
		structures,
		Definitions.STRUCTURES_FILE
	)
