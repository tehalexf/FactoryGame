"""The deep check: the game's own loader, asked whether a candidate would load.

Seam: `definitions_check.Checker.errors(candidate)`, and the store with one
wired in. These need Godot, so they skip themselves when `godot` is not on PATH
— the subset gate is what holds in that case, and `test_store.py` covers it on
its own. They do *not* need the project to have been imported already: the
checker runs an import pass itself when there is no class cache, because
`check_definitions.gd` names `Definitions` and that global only resolves
through one.

The values asserted here are the loader's own refusals, read off
`sim/definitions.gd`'s cross-checks. The point of this layer is that those rules
are *not* restated in Python, so the only way to test it is to ask.
"""

import shutil
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import definitions_check, store  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
LIVE = REPO / "content" / "tuning.toml"


@unittest.skipUnless(shutil.which("godot"), "needs godot on PATH")
class AskingTheLoader(unittest.TestCase):
    def setUp(self):
        self.checker = definitions_check.Checker(REPO)
        self.shipped = LIVE.read_text(encoding="utf-8")

    def test_the_shipped_content_loads(self):
        self.assertEqual(self.checker.errors(self.shipped), [])

    def test_refuses_a_zero_the_subset_cannot_object_to(self):
        """`bob_stride_metres` is a divisor. `0` is a perfectly good decimal, so
        no TOML parser will ever complain about it — and `Definitions` refuses
        the whole set over it, which would strand the Run."""
        candidate = self.shipped.replace(
            "bob_stride_metres = 3.2", "bob_stride_metres = 0"
        )
        self.assertNotEqual(candidate, self.shipped)
        reported = self.checker.errors(candidate)
        self.assertEqual(len(reported), 1, reported)
        self.assertIn("a stride of nothing is a division by nothing", reported[0])

    def test_names_the_real_file_rather_than_the_directory_it_staged(self):
        candidate = self.shipped.replace(
            "bob_stride_metres = 3.2", "bob_stride_metres = 0"
        )
        self.assertIn("content/tuning.toml", self.checker.errors(candidate)[0])

    def test_leaves_the_live_file_alone(self):
        self.checker.errors(self.shipped.replace("health = 6000", "health = 1"))
        self.assertEqual(LIVE.read_text(encoding="utf-8"), self.shipped)


@unittest.skipUnless(shutil.which("godot"), "needs godot on PATH")
class AStoreWithTheDeepCheckWiredIn(unittest.TestCase):
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
            deep_check=definitions_check.Checker(REPO),
        )

    def tearDown(self):
        self._temp.cleanup()

    def test_accepts_a_value_the_game_accepts(self):
        self.store.set_value("player.bob_stride_metres", "2.4")
        self.assertIn("bob_stride_metres = 2.4", self.live.read_text(encoding="utf-8"))

    def test_refuses_a_value_the_game_refuses_and_writes_nothing(self):
        before = self.live.read_text(encoding="utf-8")
        with self.assertRaises(store.Refused) as caught:
            self.store.set_value("player.bob_stride_metres", "0")
        self.assertEqual(self.live.read_text(encoding="utf-8"), before)
        self.assertIn("a stride of nothing", "\n".join(caught.exception.errors))

    def test_refuses_a_cross_key_rule_no_single_value_could_fail(self):
        """Survey View has to be above eye level. 1.5 m is a fine camera height
        on its own and a refused definition set next to a 1.7 m eye."""
        with self.assertRaises(store.Refused):
            self.store.set_value("survey.height_metres", "1.5")
