"""`tools/assets/enemy_grade.py`'s contract, on invented pixels.

The same arrangement `test_prop_grade.py` has and for the same reason: the
artistic rule is a pure function of one colour, so it can be asserted without
the atlas, without Blender and without an image library. The one test that does
touch the committed art is the regeneration check at the bottom, which is the
`test_generated_machines` arrangement — where the output is committed, prove it.
"""

from __future__ import annotations

import colorsys
import pathlib
import subprocess
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import enemy_grade  # noqa: E402
import prop_grade  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parents[3]
PALETTE = prop_grade.load_palette(REPO / "tools/assets/dieselpunk_palette.json")


def luminance(rgb: tuple[int, int, int]) -> float:
    """The linear luminance a renderer will see, out of one 8-bit sRGB colour."""
    linear = [prop_grade.SRGB_TO_LINEAR[channel] for channel in rgb]
    return sum(channel * weight for channel, weight in zip(linear, prop_grade.LUMA))


def saturation(rgb: tuple[int, int, int]) -> float:
    _, value, _ = colorsys.rgb_to_hls(*(channel / 255.0 for channel in rgb))
    _, sat, _ = colorsys.rgb_to_hsv(*(channel / 255.0 for channel in rgb))
    return sat


def hue_degrees(rgb: tuple[int, int, int]) -> float:
    hue, _, _ = colorsys.rgb_to_hsv(*(channel / 255.0 for channel in rgb))
    return hue * 360.0


# The three colours this grade exists for, read off the committed atlas by
# sampling the UVs of `Skeleton_Minion` — see the module docstring for the
# measurement. They are written here as literals so the contract does not
# depend on reading the art.
BONE = (174, 200, 212)  # the skull and the limbs: cold blue-white, L=0.551
RIBS = (161, 95, 72)  # the body cells: warm red-brown, L=0.162
BOOT = (83, 71, 65)  # the darkest cell a Minion wears, L=0.067


class TheBoneGoesToIron(unittest.TestCase):
    def test_a_cold_bone_white_loses_its_blue(self) -> None:
        graded = enemy_grade.grade_colour(BONE, PALETTE)
        self.assertLess(
            saturation(graded),
            0.14,
            f"bone {BONE} graded to {graded}, which is still a coloured thing",
        )

    def test_it_lands_inside_the_range_the_palette_declares_for_metal(self) -> None:
        graded = enemy_grade.grade_colour(BONE, PALETTE)
        self.assertLessEqual(luminance(graded), enemy_grade.FAMILIES["iron"]["ceiling"])

    def test_and_it_is_far_darker_than_it_was(self) -> None:
        self.assertLess(luminance(enemy_grade.grade_colour(BONE, PALETTE)), luminance(BONE) / 2.0)


class TheBodyStaysRed(unittest.TestCase):
    def test_a_warm_red_brown_is_still_red(self) -> None:
        graded = enemy_grade.grade_colour(RIBS, PALETTE)
        hue = hue_degrees(graded)
        self.assertTrue(
            hue >= 330.0 or hue <= 30.0,
            f"ribs {RIBS} graded to {graded}, hue {hue:.0f} deg, which is not oxide",
        )

    def test_the_palette_has_a_red_so_the_red_is_not_thrown_away(self) -> None:
        self.assertGreater(saturation(enemy_grade.grade_colour(RIBS, PALETTE)), 0.2)


class TheFloatingSkull(unittest.TestCase):
    """The defect, stated as a ratio.

    A Crawler's skull cell is eight times the luminance of its boot cell, and a
    single tint multiplies both by the same number — so the ratio survives
    untouched and what a player sees at thirty metres is a bright skull with a
    dark smudge under it. The shoulder is what closes that, and closing it is
    the measurable half of this ticket.
    """

    def test_a_tint_cannot_close_the_gap_between_the_skull_and_the_boot(self) -> None:
        before = luminance(BONE) / luminance(BOOT)
        self.assertGreater(before, 7.0)

    def test_the_grade_does(self) -> None:
        before = luminance(BONE) / luminance(BOOT)
        after = luminance(enemy_grade.grade_colour(BONE, PALETTE)) / luminance(
            enemy_grade.grade_colour(BOOT, PALETTE)
        )
        self.assertLess(after, before / 2.0, f"{before:.1f}:1 became {after:.1f}:1")

    def test_but_it_does_not_flatten_them_into_one_colour(self) -> None:
        after = luminance(enemy_grade.grade_colour(BONE, PALETTE)) / luminance(
            enemy_grade.grade_colour(BOOT, PALETTE)
        )
        self.assertGreater(after, 1.5, "a skull and a boot that read the same is a blob")


class TheEdges(unittest.TestCase):
    def test_black_stays_black(self) -> None:
        self.assertEqual(enemy_grade.grade_colour((0, 0, 0), PALETTE), (0, 0, 0))

    def test_white_does_not_overflow(self) -> None:
        graded = enemy_grade.grade_colour((255, 255, 255), PALETTE)
        self.assertTrue(all(0 <= channel <= 255 for channel in graded), graded)


class TheAtlas(unittest.TestCase):
    def test_a_png_in_is_a_png_of_the_same_shape_out(self) -> None:
        pixels = bytes(
            bytearray(
                [BONE[0], BONE[1], BONE[2], 255, RIBS[0], RIBS[1], RIBS[2], 255] * 2
            )
        )
        source = prop_grade.write_png(2, 2, 4, pixels)
        graded = enemy_grade.grade_atlas(source, PALETTE)
        width, height, channels, out = prop_grade.read_png(graded)
        self.assertEqual((width, height, channels), (2, 2, 4))
        self.assertEqual(len(out), len(pixels))

    def test_the_alpha_is_carried_through(self) -> None:
        pixels = bytes(bytearray([BONE[0], BONE[1], BONE[2], 17] * 4))
        _, _, _, out = prop_grade.read_png(
            enemy_grade.grade_atlas(prop_grade.write_png(2, 2, 4, pixels), PALETTE)
        )
        self.assertEqual([out[i] for i in range(3, len(out), 4)], [17, 17, 17, 17])


class RegradingFromTheIntakeAtlas(unittest.TestCase):
    """Where the output is committed, prove it (#57).

    The graded atlas is a committed derived asset, like a Machine's `.glb` and
    unlike the weapon viewmodels — both ends are in the repository and the
    recipe is deterministic, so staleness can be *proved* rather than dated.
    """

    def test_reproduces_the_committed_atlas_byte_for_byte(self) -> None:
        intake = REPO / enemy_grade.INTAKE_ATLAS
        committed = REPO / enemy_grade.GRADED_ATLAS
        self.assertTrue(intake.exists(), f"{intake} is missing")
        self.assertTrue(committed.exists(), f"{committed} is missing; run enemy_grade.py")
        self.assertEqual(
            enemy_grade.grade_atlas(intake.read_bytes(), PALETTE),
            committed.read_bytes(),
            f"{enemy_grade.GRADED_ATLAS} is not what the recipe now produces;"
            " re-run `python3 tools/assets/enemy_grade.py`",
        )

    def test_the_script_runs_and_changes_nothing_on_a_clean_tree(self) -> None:
        before = (REPO / enemy_grade.GRADED_ATLAS).read_bytes()
        subprocess.run(
            [sys.executable, str(REPO / "tools/assets/enemy_grade.py")],
            check=True,
            capture_output=True,
        )
        self.assertEqual((REPO / enemy_grade.GRADED_ATLAS).read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
