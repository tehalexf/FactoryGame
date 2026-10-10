#!/usr/bin/env python3
"""The arithmetic and the declaration behind a textured first-person viewmodel.

Used by ``fbx_to_viewmodel.py``; split out for ``prop_grade.py``'s reason — it is
the half that has a contract of its own, and ``tools/assets/tests/
test_viewmodel_surface.py`` can test all of it on invented pixels with **no
licensed byte anywhere near it**.

── What was actually wrong, measured rather than assumed ────────────────────

``convert_weapons.sh`` has said since #28 that "the packs reference textures they
do not ship, so every surface arrives white", and repainted each material a flat
palette colour. That sentence is half right, and the half that is wrong is the
half that matters: **the `Weapon pack` ships a complete PBR set for both rifles**
— albedo, normal, roughness, metallic and occlusion, for the L96's body, its
scope and its lens, and for the AKM — and two separate things kept them off the
model.

1. **The names do not match.** The FBX carries the authoring machine's paths, and
   the basenames at the end of them are not the basenames in the zip:
   ``T_S96_ALB.tga.png`` against the shipped ``L96_ALB.png``,
   ``T_Scope_8X_NRM.tga.png`` against ``Scope_NRM.png``,
   ``04_-_Default_Mixed_AO.tga.png`` against ``AO.png``. ``--texture-dir``
   matches by basename, so it recovered nothing, and the S96/L96 pair cannot be
   bridged by any normalisation rule — it is a vendor typo.
2. **And nothing was ever wired, so recovering the files would not have been
   enough.** These were authored as 3ds Max ShaderFX materials, and Blender's
   importer says so on the way in — ``material link
   b'3dsMax|HwShaderParams|TEX_color_map' ignored``, once per map per material.
   What it builds instead is a bare Principled BSDF with **nothing connected to
   Base Color** and the images left floating as unreferenced datablocks. So even
   with every file found, every surface would still have rendered as its default
   grey.

Which is why the recipe binds a file to a channel **explicitly, by path**. There
is no name to guess at, the mapping is written where the rest of the recipe is,
and a file that is not there is an error naming the material, the channel and the
path rather than a weapon that quietly goes flat again — #57 and #59's rule, and
the thing a flat repaint was hiding for five tickets.

── And the surfaces that genuinely have nothing to recover ──────────────────

Two of them, and the distinction is worth keeping because only one of the two
sentences this module replaces was ever true:

* **The arms.** All three arm meshes in both rifle FBXs reference
  ``fpArms_Military_D.tga``, ``fpArms_AO.tga`` and ``fpArms_NRM.tga`` from a
  ``FPS Generic Arms/`` folder, and **that folder is in neither pack**. Checked
  by name across the whole quarantine: there is not one ``fpArms_*`` file and not
  one ``.tga`` anywhere in it. The pack *does* ship ``FPS Arms/Textures/`` — but
  those belong to a different asset, a separate 346-vertex ``FPS_Arms.fbx`` with
  its own unwrap, and putting its map on the 1422-vertex sleeve would be reading
  a texture through unrelated UVs.
* **The RgsDev rig.** It ships no maps at all, and that is the asset being what
  it is rather than an omission: a low-poly kit whose Unity materials are flat
  colours. Its UVs say so too — the knife's are degenerate, 8280x between the
  tightest and the loosest triangle's metres-per-UV-unit, because they were never
  meant to carry a texture.

So those wear the palette's **own generated maps**, the same ones every Machine
wears, through ``palette_surface`` below. That is the literal version of the
sentence the flat repaint was reaching for — *the thing in the player's hands
belongs to the same world as the thing they built it with* — and it costs no new
art, because ``assets/generated/textures/`` is committed (#59) and so a clone
with no packs sees exactly what the author sees.

The UVs it needs are ``machine_parts.box_project_uvs``', which is the same answer
#64 gave the Build Gun: box-project at world scale, one UV unit to the metre, and
a material's ``texture_scale_m`` is then the only thing that sets density. That
replaces the degenerate unwrap rather than unpicking it — **it adds a UV layer
and does not move one vertex**, which is the line this project draws about an
artist's mesh (``WorldView._skinned_mesh``'s note on the Enemy glow).
"""

from __future__ import annotations

import sys
import math
from array import array
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import machine_materials  # noqa: E402

#: The channels a recipe may bind a file to. `ao` is folded into the albedo by
#: `multiply_occlusion` rather than carried, and `metallic`/`roughness` are
#: combined into glTF's one texture by `combine_metallic_roughness`.
CHANNELS = ("albedo", "normal", "roughness", "metallic", "ao")


#: Deliberately **no numpy**, and that is a decision about the suite rather than
#: about the arithmetic. `tools/assets/run_tests.sh` has never needed a
#: third-party package — `gltf_info` says "standard library only" in its first
#: line — and CI installs Godot, Blender and ffmpeg and nothing from pip. A
#: module that imported numpy would make this the first asset test that could
#: fail to *import* on a runner, which is the "green on the branch, red on the
#: merged tip" failure this project has already paid for twice. `array('f')` is
#: four bytes a channel and fast enough: the whole conversion is a developer
#: action that already takes minutes.


def _as_floats(pixels) -> array:
    """A flat RGBA run as an `array('f')`. Blender's `image.pixels` layout."""
    flat = pixels if isinstance(pixels, array) else array("f", pixels)
    if len(flat) % 4:
        raise ValueError(f"{len(flat)} channels is not a whole number of RGBA texels")
    return flat


# ── Encoding, and the mistake it is here to stop being made again ───────────
#
# **`image.pixels` hands back the file's own values, not linear ones.** Measured
# rather than assumed: reading `olive_drab_paint.png` with its colour space set
# to `sRGB` and again set to `Non-Color` gives *byte-identical* arrays, both at a
# mean of 0.4868 — which is 124/255, the file's own sRGB bytes. Blender applies
# the transfer function when the *shader samples* the texture, not when Python
# reads it.
#
# So anything that multiplies a colour map has to linearise first. Doing it in
# the file's own encoding instead multiplies an encoded value by a linear factor,
# and the shader's decode then squares it: the tint went on at 0.46 and came out
# at about 0.46², which is `olive_drab_paint` embedded at a mean of 57 sRGB where
# the palette asks for 86. That is a real defect this module shipped for one
# render, and it was found by reading the texels out of the `.glb` rather than by
# looking at the picture.
#
# A *mask* read as `Non-Color` — occlusion, roughness, metallic, a normal — is
# already linear and must not be transformed. Only colour is.


def _to_linear(encoded: float) -> float:
    return encoded / 12.92 if encoded <= 0.04045 else ((encoded + 0.055) / 1.055) ** 2.4


def _to_srgb(linear: float) -> float:
    if linear <= 0.0031308:
        return linear * 12.92
    return 1.055 * max(linear, 0.0) ** (1.0 / 2.4) - 0.055


def combine_metallic_roughness(roughness, metallic):
    """Pack a separate roughness and metallic map into glTF's one texture.

    glTF has no metallic texture and no roughness texture: it has
    ``metallicRoughnessTexture``, whose **green** channel is roughness and whose
    **blue** channel is metallic. These packs ship the two as separate greyscale
    PNGs, so they are combined here rather than by a node graph the exporter has
    to pattern-match.

    Red is left at 1.0 because that is where glTF's occlusion lives and the
    occlusion is folded into the albedo instead; a value there would darken the
    surface twice. The red channel of each source is what is believed, because
    these are RGB files with one value repeated and red is what a single-channel
    export would have written.

    Either may be ``None``: the L96's lens ships a roughness map and no metallic
    one, which is glass being a dielectric rather than the pack being incomplete.
    """
    if roughness is None and metallic is None:
        return None
    rough = _as_floats(roughness) if roughness is not None else None
    metal = _as_floats(metallic) if metallic is not None else None
    if rough is not None and metal is not None and len(rough) != len(metal):
        raise ValueError(
            f"a roughness map of {len(rough)} channels cannot be combined with a "
            f"metallic map of {len(metal)}; they are different sizes")
    count = len(rough) if rough is not None else len(metal)
    combined = array("f", bytes(4 * count))
    for base in range(0, count, 4):
        combined[base] = 1.0
        combined[base + 1] = rough[base] if rough is not None else 0.0
        combined[base + 2] = metal[base] if metal is not None else 0.0
        combined[base + 3] = 1.0
    return combined


def multiply_occlusion(albedo, occlusion):
    """Fold a baked occlusion map into the albedo it belongs to.

    ``prop_grade.py`` does the same thing for the same reason — it "deepens the
    pack's baked occlusion into grime" at conversion time — and the runtime cost
    is therefore zero. The alternative is glTF's ``occlusionTexture``, which
    Blender's exporter writes only through a node group the glTF addon supplies,
    and which would make this recipe depend on an addon's internal naming for the
    least consequential of the five maps on an object held 40 cm from one camera.

    Alpha is left alone: the lens carries one, and shading glass by an occlusion
    value would make it partly disappear where its mount darkens it.

    The albedo arrives **sRGB-encoded** — see the note above — so it is
    linearised, shaded and encoded again. The occlusion map is read as
    `Non-Color` and is already linear.
    """
    if occlusion is None:
        return albedo
    base = _as_floats(albedo)
    shade = _as_floats(occlusion)
    if len(base) != len(shade):
        raise ValueError(
            f"an albedo of {len(base)} channels cannot take an occlusion map of "
            f"{len(shade)}; they are different sizes")
    folded = array("f", base)
    for texel in range(0, len(base), 4):
        mask = shade[texel]
        for channel in range(3):
            folded[texel + channel] = _to_srgb(
                _to_linear(base[texel + channel]) * mask)
    return folded


def flip_normal_green(normal):
    """Turn a DirectX-convention normal map the way glTF reads one.

    DirectX takes +green as pointing *down* the surface where glTF and OpenGL
    take it as up, so a map authored in that convention lights every slope on the
    weapon from the opposite side. It does not read as an upside-down texture; it
    reads as the sun being somewhere else, which is why it is worth correcting by
    declaration rather than hoping somebody notices it in a render.

    The AKM's map says which convention it is in, in its own file name
    (``04_-_Default_Normal_DirectX.tga.png``), so the recipe states it. The L96's
    is plain ``L96_NRM.png`` and is left alone.
    """
    texels = _as_floats(normal)
    flipped = array("f", texels)
    for green in range(1, len(flipped), 4):
        flipped[green] = 1.0 - flipped[green]
    return flipped


def level_albedo(albedo, base_colour):
    """Scale a map so its mean linear value is the palette's ``base_color``.

    **The texture carries the variation and ``base_color`` carries the level**,
    and that split came out of a render rather than out of taste.

    ``texture_tint`` is the palette's knob for a *Machine*: the generated set was
    made to be lit as photographs, and the tint brings it back to interwar values
    for a thing read from metres away through SSAO and depth fog. A viewmodel is
    40 cm from the eye at near-normal incidence to the sun, and at the tint the
    Pneumatic Wrench's gloves measured **129 against a ground of 81** — half
    again as bright as the world behind them, where the flat colour they replaced
    measured 86. That is #42's Wall, #52's ore and #64's brightened tool: *a
    colour picked against the wrong background*, for the fourth time in this
    project.

    #64 settled which number is right for a thing in the hand — the Build Gun
    wears the palette's flat ``base_color`` and reads correctly, as the Wall
    does — so this puts the surface back at exactly that level and keeps every
    bit of the grain. Per channel, so the map's mean hue becomes the palette's
    rather than the generator's.

    A channel whose mean is zero is left alone: there is nothing to scale, and
    the alternative is a division by zero on a map that is already black.
    """
    texels = _as_floats(albedo)
    count = len(texels) // 4
    if count == 0:
        return texels
    means = [0.0, 0.0, 0.0]
    for texel in range(0, len(texels), 4):
        for channel in range(3):
            means[channel] += _to_linear(texels[texel + channel])
    scales = [
        (base_colour[channel] / (means[channel] / count)) if means[channel] > 0.0
        else 1.0
        for channel in range(3)
    ]
    levelled = array("f", texels)
    for texel in range(0, len(texels), 4):
        for channel in range(3):
            value = _to_linear(texels[texel + channel]) * scales[channel]
            levelled[texel + channel] = _to_srgb(min(max(value, 0.0), 1.0))
    return levelled


def normal_from_albedo(albedo, width: int, height: int, degrees: float):
    """Derive a tangent-space normal map from a map's own luminance.

    The generated set is **albedo only** — one PNG a surface — so a material
    dressed in it has a picture of relief on a surface that has none. That is
    #42's finding on the ground, in as many words: *however worn the picture was,
    the surface was geometrically a sheet of glass, so a 23-degree sun fell on
    every square metre identically.* Its fix was to **derive** the relief rather
    than load it, and this is the same move with the height field already in
    hand, because on rust, weave and tread plate the luminance *is* where the
    relief is.

    **The knob is the slope itself, in degrees, and that is #42's lesson built
    into the interface rather than written beside it.** A plain multiplier means
    something different on every map: measured across the palette's own four, the
    same number gives ``riveted_steel_plate`` five times the slope it gives
    ``olive_drab_paint``, because one is rivets and the other is smooth paint. So
    a multiplier would have needed a value per surface, each found by looking,
    and the first one tried here produced **0.66 degrees on the arms** — the same
    invisible one-degree tilt #42 got from its own physically reasoned guess.
    Asking for a mean slope instead is one number for every surface and it is the
    quantity that is actually visible.

    Solved by bisection on the multiplier, which is exact rather than a
    small-angle approximation and costs a few passes over an array that is at
    most a quarter of a million texels.

    Central differences rather than a Sobel, so one texel of grain survives: a
    3x3 kernel averages away exactly the detail this exists to keep. **0 turns
    it off**, which is the rule every camera number in ``[player]`` obeys.
    """
    texels = _as_floats(albedo)
    count = len(texels) // 4
    if count != width * height:
        raise ValueError(f"{count} texels is not {width}x{height} = {width * height}")
    normal = array("f", bytes(4 * len(texels)))
    for texel in range(0, len(texels), 4):
        normal[texel] = 0.5
        normal[texel + 1] = 0.5
        normal[texel + 2] = 1.0
        normal[texel + 3] = 1.0
    if degrees <= 0.0:
        return normal

    # Rec. 709 luminance, as the height field.
    field = array("f", bytes(4 * count))
    for index in range(count):
        base = index * 4
        field[index] = (0.2126 * texels[base]
                        + 0.7152 * texels[base + 1]
                        + 0.0722 * texels[base + 2])

    # Wrapped, because these maps tile: a gradient taken with a clamped edge puts
    # a seam down the join that the whole world-space projection exists to avoid.
    slope_u = array("f", bytes(4 * count))
    slope_v = array("f", bytes(4 * count))
    for row in range(height):
        here = row * width
        up = ((row + 1) % height) * width
        down = ((row - 1) % height) * width
        for column in range(width):
            index = here + column
            slope_u[index] = (field[here + (column + 1) % width]
                              - field[here + (column - 1) % width]) * 0.5
            slope_v[index] = (field[up + column] - field[down + column]) * 0.5

    magnitude = [ (slope_u[i] * slope_u[i] + slope_v[i] * slope_v[i]) ** 0.5
                  for i in range(count) ]
    if not any(magnitude):
        return normal

    wanted = math.radians(degrees)

    def mean_slope(scale: float) -> float:
        return sum(math.atan(m * scale) for m in magnitude) / count

    low, high = 0.0, 1.0
    while mean_slope(high) < wanted and high < 1e9:
        high *= 4.0
    for _ in range(40):
        middle = (low + high) * 0.5
        if mean_slope(middle) < wanted:
            low = middle
        else:
            high = middle
    scale = (low + high) * 0.5

    for index in range(count):
        x = -slope_u[index] * scale
        y = -slope_v[index] * scale
        length = (x * x + y * y + 1.0) ** 0.5
        base = index * 4
        normal[base] = x / length * 0.5 + 0.5
        normal[base + 1] = y / length * 0.5 + 0.5
        normal[base + 2] = 1.0 / length * 0.5 + 0.5
    return normal


def palette_surface(name: str) -> dict:
    """One ``dieselpunk_palette.json`` entry, as the surface a viewmodel wears.

    Resolved through ``machine_materials``' own readers rather than by parsing
    the palette again, so there is exactly one authority on what ``OliveDrab``
    is and the arms cannot come to disagree with a Machine about it.

    **`texture_tint` is deliberately not among them**, which is the one surprise
    here: it is the palette's knob for a *Machine* and `level_albedo` explains
    why it is the wrong number at arm's length. Carrying it anyway would be a
    field nothing reads, which is the treatment this project already refuses a
    tuning key that nothing reads.

    An entry the palette does not declare is a ``KeyError`` naming it, and so is
    an entry that wears **no** texture. The second one matters as much as the
    first: a few entries are colour-only on purpose — a gauge bezel is 11 cm
    across — and dressing an arm in one would be the flat repaint this flag
    exists to replace, wearing its name.
    """
    for entry in machine_materials.load():
        if entry["name"] != name:
            continue
        texture = machine_materials.texture_path(entry)
        if texture is None:
            raise KeyError(
                f"{name!r} is a colour-only palette entry and wears no texture, so "
                f"it cannot dress a viewmodel surface; textured entries are "
                f"{', '.join(textured_surface_names())}")
        return {
            "name": name,
            "texture": texture,
            "texture_scale_m": float(entry["texture_scale_m"]),
            "metallic": float(entry["metallic"]),
            "roughness": float(entry["roughness"]),
            "base_color": tuple(entry["base_color"]),
        }
    raise KeyError(
        f"{name!r} is not a material in dieselpunk_palette.json; it declares "
        f"{', '.join(e['name'] for e in machine_materials.load())}")


def textured_surface_names() -> list[str]:
    """Palette entries that wear a texture, so could dress a viewmodel."""
    return [e["name"] for e in machine_materials.load() if e.get("texture")]
