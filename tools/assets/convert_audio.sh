#!/usr/bin/env bash
# Cut the game's cues out of the Sonniss #GameAudioGDC source recordings.
#
#   bash tools/assets/convert_audio.sh            # every cue
#   bash tools/assets/convert_audio.sh silo paint # only cues whose name matches
#
# This file *is* the recipe — which recording becomes which cue, how long, how far
# transposed, and **why that recording** — in exactly the sense
# `convert_weapons.sh` is the recipe for the first-person arms.
# `tools/assets/wav_to_cue.py` is the mechanism it drives; nothing about what a
# Silo sounds like lives in there.
#
# ── The licence, which is the whole shape of this script ──────────────────────
#
# The Sonniss bundle is royalty-free for unlimited use in a shipped game and
# **forbids redistribution**; its EULA additionally carries a clause headed
# **NO AI TRAINING OR USAGE** (docs/ASSETS.md, docs/LICENSED_ASSETS.md). This
# repository is public. So, exactly as for the weapons:
#
#   * The input is in `assets_licensed/`, gitignored, behind a `.gdignore` so
#     Godot's importer never walks seven and a half gigabytes of WAV.
#   * **The output is gitignored too, and that is not an accident.** A cut from a
#     non-redistributable recording is a derivative of it and is exactly as
#     forbidden as the WAV. `tools/assets/check_licensed_staged.py` blocks it and
#     that guard is correct: do not work around it.
#   * Nothing under `assets_licensed/` — input or output — may ever be handed to
#     `tools/aigen/` or to any other model, as training data, as a reference, or
#     as anything else.
#   * Therefore the game loads these **at runtime, from a path that may
#     legitimately not exist**, and `game/sound_bank.gd` falls back to the
#     committed CC0 Kenney sounds for every single cue when it does not. A clone
#     without the bundle is a game that builds, tests, plays **and makes a noise
#     when you pull a lever** — it just does not get the hero take. That is
#     asserted in `tests/cases/test_game_audio.gd`.
#
# ── Why these recordings ──────────────────────────────────────────────────────
#
# docs/DESIGN.md: "Each diegetic control therefore needs its hero sound before it
# ships. Audio is load-bearing here, not polish." The five it names are Silo
# loading, Painting, Boiler startup and pressure relief, Delivery intake at the
# Nest, and the call-Wave-early lever, and each is annotated at its line below.
#
# Two recurring choices worth stating once:
#
#   * **Real mechanisms, not synthesised ones.** The Silo's dial is an antique
#     telephone's rotary dial and a mechanical counting machine; its commit is a
#     deep lock latch; the Wave lever is a barber's chair foot pump. The setting is
#     Dieselpunk (GLOSSARY.md) — 1920s-40s industry — and a 1930s object recorded
#     closely sounds like that era in a way a designed UI click never does.
#   * **Transposed down rather than time-stretched.** `--semitones` resamples, so a
#     cue drops in pitch *and* slows down together, which is how a small recorded
#     object becomes a big one. A boiler is not a motorcycle at a lower pitch; it is
#     a bigger thing turning more slowly, and resampling gives both.
#
# Set LICENSED_ROOT if your quarantine is elsewhere, AUDIO_OUT to write somewhere
# other than where the game looks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
licensed_root="${LICENSED_ROOT:-$repo_root/assets_licensed}"
out_dir="${AUDIO_OUT:-$repo_root/assets_licensed/generated/audio}"
bundle="$licensed_root/sonniss/gdc2026-game-audio-bundle"
worker="$repo_root/tools/assets/wav_to_cue.py"
ffmpeg="${FFMPEG:-ffmpeg}"

if ! command -v "$ffmpeg" >/dev/null; then
  echo "error: '$ffmpeg' is not on PATH. Install ffmpeg, or set FFMPEG." >&2
  exit 127
fi
if [ ! -d "$bundle" ]; then
  echo "note: no Sonniss bundle under $bundle — nothing to cut." >&2
  echo "      The game runs on the committed CC0 Kenney fallbacks; see" >&2
  echo "      docs/ASSET_PIPELINE.md and game/sound_bank.gd." >&2
  exit 0
fi

filters=("$@")
written=0
skipped=0
failed=0

# cue <name> <source fragment> [worker arguments...]
#
# The fragment is matched against every WAV path under the bundle. One match is
# required: zero means this machine's copy of the bundle does not have that
# library, which is a note rather than an error, and more than one means the
# recipe is ambiguous and has to be narrowed — a cue silently taking a different
# recording than the one written down here would make this file a lie.
#
# **`--takes N` writes N files, not one**: `name.ogg`, `name_2.ogg` … `name_N.ogg`,
# cut from the N loudest separate takes in the recording, strongest first. That is
# how a hero cue gets the variation the committed fallbacks have had all along —
# `game/sound_bank.gd` walks the numbered suffixes and `tick % count` picks one.
# Strongest first means the unnumbered file is the cut a single-take recipe would
# have made, so raising `--takes` adds files rather than changing the ones there.
cue() {
  local name="$1"; shift
  local fragment="$1"; shift

  if [ ${#filters[@]} -gt 0 ]; then
    local wanted=0
    for filter in "${filters[@]}"; do
      case "$name" in *"$filter"*) wanted=1 ;; esac
    done
    [ "$wanted" -eq 1 ] || return 0
  fi

  local matches=()
  while IFS= read -r line; do matches+=("$line"); done < <(
    find "$bundle" -type f -iname '*.wav' -path "*$fragment*" | sort
  )

  if [ ${#matches[@]} -eq 0 ]; then
    echo "skip  $name — no recording matching '$fragment'" >&2
    skipped=$((skipped + 1))
    return 0
  fi
  if [ ${#matches[@]} -gt 1 ]; then
    echo "error: '$fragment' matches ${#matches[@]} recordings; narrow it:" >&2
    printf '       %s\n' "${matches[@]}" >&2
    failed=$((failed + 1))
    return 0
  fi

  # How many takes this cue asked for, so the loop below knows how many files to
  # write. The worker is the authority on what `--takes` means; this only has to
  # know the count.
  local takes=1
  local index=1
  while [ $index -le $# ]; do
    if [ "${!index}" = "--takes" ]; then
      local value=$((index + 1))
      takes="${!value}"
    fi
    index=$((index + 1))
  done

  # A cue whose take count came *down* must not leave the takes it no longer has
  # behind: `sound_bank.gd` resolves a hero cue by walking the numbered suffixes
  # until one is missing, so an orphan would go on being played.
  rm -f "$out_dir/$name"_[0-9]*.ogg

  local take
  for take in $(seq 1 "$takes"); do
    local suffix=""
    [ "$take" -gt 1 ] && suffix="_$take"
    if python3 "$worker" --input "${matches[0]}" --output "$out_dir/$name$suffix.ogg" \
        --ffmpeg "$ffmpeg" --take "$take" "$@"; then
      written=$((written + 1))
    else
      failed=$((failed + 1))
    fi
  done
}

mkdir -p "$out_dir"

# ── Diegetic control 1: the Silo's loading cycle ──────────────────────────────
# DESIGN.md names this one first. The dial is two controls and they get two
# sounds, because they are two different acts: choosing *what* goes in the tube
# and choosing *how much*.

# The shell selector. An antique telephone's rotary dial: a wound spring, a
# detent, and a return — a thing with stops, which is exactly what the Simulation
# models (`PlayerController.KEY_SILO_SHELL` cycles through positions and wraps).
cue silo_dial_shell "COMTelph_Antique Telephone Rotary Dial" \
  --duration 1.1 --search 0:3

# The charge counter. A mechanical counting machine — the one recording in the
# bundle that *is* a number being wound on. It is 0.3 s long in total, so the cue
# is the whole of it.
cue silo_dial_charges "MACHMech_Mechanism Counting Machine Interact" \
  --duration 0.24 --search 0:1

# The commit: the one irreversible act a player can perform (CLAUDE.md, "Loading
# by hand, and why it cannot be taken back"). It has to sound *final* — there is no
# unload intent and there never will be — so it is **two cues played together**,
# the same layering the weapons get:
#
#   the latch   a deep lock latch, down a fourth, so it reads as a breech the size
#               of a Silo rather than a door. The recording is 0.38 s in total,
#               which transposed is the whole of this cue.
#   the body    a trailer boom under it, for the mass the latch alone has not got.
cue silo_commit "MECHLtch_Click Deep Mechanism Latch Button" \
  --duration 0.45 --semitones -5 --search 0:1
cue silo_commit_body "EffectiveTrailer_Booms_Vol2_075" --duration 1.8 --search 0:4

# The refusal — out of reach, not enough Charges, already loaded. The HUD says
# which before the key goes down; this says *that*, without a word.
cue silo_refused "Interface Deny Low Fat Dark" --duration 0.7 --search 0:2

# ── Diegetic control 2: Painting ──────────────────────────────────────────────
# A channel the player is rooted through, and the best co-op moment the design has
# (GLOSSARY.md). Three sounds, because a channel has three outcomes.

cue paint_begin "ELECArc_ArcPowerUpDesign04" --duration 1.4 --search 0:4

# The held layer. A designed electrical arc, looped, so the whole base can hear
# that somebody is standing still and committed.
cue paint_loop "ELECBuzz_Buzz27" \
  --mode loop --start 1.0 --duration 5.0 --seam 1.0 --channels 2

# It landed. A colossal-impact sweep: the Stratagem arriving is the payoff for
# every Charge the Silo ever assembled.
cue paint_complete "Impact Cut Sweep" --duration 1.6 --search 0:3

# It did not. The Charges left the Silo on the tick the channel began and nothing
# gives them back, so this is the most expensive sound in the game and it is
# deliberately an ugly one.
cue paint_interrupted "UIGlitch_Designed_Glitch_Corrupted_Data Error" \
  --duration 0.9 --search 0:3

# ── Diegetic control 3: Boiler startup and pressure relief ────────────────────
# A motorcycle's engine start, down a fifth: slower, lower, and much larger. The
# Simulation has no boiler valve Input Action yet, so these are hung on the
# Boiler's own pressure state — fire catching when its coal arrives, steam venting
# when it runs dry. See `game/audio_director.gd`.
cue boiler_startup "VEHMoto_Kawasaki Ninja ZX 10R Engine Start" \
  --duration 2.6 --semitones -7 --search 0:8

# Designed air, down a third: a vent opening under pressure.
cue boiler_relief "AEROJet_Blast Off Clean" --duration 2.0 --semitones -4 --search 0:3

# ── Diegetic control 4: the Delivery intake at the Nest ───────────────────────
# A crane's onboard ride — squeaks and motors — because what the Nest does with a
# Delivery is haul it in. Progression is physical (GLOSSARY.md), and this is the
# sound of it being physical.
cue delivery_intake "MACHInd_Crane Onboard Ride Squeaks Motors" \
  --duration 2.2 --search 2:60

# A tier opening. A real church bell, down a minor third: the Nest announcing to
# the whole Map that something new is possible.
cue delivery_complete "04 Church Bells, Near Distance" \
  --duration 3.6 --semitones -3 --search 0:30

# ── Diegetic control 5: the call-Wave-early lever ─────────────────────────────
# A barber's chair foot pump, down a major sixth. A pneumatic lever thrown by a
# whole leg: the heaviest mechanical throw in the bundle, which is what calling a
# Wave on yourself deserves.
cue call_wave_lever "OBJFurn_Barber Chair, Foot Pump" \
  --duration 1.3 --semitones -9 --search 0:8

# ── Waves ─────────────────────────────────────────────────────────────────────
# The Telegraph. A warning you cannot hear is not a warning, so this plays for
# exactly as long as the Telegraph does and stops with it.
#
# **Repicked twice, and the second time with the bundle in front of it.** #35's
# verdict was *"the alarm when starting a wave is too STUPID"*, and what the player
# heard was `EffectiveTrailer_Alarms_Vol2_QuarterNotes` — a *trailer* alarm, a
# designed cinematic sting, which means a film is starting rather than *get to your
# gun*. #35 repicked it blind to the factory-hall recording and that pick was wrong
# in two measurable ways: `--semitones` on a `--mode loop` is refused outright
# ("a transposed loop has no stable seam"), so the cue would not have been cut at
# all; and that recording's alarm is a 791 Hz tone standing 25-38 dB above its own
# neighbours for 0-33 s and 51-64 s of its 68 s — which is to say the alarm is
# *already inside* `factory_busy`, and a klaxon cut from the same hall would have
# been indistinguishable from the bed it plays over.
#
# A klaxon is an **electromagnetic diaphragm horn** — the same mechanism as a
# vehicle horn, which is why both are a single hard tone that starts and stops
# rather than a melody. So it is a motorcycle horn, an octave down: 419 Hz measured
# at 63 dB of prominence becomes 209 Hz, which is a horn the size of a building.
#
# **And then low-passed at 700 Hz, which is the part that was wrong first time.** A
# vehicle horn is piercing because its harmonics carry more energy than its root —
# transposed a fifth and left alone, the cut's strongest third octave was 2 kHz, with
# the fundamental 8.6 dB *below* it and the whole cue measuring a 2705 Hz centroid. A
# 2 kHz needle in the ear's most sensitive band, sustained for a whole Telegraph, is
# not a big horn; it is a small one held closer. Transposition moves a spectrum and
# does not re-balance it, so the balance has to be filtered: at an octave down with a
# 700 Hz low-pass the 250 Hz third octave is the strongest by 6 dB, above 2 kHz falls
# from -12.1 to -38.8, and the centroid lands at 495 Hz. Enough harmonic left to cut
# through a Factory, not enough to be a whistle.
#
# **Cut as a one-shot and looped by `LOOPING_CUES`, not as `--mode loop`.** A loop
# crossfades its own tail over its own head, which is right for a bed and fatal for
# a klaxon: it would fade *in* the one thing a warning needs, its attack. The whole
# recording transposed is 2.54 s, so looping the file rearticulates the horn every
# two and a half seconds — blast, gap, blast, which is what a real klaxon does and
# what no crossfaded bed could. The cut ends at -122 dB, so the loop is a
# rearticulation rather than a click.
cue telegraph_klaxon "VEHHorn_Honda CB500F Horn Long 02" \
  --duration 2.54 --semitones -12 --lowpass 700 --search 0:1

cue wave_begin "Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32" \
  --duration 3.0 --search 0:5

# A Breach opening. Heavy designed smash, down a fourth: the ground giving way.
cue breach_opens "GORESplt_Gore Designed Transient Heavy Impact Smash" \
  --duration 2.0 --semitones -5 --search 0:4

# ── Weapons: layered fire, reload, impact ─────────────────────────────────────
# Fire is **three cues played together**, because one file never sounds like a gun:
# a low boom for the pressure, a metallic crack for the mechanism, and a debris
# wash for the tail. `game/audio_director.gd` triggers all three off one shot and
# `game/sound_bank.gd` sets their relative levels.
cue weapon_fire_body "EffectiveTrailer_Booms_Vol2_011" --duration 0.9 --search 0:4
cue weapon_fire_crack "METLImpt_Metal Old File Impact Tap Against Tire Iron" \
  --duration 0.35 --search 0:3
cue weapon_fire_tail "Woosh Debris" --duration 1.3 --search 0:3

# Spring, clatter and seat: a magazine arriving.
cue weapon_reload "METLTonl_Item Spring Wire Impact Flick Top Clatter" \
  --duration 1.5 --search 0:20

# A round landing on an Enemy. A geophone-recorded metal thud: body-sized, and it
# rings.
cue weapon_impact "DSGNImpt_Metal Hit Thud Thump Low Ring Geofon" \
  --duration 1.0 --search 0:3

# The Pneumatic Wrench, which is the one weapon that swings rather than shoots.
#
# **#35: *"knife sound is too loud and too generic (needs variance)"*, and all three
# words were about the hero take.** What the player heard was
# `METLFric_SWING SCRAPE Swift Melee Weapon Swing With A Long Blade 14` out of a
# melee-weapon SFX pack — one cut, at a gain that put it 0.6 dB *above* the hit it
# lands (both measured as the loudest 85 ms window plus the gain: -16.8 against
# -16.2). A blade whoosh out of a designed melee pack is the definition of generic,
# and a wrench has no blade.
#
# **The swing and the hit are the two halves of one recorded gesture**, because that
# is what they are: a heavy weapon swung to a thud, recorded 21 times, one every three
# seconds, each take preceded by digital silence. The swing is the air before the thud
# and the hit is the thud, out of the same take. A player who swings and misses hears
# the first half; a player who connects hears both, in the order the microphone did.
#
# **Why this recording.** "Generic" turns out to be measurable, and what it measures is
# low-end content and spectral flatness. Four-band RMS below 80 Hz, and flatness of the
# resulting cut: the long-blade whoosh the player heard, -46.4 dB and 0.465 — a bright
# hiss, 28 dB more energy above 2 kHz than below 80, and one transient in the whole
# file, so it could not have had variance even in principle. A tape measure's spring,
# tried as the honest-tool answer, is thinner still at -71.7. A metal object swung past
# a microphone, which is the best standalone whoosh in the bundle, gets to 0.158-0.190
# flatness but sits at a 5704-6001 Hz centroid and has no separable takes, so its three
# cuts measured within 300 Hz of each other — three slices of one gust, which is the
# thing `wav_to_cue.py`'s own take-finding exists to refuse. This gesture's approach
# measures 0.078-0.108 flatness at a 2129-3101 Hz centroid: the only candidate with
# mass in it.
#
# **`--lead auto`, and the fixed lead it replaced is worth writing down.** The approach
# is inside the take, and its length is a property of the performance rather than of
# this file: 80 to 144 ms across these takes. A stated `--lead 0.22` was tried first
# and is wrong on every take but one — it reached back past the start of the gesture
# into the silence between takes, and shipped four cues that were 73-91% digital
# silence followed by the leading edge of the thud they were supposed to lead into.
# `--duration` is now the cap and the cue is as long as the air actually is.
cue weapon_swing "SWSH_SWING IMPACTS Quick Heavy Weapon Swing To Thud Impact" \
  --takes 5 --duration 0.22 --lead auto --semitones -4 --search 0:62

# What the wrench lands on, which is the half of a melee hit that should carry the
# weight: the same five takes of the same recording, from the onset on.
cue weapon_hit "SWSH_SWING IMPACTS Quick Heavy Weapon Swing To Thud Impact" \
  --takes 5 --duration 1.0 --search 0:62

# Trigger down, nothing in the pockets.
cue weapon_dry "MECHClik_USALightSwitch_On05" --duration 0.24 --search 0:1

# ── Machinery ambience that scales with the Factory ───────────────────────────
# Two beds, crossfaded by how much Factory there is. The quiet one is a tonal
# machinery roomtone and plays from the first Machine; the loud one is a busy
# factory hall and comes up as the Factory grows, so **growth is audible**
# (issue #21). `AudioDirector.ambience_db` is the mix.
#
# **#35: *"the middle core hum is too loud"*, and the spectrum says it exactly.**
# The quiet bed as the player heard it put 94% of its energy below 200 Hz — third
# octaves at 52, 58 and 57 dB at 32, 63 and 125 Hz against 32 dB at 500 — which is
# not a room, it is a **hum**, and a hum with no position attaches itself to the one
# structure in the middle of the Map. Levels alone could not fix that: a drone turned
# down is a quieter drone.
#
# So the high-pass goes from 35 Hz to 200. The recording keeps its machinery and
# loses the rumble under it, which is what turns a tone a player localises into a
# room they stand in. 35 Hz is the default because these are field recordings with
# handling noise in them; this one's low end *is* the defect.
cue factory_bed "AMBRoom_Factory Loop Heavy Machinery Tonal Roomtone" \
  --mode loop --start 4.0 --duration 24.0 --highpass 200 --channels 2

# **And the busy bed has an alarm in it, measured rather than inferred.** A 791 Hz
# tone stands 25-38 dB above its own third-octave neighbours through 0-33 s and
# 51-64 s of this 68 s recording, and #35's `--start 20.0` cut sat in the middle of
# the first of those — so a Factory at full tilt ran a continuous alarm tone under
# everything, which is the other half of what "too loud a hum" describes and would
# have made the Telegraph's own klaxon meaningless. 34-50 s is the one stretch where
# that tone is under 16 dB of prominence, so the window is 34.0 for 14 s with its
# 1.5 s seam landing at 49.5 — inside the quiet stretch at both ends.
#
# That window is **peak-bound rather than RMS-bound**: a factory hall holds clangs and
# voices, so its crest is high and the -3 dBFS ceiling stops the RMS normalisation
# reaching its -22 target, landing at -25.6. Raising the target buys nothing and
# raising the ceiling buys one dB, so the busy bed's level is set by its gain in
# `sound_bank.gd` and not here. Worth knowing before trying to fix it in the cut.
cue factory_busy "AMBInd_Factory Hall Busy Alarm Machines Voices" \
  --mode loop --start 34.0 --duration 14.0 --seam 1.5 --channels 2

# A Machine landing on the grid. A large metal box dragged, on a geophone, down a
# minor third: weight settling.
cue machine_built "METLFric_Large Metal Box, Drag, Geofon" \
  --duration 1.8 --semitones -3 --search 0:8

cue machine_destroyed "EXPLDsgn_Explosion Small Blast Enemy Death" \
  --duration 1.8 --semitones -4 --search 0:2

# A Machine being chewed on. Low tonal metal scrape.
cue machine_damaged "DSGNTonl_Metal Scrape Low Tonal LFE" --duration 1.0 --search 0:5

# A Turret firing, from across the base. Metal banging, down a tone.
cue turret_fire "METLImpt_Metal Bangs, Metal Hits, Banging On Doors" \
  --duration 0.5 --semitones -2 --search 0:10

# The Nest taking a hit. Bowed metal screech with a long reverb — the structure
# itself complaining, which is the one sound in the game that should make a player
# stop what they are doing.
cue nest_damaged "DSGNTonl_Designed Metal Bowed Screech Tonal Reverb" \
  --duration 2.4 --search 0:12

cue run_over "Transition Braam Slow Dark Creepy" --duration 4.0 --search 0:2

# ── Enemies and the player ────────────────────────────────────────────────────
# **#35: *"crawler hurt and death sound is too weird"*, and both cues were designed
# creature vocals.** The attack was `CREAInsc_Insectoid Creature Tremble Attack` —
# measured centroid 4986 Hz, a thin shriek — and the death was
# `CREAEthr_Ethereal Entity Grim Pain Long`, which is a *ghost*. "Weird" is the right
# word for a ghost dying in front of something with a carapace, and #35 repicked both
# onto the insectoid vocal without the bundle to check it, which keeps the thinner
# half of the problem.
#
# A Crawler is a **carapace**, and a carapace is dry, hard and brittle. So both ends
# of its life are real objects rather than designed voices, which is #21's own
# standard: a wooden spear-and-stick strike for the bite, down a tone, out of a
# library with nine separable takes in eleven seconds — because a Wave is dozens of
# bites a second and one sample is a machine gun. And for the death, ice snapping:
# three takes of something brittle and structural giving way, down a major third. The
# same family the committed fallbacks landed on (`impactWood_*`), so the two worlds
# now describe the same animal.
cue enemy_attack "WEAPBlnt_Spear And Stick Impact, Wooden MKH 2" \
  --takes 5 --duration 0.6 --semitones -2 --search 0:12
cue enemy_death "ice, crack, ice block snapping-001" \
  --takes 3 --duration 0.9 --semitones -4 --search 0:6
cue player_hurt "HMNBrth_Police Officer Gasp Vocal Male Shocked Alert" \
  --duration 0.44 --search 0:1
cue player_down "VOXReac_Construction Kit Male Flutter Death Vocal" \
  --duration 1.6 --search 0:4

# **#35: *"sound for jump is too comical"*.** There is no jump cue and never was —
# what a player hears when they jump is the landing, on the tick they get their feet
# back, and until now that cue had **no hero take at all**: the bundle ships no
# footsteps, so it was Kenney's and #35 fixed it there. But a landing is not a
# footstep: it is a **body** arriving, and the spectrum of the one the player called
# comical says why they called it that — the Kenney `impactSoft_heavy` it was has a
# centroid of 72-143 Hz and an 85% rolloff at 102-255 Hz, which is a low boof with no
# surface in it at all.
#
# A body landing is mass first and contact detail second, so the pick is the recording
# whose bands fall monotonically from the bottom up: below 80 Hz **-19.7**, 80-250
# -26.4, 250 Hz-2 kHz -32.9, above 2 kHz -39.8. Four separable takes within 0.6 dB of
# each other, down a minor third. A steel stairwell door was tried first and measured
# 16 dB the wrong way round — -52.2 below 80 Hz against -36.2 above 2 kHz — and -3
# semitones does not move a 3.8 kHz centroid into bootfall territory.
#
# `FOOTSTEP` still has no hero take and still should not: a walk cycle is five light
# scuffs and nothing in the bundle is one.
cue player_land "FGHTImpt_4 x Punch, Body 02" \
  --takes 4 --duration 0.5 --semitones -3 --search 0:5

echo
echo "Wrote $written cue(s) to $out_dir; skipped $skipped; failed $failed."
if [ "$written" -gt 0 ]; then
  du -sh "$out_dir"
fi
echo
echo "Nothing in that directory may be committed. It is gitignored, the licence"
echo "guard blocks it, and the game loads it at runtime and runs without it —"
echo "game/sound_bank.gd falls back to the committed CC0 Kenney sounds."
[ "$failed" -eq 0 ]
