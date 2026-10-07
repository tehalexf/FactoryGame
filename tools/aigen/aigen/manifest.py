"""The manifest: the committed provenance record for generated art.

`docs/ASSETS.md` demands that every asset's origin and licence be logged at
arrival, because reconstructing provenance later is far harder than recording
it now. For generated art the manifest is that log, and it goes further: it
stores the complete sampler settings, so the entry is not just a note about
where an image came from but an executable recipe for getting it back.

One JSON file per output directory, sorted and indented so git diffs are
reviewable and a regeneration that changes nothing produces no diff at all.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from .recipes import Job

SCHEMA_VERSION = 1


@dataclass(frozen=True)
class Record:
    """One generated image: what it is, how it was made, and what came out."""

    id: str
    kind: str
    path: str
    fingerprint: str
    model: dict
    settings: dict
    image_sha256: str
    image_size: tuple[int, int]
    seconds: float
    peak_vram_bytes: int | None = None
    tiling: dict | None = None
    notes: str | None = None
    recipe: str | None = None
    environment: dict = field(default_factory=dict)

    @classmethod
    def of(cls, job: Job, path: str, **outcome) -> "Record":
        """Build a record from the Job that produced it plus its outcome.

        `outcome` may override `notes` -- generation sometimes has something to
        say about an image that the recipe could not know in advance.
        """
        fields = dict(
            id=job.id,
            kind=job.kind,
            path=path,
            fingerprint=job.fingerprint(),
            model={
                "id": job.model.id,
                "revision": job.model.revision,
                "variant": job.model.variant,
                "licence": job.model.licence,
            },
            settings=job.pixel_inputs(),
            notes=job.notes,
            recipe=job.recipe_path,
        )
        fields.update(outcome)
        return cls(**fields)

    def matches(self, job: Job) -> bool:
        """True when `job` would produce this record's image again.

        Compares fingerprints, so it is immune to a comment or a path change
        and sensitive to anything that would alter a pixel.
        """
        return self.fingerprint == job.fingerprint()

    def to_json(self) -> dict:
        data = {
            "id": self.id,
            "kind": self.kind,
            "path": self.path,
            "fingerprint": self.fingerprint,
            "model": self.model,
            "settings": self.settings,
            "image_sha256": self.image_sha256,
            "image_size": list(self.image_size),
            "seconds": round(self.seconds, 3),
            "peak_vram_bytes": self.peak_vram_bytes,
            "tiling": self.tiling,
            "notes": self.notes,
            "recipe": self.recipe,
            "environment": self.environment,
        }
        return {k: v for k, v in data.items() if v is not None}

    @classmethod
    def from_json(cls, data: dict) -> "Record":
        data = dict(data)
        data["image_size"] = tuple(data["image_size"])
        known = {f for f in cls.__dataclass_fields__}
        unknown = set(data) - known
        if unknown:
            raise ValueError(f"manifest record has unknown field(s) {sorted(unknown)}")
        return cls(**data)


@dataclass
class Manifest:
    """All records for one output directory, kept in item-id order."""

    records: list[Record] = field(default_factory=list)

    def add(self, record: Record) -> None:
        """Insert or replace the record for `record.id`, keeping order stable."""
        self.records = sorted(
            [r for r in self.records if r.id != record.id] + [record],
            key=lambda r: (r.kind, r.id),
        )

    def record(self, item_id: str) -> Record:
        for record in self.records:
            if record.id == item_id:
                return record
        raise KeyError(f"no record for item {item_id!r}")

    def save(self, path: str | Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema": SCHEMA_VERSION,
            "records": [r.to_json() for r in self.records],
        }
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

    @classmethod
    def load(cls, path: str | Path) -> "Manifest":
        path = Path(path)
        if not path.exists():
            return cls()
        payload = json.loads(path.read_text())
        if payload.get("schema") != SCHEMA_VERSION:
            raise ValueError(
                f"{path}: manifest schema {payload.get('schema')!r}, "
                f"this tool writes {SCHEMA_VERSION}"
            )
        return cls(records=[Record.from_json(r) for r in payload["records"]])
