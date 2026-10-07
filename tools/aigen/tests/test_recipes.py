"""The reproducibility claim: a committed recipe pins everything that matters.

Seam under test: the public `aigen.recipes` interface -- load a recipe file,
get back fully resolved Jobs whose fingerprint covers exactly the inputs that
change the pixels.
"""

import dataclasses
import textwrap

import pytest

from aigen import recipes

RECIPE = textwrap.dedent(
    """
    kind: texture
    model:
      id: stabilityai/stable-diffusion-xl-base-1.0
      revision: 462165984030d82259a11f4367a4eed129e94a7b
      licence: CreativeML OpenRAIL++-M
    defaults:
      width: 1024
      height: 1024
      steps: 40
      guidance: 6.5
      scheduler: dpmpp_2m_karras
      seamless: true
    style: cast iron and welded steel, olive drab, 1920s heavy industry
    negative: brass, polished wood, whimsical
    items:
      - id: cast_iron_plate
        seed: 20260001
        prompt: pitted cast iron floor plate
      - id: riveted_steel
        seed: 20260002
        prompt: riveted steel plate
        steps: 50
        notes: needs more steps for the rivet highlights
    """
)


@pytest.fixture
def recipe_file(tmp_path):
    path = tmp_path / "textures.yaml"
    path.write_text(RECIPE)
    return path


def test_each_item_becomes_one_job(recipe_file):
    jobs = recipes.load_jobs(recipe_file)
    assert [job.id for job in jobs] == ["cast_iron_plate", "riveted_steel"]
    assert all(job.kind == "texture" for job in jobs)


def test_shared_defaults_apply_and_per_item_values_override_them(recipe_file):
    plate, riveted = recipes.load_jobs(recipe_file)
    assert plate.steps == 40
    assert riveted.steps == 50, "per-item setting must win over the default"
    assert riveted.guidance == 6.5, "unrelated defaults must still apply"
    assert plate.seamless is True


def test_the_shared_style_is_appended_to_every_item_prompt(recipe_file):
    plate, riveted = recipes.load_jobs(recipe_file)
    style = "cast iron and welded steel, olive drab, 1920s heavy industry"
    assert plate.full_prompt == f"pitted cast iron floor plate, {style}"
    assert riveted.full_prompt == f"riveted steel plate, {style}"
    assert plate.negative == "brass, polished wood, whimsical"


def test_the_model_and_its_licence_travel_with_the_job(recipe_file):
    plate = recipes.load_jobs(recipe_file)[0]
    assert plate.model.id == "stabilityai/stable-diffusion-xl-base-1.0"
    assert plate.model.revision == "462165984030d82259a11f4367a4eed129e94a7b"
    assert plate.model.licence == "CreativeML OpenRAIL++-M"


def test_fingerprint_is_stable_across_reloads(recipe_file):
    first = recipes.load_jobs(recipe_file)[0].fingerprint()
    second = recipes.load_jobs(recipe_file)[0].fingerprint()
    assert first == second
    assert len(first) == 16, "short enough to read in a filename"


def test_fingerprint_changes_when_any_pixel_affecting_input_changes(recipe_file):
    job = recipes.load_jobs(recipe_file)[0]
    base = job.fingerprint()
    for field, value in [
        ("seed", 99),
        ("steps", 41),
        ("guidance", 7.0),
        ("width", 512),
        ("height", 512),
        ("prompt", "something else"),
        ("negative", "something else"),
        ("style", "something else"),
        ("scheduler", "euler"),
        ("seamless", False),
    ]:
        changed = dataclasses.replace(job, **{field: value})
        assert changed.fingerprint() != base, f"{field} must affect the fingerprint"


def test_fingerprint_covers_the_model_identity(recipe_file):
    job = recipes.load_jobs(recipe_file)[0]
    other = dataclasses.replace(
        job, model=dataclasses.replace(job.model, revision="deadbeef")
    )
    assert other.fingerprint() != job.fingerprint()


def test_fingerprint_ignores_fields_that_cannot_change_the_pixels(recipe_file):
    """A note or a rename must not invalidate an already-generated image."""
    base = recipes.load_jobs(recipe_file)[0].fingerprint()
    old = "    prompt: pitted cast iron floor plate"
    new = f"{old}\n    notes: reviewed 2026-10-06, keep"
    assert old in RECIPE, "fixture drifted -- the edit below would be a no-op"
    annotated = recipe_file.parent / "annotated.yaml"
    annotated.write_text(RECIPE.replace(old, new))
    assert recipes.load_jobs(annotated)[0].notes == "reviewed 2026-10-06, keep"
    assert recipes.load_jobs(annotated)[0].fingerprint() == base


def test_an_item_without_an_explicit_seed_is_rejected(tmp_path):
    path = tmp_path / "bad.yaml"
    path.write_text(RECIPE.replace("    seed: 20260001\n", ""))
    with pytest.raises(recipes.RecipeError, match="seed"):
        recipes.load_jobs(path)


def test_duplicate_item_ids_are_rejected(tmp_path):
    path = tmp_path / "dupe.yaml"
    path.write_text(RECIPE.replace("id: riveted_steel", "id: cast_iron_plate"))
    with pytest.raises(recipes.RecipeError, match="cast_iron_plate"):
        recipes.load_jobs(path)


def test_an_unknown_setting_is_rejected_rather_than_silently_ignored(tmp_path):
    """A typo'd setting that is quietly dropped breaks reproducibility."""
    path = tmp_path / "typo.yaml"
    path.write_text(RECIPE.replace("  steps: 40", "  stpes: 40"))
    with pytest.raises(recipes.RecipeError, match="stpes"):
        recipes.load_jobs(path)
