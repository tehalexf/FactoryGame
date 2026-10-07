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


def find_attack(
    path: Path,
    search_start: float,
    search_length: float,
    ffmpeg: str = "ffmpeg",
) -> float:
    """The absolute second the loudest transient in the search window begins."""
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
            "astats=metadata=1:reset=0,"
            "ametadata=print:key=lavfi.astats.Overall.Peak_level:file=-",
            "-f",
            "null",
            "-",
        ]
    )
    if result.returncode != 0:
        raise CueError("could not analyse %s: %s" % (path, result.stderr.strip()[-400:]))
    # `file=-` writes the metadata to stdout; the progress report goes to stderr.
    return search_start + attack_offset_seconds(parse_frame_peaks(result.stdout))


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
    ffmpeg: str = "ffmpeg",
    ffprobe: str = "ffprobe",
) -> float:
    """Cut one cue. Returns the second of the source it was taken from.

    Two encodes rather than one, because the gain cannot be chosen until the cut
    has been measured and the thing worth measuring is the cut rather than the
    recording it came out of. The first encode goes to a temporary file beside the
    output; the second is the one that ships.
    """
    _require_tools(ffmpeg, ffprobe)
    if not source.exists():
        raise CueError("no such recording: %s" % source)

    ratio = speed_ratio(semitones)
    if mode == "loop" and abs(ratio - 1.0) > 1e-6:
        raise CueError("--semitones is for one-shots; a transposed loop has no stable seam")

    available = source_duration_seconds(source, ffprobe)
    needed = duration * ratio + (seam if mode == "loop" else 0.0)
    if available < needed:
        raise CueError(
            "%s is only %.2f s long and this cut needs %.2f s" % (source, available, needed)
        )

    if start is None:
        if mode == "loop":
            raise CueError("a loop needs --start: there is no transient to find")
        search_start = min(search[0], max(0.0, available - needed))
        search_length = min(search[1], available - search_start)
        start = find_attack(source, search_start, search_length, ffmpeg)
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
    return start


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
        start = convert(
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
            ffmpeg=arguments.ffmpeg,
            ffprobe=arguments.ffprobe,
        )
    except CueError as problem:
        print("error: %s" % problem, file=sys.stderr)
        return 1
    print(
        "%s  <-  %s @ %.2f s, %.2f s %s"
        % (arguments.output.name, arguments.input.name, start, arguments.duration, arguments.mode)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
