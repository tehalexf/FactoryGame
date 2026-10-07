"""The slider table: that it names real keys, and that neither stop of any
slider is a value the game would refuse.

Seam: `controls.SLIDERS` read against the shipped tuning file and the kinds
derived from the loader. These are the tests that let the table be left behind
safely — a key renamed in `content/tuning.toml` fails here rather than quietly
losing its slider.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import controls, key_kinds, toml_subset, tuning_file  # noqa: E402

REPO = Path(__file__).resolve().parents[3]


class TheSliderTable(unittest.TestCase):
    def setUp(self):
        source = (REPO / "content" / "tuning.toml").read_text(encoding="utf-8")
        self.doc = tuning_file.TuningFile.parse(source, "tuning.toml")
        self.kinds = key_kinds.load(REPO / "sim" / "definitions.gd")

    def test_every_slider_names_a_key_the_file_defines(self):
        unknown = sorted(k for k in controls.SLIDERS if not self.doc.has(k))
        self.assertEqual(unknown, [])

    def test_no_slider_is_on_a_string_or_a_flag(self):
        wrong = sorted(
            key
            for key in controls.SLIDERS
            if self.kinds.get(key)
            in (toml_subset.KIND_STRING, toml_subset.KIND_BOOLEAN)
        )
        self.assertEqual(wrong, [])

    def test_a_slider_on_a_whole_number_moves_in_whole_numbers(self):
        """`land_settle_acceleration_percent` is read with `require_int`, so a
        slider that could land on 47.5 would write a value the loader refuses."""
        fractional = sorted(
            key
            for key, bounds in controls.SLIDERS.items()
            if self.kinds.get(key) == toml_subset.KIND_INTEGER
            and not all(
                float(n).is_integer()
                for n in (bounds.minimum, bounds.maximum, bounds.step)
            )
        )
        self.assertEqual(fractional, [])

    def test_the_shipped_default_sits_inside_its_own_slider(self):
        """A default outside its slider would mean opening the page on a fresh
        checkout already showed a changed value, which is the one signal the
        whole thing is for."""
        outside = []
        for key, bounds in controls.SLIDERS.items():
            if not self.doc.has(key):
                continue
            value = float(self.doc.field(key).value_text)
            if not bounds.minimum <= value <= bounds.maximum:
                outside.append((key, value, bounds.minimum, bounds.maximum))
        self.assertEqual(outside, [])

    def test_the_camera_response_values_can_still_be_switched_right_off(self):
        """The file says every camera-response value treats 0 as off, and that
        somebody prone to motion sickness is entitled to it. A slider that
        bottomed out at 0.001 would take that away."""
        for key in [
            "player.bob_vertical_metres",
            "player.bob_lateral_metres",
            "player.land_dip_metres",
            "player.lean_roll_degrees_per_metre_per_second",
            "player.lean_pitch_degrees_per_metre_per_second",
            "player.sprint_field_of_view_add_degrees",
        ]:
            with self.subTest(key=key):
                self.assertEqual(controls.SLIDERS[key].minimum, 0)

    def test_a_divisor_never_reaches_zero(self):
        """`bob_stride_metres` and the landing dip's reference speed are both
        divisors in the Simulation, and the loader refuses a set where either is
        zero. A slider must not be able to get there."""
        self.assertGreater(controls.SLIDERS["player.bob_stride_metres"].minimum, 0)
        self.assertGreater(
            controls.SLIDERS[
                "player.land_dip_reference_speed_metres_per_second"
            ].minimum,
            0,
        )

    def test_the_field_of_view_stays_inside_what_the_loader_accepts(self):
        bounds = controls.SLIDERS["player.field_of_view_degrees"]
        self.assertGreater(bounds.minimum, 0)
        self.assertLess(bounds.maximum, 180)

    def test_the_feel_sections_are_covered_rather_than_sampled(self):
        """Issue #31's premise is that the feel values are the ones being hunted
        by hand. Every numeric key in the three sections the file itself calls
        feel gets a slider."""
        feel_sections = {"gear", "survey"}
        missing = sorted(
            f.key
            for f in self.doc.fields()
            if f.section in feel_sections
            and self.kinds.get(f.key)
            not in (toml_subset.KIND_STRING, toml_subset.KIND_BOOLEAN)
            and f.key not in controls.SLIDERS
        )
        self.assertEqual(missing, [])
