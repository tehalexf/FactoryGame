"""The claims made about the art actually in the repo, re-checked from disk.

The other test modules pin the logic using synthetic fixtures. This one points
the same logic at `assets/generated` and asserts the committed PNGs really are
seamless, really are one size, and really still match the recipes next to
them. No GPU and no model weights -- it reads the files.

If a recipe is edited without regenerating, or a PNG is touched up by hand,
these fail. That is the point: the repo should not be able to drift into a
state where the committed prompt no longer describes the committed image.
"""

from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from aigen import manifest as manifest_mod
from aigen import recipes, tiling

HERE = Path(__file__).resolve().parent.parent
ART = HERE.parent.parent / "assets" / "generated"
PROMPTS = HERE / "prompts"


def _records(kind):
    path = ART / f"{kind}s" / "manifest.json"
    if not path.exists():
        pytest.skip(f"no committed {kind}s yet")
    return manifest_mod.Manifest.load(path).records


def _jobs():
    jobs = {}
    for recipe in sorted(PROMPTS.glob("*.yaml")):
        for job in recipes.load_jobs(recipe):
            jobs[job.id] = job
    return jobs


def test_there_is_a_committed_sample_set_at_all():
    assert len(_records("texture")) >= 5, "the material palette needs breadth"
    assert len(_records("icon")) >= 5, "an icon set is judged as a set"


@pytest.mark.parametrize("kind", ["texture", "icon"])
def test_every_manifest_record_has_its_image_on_disk(kind):
    for record in _records(kind):
        assert (ART / record.path).exists(), f"{record.id}: {record.path} missing"


def test_every_committed_texture_actually_tiles():
    """The headline claim, re-measured from the PNG rather than trusted."""
    for record in _records("texture"):
        image = Image.open(ART / record.path)
        report = tiling.check_tiling(image)
        assert report.seamless, f"{record.id}: {report.summary()}"


def test_a_committed_texture_still_tiles_after_being_rolled():
    """A genuinely seamless texture is seamless from any starting offset.

    Rolling moves the wrap boundary into what used to be the middle of the
    image. If the original only *looked* seamless because its edges happened
    to be bland, the rolled version exposes it.
    """
    for record in _records("texture"):
        pixels = np.asarray(Image.open(ART / record.path).convert("RGB"))
        rolled = np.roll(pixels, (pixels.shape[0] // 2, pixels.shape[1] // 3), (0, 1))
        report = tiling.check_tiling(rolled)
        assert report.seamless, f"{record.id} rolled: {report.summary()}"


def test_the_tiling_metric_still_catches_a_deliberately_spliced_seam():
    """Guards against the measurement being vacuous.

    Half of one texture against half of another is a seam by construction. If
    this ever passes, the tolerance has been loosened until the check means
    nothing, and the test above is no longer evidence of anything.
    """
    records = _records("texture")
    left = np.asarray(Image.open(ART / records[0].path).convert("RGB"))
    right = np.asarray(Image.open(ART / records[1].path).convert("RGB"))
    width = min(left.shape[1], right.shape[1])
    spliced = np.concatenate(
        [left[:, : width // 2], right[:, : width // 2]], axis=1
    )
    assert not tiling.is_seamless(spliced), "a spliced seam must be detected"


def test_every_committed_icon_is_the_same_size():
    sizes = {tuple(record.image_size) for record in _records("icon")}
    assert len(sizes) == 1, f"icons must be one size, found {sorted(sizes)}"
    for record in _records("icon"):
        assert Image.open(ART / record.path).size == tuple(record.image_size)


def test_every_committed_icon_is_framed_to_the_same_rule():
    """Same canvas, same margin, subject centred and filling the content box."""
    for record in _records("icon"):
        image = Image.open(ART / record.path).convert("RGBA")
        canvas_px = record.settings["canvas_px"]
        margin = record.settings["margin_frac"]
        expected = canvas_px - 2 * round(canvas_px * margin)

        bbox = image.split()[3].getbbox()
        left, top, right, bottom = bbox
        longest = max(right - left, bottom - top)
        assert longest == expected, (
            f"{record.id}: subject's long side is {longest}, want {expected}"
        )
        assert abs((left + right) / 2 - canvas_px / 2) <= 1, f"{record.id} off-centre"
        assert abs((top + bottom) / 2 - canvas_px / 2) <= 1, f"{record.id} off-centre"


@pytest.mark.parametrize("kind", ["texture", "icon"])
def test_every_committed_image_still_matches_its_recipe(kind):
    jobs = _jobs()
    for record in _records(kind):
        assert record.id in jobs, f"{record.id} is committed but in no recipe"
        assert record.matches(jobs[record.id]), (
            f"{record.id}: the recipe has changed since this image was "
            "generated -- regenerate it or revert the recipe"
        )


@pytest.mark.parametrize("kind", ["texture", "icon"])
def test_every_committed_image_records_its_model_licence(kind):
    """docs/ASSETS.md: provenance is logged on arrival, never reconstructed."""
    for record in _records(kind):
        assert record.model["licence"], f"{record.id} has no licence recorded"
        assert record.model["id"], f"{record.id} has no model recorded"
