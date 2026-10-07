"""The dashboard end to end, over HTTP, against a real file.

Seam: the HTTP API — `GET /`, `GET /api/state`, `POST /api/set|reset|restore`.
These drive the server the way the browser does, which is the only way to find
out that the page's one job (change a number in a file) actually happens.

The deep loader check is deliberately off here: these tests are about the HTTP
layer, and `test_definitions_check.py` is about the loader.
"""

import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tuning import server, store  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
LIVE = REPO / "content" / "tuning.toml"


class TheDashboardOverHttp(unittest.TestCase):
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
        # Port 0: the operating system picks a free one, so a suite running
        # beside a dashboard the player left open does not collide with it.
        self.http = server.serve(self.store, port=0)
        self.base = "http://127.0.0.1:%d" % self.http.server_address[1]
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join(timeout=5)
        self._temp.cleanup()

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=10) as response:
            return response.status, response.read()

    def post(self, path, body):
        request = urllib.request.Request(
            self.base + path,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())

    def test_serves_the_page(self):
        status, body = self.get("/")
        self.assertEqual(status, 200)
        self.assertIn(b"<title>DEEP FOUNDRY", body)

    def test_hands_the_page_every_value_in_the_file(self):
        _, body = self.get("/api/state")
        state = json.loads(body)["state"]
        self.assertTrue(state["ok"] if "ok" in state else True)
        self.assertGreater(state["value_count"], 60)
        self.assertEqual(state["changed_count"], 0)

    def test_a_change_lands_in_the_file(self):
        payload = self.post("/api/set", {"key": "nest.health", "value": "9000"})
        self.assertTrue(payload["ok"], payload)
        self.assertIn("health = 9000", self.live.read_text(encoding="utf-8"))
        self.assertEqual(payload["state"]["changed_count"], 1)

    def test_a_bad_value_is_answered_with_the_reason_and_not_written(self):
        before = self.live.read_text(encoding="utf-8")
        payload = self.post("/api/set", {"key": "nest.health", "value": "6000.5"})
        self.assertFalse(payload["ok"])
        self.assertIn("whole number", payload["detail"])
        self.assertEqual(self.live.read_text(encoding="utf-8"), before)

    def test_a_refusal_still_hands_back_the_state_so_the_page_stays_true(self):
        payload = self.post("/api/set", {"key": "nest.health", "value": "nonsense"})
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["state"]["changed_count"], 0)

    def test_resets_one_value(self):
        self.post("/api/set", {"key": "nest.health", "value": "9000"})
        payload = self.post("/api/reset", {"key": "nest.health"})
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["state"]["changed_count"], 0)

    def test_resets_everything(self):
        self.post("/api/set", {"key": "nest.health", "value": "9000"})
        self.post("/api/set", {"key": "player.jump_height_metres", "value": "2"})
        payload = self.post("/api/reset", {})
        self.assertEqual(payload["state"]["changed_count"], 0)
        self.assertEqual(
            self.live.read_text(encoding="utf-8"), LIVE.read_text(encoding="utf-8")
        )

    def test_rolls_back_to_a_listed_snapshot(self):
        self.post("/api/set", {"key": "nest.health", "value": "9000"})
        self.post("/api/set", {"key": "nest.health", "value": "9500"})
        state = json.loads(self.get("/api/state")[1])["state"]
        oldest = state["history"][-1]["id"]
        payload = self.post("/api/restore", {"id": oldest})
        self.assertTrue(payload["ok"], payload)
        self.assertIn("health = 6000", self.live.read_text(encoding="utf-8"))

    def test_refuses_a_snapshot_id_that_is_a_path(self):
        """The one string the page hands back that becomes a filename."""
        payload = self.post("/api/restore", {"id": "../../../etc/passwd"})
        self.assertFalse(payload["ok"])

    def test_a_flag_can_be_switched_from_the_page(self):
        payload = self.post("/api/set", {"key": "player.sprint_is_toggle", "value": False})
        self.assertTrue(payload["ok"], payload)
        self.assertIn("sprint_is_toggle = false", self.live.read_text(encoding="utf-8"))

    def test_a_quoted_string_can_be_edited_from_the_page(self):
        payload = self.post(
            "/api/set", {"key": "player.starting_stock", "value": "iron_plate:40"}
        )
        self.assertTrue(payload["ok"], payload)
        self.assertIn(
            'starting_stock = "iron_plate:40"', self.live.read_text(encoding="utf-8")
        )

    def test_an_unknown_path_is_a_404_rather_than_a_traceback(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.get("/../store.py")
        self.assertEqual(caught.exception.code, 404)
