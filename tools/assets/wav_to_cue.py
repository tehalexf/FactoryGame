#!/usr/bin/env python3
"""Cut one game cue out of one long source recording.

    python3 tools/assets/wav_to_cue.py --input big.wav --output cue.ogg \
        --mode oneshot --duration 1.2

The Sonniss libraries are **source recordings for sound design, not game SFX**
(docs/LICENSED_ASSETS.md): single files run to hundreds of megabytes, start with
seconds of room tone, and hold several takes of the same prop end to end. Nothing
in them can be loaded at runtime as it ships. Something has to cut, trim,
normalise and convert, and the choice is between somebody's shell history and a
script.

This is the script. `tools/assets/convert_audio.sh` is the recipe that drives it
— which recording becomes which cue — in the same relationship
`convert_weapons.sh` has with `fbx_to_viewmodel.py`.

## The one interesting decision: the in-point is measured, not remembered

A hand-picked in-point is a number nobody can re-derive. Worse, it is a number
that silently becomes wrong if the pack is ever re-downloaded with a different
master. So `--mode oneshot` **finds the loudest transient in the search window
and cuts around it**: `astats` is run with a short reset interval, the frame with
the highest peak is the attack, and the window opens `PRE_ATTACK_SECONDS` ahead
of it so the cut lands before the hit rather than on it.

That is repeatable, it needs no ears, and for a prop recording — where the
loudest moment *is* the event — it picks the event. Where a recording holds
several takes it picks the biggest, which is the one worth shipping. A recipe
that disagrees can narrow the hunt with `--search` or override it outright with
`--start`.

`--takes N` is the same measurement asked `N` times, and it is what answers #35's
*"needs variance"* on a machine that has the bundle. A prop library records one
object eight or ten times end to end, so the several takes of a cue are several
takes of a real event rather than several slices of one — the loudest frame, its
onset, then that whole take forbidden and the next loudest found, repeating while
anything is within `TAKE_FLOOR_DB` of the first. **Strongest first**, so take 1 is
the cut the single-take path would have made and asking for a fifth take leaves the
first four alone. A recording holding fewer separable takes than the recipe asked
for is an error naming both numbers.

`--lead` opens the cut *ahead* of that in-point instead of on it, which is what lets
one recorded gesture become the two cues the game plays. A real swing-to-impact is
air and then a thud; the swing cue is the air, ending where the thud begins, and the
hit cue is the same take from the onset on. Both halves then come off one recording
of one real event rather than two libraries that have never met.

**`--lead auto` measures the run-up rather than taking a number for it**, for the
same reason the in-point is measured: the approach is *inside* the take and its
length is a property of the performance, not of the recipe. Measured on the bundle's
own swing-impact library the run-ups are 80, 85, 91, 96, 96, 123, 128 and 144 ms, so
a stated lead is wrong on every take but one — and the first attempt at this cue
stated 0.22 s against a 113 ms mean, which put four of five cues 73-91% into the
digital silence *between* takes. `--duration` becomes the cap, and the cue is as long
as the air it found.

`--mode loop` takes a declared window instead, because an ambience bed has no
transient to find, and then **crossfades its own tail over its own head** so the
file loops without a click. The output is `duration` long and seamless; the extra
`--seam` seconds are read past the window and folded back in.

## Levels

One-shots are peak-normalised, which is what a transient wants: the hit arrives
at a known ceiling and the mix is set by the cue's gain in `game/sound_bank.gd`.
Loops are **RMS**-normalised under a peak ceiling, because an ambience bed is
judged by how loud it sits, not by its worst sample, and a bed peak-normalised
against one distant clang is a bed nobody can hear.

Mono by default: a positional `AudioStreamPlayer3D` discards one channel of a
stereo stream anyway, so a stereo one-shot is half a file wasted. Loops ask for
`--channels 2` because the ambience bed is not positional.

## Licence

Every input to this script is licensed for use in a shipped game and forbidden
from redistribution, and the Sonniss EULA additionally prohibits AI/ML use of any
kind. **The output is therefore quarantined exactly as the input is**, and
nothing here ever writes into the shipping tree. See `convert_audio.sh`, which
says so again where it is impossible to miss.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# How far ahead of the measured attack the cut opens. Long enough that the
# transient's own leading edge survives — cutting *on* a peak clips the attack and
# makes a heavy sound thin — and short enough not to drag silence in with it.
PRE_ATTACK_SECONDS = 0.045

# How far below the stretch's loudest sample still counts as "the hit has landed",
# in dB. 6 dB is half the amplitude: a frame already that loud is unmistakably part
# of the transient and not the room tone before it.
ONSET_TOLERANCE_DB = 6.0

# How long the search listens for by default. The longest recordings here run to
# twenty minutes and analysing all of it costs minutes; the event a prop library is
# selling is always near the front.
DEFAULT_SEARCH_SECONDS = 60.0

# What a one-shot's loudest sample is normalised to, in dBFS. Not 0: a Vorbis
# encode can overshoot its input by a fraction of a dB, and a cue that clips only
# after encoding is the worst kind to debug.
DEFAULT_PEAK_DBFS = -1.0

# What a loop's RMS is normalised to, and the ceiling its peaks may not cross.
DEFAULT_RMS_DBFS = -22.0
DEFAULT_LOOP_PEAK_DBFS = -3.0

# How many samples each frame the attack hunt reads covers. ffmpeg's own audio
# frame is 4096, which quantises every in-point in this file to 85 ms; this is the
# precision the whole measured-in-point idea actually needs, and it is cheap —
# eight times as many frames to parse, seconds on the longest search here.
ANALYSIS_FRAME_SAMPLES = 512

# How far below the loudest take in a search window a quieter one still counts as
# a take of the same event. A prop library records the same object eight or ten
# times and they are never the same loudness; 22 dB takes the quiet ones and
# still refuses the room tone between them.
TAKE_FLOOR_DB = 22.0

# How long a loop's tail is folded back over its head. Long enough to hide the
# seam in a broadband bed, short enough that a rhythmic one does not audibly
# stutter.
DEFAULT_SEAM_SECONDS = 1.5

# Everything is resampled to this. Godot mixes at 44.1 kHz by default and will
# resample whatever it is given; one rate across the set means one resample
# behaviour across the set.
SAMPLE_RATE = 48000

# Vorbis quality. 5 is transparent for SFX at a third of the size of 8, and these
# are short.
VORBIS_QUALITY = 5

# Below this a frame is silence rather than a quiet passage, and the attack hunt
# ignores it. `astats` reports -inf for a truly empty frame, which is not a number
# `max` can be trusted with.
SILENCE_FLOOR_DBFS = -70.0


class CueError(RuntimeError):
    """Something about this cut cannot be carried out, described for a human."""


@dataclass
class Levels:
    """What a stretch of audio measures, in dBFS."""

    peak_dbfs: float
    rms_dbfs: float


def _run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, check=False)


def _require_tools(ffmpeg: str, ffprobe: str) -> None:
    for tool in (ffmpeg, ffprobe):
        if shutil.which(tool) is None:
            raise CueError(
                "'%s' is not on PATH. Install ffmpeg, or set FFMPEG/FFPROBE." % tool
            )


def source_duration_seconds(path: Path, ffprobe: str = "ffprobe") -> float:
    """How long the recording is. Needed because a cut may not run off the end."""
    result = _run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(path),
        ]
    )
    if result.returncode != 0:
        raise CueError("could not read %s: %s" % (path, result.stderr.strip()))
    try:
        return float(json.loads(result.stdout)["format"]["duration"])
    except (KeyError, ValueError, json.JSONDecodeError) as problem:
        raise CueError("%s reports no duration: %s" % (path, problem)) from problem


# ── Finding the attack ────────────────────────────────────────────────────────

# What `ametadata=print` writes, two lines per audio frame: the frame's start time,
# then the statistic. They are matched together rather than separately because a
# peak with no time attached is a frame index, and a frame index is not a second —
# ffmpeg's audio frames are 4096 samples, not whatever interval the hunt would like
# them to be, and assuming otherwise is wrong by a factor of three.
_PEAK_FRAME = re.compile(
    r"pts_time:(-?[0-9]+(?:\.[0-9]+)?)\s*\n"
    r"lavfi\.astats\.Overall\.Peak_level=(-?[0-9]+(?:\.[0-9]+)?|-?inf)"
)


def parse_frame_peaks(metadata: str) -> list[tuple[float, float]]:
    """`(frame start in seconds, peak in dBFS)` for every frame, in order.

    Split out from the subprocess so the parsing is testable without ffmpeg. A
    frame ffmpeg reports as `-inf` comes back as `-inf`, which compares correctly
    and is never the maximum of a stretch with any signal in it at all.
    """
    frames: list[tuple[float, float]] = []
    for match in _PEAK_FRAME.finditer(metadata):
        text = match.group(2)
        frames.append(
            (float(match.group(1)), -math.inf if text.endswith("inf") else float(text))
        )
    return frames


def attack_offset_seconds(frames: list[tuple[float, float]]) -> float:
    """How far into the searched stretch the loudest transient begins.

    **`astats` is left cumulative**, which is what makes this one pass rather than
    two. With its `reset` disabled each frame's reported peak is the loudest sample
    *so far*, so the figure is a staircase that rises to the stretch's overall peak
    and then stays flat.

    Reading the top of that staircase would find the loudest *sample*, which is not
    the same instant as the onset: a heavy hit keeps getting louder for tens of
    milliseconds after it starts, and ffmpeg's audio frames are 85 ms wide, so
    cutting at the top of the staircase lands audibly inside the attack and makes a
    weighty sound thin. So the onset is taken as the **first frame within
    `ONSET_TOLERANCE_DB` of the top** — the moment the hit is already essentially at
    full force — and the window opens `PRE_ATTACK_SECONDS` ahead of that.

    Zero when nothing rises above silence, which is the honest answer for a stretch
    of room tone and leaves the caller cutting from the front.
    """
    loudest = max((peak for _, peak in frames), default=-math.inf)
    if loudest <= SILENCE_FLOOR_DBFS:
        return 0.0
    for second, peak in frames:
        if peak >= loudest - ONSET_TOLERANCE_DB:
            return max(0.0, second - PRE_ATTACK_SECONDS)
    return 0.0


def take_offsets_seconds(
    frames: list[tuple[float, float]], count: int, min_gap_seconds: float
) -> list[float]:
    """Where the `count` loudest separate takes in a stretch begin, strongest first.

    A prop library records the same object eight or ten times end to end, which is
    the one thing in the bundle that answers *"needs variance"*: several cuts of one
    recording are several takes of one event, where several in-points of one
    continuous whoosh are three slices of the same gust.

    **The frames here are not cumulative.** `attack_offset_seconds` reads the
    staircase `reset=0` produces, which can only ever find one event; this reads
    per-frame peaks, so the envelope rises and falls once per take.

    Greedy, because the alternative — thresholding — needs a threshold, and the
    loudness of a prop recording's quietest usable take is not knowable in advance.
    So: take the loudest frame, back it off to its own onset exactly as
    `attack_offset_seconds` does, forbid `min_gap_seconds` either side of it so the
    same take cannot be picked twice, and repeat while the next loudest is within
    `TAKE_FLOOR_DB` of the first.

    **Strongest first, not earliest first**, so take 1 is the take the single-cut
    path would have chosen and asking for one more take appends rather than
    renumbering every cue that was already cut.
    """
    if count < 1 or not frames:
        return []
    loudest = max(peak for _, peak in frames)
    if loudest <= SILENCE_FLOOR_DBFS:
        return []

    remaining = [peak for _, peak in frames]
    offsets: list[float] = []
    while len(offsets) < count:
        peak = max(remaining)
        if peak <= loudest - TAKE_FLOOR_DB or peak == -math.inf:
            break
        index = remaining.index(peak)
        onset = index
        while onset > 0 and frames[onset - 1][1] >= frames[index][1] - ONSET_TOLERANCE_DB:
            onset -= 1
        second = max(0.0, frames[onset][0] - PRE_ATTACK_SECONDS)
        # **The gap is enforced on the onsets, not only on the peaks**, and that is
        # not redundant: a take whose envelope stays within `ONSET_TOLERANCE_DB` for
        # half a second backs two peaks that *are* a gap apart off to two onsets
        # that are not, and the cuts then overlap. Measured on a tool recording,
        # which gave takes 80 ms apart from peaks 400 ms apart — two files that are
        # all but the same sound, which answers "needs variance" with a copy.
        if all(abs(second - taken) >= min_gap_seconds for taken in offsets):
            offsets.append(second)
        for other in range(len(frames)):
            if abs(frames[other][0] - frames[index][0]) < min_gap_seconds:
                remaining[other] = -math.inf
    return offsets


def approach_offsets_seconds(
    frames: list[tuple[float, float]], onsets: list[float]
) -> list[float]:
    """How long the run-up to each of `onsets` lasts, in seconds, in the same order.

    **The measurement `--lead auto` is made of, and the reason a fixed lead was
    wrong.** A melee library records a swing-to-impact as one gesture with digital
    silence between takes, so the air before the hit is *inside* the take and its
    length is a property of the performance: measured on the bundle's own
    swing-impact recording the run-ups are 80, 85, 91, 96, 96, 123, 128 and 144 ms.
    A recipe that names one number is therefore wrong on every take but one, and
    wrong in the direction that matters — #35 shipped `--lead 0.22` against a 113 ms
    mean, so four of five cues were 73-91% digital silence followed by the leading
    edge of the thud they were supposed to lead into.

    So the run-up is read rather than declared: from the onset, walk back while
    there is still signal, and stop at the silence that separates this take from the
    one before it. `SILENCE_FLOOR_DBFS` is the floor because that is already this
    file's definition of "nothing here", and a prop library's inter-take gap is
    digital silence at -95 dB or below rather than room tone.

    Zero for a take that runs straight out of the start of the stretch or out of
    continuous signal — honest, and it leaves the caller cutting from the onset
    exactly as it would without a lead.
    """
    if not frames:
        return [0.0 for _ in onsets]
    approaches: list[float] = []
    for onset in onsets:
        # The frame the onset names. `take_offsets_seconds` has already backed the
        # onset off by `PRE_ATTACK_SECONDS`, so the search starts at or just before
        # the frame the attack is in, which is what we want to walk back from.
        index = 0
        for position, (second, _) in enumerate(frames):
            if second > onset:
                break
            index = position
        edge = index
        while edge > 0 and frames[edge - 1][1] > SILENCE_FLOOR_DBFS:
            edge -= 1
        if edge == 0:
            # The walk ran off the front without meeting silence, so this take does
            # not begin inside the searched stretch and its run-up is **not
            # bounded** by anything here. Reporting the whole stretch would cut
            # however much audio happened to precede the window and call it a swing;
            # zero says "nothing measurable", and `convert` turns that into a
            # refusal naming the cue.
            approaches.append(0.0)
            continue
        approaches.append(max(0.0, frames[index][0] - frames[edge][0]))
    return approaches


def _frame_peaks(
    path: Path,
    search_start: float,
    search_length: float,
    cumulative: bool,
    ffmpeg: str,
) -> list[tuple[float, float]]:
    """Every audio frame's peak across the search window, as `astats` reports it."""
    result = _run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostdin",
            "-ss",
            "%.3f" % search_start,
            "-t",
            "%.3f" % search_length,
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-af",
            # **Re-frame before measuring.** ffmpeg's native audio frame is 4096
            # samples — 85 ms — and the onset is read off a frame *start*, so the
            # real attack can sit anywhere inside it: the cut opens between 45 ms
            # before the hit and 40 ms after it, differently for every take.
            # Measured across a four-take series, the RMS of each cue's first 75 ms
            # spread **44.0 dB** at 4096 samples and 4.9 dB at 512 — three of the
            # four opened in digital silence and arrived late. 512 samples is
            # 10.7 ms, under the ~20 ms at which an offset stops being heard as a
            # separate event. `p=0` leaves the last short frame unpadded.
            "asetnsamples=n=%d:p=0,"
            "astats=metadata=1:reset=%d,"
            "ametadata=print:key=lavfi.astats.Overall.Peak_level:file=-"
            % (ANALYSIS_FRAME_SAMPLES, 0 if cumulative else 1),
            "-f",
            "null",
            "-",
        ]
    )
    if result.returncode != 0:
        raise CueError("could not analyse %s: %s" % (path, result.stderr.strip()[-400:]))
    # `file=-` writes the metadata to stdout; the progress report goes to stderr.
    return parse_frame_peaks(result.stdout)


def find_attack(
    path: Path,
    search_start: float,
    search_length: float,
    ffmpeg: str = "ffmpeg",
) -> float:
    """The absolute second the loudest transient in the search window begins."""
    frames = _frame_peaks(path, search_start, search_length, True, ffmpeg)
    return search_start + attack_offset_seconds(frames)


def find_takes(
    path: Path,
    search_start: float,
    search_length: float,
    count: int,
    min_gap_seconds: float,
    ffmpeg: str = "ffmpeg",
) -> list[float]:
    """The absolute seconds the `count` loudest separate takes begin, strongest first.

    A recording with fewer separable takes than the recipe asked for is an **error
    naming both numbers**, not a cue that quietly ships the same cut twice: the
    whole value of several takes is that they are different, so silently writing
    four copies of one would answer the report it exists to answer with a lie.
    """
    return [onset for onset, _ in find_take_windows(
        path, search_start, search_length, count, min_gap_seconds, ffmpeg
    )]


def find_take_windows(
    path: Path,
    search_start: float,
    search_length: float,
    count: int,
    min_gap_seconds: float,
    ffmpeg: str = "ffmpeg",
) -> list[tuple[float, float]]:
    """`(onset, run-up length)` for each of the `count` loudest takes, strongest first.

    One analysis pass for both numbers, because they come off the same envelope and
    reading it twice would be two ffmpeg invocations over the same minute of audio.
    `find_takes` is this with the run-ups dropped.
    """
    frames = _frame_peaks(path, search_start, search_length, False, ffmpeg)
    offsets = take_offsets_seconds(frames, count, min_gap_seconds)
    if len(offsets) < count:
        raise CueError(
            "%s holds %d separable take(s) in %.1f s from %.1f s, and %d were asked for"
            % (path, len(offsets), search_length, search_start, count)
        )
    approaches = approach_offsets_seconds(frames, offsets)
    return [
        (search_start + offset, approach)
        for offset, approach in zip(offsets, approaches)
    ]


# ── Measuring and setting levels ──────────────────────────────────────────────

# `astats` writes its report to stderr with ffmpeg's own filter prefix in front of
# every line — `[Parsed_astats_0 @ 0x…] Peak level dB: -18.17` — so these must not
# be anchored to the start of a line.
_LEVEL_LINES = {
    "peak_dbfs": re.compile(r"\bPeak level dB:\s*(-?[0-9.]+|-?inf)"),
    "rms_dbfs": re.compile(r"(?<!RMS )\bRMS level dB:\s*(-?[0-9.]+|-?inf)"),
}


def parse_levels(astats_report: str) -> Levels:
    """The overall peak and RMS out of an `astats` report."""
    found: dict[str, float] = {}
    for name, pattern in _LEVEL_LINES.items():
        matches = pattern.findall(astats_report)
        if not matches:
            raise CueError("astats reported no %s" % name)
        # astats prints per-channel blocks and then an Overall block; the last
        # match is the overall one, which is the figure a mono-downmixed cue wants.
        text = matches[-1]
        found[name] = -math.inf if text.endswith("inf") else float(text)
    return Levels(peak_dbfs=found["peak_dbfs"], rms_dbfs=found["rms_dbfs"])


def measure(path: Path, ffmpeg: str = "ffmpeg") -> Levels:
    result = _run(
        [
            ffmpeg,
            "-hide_banner",
            "-nostdin",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-af",
            "astats=measure_perchannel=none",
            "-f",
            "null",
            "-",
        ]
    )
    if result.returncode != 0:
        raise CueError("could not measure %s: %s" % (path, result.stderr.strip()[-400:]))
    return parse_levels(result.stderr)


def normalising_gain_db(
    levels: Levels,
    peak_target_dbfs: float,
    rms_target_dbfs: float | None,
) -> float:
    """How much to turn a measured clip up or down, in dB.

    With no RMS target this is plain peak normalisation. With one it is RMS
    normalisation **under** the peak ceiling: the quieter of the two gains wins, so
    a bed is brought up to a usable loudness unless doing so would clip it.
    """
    if levels.peak_dbfs == -math.inf:
        # Silence. Any gain leaves it silent; 0 keeps the arithmetic honest.
        return 0.0
    headroom = peak_target_dbfs - levels.peak_dbfs
    if rms_target_dbfs is None or levels.rms_dbfs == -math.inf:
        return headroom
    return min(headroom, rms_target_dbfs - levels.rms_dbfs)


# ── Cutting ───────────────────────────────────────────────────────────────────


def _colour(highpass: int, lowpass: int) -> list[str]:
    """The tone shaping every cut gets, if any was asked for.

    A high-pass by default, at 35 Hz: these are field recordings and several carry
    handling rumble and traffic well below anything a game speaker reproduces, which
    costs bitrate and headroom and buys nothing.
    """
    stages: list[str] = []
    if highpass > 0:
        stages.append("highpass=f=%d" % highpass)
    if lowpass > 0:
        stages.append("lowpass=f=%d" % lowpass)
    return stages


def speed_ratio(semitones: float) -> float:
    """The playback-rate multiplier `semitones` of transposition amounts to.

    Below 1 for a downward shift, which also makes the clip longer — that is the
    whole point. Resampling rather than time-stretching is deliberate: a boiler is
    not a motorcycle played at the same speed and a lower pitch, it is a bigger
    thing moving more slowly, and dropping the rate gives both at once. Phase-
    vocoder pitch shifting would preserve the tempo and keep the small-object cues
    a listener reads as "small object".
    """
    return 2.0 ** (semitones / 12.0)


def _transpose(ratio: float) -> list[str]:
    """Resample to the shipping rate, re-label it, resample back.

    `asetrate` re-labels the stream's rate without touching its samples, so the
    following `aresample` is what actually transposes it. The `aresample` *before*
    it is not redundant: `asetrate` takes an absolute rate, so the arithmetic is
    only right if the input is known to be at `SAMPLE_RATE` already.
    """
    if abs(ratio - 1.0) < 1e-6:
        return []
    return [
        "aresample=%d" % SAMPLE_RATE,
        "asetrate=%d" % int(round(SAMPLE_RATE * ratio)),
        "aresample=%d" % SAMPLE_RATE,
    ]


def one_shot_filter(
    duration: float, highpass: int, lowpass: int, gain_db: float, ratio: float = 1.0
) -> str:
    """The whole chain for a one-shot, as a simple `-af` string.

    `duration` is the length of the **output**, after any transposition, which is
    why the transposition comes first and the fade is positioned against it. The
    caller trims `duration * ratio` out of the source to feed it.
    """
    stages = _transpose(ratio) + _colour(highpass, lowpass)
    # A tail fade, always. A cut through a decaying resonance clicks, and a tenth
    # of the cue is short enough never to blunt an attack.
    fade = max(0.02, duration * 0.1)
    stages.append("afade=t=out:st=%.4f:d=%.4f" % (max(0.0, duration - fade), fade))
    stages.append("volume=%.3fdB" % gain_db)
    return ",".join(stages)


def loop_filter_complex(
    start: float,
    duration: float,
    seam: float,
    highpass: int,
    lowpass: int,
    gain_db: float,
) -> str:
    """A seamless loop: the window, with the `seam` seconds after it folded back in.

    `asplit` is what lets one input be read twice. The head fades *in* across the
    seam and the tail fades *out* across it, and `amix` lines both up at zero —
    so the sum is flat, the file is `duration` long, and its end meets its start.

    The gain is folded in here rather than added as an `-af` afterwards, because
    ffmpeg refuses to put a simple filter on a stream that came out of a complex
    graph. One filter string per mode, carrying everything that mode does.
    """
    tint = "".join("," + stage for stage in _colour(highpass, lowpass))
    return (
        "[0:a]asplit=2[head][tail];"
        "[head]atrim=start=%.4f:end=%.4f,asetpts=N/SR/TB,afade=t=in:st=0:d=%.4f%s[h];"
        "[tail]atrim=start=%.4f:end=%.4f,asetpts=N/SR/TB,afade=t=out:st=0:d=%.4f%s[t];"
        "[h][t]amix=inputs=2:duration=first:dropout_transition=0:normalize=0,"
        "volume=%.3fdB[out]"
        % (
            start,
            start + duration,
            seam,
            tint,
            start + duration,
            start + duration + seam,
            seam,
            tint,
            gain_db,
        )
    )


def encode_arguments(
    source: Path,
    mode: str,
    start: float,
    duration: float,
    seam: float,
    highpass: int,
    lowpass: int,
    gain_db: float,
    ratio: float = 1.0,
) -> list[str]:
    """The ffmpeg input and filter arguments for one cut at one gain.

    Called twice per cue with two different gains — once at unity to measure the
    cut, once at the gain that measurement chose — so the two encodes are the same
    cut by construction rather than by two code paths agreeing.
    """
    if mode == "loop":
        return [
            "-i",
            str(source),
            "-filter_complex",
            loop_filter_complex(start, duration, seam, highpass, lowpass, gain_db),
            "-map",
            "[out]",
        ]
    return [
        "-ss",
        "%.4f" % start,
        # `duration` is the output's length, so a transposed cue reads `ratio` times
        # that much source: pitched down it needs more, pitched up it needs less.
        "-t",
        "%.4f" % (duration * ratio),
        "-i",
        str(source),
        "-map",
        "0:a:0",
        "-af",
        one_shot_filter(duration, highpass, lowpass, gain_db, ratio),
    ]


def _encode(arguments: list[str], output: Path, channels: int, ffmpeg: str) -> None:
    command = (
        [ffmpeg, "-hide_banner", "-nostdin", "-y"]
        + arguments
        + [
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            str(channels),
            "-c:a",
            "libvorbis",
            "-q:a",
            str(VORBIS_QUALITY),
            str(output),
        ]
    )
    result = _run(command)
    if result.returncode != 0:
        raise CueError(
            "could not write %s: %s" % (output, result.stderr.strip()[-600:])
        )


def convert(
    source: Path,
    output: Path,
    mode: str,
    duration: float,
    start: float | None,
    search: tuple[float, float],
    seam: float,
    channels: int,
    highpass: int,
    lowpass: int,
    extra_gain_db: float,
    peak_dbfs: float,
    rms_dbfs: float | None,
    semitones: float = 0.0,
    lead: float = 0.0,
    take: int = 1,
    takes: int = 1,
    ffmpeg: str = "ffmpeg",
    ffprobe: str = "ffprobe",
) -> tuple[float, float]:
    """Cut one cue. Returns the second of the source it came from, and the cue's length.

    The length is returned rather than taken as read because `--lead auto`
    **measures** it: the cue is exactly as long as the run-up it found, so a caller
    that reported what it asked for would be reporting a number that is not the
    file's.

    Two encodes rather than one, because the gain cannot be chosen until the cut
    has been measured and the thing worth measuring is the cut rather than the
    recording it came out of. The first encode goes to a temporary file beside the
    output; the second is the one that ships.
    """
    _require_tools(ffmpeg, ffprobe)
    if not source.exists():
        raise CueError("no such recording: %s" % source)

    ratio = speed_ratio(semitones)

    # ── What the caller asked for, checked before anything is read ────────────
    #
    # These are all contradictions **within the arguments**, so none of them needs
    # the recording and none of them should wait for it: a refusal that depends on
    # reading a 400 MB WAV is slower than it needs to be and, worse, reports the
    # wrong problem first when the input is not audio at all. `--take 4 of 3` is a
    # contradiction whatever the file turns out to be.
    if mode == "loop" and abs(ratio - 1.0) > 1e-6:
        raise CueError("--semitones is for one-shots; a transposed loop has no stable seam")
    if takes > 1 and mode == "loop":
        raise CueError("--takes is for one-shots; an ambience bed has one window")
    if not 1 <= take <= takes:
        raise CueError("--take %d is not one of %d take(s)" % (take, takes))
    if lead != 0.0 and mode == "loop":
        raise CueError("--lead is for a measured in-point; a loop's window is declared")

    available = source_duration_seconds(source, ffprobe)
    needed = duration * ratio + (seam if mode == "loop" else 0.0)
    if available < needed:
        raise CueError(
            "%s is only %.2f s long and this cut needs %.2f s" % (source, available, needed)
        )

    # Set where a take's run-up is measured, and left unset on every path that does
    # not measure one — a stated `--start`, or a single-take cut.
    measured_approach: float | None = None

    if start is None:
        if mode == "loop":
            raise CueError("a loop needs --start: there is no transient to find")
        search_start = min(search[0], max(0.0, available - needed))
        search_length = min(search[1], available - search_start)
        if takes > 1:
            # No two takes may overlap, so they are at least one cue's worth of
            # source apart — which is `(duration + lead) * ratio`, the stretch this
            # cut actually reads, and not the output's length.
            window = find_take_windows(
                source,
                search_start,
                search_length,
                takes,
                (duration + max(lead, 0.0)) * ratio,
                ffmpeg,
            )[take - 1]
            start, measured_approach = window
        else:
            start = find_attack(source, search_start, search_length, ffmpeg)

    if lead < 0.0:
        # `--lead auto`. The run-up is a property of the performance and differs
        # take to take, so it is measured off the same envelope the onset came from
        # and the cue is exactly as long as the approach it found. `--duration` is
        # the **cap**: a run-up longer than the cue asked for is trimmed to end on
        # the onset, which is the end that matters.
        if measured_approach is None:
            raise CueError("--lead auto needs --takes; there is one envelope to read")
        if measured_approach <= 0.0:
            raise CueError(
                "%s take %d of %d runs out of silence with no measurable approach;"
                " name a --lead in seconds or cut this cue from the onset"
                % (source, take, takes)
            )
        # **The approach is measured in *source* seconds and `--duration` is in
        # output seconds**, so it crosses the transposition before the two are
        # compared. Without that division a cue pitched down a major third would
        # open 79% of the way back through its own run-up and drop the first fifth
        # of the air — internally consistent, and not the approach it measured.
        lead = min(duration, measured_approach / ratio)
        duration = lead
        needed = duration * ratio
    # The lead is in output seconds like `duration` is, so it stretches with the
    # transposition: an octave down reads half as much source and the approach to
    # the hit arrives half as fast, which is the whole point of resampling.
    start = max(0.0, start - lead * ratio)
    start = max(0.0, min(start, available - needed))

    output.parent.mkdir(parents=True, exist_ok=True)
    probe = output.with_suffix(".probe.ogg")
    try:
        def cut(gain_db: float) -> list[str]:
            return encode_arguments(
                source, mode, start, duration, seam, highpass, lowpass, gain_db, ratio
            )

        _encode(cut(0.0), probe, channels, ffmpeg)
        gain = normalising_gain_db(measure(probe, ffmpeg), peak_dbfs, rms_dbfs) + extra_gain_db
        _encode(cut(gain), output, channels, ffmpeg)
    finally:
        probe.unlink(missing_ok=True)
    return start, duration


def _parse_lead(text: str) -> float:
    """`--lead 0.22` in seconds, or `--lead auto` as the sentinel -1.

    A negative lead has no meaning as a distance — it would open the cut *after* the
    in-point it is measured from — so negative is free to mean "measure it", and
    `convert` reads it that way. One parameter rather than two because a lead is one
    idea: how far before the hit this cue starts. Only the answer's source changes.
    """
    if text.strip().lower() == "auto":
        return -1.0
    return float(text)


def _parse_search(text: str) -> tuple[float, float]:
    """`--search 3:20` — begin three seconds in and listen for twenty."""
    if ":" not in text:
        return (0.0, float(text))
    head, _, tail = text.partition(":")
    return (float(head or 0.0), float(tail or DEFAULT_SEARCH_SECONDS))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", choices=("oneshot", "loop"), default="oneshot")
    parser.add_argument("--duration", required=True, type=float)
    parser.add_argument(
        "--start",
        type=float,
        default=None,
        help="cut from here instead of hunting for the attack; required for a loop",
    )
    parser.add_argument(
        "--search",
        default="0:%g" % DEFAULT_SEARCH_SECONDS,
        help="where to hunt for the attack, as `start:length` in seconds",
    )
    parser.add_argument("--seam", type=float, default=DEFAULT_SEAM_SECONDS)
    parser.add_argument("--channels", type=int, default=1, choices=(1, 2))
    parser.add_argument("--highpass", type=int, default=35)
    parser.add_argument("--lowpass", type=int, default=0)
    parser.add_argument(
        "--semitones",
        type=float,
        default=0.0,
        help="transpose by resampling; negative is lower, slower and bigger. One-shots only",
    )
    parser.add_argument(
        "--lead",
        default="0",
        help=(
            "open the cut this many output seconds ahead of the measured in-point,"
            " or 'auto' to measure the take's own run-up and end on the in-point"
        ),
    )
    parser.add_argument(
        "--takes",
        type=int,
        default=1,
        help="how many separate takes of this event the recording holds. One-shots only",
    )
    parser.add_argument(
        "--take",
        type=int,
        default=1,
        help="which of them to cut, 1 being the loudest. Strongest first, so --takes may grow",
    )
    parser.add_argument("--gain-db", type=float, default=0.0)
    parser.add_argument("--peak-dbfs", type=float, default=None)
    parser.add_argument("--rms-dbfs", type=float, default=None)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    arguments = parser.parse_args(argv)

    is_loop = arguments.mode == "loop"
    peak = arguments.peak_dbfs
    if peak is None:
        peak = DEFAULT_LOOP_PEAK_DBFS if is_loop else DEFAULT_PEAK_DBFS
    rms = arguments.rms_dbfs
    if rms is None and is_loop:
        rms = DEFAULT_RMS_DBFS

    try:
        start, written = convert(
            source=arguments.input,
            output=arguments.output,
            mode=arguments.mode,
            duration=arguments.duration,
            start=arguments.start,
            search=_parse_search(arguments.search),
            seam=arguments.seam,
            channels=arguments.channels,
            highpass=arguments.highpass,
            lowpass=arguments.lowpass,
            extra_gain_db=arguments.gain_db,
            peak_dbfs=peak,
            rms_dbfs=rms,
            semitones=arguments.semitones,
            lead=_parse_lead(arguments.lead),
            take=arguments.take,
            takes=arguments.takes,
            ffmpeg=arguments.ffmpeg,
            ffprobe=arguments.ffprobe,
        )
    except CueError as problem:
        print("error: %s" % problem, file=sys.stderr)
        return 1
    print(
        "%s  <-  %s @ %.2f s, %.2f s %s%s%s"
        % (
            arguments.output.name,
            arguments.input.name,
            start,
            written,
            arguments.mode,
            "" if arguments.takes == 1 else ", take %d of %d" % (arguments.take, arguments.takes),
            # Said out loud, because a measured run-up is the one figure in the line
            # the recipe did not choose, and a recipe author reading this is exactly
            # the person who needs to see what it found.
            ""
            if _parse_lead(arguments.lead) >= 0.0
            else ", run-up measured (cap %.2f s)" % arguments.duration,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
