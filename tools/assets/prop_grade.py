#!/usr/bin/env python3
"""Grade a purchased prop pack into `dieselpunk_palette.json`'s own colours.

Used by ``convert_props.py``; split out because it is the artistic half of that
script and has a contract of its own that
``tools/assets/tests/test_prop_grade.py`` can test on invented pixels, with no
licensed byte anywhere near it.

── Why a remap and not a tint ───────────────────────────────────────────────

The first pass at this multiplied each pack's ``baseColorFactor`` by a colour
pulled toward the palette. Two things were wrong with that.

**It did nothing at all for the props a player actually stands among.** All 213
heyheythere props share one atlas, so ``convert_props.py`` strips the image out
of every GLB and ``SetDressing`` puts *one* ``StandardMaterial3D`` back as a
``material_override``. An override replaces the mesh's material outright — the
graded ``baseColorFactor`` in the GLB is never read by anything. The only thing
that decides what a prop in the foreground is coloured is **the atlas**, and the
atlas was shipped through untouched.

**And a multiply would have been the wrong move even where it landed.** The
palette's quarrel with these packs is not that they are the wrong brightness of
the right colour. It is that they are a different art direction: clean modern
high-visibility industrial, safety yellow and process teal over white, against
1920s-40s heavy industry — cast iron, welded steel, olive drab over red-oxide
primer, soot. Multiplying a safety-yellow pipe by a brown makes a darker
safety-yellow pipe. Measured against the Machines' own surfaces:

    Machine textures, effective linear albedo luminance     0.03 .. 0.14
    heyheythere atlas, same measure, median 0.175, p95      0.58

Sixty-one per cent of the atlas was brighter than the brightest thing on any
Machine, which is the whole of the defect: the decoration was the brightest and
newest-looking matter in a world of grimy castings, and it took the eye off the
Machines, which are the objects a player has to read.

── What this does instead ───────────────────────────────────────────────────

Three passes, all at conversion time, so the runtime cost is exactly zero:

1. ``grade_albedo`` **remaps every texel onto one of the palette's own ramps.**
   A texel is sorted into a family by hue and saturation — neutral, red, or
   yellow/green — and each family names a palette material it is pulled toward
   in hue and saturation, and a shoulder curve that lands its luminance inside
   that material's *measured* range. Teal and blue have no counterpart in the
   palette at all, so they go to iron: a process-teal pipe becomes a steel pipe,
   not a red one. Safety yellow goes to olive drab, which is where a painted
   pipe in 1935 would in fact have been.

   The shoulder is ``ceiling * L / (L + knee)``, which compresses the top
   without flattening it — relief and wear survive, the stop-and-a-half of
   studio brightness does not — and it darkens the bottom end, which is free
   grime.

2. ``grade_emission`` does the same for the glow atlas, where the problem is
   narrower and louder: the pack's lit texels include a turquoise and a green,
   so the yard had a neon sign in it. Everything emissive is forced to one
   tungsten hue at its own brightness.

3. ``deepen_grime`` is the part the palette asks for by name and hue cannot
   give. The props are factory-clean; the palette names soot. heyheythere bakes
   its ambient occlusion into ``COLOR_0``, over a timid range (0.50 .. 1.00), so
   raising that to a power and tinting its dark end toward soot puts dirt in
   exactly the creases a renderer cannot find for itself, per prop, geometrically
   correct, at no cost to anything.

**Hazard colour is not abolished, it is moved.** Period industry painted
bollards and kerbs, and a yellow stripe reads as 1930s when everything round it
is filthy — the defect was uniform brightness, not the existence of colour. So
the atlas loses its safety yellow wholesale, and ``game/set_dressing.gd`` paints
it back onto a named handful of prop kinds with the palette's own
``HazardYellow``, where it is a deliberate placement rather than whatever the
pack happened to spray.

Nothing here needs Blender, numpy or Pillow: ``tools/assets/run_tests.sh`` is a
CI command and the rest of this directory is standard library, so this is too.
The atlas is 2048 square but carries only about twenty thousand distinct
colours, so the grade is computed once per colour and applied through a lookup.
"""

from __future__ import annotations

import colorsys
import json
import pathlib
import struct
import zlib

# ── The targets, read out of the palette ─────────────────────────────────────
#
# A family is a slice of the colour wheel, the palette material it is remapped
# onto, and how hard. `hue` and `saturation` come from that material's
# `base_color`; `ceiling` and `knee` are the shoulder, and they are tuned so the
# family lands inside the *measured* linear-albedo range of the material's own
# generated texture (`tools/assets/machine_materials.py` is where those textures
# get their `texture_tint`, and the ranges above are of the tinted result).
#
# `hue_pull` and `saturation_pull` are deliberately short of 1.0. Snapping every
# texel onto exactly three hues would make the yard look stencilled; leaving a
# fifth of the original keeps crates distinguishable from drums while putting
# the whole set inside the palette's gamut.

FAMILIES = {
    # Anything desaturated, plus the whole cold half of the wheel. There is no
    # teal, blue, cyan or purple anywhere in the palette, so there is nothing to
    # remap those onto and they become metal.
    "iron": {
        "material": "CastIron",
        "ceiling": 0.098,
        "knee": 0.40,
        "saturation": 0.07,
        "hue_pull": 0.9,
        "saturation_pull": 0.85,
    },
    # Reds and red-browns, which the palette does have: primer showing through.
    "oxide": {
        "material": "OxideRed",
        "ceiling": 0.105,
        "knee": 0.42,
        "saturation": 0.34,
        "hue_pull": 0.8,
        "saturation_pull": 0.6,
    },
    # Oranges, yellows and greens — the safety-yellow mass, 11% of the atlas,
    # and the single loudest thing in the frame before this existed.
    "olive": {
        "material": "OliveDrab",
        "ceiling": 0.105,
        "knee": 0.42,
        "saturation": 0.33,
        "hue_pull": 0.82,
        "saturation_pull": 0.7,
    },
}

# Which family a hue falls in, as (start, end] arcs in degrees. Everything not
# named here, and everything below `CHROMA_FLOOR`, is iron.
HUE_ARCS = [
    (338.0, 22.0, "oxide"),
    (22.0, 165.0, "olive"),
]

# Below this saturation a texel has no hue worth remapping and is simply metal.
CHROMA_FLOOR = 0.16

# The one hue every emissive texel is forced to, and how much colour it keeps.
# A tungsten filament at the far end of a smoggy afternoon, not a process light.
TUNGSTEN_HUE = 36.0
TUNGSTEN_SATURATION = 0.46
EMISSION_CEILING = 0.82

# How far the baked occlusion in COLOR_0 is pushed, and what its dark end is
# tinted toward. The pack ships 0.50..1.00, which is a hint of contact; soot in
# a crease is darker and browner than the surface it sits in.
GRIME_GAMMA = 2.1
GRIME_FLOOR = 0.30
GRIME_SOOT = (0.62, 0.58, 0.52)


def load_palette(path: pathlib.Path) -> dict[str, dict]:
    """`dieselpunk_palette.json` by material name."""
    document = json.loads(path.read_text())
    return {entry["name"]: entry for entry in document["materials"]}


def _srgb_to_linear(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(value: float) -> float:
    if value <= 0.0031308:
        return value * 12.92
    return 1.055 * (value ** (1.0 / 2.4)) - 0.055


SRGB_TO_LINEAR = [_srgb_to_linear(i / 255.0) for i in range(256)]

LUMA = (0.2126, 0.7152, 0.0722)


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


def _blend_hue(source: float, target: float, amount: float) -> float:
    """Interpolate around the wheel the short way, in degrees."""
    difference = ((target - source + 180.0) % 360.0) - 180.0
    return (source + difference * amount) % 360.0


def _targets(palette: dict[str, dict]) -> dict[str, dict]:
    """Each family's spec with the palette's own hue filled in."""
    resolved = {}
    for name, spec in FAMILIES.items():
        colour = palette[spec["material"]]["base_color"]
        hue, _, _ = colorsys.rgb_to_hsv(colour[0], colour[1], colour[2])
        resolved[name] = dict(spec, hue=hue * 360.0)
    return resolved


def grade_colour(rgb: tuple[int, int, int], targets: dict[str, dict]) -> tuple[int, int, int]:
    """One 8-bit sRGB colour, remapped onto the palette. The whole artistic rule.

    Hue and saturation move toward the family's palette material; luminance goes
    through that family's shoulder. The hue and saturation are decided in sRGB,
    where they match what a human called the colour, and the luminance is scaled
    in linear light, where a ratio means what a renderer will do with it.
    """
    red, green, blue = (channel / 255.0 for channel in rgb)
    hue, saturation, value = colorsys.rgb_to_hsv(red, green, blue)
    spec = targets[_family_of(hue * 360.0, saturation)]

    graded_hue = _blend_hue(hue * 360.0, spec["hue"], spec["hue_pull"]) / 360.0
    graded_saturation = saturation + (spec["saturation"] - saturation) * spec["saturation_pull"]
    toned = colorsys.hsv_to_rgb(graded_hue, graded_saturation, value)

    linear = [SRGB_TO_LINEAR[int(round(channel * 255.0))] for channel in toned]
    luminance = sum(channel * weight for channel, weight in zip(linear, LUMA))
    if luminance <= 0.0:
        return (0, 0, 0)
    wanted = spec["ceiling"] * luminance / (luminance + spec["knee"])
    scale = wanted / luminance
    out = [min(1.0, channel * scale) for channel in linear]
    return tuple(int(round(min(1.0, max(0.0, _linear_to_srgb(channel))) * 255.0)) for channel in out)


def grade_emission_colour(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    """One texel of the glow atlas: its own brightness, tungsten's colour.

    The map is almost all black and the black must stay exactly black — the
    shared material multiplies by it, so a texel that is not zero is a lamp.
    """
    red, green, blue = (channel / 255.0 for channel in rgb)
    _, _, value = colorsys.rgb_to_hsv(red, green, blue)
    if value <= 0.0:
        return (0, 0, 0)
    lit = colorsys.hsv_to_rgb(
        TUNGSTEN_HUE / 360.0, TUNGSTEN_SATURATION, min(1.0, value * EMISSION_CEILING)
    )
    return tuple(int(round(channel * 255.0)) for channel in lit)


def grade_image(pixels: bytes, channels: int, grade) -> bytes:
    """Apply `grade` to every pixel, once per *distinct* colour.

    The atlas is four million texels and about twenty thousand colours, so the
    expensive part runs twenty thousand times and the cheap part is a dictionary
    lookup. Alpha, where there is one, is carried through untouched.
    """
    out = bytearray(pixels)
    table: dict[bytes, bytes] = {}
    for offset in range(0, len(pixels), channels):
        key = pixels[offset : offset + 3]
        replacement = table.get(key)
        if replacement is None:
            replacement = bytes(grade((key[0], key[1], key[2])))
            table[key] = replacement
        out[offset : offset + 3] = replacement
    return bytes(out)


# ── A PNG, in the standard library ───────────────────────────────────────────
#
# Pillow is not a dependency of this directory and `tools/assets/run_tests.sh`
# is a CI command, so the two atlases are decoded and re-encoded here. Only what
# these files actually are is supported — eight bits a channel, RGB or RGBA, no
# interlace — and anything else raises rather than being quietly mangled.


def read_png(data: bytes) -> tuple[int, int, int, bytes]:
    """(width, height, channels, unfiltered pixel rows)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    offset = 8
    header = None
    compressed = bytearray()
    while offset + 8 <= len(data):
        (length,) = struct.unpack_from(">I", data, offset)
        kind = data[offset + 4 : offset + 8]
        body = data[offset + 8 : offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed += body
        elif kind == b"IEND":
            break
        offset += 12 + length
    if header is None:
        raise ValueError("PNG carries no IHDR")
    width, height, depth, colour_type, compression, filter_method, interlace = header
    if depth != 8 or compression != 0 or filter_method != 0 or interlace != 0:
        raise ValueError(f"unsupported PNG: depth {depth}, interlace {interlace}")
    if colour_type not in (2, 6):
        raise ValueError(
            f"unsupported PNG colour type {colour_type}; the prop atlases are RGB or RGBA"
        )
    channels = 3 if colour_type == 2 else 4
    rows = _unfilter(zlib.decompress(bytes(compressed)), width, height, channels)
    return width, height, channels, rows


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytes:
    stride = width * channels
    out = bytearray(stride * height)
    previous = bytearray(stride)
    position = 0
    for row in range(height):
        method = raw[position]
        position += 1
        line = bytearray(raw[position : position + stride])
        position += stride
        if method == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif method == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif method == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif method == 4:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                upper_left = previous[i - channels] if i >= channels else 0
                up = previous[i]
                estimate = left + up - upper_left
                distance_left = abs(estimate - left)
                distance_up = abs(estimate - up)
                distance_corner = abs(estimate - upper_left)
                if distance_left <= distance_up and distance_left <= distance_corner:
                    predictor = left
                elif distance_up <= distance_corner:
                    predictor = up
                else:
                    predictor = upper_left
                line[i] = (line[i] + predictor) & 0xFF
        elif method != 0:
            raise ValueError(f"unknown PNG filter {method}")
        out[row * stride : (row + 1) * stride] = line
        previous = line
    return bytes(out)


def write_png(width: int, height: int, channels: int, pixels: bytes) -> bytes:
    """Re-encode with no row filtering: zlib does the work and the code stays short."""
    stride = width * channels
    raw = bytearray()
    for row in range(height):
        raw.append(0)
        raw += pixels[row * stride : (row + 1) * stride]
    colour_type = 2 if channels == 3 else 6
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    for kind, body in (
        (b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0)),
        (b"IDAT", zlib.compress(bytes(raw), 9)),
        (b"IEND", b""),
    ):
        out += struct.pack(">I", len(body)) + kind + body
        out += struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    return bytes(out)


def grade_albedo(data: bytes, palette: dict[str, dict]) -> bytes:
    """A pack's albedo atlas, remapped onto the palette. PNG in, PNG out."""
    width, height, channels, pixels = read_png(data)
    targets = _targets(palette)
    graded = grade_image(pixels, channels, lambda rgb: grade_colour(rgb, targets))
    return write_png(width, height, channels, graded)


def grade_emission(data: bytes) -> bytes:
    """A pack's glow atlas, forced to tungsten. PNG in, PNG out."""
    width, height, channels, pixels = read_png(data)
    graded = grade_image(pixels, channels, grade_emission_colour)
    return write_png(width, height, channels, graded)


# ── Grime, which lives in the vertex colours ─────────────────────────────────

COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
COMPONENT_FORMAT = {5121: ("B", 1, 255.0), 5123: ("H", 2, 65535.0), 5126: ("f", 4, 1.0)}


def deepen_grime(document: dict, binary: bytearray) -> int:
    """Push every `COLOR_0` toward soot, in place. Returns how many it touched.

    heyheythere bakes ambient occlusion into vertex colours and the shared
    material multiplies them into the albedo, which means the one piece of
    per-prop geometric information about where dirt would collect is already in
    the file — just far too polite about it. Raising it to `GRIME_GAMMA` and
    tinting the dark end toward `GRIME_SOOT` is the whole of it: a crease goes
    dark and slightly brown, a flat panel is left alone, and nothing has to be
    decided about any particular prop.
    """
    touched = 0
    for accessor_index in _colour_accessors(document):
        accessor = document["accessors"][accessor_index]
        count = accessor["count"]
        components = COMPONENT_COUNT[accessor["type"]]
        if components < 3:
            continue
        format_code, size, maximum = COMPONENT_FORMAT[accessor["componentType"]]
        view = document["bufferViews"][accessor["bufferView"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride") or components * size
        for index in range(count):
            offset = start + index * stride
            values = list(struct.unpack_from("<" + format_code * components, binary, offset))
            scaled = [value / maximum for value in values[:3]]
            dirty = []
            for channel, soot in zip(scaled, GRIME_SOOT):
                # Deepen the occlusion, then warm its dark end toward soot, then
                # lift off zero: a crease is filthy, not a hole in the mesh.
                occluded = max(0.0, min(1.0, channel)) ** GRIME_GAMMA
                sooty = occluded * (soot + (1.0 - soot) * occluded)
                dirty.append(GRIME_FLOOR + (1.0 - GRIME_FLOOR) * sooty)
            for channel in range(3):
                values[channel] = (
                    dirty[channel]
                    if maximum == 1.0
                    else int(round(max(0.0, min(1.0, dirty[channel])) * maximum))
                )
            struct.pack_into("<" + format_code * components, binary, offset, *values)
        touched += 1
    return touched


def _colour_accessors(document: dict) -> list[int]:
    seen: list[int] = []
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            index = primitive.get("attributes", {}).get("COLOR_0")
            if index is not None and index not in seen:
                seen.append(index)
    return seen
