"""Behaviour of the audio cue conversion path.

Two seams:

* the pure analysis — where the attack is in a report ffmpeg wrote, what gain a
  measured clip needs, what filter string a mode builds — which needs no ffmpeg
  and no audio at all;
* the converter's command line (`python3 tools/assets/wav_to_cue.py ...`) and the
  `.ogg` it writes, read back with `ffprobe`.

**Every one of these runs on a synthesised signal, never on the Sonniss bundle.**
That bundle forbids redistribution and is not in this repository
(docs/ASSETS.md), so a test that needed it would be a test only one machine could
run — and its EULA prohibits machine-learning use besides. A sine with a gap in
front of it reproduces the one thing about those recordings that actually bites:
the event is somewhere in the middle and nobody can be asked to find it by hand.
"""

import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import wav_to_cue  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
RECIPE = REPO / "tools" / "assets" / "convert_audio.sh"
CONVERTER = REPO / "tools" / "assets" / "wav_to_cue.py"
FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")

_work: Path | None = None
_signals: dict[str, Path] = {}


def setUpModule():
    """Synthesise the signals once. Skips the ffmpeg half if it is not installed."""
    global _work
    if FFMPEG is None or FFPROBE is None:
        return
    _work = Path(tempfile.mkdtemp(prefix="wav_to_cue_"))

    # A twelve-second recording with one 0.4 s event starting at 5.0 s and silence
    # either side: "the thing you want is somewhere in the middle", which is every
    # file in the bundle.
    _signals["event"] = _work / "event.wav"
    _render(
        _signals["event"],
        "sine=f=220:d=12",
        "volume=0:enable='lt(t,5)',volume=0:enable='gt(t,5.4)'",
    )
    # A steady tone, for the loop path: no transient to find, so a loop must be
    # told where to start.
    _signals["steady"] = _work / "steady.wav"
    _render(_signals["steady"], "sine=f=110:d=20", "volume=0.5")
    # Something far too short for any sensible cut, to prove the refusal.
    _signals["brief"] = _work / "brief.wav"
    _render(_signals["brief"], "sine=f=440:d=0.2", "volume=0.5")
    # Two **gestures**, each a quiet run-up that swells into a loud hit, with digital
    # silence between them: the shape of a melee library's swing-to-impact takes, and
    # the one `--lead auto` exists for. The run-ups are deliberately different
    # lengths — 0.30 s and 0.15 s — because that is the thing a fixed `--lead` cannot
    # be right about twice. Hits land at 2.0 s and 6.0 s.
    _signals["gestures"] = _work / "gestures.wav"
    _render(
        _signals["gestures"],
        "sine=f=300:d=9",
        # Each window is scaled to its own envelope and everything else is zeroed, so
        # between the gestures the file is digitally silent rather than quiet.
        "volume=0.06:enable='between(t,1.70,2.00)',"
        "volume=1.0:enable='between(t,2.00,2.25)',"
        "volume=0.06:enable='between(t,5.85,6.00)',"
        "volume=0.9:enable='between(t,6.00,6.25)',"
        "volume=0:enable='not(between(t,1.70,2.25)+between(t,5.85,6.25))'",
    )


def tearDownModule():
    if _work is not None:
        shutil.rmtree(_work, ignore_errors=True)


def _render(path: Path, source: str, filters: str) -> None:
    subprocess.run(
        [
            FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", source,
            "-af", filters, "-ar", "48000", str(path),
        ],
        check=True,
    )


def _probe(path: Path) -> dict:
    result = subprocess.run(
        [
            FFPROBE, "-v", "error",
            "-show_entries", "stream=channels,sample_rate,codec_name",
            "-show_entries", "format=duration",
            "-of", "json", str(path),
        ],
        capture_output=True, text=True, check=True,
    )
    report = json.loads(result.stdout)
    stream = report["streams"][0]
    return {
        "channels": stream["channels"],
        "sample_rate": int(stream["sample_rate"]),
        "codec": stream["codec_name"],
        "duration": float(report["format"]["duration"]),
    }


def _second(report: str) -> float:
    """The second the converter says it cut from, out of its own one-line report."""
    return float(re.search(r"@ ([0-9.]+) s", report).group(1))


def _convert(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CONVERTER), *arguments], capture_output=True, text=True
    )


# ── The analysis, which needs no ffmpeg ───────────────────────────────────────


class ParsingAnFfmpegReport(unittest.TestCase):
    """The two report formats the script reads, parsed without running anything."""

    def test_a_frame_without_a_time_is_not_a_second(self):
        # The bug this guards against: reading peaks on their own gives frame
        # indices, and multiplying a frame index by a guessed frame length is
        # wrong by a factor of three. The time has to come out of the report.
        report = (
            "frame:0    pts:0       pts_time:0\n"
            "lavfi.astats.Overall.Peak_level=-inf\n"
            "frame:1    pts:4096    pts_time:0.0853333\n"
            "lavfi.astats.Overall.Peak_level=-12.5\n"
        )
        self.assertEqual(
            wav_to_cue.parse_frame_peaks(report),
            [(0.0, -math.inf), (0.0853333, -12.5)],
        )

    def test_astats_levels_survive_ffmpegs_own_line_prefix(self):
        report = (
            "[Parsed_astats_0 @ 0x7e43d0003140] Overall\n"
            "[Parsed_astats_0 @ 0x7e43d0003140] Peak level dB: -18.174659\n"
            "[Parsed_astats_0 @ 0x7e43d0003140] RMS level dB: -38.874077\n"
            "[Parsed_astats_0 @ 0x7e43d0003140] RMS peak dB: -21.991840\n"
        )
        levels = wav_to_cue.parse_levels(report)
        self.assertAlmostEqual(levels.peak_dbfs, -18.174659)
        self.assertAlmostEqual(
            levels.rms_dbfs, -38.874077, msg="'RMS peak dB' must not be mistaken for it"
        )

    def test_a_missing_statistic_is_an_error_and_not_a_zero(self):
        with self.assertRaises(wav_to_cue.CueError):
            wav_to_cue.parse_levels("[Parsed_astats_0 @ 0x0] Overall\n")


class TheFfmpegVersionFloor(unittest.TestCase):
    """The cutter refuses an ffmpeg it knows writes near-empty loops.

    #40 turned CI on and found that ubuntu-24.04's ffmpeg 6.1.1 exits 0 and writes a
    0.048-second file where twenty-four seconds were asked for. It pinned 8.1.3 for
    CI, which protects CI and leaves every local run on a distro ffmpeg getting the
    same silent near-empty bed. This is the half that makes it a property of the tool.
    """

    def test_the_version_forms_that_actually_occur_are_all_read(self):
        for banner, expected in (
            ("ffmpeg version 7.0.2-static https://johnvansickle.com/ffmpeg/", 7),
            ("ffmpeg version n8.1.3-26-g1f2e3d4 Copyright (c) 2000-2026", 8),
            ("ffmpeg version 6.1.1-3ubuntu5 Copyright (c) 2000-2023", 6),
            ("ffprobe version 10.2.0 Copyright (c)", 10),
        ):
            with self.subTest(banner=banner):
                self.assertEqual(wav_to_cue.tool_major_version(banner), expected)

    def test_a_build_with_no_release_number_is_unknown_rather_than_refused(self):
        # A nightly carries no version. Refusing a toolchain the guard cannot assess
        # would make the cutter unusable on a good one, and the behavioural test
        # below still fails loudly on a build that really is too old.
        self.assertIsNone(
            wav_to_cue.tool_major_version("ffmpeg version N-120345-g1a2b3c4")
        )
        self.assertIsNone(wav_to_cue.tool_major_version(""))

    def test_the_floor_is_the_version_whose_loop_mode_works(self):
        # Not an arbitrary number: 6.x is the one observed to write a near-empty loop.
        self.assertEqual(wav_to_cue.FFMPEG_MINIMUM_MAJOR, 7)

    def test_ci_pins_an_ffmpeg_that_satisfies_the_floor(self):
        # The two places this requirement is written down have to agree, or CI would
        # install a build the cutter then refuses — or worse, stop installing one and
        # go back to the distro's.
        env = REPO / ".github" / "ci" / "toolchain.env"
        if not env.exists():
            self.skipTest("no CI toolchain pin in this checkout")
        pinned = re.search(r"^FFMPEG_VERSION=n?(\d+)\.", env.read_text(), re.M)
        self.assertIsNotNone(pinned, "toolchain.env must pin a numbered ffmpeg")
        self.assertGreaterEqual(
            int(pinned.group(1)),
            wav_to_cue.FFMPEG_MINIMUM_MAJOR,
            "CI's pinned ffmpeg is older than the cutter's own floor",
        )


@unittest.skipIf(FFMPEG is None, "ffmpeg is not installed")
class TheInstalledFfmpegIsUsable(unittest.TestCase):
    def test_the_ffmpeg_on_this_machine_passes_the_tools_own_check(self):
        # Belt and braces: if this fails, every other ffmpeg test in this file is
        # about to fail for a reason that has nothing to do with what it asserts.
        wav_to_cue._require_tools(FFMPEG, FFPROBE)
        self.assertGreaterEqual(
            wav_to_cue.tool_major_version(
                subprocess.run(
                    [FFMPEG, "-version"], capture_output=True, text=True
                ).stdout
            )
            or wav_to_cue.FFMPEG_MINIMUM_MAJOR,
            wav_to_cue.FFMPEG_MINIMUM_MAJOR,
        )


class FindingTheOnset(unittest.TestCase):
    """`astats` is left cumulative, so the report is a staircase."""

    @staticmethod
    def _staircase(rises_at: float) -> list[tuple[float, float]]:
        frames = []
        second = 0.0
        while second < 2.0:
            frames.append((second, -3.0 if second >= rises_at else -60.0))
            second += 0.0853333
        return frames

    def test_the_onset_is_the_first_loud_frame_and_the_cut_opens_before_it(self):
        offset = wav_to_cue.attack_offset_seconds(self._staircase(1.0))
        self.assertAlmostEqual(offset, 1.0239996 - wav_to_cue.PRE_ATTACK_SECONDS, places=4)
        self.assertLess(offset, 1.0, "the cut must open before the hit, never on it")

    def test_a_hit_that_keeps_getting_louder_is_still_cut_at_its_onset(self):
        # The reason the tolerance exists. A heavy transient climbs for tens of
        # milliseconds, so the top of the staircase is not the onset — and
        # ffmpeg's frames are 85 ms, so cutting at the top lands audibly inside
        # the attack.
        frames = [(0.0, -60.0), (0.1, -5.0), (0.2, -3.0), (0.3, -1.0)]
        self.assertAlmostEqual(
            wav_to_cue.attack_offset_seconds(frames),
            0.1 - wav_to_cue.PRE_ATTACK_SECONDS,
            places=4,
        )

    def test_room_tone_has_no_onset_and_says_so(self):
        self.assertEqual(
            wav_to_cue.attack_offset_seconds([(0.0, -85.0), (0.1, -90.0)]),
            0.0,
            "a stretch with nothing in it is cut from the front, not guessed at",
        )
        self.assertEqual(wav_to_cue.attack_offset_seconds([]), 0.0)


class FindingSeveralTakes(unittest.TestCase):
    """`--takes` reads a non-cumulative envelope, so it rises and falls per take."""

    @staticmethod
    def _hits(at: list[tuple[float, float]], length: float = 12.0) -> list[tuple[float, float]]:
        """An 85 ms frame envelope that is silent except for a hit at each `(second, dB)`."""
        frames = []
        second = 0.0
        while second < length:
            level = -90.0
            for when, peak in at:
                if when <= second < when + 0.2:
                    level = peak
            frames.append((second, level))
            second += 0.0853333
        return frames

    def test_the_loudest_take_comes_first_so_adding_one_does_not_renumber_the_rest(self):
        frames = self._hits([(1.0, -12.0), (4.0, -3.0), (8.0, -20.0)])
        three = wav_to_cue.take_offsets_seconds(frames, 3, 0.5)
        self.assertEqual(len(three), 3)
        self.assertAlmostEqual(three[0], 4.0 - wav_to_cue.PRE_ATTACK_SECONDS, places=1)
        self.assertEqual(
            wav_to_cue.take_offsets_seconds(frames, 2, 0.5),
            three[:2],
            "asking for one fewer take must leave the others where they were",
        )

    def test_two_peaks_inside_one_hit_are_one_take(self):
        # The bug this guards against, measured on a tool recording: a take whose
        # envelope stays flat for half a second has two frames a gap apart that back
        # off to onsets 80 ms apart, and the two cuts then overlap almost entirely.
        frames = [(second * 0.0853333, -4.0 if 10 <= second <= 20 else -90.0) for second in range(40)]
        self.assertEqual(
            len(wav_to_cue.take_offsets_seconds(frames, 4, 0.4)),
            1,
            "one event is one take however many frames of it are near the peak",
        )

    def test_a_take_more_than_the_floor_below_the_loudest_is_not_a_take(self):
        frames = self._hits([(1.0, -3.0), (5.0, -3.0 - wav_to_cue.TAKE_FLOOR_DB - 6.0)])
        self.assertEqual(
            len(wav_to_cue.take_offsets_seconds(frames, 2, 0.5)),
            1,
            "the room tone between the takes is not a quiet take of the prop",
        )

    def test_room_tone_holds_no_takes_at_all(self):
        self.assertEqual(wav_to_cue.take_offsets_seconds(self._hits([]), 3, 0.5), [])
        self.assertEqual(wav_to_cue.take_offsets_seconds([], 3, 0.5), [])


class TheFrameTheAnalysisReadsOn(unittest.TestCase):
    """The in-point can only be as precise as the frame it is measured on.

    Asserted here rather than through an output file because the frame size does not
    appear anywhere in what `parse_frame_peaks` reads — it is a property of the
    request — and because the thing it fixes is a 0-130 ms inconsistency between
    takes, which no single cue's duration or level can show.
    """

    def test_the_hunt_asks_for_a_frame_short_enough_to_place_an_onset(self):
        self.assertLessEqual(
            wav_to_cue.ANALYSIS_FRAME_SAMPLES / wav_to_cue.SAMPLE_RATE,
            0.020,
            "an onset offset under ~20 ms is not heard as a separate event; "
            "ffmpeg's own 4096-sample frame is 85 ms and four times too coarse",
        )

    def test_the_frame_is_re_cut_before_astats_rather_than_after(self):
        # `asetnsamples` has to come first in the chain or `astats` has already
        # reported on the frames ffmpeg chose.
        captured = {}

        def fake_run(command):
            captured["filters"] = command[command.index("-af") + 1]

            class Result:
                returncode = 0
                stdout = "pts_time:0\nlavfi.astats.Overall.Peak_level=-6.0\n"
                stderr = ""

            return Result()

        original = wav_to_cue._run
        wav_to_cue._run = fake_run
        try:
            wav_to_cue._frame_peaks(Path("in.wav"), 0.0, 1.0, False, "ffmpeg")
        finally:
            wav_to_cue._run = original
        filters = captured["filters"]
        self.assertIn("asetnsamples=n=%d" % wav_to_cue.ANALYSIS_FRAME_SAMPLES, filters)
        self.assertLess(
            filters.index("asetnsamples"), filters.index("astats"), "order is the claim"
        )
        self.assertIn("p=0", filters, "a padded last frame is a frame of invented silence")


class MeasuringTheRunUpToAHit(unittest.TestCase):
    """`approach_offsets_seconds`, which is what `--lead auto` is made of.

    The bug it exists to prevent shipped once: a fixed `--lead 0.22` against run-ups
    that are really 80-144 ms, on a recording with digital silence between takes, so
    four of five cues were most of a fifth of a second of silence followed by the
    leading edge of the thud they were supposed to lead into.
    """

    @staticmethod
    def _frames(levels: list[float], step: float = 0.01) -> list[tuple[float, float]]:
        return [(index * step, level) for index, level in enumerate(levels)]

    def test_the_run_up_is_measured_back_to_the_silence_before_it(self):
        # Silence, then 50 ms of quiet run-up, then the hit. The run-up is what the
        # cue should be, and it is 50 ms whatever the recipe guessed.
        frames = self._frames([-95.0] * 10 + [-30.0] * 5 + [-2.0] * 5)
        self.assertAlmostEqual(
            approach(frames, [0.15])[0], 0.05, places=3,
            msg="back to where signal rose out of the silence, not to the file's start",
        )

    def test_two_takes_in_one_recording_get_their_own_lengths(self):
        # The whole point: a run-up is a property of the performance, so two takes in
        # one file have two different ones and a single declared number is wrong on at
        # least one of them.
        frames = self._frames(
            [-95.0] * 5 + [-30.0] * 8 + [-2.0] * 3 + [-95.0] * 5 + [-30.0] * 2 + [-2.0] * 3
        )
        self.assertEqual(
            [round(value, 3) for value in approach(frames, [0.13, 0.23])],
            [0.08, 0.02],
        )

    def test_a_take_with_no_silence_in_front_of_it_reports_nothing(self):
        # Continuous signal has no measurable run-up, and saying zero is honest —
        # `convert` turns that into a refusal naming the cue rather than cutting an
        # arbitrary window and calling it a swing.
        frames = self._frames([-30.0] * 20)
        self.assertEqual(approach(frames, [0.19]), [0.0])

    def test_no_frames_is_no_measurement_rather_than_an_error(self):
        self.assertEqual(approach([], [1.0, 2.0]), [0.0, 0.0])


def approach(frames, onsets):
    return wav_to_cue.approach_offsets_seconds(frames, onsets)


class ChoosingTheGain(unittest.TestCase):
    def test_a_one_shot_is_peak_normalised(self):
        quiet = wav_to_cue.Levels(peak_dbfs=-18.0, rms_dbfs=-40.0)
        self.assertAlmostEqual(
            wav_to_cue.normalising_gain_db(quiet, peak_target_dbfs=-1.0, rms_target_dbfs=None),
            17.0,
        )

    def test_a_loop_is_rms_normalised_under_the_peak_ceiling(self):
        # RMS wants +18 dB and the peak ceiling only allows +2. The ceiling wins,
        # because a bed that clips is worse than a bed that is quiet.
        peaky = wav_to_cue.Levels(peak_dbfs=-5.0, rms_dbfs=-40.0)
        self.assertAlmostEqual(
            wav_to_cue.normalising_gain_db(peaky, peak_target_dbfs=-3.0, rms_target_dbfs=-22.0),
            2.0,
        )
        # And where there is headroom to spare, RMS is what sets the level.
        even = wav_to_cue.Levels(peak_dbfs=-30.0, rms_dbfs=-40.0)
        self.assertAlmostEqual(
            wav_to_cue.normalising_gain_db(even, peak_target_dbfs=-3.0, rms_target_dbfs=-22.0),
            18.0,
        )

    def test_silence_is_left_alone_rather_than_amplified_infinitely(self):
        self.assertEqual(
            wav_to_cue.normalising_gain_db(
                wav_to_cue.Levels(peak_dbfs=-math.inf, rms_dbfs=-math.inf), -1.0, None
            ),
            0.0,
        )


class BuildingTheFilters(unittest.TestCase):
    def test_a_transposed_cue_reads_more_source_than_it_writes(self):
        ratio = wav_to_cue.speed_ratio(-12.0)
        self.assertAlmostEqual(ratio, 0.5, msg="an octave down is half the rate")
        arguments = wav_to_cue.encode_arguments(
            Path("in.wav"), "oneshot", 1.0, 2.0, 0.0, 35, 0, 0.0, ratio
        )
        self.assertIn("-t", arguments)
        self.assertEqual(
            arguments[arguments.index("-t") + 1],
            "1.0000",
            "--duration is the output's length, so an octave down reads half as much",
        )

    def test_the_gain_rides_inside_the_loop_graph_rather_than_after_it(self):
        # ffmpeg refuses a simple `-af` on a stream that came out of a complex
        # graph, so a loop's gain has to be part of the graph.
        graph = wav_to_cue.loop_filter_complex(2.0, 8.0, 1.0, 35, 0, -6.0)
        self.assertIn("volume=-6.000dB", graph)
        self.assertIn("asplit=2", graph)
        self.assertIn("amix=inputs=2", graph)

    def test_a_one_shot_always_fades_out(self):
        # A cut through a decaying resonance clicks.
        self.assertIn("afade=t=out", wav_to_cue.one_shot_filter(1.0, 35, 0, 0.0))


# ── The artefact, which needs ffmpeg ──────────────────────────────────────────


@unittest.skipIf(FFMPEG is None or FFPROBE is None, "ffmpeg is not installed")
class CuttingTheRunUpRatherThanTheSilenceBeforeIt(unittest.TestCase):
    """`--lead auto` end to end, against two gestures with unequal run-ups.

    The regression this pins down shipped: a swing cue that was 73-91% digital
    silence because the declared lead was longer than the run-up, so the window
    opened in the gap between takes. A cue that begins in silence is the one defect
    here that a level meter misses entirely — it peak-normalises to exactly the same
    -1 dBFS as a good one.
    """

    def _cut(self, take: str, extra: list[str] | None = None):
        # The extra arguments are part of the name, because two cuts of the same take
        # that differ only in `--semitones` are two different files and writing both
        # to one path compares a file with itself — which is exactly what this helper
        # did when the transposition test was written against it.
        tag = "_".join(extra or []).replace("-", "").replace(".", "") or "plain"
        out = _work / f"runup_{take}_{tag}.ogg"
        result = _convert(
            "--input", str(_signals["gestures"]), "--output", str(out),
            "--takes", "2", "--take", take,
            "--duration", "0.5", "--lead", "auto", "--search", "0:9",
            *(extra or []),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return out, result.stdout

    def test_the_cue_is_as_long_as_the_run_up_it_measured(self):
        # The fixture's two run-ups are 0.30 s and 0.15 s and the cap is 0.5 s, so
        # neither cue may come out at the cap — that would be the fixed-lead bug back
        # again — and the two must differ, because that is the whole claim.
        lengths = {}
        for take in ("1", "2"):
            out, said = self._cut(take)
            lengths[take] = _probe(out)["duration"]
            self.assertIn("run-up measured", said, "the figure is reported, not hidden")
        for take, length in lengths.items():
            with self.subTest(take=take):
                self.assertLess(length, 0.45, "measured, not the declared cap")
                self.assertGreater(length, 0.05, "and not nothing")
        self.assertNotAlmostEqual(
            lengths["1"], lengths["2"], places=2,
            msg="two takes, two performances, two lengths — one number cannot fit both",
        )

    def test_a_transposed_cue_keeps_the_whole_run_up_it_measured(self):
        # **The unit bug this exists to prevent, and it shipped once.** The run-up is
        # measured on the *source* envelope and `--duration` is the length of the
        # *output*, so the two are in different units until the transposition is
        # divided out. Comparing them directly capped a pitched-down cue at the
        # source figure and dropped the front of the air: at -4 semitones a 0.30 s
        # run-up came out 0.30 s long where it should be 0.378, so the cut opened
        # 79% of the way through its own approach. Internally consistent, and not
        # the approach it had just measured.
        #
        # So: the same take, cut twice, differing only by `--semitones`. Down a major
        # third stretches time by 1/0.7937, and the cue has to stretch with it.
        plain, _ = self._cut("1")
        lower, _ = self._cut("1", ["--semitones", "-4"])
        ratio = wav_to_cue.speed_ratio(-4.0)
        self.assertAlmostEqual(
            _probe(lower)["duration"], _probe(plain)["duration"] / ratio, places=2,
            msg="a transposed run-up is the same air arriving more slowly, all of it",
        )
        # And the cap is still the cap, in the units the cap is quoted in.
        self.assertLessEqual(_probe(lower)["duration"], 0.5 + 0.01)

    def test_the_cue_holds_signal_from_its_first_moment(self):
        # The assertion the shipped regression would have failed: measure only the
        # opening of the cue. 200 of 220 ms at -95 dB is what went out, and every
        # level check on the whole file passed it.
        out, _ = self._cut("1")
        opening = _work / "opening.wav"
        subprocess.run(
            [FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
             "-t", "0.03", "-i", str(out), str(opening)],
            check=True,
        )
        self.assertGreater(
            wav_to_cue.measure(opening, FFMPEG).rms_dbfs, -60.0,
            "a cue that opens in silence is a cue that fires late",
        )

    def test_a_measured_lead_needs_several_takes_to_measure_across(self):
        result = _convert(
            "--input", str(_signals["gestures"]), "--output", str(_work / "no.ogg"),
            "--duration", "0.3", "--lead", "auto",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("--takes", result.stderr)

    def test_a_loop_has_no_in_point_to_lead_and_says_so(self):
        result = _convert(
            "--input", str(_signals["steady"]), "--output", str(_work / "no.ogg"),
            "--mode", "loop", "--start", "2", "--duration", "4", "--lead", "auto",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("--lead", result.stderr)


@unittest.skipIf(FFMPEG is None or FFPROBE is None, "ffmpeg is not installed")
class CuttingACue(unittest.TestCase):
    def test_a_one_shot_finds_the_event_in_the_middle_of_the_recording(self):
        out = _work / "found.ogg"
        result = _convert(
            "--input", str(_signals["event"]), "--output", str(out),
            "--duration", "0.6", "--search", "0:12",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        # Reported, so the recipe's author can see what it chose without listening.
        self.assertRegex(result.stdout, r"@ 4\.[0-9]+ s|@ 5\.[0-9]+ s")

        probe = _probe(out)
        self.assertEqual(probe["codec"], "vorbis")
        self.assertEqual(probe["sample_rate"], wav_to_cue.SAMPLE_RATE)
        self.assertEqual(probe["channels"], 1, "a positional cue is mono")
        self.assertAlmostEqual(probe["duration"], 0.6, places=2)

    def test_the_cut_is_actually_the_event_and_not_the_silence_around_it(self):
        out = _work / "loud.ogg"
        self.assertEqual(
            _convert(
                "--input", str(_signals["event"]), "--output", str(out),
                "--duration", "0.3", "--search", "0:12",
            ).returncode,
            0,
        )
        levels = wav_to_cue.measure(out, FFMPEG)
        self.assertGreater(
            levels.peak_dbfs, -6.0, "peak-normalised, so the loudest sample is near the ceiling"
        )
        self.assertGreater(
            levels.rms_dbfs, -30.0, "and the window holds signal rather than room tone"
        )

    def test_a_transposed_cue_comes_out_the_length_it_asked_for(self):
        out = _work / "low.ogg"
        self.assertEqual(
            _convert(
                "--input", str(_signals["event"]), "--output", str(out),
                "--duration", "1.0", "--semitones", "-9", "--search", "0:12",
            ).returncode,
            0,
        )
        self.assertAlmostEqual(_probe(out)["duration"], 1.0, places=2)

    def test_a_loop_is_stereo_and_exactly_as_long_as_it_was_told(self):
        out = _work / "bed.ogg"
        result = _convert(
            "--input", str(_signals["steady"]), "--output", str(out),
            "--mode", "loop", "--start", "2", "--duration", "8", "--channels", "2",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        probe = _probe(out)
        self.assertEqual(probe["channels"], 2)
        self.assertAlmostEqual(
            probe["duration"], 8.0, places=2,
            msg="the seam is folded back in, so it must not make the file longer",
        )

    def test_a_loop_without_a_start_is_refused_rather_than_guessed(self):
        result = _convert(
            "--input", str(_signals["steady"]), "--output", str(_work / "nope.ogg"),
            "--mode", "loop", "--duration", "4",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("--start", result.stderr)

    def test_several_takes_of_one_recording_are_several_different_cuts(self):
        # Three events, so three takes — and the point of them is that they differ.
        source = _work / "three.wav"
        _render(
            source,
            "sine=f=330:d=12",
            "volume=0:enable='between(t,0,2)+between(t,2.4,5)+between(t,5.4,8)+gt(t,8.4)'",
        )
        sizes = []
        for take in (1, 2, 3):
            out = _work / ("take%d.ogg" % take)
            result = _convert(
                "--input", str(source), "--output", str(out), "--duration", "0.3",
                "--takes", "3", "--take", str(take), "--search", "0:12",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("take %d of 3" % take, result.stdout)
            sizes.append(out.read_bytes())
        self.assertEqual(len(set(sizes)), 3, "three takes that are byte-identical are one take")

    def test_asking_for_more_takes_than_the_recording_holds_names_both_numbers(self):
        result = _convert(
            "--input", str(_signals["event"]), "--output", str(_work / "nope.ogg"),
            "--duration", "0.3", "--takes", "4", "--search", "0:12",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("4 were asked for", result.stderr)
        self.assertIn("separable take", result.stderr)

    def test_a_lead_opens_the_cut_before_the_onset_rather_than_on_it(self):
        # How one recorded swing-to-impact becomes two cues: the swing is the air in
        # front of the thud, so its window ends where the measured in-point begins.
        plain = _convert(
            "--input", str(_signals["event"]), "--output", str(_work / "on.ogg"),
            "--duration", "0.3", "--search", "0:12",
        )
        led = _convert(
            "--input", str(_signals["event"]), "--output", str(_work / "ahead.ogg"),
            "--duration", "0.3", "--lead", "0.3", "--search", "0:12",
        )
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(led.returncode, 0, led.stderr)
        self.assertAlmostEqual(
            _second(led.stdout), _second(plain.stdout) - 0.3, places=2,
            msg="the lead is in output seconds, like --duration",
        )
        self.assertLess(
            wav_to_cue.measure(_work / "ahead.ogg", FFMPEG).rms_dbfs,
            wav_to_cue.measure(_work / "on.ogg", FFMPEG).rms_dbfs,
            "and what it cut is the approach, which is quieter than the event",
        )

    def test_a_recording_too_short_for_the_cut_says_so_by_name(self):
        result = _convert(
            "--input", str(_signals["brief"]), "--output", str(_work / "nope.ogg"),
            "--duration", "2.0",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("brief.wav", result.stderr)
        self.assertIn("only 0.2", result.stderr)

    def test_nothing_is_left_behind_beside_the_output(self):
        out = _work / "tidy.ogg"
        _convert(
            "--input", str(_signals["event"]), "--output", str(out), "--duration", "0.4"
        )
        # The measuring pass writes a probe encode next to the output.
        self.assertFalse(
            out.with_suffix(".probe.ogg").exists(), "the measuring encode is cleaned up"
        )


# ── The recipe ────────────────────────────────────────────────────────────────


class TheRecipe(unittest.TestCase):
    """`convert_audio.sh` is the only record of which recording becomes which cue."""

    def setUp(self):
        self.text = RECIPE.read_text()

    def test_it_writes_outside_the_shipping_tree(self):
        # A cut from a non-redistributable recording is a derivative of it and is
        # exactly as forbidden as the recording.
        self.assertIn("assets_licensed/generated/audio", self.text)
        self.assertNotIn("$repo_root/assets/audio", self.text)

    def test_it_no_ops_without_the_bundle(self):
        # Most clones do not have 7.5 GB of WAV, and the asset pipeline has to run
        # anyway.
        self.assertIn("nothing to cut", self.text)
        self.assertIn("exit 0", self.text)

    def test_it_states_the_two_prohibitions_the_sonniss_licence_carries(self):
        self.assertIn("NO AI TRAINING OR USAGE", self.text)
        self.assertIn("tools/aigen", self.text)

    def test_every_cue_it_writes_is_one_the_game_knows_about(self):
        # The recipe and `game/sound_bank.gd` are two halves of one list, and a cue
        # cut but never played is dead weight in the quarantine.
        catalogue = (REPO / "game" / "sound_bank.gd").read_text()
        cut = [
            line.split()[1]
            for line in self.text.splitlines()
            if line.startswith("cue ") and len(line.split()) > 1
        ]
        self.assertGreater(len(cut), 20, "the recipe is not a stub")
        for name in cut:
            self.assertIn(
                '"%s"' % name,
                catalogue,
                "convert_audio.sh cuts '%s' but game/sound_bank.gd never plays it" % name,
            )


if __name__ == "__main__":
    unittest.main()
