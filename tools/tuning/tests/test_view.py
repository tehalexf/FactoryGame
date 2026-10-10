"""The page's view of the file: labels, units, controls, and what is changed.

Seam: `view.state(store)` and `view.label_and_unit`. These are presentation
tests — what makes the page readable rather than what makes a write safe.
"""

import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import store, view  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
LIVE = REPO / "content" / "tuning.toml"


class ReadingAKeyBackAsEnglish(unittest.TestCase):
    def test_takes_the_unit_off_the_end(self):
        self.assertEqual(
            view.label_and_unit("walk_speed_metres_per_second"), ("Walk speed", "m/s")
        )

    def test_reads_the_longest_unit_rather_than_the_first_it_sees(self):
        self.assertEqual(
            view.label_and_unit("walk_acceleration_metres_per_second_squared"),
            ("Walk acceleration", "m/s²"),
        )

    def test_capitalises_the_domain_vocabulary(self):
        self.assertEqual(view.label_and_unit("crawler_health")[0], "Crawler health")
        self.assertEqual(view.label_and_unit("breach_tier")[0], "Breach tier")

    def test_leaves_a_key_that_is_nothing_but_a_unit_alone(self):
        """`heat.per_craft` would otherwise be stripped down to nothing."""
        self.assertEqual(view.label_and_unit("per_craft"), ("Per craft", ""))

    def test_names_a_section_the_way_the_glossary_does(self):
        self.assertEqual(view.title_of("siege_hulk"), "Siege Hulk")
        self.assertEqual(view.title_of("player"), "Player")


class TheStateThePageDraws(unittest.TestCase):
    def setUp(self):
        self._temp = TemporaryDirectory()
        root = Path(self._temp.name)
        self.live = root / "tuning.toml"
        self.live.write_text(LIVE.read_text(encoding="utf-8"), encoding="utf-8")
        self.store = store.TuningStore(
            live_path=self.live,
            defaults_path=LIVE,
            history_dir=root / "history",
            definitions_gd=REPO / "sim" / "definitions.gd",
        )

    def tearDown(self):
        self._temp.cleanup()

    def field(self, state, key):
        for section in state["sections"]:
            for entry in section["fields"]:
                if entry["key"] == key:
                    return entry
        raise AssertionError("no field %s" % key)

    def test_every_value_in_the_file_reaches_the_page(self):
        state = view.state(self.store)
        drawn = sum(len(s["fields"]) for s in state["sections"])
        self.assertEqual(drawn, state["value_count"])
        self.assertGreater(drawn, 60)

    def test_every_control_carries_the_file_s_own_comment(self):
        state = view.state(self.store)
        for section in state["sections"]:
            for entry in section["fields"]:
                self.assertTrue(entry["help"], entry["key"])

    def test_a_bounded_feel_value_gets_a_slider_with_its_stops(self):
        entry = self.field(view.state(self.store), "player.bob_vertical_metres")
        self.assertEqual(entry["control"], "slider")
        self.assertEqual((entry["min"], entry["max"], entry["step"]), (0, 0.08, 0.001))

    def test_a_hit_point_total_gets_a_number_box_rather_than_a_slider(self):
        entry = self.field(view.state(self.store), "nest.health")
        self.assertEqual(entry["control"], "number")
        self.assertEqual(entry["step"], 1)

    def test_a_flag_gets_a_switch(self):
        self.assertEqual(
            self.field(view.state(self.store), "player.sprint_is_toggle")["control"],
            "flag",
        )

    def test_a_quoted_string_gets_a_text_box_without_its_quotes(self):
        entry = self.field(view.state(self.store), "player.starting_stock")
        self.assertEqual(entry["control"], "text")
        self.assertEqual(entry["value"], "iron_plate:110")

    def test_nothing_is_marked_changed_on_a_fresh_checkout(self):
        state = view.state(self.store)
        self.assertEqual(state["changed_count"], 0)
        self.assertEqual(state["drift"], [])

    def test_marks_what_was_touched_and_remembers_the_default(self):
        self.store.set_value("nest.health", "9000")
        state = view.state(self.store)
        entry = self.field(state, "nest.health")
        self.assertEqual(state["changed_count"], 1)
        self.assertTrue(entry["changed"])
        self.assertEqual((entry["value"], entry["default"]), ("9000", "6000"))

    def test_counts_what_changed_per_section_so_the_nav_can_say_so(self):
        self.store.set_value("nest.health", "9000")
        counts = {s["name"]: s["changed"] for s in view.state(self.store)["sections"]}
        self.assertEqual(counts["nest"], 1)
        self.assertEqual(counts["player"], 0)

    def test_keeps_the_file_s_own_subheadings_in_place(self):
        """The file divides `[player]` with `── Weight ──` and
        `── The camera's response ──`. The page reads in the file's order, with
        the file's own headings, so somebody who knows the file knows the page."""
        player = view.state(self.store)["sections"][0]
        self.assertEqual(
            [note["heading"] for note in player["notes"] if note["heading"]],
            ["Weight", "The camera's response"],
        )

    def test_offers_the_history_newest_first(self):
        self.store.set_value("nest.health", "9000")
        self.store.set_value("nest.health", "9500")
        summaries = [h["summary"] for h in view.state(self.store)["history"]]
        self.assertEqual(
            summaries, ["nest.health 9000 → 9500", "nest.health 6000 → 9000"]
        )
