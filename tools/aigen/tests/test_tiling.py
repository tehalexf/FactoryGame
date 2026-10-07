"""The tiling claim: a texture marked `seamless` really does wrap.

Seam under test: the public `aigen.tiling` interface. Reference values come
from images whose wrap behaviour is known analytically, not from the
implementation.
"""

import numpy as np
import pytest

from aigen import tiling


def _sine(width=256, periods=4):
    """Seamless by construction: an exact whole number of periods wraps."""
    x = np.arange(width)
    row = 127.5 + 127.5 * np.sin(2 * np.pi * periods * x / width)
    return np.repeat(row[None, :, None], width, axis=0).repeat(3, axis=2)


def _ramp(width=256):
    """Maximally non-seamless: a 0->255 gradient has a 255-wide wrap cliff."""
    x = np.linspace(0, 255, width)
    return np.repeat(x[None, :, None], width, axis=0).repeat(3, axis=2)


def test_seamless_image_has_wrap_gradient_in_line_with_its_interior():
    ratio = tiling.seam_ratio(_sine(), axis="x")
    assert ratio == pytest.approx(1.0, abs=0.2)


def test_gradient_image_wrap_cliff_is_far_worse_than_its_interior():
    # Interior step is 255/255 == 1 per column; the wrap step is 255.
    assert tiling.seam_ratio(_ramp(), axis="x") > 50


def test_seam_ratio_is_measured_per_axis():
    sine = _sine()  # varies along x, constant along y
    assert tiling.seam_ratio(sine, axis="y") == pytest.approx(1.0, abs=0.2)
    ramp_x = _ramp()
    assert tiling.seam_ratio(ramp_x, axis="y") == pytest.approx(1.0, abs=0.2)
    assert tiling.seam_ratio(ramp_x.transpose(1, 0, 2), axis="y") > 50


def test_is_seamless_accepts_a_wrapping_image_and_rejects_a_cliff():
    assert tiling.is_seamless(_sine()) is True
    assert tiling.is_seamless(_ramp()) is False


def test_check_tiling_reports_the_ratios_it_judged_on():
    report = tiling.check_tiling(_ramp())
    assert report.seamless is False
    assert report.x_ratio > 50
    assert report.y_ratio == pytest.approx(1.0, abs=0.2)
    assert report.tolerance > 1.0
