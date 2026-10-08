"""The layer that can silently destroy a session's work: reading, validating,
writing, resetting and rolling back `content/tuning.toml`.

Seam: `store.TuningStore` — `read`, `set_value`, `reset`, `reset_all`,
`history`, `restore`, `changed_from_default`. The HTTP layer calls nothing else,
and nothing else touches the file.

What these tests are really guarding: a malformed write means `Definitions`
refuses the whole set, so the Run is stuck on its last good content with no way
back but a text editor. Every refusal test below is that failure, prevented.
"""

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import store  # noqa: E402

REPO = Path(__file__).resolve().parents[3]

DEFAULTS = """\
[player]

# How fast a player walks, in metres per second.
walk_speed_metres_per_second = 4

# What a player starts a Run carrying.
starting_stock = "iron_plate:80"

# Whether the sprint key is a toggle.
sprint_is_toggle = true

[nest]

# The Nest's hit points.
health = 6000
"""


class StoreFixture(unittest.TestCase):
    def setUp(self):
        self._temp = TemporaryDirectory()
        root = Path(self._temp.name)
        self.live = root / "content" / "tuning.toml"
        self.live.parent.mkdir(parents=True)
        self.live.write_text(DEFAULTS, encoding="utf-8")
        self.defaults = root / "defaults" / "tuning.toml"
        self.defaults.parent.mkdir(parents=True)
        self.defaults.write_text(DEFAULTS, encoding="utf-8")
        self.history_dir = root / "history"
        self.store = store.TuningStore(
            live_path=self.live,
            defaults_path=self.defaults,
            history_dir=self.history_dir,
            # The real loader, because which keys are whole numbers is its
            # decision and the fixture's keys are real keys.
            definitions_gd=REPO / "sim" / "definitions.gd",
        )

    def tearDown(self):
        self._temp.cleanup()


class WritingAValue(StoreFixture):
    def test_lands_in_the_file_so_the_watcher_sees_it(self):
        self.store.set_value("nest.health", "7000")
        self.assertIn("health = 7000", self.live.read_text(encoding="utf-8"))

    def test_leaves_every_comment_in_place(self):
        self.store.set_value("nest.health", "7000")
        self.assertIn("# The Nest's hit points.", self.live.read_text(encoding="utf-8"))

    def test_a_decimal_is_written_as_a_decimal(self):
        self.store.set_value("player.walk_speed_metres_per_second", "4.5")
        self.assertIn(
            "walk_speed_metres_per_second = 4.5", self.live.read_text(encoding="utf-8")
        )

    def test_a_string_is_written_quoted(self):
        self.store.set_value("player.starting_stock", "iron_plate:40;coal:10")
        self.assertIn(
            'starting_stock = "iron_plate:40;coal:10"',
            self.live.read_text(encoding="utf-8"),
        )

    def test_a_boolean_is_written_unquoted(self):
        self.store.set_value("player.sprint_is_toggle", "false")
        self.assertIn("sprint_is_toggle = false", self.live.read_text(encoding="utf-8"))

    def test_writes_through_a_temporary_file_and_a_rename(self):
        """The watcher digests whatever it finds. A half-written file caught
        mid-save is a definition set with no definitions in it, so the file the
        game can see is only ever a complete one."""
        self.store.set_value("nest.health", "7000")
        self.assertEqual(
            sorted(p.name for p in self.live.parent.iterdir()), ["tuning.toml"]
        )


class RefusingABadValue(StoreFixture):
    def assertRefused(self, key, text):
        before = self.live.read_text(encoding="utf-8")
        with self.assertRaises(store.Refused) as caught:
            self.store.set_value(key, text)
        self.assertEqual(self.live.read_text(encoding="utf-8"), before)
        return caught.exception

    def test_refuses_a_value_outside_the_accepted_subset(self):
        refusal = self.assertRefused("nest.health", "lots")
        self.assertIn("outside the supported subset", str(refusal))

    def test_refuses_an_array_even_though_it_is_valid_toml(self):
        self.assertRefused("nest.health", "[1, 2]")

    def test_refuses_a_whole_number_written_where_a_whole_number_is_read(self):
        """`nest.health` is read with `require_int`, so `6000.5` would load as a
        FIXED and the game would report `"nest.health" must be a whole number`.
        The dashboard refuses it before it reaches the file."""
        refusal = self.assertRefused("nest.health", "6000.5")
        self.assertIn("whole number", str(refusal))

    def test_refuses_a_newline_that_would_split_the_line_in_two(self):
        self.assertRefused("nest.health", "7000\nhealth = 1")

    def test_refuses_a_comment_marker_that_would_swallow_the_value(self):
        self.assertRefused("nest.health", "7000 # sneaky")

    def test_refuses_a_quote_inside_a_string(self):
        self.assertRefused("player.starting_stock", 'iron"plate:80')

    def test_refuses_a_boolean_that_is_not_true_or_false(self):
        self.assertRefused("player.sprint_is_toggle", "yes")

    def test_refuses_a_key_the_file_does_not_define(self):
        with self.assertRaises(store.Refused):
            self.store.set_value("nest.invented", "1")

    def test_refuses_a_magnitude_fixed_point_could_not_hold(self):
        """Past `Fixed.MUL_OPERAND_LIMIT` a quantity cannot be an operand of
        `Fixed.mul`, so the overflow would happen in the Simulation rather than
        in the file, where nobody would connect it to the number they typed."""
        self.assertRefused("player.walk_speed_metres_per_second", "99999999999.0")

    def test_a_refusal_writes_no_history_entry(self):
        with self.assertRaises(store.Refused):
            self.store.set_value("nest.health", "lots")
        self.assertEqual(self.store.history(), [])


class ShowingWhatChanged(StoreFixture):
    def test_nothing_is_changed_in_a_fresh_checkout(self):
        self.assertEqual(self.store.changed_from_default(), {})

    def test_names_the_value_and_the_default_it_came_from(self):
        self.store.set_value("nest.health", "7000")
        self.assertEqual(
            self.store.changed_from_default(), {"nest.health": ("7000", "6000")}
        )

    def test_a_value_set_back_to_its_default_by_hand_is_not_changed(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "6000")
        self.assertEqual(self.store.changed_from_default(), {})


class ResettingToShippedDefaults(StoreFixture):
    def test_puts_one_value_back(self):
        self.store.set_value("nest.health", "7000")
        self.store.reset("nest.health")
        self.assertIn("health = 6000", self.live.read_text(encoding="utf-8"))

    def test_puts_every_value_back_at_once(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("player.walk_speed_metres_per_second", "9")
        self.store.reset_all()
        self.assertEqual(self.live.read_text(encoding="utf-8"), DEFAULTS)

    def test_a_global_reset_is_itself_undoable(self):
        """The one destructive button on the page. It snapshots first, exactly as
        a single edit does, so an hour of tuning thrown away by a misclick is one
        restore away."""
        self.store.set_value("nest.health", "7000")
        self.store.reset_all()
        self.store.restore(self.store.history()[0].snapshot_id)
        self.assertIn("health = 7000", self.live.read_text(encoding="utf-8"))


class RollingBack(StoreFixture):
    def test_snapshots_the_file_before_each_write(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "8000")
        self.assertEqual(len(self.store.history()), 2)

    def test_lists_the_newest_first_and_says_what_each_write_changed(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("player.walk_speed_metres_per_second", "9")
        self.assertEqual(
            [entry.summary for entry in self.store.history()],
            [
                "player.walk_speed_metres_per_second 4 → 9",
                "nest.health 6000 → 7000",
            ],
        )

    def test_restores_the_file_as_it_was_before_that_write(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "8000")
        oldest = self.store.history()[-1]
        self.store.restore(oldest.snapshot_id)
        self.assertIn("health = 6000", self.live.read_text(encoding="utf-8"))

    def test_a_restore_is_itself_a_write_so_it_can_be_undone(self):
        self.store.set_value("nest.health", "7000")
        self.store.restore(self.store.history()[0].snapshot_id)
        self.store.restore(self.store.history()[0].snapshot_id)
        self.assertIn("health = 7000", self.live.read_text(encoding="utf-8"))

    def test_refuses_to_restore_a_snapshot_outside_the_accepted_subset(self):
        """A snapshot is a file somebody could have hand-edited between
        sessions. It is validated on the way back in, like anything else."""
        self.store.set_value("nest.health", "7000")
        snapshot = self.store.history()[0]
        path = self.history_dir / ("%s.toml" % snapshot.snapshot_id)
        path.write_text("[nest]\nhealth = [1]\n", encoding="utf-8")
        with self.assertRaises(store.Refused):
            self.store.restore(snapshot.snapshot_id)

    def test_refuses_a_snapshot_id_it_does_not_have(self):
        with self.assertRaises(store.Refused):
            self.store.restore("not-a-snapshot")

    def test_history_survives_a_new_store_over_the_same_directory(self):
        self.store.set_value("nest.health", "7000")
        reopened = store.TuningStore(
            live_path=self.live,
            defaults_path=self.defaults,
            history_dir=self.history_dir,
            definitions_gd=REPO / "sim" / "definitions.gd",
        )
        self.assertEqual(len(reopened.history()), 1)


class AKeyTheLoaderDoesNotMention(StoreFixture):
    """A key added to the tuning file and not yet read by anything is a
    *warning* in the game, not an error, so the dashboard still lets it be
    tuned — as a number, the widest numeric reading of how it is written."""

    def setUp(self):
        super().setUp()
        self.live.write_text(DEFAULTS + "\n# Not read yet.\nspare = 3\n", "utf-8")
        self.defaults.write_text(DEFAULTS + "\n# Not read yet.\nspare = 3\n", "utf-8")

    def test_accepts_a_decimal_where_the_default_is_a_whole_number(self):
        self.store.set_value("nest.spare", "3.5")
        self.assertIn("spare = 3.5", self.live.read_text(encoding="utf-8"))

    def test_still_refuses_what_the_subset_refuses(self):
        with self.assertRaises(store.Refused):
            self.store.set_value("nest.spare", "[3]")


class AgainstTheRealRepository(unittest.TestCase):
    def test_the_shipped_defaults_match_the_shipped_tuning_file(self):
        """`tools/tuning/defaults/tuning.toml` is what reset goes back to. It is
        a committed copy rather than a git lookup so the dashboard works in any
        checkout and with no repository at all — which means it can fall out of
        step, and this is what notices. Re-baseline deliberately with
        `python3 tools/tuning_dashboard.py --adopt-defaults`."""
        live = (REPO / "content" / "tuning.toml").read_text(encoding="utf-8")
        shipped = (
            REPO / "tools" / "tuning" / "defaults" / "tuning.toml"
        ).read_text(encoding="utf-8")
        self.assertEqual(
            sorted(_values(live)),
            sorted(_values(shipped)),
            "defaults and content/tuning.toml declare different keys",
        )

    def test_every_key_in_the_file_is_reachable_from_the_default_store(self):
        opened = store.open_repository(REPO)
        self.assertGreater(len(opened.read().fields()), 60)
        self.assertEqual(opened.unknown_defaults(), [])


def _values(source):
    from tuning import tuning_file

    return [f.key for f in tuning_file.TuningFile.parse(source, "x").fields()]


class SnapshotsTakenInsideOneMillisecond(StoreFixture):
    """Two writes close enough together to share a snapshot id stem.

    The id is a UTC timestamp to the millisecond, and a second write inside the
    same millisecond gets `-1` appended. `history()` used to order those by
    sorting the `*.json` paths, which compares the extension too — and `-` is
    0x2D while `.` is 0x2E, so `...123-1.json` sorts *before* `...123.json` and
    a reverse sort puts the **older** snapshot first. `history()` promises
    newest first and the page's undo button restores `history()[0]`, so a tie
    rolled back the wrong edit: it discarded the second-newest change and kept
    the newest.

    Whether two writes land in one millisecond is a question about how fast the
    machine is, which is why this surfaced as the same commit passing one CI run
    and failing the next. The clock is pinned here so it is not a question at
    all, and `test_the_oldest_entry_still_undoes_everything` fails with the exact
    text that CI reported.
    """

    def setUp(self):
        super().setUp()
        frozen = datetime(2026, 10, 8, 12, 0, 0, 123456, tzinfo=timezone.utc)

        class Frozen(datetime):
            @classmethod
            def now(cls, tz=None):
                return frozen

        self._real_datetime = store.datetime
        store.datetime = Frozen
        self.addCleanup(self._restore_clock)

    def _restore_clock(self):
        store.datetime = self._real_datetime

    def test_history_is_newest_first(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "8000")
        self.assertEqual(
            [entry.summary for entry in self.store.history()],
            ["nest.health 7000 → 8000", "nest.health 6000 → 7000"],
        )

    def test_the_oldest_entry_still_undoes_everything(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "8000")
        self.store.restore(self.store.history()[-1].snapshot_id)
        self.assertIn("health = 6000", self.live.read_text(encoding="utf-8"))

    def test_undoing_the_newest_entry_puts_back_the_write_before_it(self):
        self.store.set_value("nest.health", "7000")
        self.store.set_value("nest.health", "8000")
        self.store.restore(self.store.history()[0].snapshot_id)
        self.assertIn("health = 7000", self.live.read_text(encoding="utf-8"))

    def test_pruning_still_drops_the_oldest_and_keeps_the_newest(self):
        """`_prune` sorts bare stems, not filenames, so it was already right —
        a stem is a prefix of its own `-1` and a prefix sorts first. Pinned here
        so that it stays right for a reason rather than by coincidence."""
        self.store.history_limit = 2
        for health in ("7000", "8000", "9000"):
            self.store.set_value("nest.health", health)
        self.assertEqual(
            [entry.summary for entry in self.store.history()],
            ["nest.health 8000 → 9000", "nest.health 7000 → 8000"],
        )
