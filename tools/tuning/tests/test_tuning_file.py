"""Reading `content/tuning.toml` as something a dashboard can draw, and writing
one value back without disturbing a byte of anything else.

Seam: `tuning_file.TuningFile` — `parse`, `sections`, `field`, `with_value`,
`render`. The dashboard never assembles TOML text by any other route.

The help copy is the *file's own* comments. There is no second description
anywhere in this tool, because a second description is a description that drifts.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import tuning_file  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
SHIPPED = REPO / "content" / "tuning.toml"

SAMPLE = """\
# A file preamble.

[player]

# How fast a player walks, in metres per second.
# A second line of the same comment.
walk_speed_metres_per_second = 4

# ── Weight ───────────────────────────────────────────────
#
# Prose about a group of keys.

# The pair below share one comment.
air_acceleration_metres_per_second_squared = 6
air_deceleration_metres_per_second_squared = 1.5

a_flag = true

[nest]

# Section prose, because a comment block follows it.

# The Nest's hit points.
health = 6000
"""


class ReadingTheFile(unittest.TestCase):
    def setUp(self):
        self.doc = tuning_file.TuningFile.parse(SAMPLE, "sample.toml")

    def test_groups_values_by_their_section_in_file_order(self):
        self.assertEqual([s.name for s in self.doc.sections()], ["player", "nest"])

    def test_lists_every_key_as_section_dot_key(self):
        self.assertEqual(
            self.doc.keys(),
            [
                "player.walk_speed_metres_per_second",
                "player.air_acceleration_metres_per_second_squared",
                "player.air_deceleration_metres_per_second_squared",
                "player.a_flag",
                "nest.health",
            ],
        )

    def test_a_field_carries_the_comment_block_above_it_as_its_help(self):
        field = self.doc.field("player.walk_speed_metres_per_second")
        self.assertEqual(
            field.help,
            "How fast a player walks, in metres per second.\n"
            "A second line of the same comment.",
        )

    def test_consecutive_keys_share_the_one_comment_above_them(self):
        """`air_acceleration` and `air_deceleration` are written as a pair under
        one comment in the shipped file; both controls get that text."""
        first = self.doc.field("player.air_acceleration_metres_per_second_squared")
        second = self.doc.field("player.air_deceleration_metres_per_second_squared")
        self.assertEqual(first.help, "The pair below share one comment.")
        self.assertEqual(second.help, first.help)

    def test_a_field_with_no_comment_above_it_has_no_help(self):
        self.assertEqual(self.doc.field("player.a_flag").help, "")

    def test_a_comment_block_followed_by_another_block_is_prose_not_help(self):
        notes = self.doc.sections()[1].notes
        self.assertEqual([note.body for note in notes], ["Section prose, because a comment block follows it."])
        self.assertEqual(self.doc.field("nest.health").help, "The Nest's hit points.")

    def test_a_divider_comment_becomes_a_heading_on_its_note(self):
        notes = self.doc.sections()[0].notes
        self.assertEqual([note.heading for note in notes], ["Weight"])
        self.assertEqual(notes[0].body, "Prose about a group of keys.")

    def test_the_file_preamble_is_kept_as_the_document_note(self):
        self.assertEqual(self.doc.preamble, "A file preamble.")

    def test_a_field_reports_its_kind_and_how_it_is_written(self):
        field = self.doc.field("player.air_deceleration_metres_per_second_squared")
        self.assertEqual(field.kind, "fixed")
        self.assertEqual(field.source, "1.5")


class WritingOneValueBack(unittest.TestCase):
    def test_changes_only_that_line(self):
        doc = tuning_file.TuningFile.parse(SAMPLE, "sample.toml")
        rendered = doc.with_value("nest.health", "7000").render()
        self.assertEqual(
            rendered.split("\n"), SAMPLE.replace("health = 6000", "health = 7000").split("\n")
        )

    def test_rendering_an_untouched_document_returns_the_bytes_it_was_given(self):
        doc = tuning_file.TuningFile.parse(SAMPLE, "sample.toml")
        self.assertEqual(doc.render(), SAMPLE)

    def test_the_shipped_file_round_trips_byte_for_byte(self):
        source = SHIPPED.read_text(encoding="utf-8")
        self.assertEqual(
            tuning_file.TuningFile.parse(source, str(SHIPPED)).render(), source
        )

    def test_keeps_a_trailing_comment_on_the_line_it_rewrites(self):
        doc = tuning_file.TuningFile.parse("[a]\nk = 1  # why\n", "s.toml")
        self.assertEqual(doc.with_value("a.k", "2").render(), "[a]\nk = 2  # why\n")

    def test_refuses_a_key_the_file_does_not_define(self):
        doc = tuning_file.TuningFile.parse(SAMPLE, "sample.toml")
        with self.assertRaises(KeyError):
            doc.with_value("nest.invented_key", "1")


class TheShippedFile(unittest.TestCase):
    def setUp(self):
        self.doc = tuning_file.TuningFile.parse(
            SHIPPED.read_text(encoding="utf-8"), str(SHIPPED)
        )

    def test_every_key_in_it_has_help_from_its_own_comment(self):
        """The dashboard's labelling is only as good as this. A key that reaches
        the browser with no explanation is one the player has to alt-tab to
        understand, which is the whole thing being replaced."""
        unexplained = [f.key for f in self.doc.fields() if not f.help]
        self.assertEqual(unexplained, [])

    def test_covers_the_sections_the_file_declares(self):
        self.assertEqual(
            [s.name for s in self.doc.sections()],
            [
                "player", "gear", "belt", "machine", "wall", "wrench", "survey",
                "power", "nest", "silo", "wave", "heat", "enemy", "depth",
                "siege_hulk", "hive",
            ],
        )

    def test_is_the_seventy_or_so_values_the_ticket_describes(self):
        self.assertGreater(len(self.doc.fields()), 60)
