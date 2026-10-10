#!/usr/bin/env python3
"""Grade the committed KayKit skeleton atlas into `dieselpunk_palette.json`.

    python3 tools/assets/enemy_grade.py

Reads `assets/characters/kaykit_skeletons/intake_textures/skeleton_texture_A.png`
and writes `assets/characters/kaykit_skeletons/graded/skeleton_texture_A.png`,
which is what `WorldView._skinned_mesh` paints every Enemy with. Both ends are
committed and the recipe is deterministic, so staleness here is *proved* rather
than dated — `tools/assets/tests/test_enemy_grade.py` regrades and compares the
bytes, which is `test_generated_machines`' arrangement and #57's rule.

── Why a graded atlas and not a tint ────────────────────────────────────────

#38 dressed the Enemies in six committed CC0 KayKit characters and wrote down
the mismatch in `WorldView._skinned_mesh`'s own comment: *clean fantasy
skeletons in a world of grimy cast iron*. What it did about it was multiply
every surface by one dark colour per kind. #75 is the user looking at the
result and saying the Enemies look like shit, and they were right — a tint is
`prop_grade.py`'s first attempt arriving a second time, and it fails the same
way, for a reason that is arithmetic rather than taste.

**A multiply cannot change a ratio.** Measured off the committed atlas by
sampling `Skeleton_Minion`'s own UVs, the cells a Crawler wears are:

    skull, limbs   (174, 200, 212)  cold blue-white   linear L = 0.551
    ribs, pelvis   (161,  95,  72)  warm red-brown    linear L = 0.162
    boots          ( 83,  71,  65)  near-black        linear L = 0.067

Eight to one between the skull and the boot, and one tint multiplies both by
the same number — so whatever the tint is, a Crawler is a bright skull with a
dark smudge under it. Turning the tint down does not close the gap; it just
moves the whole thing toward black, which is exactly what shipped. Measured off
the `swarm bare` render that opened #75, a Crawler's body was rendering at a
linear luminance of **0.007** against a ground at **0.046** — one seventh of
the thing it stands on, which is not a dark enemy, it is a hole in the floor.

**And the hue is wrong in a direction a multiply cannot reach.** Bone is a cold
blue-white at about 200 degrees. There is no blue anywhere in this palette, and
multiplying a blue by a brown gives a dark blue-brown, not iron.

── What this does instead ───────────────────────────────────────────────────

`prop_grade.grade_colour`'s rule, with this atlas's families and this subject's
ceilings: a texel is sorted into a family by hue and saturation, pulled toward
that family's palette material in hue and saturation, and its luminance run
through a shoulder `ceiling * L / (L + knee)`. Bone and steel become iron, the
red-browns stay oxide red because the palette has one, and the pack's turquoise
and purple have no counterpart and become metal.

The shoulder is what closes the ratio: it compresses the top and lifts nothing,
so 8:1 becomes about 3.5:1 — enough that a skull still reads as the brightest
part of a Crawler and not enough that it reads as a separate object.

**The ceilings are higher than `prop_grade`'s and that is deliberate.** A prop
is scenery and is supposed to lose a contrast fight with the Machine beside it;
an Enemy is the thing a player spends a whole Run looking at and shooting, and
on the shipped Map it is seen against the *ground*, which renders four to five
times brighter than any Machine surface. #52 paid for the other reading of this
rule — an ore marker picked against the palette rather than against the floor
it lies on, and invisible for it. The colours to check a mark against are the
ones it is guaranteed to be seen beside.

The remaining half of the surface is not here, because it is not in the atlas:
this pack bakes no ambient occlusion into `COLOR_0` the way heyheythere does,
and its cells are flat swatches with a vertical gradient and no detail at all.
So the grime and the relief are procedural, in `game/enemy_skin.gdshader`,
derived from the rest-pose position the way `ground.gdshader` derives the
yard's relief from the world position. See that file.

Standard library only, like `prop_grade`, because `tools/assets/run_tests.sh`
is a CI command.
"""

from __future__ import annotations

import colorsys
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import prop_grade

# Where the one atlas comes from and where the graded one goes. Six characters
# share it — `rebuild_assets.sh` passes the same `--texture-dir` to every one —
# so there is one file to grade and one graded file for every Enemy to wear.
#
# **Atlas B is deliberately not graded.** No committed character references it:
# `rebuild_assets.sh` recovers whatever each FBX names, and all six named A. A
# graded copy of a map nothing reads is the defect `prop_grade`'s own docstring
# opens with, in the other direction.
INTAKE_ATLAS = "assets/characters/kaykit_skeletons/intake_textures/skeleton_texture_A.png"
GRADED_ATLAS = "assets/characters/kaykit_skeletons/graded/skeleton_texture_A.png"

# The families, in `prop_grade.FAMILIES`' shape. `ceiling` and `knee` are the
# shoulder and they are the two numbers this file is actually about; the hue and
# saturation targets come out of the palette by name, as they do there.
#
# `knee` is shorter than the props' 0.40-0.42 on purpose: a smaller knee is a
# harder compression, and the thing being compressed here is the eight-to-one
# gap between a skull and a boot rather than a stop of studio brightness.
FAMILIES = {
    # Bone, steel, the Warrior's helmet, the Golem's slab body, and the whole
    # cold half of the wheel — there is no blue, teal or purple in the palette,
    # so a cold texel is simply metal. This is most of every Enemy.
    "iron": {
        "material": "CastIron",
        "ceiling": 0.15,
        "knee": 0.30,
        "saturation": 0.07,
        "hue_pull": 0.9,
        "saturation_pull": 0.9,
    },
    # The red-browns the pack dresses its ribcages and cloaks in, which are the
    # one thing in this atlas the palette already has a name for.
    "oxide": {
        "material": "OxideRed",
        "ceiling": 0.17,
        "knee": 0.30,
        "saturation": 0.34,
        "hue_pull": 0.8,
        "saturation_pull": 0.6,
    },
    # Oranges and yellow-greens. Small on this atlas, and painted canvas and
    # webbing is where it lands.
    "olive": {
        "material": "OliveDrab",
        "ceiling": 0.16,
        "knee": 0.30,
        "saturation": 0.33,
        "hue_pull": 0.82,
        "saturation_pull": 0.7,
    },
}

# Which family a hue falls in. Narrower on the warm end than `prop_grade`'s,
# because this atlas's green arc runs all the way into the turquoise the pack
# paints its eye sockets with, and turquoise has no counterpart here either.
HUE_ARCS = [
    (338.0, 22.0, "oxide"),
    (22.0, 130.0, "olive"),
]

# Below this a texel has no hue worth keeping. Higher than the props' 0.16: the
# bone cells sit at about 0.18 saturation and are a *cold* blue-white rather
# than a tinted grey, so the arc test is what should decide them, not the floor.
CHROMA_FLOOR = 0.12


def _targets(palette: dict[str, dict]) -> dict[str, dict]:
    """Each family's spec with the palette's own hue filled in."""
    resolved = {}
    for name, spec in FAMILIES.items():
        colour = palette[spec["material"]]["base_color"]
        hue, _, _ = colorsys.rgb_to_hsv(colour[0], colour[1], colour[2])
        resolved[name] = dict(spec, hue=hue * 360.0)
    return resolved


def _family_of(hue_degrees: float, saturation: float) -> str:
    if saturation < CHROMA_FLOOR:
        return "iron"
    for start, end, name in HUE_ARCS:
        if start > end:
            if hue_degrees >= start or hue_degrees < end:
                return name
        elif start <= hue_degrees < end:
            return name
    return "iron"


def grade_colour(rgb: tuple[int, int, int], palette: dict[str, dict]) -> tuple[int, int, int]:
    """One 8-bit sRGB colour of the atlas, remapped onto the palette.

    `prop_grade.grade_colour`'s rule with this file's families and arcs. It is
    reimplemented here as a four-line wrapper rather than shared, because what
    differs between the two is the *classifier* and not the arithmetic, and
    threading a classifier through that function would make the props' rule
    read as a special case of something more general than it is.
    """
    red, green, blue = (channel / 255.0 for channel in rgb)
    hue, saturation, _ = colorsys.rgb_to_hsv(red, green, blue)
    return _apply(rgb, _targets(palette)[_family_of(hue * 360.0, saturation)])


def _apply(rgb: tuple[int, int, int], spec: dict) -> tuple[int, int, int]:
    """Hue and saturation toward the family, luminance through its shoulder.

    Decided in sRGB where a hue matches what a human called the colour, and
    scaled in linear light where a ratio means what a renderer will do with it —
    `prop_grade.grade_colour`'s split, kept deliberately identical so the two
    graded sets agree about what "in the palette" means.
    """
    import colorsys

    red, green, blue = (channel / 255.0 for channel in rgb)
    hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)

    graded_hue = prop_grade._blend_hue(hue * 360.0, spec["hue"], spec["hue_pull"]) / 360.0
    graded_saturation = saturation + (spec["saturation"] - saturation) * spec["saturation_pull"]
    toned = colorsys.hsv_to_rgb(graded_hue, graded_saturation, value)

    linear = [prop_grade.SRGB_TO_LINEAR[int(round(channel * 255.0))] for channel in toned]
    luminance = sum(channel * weight for channel, weight in zip(linear, prop_grade.LUMA))
    if luminance <= 0.0:
        return (0, 0, 0)
    wanted = spec["ceiling"] * luminance / (luminance + spec["knee"])
    scale = wanted / luminance
    out = [min(1.0, channel * scale) for channel in linear]
    return tuple(
        int(round(min(1.0, max(0.0, prop_grade._linear_to_srgb(channel))) * 255.0))
        for channel in out
    )


def grade_atlas(data: bytes, palette: dict[str, dict]) -> bytes:
    """The character atlas, remapped onto the palette. PNG in, PNG out."""
    width, height, channels, pixels = prop_grade.read_png(data)
    graded = prop_grade.grade_image(pixels, channels, lambda rgb: grade_colour(rgb, palette))
    return prop_grade.write_png(width, height, channels, graded)


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parents[2]
    palette = prop_grade.load_palette(repo / "tools/assets/dieselpunk_palette.json")
    intake = repo / INTAKE_ATLAS
    graded = repo / GRADED_ATLAS
    graded.parent.mkdir(parents=True, exist_ok=True)
    output = grade_atlas(intake.read_bytes(), palette)
    unchanged = graded.exists() and graded.read_bytes() == output
    graded.write_bytes(output)
    print(f"{'unchanged' if unchanged else 'wrote'} {GRADED_ATLAS} ({len(output)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
