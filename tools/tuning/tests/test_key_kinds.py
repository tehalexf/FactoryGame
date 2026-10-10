"""The kind each tuning key is read as, derived from `sim/definitions.gd`.

Seam: `key_kinds.load(path)`. Expected kinds below are read off the loader's own
`require_*` calls, which is the only thing that decides them.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import key_kinds, toml_subset, tuning_file  # noqa: E402

REPO = Path(__file__).resolve().parents[3]


class ReadingTheLoader(unittest.TestCase):
    def setUp(self):
        self.kinds = key_kinds.load(REPO / "sim" / "definitions.gd")

    def test_finds_a_whole_number_key(self):
        self.assertEqual(self.kinds["nest.health"], toml_subset.KIND_INTEGER)

    def test_finds_a_fixed_point_key_written_as_a_whole_number(self):
        """`walk_speed_metres_per_second = 4` is an integer in the file and is
        read with `require_fixed`, so `4.5` must be allowed in the browser. A
        kind table inferred from the file's own value would get this wrong."""
        self.assertEqual(
            self.kinds["player.walk_speed_metres_per_second"], toml_subset.KIND_FIXED
        )

    def test_finds_a_string_key(self):
        self.assertEqual(self.kinds["player.starting_stock"], toml_subset.KIND_STRING)

    def test_finds_a_boolean_key(self):
        self.assertEqual(
            self.kinds["player.sprint_is_toggle"], toml_subset.KIND_BOOLEAN
        )

    def test_finds_a_key_whose_constant_the_formatter_wrapped(self):
        """`TUNING_PLAYER_WALK_ACCELERATION` is declared across two lines because
        its value is too long for one. The derivation has to survive that."""
        self.assertEqual(
            self.kinds["player.walk_acceleration_metres_per_second_squared"],
            toml_subset.KIND_FIXED,
        )

    def test_covers_every_key_the_tuning_file_defines(self):
        """Also the game's own rule: a tuning key nothing reads is a warning,
        because a file carrying a number that does nothing lies to whoever is
        tuning it. If this fails, either the derivation broke or a key went
        unread — and both are worth knowing."""
        source = (REPO / "content" / "tuning.toml").read_text(encoding="utf-8")
        declared = {f.key for f in tuning_file.TuningFile.parse(source, "x").fields()}
        self.assertEqual(sorted(declared - set(self.kinds)), [])
