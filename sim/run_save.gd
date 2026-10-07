## Writes a Run out and reads it back, so a Factory survives being closed.
##
## The whole promise is one sentence: **a Run written out and read back hashes to the
## integer it hashed to before.** `Simulation.hash()` already covers every piece of
## state that matters, so that single comparison is the entire acceptance criterion
## and a save that loses something fails loudly rather than subtly.
##
## # Nothing here knows what a Belt is
##
## There is no per-field serialisation code and no manifest of fields to keep in step
## with `simulation.gd`. This walks the Simulation's own property list and writes
## **every** script variable it finds, whatever it is. A later ticket that adds
## `_enemy_hp` to the Simulation gets it saved, loaded and round-tripped without
## touching this file — forgetting is not a thing that can happen, rather than a thing
## a test catches afterwards. Two special cases, and only two, are named here: the
## `Definitions` (carried as a digest, because content lives in `content/` and a Run
## that moved between content sets must say so) and the `DeterministicRng` (whose whole
## memory is one integer).
##
## Three mechanisms make that robust rather than merely convenient:
##
## 1. **The file is a census.** Every property gets a line, including the two special
##    cases, so the file states on its face which properties existed when it was
##    written.
## 2. **Loading compares that census against the live Simulation.** A property the file
##    does not carry, or one it carries that no longer exists, is refused by name. An
##    old save meeting a newer Simulation therefore says so instead of resuming with a
##    field silently left at its default.
## 3. **The save carries its own state hash, and loading re-checks it.** If a restored
##    Run does not hash to what was written, the load is refused. Any failure of any
##    part of this file to round-trip exactly is caught at every single load, not only
##    in the suite.
##
## A property whose type this cannot encode is written as `unsupported` and refused on
## load by name, so an exotic new field is an error with an address rather than a
## quietly empty array.
##
## # The format: line-oriented text, not a packed binary blob
##
## The Simulation is parallel arrays of integers and a few string tables, which argues
## for something compact and positional. It is text anyway, and deliberately:
##
## * **It is diffable.** This is a project whose entire method is comparing two states
##   and finding where they differ. `diff` over two saves pointing at the line whose
##   array drifted is worth more than the bytes it costs.
## * **It is keyed by name, not by position.** Two tickets adding state concurrently
##   cannot produce a file where everything after their field is shifted by one and
##   misread as something else. Positional formats fail silently under exactly the
##   merge this ticket expects.
## * **The census above is only possible because the format is self-describing.**
##   A positional blob cannot tell you which field it is missing.
## * **Compactness is not yet the binding constraint,** and when it becomes one the
##   encoding can be swapped behind `serialise`/`deserialise` without the Simulation
##   noticing, because the contract is the hash and not the bytes.
##
## Each line is `<property> <tokens…>` in prefix notation: a type tag followed by its
## payload, with every container announcing its length, so nesting needs no brackets
## and parsing is a single left-to-right walk. Strings are escaped to contain no
## whitespace, which is the only escaping the format needs.
class_name RunSave
extends RefCounted

## First line of every save. A file that does not start with it is refused as not
## being a save at all, rather than producing a parse error halfway down.
const MAGIC: String = "deep_foundry_run_save"

## The format version. Bump it when the encoding changes in a way an older reader
## would misread; a file declaring any other version is refused by number.
const FORMAT_VERSION: int = 1

const KEY_FORMAT: String = "format"
const KEY_DEFINITIONS_DIGEST: String = "definitions_digest"
const KEY_STATE_HASH: String = "state_hash"

## Type tags. One character or two, because every line carries several.
const TAG_INT: String = "i"
const TAG_BOOL: String = "b"
const TAG_TEXT: String = "t"
const TAG_INT_ARRAY: String = "ia"
const TAG_TEXT_ARRAY: String = "sa"
const TAG_ARRAY: String = "a"
## The content definitions. Not written out — they live in `content/` and the header
## carries their digest — but given a line so the file remains a complete census.
const TAG_DEFINITIONS: String = "defs"
## The random generator, whose entire memory is one integer.
const TAG_RNG: String = "rng"
## A property this format cannot encode. Written rather than skipped so the load
## refuses it by name.
const TAG_UNSUPPORTED: String = "unsupported"

## The Simulation properties that are objects rather than data, and the only two
## things in this file that know anything about what the Simulation contains.
const PROPERTY_DEFINITIONS: String = "_definitions"
const PROPERTY_RNG: String = "_rng"


## The verdict of a load: a Simulation, or the reasons there is not one.
##
## Shaped like `Definitions`: a result that either loaded or did not, carrying errors
## that name what was wrong. The three flags separate findings that send a reader to
## different places — a version refusal is not a corrupt file, and a content mismatch
## is not a bug in the Simulation.
class Load extends RefCounted:
	## The restored Run, or null when anything at all went wrong. Never a
	## half-restored Simulation: a Run missing one array is more dangerous than no
	## Run, because it looks playable.
	var simulation: Simulation = null
	var errors: PackedStringArray = PackedStringArray()

	## The file declares a format this build does not read.
	var version_mismatch: bool = false
	## The file was saved under different content definitions than are loaded now.
	var definitions_mismatch: bool = false
	## The file's census of Simulation properties disagrees with this build's.
	var state_mismatch: bool = false

	func has_errors() -> bool:
		return errors.size() > 0

	func describe_errors() -> String:
		return "\n".join(errors)

	func _fail(message: String) -> Load:
		errors.append(message)
		simulation = null
		return self


# ── Writing ───────────────────────────────────────────────────────────────────

## Serialises a Run.
##
## A pure read. It calls no mutator, steps nothing and takes no action: `hash()` before
## and after a save are the same integer, and a Run saved mid-flight carries on along
## exactly the tick sequence it would have followed unsaved.
static func serialise(sim: Simulation) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(MAGIC)
	lines.append("%s %d" % [KEY_FORMAT, FORMAT_VERSION])
	lines.append("%s %d" % [KEY_DEFINITIONS_DIGEST, sim.query_definition_digest()])
	lines.append("%s %d" % [KEY_STATE_HASH, sim.hash()])
	lines.append("")

	for property_name: String in state_property_names(sim):
		lines.append("%s %s" % [property_name, _encode_property(sim, property_name)])

	lines.append("")
	return "\n".join(lines)


## Every authoritative property of a Simulation, sorted.
##
## Sorted rather than left in declaration order so the file is canonical: where a later
## ticket happens to insert its `var` cannot move anybody else's line, which is what
## keeps two saves diffable and keeps a concurrent merge from rewriting the whole file.
##
## This is the mechanism the rest of the file rests on. It asks the Simulation what it
## is made of instead of being told, so a new array is persisted the moment it exists.
static func state_property_names(sim: Simulation) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	# purity-ok: an Array walked in index order; the entries are indexed by known key
	# and never iterated, so no unordered iteration happens here.
	for property: Variant in sim.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		names.append(String(property["name"]))
	names.sort()
	return names


static func _encode_property(sim: Simulation, property_name: String) -> String:
	if property_name == PROPERTY_DEFINITIONS:
		return TAG_DEFINITIONS
	if property_name == PROPERTY_RNG:
		var rng: DeterministicRng = sim.get(property_name)
		return "%s %d" % [TAG_RNG, 0 if rng == null else rng.state]
	return _encode_value(sim.get(property_name))


static func _encode_value(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return "%s %d" % [TAG_INT, value]
		TYPE_BOOL:
			return "%s %d" % [TAG_BOOL, 1 if value else 0]
		TYPE_STRING:
			return "%s %s" % [TAG_TEXT, encode_text(value)]
		TYPE_PACKED_INT64_ARRAY:
			var ints: PackedInt64Array = value
			var out: PackedStringArray = PackedStringArray()
			out.append("%s %d" % [TAG_INT_ARRAY, ints.size()])
			for element: int in ints:
				out.append(str(element))
			return " ".join(out)
		TYPE_PACKED_STRING_ARRAY:
			var texts: PackedStringArray = value
			var out: PackedStringArray = PackedStringArray()
			out.append("%s %d" % [TAG_TEXT_ARRAY, texts.size()])
			for element: String in texts:
				out.append(encode_text(element))
			return " ".join(out)
		TYPE_ARRAY:
			var array: Array = value
			var out: PackedStringArray = PackedStringArray()
			out.append("%s %d" % [TAG_ARRAY, array.size()])
			for element: Variant in array:
				out.append(_encode_value(element))
			return " ".join(out)
	return "%s %d" % [TAG_UNSUPPORTED, typeof(value)]


# ── Reading ───────────────────────────────────────────────────────────────────

## Restores a Run from its serialised form.
##
## `definitions` is the content the restored Run will use; null reads `content/`, which
## is what a player loading a save wants. The save's digest is compared against it
## before anything is restored, so a Run saved under one content set and opened under
## another says so rather than silently drifting.
##
## `replacement_sim` restores into something other than a plain `Simulation` — a subclass
## a test has extended with the state a later ticket will add. `DeterminismHarness.verify`
## takes one for the same reason: it is how a mechanism that claims to handle state it has
## never heard of gets made to prove it.
##
## Returns a `Load` that either carries a Simulation or carries the reasons it does not.
## Never both, and never a partially restored Simulation.
static func deserialise(
	text: String, definitions: Definitions = null, replacement_sim: Simulation = null
) -> Load:
	var result: Load = Load.new()

	var lines: PackedStringArray = text.split("\n")
	if lines.size() == 0 or lines[0].strip_edges() != MAGIC:
		return result._fail("this is not a Deep Foundry save: it does not begin with '%s'" % MAGIC)

	var declared_format: int = -1
	var declared_definitions_digest: int = 0
	var declared_state_hash: int = 0
	var saw_definitions_digest: bool = false
	var saw_state_hash: bool = false

	var body_names: PackedStringArray = PackedStringArray()
	var body_tokens: Array = []

	for index: int in range(1, lines.size()):
		var line: String = lines[index].strip_edges()
		if line.is_empty():
			continue
		var tokens: PackedStringArray = line.split(" ", false)
		var key: String = tokens[0]
		if key == KEY_FORMAT:
			declared_format = _token_to_int(tokens, 1)
			continue
		if key == KEY_DEFINITIONS_DIGEST:
			declared_definitions_digest = _token_to_int(tokens, 1)
			saw_definitions_digest = true
			continue
		if key == KEY_STATE_HASH:
			declared_state_hash = _token_to_int(tokens, 1)
			saw_state_hash = true
			continue
		if body_names.has(key):
			return result._fail("the save carries '%s' twice" % key)
		body_names.append(key)
		body_tokens.append(tokens.slice(1))

	# Checked before anything else is believed. A file from a future build may encode
	# the same property names in an incompatible way, so reading its body at all would
	# be guessing.
	if declared_format != FORMAT_VERSION:
		result.version_mismatch = true
		if declared_format == -1:
			return result._fail("the save declares no format version; this build reads format %d" % FORMAT_VERSION)
		return result._fail(
			"this save is in format %d and this build of Deep Foundry reads format %d"
			% [declared_format, FORMAT_VERSION]
		)

	if not saw_definitions_digest or not saw_state_hash:
		return result._fail("the save is incomplete: its header is missing a digest or a state hash")

	var content: Definitions = definitions
	if content == null:
		content = Definitions.load_from_directory(Definitions.CONTENT_DIR)
	if content.has_errors():
		return result._fail(
			"refusing to resume a Run: the content definitions did not load:\n%s"
			% content.describe_errors()
		)

	if content.digest() != declared_definitions_digest:
		result.definitions_mismatch = true
		return result._fail(
			(
				"this Run was saved under content definitions with digest %d and the"
				+ " content loaded now has digest %d; resuming it would be a different game"
			)
			% [declared_definitions_digest, content.digest()]
		)

	# The Map's geography, the seed, the player count and every array come out of the
	# file, so the Simulation is built as bare as it can be and then wholly overwritten.
	var sim: Simulation = replacement_sim
	if sim == null:
		sim = Simulation.new(0, 1, content, MapLayout.empty())

	var expected: PackedStringArray = state_property_names(sim)
	var census: PackedStringArray = _census_errors(expected, body_names)
	if census.size() > 0:
		result.state_mismatch = true
		result.errors.append_array(census)
		result.simulation = null
		return result

	for index: int in range(body_names.size()):
		var property_name: String = body_names[index]
		var tokens: PackedStringArray = body_tokens[index]
		var reader: _Reader = _Reader.new(tokens)
		var restored: Variant = _restore_property(sim, property_name, reader, content)
		if reader.error != "":
			return result._fail("'%s': %s" % [property_name, reader.error])
		if restored != null:
			sim.set(property_name, restored)

	result.simulation = sim

	# The save checks itself. Every load re-derives the hash and compares it against
	# what was written, so any failure of any property to round-trip exactly is caught
	# here — on every load a player ever performs, not only in the suite.
	var restored_hash: int = sim.hash()
	if restored_hash != declared_state_hash:
		result.state_mismatch = true
		return result._fail(
			(
				"the restored Run hashes to %d but the save says %d; the file is corrupt"
				+ " or carries state this build restores differently"
			)
			% [restored_hash, declared_state_hash]
		)

	return result


## Which properties the save and this build's Simulation disagree about, named.
##
## The structural half of the promise: the file is a census of what existed when it was
## written, and this compares it against what exists now. A ticket that adds state to
## the Simulation makes older saves refuse by name instead of resuming with that state
## silently left at its default.
static func _census_errors(expected: PackedStringArray, found: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for property_name: String in expected:
		if not found.has(property_name):
			errors.append(
				"the save does not carry '%s', which this build's Simulation holds;"
				% property_name
				+ " it was written by an older build"
			)
	for property_name: String in found:
		if not expected.has(property_name):
			errors.append(
				"the save carries '%s', which this build's Simulation no longer holds"
				% property_name
			)
	return errors


static func _restore_property(
	sim: Simulation, property_name: String, reader: _Reader, content: Definitions
) -> Variant:
	var tag: String = reader.next_token()
	if tag == TAG_DEFINITIONS:
		sim.set(property_name, content)
		return null
	if tag == TAG_RNG:
		var rng: DeterministicRng = DeterministicRng.new(0)
		rng.state = reader.next_int()
		sim.set(property_name, rng)
		return null
	if tag == TAG_UNSUPPORTED:
		reader.error = (
			"this property's type (%d) is one the save format cannot encode; teach"
			% reader.next_int()
			+ " RunSave._encode_value about it, or hold the state as integer arrays"
		)
		return null
	return _decode_value(reader, tag)


static func _decode_value(reader: _Reader, tag: String) -> Variant:
	match tag:
		TAG_INT:
			return reader.next_int()
		TAG_BOOL:
			return reader.next_int() != 0
		TAG_TEXT:
			return decode_text(reader.next_token())
		TAG_INT_ARRAY:
			var count: int = reader.next_int()
			var ints: PackedInt64Array = PackedInt64Array()
			for index: int in range(count):
				ints.append(reader.next_int())
			return ints
		TAG_TEXT_ARRAY:
			var count: int = reader.next_int()
			var texts: PackedStringArray = PackedStringArray()
			for index: int in range(count):
				texts.append(decode_text(reader.next_token()))
			return texts
		TAG_ARRAY:
			var count: int = reader.next_int()
			var array: Array = []
			for index: int in range(count):
				array.append(_decode_value(reader, reader.next_token()))
			return array
	reader.error = "unknown type tag '%s'" % tag
	return null


# ── Files ─────────────────────────────────────────────────────────────────────
# Where a Run actually lives. Separate from `serialise`/`deserialise` so the format has
# a contract that can be tested without touching a disk, and so the hash round trip —
# which is the acceptance criterion — is proved over a String rather than over a file
# system's moods.

## Where a Run is saved when nobody says otherwise. `user://` because a save is the
## player's, not the repository's, and must survive an export.
const DEFAULT_PATH: String = "user://run.deepfoundry"


## Writes a Run to a file. Returns an empty string on success, or the reason it failed.
static func write_to_file(sim: Simulation, path: String = DEFAULT_PATH) -> String:
	var text: String = serialise(sim)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(text)
	file.close()
	return ""


## Reads a Run back. A file that is missing or unreadable is a `Load` carrying that as
## its reason, exactly like a malformed one — a caller has one thing to check.
static func read_from_file(
	path: String = DEFAULT_PATH,
	definitions: Definitions = null,
	replacement_sim: Simulation = null
) -> Load:
	if not FileAccess.file_exists(path):
		return Load.new()._fail("there is no saved Run at %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Load.new()._fail(
			"could not open %s for reading (error %d)" % [path, FileAccess.get_open_error()]
		)
	var text: String = file.get_as_text()
	file.close()
	return deserialise(text, definitions, replacement_sim)


# ── Escaping ──────────────────────────────────────────────────────────────────
# Tokens are separated by single spaces and nothing else, so the only escaping the
# format needs is whatever would otherwise look like a separator — plus a marker for
# the empty string, which would vanish between two spaces.

const EMPTY_MARKER: String = "\\z"


static func encode_text(value: String) -> String:
	if value.is_empty():
		return EMPTY_MARKER
	var out: String = value.replace("\\", "\\\\")
	out = out.replace(" ", "\\_")
	out = out.replace("\n", "\\n")
	out = out.replace("\r", "\\r")
	out = out.replace("\t", "\\t")
	return out


static func decode_text(token: String) -> String:
	if token == EMPTY_MARKER:
		return ""
	var out: String = ""
	var index: int = 0
	while index < token.length():
		var character: String = token[index]
		if character != "\\" or index + 1 >= token.length():
			out += character
			index += 1
			continue
		var escaped: String = token[index + 1]
		match escaped:
			"\\":
				out += "\\"
			"_":
				out += " "
			"n":
				out += "\n"
			"r":
				out += "\r"
			"t":
				out += "\t"
			_:
				out += escaped
		index += 2
	return out


static func _token_to_int(tokens: PackedStringArray, index: int) -> int:
	if index >= tokens.size() or not tokens[index].is_valid_int():
		return -1
	return tokens[index].to_int()


## A left-to-right walk over one line's tokens, which is all the parsing this format
## needs: every container announces its length, so nothing has to look ahead.
class _Reader extends RefCounted:
	var _tokens: PackedStringArray
	var _index: int = 0
	var error: String = ""

	func _init(tokens: PackedStringArray) -> void:
		_tokens = tokens

	func next_token() -> String:
		if _index >= _tokens.size():
			if error == "":
				error = "the line ends sooner than its declared lengths require"
			return ""
		var token: String = _tokens[_index]
		_index += 1
		return token

	func next_int() -> int:
		var token: String = next_token()
		if token == "":
			return 0
		if not token.is_valid_int():
			if error == "":
				error = "'%s' is not a whole number" % token
			return 0
		return token.to_int()
