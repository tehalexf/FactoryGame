"""Turning a generated picture of an Item into a usable Item icon.

An icon set is judged as a set. If one Item's art fills its tile and the next
sits in the middle of a sea of empty pixels, the inventory looks broken even
though both images are individually fine. So the model is never trusted to
frame anything: it is asked for a subject on a flat backdrop, the backdrop is
keyed out, and the subject is then measured and placed to a fixed rule.

The rule: longest side of the subject is scaled to `canvas_px * (1 - 2 *
margin)`, and the subject is centred. Every icon therefore has the same
footprint on the same canvas regardless of what the model drew or where.
"""

from __future__ import annotations

from collections import deque

import numpy as np
from PIL import Image

#: Item icons ship at this size. Big enough to stay crisp on a hover panel,
#: small enough that a full Recipe book is cheap to keep in memory.
DEFAULT_CANVAS_PX = 256

#: Breathing room so adjacent icons in a grid do not touch.
DEFAULT_MARGIN_FRAC = 0.08

# All three tolerances below are in mean absolute levels per channel (0-255),
# so "20" means "twenty levels different", not a Euclidean colour distance
# that reads 1.73x larger on greys than the number suggests.

#: How far a pixel may sit from the *fitted* backdrop surface and still count
#: as backdrop. Not a distance from one flat colour -- see `_fit_backdrop`.
DEFAULT_KEY_TOLERANCE = 20.0

#: How far a pixel may sit from the fitted backdrop and still be eaten as a
#: cast shadow, provided it is reached by small steps from known backdrop. A
#: shadow is much darker than the backdrop but fades into it gradually, which
#: is exactly the distinction these two numbers encode.
SHADOW_TOLERANCE = 40.0

#: Largest single-pixel colour step the shadow walk may cross. The subject's
#: edge is a hard step and blocks the walk; a shadow's falloff is gentle and
#: does not. Keep this small -- it is the only thing standing between the
#: flood fill and the inside of a grey steel subject.
SHADOW_STEP_TOLERANCE = 6.0


def alpha_from_flat_background(
    image: Image.Image, tolerance: float = DEFAULT_KEY_TOLERANCE
) -> Image.Image:
    """Key out the studio backdrop, returning RGBA.

    Three ideas, each answering a way the two simpler approaches fail.

    1. **The backdrop is fitted, not assumed.** Ask a diffusion model for a
       flat grey background and it paints a studio sweep: the corners are
       nowhere near the same grey. Measuring every pixel against one backdrop
       colour therefore leaves slabs of unkeyed background behind. So a smooth
       quadratic surface is least-squares fitted to the border ring and each
       pixel is measured against *that*.

    2. **Only background connected to the border is removed.** A rivet hole or
       a dark recess inside the subject that happens to match the backdrop
       stays opaque, because the fill cannot reach it.

    3. **Shadows are eaten by a bounded walk.** A cast shadow is far darker
       than the backdrop, so step 1 keeps it, and a shadow left attached drags
       the subject's bounding box off-centre. But a shadow fades into the
       backdrop gradually, whereas the subject's edge is a hard step. So the
       fill is allowed to continue into darker pixels only while each single
       step stays small. Walking by *small steps alone* is not enough on its
       own -- soft anti-aliased edges let it stroll straight into a grey steel
       subject and hollow it out -- hence the `SHADOW_TOLERANCE` ceiling as
       well.
    """
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    height, width = rgb.shape[:2]

    deviation = np.abs(rgb - _fit_backdrop(rgb)).mean(axis=2)
    core = deviation <= tolerance
    walkable = deviation <= SHADOW_TOLERANCE

    background = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def seed(y: int, x: int) -> None:
        if core[y, x] and not background[y, x]:
            background[y, x] = True
            queue.append((y, x))

    for y in range(height):
        seed(y, 0)
        seed(y, width - 1)
    for x in range(width):
        seed(0, x)
        seed(height - 1, x)

    while queue:
        y, x = queue.popleft()
        here = rgb[y, x]
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if not (0 <= ny < height and 0 <= nx < width) or background[ny, nx]:
                continue
            if not walkable[ny, nx]:
                continue
            step = float(np.abs(rgb[ny, nx] - here).mean())
            if core[ny, nx] or step <= SHADOW_STEP_TOLERANCE:
                background[ny, nx] = True
                queue.append((ny, nx))

    out = np.dstack(
        [rgb.astype(np.uint8), np.where(background, 0, 255).astype(np.uint8)]
    )
    return Image.fromarray(out, mode="RGBA")


def _fit_backdrop(rgb: np.ndarray) -> np.ndarray:
    """Least-squares quadratic surface through the border ring, per channel.

    Quadratic rather than a plane because a studio sweep is curved; low order
    rather than high so the fit describes the backdrop and cannot bend itself
    around the subject.
    """
    height, width = rgb.shape[:2]
    ys, xs = np.mgrid[0:height, 0:width]
    yn = ys / max(height - 1, 1)
    xn = xs / max(width - 1, 1)
    basis = np.stack(
        [np.ones_like(xn), xn, yn, xn * xn, xn * yn, yn * yn], axis=-1
    )

    ring = max(1, min(height, width) // 32)
    mask = np.zeros((height, width), dtype=bool)
    mask[:ring, :] = mask[-ring:, :] = True
    mask[:, :ring] = mask[:, -ring:] = True

    design = basis[mask]
    fitted = np.empty_like(rgb)
    for channel in range(rgb.shape[2]):
        coefficients, *_ = np.linalg.lstsq(design, rgb[mask][:, channel], rcond=None)
        fitted[:, :, channel] = basis @ coefficients
    return fitted


def frame_to_canvas(
    image: Image.Image,
    canvas_px: int = DEFAULT_CANVAS_PX,
    margin_frac: float = DEFAULT_MARGIN_FRAC,
) -> Image.Image:
    """Scale and centre `image`'s opaque subject onto a fixed square canvas.

    `image` must already have an alpha channel marking the subject; run
    `alpha_from_flat_background` first if it does not.
    """
    if not 0 <= margin_frac < 0.5:
        raise ValueError(f"margin_frac must be in [0, 0.5), got {margin_frac}")

    rgba = image.convert("RGBA")
    bbox = rgba.split()[3].getbbox()
    if bbox is None:
        raise ValueError("image is fully transparent -- nothing to frame")

    subject = rgba.crop(bbox)
    content_px = canvas_px - 2 * round(canvas_px * margin_frac)
    scale = content_px / max(subject.size)
    scaled = subject.resize(
        (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
        Image.LANCZOS,
    )

    canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    canvas.alpha_composite(
        scaled,
        ((canvas_px - scaled.width) // 2, (canvas_px - scaled.height) // 2),
    )
    return canvas


def contact_sheet(
    images: list[Image.Image], cell_px: int = 64, columns: int = 8
) -> Image.Image:
    """Lay icons out at `cell_px` to check they read at small scale.

    The point of a set of icons is being distinguishable in an inventory grid.
    That is only answerable by looking at them all together, tiny.
    """
    if not images:
        raise ValueError("no images to lay out")
    columns = min(columns, len(images))
    rows = -(-len(images) // columns)
    sheet = Image.new("RGBA", (columns * cell_px, rows * cell_px), (24, 24, 22, 255))
    for index, image in enumerate(images):
        cell = image.convert("RGBA").resize((cell_px, cell_px), Image.LANCZOS)
        sheet.alpha_composite(
            cell, ((index % columns) * cell_px, (index // columns) * cell_px)
        )
    return sheet
