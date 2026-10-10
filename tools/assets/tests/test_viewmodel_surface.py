"""Behaviour of the viewmodel surface module.

Seam: `tools/assets/viewmodel_surface.py`'s public functions, on invented pixels
and the committed palette. Split out of the converter for `prop_grade.py`'s
reason — the pixel arithmetic and the palette lookup have a contract of their
own, and **no licensed byte comes anywhere near this file**: every array here is
written out by hand, so these run on a clone that has bought nothing.

What they are about is the one thing a flat repaint could not get wrong and a
texture can: a map bound to the wrong channel is a weapon that renders shiny
where it should be matt, and a glTF reader cannot tell you that it is wrong — it
can only tell you a texture is present.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import viewmodel_surface  # noqa: E402


def flat(*texels: tuple[float, float, float, float]) -> list[float]:
    """Blender's `image.pixels` layout: one flat run of RGBA floats."""
    return [channel for texel in texels for channel in texel]


def linear(encoded: float) -> float:
    """The sRGB transfer function, written out here rather than imported.

    An independent source of truth on purpose: a test that linearised by calling
    the module's own helper would pass whatever that helper did, which is exactly
    the shape of the bug these assertions exist to catch.
    """
    if encoded <= 0.04045:
        return encoded / 12.92
    return ((encoded + 0.055) / 1.055) ** 2.4


class PacksSeparateMapsIntoTheOneGltfChannelThatCarriesBoth(unittest.TestCase):
    """glTF has no metallic texture and no roughness texture. It has one
    `metallicRoughnessTexture` whose **green** channel is roughness and whose
    **blue** channel is metallic, and these packs ship the two as separate
    greyscale files. So they have to be combined, and which channel goes where is
    not a thing a render makes obvious: swap them and a matt steel barrel becomes
    a mirror, which reads as a lighting bug rather than as a texture bug."""

    def test_roughness_lands_in_green_and_metallic_in_blue(self):
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=flat((0.25, 0.25, 0.25, 1.0)),
            metallic=flat((0.75, 0.75, 0.75, 1.0)))
        self.assertAlmostEqual(combined[1], 0.25, places=5)
        self.assertAlmostEqual(combined[2], 0.75, places=5)

    def test_it_reads_the_red_channel_of_a_greyscale_map(self):
        # These ship as RGB PNGs with the value repeated, not as single-channel
        # files, so there is a choice of which channel to believe. Red, because
        # that is the one a one-channel export would have written.
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=flat((0.6, 0.0, 0.0, 1.0)),
            metallic=flat((0.1, 0.0, 0.0, 1.0)))
        self.assertAlmostEqual(combined[1], 0.6, places=5)
        self.assertAlmostEqual(combined[2], 0.1, places=5)

    def test_red_is_left_white_because_nothing_reads_it(self):
        # glTF's occlusion lives in red, and the occlusion these packs ship is
        # folded into the albedo instead (see below), so leaving red at anything
        # other than 1.0 would darken a surface twice.
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=flat((0.3, 0.3, 0.3, 1.0)),
            metallic=flat((0.3, 0.3, 0.3, 1.0)))
        self.assertAlmostEqual(combined[0], 1.0, places=5)
        self.assertAlmostEqual(combined[3], 1.0, places=5)

    def test_every_texel_is_combined_and_the_length_is_preserved(self):
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=flat((0.1, 0, 0, 1), (0.2, 0, 0, 1), (0.3, 0, 0, 1)),
            metallic=flat((0.9, 0, 0, 1), (0.8, 0, 0, 1), (0.7, 0, 0, 1)))
        self.assertEqual(len(combined), 12)
        self.assertAlmostEqual(combined[1], 0.1, places=5)
        self.assertAlmostEqual(combined[5], 0.2, places=5)
        self.assertAlmostEqual(combined[9], 0.3, places=5)
        self.assertAlmostEqual(combined[2], 0.9, places=5)
        self.assertAlmostEqual(combined[10], 0.7, places=5)

    def test_two_maps_of_different_sizes_are_refused_by_their_lengths(self):
        # The alternative is numpy broadcasting them into something plausible and
        # wrong, which is the silence this whole ticket is about.
        with self.assertRaises(ValueError) as caught:
            viewmodel_surface.combine_metallic_roughness(
                roughness=flat((0.1, 0, 0, 1)),
                metallic=flat((0.1, 0, 0, 1), (0.2, 0, 0, 1)))
        self.assertIn("4", str(caught.exception))
        self.assertIn("8", str(caught.exception))

    def test_a_missing_metallic_map_leaves_the_channel_at_zero(self):
        # The scope lens ships a roughness map and no metallic one, which is
        # honest rather than incomplete: glass is a dielectric.
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=flat((0.4, 0, 0, 1)), metallic=None)
        self.assertAlmostEqual(combined[1], 0.4, places=5)
        self.assertAlmostEqual(combined[2], 0.0, places=5)

    def test_a_missing_roughness_map_keeps_the_metallic_one(self):
        combined = viewmodel_surface.combine_metallic_roughness(
            roughness=None, metallic=flat((0.9, 0, 0, 1)))
        self.assertAlmostEqual(combined[2], 0.9, places=5)

    def test_neither_map_is_nothing_to_combine(self):
        self.assertIsNone(
            viewmodel_surface.combine_metallic_roughness(roughness=None, metallic=None))


class FoldsOcclusionIntoTheAlbedoRatherThanAddingAChannel(unittest.TestCase):
    """`prop_grade.py`'s precedent — it "deepens the pack's baked occlusion into
    grime" at conversion time rather than carrying a channel for it.

    The alternative here is glTF's own `occlusionTexture`, which Blender's
    exporter will only write through an addon-supplied node group. Folding it in
    is pixel arithmetic this file can test, costs the runtime nothing, and
    occlusion is the least of the five maps on an object held 40 cm from one
    camera at one angle."""

    def test_occlusion_halves_the_light_a_texel_reflects_not_the_byte_it_stores(self):
        # **In linear.** An albedo map arrives sRGB-encoded (`image.pixels` hands
        # back the file's own values — see the module header), and occlusion is a
        # linear mask, so shading has to happen either side of the transfer
        # function. Doing it in the stored encoding instead is what made the tint
        # land twice, and it would make this surface 46% too bright.
        folded = viewmodel_surface.multiply_occlusion(
            albedo=flat((0.8, 0.4, 0.2, 1.0)),
            occlusion=flat((0.5, 0.5, 0.5, 1.0)))
        for channel, before in enumerate((0.8, 0.4, 0.2)):
            self.assertAlmostEqual(linear(folded[channel]), linear(before) * 0.5,
                                   places=5)

    def test_shading_in_the_stored_encoding_would_be_visibly_brighter(self):
        # The size of the mistake, as a number, so that nobody "simplifies" this
        # back: half of 0.8 encoded is 0.4, and the right answer is 0.586.
        folded = viewmodel_surface.multiply_occlusion(
            albedo=flat((0.8, 0.8, 0.8, 1.0)),
            occlusion=flat((0.5, 0.5, 0.5, 1.0)))
        self.assertAlmostEqual(folded[0], 0.58553, places=4)
        self.assertNotAlmostEqual(folded[0], 0.4, places=2)

    def test_it_leaves_alpha_alone(self):
        # The scope lens carries an alpha, and multiplying it by an occlusion
        # value would make the glass partly disappear where the mount shades it.
        folded = viewmodel_surface.multiply_occlusion(
            albedo=flat((0.8, 0.8, 0.8, 0.35)),
            occlusion=flat((0.25, 0.25, 0.25, 1.0)))
        self.assertAlmostEqual(folded[3], 0.35, places=5)

    def test_unoccluded_white_changes_nothing(self):
        before = flat((0.73, 0.21, 0.52, 1.0))
        folded = viewmodel_surface.multiply_occlusion(
            albedo=before, occlusion=flat((1.0, 1.0, 1.0, 1.0)))
        for index, channel in enumerate(before):
            self.assertAlmostEqual(folded[index], channel, places=5)

    def test_no_occlusion_map_is_the_albedo_unaltered(self):
        before = flat((0.1, 0.2, 0.3, 1.0))
        self.assertEqual(viewmodel_surface.multiply_occlusion(before, None), before)

    def test_maps_of_different_sizes_are_refused_rather_than_broadcast(self):
        with self.assertRaises(ValueError):
            viewmodel_surface.multiply_occlusion(
                albedo=flat((0.5, 0.5, 0.5, 1.0)),
                occlusion=flat((0.5, 0, 0, 1), (0.5, 0, 0, 1)))


class TurnsADirectxNormalMapTheRightWayUp(unittest.TestCase):
    """The AKM's normal map is called ``04_-_Default_Normal_DirectX.tga.png`` and
    it means it. DirectX takes +green as *down* where glTF and OpenGL take it as
    up, so a map shipped in that convention lights every slope on the weapon from
    the opposite side — which reads as the sun being in the wrong place rather
    than as a texture being upside down, and is exactly the class of defect a
    glTF reader cannot see. The pack says which convention it is in, in the file
    name, so this is a correction the recipe can state rather than guess."""

    def test_green_is_inverted_and_the_other_channels_are_not(self):
        flipped = viewmodel_surface.flip_normal_green(flat((0.1, 0.25, 0.9, 1.0)))
        self.assertAlmostEqual(flipped[0], 0.1, places=5)
        self.assertAlmostEqual(flipped[1], 0.75, places=5)
        self.assertAlmostEqual(flipped[2], 0.9, places=5)
        self.assertAlmostEqual(flipped[3], 1.0, places=5)

    def test_a_flat_normal_is_unchanged_by_the_flip(self):
        # 0.5 green is "no slope", which is its own mirror image. A map that came
        # out different here would mean the inversion was off by a half.
        flipped = viewmodel_surface.flip_normal_green(flat((0.5, 0.5, 1.0, 1.0)))
        self.assertAlmostEqual(flipped[1], 0.5, places=5)

    def test_flipping_twice_is_the_map_it_started_as(self):
        before = flat((0.2, 0.3, 0.8, 1.0), (0.6, 0.91, 0.4, 1.0))
        twice = viewmodel_surface.flip_normal_green(
            viewmodel_surface.flip_normal_green(before))
        for index, channel in enumerate(before):
            self.assertAlmostEqual(twice[index], channel, places=5)


class LevelsAMapToThePalettesOwnAlbedoRatherThanItsTint(unittest.TestCase):
    """The texture carries the **variation** and `base_color` carries the
    **level**, and that split is a render finding rather than a preference.

    `texture_tint` is the palette's knob for a *Machine*: the generated set was
    made to be lit as photographs, and the tint brings it back to interwar values
    for something read from metres away through SSAO and depth fog. A viewmodel
    is 40 cm from the eye at near-normal incidence to the sun, and dressed at the
    tint the Pneumatic Wrench's gloves measured **129 against a ground of 81** —
    half again as bright as the world behind them, where the flat colour they
    replaced measured 86. That is #42's Wall, #52's ore and #64's brightened
    tool: *a colour picked against the wrong background*, a fourth time.

    #64 settled which number is right for a thing in the hand — the Build Gun is
    drawn with the palette's flat `base_color` and reads correctly, as the Wall
    does. So the map is scaled so that its **mean linear value is that
    `base_color`**, which keeps every bit of the grain and puts the surface back
    at the level that was already known to work."""

    def test_the_mean_lands_on_the_palettes_base_colour(self):
        levelled = viewmodel_surface.level_albedo(
            flat((0.8, 0.8, 0.8, 1.0), (0.4, 0.4, 0.4, 1.0)),
            base_colour=(0.02, 0.04, 0.06))
        means = [sum(linear(levelled[t * 4 + c]) for t in range(2)) / 2
                 for c in range(3)]
        for channel, wanted in enumerate((0.02, 0.04, 0.06)):
            self.assertAlmostEqual(means[channel], wanted, places=5)

    def test_the_variation_survives_being_levelled(self):
        # The whole point. A flat repaint is what this replaces, so a map that
        # came out uniform would be the ticket undone with extra steps.
        levelled = viewmodel_surface.level_albedo(
            flat((0.9, 0.9, 0.9, 1.0), (0.3, 0.3, 0.3, 1.0)),
            base_colour=(0.05, 0.05, 0.05))
        bright, dark = linear(levelled[0]), linear(levelled[4])
        self.assertGreater(bright, dark)
        # and in the same proportion it arrived in, because the scale is linear
        self.assertAlmostEqual(bright / dark, linear(0.9) / linear(0.3), places=3)

    def test_a_black_map_is_left_alone_rather_than_divided_by_zero(self):
        levelled = viewmodel_surface.level_albedo(
            flat((0.0, 0.0, 0.0, 1.0)), base_colour=(0.05, 0.05, 0.05))
        self.assertEqual(len(levelled), 4)
        for channel in range(3):
            self.assertAlmostEqual(levelled[channel], 0.0, places=5)

    def test_it_leaves_alpha_alone(self):
        levelled = viewmodel_surface.level_albedo(
            flat((0.8, 0.8, 0.8, 0.25)), base_colour=(0.05, 0.05, 0.05))
        self.assertAlmostEqual(levelled[3], 0.25, places=5)

    def test_a_texel_that_would_pass_white_is_clamped(self):
        # A near-black map asked to average a bright colour cannot get there, and
        # white is where a texel stops. The mean then undershoots, which is the
        # honest outcome rather than a blown-out map.
        levelled = viewmodel_surface.level_albedo(
            flat((1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)),
            base_colour=(0.9, 0.9, 0.9))
        self.assertLessEqual(levelled[0], 1.0)


class DerivesANormalFromTheAlbedoWhenThePaletteShipsNoneToLoad(unittest.TestCase):
    """The generated set is **albedo only** — one PNG a surface, no normal map
    anywhere — so an arm dressed in it would carry a picture of grain on a
    surface that is geometrically a sheet of glass. That is the exact defect #42
    found on the ground: *"however worn the picture was, the surface was
    geometrically a sheet of glass: one normal over the whole Map, so a 23-degree
    sun fell on every square metre identically."*

    Its answer was to **derive** the relief rather than load it, and so is this:
    the gradient of the map's own luminance, which on rust, weave and tread plate
    is where the relief is. What a render has to settle, and a test cannot, is the
    strength — #42's lesson is that *what is visible is the slope, not the
    height*, and that the physically-reasoned first guess was invisible."""

    def test_the_knob_is_the_slope_itself_whatever_the_maps_contrast(self):
        """#42's lesson as an interface rather than as a comment.

        A plain multiplier means something different on every map: measured over
        the palette's own four, the same number gives `riveted_steel_plate` five
        times the slope it gives `olive_drab_paint`, because one is rivets and
        the other is smooth paint. So the recipe would have had to carry a
        strength per surface, each one found by looking.

        The knob is therefore **the mean slope in degrees**, solved for. #42
        found that *what is visible is the slope, not the height*, and that its
        physically reasoned first guess rendered as no change at all — and the
        first attempt here did exactly the same, at 0.66 degrees on the arms,
        which is a tilt the sun cannot find."""
        # Both at period four along the row. A period-*two* pattern is the one
        # shape central differences cannot see at all — `f[x+1]` and `f[x-1]` are
        # the same texel value, so the gradient is exactly zero — which is a true
        # property of the filter and makes for a useless fixture.
        smooth = flat(*[(0.50 + 0.02 * (i % 4 < 2), 0.5, 0.5, 1.0) for i in range(64)])
        rough = flat(*[(0.20 + 0.60 * (i % 4 < 2), 0.5, 0.5, 1.0) for i in range(64)])
        for name, pixels in (("smooth", smooth), ("rough", rough)):
            normal = viewmodel_surface.normal_from_albedo(
                pixels, width=8, height=8, degrees=8.0)
            self.assertAlmostEqual(self.mean_slope(normal), 8.0, delta=0.5,
                                   msg=f"{name} map did not land on 8 degrees")

    def test_asking_for_a_steeper_slope_gets_one(self):
        pixels = flat(*[(0.2 + 0.1 * (i % 4), 0.5, 0.5, 1.0) for i in range(64)])
        gentle = viewmodel_surface.normal_from_albedo(
            pixels, width=8, height=8, degrees=4.0)
        steep = viewmodel_surface.normal_from_albedo(
            pixels, width=8, height=8, degrees=20.0)
        self.assertAlmostEqual(self.mean_slope(gentle), 4.0, delta=0.5)
        self.assertAlmostEqual(self.mean_slope(steep), 20.0, delta=0.5)

    @staticmethod
    def mean_slope(normal) -> float:
        import math
        total, count = 0.0, 0
        for texel in range(0, len(normal), 4):
            x = (normal[texel] - 0.5) * 2.0
            y = (normal[texel + 1] - 0.5) * 2.0
            z = max((normal[texel + 2] - 0.5) * 2.0, 1e-9)
            total += math.degrees(math.atan(math.hypot(x, y) / z))
            count += 1
        return total / count

    def test_a_flat_map_derives_a_flat_normal(self):
        # 0.5, 0.5, 1.0 is "straight out of the surface" in a tangent-space map.
        # No gradient anywhere means nothing to solve a slope against, and the
        # answer is the flat normal rather than a division by zero.
        normal = viewmodel_surface.normal_from_albedo(
            flat(*[(0.4, 0.4, 0.4, 1.0)] * 16), width=4, height=4, degrees=8.0)
        for texel in range(16):
            self.assertAlmostEqual(normal[texel * 4 + 0], 0.5, places=4)
            self.assertAlmostEqual(normal[texel * 4 + 1], 0.5, places=4)
            self.assertAlmostEqual(normal[texel * 4 + 2], 1.0, places=4)

    def test_a_slope_across_one_axis_tilts_that_axis_and_leaves_the_other(self):
        # A ramp in u only. Red carries the u slope and green the v slope, so a
        # map that tilted green here would be transposed — which lights every
        # groove across the grain instead of along it.
        rows = []
        for _row in range(4):
            rows.extend([(value, value, value, 1.0) for value in (0.0, 0.3, 0.6, 0.9)])
        normal = viewmodel_surface.normal_from_albedo(
            flat(*rows), width=4, height=4, degrees=8.0)
        reds = [normal[t * 4 + 0] for t in range(16)]
        greens = [normal[t * 4 + 1] for t in range(16)]
        self.assertTrue(max(reds) - min(reds) > 0.01 or abs(reds[1] - 0.5) > 0.01,
                        f"a slope in u left red flat: {reds[:4]}")
        for green in greens:
            self.assertAlmostEqual(green, 0.5, places=4)

    def test_zero_degrees_is_the_switch_that_turns_the_relief_off(self):
        # Every camera number in `[player]` takes 0 as off and so does this.
        rows = [(value, value, value, 1.0) for value in (0.0, 0.3, 0.6, 0.9)] * 4
        normal = viewmodel_surface.normal_from_albedo(
            flat(*rows), width=4, height=4, degrees=0.0)
        for texel in range(16):
            self.assertAlmostEqual(normal[texel * 4 + 0], 0.5, places=4)
            self.assertAlmostEqual(normal[texel * 4 + 1], 0.5, places=4)

    def test_it_is_a_unit_vector_so_the_shader_does_not_have_to_normalise(self):
        rows = [(value, value, value, 1.0) for value in (0.0, 0.9, 0.2, 0.7)] * 4
        normal = viewmodel_surface.normal_from_albedo(
            flat(*rows), width=4, height=4, degrees=12.0)
        for texel in range(16):
            vector = [normal[texel * 4 + axis] * 2.0 - 1.0 for axis in range(3)]
            length = sum(component * component for component in vector) ** 0.5
            self.assertAlmostEqual(length, 1.0, places=3)

    def test_the_size_it_is_told_has_to_match_the_pixels_it_is_given(self):
        with self.assertRaises(ValueError):
            viewmodel_surface.normal_from_albedo(
                flat((0.5, 0.5, 0.5, 1.0)), width=4, height=4, degrees=8.0)


class ReadsASurfaceOutOfTheOnePaletteEveryMachineWears(unittest.TestCase):
    """The arms sleeve and the whole RgsDev rig have no maps to recover, so they
    wear the palette's own generated textures — literally the surfaces the
    Machines wear, from one declaration. `dieselpunk_palette.json` is the
    authority and this does not get a second copy of any of its numbers."""

    def test_a_surface_carries_the_palette_entrys_own_numbers(self):
        surface = viewmodel_surface.palette_surface("WeldedSteel")
        self.assertEqual(surface["name"], "WeldedSteel")
        self.assertEqual(surface["metallic"], 1.0)
        self.assertEqual(surface["roughness"], 0.45)

    def test_a_textured_entry_names_a_map_that_is_committed(self):
        # `assets/generated/` is tracked (#59), so unlike every other asset in
        # this recipe these are present in a clone that has bought nothing.
        surface = viewmodel_surface.palette_surface("OliveDrab")
        self.assertTrue(surface["texture"].exists(), surface["texture"])
        self.assertGreater(surface["texture_scale_m"], 0.0)

    def test_the_base_colour_is_the_palettes_and_not_a_second_opinion(self):
        import machine_materials
        entry = next(e for e in machine_materials.load() if e["name"] == "OliveDrab")
        self.assertEqual(viewmodel_surface.palette_surface("OliveDrab")["base_color"],
                         tuple(entry["base_color"]))

    def test_a_surface_does_not_carry_the_tint_because_nothing_here_reads_it(self):
        # `level_albedo` uses `base_color` instead, for the reason written there.
        # A field nothing reads is the thing a warning exists for elsewhere in
        # this project, so it is simply not carried.
        self.assertNotIn("texture_tint", viewmodel_surface.palette_surface("OliveDrab"))

    def test_an_entry_the_palette_does_not_declare_is_refused_by_name(self):
        # A typo in the recipe must not quietly become a flat surface, which is
        # the failure mode this ticket exists to remove.
        with self.assertRaises(KeyError) as caught:
            viewmodel_surface.palette_surface("GunmetalBlue")
        self.assertIn("GunmetalBlue", str(caught.exception))

    def test_an_untextured_entry_is_refused_for_a_viewmodel(self):
        # A gauge bezel has no map on purpose, and dressing an arm in one would
        # be a flat repaint wearing this flag's name.
        with self.assertRaises(KeyError) as caught:
            viewmodel_surface.palette_surface("DullBrass")
        self.assertIn("DullBrass", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
