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

  if python3 "$worker" --input "${matches[0]}" --output "$out_dir/$name.ogg" \
      --ffmpeg "$ffmpeg" "$@"; then
    written=$((written + 1))
  else
    failed=$((failed + 1))
  fi
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
# The Telegraph, and **the third attempt at it, which is not an alarm** (#42).
#
# The player's verdict on the second was *"the klaxon is AWFUL, just make it very
# subtle"*. The first was a trailer alarm in quarter notes — a designed cinematic
# sting, which is the thing this file's own standard rules out. The second was a
# motorcycle horn an octave down and low-passed to 700 Hz, measured and argued for
# at length, and the player hated that too. Three goes at "the right alarm" is
# enough evidence that **the category is wrong**, not the pick inside it.
#
# What a siren does is demand attention, continuously, for as long as it runs, and
# nothing in this game needs that: the Telegraph is already on the HUD with a
# countdown, a gauge and the Wave's composition on it (CLAUDE.md, "nothing arrives
# unannounced"). The audio does not have to carry the warning on its own. It has to
# make a player *look up*.
#
# So it is a **struck plate heard from across the yard**: a geofon hit, which is a
# low metal thud with a short ring and a long tail of nothing. That is what a works
# alarm was before electricity — somebody hitting a length of rail with a hammer —
# so it belongs in a 1930s foundry in a way a vehicle horn never did, and it is
# low, dull and over almost immediately, which are the three things a siren is not.
#
# Cut long and left mostly empty on purpose. The hit is under a second and the file
# runs five, so `LOOPING_CUES` rearticulates it about every five seconds: a slow,
# quiet knock that keeps going until the Wave arrives, rather than a tone held
# across the whole Telegraph. The gap is the point — a sound that stops is a sound a
# player can think over.
#
# Filtered hard and low. 320 Hz low-pass takes off the metallic ring that makes a
# struck plate read as *near*, and a 45 Hz high-pass takes off the subsonic thump
# that would otherwise eat headroom nobody can hear. What is left is the body of the
# hit: dull, distant and below everything the Factory is doing. The level is in
# `game/sound_bank.gd` and is the other half of this; see the note there.
cue telegraph_klaxon "DSGNImpt_Metal Hit Thud Thump Low Ring Geofon 1" \
  --duration 5.0 --start 0.0 --lowpass 600 --highpass 90 --channels 2

cue wave_begin "Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32" \
  --duration 3.0 --search 0:5

# A Breach opening. Heavy designed smash, down a fourth: the ground giving way.
#
# **Rolled off above 2.4 kHz** (#42). There is no separate Breach klaxon — the only
# sustained warning in the game is the Telegraph's, above — but this is the nearest
# thing to one and it had the same defect for the same reason: the cut measured a
# 4610 Hz centroid, which is a bright splattery crack sitting squarely in the ear's
# most sensitive band, in a game whose whole palette is low industrial. The source
# is a gore splatter and it was audibly a gore splatter at the top end.
#
# It stays a **loud one-shot**, and that is the difference from the klaxon: a Breach
# opening is an event, it happens once, and being startled by it is the correct
# response. What was wrong was the band, not the level — so the level moved three
# decibels and the top moved an octave.
cue breach_opens "GORESplt_Gore Designed Transient Heavy Impact Smash" \
  --duration 2.0 --semitones -5 --lowpass 2400 --search 0:4

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
cue weapon_swing "METLFric_SWING SCRAPE Swift Melee Weapon Swing" --duration 0.7 --search 0:4
cue weapon_hit "METLImpt_METAL SWING HIT Weapon Swing To Metallic Body" \
  --duration 1.2 --search 0:4

# Trigger down, nothing in the pockets.
cue weapon_dry "MECHClik_USALightSwitch_On05" --duration 0.24 --search 0:1

# ── Machinery ambience that scales with the Factory ───────────────────────────
# Two beds, crossfaded by how much Factory there is. The quiet one is a tonal
# machinery roomtone and plays from the first Machine; the loud one is a busy
# factory hall with alarms and machines in it and comes up as the Factory grows,
# so **growth is audible** (issue #21). `AudioDirector.ambience_db` is the mix.
cue factory_bed "AMBRoom_Factory Loop Heavy Machinery Tonal Roomtone" \
  --mode loop --start 4.0 --duration 24.0 --channels 2
cue factory_busy "AMBInd_Factory Hall Busy Alarm Machines Voices" \
  --mode loop --start 20.0 --duration 24.0 --channels 2

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
cue enemy_attack "CREAInsc_Insectoid Creature Tremble Attack" --duration 1.0 --search 0:6
cue enemy_death "CREAEthr_Ethereal Entity Grim Pain Long" --duration 1.2 --search 0:6
cue player_hurt "HMNBrth_Police Officer Gasp Vocal Male Shocked Alert" \
  --duration 0.44 --search 0:1
cue player_down "VOXReac_Construction Kit Male Flutter Death Vocal" \
  --duration 1.6 --search 0:4

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
