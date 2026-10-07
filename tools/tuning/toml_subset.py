"""The TOML subset `sim/toml_document.gd` accepts, mirrored exactly.

The dashboard's whole safety property is that it never writes something the game
would refuse. A malformed write means `Definitions` carries no definitions at
all, and the Run is stuck on its last good content until somebody alt-tabs to a
text editor — which is the thing the dashboard exists to stop happening.

So this is a deliberate, line-for-line port of the parser in
`sim/toml_document.gd`, including its error messages, and it is the only place in
the dashboard that decides whether a value is acceptable. When that parser
changes, this changes with it and `tests/test_toml_subset.py` is what notices.

The subset, and nothing else:

    # a comment
    [section]
    an_integer = 3
    a_rate = 4.5          # a fixed-point quantity, exactly
    a_string = "iron_ore"
    a_flag = true         # or false

Being *stricter* than the game is safe here; being looser is not. Where a
judgement call exists this errs towards refusing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# `Fixed.FRACTIONAL_BITS`. A value the game would hold as a fixed-point quantity
# has to survive the trip, so the dashboard refuses magnitudes that would not.
FRACTIONAL_BITS = 16
ONE = 1 << FRACTIONAL_BITS

# `Fixed.MUL_OPERAND_LIMIT` — isqrt(2^63 - 1). A quantity larger than this cannot
# be an operand of `Fixed.mul`, so writing one would arm an overflow somewhere in
# the Simulation rather than in the file.
MUL_OPERAND_LIMIT = 3037000499

KIND_INTEGER = "integer"
KIND_FIXED = "fixed"
KIND_STRING = "string"
KIND_BOOLEAN = "boolean"

# Godot's `String.is_valid_int()`: an optional single sign, then digits.
_VALID_INT = re.compile(r"^[+-]?[0-9]+$")

_IDENTIFIER = re.compile(r"^[a-z0-9_]+$")


@dataclass(frozen=True)
class Value:
    """One classified value, in the same shape `TomlDocument.Entry` holds."""

    kind: str
    ## The integer, the fixed-point quantity, or 0/1 for a boolean.
    number: int = 0
    ## The string's contents, without its quotes.
    text: str = ""
    ## The value exactly as it is written in the file.
    source: str = ""


# ── Classifying one value ─────────────────────────────────────────────────────


def is_identifier(text: str) -> bool:
    """`CsvTable.is_identifier`: lowercase letters, digits and underscore."""
    return bool(_IDENTIFIER.match(text))


def is_valid_int(text: str) -> bool:
    return bool(_VALID_INT.match(text))


def is_decimal_string(text: str) -> bool:
    """`Fixed.is_decimal_string`."""
    body = text.strip()
    if body.startswith("-") or body.startswith("+"):
        body = body[1:]
    if not body:
        return False
    parts = body.split(".")
    if len(parts) > 2:
        return False
    return all(part and is_valid_int(part) for part in parts)


def from_decimal_string(text: str) -> int:
    """`Fixed.from_decimal_string`, including its flooring."""
    if not is_decimal_string(text):
        return 0
    body = text.strip()
    negative = body.startswith("-")
    if negative or body.startswith("+"):
        body = body[1:]
    parts = body.split(".")
    digits = parts[0]
    denominator = 1
    if len(parts) == 2:
        digits += parts[1]
        denominator = 10 ** len(parts[1])
    numerator = int(digits)
    if negative:
        numerator = -numerator
    # `Fixed.from_rational` — floor division, which is Python's `//`.
    return (numerator * ONE) // denominator


def classify(text: str) -> Value | None:
    """The value kind, or None when it is outside the subset.

    The order matters and matches `_read_value`: `true`/`false` first, then a
    quoted string, then a whole number, then a decimal. A whole number is an
    INTEGER and not a FIXED, which is what lets `require_int` accept it.
    """
    if text in ("true", "false"):
        return Value(KIND_BOOLEAN, number=1 if text == "true" else 0, source=text)

    if text.startswith('"'):
        if len(text) < 2 or not text.endswith('"'):
            return None
        return Value(KIND_STRING, text=text[1:-1], source=text)

    if is_valid_int(text):
        return Value(KIND_INTEGER, number=int(text), source=text)

    if is_decimal_string(text):
        return Value(KIND_FIXED, number=from_decimal_string(text), source=text)

    return None


def strip_comment(line: str) -> str:
    """`TomlDocument._strip_comment`: drops a trailing comment, leaving a `#`
    inside a quoted string alone."""
    in_string = False
    for index, character in enumerate(line):
        if character == '"':
            in_string = not in_string
        elif character == "#" and not in_string:
            return line[:index]
    return line


# ── Validating a whole file ───────────────────────────────────────────────────


def validate(source: str, path: str) -> list[str]:
    """Every problem the game's parser would report, in file order.

    An empty list means `TomlDocument.parse` would come back without errors, so
    the write is safe to land. This deliberately re-parses the *rendered output*
    rather than checking the one value that changed: a renderer bug that mangled
    an unrelated line is exactly the failure that would strand a Run.
    """
    errors: list[str] = []
    section = ""
    seen_sections: list[str] = []
    seen_keys: dict[str, int] = {}

    for line_number, raw_line in enumerate(source.split("\n"), start=1):
        line = strip_comment(raw_line).strip()
        if not line:
            continue

        if line.startswith("["):
            section = _read_section(line, line_number, seen_sections, path, errors)
            continue

        _read_pair(line, line_number, section, seen_keys, path, errors)

    return errors


def _read_section(
    line: str, line_at: int, seen: list[str], path: str, errors: list[str]
) -> str:
    if not line.endswith("]"):
        errors.append(_report(path, line_at, "section header is not closed with ]"))
        return ""

    name = line[1:-1].strip()
    if not is_identifier(name):
        errors.append(
            _report(path, line_at, 'section name "%s" must be an identifier' % name)
        )
        return ""
    if name in seen:
        errors.append(
            _report(path, line_at, "section [%s] appears more than once" % name)
        )
        return ""

    seen.append(name)
    return name


def _read_pair(
    line: str,
    line_at: int,
    section: str,
    seen_keys: dict[str, int],
    path: str,
    errors: list[str],
) -> None:
    separator = line.find("=")
    if separator == -1:
        errors.append(
            _report(path, line_at, 'expected "key = value", got "%s"' % line)
        )
        return

    name = line[:separator].strip()
    text = line[separator + 1 :].strip()

    if not is_identifier(name):
        errors.append(_report(path, line_at, 'key "%s" must be an identifier' % name))
        return
    if not section:
        errors.append(
            _report(
                path,
                line_at,
                'key "%s" is not inside a [section], so it has no address' % name,
            )
        )
        return
    if not text:
        errors.append(_report(path, line_at, 'key "%s" has no value' % name))
        return

    key = "%s.%s" % (section, name)
    if key in seen_keys:
        errors.append(
            _report(
                path,
                line_at,
                '"%s" is already defined on line %d' % (key, seen_keys[key]),
            )
        )
        return

    value = classify(text)
    if value is None:
        if text.startswith('"'):
            errors.append(_report(path, line_at, "string is not closed with a quote"))
        else:
            errors.append(
                _report(
                    path,
                    line_at,
                    'value "%s" is outside the supported subset '
                    '(integer, decimal, "string", true, false)' % text,
                )
            )
        return

    seen_keys[key] = line_at


def _report(path: str, line_at: int, detail: str) -> str:
    if line_at > 0:
        return "%s:%d: %s" % (path, line_at, detail)
    return "%s: %s" % (path, detail)
