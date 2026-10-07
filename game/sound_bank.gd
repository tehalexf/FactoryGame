## Which file a cue plays, how loud, and what it falls back to when the hero take
## is not on this machine.
##
## The catalogue and nothing else. **What** makes a noise and **when** is
## `game/audio_director.gd`'s job; this file only answers "given the cue
## `silo_commit`, hand me a stream".
##
## ## Two sources, and every cue has both
##
## The hero takes are cut out of the Sonniss `#GameAudioGDC` bundle by
## `tools/assets/convert_audio.sh`. That bundle is royalty-free for use in a
## shipped game and **forbids redistribution**, so neither it nor anything derived
## from it may be committed to a public repository — the cuts land in
## `HERO_DIRECTORY`, which is gitignored, outside the shipping tree, and on most
## clones does not exist (docs/ASSETS.md, docs/LICENSED_ASSETS.md).
##
## So **every cue also names committed CC0 fallbacks**, from Kenney's "Impact
## Sounds" and "Sci-Fi Sounds". This is the one place where this project's
## absent-asset rule does better than a placeholder: a clone without the bundle
## does not get a silent lever, it gets a Kenney lever. The game is audibly a game
## either way, and that is asserted in `tests/cases/test_game_audio.gd`.
##
## A handful of cues — footsteps, landings — have **no** hero take, because the
## bundle has no footsteps in it. They are fallback-only and that is not a defect:
## the catalogue's contract is that a cue resolves, not that it resolves to
## Sonniss.
##
## ## Variation is chosen by tick, never by `randi`
##
## Kenney ships five takes of every impact and playing one of them is what stops a
## Factory under fire sounding like a machine gun of one sample. Which one is
## `tick % count` — **deterministic**, for the reason `WeaponViewmodel` seeks its
## clips by tick rather than letting the engine's clock drive them: the Simulation
## is reproducible and nothing in the presentation layer should be the reason a
## replay sounds different from the Run it recorded.
class_name SoundBank
extends RefCounted

## Where `tools/assets/convert_audio.sh` writes the hero cues. Outside the
## shipping tree, gitignored, and usually absent — an ordinary state, not a
## warning, exactly as a Machine with no `.glb` is.
const HERO_DIRECTORY: String = "res://assets_licensed/generated/audio/"

const IMPACTS: String = "res://assets/audio/kenney_impact_sounds/"
const SCI_FI: String = "res://assets/audio/kenney_sci_fi_sounds/"

# ── The cues ──────────────────────────────────────────────────────────────────
# Named constants rather than bare strings, so a typo in the director is a load
# error rather than a cue that silently never plays.

# The five diegetic controls DESIGN.md names, in its order.
const SILO_DIAL_SHELL: String = "silo_dial_shell"
const SILO_DIAL_CHARGES: String = "silo_dial_charges"
const SILO_COMMIT: String = "silo_commit"
const SILO_COMMIT_BODY: String = "silo_commit_body"
const SILO_REFUSED: String = "silo_refused"
const PAINT_BEGIN: String = "paint_begin"
const PAINT_LOOP: String = "paint_loop"
const PAINT_COMPLETE: String = "paint_complete"
const PAINT_INTERRUPTED: String = "paint_interrupted"
const BOILER_STARTUP: String = "boiler_startup"
const BOILER_RELIEF: String = "boiler_relief"
const DELIVERY_INTAKE: String = "delivery_intake"
const DELIVERY_COMPLETE: String = "delivery_complete"
const CALL_WAVE_LEVER: String = "call_wave_lever"

# Waves.
const TELEGRAPH_KLAXON: String = "telegraph_klaxon"
const WAVE_BEGIN: String = "wave_begin"
const BREACH_OPENS: String = "breach_opens"

# Weapons.
const WEAPON_FIRE_BODY: String = "weapon_fire_body"
const WEAPON_FIRE_CRACK: String = "weapon_fire_crack"
const WEAPON_FIRE_TAIL: String = "weapon_fire_tail"
const WEAPON_RELOAD: String = "weapon_reload"
const WEAPON_IMPACT: String = "weapon_impact"
const WEAPON_SWING: String = "weapon_swing"
const WEAPON_HIT: String = "weapon_hit"
const WEAPON_DRY: String = "weapon_dry"

# The Factory.
const FACTORY_BED: String = "factory_bed"
const FACTORY_BUSY: String = "factory_busy"
const MACHINE_BUILT: String = "machine_built"
const MACHINE_DESTROYED: String = "machine_destroyed"
const MACHINE_DAMAGED: String = "machine_damaged"
const TURRET_FIRE: String = "turret_fire"
const NEST_DAMAGED: String = "nest_damaged"
const RUN_OVER: String = "run_over"

# Enemies and the player.
const ENEMY_ATTACK: String = "enemy_attack"
const ENEMY_DEATH: String = "enemy_death"
const PLAYER_HURT: String = "player_hurt"
const PLAYER_DOWN: String = "player_down"
const FOOTSTEP: String = "footstep"
const PLAYER_LAND: String = "player_land"

## The five controls' **hero** cues, which is the list issue #21's "every Diegetic
## control has a distinct hero sound" is about. Kept as data so the test asserting
## it can be about the design rather than about a hand-copied list.
const DIEGETIC_CUES: Array = [
	SILO_DIAL_SHELL,
	SILO_DIAL_CHARGES,
	SILO_COMMIT,
	PAINT_BEGIN,
	PAINT_LOOP,
	BOILER_STARTUP,
	BOILER_RELIEF,
	DELIVERY_INTAKE,
	CALL_WAVE_LEVER,
]

## The cues that play as a sustained bed rather than as a hit, so `loop` is set on
## the stream before it is handed out. Everything else is one-shot.
const LOOPING_CUES: Array = [FACTORY_BED, FACTORY_BUSY, PAINT_LOOP, TELEGRAPH_KLAXON]

## Cue id -> `[hero file, [committed fallbacks], gain in dB]`.
##
## The gain is **the mix**, and it has to be here rather than in the conversion,
## because every hero cue comes out of `wav_to_cue.py` peak-normalised to the same
## ceiling: equally loud, which is the opposite of a mix. These numbers are what
## make a Silo's breech louder than a footstep.
##
## A fallback list is a set of takes of the same event, not a chain of
## alternatives: all of them exist, and one is picked per play.
const CATALOGUE: Dictionary = {
	# ── The Silo's loading cycle ─────────────────────────────────────────────
	# The dial sits under a player's hands, so it is close, dry and quiet. Tin for
	# the selector and light metal for the counter: a selector *chooses*, a counter
	# *ticks*, and the fallbacks keep that distinction even without the hero takes.
	SILO_DIAL_SHELL: ["silo_dial_shell", ["impactTin_medium_000", "impactTin_medium_002"], -7.0],
	SILO_DIAL_CHARGES: [
		"silo_dial_charges",
		["impactMetal_light_000", "impactMetal_light_002", "impactMetal_light_004"],
		-9.0,
	],
	# The commit is the loudest thing in this table on purpose. It is the one act a
	# player cannot take back.
	SILO_COMMIT: ["silo_commit", ["impactPlate_heavy_000", "impactPlate_heavy_003"], 0.0],
	SILO_COMMIT_BODY: ["silo_commit_body", ["lowFrequency_explosion_000"], -5.0],
	SILO_REFUSED: ["silo_refused", ["impactGeneric_light_001"], -10.0],

	# ── Painting ─────────────────────────────────────────────────────────────
	PAINT_BEGIN: ["paint_begin", ["forceField_000", "forceField_002"], -4.0],
	PAINT_LOOP: ["paint_loop", ["computerNoise_002"], -13.0],
	PAINT_COMPLETE: ["paint_complete", ["lowFrequency_explosion_001"], -1.0],
	PAINT_INTERRUPTED: ["paint_interrupted", ["impactGlass_medium_001"], -4.0],

	# ── The Boiler ───────────────────────────────────────────────────────────
	BOILER_STARTUP: ["boiler_startup", ["engineCircular_000", "engineCircular_003"], -7.0],
	BOILER_RELIEF: ["boiler_relief", ["thrusterFire_001", "thrusterFire_003"], -6.0],

	# ── The Nest's Delivery intake ───────────────────────────────────────────
	DELIVERY_INTAKE: ["delivery_intake", ["impactSoft_heavy_000", "impactSoft_heavy_002"], -4.0],
	# A bell for a tier opening, and a bell is what Kenney has too.
	DELIVERY_COMPLETE: ["delivery_complete", ["impactBell_heavy_000"], -3.0],

	# ── The call-Wave-early lever ────────────────────────────────────────────
	CALL_WAVE_LEVER: ["call_wave_lever", ["impactMetal_heavy_000", "impactMetal_heavy_002"], -2.0],

	# ── Waves ────────────────────────────────────────────────────────────────
	# A warning you cannot hear is not a warning, so the klaxon is the loudest
	# non-diegetic cue in the game.
	TELEGRAPH_KLAXON: ["telegraph_klaxon", ["forceField_003"], -5.0],
	WAVE_BEGIN: ["wave_begin", ["lowFrequency_explosion_001"], -3.0],
	BREACH_OPENS: ["breach_opens", ["impactGlass_heavy_000", "impactGlass_heavy_003"], -4.0],

	# ── Weapons ──────────────────────────────────────────────────────────────
	# Three layers on one shot. The body carries the pressure, the crack carries the
	# mechanism, the tail carries the room — and the tail is well down, because a
	# tail you can pick out individually is a second gunshot.
	WEAPON_FIRE_BODY: ["weapon_fire_body", ["lowFrequency_explosion_000"], -3.0],
	WEAPON_FIRE_CRACK: ["weapon_fire_crack", ["impactMetal_medium_000", "impactMetal_medium_003"], -6.0],
	WEAPON_FIRE_TAIL: ["weapon_fire_tail", ["explosionCrunch_000", "explosionCrunch_002"], -14.0],
	WEAPON_RELOAD: ["weapon_reload", ["impactMetal_light_001", "impactMetal_light_003"], -6.0],
	WEAPON_IMPACT: ["weapon_impact", ["impactPunch_heavy_000", "impactPunch_heavy_002"], -8.0],
	WEAPON_SWING: ["weapon_swing", ["impactSoft_medium_000"], -8.0],
	WEAPON_HIT: ["weapon_hit", ["impactPunch_medium_000", "impactPunch_medium_003"], -5.0],
	WEAPON_DRY: ["weapon_dry", ["impactGeneric_light_003"], -11.0],

	# ── The Factory ──────────────────────────────────────────────────────────
	# Both beds sit low. `AudioDirector.ambience_db` moves them against each other
	# as the Factory grows; these are the ceilings that mix is measured down from.
	FACTORY_BED: ["factory_bed", ["spaceEngineLow_000"], -16.0],
	FACTORY_BUSY: ["factory_busy", ["engineCircular_002"], -14.0],
	MACHINE_BUILT: ["machine_built", ["impactPlate_medium_000", "impactPlate_medium_002"], -5.0],
	MACHINE_DESTROYED: ["machine_destroyed", ["explosionCrunch_001", "explosionCrunch_003"], -3.0],
	MACHINE_DAMAGED: ["machine_damaged", ["impactMetal_medium_001", "impactMetal_medium_004"], -9.0],
	# A Turret firing is heard across the base all Wave long, so it is deliberately
	# further down than the player's own weapon.
	TURRET_FIRE: ["turret_fire", ["impactMetal_light_002", "impactMetal_light_004"], -12.0],
	NEST_DAMAGED: ["nest_damaged", ["impactBell_heavy_002", "impactBell_heavy_004"], -2.0],
	RUN_OVER: ["run_over", ["lowFrequency_explosion_001"], 0.0],

	# ── Enemies and the player ───────────────────────────────────────────────
	ENEMY_ATTACK: ["enemy_attack", ["slime_000", "slime_001"], -6.0],
	ENEMY_DEATH: ["enemy_death", ["impactSoft_medium_001", "impactSoft_medium_003"], -7.0],
	PLAYER_HURT: ["player_hurt", ["impactPunch_medium_001"], -4.0],
	PLAYER_DOWN: ["player_down", ["impactSoft_heavy_004"], -2.0],
	# No hero take: the bundle has no footsteps in it. Kenney ships five of concrete,
	# which is what a Factory floor is.
	FOOTSTEP: [
		"",
		[
			"footstep_concrete_000",
			"footstep_concrete_001",
			"footstep_concrete_002",
			"footstep_concrete_003",
			"footstep_concrete_004",
		],
		-19.0,
	],
	PLAYER_LAND: ["", ["impactSoft_heavy_001", "impactSoft_heavy_003"], -12.0],
}

## Which Kenney pack a fallback name lives in. Both packs are flat directories of
## `.ogg`, and the names do not collide, so the directory is a function of the
## name — which keeps the catalogue above about *sounds* rather than about paths.
const SCI_FI_PREFIXES: Array = [
	"computerNoise",
	"doorClose",
	"doorOpen",
	"engineCircular",
	"explosionCrunch",
	"forceField",
	"impactMetal_0",
	"laserLarge",
	"laserRetro",
	"laserSmall",
	"lowFrequency",
	"slime",
	"spaceEngine",
	"thrusterFire",
]

## Cue id -> variant index -> the loaded stream, or null when that variant could
## not be loaded at all. Cached because a Wave asks for the same cue hundreds of
## times and `load` is not free.
var _streams: Dictionary = {}


## The stream for `cue` on `tick`, or null when neither the hero take nor any
## fallback could be loaded.
##
## `tick` picks the variant. A caller that wants the same take twice passes the
## same tick, which is what layering a shot does.
func stream_for(cue: String, tick: int = 0) -> AudioStream:
	var paths: PackedStringArray = paths_for(cue)
	if paths.is_empty():
		return null
	var index: int = posmod(tick, paths.size())
	var cached: Dictionary = _streams.get(cue, {}) as Dictionary
	if cached.has(index):
		return cached[index] as AudioStream
	var loaded: AudioStream = _load(paths[index], LOOPING_CUES.has(cue))
	cached[index] = loaded
	_streams[cue] = cached
	return loaded


## Every file this cue might play, best first: the hero take when it is on this
## machine, otherwise the committed fallbacks. Empty for a cue that is not in the
## catalogue at all.
##
## Separate from `stream_for` because *which file* is the interesting claim and the
## one a test can make without an audio device: it is how
## `tests/cases/test_game_audio.gd` asserts both that the hero takes are used when
## present and that nothing is silent when they are not.
func paths_for(cue: String) -> PackedStringArray:
	var entry: Array = CATALOGUE.get(cue, []) as Array
	if entry.is_empty():
		return PackedStringArray()

	var hero: String = entry[0] as String
	if hero != "":
		var path: String = "%s%s.ogg" % [HERO_DIRECTORY, hero]
		if FileAccess.file_exists(path):
			# One hero take, not a set: the variation a Wave needs is already in the
			# fallbacks, and a hero cue is a particular recording chosen on purpose.
			return PackedStringArray([path])

	return committed_paths(cue)


## The committed CC0 files this cue falls back to, whether or not the hero take is
## on this machine.
##
## The claim the licence makes load-bearing, and the reason it is a method rather
## than something a test digs out of `CATALOGUE`: **this list is what a clone
## without the Sonniss bundle actually hears**, which on almost every machine is
## every clone. A cue whose fallback list were empty would be a cue that is silent
## for almost everybody, and that is what `tests/cases/test_game_audio.gd` checks.
func committed_paths(cue: String) -> PackedStringArray:
	var entry: Array = CATALOGUE.get(cue, []) as Array
	var paths: PackedStringArray = PackedStringArray()
	if entry.size() < 2:
		return paths
	for name: String in entry[1] as Array:
		paths.append("%s%s.ogg" % [_pack_for(name), name])
	return paths


## The gain this cue plays at, in dB. Zero for a cue nobody declared, which is the
## loudest a missing declaration can be and therefore the easiest to notice.
func gain_db(cue: String) -> float:
	var entry: Array = CATALOGUE.get(cue, []) as Array
	if entry.size() < 3:
		return 0.0
	return entry[2] as float


## Whether this cue is playing the hero take. Reported so the HUD-free tests can
## say *which* of the two worlds they are in rather than asserting on the one this
## machine happens to be in.
func is_hero(cue: String) -> bool:
	var paths: PackedStringArray = paths_for(cue)
	return not paths.is_empty() and paths[0].begins_with(HERO_DIRECTORY)


## Every cue the catalogue declares, in a stable order. Sorted rather than in
## declaration order, because a Dictionary's key order is not something to build a
## test on.
func cues() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(CATALOGUE.keys())
	names.sort()
	return names


func _pack_for(name: String) -> String:
	for prefix: String in SCI_FI_PREFIXES:
		if name.begins_with(prefix):
			return SCI_FI
	return IMPACTS


## Loads one file, by whichever route its directory allows.
##
## The committed Kenney `.ogg` have `.import` sidecars, so `load` returns the
## engine's imported resource. The hero cues are **outside the importer's reach**
## — `assets_licensed/.gdignore` is what keeps Godot from walking seven gigabytes
## of WAV — so there is no imported resource to ask for and the file is parsed
## directly, the same trick `WeaponViewmodel` plays with `GLTFDocument`.
##
## A looping cue is handed a *duplicate* with `loop` set, because the alternative
## is mutating a shared imported resource and leaving a one-shot somewhere else
## looping forever.
func _load(path: String, looping: bool) -> AudioStream:
	var stream: AudioStream = null
	if path.begins_with(HERO_DIRECTORY):
		if not FileAccess.file_exists(path):
			return null
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		return null
	if looping:
		stream = stream.duplicate() as AudioStream
		stream.set("loop", true)
	return stream
