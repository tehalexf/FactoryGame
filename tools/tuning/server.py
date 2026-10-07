"""The dashboard's HTTP layer. `http.server` and nothing else.

No framework, no build step, no npm — because a tuning surface that needs
installing is one that is not there when the player wants to drag a slider, and
because `tools/` in this repository is Python and bash and should stay that way.

**The file is the API.** Every request below ends in `store`, which ends in
`content/tuning.toml`, which `game/definition_watcher.gd` is already watching.
There is no socket into the running game and no handle on a Run: a change lands
because the file changed, which is why it works identically with the game
closed, with it running, and with two of them running.

Bound to the loopback interface only. Authentication and remote access are out of
scope for issue #31, and a tuning surface reachable from the network would need
both — so it is not reachable from the network.
"""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import view
from .store import Refused, TuningStore

HERE = Path(__file__).resolve().parent
PAGE = HERE / "dashboard.html"

## Writes are serialised. Two browser tabs, or a slider release racing a reset,
## must not interleave a snapshot with somebody else's rename.
_write_lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    server_version = "DeepFoundryTuning/1"
    store: TuningStore

    # ── Reading ───────────────────────────────────────────────────────────────

    def do_GET(self) -> None:  # noqa: N802 — http.server's spelling
        if self.path in ("/", "/index.html"):
            self._send(200, "text/html; charset=utf-8", PAGE.read_bytes())
            return
        if self.path == "/api/state":
            self._send_json(200, {"ok": True, "state": self._state()})
            return
        self._send_json(404, {"ok": False, "detail": "no such path"})

    # ── Writing ───────────────────────────────────────────────────────────────

    def do_POST(self) -> None:  # noqa: N802
        try:
            body = self._read_json()
        except ValueError as problem:
            self._send_json(400, {"ok": False, "detail": str(problem)})
            return

        actions = {
            "/api/set": self._set,
            "/api/reset": self._reset,
            "/api/restore": self._restore,
        }
        action = actions.get(self.path)
        if action is None:
            self._send_json(404, {"ok": False, "detail": "no such path"})
            return

        try:
            with _write_lock:
                action(body)
        except Refused as refusal:
            # 200 with `ok: false`: a refusal is an answer the page draws, not a
            # transport failure, and it carries the game's own error text.
            self._send_json(
                200,
                {
                    "ok": False,
                    "detail": refusal.detail,
                    "errors": refusal.errors,
                    "state": self._state(),
                },
            )
            return
        except (OSError, KeyError, ValueError) as problem:
            self._send_json(
                200,
                {
                    "ok": False,
                    "detail": "%s: %s" % (type(problem).__name__, problem),
                    "state": self._state(),
                },
            )
            return

        self._send_json(200, {"ok": True, "state": self._state()})

    def _set(self, body: dict) -> None:
        self.store.set_value(_text(body, "key"), _text(body, "value"))

    def _reset(self, body: dict) -> None:
        key = body.get("key") or ""
        if key:
            self.store.reset(str(key))
        else:
            self.store.reset_all()

    def _restore(self, body: dict) -> None:
        self.store.restore(_text(body, "id"))

    # ── Plumbing ──────────────────────────────────────────────────────────────

    def _state(self) -> dict:
        return view.state(self.store)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        if length > 1 << 20:
            raise ValueError("request too large")
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as problem:
            raise ValueError("malformed JSON: %s" % problem) from problem
        if not isinstance(body, dict):
            raise ValueError("expected a JSON object")
        return body

    def _send_json(self, status: int, payload: dict) -> None:
        self._send(
            status,
            "application/json; charset=utf-8",
            json.dumps(payload).encode("utf-8"),
        )

    def _send(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        """Quiet. The useful log is the history list in the page, and a line per
        slider tick would bury the one message that matters — a refusal."""
        return


def _text(body: dict, name: str) -> str:
    value = body.get(name)
    if value is None:
        raise ValueError('missing "%s"' % name)
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def serve(store: TuningStore, host: str = "127.0.0.1", port: int = 8765):
    """A server bound and ready. Call `serve_forever` on it."""
    handler = type("BoundHandler", (Handler,), {"store": store})
    return ThreadingHTTPServer((host, port), handler)
