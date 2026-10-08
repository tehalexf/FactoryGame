"""The file index of an exported Godot build, read off the shipped artefact.

A release has to be able to answer one question about itself: *is that file
actually in there*. The export log is not an answer — it says what the exporter
believed it was doing — and neither is the file size. The pack's own index is.

That matters here more than it would in most projects. Three asset classes load at
runtime from a gitignored tree Godot's importer is deliberately kept out of
(`assets_licensed/.gdignore`), so they reach the pack by a route that is easy to
break and, because every one of them degrades gracefully, impossible to notice
from the outside. `verify_pck.py` compares this index against `manifest.py`'s
expected set, and that comparison is the safety net.

## The format

**Pack format version 4**, as written by Godot 4.7. Little-endian throughout, and
the header is all this module needs to find its way:

    offset 0   magic        uint32  0x43504447, "GDPC"
    offset 4   pack version int32   4
    offset 8   engine       int32x3 major, minor, patch
    offset 20  flags        uint32  bit 0 encrypted directory,
                                    bit 1 offsets are relative to the file base
    offset 24  file base    int64   where the stored data begins
    offset 32  dir offset   int64   where the file index begins
               reserved     …       zero to the file base

Version 4 moved the index to **after** the data, which is why `dir offset` exists,
and dropped the `res://` prefix from the stored paths. Both are re-added here so a
caller compares like with like against the paths the game asks for.

At the directory:

    file count   uint32
    then, per file:
    path length  uint32   padded to a multiple of 4
    path         bytes    NUL-padded to that length, no "res://"
    offset       int64    from the file base
    size         int64
    md5          bytes16
    flags        uint32

An **embedded** pack — which is what this project ships, one executable with
nothing loose beside it — is appended to the binary and followed by a twelve-byte
trailer: the pack's own length as an int64, then the magic again. So it is found
from the end.

Only version 4 is read. A newer Godot that bumps the format will stop the build
with the version in the message rather than quietly mis-parse a pack, which is the
right way round: every other failure here is silent by construction.
"""

from __future__ import annotations

import dataclasses
import struct
from pathlib import Path

MAGIC = 0x43504447  # "GDPC"
PACK_FORMAT_VERSION = 4

_FLAG_ENCRYPTED_DIRECTORY = 0x1
_FLAG_RELATIVE_FILE_BASE = 0x2
_TRAILER_SIZE = 8 + 4
_PREFIX = "res://"


class NotAPack(Exception):
    """This file is not, and does not contain, a readable Godot pack.

    Raised rather than returning an empty index, because "no pack here" and "a
    pack with nothing in it" have to be different answers — the second is the bug
    this module exists to catch.
    """


@dataclasses.dataclass(frozen=True)
class Entry:
    """One file in the pack: where it is, how big, and what it hashes to."""

    path: str
    offset: int
    size: int
    md5: str


@dataclasses.dataclass(frozen=True)
class Pack:
    """A pack's index, by `res://` path."""

    files: dict[str, Entry]
    embedded: bool
    engine: tuple[int, int, int]

    def under(self, prefix: str) -> dict[str, Entry]:
        """Every entry whose path starts with `prefix`.

        How an asset class is counted without assuming anything about the rest of
        the pack: `pack.under("res://assets_licensed/generated/audio/")`.
        """
        return {
            path: entry for path, entry in self.files.items() if path.startswith(prefix)
        }


def read(path: Path) -> Pack:
    """The index of the pack in `path`, standalone `.pck` or embedded executable."""
    path = Path(path)
    data = path.read_bytes()
    start, embedded = _locate(data)

    magic, version, major, minor, patch, flags = struct.unpack_from("<IiiiiI", data, start)
    if magic != MAGIC:
        raise NotAPack(f"{path}: no GDPC magic where a pack header was expected")
    if version != PACK_FORMAT_VERSION:
        raise NotAPack(
            f"{path}: pack format version {version}, and this reader understands"
            f" {PACK_FORMAT_VERSION}. A Godot upgrade has changed the format;"
            " tools/release/pck.py has to be taught the new one."
        )
    if flags & _FLAG_ENCRYPTED_DIRECTORY:
        raise NotAPack(f"{path}: the directory is encrypted and cannot be read here")

    file_base, directory_offset = struct.unpack_from("<qq", data, start + 24)

    # Where a stored file's own offset is measured from. Getting this wrong yields
    # a believable index over the wrong bytes, so `test_pck.py` re-hashes a file out
    # of the artefact rather than trusting the arithmetic.
    base = (start if flags & _FLAG_RELATIVE_FILE_BASE else 0) + file_base

    cursor = start + directory_offset
    (count,) = struct.unpack_from("<I", data, cursor)
    cursor += 4

    files: dict[str, Entry] = {}
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor : cursor + length].rstrip(b"\0").decode("utf-8")
        cursor += length
        offset, size = struct.unpack_from("<qq", data, cursor)
        cursor += 16
        digest = data[cursor : cursor + 16].hex()
        cursor += 16
        cursor += 4  # per-file flags
        if not name.startswith(_PREFIX):
            name = _PREFIX + name
        files[name] = Entry(path=name, offset=base + offset, size=size, md5=digest)

    return Pack(files=files, embedded=embedded, engine=(major, minor, patch))


def _locate(data: bytes) -> tuple[int, bool]:
    """Where the pack starts, and whether it was appended to something else."""
    if len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] == MAGIC:
        return 0, False
    if len(data) < _TRAILER_SIZE:
        raise NotAPack("file is too short to contain a pack")
    (trailing_magic,) = struct.unpack_from("<I", data, len(data) - 4)
    if trailing_magic != MAGIC:
        raise NotAPack(
            "no GDPC magic at the start or the end of the file — nothing was"
            " embedded in this binary, so it carries no game"
        )
    (size,) = struct.unpack_from("<q", data, len(data) - _TRAILER_SIZE)
    start = len(data) - _TRAILER_SIZE - size
    if start < 0 or struct.unpack_from("<I", data, start)[0] != MAGIC:
        raise NotAPack("the appended pack's declared length does not find its header")
    return start, True
