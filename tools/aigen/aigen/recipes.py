"""Recipes: the committed, human-editable description of what to generate.

The whole point of this pipeline is that no image is a one-off. A recipe file
holds the model, the shared style, the per-Item prompt and every sampler
setting; the recipe is committed next to the PNG it produced. Regenerating is
then `generate.py --recipe <file>`, not archaeology.

Two properties the rest of the tool leans on:

* **Everything is explicit.** Seeds are mandatory and unknown keys are a hard
  error. A silently-defaulted seed or a typo'd `stpes: 40` would produce an
  image nobody can get back.
* **A Job knows its own fingerprint.** The fingerprint hashes exactly the
  inputs that reach the sampler, so it survives a comment being added to the
  recipe but changes the moment a pixel could.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

import yaml

FINGERPRINT_CHARS = 16

#: Settings that may appear in `defaults:` or on an item, with their types.
SETTING_TYPES: dict[str, type | tuple[type, ...]] = {
    "width": int,
    "height": int,
    "steps": int,
    "guidance": (int, float),
    "scheduler": str,
    "seamless": bool,
    "canvas_px": int,
    "margin_frac": (int, float),
    "key_tolerance": (int, float),
}

#: Per-item keys that are not settings. `notes` is documentation only and is
#: deliberately excluded from the fingerprint.
ITEM_KEYS = {"id", "prompt", "seed", "negative", "style", "notes"}

KINDS = {"texture", "icon"}


class RecipeError(Exception):
    """A recipe is malformed. Always raised with the offending key named."""


@dataclass(frozen=True)
class Model:
    """Which weights produced an image, and under what licence."""

    id: str
    revision: str | None = None
    licence: str | None = None
    variant: str | None = None

    def identity(self) -> dict[str, str | None]:
        """Only the parts that change the pixels -- the licence does not."""
        return {"id": self.id, "revision": self.revision, "variant": self.variant}


@dataclass(frozen=True)
class Job:
    """One image to generate, with every input resolved and nothing implicit."""

    id: str
    kind: str
    model: Model
    prompt: str
    style: str
    negative: str
    seed: int
    width: int
    height: int
    steps: int
    guidance: float
    scheduler: str
    seamless: bool = False
    canvas_px: int = 256
    margin_frac: float = 0.08
    key_tolerance: float = 28.0
    notes: str | None = None
    recipe_path: str | None = None

    @property
    def full_prompt(self) -> str:
        """The item prompt plus the recipe's shared style suffix.

        Keeping the style in one place is what makes a *set* look like a set;
        editing it regenerates every image in the recipe, by design.
        """
        if not self.style:
            return self.prompt
        return f"{self.prompt}, {self.style}"

    def pixel_inputs(self) -> dict:
        """Exactly the inputs that reach the sampler, canonically ordered."""
        return {
            "model": self.model.identity(),
            "kind": self.kind,
            "prompt": self.full_prompt,
            "negative": self.negative,
            "seed": self.seed,
            "width": self.width,
            "height": self.height,
            "steps": self.steps,
            "guidance": float(self.guidance),
            "scheduler": self.scheduler,
            "seamless": self.seamless,
            "canvas_px": self.canvas_px,
            "margin_frac": float(self.margin_frac),
            "key_tolerance": float(self.key_tolerance),
        }

    def fingerprint(self) -> str:
        """Short stable hash of `pixel_inputs`, used in filenames and manifests."""
        blob = json.dumps(self.pixel_inputs(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(blob.encode()).hexdigest()[:FINGERPRINT_CHARS]


def _require(mapping: dict, key: str, where: str):
    if key not in mapping:
        raise RecipeError(f"{where}: missing required key {key!r}")
    return mapping[key]


def _check_settings(settings: dict, where: str) -> dict:
    for key, value in settings.items():
        if key not in SETTING_TYPES:
            known = ", ".join(sorted(SETTING_TYPES))
            raise RecipeError(
                f"{where}: unknown setting {key!r} (known settings: {known})"
            )
        if not isinstance(value, SETTING_TYPES[key]) or isinstance(value, bool) != (
            SETTING_TYPES[key] is bool
        ):
            raise RecipeError(
                f"{where}: setting {key!r} should be "
                f"{SETTING_TYPES[key]}, got {type(value).__name__}"
            )
    return dict(settings)


def load_recipe(path: str | Path) -> dict:
    """Read and validate a recipe file, returning the raw validated mapping."""
    path = Path(path)
    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        raise RecipeError(f"{path}: not valid YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise RecipeError(f"{path}: expected a mapping at the top level")

    kind = _require(data, "kind", str(path))
    if kind not in KINDS:
        raise RecipeError(f"{path}: kind must be one of {sorted(KINDS)}, got {kind!r}")

    unknown = set(data) - {
        "kind", "model", "defaults", "style", "negative", "items", "description"
    }
    if unknown:
        raise RecipeError(f"{path}: unknown top-level key(s) {sorted(unknown)}")
    return data


def load_jobs(path: str | Path) -> list[Job]:
    """Resolve a recipe into one fully-specified Job per item."""
    path = Path(path)
    data = load_recipe(path)

    model_data = _require(data, "model", str(path))
    if isinstance(model_data, str):
        model_data = {"id": model_data}
    model = Model(
        id=_require(model_data, "id", f"{path}: model"),
        revision=model_data.get("revision"),
        licence=model_data.get("licence"),
        variant=model_data.get("variant"),
    )

    defaults = _check_settings(data.get("defaults") or {}, f"{path}: defaults")
    items = _require(data, "items", str(path))
    if not isinstance(items, list) or not items:
        raise RecipeError(f"{path}: items must be a non-empty list")

    jobs: list[Job] = []
    seen: set[str] = set()
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise RecipeError(f"{path}: items[{index}] must be a mapping")
        item_id = _require(item, "id", f"{path}: items[{index}]")
        where = f"{path}: item {item_id!r}"
        if item_id in seen:
            raise RecipeError(f"{where}: duplicate item id {item_id!r}")
        seen.add(item_id)

        if "seed" not in item:
            raise RecipeError(
                f"{where}: missing required key 'seed'. Seeds must be explicit -- "
                "an image generated from an implicit seed cannot be regenerated."
            )
        if not isinstance(item["seed"], int) or isinstance(item["seed"], bool):
            raise RecipeError(f"{where}: seed must be an integer")

        overrides = _check_settings(
            {k: v for k, v in item.items() if k not in ITEM_KEYS}, where
        )
        settings = {**defaults, **overrides}

        for required in ("width", "height", "steps", "guidance", "scheduler"):
            if required not in settings:
                raise RecipeError(f"{where}: missing required setting {required!r}")

        jobs.append(
            Job(
                id=item_id,
                kind=data["kind"],
                model=model,
                prompt=_require(item, "prompt", where),
                style=item.get("style", data.get("style") or ""),
                negative=item.get("negative", data.get("negative") or ""),
                seed=item["seed"],
                notes=item.get("notes"),
                recipe_path=str(path),
                **settings,
            )
        )
    return jobs
