"""Behaviour of the set-dressing colour grade.

Seam: `prop_grade`'s four public moves — `grade_colour`, `grade_emission_colour`,
`deepen_grime` and the PNG pair round-tripping an image through them — asserted
on **invented pixels**. Not one licensed byte is involved, which is the same rule
`test_convert_props.py` keeps and for the same reason: the packs are not in this
repository and a test that needed them would be a test one machine could run.

What is actually being pinned here is the claim the grade exists to make, and it
is a claim about *values rather than about hues*: a purchased prop must not be
brighter than a Machine. The Machines' own generated textures, multiplied by the
`texture_tint` the palette gives each of them, run 0.03 to 0.14 in linear albedo
luminance. So does every graded texel, and `test_nothing_comes_out_brighter_than
_a_machine` is the test that says so.
"""

import colorsys
import json
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prop_grade  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
PALETTE = REPO / "tools" / "assets" / "dieselpunk_palette.json"

# What the Machines are, measured the same way, and therefore what the props have
# to fit inside. See the module docstring of `prop_grade`.
MACHINE_ALBEDO_CEILING = 0.14


def linear_luminance(rgb: tuple[int, int, int]) -> float:
    linear = [prop_grade.SRGB_TO_LINEAR[channel] for channel in rgb]
    return sum(channel * weight for channel, weight in zip(linear, prop_grade.LUMA))


def saturation_of(rgb: tuple[int, int, int]) -> float:
    _, saturation, _ = colorsys.rgb_to_hsv(*[channel / 255.0 for channel in rgb])
    return saturation


def hue_of(rgb: tuple[int, int, int]) -> float:
    hue, _, _ = colorsys.rgb_to_hsv(*[channel / 255.0 for channel in rgb])
    return hue * 360.0


class GradeTest(unittest.TestCase):
    def setUp(self):
        self.palette = prop_grade.load_palette(PALETTE)
        self.targets = prop_grade._targets(self.palette)

    def grade(self, rgb):
        return prop_grade.grade_colour(rgb, self.targets)

    # ── The value claim, which is the whole point ────────────────────────────

    def test_nothing_comes_out_brighter_than_a_machine(self):
        # Walked rather than sampled: every eighth step of the whole 8-bit cube is
        # 32768 colours, which is more distinct colours than the real atlas has.
        brightest = 0.0
        for red in range(0, 256, 8):
            for green in range(0, 256, 8):
                for blue in range(0, 256, 8):
                    brightest = max(brightest, linear_luminance(self.grade((red, green, blue))))
        self.assertLessEqual(
            brightest,
            MACHINE_ALBEDO_CEILING,
            "a graded prop texel is brighter than the brightest Machine surface",
        )

    def test_safety_yellow_stops_being_safety_yellow(self):
        # The single loudest thing in the pack: eleven per cent of the atlas is
        # this, and before the grade it was six times a Machine's brightness.
        before = (196, 154, 44)
        after = self.grade(before)
        self.assertGreater(linear_luminance(before), 0.3)
        self.assertLess(linear_luminance(after), 0.11)
        self.assertLess(saturation_of(after), saturation_of(before))

    def test_white_becomes_steel_rather_than_staying_the_brightest_thing(self):
        after = self.grade((242, 242, 242))
        self.assertLess(linear_luminance(after), MACHINE_ALBEDO_CEILING)
        self.assertLess(saturation_of(after), 0.2)

    def test_black_stays_black(self):
        # The atlas is half unused and the unused half is zero. A grade that
        # lifted it off zero would put a grey rectangle on every prop's seams.
        self.assertEqual(self.grade((0, 0, 0)), (0, 0, 0))

    # ── The hue claim: onto the palette's ramps, not away from them ──────────

    def test_process_teal_becomes_metal_and_not_some_other_colour(self):
        # There is no teal, cyan or blue anywhere in the palette, so the honest
        # remap for a teal pipe is a steel pipe. Turning it red would be as wrong
        # as leaving it teal.
        after = self.grade((62, 98, 95))
        self.assertLess(saturation_of(after), 0.2, "teal kept too much of its colour")

    def test_a_red_stays_in_the_red_family_because_the_palette_has_one(self):
        after = self.grade((151, 58, 45))
        hue = hue_of(after)
        oxide = self.targets["oxide"]["hue"]
        self.assertLess(min(abs(hue - oxide), 360.0 - abs(hue - oxide)), 25.0)

    def test_the_families_take_their_hues_from_the_palette_file(self):
        # Not from a number copied into this module. Editing `base_color` in
        # `dieselpunk_palette.json` has to move the grade, or the palette has
        # stopped being the one authority on what this world is coloured.
        materials = json.loads(PALETTE.read_text())["materials"]
        by_name = {entry["name"]: entry for entry in materials}
        for name, spec in prop_grade.FAMILIES.items():
            colour = by_name[spec["material"]]["base_color"]
            expected, _, _ = colorsys.rgb_to_hsv(colour[0], colour[1], colour[2])
            self.assertAlmostEqual(self.targets[name]["hue"], expected * 360.0, places=4)

    # ── Emission ─────────────────────────────────────────────────────────────

    def test_a_lamp_keeps_its_brightness_and_loses_its_colour(self):
        # The pack's glow map has a turquoise and a green in it, which under a
        # multiply operator put a neon sign in a 1930s yard.
        turquoise = prop_grade.grade_emission_colour((111, 210, 194))
        self.assertGreater(turquoise[0], turquoise[2], "a lit texel should be warm")
        self.assertAlmostEqual(hue_of(turquoise), prop_grade.TUNGSTEN_HUE, delta=3.0)

    def test_an_unlit_texel_stays_exactly_unlit(self):
        # The shared material multiplies by this map, so a texel that is not
        # exactly zero is a lamp. Almost-zero would light the whole yard.
        self.assertEqual(prop_grade.grade_emission_colour((0, 0, 0)), (0, 0, 0))

    # ── Grime ────────────────────────────────────────────────────────────────

    def test_grime_darkens_a_crease_and_leaves_a_flat_panel_alone(self):
        document, binary = a_prop_with_occlusion([1.0, 0.75, 0.503])
        touched = prop_grade.deepen_grime(document, binary)
        self.assertEqual(touched, 1)
        after = read_colours(document, binary)
        self.assertAlmostEqual(after[0][0], 1.0, places=2)
        self.assertLess(after[1][0], 0.75)
        self.assertLess(after[2][0], 0.503)

    def test_grime_is_warm_rather_than_neutral(self):
        # Soot in a crease is browner than the surface it sits in; a grey
        # multiplier would only turn the lights down.
        document, binary = a_prop_with_occlusion([0.503])
        prop_grade.deepen_grime(document, binary)
        red, green, blue = read_colours(document, binary)[0]
        self.assertGreater(red, blue)

    def test_grime_never_reaches_zero(self):
        document, binary = a_prop_with_occlusion([0.0])
        prop_grade.deepen_grime(document, binary)
        # To within one step of the sixteen-bit quantisation the pack stores it in.
        self.assertAlmostEqual(
            read_colours(document, binary)[0][0], prop_grade.GRIME_FLOOR, places=4
        )

    def test_a_prop_with_no_vertex_colours_is_not_a_failure(self):
        # Two of the three packs have none; it is an ordinary state.
        self.assertEqual(prop_grade.deepen_grime({"meshes": []}, bytearray()), 0)

    # ── The PNG pair, which has to round-trip or none of the above lands ─────

    def test_an_image_survives_the_round_trip_unchanged_when_nothing_grades_it(self):
        pixels = bytes(range(0, 48))
        encoded = prop_grade.write_png(4, 4, 3, pixels)
        width, height, channels, decoded = prop_grade.read_png(encoded)
        self.assertEqual((width, height, channels), (4, 4, 3))
        self.assertEqual(decoded, pixels)

    def test_every_png_row_filter_decodes(self):
        # `write_png` only ever emits filter 0, so the four it does not emit are
        # exercised here against hand-built rows — the packs' own PNGs use all of
        # them and a wrong Paeth is a subtly wrong atlas rather than a crash.
        import zlib

        width, height = 3, 5
        stride = width * 3
        flat = bytes((i * 7 + 11) % 256 for i in range(stride * height))
        raw = bytearray()
        previous = bytes(stride)
        for row in range(height):
            line = flat[row * stride : (row + 1) * stride]
            method = row  # 0..4, one of each
            encoded = bytearray()
            for i, value in enumerate(line):
                left = line[i - 3] if i >= 3 else 0
                up = previous[i]
                upper_left = previous[i - 3] if i >= 3 else 0
                if method == 0:
                    encoded.append(value)
                elif method == 1:
                    encoded.append((value - left) & 0xFF)
                elif method == 2:
                    encoded.append((value - up) & 0xFF)
                elif method == 3:
                    encoded.append((value - ((left + up) >> 1)) & 0xFF)
                else:
                    estimate = left + up - upper_left
                    candidates = (
                        (abs(estimate - left), left),
                        (abs(estimate - up), up),
                        (abs(estimate - upper_left), upper_left),
                    )
                    encoded.append((value - min(candidates)[1]) & 0xFF)
            raw.append(method)
            raw += encoded
            previous = line
        png = bytearray(b"\x89PNG\r\n\x1a\n")
        for kind, body in (
            (b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
            (b"IDAT", zlib.compress(bytes(raw))),
            (b"IEND", b""),
        ):
            png += struct.pack(">I", len(body)) + kind + body
            png += struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        _, _, _, decoded = prop_grade.read_png(bytes(png))
        self.assertEqual(decoded, flat)

    def test_a_png_this_cannot_honestly_handle_raises_rather_than_mangling(self):
        png = bytearray(b"\x89PNG\r\n\x1a\n")
        body = struct.pack(">IIBBBBB", 1, 1, 8, 3, 0, 0, 0)  # palettised
        png += struct.pack(">I", len(body)) + b"IHDR" + body
        png += struct.pack(">I", 0)
        with self.assertRaises(ValueError):
            prop_grade.read_png(bytes(png))

    def test_an_alpha_channel_is_carried_through_untouched(self):
        pixels = bytes([200, 30, 30, 17, 0, 0, 0, 255])
        encoded = prop_grade.write_png(2, 1, 4, pixels)
        graded = prop_grade.grade_albedo(encoded, self.palette)
        _, _, channels, decoded = prop_grade.read_png(graded)
        self.assertEqual(channels, 4)
        self.assertEqual(decoded[3], 17)
        self.assertEqual(decoded[7], 255)


# ── Fixtures ────────────────────────────────────────────────────────────────


def a_prop_with_occlusion(values: list[float]) -> tuple[dict, bytearray]:
    """A glTF document whose only attribute is a greyscale `COLOR_0`."""
    binary = bytearray()
    for value in values:
        amount = int(round(max(0.0, min(1.0, value)) * 65535))
        binary += struct.pack("<HHHH", amount, amount, amount, 65535)
    document = {
        "meshes": [{"primitives": [{"attributes": {"COLOR_0": 0}}]}],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5123,
                "normalized": True,
                "count": len(values),
                "type": "VEC4",
            }
        ],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(binary)}],
    }
    return document, binary


def read_colours(document: dict, binary: bytearray) -> list[tuple[float, float, float]]:
    count = document["accessors"][0]["count"]
    out = []
    for index in range(count):
        red, green, blue, _ = struct.unpack_from("<HHHH", binary, index * 8)
        out.append((red / 65535.0, green / 65535.0, blue / 65535.0))
    return out


if __name__ == "__main__":
    unittest.main()
