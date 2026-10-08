## Asks the exported build, in its own engine, whether it got its assets.
##
## Run it **with the shipped binary**, not with the editor:
##
##     DeepFoundry.console.exe --headless \
##         --script res://tools/release/verify_bundled_assets.gd -- --out report.json
##
## ## Why this exists
##
## Three asset classes load at runtime out of `res://assets_licensed/generated/`,
## and every one of them has a working fallback: `WeaponViewmodel` draws two boxes,
## `SoundBank` plays committed CC0 Kenney sounds, `SetDressing` builds the yard out
## of self-authored stand-ins (docs/ASSET_PIPELINE.md §7-9). So a build that lost
## them **starts, plays, looks worse, sounds worse and reports nothing**, which is
## the one failure mode `docs/RELEASING.md` is written to make impossible.
##
## `tools/release/verify_pck.py` already proves the bytes are in the pack. That is
## necessary and it is not sufficient: a file can be in the pack at a path nothing
## asks for, in a format the loader will not take, or — the one that actually
## happened — reachable only through `ProjectSettings.globalize_path`, which names
## a file on disk and there is no disk inside a PCK. So this half asks the game's
## own classes, through their own public API, and counts what they resolved:
##
## | Class | Question asked | What a loss looks like |
## |---|---|---|
## | `Definitions` | did `content/` load at all | no Machines; the game cannot start |
## | `SoundBank.is_hero` | how many cues play their hero take | every cue falls back to Kenney |
## | `WeaponViewmodel.has_model` | how many viewmodels loaded | boxes in the player's hands |
## | `SetDressing.uses_purchased_props` | are the purchased props drawn | a yard of stand-in boxes |
## | `SetDressing.uses_purchased_atlas` | did the shared atlas resolve | purchased props, untextured |
##
## The last row is its own question for a reason: the meshes come out of GLB files
## through `GLTFDocument` and the atlas out of two PNGs through `Image`, and the
## atlas route broke in the exported build while the mesh route did not.
##
## Exits 0 when everything resolved and 1 otherwise, and writes a JSON report to
## `--out` so the build script can read the counts rather than scrape a log.
extends SceneTree

## The seed and player count the yard is laid out for. Any Run would do — the
## layout is a pure function of the seed — so this is simply a Run that exists.
const SEED: int = 1
const PLAYERS: int = 1

## A Factory with no Machines in it means `content/` did not reach the pack, which
## is a dead build rather than a degraded one.
const MINIMUM_MACHINE_DEFINITIONS: int = 1


func _initialize() -> void:
	var findings: Dictionary = {}
	var faults: Array[String] = []

	_check_content(findings, faults)
	_check_audio(findings, faults)
	_check_viewmodels(findings, faults)
	_check_set_dressing(findings, faults)

	findings["faults"] = faults
	findings["ok"] = faults.is_empty()

	var report: String = JSON.stringify(findings, "  ", true, true)
	print("bundled-assets-report ", JSON.stringify(findings))
	var out: String = _argument("--out")
	if out != "":
		var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			push_error("could not write the report to %s" % out)
			quit(1)
			return
		file.store_string(report + "\n")
		file.close()

	for fault: String in faults:
		push_error(fault)
	quit(0 if faults.is_empty() else 1)


## Did the definitions ship? Everything else in this file assumes a Run can exist.
func _check_content(findings: Dictionary, faults: Array[String]) -> void:
	var definitions: Definitions = Definitions.load_from_directory("res://content")
	findings["content_errors"] = definitions.errors
	findings["machine_definitions"] = definitions.machine_ids().size()
	findings["recipe_definitions"] = definitions.recipe_ids().size()
	findings["item_definitions"] = definitions.item_ids().size()
	if not definitions.errors.is_empty():
		faults.append(
			"content/ did not load in the exported build: %s"
			% ", ".join(definitions.errors)
		)
	elif definitions.machine_ids().size() < MINIMUM_MACHINE_DEFINITIONS:
		faults.append("content/ loaded but carries no Machines")


## How many cues play the take that was cut for them, rather than a fallback.
func _check_audio(findings: Dictionary, faults: Array[String]) -> void:
	var bank: SoundBank = SoundBank.new()
	var cues: PackedStringArray = bank.cues()
	var hero: int = 0
	var silent: PackedStringArray = PackedStringArray()
	for cue: String in cues:
		if bank.is_hero(cue):
			hero += 1
		if bank.paths_for(cue).is_empty():
			silent.append(cue)
	findings["audio_cues"] = cues.size()
	findings["audio_hero_cues"] = hero
	findings["audio_silent_cues"] = silent

	if hero == 0:
		faults.append(
			("not one of %d cues resolved its hero take — the whole build is on the"
				+ " Kenney fallbacks. Run: bash tools/assets/convert_audio.sh")
			% cues.size()
		)
	if silent.size() > 0:
		faults.append("cues that resolve to nothing at all: %s" % ", ".join(silent))


## How many weapon frames have a model, asked the way the game asks it.
func _check_viewmodels(findings: Dictionary, faults: Array[String]) -> void:
	var directory: String = WeaponViewmodel.WEAPON_BODY_DIRECTORY
	var names: PackedStringArray = PackedStringArray()
	var listing: DirAccess = DirAccess.open(directory)
	if listing != null:
		for file_name: String in listing.get_files():
			if file_name.ends_with(".glb"):
				names.append(file_name.get_basename())
	names.sort()

	var drawn: PackedStringArray = PackedStringArray()
	for weapon_id: String in names:
		var viewmodel: WeaponViewmodel = WeaponViewmodel.new()
		root.add_child(viewmodel)
		var facts: WeaponAnimator.Facts = WeaponAnimator.Facts.new()
		facts.weapon = weapon_id
		facts.alive = true
		facts.interval_ticks = 1
		viewmodel.show_held(facts)
		if viewmodel.has_model():
			drawn.append(weapon_id)
		viewmodel.queue_free()
		root.remove_child(viewmodel)

	findings["viewmodels_bundled"] = names.size()
	findings["viewmodels_loaded"] = drawn
	if names.size() == 0:
		faults.append(
			("%s is empty in the exported build — every weapon is two placeholder"
				+ " boxes. Run: bash tools/assets/convert_weapons.sh")
			% directory
		)
	elif drawn.size() < names.size():
		faults.append(
			"%d of %d bundled viewmodels did not load as glTF"
			% [names.size() - drawn.size(), names.size()]
		)


## Is the yard made of purchased props, and are they textured?
func _check_set_dressing(findings: Dictionary, faults: Array[String]) -> void:
	var sim: Simulation = Simulation.new(SEED, PLAYERS)
	var dressing: SetDressing = SetDressing.new()
	root.add_child(dressing)
	dressing.sync(sim)

	findings["set_dressing_instances"] = dressing.instance_count()
	findings["set_dressing_groups"] = dressing.group_count()
	findings["set_dressing_uses_purchased_props"] = dressing.uses_purchased_props()
	findings["set_dressing_uses_purchased_atlas"] = dressing.uses_purchased_atlas()

	if not dressing.uses_purchased_props():
		faults.append(
			"the yard is drawn entirely out of stand-ins — no purchased prop"
				+ " resolved. Run: bash tools/assets/convert_props.sh"
		)
	elif not dressing.uses_purchased_atlas():
		faults.append(
			"the purchased props resolved but their shared atlas did not, so the"
				+ " whole yard is untextured. Check atlas.png and atlas_glow.png are"
				+ " in the pack and that SetDressing._runtime_texture is not"
				+ " globalising its path."
		)

	dressing.queue_free()
	root.remove_child(dressing)


## One `--name value` pair out of the arguments past `--`.
func _argument(name: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return ""
