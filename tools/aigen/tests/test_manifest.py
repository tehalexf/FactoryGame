"""The provenance claim: every committed image can be traced and re-derived.

Seam under test: the public `aigen.manifest` interface. The manifest is the
committed record sitting next to the art; if it does not survive a save/load
round-trip then the provenance in the repo is worthless.
"""

import dataclasses
import textwrap

import pytest

from aigen import manifest as manifest_mod
from aigen import recipes

RECIPE = textwrap.dedent(
    """
    kind: texture
    model:
      id: stabilityai/stable-diffusion-xl-base-1.0
      revision: 462165984030d82259a11f4367a4eed129e94a7b
      licence: CreativeML OpenRAIL++-M
    defaults:
      width: 512
      height: 512
      steps: 20
      guidance: 6.5
      scheduler: dpmpp_2m_karras
      seamless: true
    style: cast iron, olive drab
    negative: brass
    items:
      - id: cast_iron_plate
        seed: 20260001
        prompt: pitted cast iron floor plate
    """
)


@pytest.fixture
def job(tmp_path):
    path = tmp_path / "textures.yaml"
    path.write_text(RECIPE)
    return recipes.load_jobs(path)[0]


def _record(job, **overrides):
    defaults = dict(
        image_sha256="a" * 64,
        image_size=(512, 512),
        seconds=4.25,
        peak_vram_bytes=7_000_000_000,
        tiling={"x_ratio": 1.02, "y_ratio": 1.04, "tolerance": 1.5, "seamless": True},
    )
    return manifest_mod.Record.of(job, path="textures/cast_iron_plate.png",
                                  **{**defaults, **overrides})


def test_a_saved_manifest_loads_back_identical(tmp_path, job):
    original = manifest_mod.Manifest(records=[_record(job)])
    path = tmp_path / "manifest.json"
    original.save(path)
    assert manifest_mod.Manifest.load(path) == original


def test_the_manifest_is_committed_as_readable_sorted_json(tmp_path, job):
    path = tmp_path / "manifest.json"
    manifest_mod.Manifest(records=[_record(job)]).save(path)
    text = path.read_text()
    assert text.endswith("\n"), "must be a well-formed text file for git"
    assert "\n  " in text, "must be indented so diffs are reviewable"
    # Written twice, byte-identical: no dict ordering noise in git history.
    manifest_mod.Manifest(records=[_record(job)]).save(path)
    assert path.read_text() == text


def test_a_record_carries_the_job_fingerprint_and_its_full_settings(job):
    record = _record(job)
    assert record.fingerprint == job.fingerprint()
    assert record.settings == job.pixel_inputs()
    assert record.model["licence"] == "CreativeML OpenRAIL++-M"


def test_a_loaded_record_still_matches_a_job_rebuilt_from_the_recipe(tmp_path, job):
    path = tmp_path / "manifest.json"
    manifest_mod.Manifest(records=[_record(job)]).save(path)
    loaded = manifest_mod.Manifest.load(path).record("cast_iron_plate")
    assert loaded.matches(job), "the committed settings must re-derive the same job"


def test_a_record_stops_matching_once_the_recipe_is_edited(tmp_path, job):
    path = tmp_path / "manifest.json"
    manifest_mod.Manifest(records=[_record(job)]).save(path)
    loaded = manifest_mod.Manifest.load(path).record("cast_iron_plate")
    assert not loaded.matches(dataclasses.replace(job, seed=7))


def test_records_are_addressed_by_item_id(tmp_path, job):
    other = dataclasses.replace(job, id="riveted_steel", seed=2)
    sheet = manifest_mod.Manifest(records=[_record(job), _record(other)])
    assert sheet.record("riveted_steel").id == "riveted_steel"
    with pytest.raises(KeyError, match="no_such_item"):
        sheet.record("no_such_item")


def test_adding_a_record_replaces_the_previous_one_for_that_item(job):
    sheet = manifest_mod.Manifest()
    sheet.add(_record(job, seconds=1.0))
    sheet.add(_record(job, seconds=2.0))
    assert len(sheet.records) == 1
    assert sheet.record("cast_iron_plate").seconds == 2.0


def test_records_are_kept_in_item_id_order_so_diffs_stay_small(job):
    zebra = dataclasses.replace(job, id="zinc_sheet", seed=3)
    alpha = dataclasses.replace(job, id="anvil", seed=4)
    sheet = manifest_mod.Manifest()
    sheet.add(_record(zebra))
    sheet.add(_record(alpha))
    assert [r.id for r in sheet.records] == ["anvil", "zinc_sheet"]
