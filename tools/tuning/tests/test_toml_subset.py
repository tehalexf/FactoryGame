"""The TOML subset the game accepts, mirrored in Python.

Seam: `toml_subset.validate(source, path)` and `toml_subset.classify(text)`.
Nothing else in the dashboard is allowed to decide whether a value is
acceptable — this module is the gate in front of every write.

The expected errors here are read off `sim/toml_document.gd`'s own `_report`
calls, which is the independent source of truth: the point of this module is to
refuse exactly what the game refuses, so a message that drifts is a bug even
when the refusal is correct.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import toml_subset  # noqa: E402


class TheAcceptedSubset(unittest.TestCase):
    def test_accepts_the_five_value_forms(self):
        source = (
            "# a comment\n"
            "[section]\n"
            "an_integer = 3\n"
            "a_negative = -7\n"
            "a_rate = 4.5\n"
            'a_string = "iron_ore"\n'
            "a_flag = true\n"
            "another_flag = false\n"
        )
        self.assertEqual(toml_subset.validate(source, "t.toml"), [])

    def test_refuses_an_array(self):
        source = "[section]\nthings = [1, 2]\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            [
                't.toml:2: value "[1, 2]" is outside the supported subset '
                '(integer, decimal, "string", true, false)'
            ],
        )

    def test_refuses_a_key_outside_any_section(self):
        source = "orphan = 1\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            ['t.toml:1: key "orphan" is not inside a [section], so it has no address'],
        )

    def test_refuses_a_duplicate_key(self):
        source = "[section]\nkey = 1\nkey = 2\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            ['t.toml:3: "section.key" is already defined on line 2'],
        )

    def test_refuses_a_duplicate_section(self):
        source = "[one]\na = 1\n[one]\nb = 2\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            [
                "t.toml:3: section [one] appears more than once",
                # `_read_section` returns "" on a refusal, so every key under the
                # rejected header loses its address too. Mirrored on purpose: the
                # dashboard reports the game's report, cascade included.
                't.toml:4: key "b" is not inside a [section], so it has no address',
            ],
        )

    def test_refuses_a_key_that_is_not_an_identifier(self):
        source = "[section]\nTwo Words = 1\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            ['t.toml:2: key "Two Words" must be an identifier'],
        )

    def test_refuses_a_value_that_is_missing_altogether(self):
        source = "[section]\nkey =\n"
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            ['t.toml:2: key "key" has no value'],
        )

    def test_refuses_an_unclosed_string(self):
        source = '[section]\nkey = "open\n'
        self.assertEqual(
            toml_subset.validate(source, "t.toml"),
            ["t.toml:2: string is not closed with a quote"],
        )

    def test_leaves_a_hash_inside_a_quoted_string_alone(self):
        source = '[section]\nkey = "a # b"\n'
        self.assertEqual(toml_subset.validate(source, "t.toml"), [])

    def test_the_shipped_tuning_file_is_in_the_subset(self):
        repo = Path(__file__).resolve().parents[3]
        shipped = repo / "content" / "tuning.toml"
        self.assertEqual(
            toml_subset.validate(shipped.read_text(encoding="utf-8"), str(shipped)), []
        )


class ClassifyingOneValue(unittest.TestCase):
    def test_reads_the_four_kinds(self):
        self.assertEqual(toml_subset.classify("3").kind, "integer")
        self.assertEqual(toml_subset.classify("4.5").kind, "fixed")
        self.assertEqual(toml_subset.classify('"a"').kind, "string")
        self.assertEqual(toml_subset.classify("true").kind, "boolean")

    def test_an_integer_is_an_integer_and_not_a_decimal(self):
        """`_read_value` tries `is_valid_int` before `is_decimal_string`, so a
        whole number in the file is INTEGER and `require_int` accepts it."""
        self.assertEqual(toml_subset.classify("-7").kind, "integer")

    def test_a_string_keeps_its_quotes_out_of_the_text(self):
        self.assertEqual(toml_subset.classify('"iron_plate:80"').text, "iron_plate:80")

    def test_refuses_what_the_game_refuses(self):
        for text in ["[1]", "{a = 1}", "1979-05-27", "0x10", "1e3", "TRUE", "nan"]:
            with self.subTest(text=text):
                self.assertIsNone(toml_subset.classify(text), text)
