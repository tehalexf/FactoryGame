"""The tuning file as the shape the page draws: sections, notes, controls.

Everything here is derived from the file, the loader and the slider table. There
is no fourth source: a label is the key's own name read back as English, a unit
is the suffix the key already carries, and the help is the file's own comment
verbatim. The one thing this module decides is *presentation*, which is why it
is separate from `store` — `store` is the layer that must never be wrong, and
this is the layer that must never be ugly.
"""

from __future__ import annotations

from . import controls, toml_subset
from .store import TuningStore

## Domain vocabulary, from GLOSSARY.md. Capitalised in a label because that is
## how the project writes them everywhere else, and a dashboard that called a
## Nest a "nest" would be the only place that did.
PROPER_NOUNS = {
    "nest": "Nest",
    "hive": "Hive",
    "breach": "Breach",
    "breaches": "Breaches",
    "run": "Run",
    "map": "Map",
    "factory": "Factory",
    "machine": "Machine",
    "machines": "Machines",
    "turret": "Turret",
    "recipe": "Recipe",
    "node": "Node",
    "depth": "Depth",
    "miner": "Miner",
    "power": "Power",
    "belt": "Belt",
    "wave": "Wave",
    "heat": "Heat",
    "enemy": "Enemy",
    "chaff": "Chaff",
    "crawler": "Crawler",
    "breaker": "Breaker",
    "siege": "Siege",
    "hulk": "Hulk",
    "telegraph": "Telegraph",
    "downed": "Downed",
    "stratagem": "Stratagem",
    "silo": "Silo",
    "charge": "Charge",
    "charges": "Charges",
    "painting": "Painting",
    "gear": "Gear",
    "delivery": "Delivery",
    "item": "Item",
    "wall": "Wall",
    "ammunition": "Ammunition",
}

## Unit suffixes, longest first so `metres_per_second_squared` is not read as
## `metres` followed by noise. Each is stripped off the key's name and shown next
## to the control instead, which is what lets a label read as four words.
UNIT_SUFFIXES: list[tuple[str, str]] = [
    ("degrees_per_metre_per_second", "°/(m/s)"),
    ("metres_per_second_squared", "m/s²"),
    ("turns_per_1000_pixels", "turns / 1000 px"),
    ("metres_per_second", "m/s"),
    ("points_per_second", "points/s"),
    ("items_per_second", "items/s"),
    ("per_1000_pixels", "/1000 px"),
    ("per_minute", "per minute"),
    ("per_second", "per second"),
    ("per_item", "per Item"),
    ("per_shot", "per shot"),
    ("per_load", "per load"),
    ("per_depth", "per Depth"),
    ("per_tile", "per tile"),
    ("add_degrees", "°"),
    ("seconds", "s"),
    ("metres", "m"),
    ("degrees", "°"),
    ("percent", "%"),
    ("kw", "kW"),
    ("tiles", "tiles"),
    ("crafts", "crafts"),
    ("multiplier", "×"),
]


def state(store: TuningStore) -> dict:
    """Everything the page needs, in one object.

    Read fresh from the file on every request rather than cached, so a hand edit
    in a text editor, a `git checkout`, or another agent's change shows up on a
    refresh instead of being overwritten by a stale view.
    """
    live = store.read()
    shipped = store.defaults()
    changed = store.changed_from_default()
    deep = store.deep_check

    sections = []
    for section in live.sections():
        fields = []
        for entry in section.fields:
            default = (
                shipped.field(entry.key).value_text
                if shipped.has(entry.key)
                else entry.value_text
            )
            fields.append(_field(store, entry, default, entry.key in changed))
        sections.append(
            {
                "name": section.name,
                "title": title_of(section.name),
                "notes": [
                    {
                        "heading": note.heading,
                        "body": note.body,
                        "position": note.position,
                    }
                    for note in section.notes
                ],
                "fields": fields,
                "changed": sum(1 for f in fields if f["changed"]),
            }
        )

    return {
        "file": "content/tuning.toml",
        "preamble": live.preamble,
        "sections": sections,
        "changed_count": len(changed),
        "value_count": len(live.fields()),
        "deep_check_available": bool(deep is not None and deep.available),
        "drift": store.unknown_defaults(),
        "history": [
            {
                "id": snapshot.snapshot_id,
                "summary": snapshot.summary,
                "written_at": snapshot.written_at,
            }
            for snapshot in store.history()
        ],
    }


def _field(store: TuningStore, entry, default: str, changed: bool) -> dict:
    kind = store.required_kind(entry.key)
    label, unit = label_and_unit(entry.name)
    bounds = controls.slider_for(entry.key)

    if kind == toml_subset.KIND_BOOLEAN:
        control = "flag"
    elif kind == toml_subset.KIND_STRING:
        control = "text"
    elif bounds is not None:
        control = "slider"
    else:
        control = "number"

    field = {
        "key": entry.key,
        "name": entry.name,
        "label": label,
        "unit": unit,
        "help": entry.help,
        "kind": kind,
        "control": control,
        "value": entry.value_text,
        "default": default,
        "changed": changed,
        "line": entry.line_number,
    }
    if bounds is not None:
        field["min"] = bounds.minimum
        field["max"] = bounds.maximum
        field["step"] = bounds.step
    elif kind == toml_subset.KIND_INTEGER:
        field["step"] = 1
    return field


def title_of(section: str) -> str:
    """`siege_hulk` → `Siege Hulk`."""
    return " ".join(PROPER_NOUNS.get(word, word.capitalize()) for word in section.split("_"))


def label_and_unit(name: str) -> tuple[str, str]:
    """A key's name read back as English, with its unit taken off the end.

    `walk_speed_metres_per_second` → `Walk speed`, `m/s`. The label is the key,
    not a restatement of it, so it cannot disagree with the file.
    """
    words = name.split("_")
    unit = ""
    for suffix, rendered in UNIT_SUFFIXES:
        tail = suffix.split("_")
        if len(words) > len(tail) and words[-len(tail) :] == tail:
            unit = rendered
            words = words[: -len(tail)]
            break

    if not words:
        return name.replace("_", " ").capitalize(), unit

    spelled = [PROPER_NOUNS.get(word, word) for word in words]
    label = " ".join(spelled)
    if label[:1].islower():
        label = label[0].upper() + label[1:]
    return label, unit
