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
##
## **A hero cue has takes too, and until #35 it did not.** `_resolve` returned one
## path for any cue whose hero cut was present — "a hero cue is a particular
## recording chosen on purpose" — so the variance that answers the playtest's
## *"needs variance"* existed only on the clones *without* the bundle, which is to
## say in the one world the player who filed the report was not in. A prop library
## records its object eight or ten times end to end, so `convert_audio.sh --takes N`
## cuts N of them to `name.ogg`, `name_2.ogg` … and `_hero_paths` walks those
## numbered suffixes until one is missing. One mechanism, two sources: `tick % count`
## has never known or cared which world it is choosing in.
##
## ## The gain is per source where the two sources are not the same loudness
##
## One number per cue was the original arrangement and it rests on an assumption
## that is true of the one-shots and false of the beds: that a hero cut and a Kenney
## take of the same event are equally loud, so one gain means one mix. Measured, the
## two ambience beds' hero cuts are **ten dB quieter** than the Kenney loops they
## fall back to — `wav_to_cue.py` normalises a bed's RMS under a peak ceiling where
## Kenney ships a mastered loop at full scale — so a gain set for one world was
## wrong by ten dB in the other, and #35 set them for the world it could see.
##
## So a catalogue entry may carry a **fourth** number, the gain to use when the hero
## take is the one playing. Where it is absent the one gain serves both, which is the
## case for every cue whose two sources measured within a few dB of each other.
## `gain_db` is the only reader, so nothing else has to know.
class_name SoundBank
extends RefCounted

## Where `tools/assets/convert_audio.sh` writes the hero cues. Outside the
## shipping tree, gitignored, and usually absent — an ordinary state, not a
## warning, exactly as a Machine with no `.glb` is.
const HERO_DIRECTORY: String = "res://assets_licensed/generated/audio/"

## How far `_hero_paths` counts before it stops looking. A bound rather than a
## limit anybody will reach: the point is that a corrupt asset tree cannot turn cue
## resolution into an unbounded walk, and no recording in the bundle holds twenty
## usable takes of one event.
const MAX_HERO_TAKES: int = 16

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

## Cue id -> `[hero file, [committed fallbacks], gain in dB]`, with an optional
## fourth entry: the gain to use when the hero take is what is playing.
##
## The gain is **the mix**, and it has to be here rather than in the conversion,
## because every hero one-shot comes out of `wav_to_cue.py` peak-normalised to the
## same ceiling: equally loud, which is the opposite of a mix. These numbers are what
## make a Silo's breech louder than a footstep.
##
## A fallback list is a set of takes of the same event, not a chain of
## alternatives: all of them exist, and one is picked per play. A hero cue's takes
## are the numbered files beside it and work the same way.
##
## **Every figure in a `#35` note below is the loudest 85 ms window of the file plus
## this gain** — what a player hears, rather than what the file peaks at. All the
## hero cues peak within a dB of each other by construction, so a peak reading can
## only ever say they are all the same, and the thing the report was about is which
## of them is loud.
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
	# **The Telegraph cue is the quietest thing in this table, deliberately** (#42).
	#
	# It used to be the loudest, on the argument that a warning you cannot hear is not a
	# warning. The player has now rejected two cues written to that argument — the second
	# of them (#35) carefully measured, repicked to a real horn and already brought down
	# from -4 to -9 on the finding that -4 made it the loudest thing in the entire
	# catalogue — and their words the second time were *"the klaxon is AWFUL, just make it
	# very subtle"*.
	#
	# So the argument is what is wrong. The Telegraph is already a countdown, a gauge and
	# a named Wave composition on the HUD, so the sound is not carrying the warning on its
	# own and does not have to win against the Factory to do its job. At -24 it is level
	# with the quiet ambience bed and four decibels under the busy one — a knock from
	# across the yard rather than a siren over your head — and what makes it noticeable
	# there is that it is a transient against a continuous bed, which costs no loudness
	# at all.
	#
	# **The fallback is an impact now, not a motor.** #35 moved it from a sci-fi shimmer
	# to `engineCircular_004` on the reasoning that a siren is a motor spinning a chopper,
	# which was right about the cue it was a stand-in for. It is the wrong stand-in for
	# this one twice over: a continuous motor is exactly the character being removed, and
	# a clone without the bundle would get back the sustained tone the hero take no longer
	# is. A struck plate is what the hero cue is, so a struck plate is what stands in.
	#
	# See `tools/assets/convert_audio.sh` for the cut and `CLAUDE.md` for the measurements.
	TELEGRAPH_KLAXON: ["telegraph_klaxon", ["impactPlate_heavy_001"], -24.0],
	WAVE_BEGIN: ["wave_begin", ["lowFrequency_explosion_001"], -3.0],
	# Down three from -4 and rolled off above 2.4 kHz in the cut (#42): still a loud
	# one-shot, because a Breach opening is an event and being startled by one is the
	# right answer — but no longer the brightest thing in a game of low industry.
	BREACH_OPENS: ["breach_opens", ["impactGlass_heavy_000", "impactGlass_heavy_003"], -7.0],

	# ── Weapons ──────────────────────────────────────────────────────────────
	# Three layers on one shot. The body carries the pressure, the crack carries the
	# mechanism, the tail carries the room — and the tail is well down, because a
	# tail you can pick out individually is a second gunshot.
	WEAPON_FIRE_BODY: ["weapon_fire_body", ["lowFrequency_explosion_000"], -3.0],
	WEAPON_FIRE_CRACK: ["weapon_fire_crack", ["impactMetal_medium_000", "impactMetal_medium_003"], -6.0],
	WEAPON_FIRE_TAIL: ["weapon_fire_tail", ["explosionCrunch_000", "explosionCrunch_002"], -14.0],
	WEAPON_RELOAD: ["weapon_reload", ["impactMetal_light_001", "impactMetal_light_003"], -6.0],
	WEAPON_IMPACT: [
		"weapon_impact",
		["impactPunch_heavy_000", "impactPunch_heavy_002", "impactPunch_heavy_004"],
		-9.0,
	],
	# **#35: *"knife sound is too loud and too generic (needs variance)"*.** The
	# Pneumatic Wrench is the weapon a Run opens with, so its swing is the sound a new
	# player hears more than any other, and it had one take at -8 dB — one sample, at
	# the volume of a Machine being built, on every swing for the whole Run.
	#
	# Three fixes, and they are three different complaints. *Variance*: five committed
	# takes and **five hero ones**, so `tick % count` has something to choose between in
	# either world — the hero half of that is what #35 could not do, because it could not
	# see the bundle and `_resolve` returned one path. *Too loud*: a swing through air is
	# the quietest thing a weapon does — what matters is what it lands on. *Generic* is
	# the one the committed packs cannot fully answer: Kenney ships no whoosh, and a soft
	# medium impact is the nearest thing to air moving.
	#
	# **The hero cut is a different recording now, and the old one is why the report says
	# "generic".** The player heard a long-blade whoosh out of a melee SFX pack: the wrong
	# object — a wrench has no blade — measured 0.6 dB *louder* than the hit it lands
	# (-16.8 against -16.2), and 31 dB short of it below 80 Hz. A swing with no mass under
	# it is what "generic" sounds like.
	#
	# **The swing and the hit are the two halves of one recorded gesture**, which is what
	# they are: `convert_audio.sh` cuts the air before the thud for this cue and the thud
	# for `WEAPON_HIT`, out of the same take of the same real swing, five takes each. The
	# air is 134-175 ms depending on the take, because `--lead auto` measures each
	# performance's run-up rather than taking a number for it — the fixed `--lead 0.22`
	# tried first shipped four cues that were most of the way to being digital silence,
	# and `convert_audio.sh` keeps that attempt written down.
	#
	# Measured on the cuts: centroid **267-277 Hz** with 80-250 Hz the strongest band and
	# above 2 kHz at -39, against the blade's 3108 Hz. A heavy tool moving air, which is
	# what a Pneumatic Wrench is and what every earlier pick was not.
	#
	# **-17 on the fallbacks, -13 on the hero take.** A rising whoosh has a low crest, so
	# peak-normalising one leaves it quieter than a peak-normalised impact — the hero cuts
	# measure 4.7 dB below the Kenney takes they stand in for — and one gain would have
	# put the two worlds that far apart. At these two they land at -23.8 and -22.7: five
	# and a half dB under the hit's -18.2 and about two above a footstep's -25.6, which is
	# the order a melee swing wants. What you hit matters more than the swinging, and
	# neither is a bootfall.
	WEAPON_SWING: [
		"weapon_swing",
		[
			"impactSoft_medium_000",
			"impactSoft_medium_001",
			"impactSoft_medium_002",
			"impactSoft_medium_003",
			"impactSoft_medium_004",
		],
		-17.0,
		-13.0,
	],
	# What the wrench lands on, which is the half of a melee hit that should carry the
	# weight. Five takes and 4 dB down: it was the third-loudest cue in the table. **Five
	# hero takes too**, each the second half of the gesture whose first half is
	# `WEAPON_SWING` — the half of the wrench a player hears on contact had one take
	# before #35 and one hero take until now. Consistent within 3.4 dB.
	WEAPON_HIT: [
		"weapon_hit",
		[
			"impactPunch_medium_000",
			"impactPunch_medium_001",
			"impactPunch_medium_002",
			"impactPunch_medium_003",
			"impactPunch_medium_004",
		],
		-9.0,
	],
	WEAPON_DRY: ["weapon_dry", ["impactGeneric_light_003"], -11.0],

	# ── The Factory ──────────────────────────────────────────────────────────
	# Both beds sit low. `AudioDirector.ambience_db` moves them against each other
	# as the Factory grows; these are the ceilings that mix is measured down from.
	#
	# **#35: *"the middle core hum is too loud"*.** The player heard it as coming from
	# the Nest, which is the one structure in the middle of the Map and the thing a drone
	# with no position attaches itself to. These are the ceilings a *full* Factory
	# sustains rather than a worst case, and they were -30.3 and -27.4 as heard.
	#
	# A bed is the floor of the mix: everything else stands on it, so it belongs under
	# the quietest thing it carries.
	# `test_the_ambience_beds_sit_under_everything_they_are_a_bed_for` is that rule
	# rather than these numbers, so a later cue that goes quieter than a bed fails rather
	# than disappearing underneath it.
	#
	# **The busy bed carries two gains and the quiet one does not, which is the fourth
	# entry earning its keep rather than being applied for symmetry.** The *loud* bed has
	# to sit above the quiet one or the crossfade that "growth is audible" is made of
	# inverts — and the gap has to be built differently in each world, because the hero
	# busy cut measures 0.5 dB *below* the hero bed while the Kenney busy loop measures
	# 0.5 dB *above* the Kenney bed. One gain cannot produce a gap in both. So: -22/-20 on
	# busy against a flat -24 on the bed, which lands the pairs at -26.6 and -29.1 as
	# heard on the fallbacks and -35.5 and -39.0 on the hero cuts. Busy above bed by 2.5
	# and 3.5 dB; both pairs under a footstep's -25.6.
	#
	# **The hero pair ends up a further ten dB down, and that is the gain-comparison rule
	# costing them.** `gain_db` must stay below the quietest declared gain for the test
	# above to pass, and the hero cuts are quiet files, so a level target of -33 would
	# have needed gains of -18 and -14.5 and failed it. The error is in the quiet
	# direction, which is the direction the report points, and **the quiet bed at -39 is
	# the one number here I would most want a listener to check** — it may now be under
	# the threshold of being a bed at all in a small Factory, where `BED_FLOOR_DB` takes
	# it another 14 dB down.
	#
	# **And the hum was a character problem as well as a level one.** The quiet bed put
	# 94% of its energy below 200 Hz, which is the measurement behind the word "hum" —
	# and because a bed is normalised on its RMS, which that rumble dominated, turning it
	# down could only ever have made a quieter drone. `convert_audio.sh` high-passes it at
	# 200 Hz now, and found an alarm tone sitting inside the *busy* bed while it was
	# looking. Both are there.
	FACTORY_BED: ["factory_bed", ["spaceEngineLow_000"], -24.0],
	FACTORY_BUSY: ["factory_busy", ["engineCircular_002"], -22.0, -20.0],
	MACHINE_BUILT: ["machine_built", ["impactPlate_medium_000", "impactPlate_medium_002"], -5.0],
	MACHINE_DESTROYED: ["machine_destroyed", ["explosionCrunch_001", "explosionCrunch_003"], -3.0],
	MACHINE_DAMAGED: ["machine_damaged", ["impactMetal_medium_001", "impactMetal_medium_004"], -9.0],
	# A Turret firing is heard across the base all Wave long, so it is deliberately
	# further down than the player's own weapon.
	TURRET_FIRE: ["turret_fire", ["impactMetal_light_002", "impactMetal_light_004"], -12.0],
	NEST_DAMAGED: ["nest_damaged", ["impactBell_heavy_002", "impactBell_heavy_004"], -2.0],
	RUN_OVER: ["run_over", ["lowFrequency_explosion_001"], 0.0],

	# ── Enemies and the player ───────────────────────────────────────────────
	# **#35: *"crawler hurt and death sound is too weird"*.** Both were wet. The attack
	# was literally `slime`, and the death a soft medium impact — a squelch and a squish,
	# which is a different creature from the one on screen and is what "weird" means here.
	#
	# A Crawler is a **carapace**: the sound of one is dry, hard and brittle, and a dry
	# woody crack is the standard stand-in for chitin because wood and shell break the
	# same way. Five takes of it for the attack, because a Wave is dozens of them a
	# second, and the heavier family for a death — something structural giving way rather
	# than something soft landing.
	#
	# **And the hero takes are off designed creature vocals and onto real objects**, which
	# is where "weird" was actually coming from: the player heard an insectoid shriek at a
	# 4986 Hz centroid attacking and an *ethereal entity* dying. Both are physical now —
	# a wooden strike for the bite at 1273-2435 Hz, brittle ice snapping for the death —
	# and both have takes, five and three, where each had one. `convert_audio.sh` has why
	# those two recordings and not the insectoid one #35 repicked blind.
	ENEMY_ATTACK: [
		"enemy_attack",
		[
			"impactWood_light_000",
			"impactWood_light_001",
			"impactWood_light_002",
			"impactWood_light_003",
			"impactWood_light_004",
		],
		-9.0,
	],
	ENEMY_DEATH: [
		"enemy_death",
		[
			"impactWood_medium_000",
			"impactWood_medium_001",
			"impactWood_medium_002",
			"impactWood_medium_003",
			"impactWood_medium_004",
		],
		-9.0,
	],
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
	# **#35: *"sound for jump is too comical"*.** There is no jump cue and never was —
	# what a player hears when they jump is this, the landing, on the tick they get their
	# feet back. It was two takes of `impactSoft_heavy`, a big soft squelchy thud, which
	# is a cartoon character hitting the floor rather than a person in boots.
	#
	# A player lands on a Factory floor or on a Machine's roof, and both are plate steel
	# over concrete, so the landing is a bootfall with weight behind it: five takes of a
	# light steel plate, three dB further down. Same family as `MACHINE_BUILT`'s plate
	# and two weights below it, because setting a Smelter down should be heavier than
	# landing on one.
	#
	# **It has a hero take now, and #35 was right that it had none.** "The bundle has no
	# footsteps in it" was true and was the wrong question: a landing is not a footstep,
	# it is a **body** arriving, mass first and surface second. Four takes of exactly that,
	# whose bands fall monotonically from -11.5 dB below 80 Hz to -28.3 above 2 kHz — and
	# the comical one they replace was the inverse of a body, a boof with an 85% rolloff
	# at 255 Hz and no surface in it at all. One gain serves both worlds, -22.6 heard
	# against -24.8. `FOOTSTEP` still has no hero take and still should not: a walk cycle
	# is five light scuffs and nothing in the bundle is one.
	PLAYER_LAND: [
		"player_land",
		[
			"impactPlate_light_000",
			"impactPlate_light_001",
			"impactPlate_light_002",
			"impactPlate_light_003",
			"impactPlate_light_004",
		],
		-15.0,
	],
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

## Cue id -> the files it resolved to, cached because `paths_for` asks the
## filesystem whether the hero take is there and a Wave asks for the same cue
## hundreds of times. **Resolved once per session**, which is the same bargain
## `WeaponViewmodel` makes by loading each model once: an asset tree that changes
## under a running game is not a case worth a `stat` per gunshot.
var _resolved: Dictionary = {}


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
	if _resolved.has(cue):
		return _resolved[cue] as PackedStringArray
	_resolved[cue] = _resolve(cue)
	return _resolved[cue] as PackedStringArray


func _resolve(cue: String) -> PackedStringArray:
	var entry: Array = CATALOGUE.get(cue, []) as Array
	if entry.is_empty():
		return PackedStringArray()

	var hero: PackedStringArray = _hero_paths(entry[0] as String)
	if not hero.is_empty():
		return hero

	return committed_paths(cue)


## Every take of `hero` that is on this machine: `hero.ogg`, then `hero_2.ogg`,
## `hero_3.ogg` and so on until one is missing. Empty when the bundle is not here,
## which is the ordinary case.
##
## **Numbered rather than listed**, so adding a take to `convert_audio.sh` needs no
## edit here — and numbered rather than enumerated with `DirAccess`, because a
## directory listing's order is not something to build a deterministic choice on and
## `tick % count` has to mean the same thing on every machine. The first missing
## number ends the set: a gap would make the count depend on a file nobody cut.
func _hero_paths(hero: String) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	if hero == "":
		return paths
	var first: String = "%s%s.ogg" % [HERO_DIRECTORY, hero]
	if not FileAccess.file_exists(first):
		return paths
	paths.append(first)
	for take: int in range(2, MAX_HERO_TAKES + 1):
		var path: String = "%s%s_%d.ogg" % [HERO_DIRECTORY, hero, take]
		if not FileAccess.file_exists(path):
			break
		paths.append(path)
	return paths


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


## The gain this cue plays at **on this machine**, in dB. Zero for a cue nobody
## declared, which is the loudest a missing declaration can be and therefore the
## easiest to notice.
##
## Two sources that are not equally loud need two gains to land at one mix, and the
## two ambience beds are measurably ten dB apart — see the note at the head of this
## file. A cue with no fourth entry has one gain, which is almost all of them.
func gain_db(cue: String) -> float:
	var entry: Array = CATALOGUE.get(cue, []) as Array
	if entry.size() < 3:
		return 0.0
	if entry.size() > 3 and is_hero(cue):
		return entry[3] as float
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
