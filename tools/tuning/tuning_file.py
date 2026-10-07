"""`content/tuning.toml` as a thing a dashboard can draw, and as a thing one
value can be written back into without disturbing anything else.

Two properties hold this together.

**The file is the help copy.** Every key in the tuning file carries a prose
comment saying what raising it does, and that text is what the dashboard labels
its controls with. Nothing in this tool writes a second description of a tuning
value, because a second description is one that drifts from the file the moment
somebody edits one and not the other.

**A write rewrites one line.** The document is kept as the list of lines it was
read from, and setting a value replaces the value text inside the line that
defines it. Comments, blank lines, section order and trailing comments all come
back out exactly as they went in — so a day of tuning leaves a diff that reads as
a list of numbers that changed, and a renderer bug cannot silently eat a comment.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field as dataclass_field

from . import toml_subset

# `# ── Weight ───────` — the file's own in-section dividers.
_DIVIDER = re.compile(r"^[─\-=]{2,}\s*(.*?)\s*[─\-=]{2,}$")


@dataclass
class Field:
    """One `section.key = value`, with the comment that explains it."""

    key: str
    section: str
    name: str
    kind: str
    ## The value exactly as written in the file, e.g. `1.5` or `"iron_plate:80"`.
    source: str
    ## The file's own comment for this key, as plain text. The dashboard's label.
    help: str
    ## Index into the document's line list, so a write knows what to rewrite.
    line_index: int

    @property
    def line_number(self) -> int:
        return self.line_index + 1

    @property
    def value_text(self) -> str:
        """The value without its quotes for a string, as written otherwise.

        What a control is populated with: a text box for `starting_stock` shows
        `iron_plate:80`, not `"iron_plate:80"`.
        """
        if self.kind == toml_subset.KIND_STRING:
            return self.source[1:-1]
        return self.source


@dataclass
class Note:
    """Prose in a section that belongs to no single key — the file's own
    commentary, including its `── Weight ──` style dividers."""

    heading: str
    body: str
    ## Where the note sits relative to the fields, so the page reads in file order.
    position: int


@dataclass
class Section:
    name: str
    notes: list[Note] = dataclass_field(default_factory=list)
    fields: list[Field] = dataclass_field(default_factory=list)


class TuningFile:
    """A parsed tuning file. Immutable in practice: `with_value` returns a new
    document rather than editing this one, so a refused write cannot leave a
    half-edited document behind."""

    def __init__(self, lines: list[str], path: str, trailing_newline: bool):
        self._lines = lines
        self._path = path
        self._trailing_newline = trailing_newline
        self._sections: list[Section] = []
        self._by_key: dict[str, Field] = {}
        self.preamble: str = ""

    # ── Reading ───────────────────────────────────────────────────────────────

    @staticmethod
    def parse(source: str, path: str) -> "TuningFile":
        trailing_newline = source.endswith("\n")
        body = source[:-1] if trailing_newline else source
        doc = TuningFile(body.split("\n"), path, trailing_newline)
        doc._read()
        return doc

    def render(self) -> str:
        text = "\n".join(self._lines)
        return text + "\n" if self._trailing_newline else text

    def sections(self) -> list[Section]:
        return self._sections

    def fields(self) -> list[Field]:
        return [f for section in self._sections for f in section.fields]

    def keys(self) -> list[str]:
        return [f.key for f in self.fields()]

    def has(self, key: str) -> bool:
        return key in self._by_key

    def field(self, key: str) -> Field:
        return self._by_key[key]

    # ── Writing ───────────────────────────────────────────────────────────────

    def with_value(self, key: str, source_text: str) -> "TuningFile":
        """This document with one key's value replaced by `source_text`, which is
        TOML source — quotes and all for a string.

        Rewrites the value in place inside its own line, so a trailing comment on
        that line survives. Does *not* validate: `store` validates the rendered
        result, which is the only check that can see a renderer mistake.
        """
        if key not in self._by_key:
            raise KeyError("%s defines no key %r" % (self._path, key))
        if "\n" in source_text or "\r" in source_text:
            raise ValueError("a tuning value cannot contain a newline")

        target = self._by_key[key]
        line = self._lines[target.line_index]
        separator = line.find("=")
        before = line[: separator + 1]
        after = line[separator + 1 :]

        # Keep the original spacing around the value and any trailing comment.
        stripped = after.lstrip()
        leading_space = after[: len(after) - len(stripped)] or " "
        body = toml_subset.strip_comment(stripped)
        comment = stripped[len(body) :]
        trailing_space = body[len(body.rstrip()) :]

        lines = list(self._lines)
        lines[target.line_index] = (
            before + leading_space + source_text + trailing_space + comment
        )
        rewritten = TuningFile(lines, self._path, self._trailing_newline)
        rewritten._read()
        return rewritten

    # ── Parsing ───────────────────────────────────────────────────────────────

    def _read(self) -> None:
        self._sections = []
        self._by_key = {}
        self.preamble = ""

        section: Section | None = None
        ## Comment blocks seen since the last key line. The *last* one is "open"
        ## when no blank line closed it, and an open block is the help for the key
        ## that follows. Every other block is prose about the section.
        blocks: list[list[str]] = []
        open_block = False
        ## The help a run of consecutive key lines shares — the file writes pairs
        ## and triples of related keys under one comment, and both halves of
        ## `air_acceleration` / `air_deceleration` want that text.
        shared_help = ""

        for index, raw_line in enumerate(self._lines):
            stripped = raw_line.strip()

            if not stripped:
                # A blank line closes a comment block and ends a run of keys.
                open_block = False
                shared_help = ""
                continue

            if stripped.startswith("#"):
                if not open_block:
                    blocks.append([])
                    open_block = True
                blocks[-1].append(stripped[1:].strip())
                continue

            if stripped.startswith("["):
                self._flush_notes(blocks, section)
                blocks = []
                open_block = False
                shared_help = ""
                name = toml_subset.strip_comment(stripped).strip()[1:-1].strip()
                section = Section(name=name)
                self._sections.append(section)
                continue

            # A key line. A comment block flush against it is its help; anything
            # above that is the section's own prose.
            if open_block:
                shared_help = _as_prose(blocks.pop())
            self._flush_notes(blocks, section)
            blocks = []
            open_block = False
            self._read_pair(raw_line, index, section, shared_help)

        self._flush_notes(blocks, section)

    def _read_pair(
        self, raw_line: str, index: int, section: Section | None, help_text: str
    ) -> None:
        if section is None:
            return
        line = toml_subset.strip_comment(raw_line).strip()
        separator = line.find("=")
        if separator == -1:
            return
        name = line[:separator].strip()
        text = line[separator + 1 :].strip()
        value = toml_subset.classify(text)
        if value is None or not toml_subset.is_identifier(name):
            return

        key = "%s.%s" % (section.name, name)
        entry = Field(
            key=key,
            section=section.name,
            name=name,
            kind=value.kind,
            source=text,
            help=help_text,
            line_index=index,
        )
        section.fields.append(entry)
        self._by_key[key] = entry

    def _flush_notes(self, blocks: list[list[str]], section: Section | None) -> None:
        for block in blocks:
            self._flush_note(block, section)

    def _flush_note(self, pending: list[str], section: Section | None) -> None:
        """A comment block that no key follows. Before the first section it is the
        file's preamble; inside one it is the section's own commentary."""
        if not pending:
            return
        heading = ""
        lines = list(pending)
        match = _DIVIDER.match(lines[0])
        if match:
            heading = match.group(1)
            lines = lines[1:]
        body = _as_prose(lines)
        if section is None:
            self.preamble = body
            return
        if not heading and not body:
            return
        section.notes.append(
            Note(heading=heading, body=body, position=len(section.fields))
        )


def _as_prose(lines: list[str]) -> str:
    """A comment block as plain text. Blank comment lines are paragraph breaks,
    which is how the file already writes its longer explanations."""
    return "\n".join(lines).strip()
