"""The icon claim: every Item icon comes out the same size, framed the same.

Seam under test: the public `aigen.framing` interface. Expected geometry is
worked out from the arguments by hand below, not read back off the code.
"""

import numpy as np
import pytest
from PIL import Image

from aigen import framing


def _blob_on_transparent(canvas=100, box=(30, 40, 70, 60)):
    """An opaque rectangle (40 wide, 20 tall) adrift on a transparent canvas."""
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    img.paste((200, 90, 20, 255), box)
    return img


def _blob_on_flat_grey(canvas=100, box=(30, 40, 70, 60), bg=(128, 128, 128)):
    img = Image.new("RGB", (canvas, canvas), bg)
    img.paste((200, 90, 20), box)
    return img


def _alpha_bbox(img):
    return Image.fromarray(np.asarray(img)[:, :, 3]).getbbox()


def test_framed_icon_is_exactly_the_requested_canvas_size():
    out = framing.frame_to_canvas(_blob_on_transparent(), canvas_px=256)
    assert out.size == (256, 256)
    assert out.mode == "RGBA"


def test_framed_icon_fills_the_canvas_minus_its_margin():
    # canvas 256, margin 0.1 -> 26 px each side, so content box is 204 px.
    out = framing.frame_to_canvas(
        _blob_on_transparent(), canvas_px=256, margin_frac=0.1
    )
    left, top, right, bottom = _alpha_bbox(out)
    # Source blob is 40x20, so the long side is the one pinned to 204,
    # and the short side follows at half that, aspect ratio preserved.
    assert right - left == 204
    assert bottom - top == pytest.approx(102, abs=1)


def test_framed_icon_is_centred_on_the_canvas():
    out = framing.frame_to_canvas(
        _blob_on_transparent(), canvas_px=256, margin_frac=0.1
    )
    left, top, right, bottom = _alpha_bbox(out)
    assert (left + right) / 2 == pytest.approx(128, abs=1)
    assert (top + bottom) / 2 == pytest.approx(128, abs=1)


def test_icons_from_differently_placed_sources_frame_identically():
    """Two Items drawn at different scales and offsets must still match."""
    a = framing.frame_to_canvas(
        _blob_on_transparent(box=(10, 10, 50, 30)), canvas_px=128
    )
    b = framing.frame_to_canvas(
        _blob_on_transparent(box=(55, 70, 95, 90)), canvas_px=128
    )
    assert a.size == b.size
    assert _alpha_bbox(a) == _alpha_bbox(b)


def test_a_flat_studio_background_becomes_transparent():
    cut = framing.alpha_from_flat_background(_blob_on_flat_grey())
    alpha = np.asarray(cut)[:, :, 3]
    assert alpha[0, 0] == 0, "the backdrop should be keyed out"
    assert alpha[50, 50] == 255, "the subject should stay opaque"
    assert _alpha_bbox(cut) == (30, 40, 70, 60)


def _blob_on_graded_backdrop(canvas=100, box=(30, 40, 70, 60)):
    """What the model actually paints: a studio sweep, not a flat colour.

    A vertical ramp from 90 to 190 grey. No two opposite corners are within
    any sane colour-distance of each other, so a fixed threshold against a
    single backdrop colour cannot key this.
    """
    ramp = np.linspace(90, 190, canvas, dtype=np.uint8)
    rgb = np.repeat(np.repeat(ramp[:, None], canvas, axis=1)[:, :, None], 3, axis=2)
    img = Image.fromarray(rgb, mode="RGB")
    img.paste((200, 90, 20), box)
    return img


def test_a_graded_studio_backdrop_is_still_keyed_out():
    """The real failure mode: SDXL never paints a genuinely flat background."""
    cut = framing.alpha_from_flat_background(_blob_on_graded_backdrop())
    alpha = np.asarray(cut)[:, :, 3]
    assert alpha[0, 0] == 0, "the light end of the sweep must be keyed out"
    assert alpha[99, 99] == 0, "and so must the dark end"
    assert _alpha_bbox(cut) == (30, 40, 70, 60), "only the subject may survive"


def test_a_soft_cast_shadow_is_keyed_out_with_the_backdrop():
    """A shadow left attached drags the subject's bounding box off-centre."""
    canvas = 100
    # A smooth elliptical pool of darkness below the subject, 56 levels deep at
    # its centre and fading over ~12 px -- about 4 levels per pixel, the way a
    # real soft shadow falls off.
    ys, xs = np.mgrid[0:canvas, 0:canvas]
    distance = np.sqrt(((ys - 58) / 1.0) ** 2 + ((xs - 50) / 1.6) ** 2)
    darkening = 36.0 * np.exp(-((distance / 12.0) ** 2))
    plate = np.full((canvas, canvas, 3), 128.0) - darkening[:, :, None]
    img = Image.fromarray(plate.clip(0, 255).astype(np.uint8), mode="RGB")
    img.paste((200, 90, 20), (30, 30, 70, 50))
    cut = framing.alpha_from_flat_background(img)
    left, top, right, bottom = _alpha_bbox(cut)
    assert (left, top, right, bottom) == (30, 30, 70, 50), "shadow must not survive"


def test_a_dark_subject_with_soft_edges_is_not_hollowed_out():
    """The other side of the shadow trade-off, and the costlier failure.

    Most Items are dark grey steel with anti-aliased edges. A fill that walks
    into darkness by small steps will stroll across that soft edge and eat the
    subject from the inside, leaving a hollow outline. Shadow removal must
    never be bought at this price: a surviving shadow nudges a bounding box,
    a hollowed subject is an unusable icon.
    """
    canvas = 100
    plate = np.full((canvas, canvas, 3), 128.0)
    ys, xs = np.mgrid[0:canvas, 0:canvas]
    # A dark grey disc with a 4px soft edge -- about 22 levels per pixel, well
    # under any threshold that would also catch a real shadow's falloff.
    radius = np.sqrt((ys - 50.0) ** 2 + (xs - 50.0) ** 2)
    ramp = np.clip((radius - 26.0) / 4.0, 0.0, 1.0)
    plate = 40.0 + (128.0 - 40.0) * ramp
    img = Image.fromarray(
        np.repeat(plate[:, :, None], 3, axis=2).astype(np.uint8), mode="RGB"
    )
    alpha = np.asarray(framing.alpha_from_flat_background(img))[:, :, 3]
    assert alpha[50, 50] == 255, "the subject's dark centre must survive"
    assert alpha[40, 50] == 255, "and so must the rest of its body"
    assert alpha[0, 0] == 0, "while the backdrop is still removed"


def test_keying_does_not_punch_holes_in_a_subject_matching_the_backdrop():
    """A grey rivet inside the subject is interior, not background."""
    img = _blob_on_flat_grey(box=(20, 20, 80, 80))
    img.paste((128, 128, 128), (45, 45, 55, 55))  # same colour as the backdrop
    alpha = np.asarray(framing.alpha_from_flat_background(img))[:, :, 3]
    assert alpha[50, 50] == 255, "an enclosed region must not be keyed out"
    assert alpha[0, 0] == 0
