"""Reading, validating, writing, resetting and rolling back `content/tuning.toml`.

This is the whole of the dashboard's contact with the file, and it is the part
that can quietly destroy a session's work, so it is arranged around one fact:

**A malformed definition set carries no definitions.** `Definitions` gathers
every error and then hands back nothing rather than half a set, the running game
refuses the reload, and the Run is stuck on its last good content. So a bad value
must never reach the file at all, and a good value must land whole or not land.

Four guards, in order:

1. **The value is encoded for its kind** — a string gets its quotes, a whole
   number stays whole — and a kind that cannot hold what was typed is refused by
   name before anything is rendered.
2. **The rendered file is re-parsed with the game's own subset** (`toml_subset`,
   a port of `sim/toml_document.gd`) and refused on any error. Re-parsing the
   whole file rather than checking the one value is deliberate: a renderer bug
   that mangled an unrelated line is exactly the failure that strands a Run.
3. **Every other value has to come back out unchanged**, and the one that
   changed has to read back as what was asked for. That catches a value that
   parses but means something else — `7000 # sneaky` reads back as `7000`.
4. **The write is atomic**: a temporary file in the same directory, flushed and
   fsynced, then renamed over the original. `game/definition_watcher.gd` digests
   whatever it finds whenever it looks, so a half-written file caught mid-save
   would be a definition set with no definitions in it.

And one safety net behind all four: **every write snapshots the file first**, so
anything this layer gets wrong is one restore away rather than gone.
"""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from . import key_kinds, toml_subset
from .tuning_file import TuningFile


class Refused(Exception):
    """A write that did not happen, and the reason, named the way the game would
    name it. Nothing was written, and no history entry was made."""

    def __init__(self, detail: str, errors: list[str] | None = None):
        super().__init__(detail)
        self.detail = detail
        self.errors = errors or []


@dataclass(frozen=True)
class Snapshot:
    """The file as it was before one write."""

    snapshot_id: str
    ## What the write that followed it did, for the history list.
    summary: str
    written_at: str


class TuningStore:
    def __init__(
        self,
        live_path: Path,
        defaults_path: Path,
        history_dir: Path,
        definitions_gd: Path | None = None,
        history_limit: int = 500,
        deep_check=None,
    ):
        self.live_path = Path(live_path)
        self.defaults_path = Path(defaults_path)
        self.history_dir = Path(history_dir)
        self.history_limit = history_limit
        self._kinds = key_kinds.load(definitions_gd) if definitions_gd else {}
        ## Something with `.errors(candidate) -> list[str]` and `.available`, or
        ## None. See `definitions_check`: it asks the game's own loader whether
        ## the candidate would load, which catches the rules the subset cannot
        ## see — a stride of 0, a Survey View below eye level.
        self.deep_check = deep_check

    # ── Reading ───────────────────────────────────────────────────────────────

    def read(self) -> TuningFile:
        return TuningFile.parse(
            self.live_path.read_text(encoding="utf-8"), str(self.live_path)
        )

    def defaults(self) -> TuningFile:
        return TuningFile.parse(
            self.defaults_path.read_text(encoding="utf-8"), str(self.defaults_path)
        )

    def required_kind(self, key: str) -> str:
        """The kind `Definitions` reads this key as.

        A key the loader does not mention falls back to the kind it is written
        as in the shipped defaults, widened so a whole number may become a
        decimal. That is the right degradation: a key added to the tuning file
        and not yet read by anything is a *warning* in the game, not an error,
        and the dashboard should still let it be tuned.
        """
        if key in self._kinds:
            return self._kinds[key]
        shipped = self.defaults()
        if shipped.has(key):
            written = shipped.field(key).kind
            if written == toml_subset.KIND_INTEGER:
                return toml_subset.KIND_FIXED
            return written
        return toml_subset.KIND_FIXED

    def changed_from_default(self) -> dict[str, tuple[str, str]]:
        """Every value that differs from the shipped default, as
        `key → (now, default)`.

        This is what the page marks. After an hour of tuning it is the only
        honest answer to "what did I actually touch?", and it is computed from
        the file rather than remembered, so it is still right after a restore, a
        hand edit in a text editor, or a git checkout.
        """
        live = self.read()
        shipped = self.defaults()
        changed: dict[str, tuple[str, str]] = {}
        for entry in live.fields():
            if not shipped.has(entry.key):
                continue
            default = shipped.field(entry.key).source
            if entry.source != default:
                changed[entry.key] = (entry.source, default)
        return changed

    def unknown_defaults(self) -> list[str]:
        """Keys the defaults file declares that the live file does not. A
        non-empty list means the two have drifted and reset would be a lie."""
        live = self.read()
        return sorted(f.key for f in self.defaults().fields() if not live.has(f.key))

    # ── Writing ───────────────────────────────────────────────────────────────

    def set_value(self, key: str, value_text: str) -> None:
        """Set one key from what the control holds — the string's contents
        without its quotes, the number as typed, `true` or `false`.

        Refuses rather than writes on anything the game would not accept.
        """
        live = self.read()
        if not live.has(key):
            raise Refused('%s defines no key "%s"' % (self.live_path.name, key))

        source_text = self._encode(key, value_text)
        before = live.field(key).source
        if source_text == before:
            return
        candidate = live.with_value(key, source_text).render()
        self._check(candidate, live, {key: source_text})
        self._write(
            candidate,
            summary="%s %s → %s" % (key, _plain(before), _plain(source_text)),
            key=key,
        )

    def reset(self, key: str) -> None:
        """One value back to its shipped default."""
        shipped = self.defaults()
        if not shipped.has(key):
            raise Refused('the shipped defaults declare no key "%s"' % key)
        live = self.read()
        if not live.has(key):
            raise Refused('%s defines no key "%s"' % (self.live_path.name, key))
        source_text = shipped.field(key).source
        before = live.field(key).source
        if source_text == before:
            return
        candidate = live.with_value(key, source_text).render()
        self._check(candidate, live, {key: source_text})
        self._write(
            candidate,
            summary="%s reset to %s" % (key, _plain(source_text)),
            key=key,
        )

    def reset_all(self) -> None:
        """Every value back to its shipped default, by restoring the shipped file
        itself — comments, order and all.

        The one destructive button on the page, so it snapshots first exactly as
        a single edit does. An hour of tuning thrown away by a misclick is one
        restore away.
        """
        candidate = self.defaults_path.read_text(encoding="utf-8")
        errors = toml_subset.validate(candidate, str(self.defaults_path))
        if errors:
            raise Refused("the shipped defaults are not loadable", errors)
        if candidate == self.live_path.read_text(encoding="utf-8"):
            return
        self._check_deeply(candidate)
        self._write(candidate, summary="reset everything to shipped defaults", key="")

    # ── Rollback ──────────────────────────────────────────────────────────────

    def history(self) -> list[Snapshot]:
        """Every snapshot, newest first. Each one is the file as it was *before*
        the write its summary describes, so restoring the first entry undoes the
        most recent change."""
        if not self.history_dir.is_dir():
            return []
        entries: list[Snapshot] = []
        metas = sorted(
            self.history_dir.glob("*.json"),
            key=lambda path: _age_key(path.stem),
            reverse=True,
        )
        for meta_path in metas:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            entries.append(
                Snapshot(
                    snapshot_id=meta_path.stem,
                    summary=meta.get("summary", ""),
                    written_at=meta.get("written_at", ""),
                )
            )
        return entries

    def restore(self, snapshot_id: str) -> None:
        """Put a snapshot back, as a write — so it snapshots the current file
        first and can itself be undone.

        The snapshot is validated on the way in. It is a file on disk somebody
        could have hand-edited between sessions, and restoring it unchecked
        would be the one hole in everything above.
        """
        path = self._snapshot_path(snapshot_id)
        if path is None:
            raise Refused('no snapshot "%s"' % snapshot_id)
        candidate = path.read_text(encoding="utf-8")
        errors = toml_subset.validate(candidate, str(path))
        if errors:
            raise Refused("that snapshot is not loadable", errors)
        live = self.read()
        reparsed = TuningFile.parse(candidate, str(path))
        missing = [f.key for f in live.fields() if not reparsed.has(f.key)]
        if missing:
            raise Refused(
                "that snapshot is missing %d of the keys the file defines: %s"
                % (len(missing), ", ".join(missing[:5]))
            )
        self._check_deeply(candidate)
        self._write(candidate, summary="restored %s" % snapshot_id, key="")

    # ── The guards ────────────────────────────────────────────────────────────

    def _encode(self, key: str, value_text: str) -> str:
        """What the control holds, as TOML source for this key's kind."""
        kind = self.required_kind(key)
        text = value_text.strip()

        if kind == toml_subset.KIND_STRING:
            if '"' in value_text:
                raise Refused(
                    'a quoted string cannot contain a " — the subset has no escapes'
                )
            if "\n" in value_text or "\r" in value_text:
                raise Refused("a tuning value cannot contain a newline")
            return '"%s"' % value_text

        value = toml_subset.classify(text)
        if value is None:
            raise Refused(
                'value "%s" is outside the supported subset '
                '(integer, decimal, "string", true, false)' % text
            )
        if value.kind not in key_kinds.ACCEPTS[kind]:
            raise Refused(
                '"%s" must be %s' % (key, key_kinds.DESCRIBED[kind])
            )
        if value.kind in (toml_subset.KIND_INTEGER, toml_subset.KIND_FIXED):
            self._check_magnitude(key, value)
        return text

    def _check_magnitude(self, key: str, value: toml_subset.Value) -> None:
        """Past `Fixed.MUL_OPERAND_LIMIT` a quantity cannot be an operand of
        `Fixed.mul`, so an overflow would happen somewhere in the Simulation
        rather than here, where nobody would connect it to the number typed."""
        quantity = (
            value.number
            if value.kind == toml_subset.KIND_FIXED
            else value.number * toml_subset.ONE
        )
        if abs(quantity) > toml_subset.MUL_OPERAND_LIMIT:
            raise Refused(
                '"%s" is too large for a fixed-point quantity (the limit is about %d)'
                % (key, toml_subset.MUL_OPERAND_LIMIT // toml_subset.ONE)
            )

    def _check(
        self, candidate: str, live: TuningFile, expected: dict[str, str]
    ) -> None:
        errors = toml_subset.validate(candidate, str(self.live_path))
        if errors:
            raise Refused("that would not load", errors)

        reparsed = TuningFile.parse(candidate, str(self.live_path))
        if reparsed.keys() != live.keys():
            raise Refused("that would change which keys the file defines")
        for entry in live.fields():
            want = expected.get(entry.key, entry.source)
            if reparsed.field(entry.key).source != want:
                raise Refused(
                    '"%s" would read back as %s rather than %s'
                    % (entry.key, reparsed.field(entry.key).source, want)
                )

        self._check_deeply(candidate)

    def _check_deeply(self, candidate: str) -> None:
        """The game's own loader's verdict, when there is a Godot to ask."""
        if self.deep_check is None or not getattr(self.deep_check, "available", True):
            return
        reported = self.deep_check.errors(candidate)
        if reported:
            raise Refused("the game would refuse this definition set", reported)

    # ── The write itself ──────────────────────────────────────────────────────

    def _write(self, candidate: str, summary: str, key: str) -> None:
        snapshot_id = self._snapshot(summary)
        directory = self.live_path.parent
        handle, temp_name = tempfile.mkstemp(
            dir=str(directory), prefix=".tuning-", suffix=".toml"
        )
        try:
            with os.fdopen(handle, "w", encoding="utf-8", newline="") as temp:
                temp.write(candidate)
                temp.flush()
                os.fsync(temp.fileno())
            os.replace(temp_name, self.live_path)
        except BaseException:
            Path(temp_name).unlink(missing_ok=True)
            raise
        self._prune()
        del snapshot_id, key

    def _snapshot(self, summary: str) -> str:
        self.history_dir.mkdir(parents=True, exist_ok=True)
        now = datetime.now(timezone.utc)
        stem = now.strftime("%Y%m%d-%H%M%S-") + "%03d" % (now.microsecond // 1000)
        snapshot_id = stem
        attempt = 0
        while (self.history_dir / ("%s.toml" % snapshot_id)).exists():
            attempt += 1
            snapshot_id = "%s-%d" % (stem, attempt)
        (self.history_dir / ("%s.toml" % snapshot_id)).write_text(
            self.live_path.read_text(encoding="utf-8"), encoding="utf-8"
        )
        (self.history_dir / ("%s.json" % snapshot_id)).write_text(
            json.dumps({"summary": summary, "written_at": now.isoformat()}, indent=1),
            encoding="utf-8",
        )
        return snapshot_id

    def _snapshot_path(self, snapshot_id: str) -> Path | None:
        """The snapshot's file, or None. Guards the id rather than trusting it:
        this one string arrives over HTTP and is turned into a path."""
        if not snapshot_id or any(c in snapshot_id for c in "/\\.\0"):
            return None
        path = self.history_dir / ("%s.toml" % snapshot_id)
        return path if path.is_file() else None

    def _prune(self) -> None:
        """Keep the newest `history_limit` snapshots. A long tuning session is
        hundreds of small writes, and none of them are worth unbounded disk."""
        stems = sorted(
            (p.stem for p in self.history_dir.glob("*.toml")),
            key=_age_key,
            reverse=True,
        )
        for stem in stems[self.history_limit :]:
            (self.history_dir / ("%s.toml" % stem)).unlink(missing_ok=True)
            (self.history_dir / ("%s.json" % stem)).unlink(missing_ok=True)


def _age_key(snapshot_id: str) -> tuple[str, int]:
    """How old a snapshot is, for sorting. Newest sorts largest.

    A snapshot id is `YYYYmmdd-HHMMSS-mmm`, and a second write inside the same
    millisecond gets `-1` appended. Ordering those by filename is a trap, and
    `history()` fell into it: it sorted the `*.json` paths, where the extension
    is part of the comparison, and `-` is 0x2D while `.` is 0x2E — so
    `...123-1.json` sorts *before* `...123.json` and a reverse sort hands back
    the older snapshot as the newest. The page's undo button restores
    `history()[0]`, so a tie rolled back the wrong edit: it discarded the
    second-newest change and kept the newest.

    Comparing the stem as a string and the counter as a number is correct
    whatever is appended to it. An id with no counter is the first write of its
    millisecond, hence 0; anything that does not parse keeps its whole stem and
    sorts as if it had no counter, which is what the old code did for anything
    hand-dropped into the directory.

    `_prune` sorts bare stems rather than filenames, so it was never wrong — a
    stem is a prefix of its own `-1`, and a prefix sorts first. It uses this key
    anyway, so that staying correct does not depend on noticing that.
    """
    pieces = snapshot_id.split("-")
    if len(pieces) == 4 and pieces[3].isdigit():
        return ("-".join(pieces[:3]), int(pieces[3]))
    return (snapshot_id, 0)


def _plain(source: str) -> str:
    """A value as it reads in a history line — without a string's quotes."""
    if len(source) >= 2 and source.startswith('"') and source.endswith('"'):
        return source[1:-1]
    return source


def open_repository(repo: Path, deep: bool = True) -> TuningStore:
    """The store this repository's dashboard uses.

    `deep=False` drops the Godot loader check — the subset gate still stands, and
    with it the atomic write and the snapshot before it.
    """
    from . import definitions_check

    repo = Path(repo)
    here = Path(__file__).resolve().parent
    return TuningStore(
        live_path=repo / "content" / "tuning.toml",
        defaults_path=here / "defaults" / "tuning.toml",
        history_dir=here / "history",
        definitions_gd=repo / "sim" / "definitions.gd",
        deep_check=definitions_check.Checker(repo) if deep else None,
    )
