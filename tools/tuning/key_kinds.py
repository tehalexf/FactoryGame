"""Which kind of value each tuning key is *read* as, derived from `sim/definitions.gd`.

The subset parser will happily accept `nest.health = 6000.5`: it is a decimal, and
decimals are in the subset. `Definitions` then reads it with `require_int` and
reports `"nest.health" must be a whole number`, which carries **no definitions at
all** — so a stray decimal point in the browser would strand the Run on its last
good content just as surely as a syntax error.

That mapping lives in exactly one place, which is the loader itself:

    const TUNING_NEST_HEALTH: String = "nest.health"
    ...
    nest_health = tuning.require_int(TUNING_NEST_HEALTH)

So this reads that file rather than restating it. A table of seventy keys and
their types, hand-maintained over there in GDScript and over here in Python,
would be wrong within a week — and wrong in the direction that breaks Runs.

`tests/test_key_kinds.py` is what notices when the derivation stops working:
it asserts every key the tuning file defines got a kind out of this.
"""

from __future__ import annotations

import re
from pathlib import Path

from . import toml_subset

## `const TUNING_WALK_SPEED: String = "player.walk_speed_metres_per_second"`,
## including the form Godot's formatter wraps onto its own line inside brackets.
_CONSTANT = re.compile(
    r"^const\s+(TUNING_[A-Z0-9_]+)\s*:\s*String\s*=\s*\(?\s*(?:\n\s*)?\"([^\"]*)\"",
    re.MULTILINE,
)

## `tuning.require_fixed(TUNING_WALK_SPEED)`, wrapped or not.
_READ = re.compile(r"tuning\.require_(int|fixed|string|bool)\(\s*(TUNING_[A-Z0-9_]+)")

_KIND_OF_READ = {
    "int": toml_subset.KIND_INTEGER,
    "fixed": toml_subset.KIND_FIXED,
    "string": toml_subset.KIND_STRING,
    "bool": toml_subset.KIND_BOOLEAN,
}

## What each read accepts. `require_fixed` takes a whole number too, because
## writing `4` where `4.0` was meant is a mistake nobody should be punished for.
ACCEPTS = {
    toml_subset.KIND_INTEGER: (toml_subset.KIND_INTEGER,),
    toml_subset.KIND_FIXED: (toml_subset.KIND_INTEGER, toml_subset.KIND_FIXED),
    toml_subset.KIND_STRING: (toml_subset.KIND_STRING,),
    toml_subset.KIND_BOOLEAN: (toml_subset.KIND_BOOLEAN,),
}

DESCRIBED = {
    toml_subset.KIND_INTEGER: "a whole number",
    toml_subset.KIND_FIXED: "a number",
    toml_subset.KIND_STRING: "a quoted string",
    toml_subset.KIND_BOOLEAN: "true or false",
}


def load(definitions_gd: Path) -> dict[str, str]:
    """`section.key` → the kind `Definitions` reads it as."""
    source = definitions_gd.read_text(encoding="utf-8")
    # Join bracket-wrapped constants so one regex sees the whole declaration.
    flattened = re.sub(r"\(\s*\n\s*", "(", source)
    constants = {name: key for name, key in _CONSTANT.findall(flattened)}
    kinds: dict[str, str] = {}
    for read, name in _READ.findall(re.sub(r"\(\s*\n\s*", "(", source)):
        key = constants.get(name)
        if key and "." in key:
            kinds[key] = _KIND_OF_READ[read]
    return kinds
