"""Seamless tiling: making it happen, and proving it did.

Two halves, and the second is the one that matters. Diffusion models do not
produce wrapping textures by default, and a texture that *almost* wraps shows
a visible grid line across a Factory floor. So the generator patches the
model's convolutions to wrap (`circular_padding`), and every texture is then
*measured* (`check_tiling`) rather than assumed.

The measurement idea: in a seamless image the pixel step across the wrap
boundary is statistically ordinary -- no different from any other adjacent
pair of columns. In a non-seamless image it is a cliff. So compare the wrap
step against the *upper tail* of the interior step distribution and take the
ratio. ~1.0 means seamless; a large number is a seam. The metric is
scale-free, so it works equally well on flat concrete and on busy riveted
plate.

The comparator is the 95th percentile rather than the mean on purpose. The
wrap step is a single sample, and in a smoothly varying image a single
ordinary step can sit well above the mean -- a pure sine wave's steepest step
is pi/2 times its mean step, which a mean comparator would flag as a seam
that is not there. Asking instead "is the wrap step within the range of
interior steps" is the question actually being posed.
"""

from __future__ import annotations

import contextlib
from dataclasses import dataclass

import numpy as np

#: A wrap step up to this many times the interior 95th-percentile step still
#: counts as seamless. Circular-padded output lands at roughly 1.0; a genuine
#: seam lands well above 2. 1.5 separates them with room to spare.
DEFAULT_TOLERANCE = 1.5

#: Which point of the interior step distribution the wrap step is compared to.
INTERIOR_PERCENTILE = 95.0


def _as_float_array(image) -> np.ndarray:
    """Accept a PIL image or anything array-like; return H x W x C floats."""
    arr = np.asarray(image, dtype=np.float64)
    if arr.ndim == 2:
        arr = arr[:, :, None]
    return arr[:, :, :3] if arr.shape[2] >= 3 else arr


def seam_ratio(image, axis: str = "x") -> float:
    """How much worse the wrap boundary is than a typical interior step.

    `axis="x"` measures the left/right wrap, `axis="y"` the top/bottom one.
    Returns ~1.0 for a seamless image and a large number for a visible seam.
    """
    if axis not in ("x", "y"):
        raise ValueError(f"axis must be 'x' or 'y', got {axis!r}")
    arr = _as_float_array(image)
    # Normalise so the wrapping axis is axis 0, then the maths is one shape.
    if axis == "x":
        arr = arr.transpose(1, 0, 2)
    if arr.shape[0] < 2:
        raise ValueError("need at least 2 pixels along the measured axis")

    # One scalar per adjacent-slice boundary, so the wrap step is compared
    # against like-for-like quantities rather than against raw pixel noise.
    steps = np.abs(np.diff(arr, axis=0)).mean(axis=tuple(range(1, arr.ndim)))
    interior = float(np.percentile(steps, INTERIOR_PERCENTILE))
    wrap = float(np.abs(arr[0] - arr[-1]).mean())

    if interior == 0.0:
        # A perfectly flat axis: seamless unless the wrap itself steps.
        return 1.0 if wrap == 0.0 else float("inf")
    return wrap / interior


@dataclass(frozen=True)
class TilingReport:
    """What was measured, so a failure says *how far off* and not just "no"."""

    x_ratio: float
    y_ratio: float
    tolerance: float

    @property
    def seamless(self) -> bool:
        return self.x_ratio <= self.tolerance and self.y_ratio <= self.tolerance

    def summary(self) -> str:
        verdict = "seamless" if self.seamless else "SEAM"
        return (
            f"{verdict}: x={self.x_ratio:.2f} y={self.y_ratio:.2f} "
            f"(tolerance {self.tolerance:.2f})"
        )


def check_tiling(image, tolerance: float = DEFAULT_TOLERANCE) -> TilingReport:
    """Measure both wrap boundaries and judge against `tolerance`."""
    return TilingReport(
        x_ratio=seam_ratio(image, "x"),
        y_ratio=seam_ratio(image, "y"),
        tolerance=tolerance,
    )


def is_seamless(image, tolerance: float = DEFAULT_TOLERANCE) -> bool:
    """True when both wrap boundaries are indistinguishable from the interior."""
    return check_tiling(image, tolerance).seamless


@contextlib.contextmanager
def circular_padding(*modules):
    """Make every Conv2d in `modules` wrap, for the duration of the block.

    This is what actually produces a tiling texture: a convolution that reads
    off the right edge gets pixels from the left edge instead of zeros, so the
    model never learns the image has a border. It must be applied to the UNet
    *and* the VAE decoder -- patching only one leaves a faint seam from the
    other. Restored on exit so an icon generated next is unaffected.
    """
    import torch

    saved: list[tuple[torch.nn.Conv2d, str]] = []
    try:
        for module in modules:
            if module is None:
                continue
            for layer in module.modules():
                if isinstance(layer, torch.nn.Conv2d):
                    saved.append((layer, layer.padding_mode))
                    layer.padding_mode = "circular"
        yield
    finally:
        for layer, mode in saved:
            layer.padding_mode = mode
