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
