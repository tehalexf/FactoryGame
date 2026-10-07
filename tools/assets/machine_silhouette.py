#!/usr/bin/env python3
"""A Machine's silhouette, as a number rather than as an opinion.

A player identifies a building across a Factory by its outline: at fifty metres,
in peripheral vision, while something is chasing them. Surface detail is gone at
that distance, so "is this Machine recognisable?" is a question about the gross
form only — height, mass, roof shape, what projects from the body.

This module answers it mechanically. It rasterises a Machine's projected outline
into a deliberately **coarse** occupancy grid and reports the Jaccard distance
between every pair. Coarse on purpose: at 28 cm per cell a chimney moves the
score and a rivet cannot, so the only way to pass the gate is to change the
silhouette rather than to add detailing.

    python3 tools/assets/machine_silhouette.py             # the distance matrix
    python3 tools/assets/machine_silhouette.py --ascii     # every silhouette

Standard library only, and it reads the committed `.glb` bytes — so it measures
the shipped artifact and not the generator's intentions.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import gltf_info  # noqa: E402

REPO = HERE.parents[1]
MACHINE_DIR = REPO / "assets" / "machines"

#: The frame every Machine is rasterised in, in metres. Shared rather than
#: per-Machine, because absolute size is *part* of a silhouette: an 8 m Silo and a
#: 4 m Generator are told apart by being different sizes, and normalising each one
#: to fill the frame would throw that away.
VIEW_HALF_WIDTH_M = 4.5
VIEW_HEIGHT_M = 11.25

#: Cells across and up. 32 cells over 9 m is 28 cm a cell — about the size of a
#: hydraulic ram, well under the size of a chimney.
GRID_WIDE = 32
GRID_HIGH = 40

#: Which way the camera looks. `front` is the view down a Belt line from the
#: north; `side` is the view along it. Both in Godot's exported axes, where the
#: glTF has already been converted to +Y up.
VIEWS = ("front", "side")

def triangles(path: Path) -> list[tuple[tuple[float, float, float], ...]]:
    """Every triangle in a Machine mesh, in the Machine's own space.

    The generator leaves every object's transform at identity, which the asset
    suite asserts, so a vertex position is already the Machine's own coordinate
    and no node hierarchy has to be walked.
    """
    out: list[tuple[tuple[float, float, float], ...]] = []
    for primitive in gltf_info.mesh_primitives(path):
        verts, order = primitive["positions"], primitive["indices"]
        for i in range(0, len(order) - 2, 3):
            out.append((verts[order[i]], verts[order[i + 1]], verts[order[i + 2]]))
    return out


def _project(vertex, view: str) -> tuple[float, float]:
    x, y, z = vertex
    return (x if view == "front" else z, y)


def rasterise(tris, view: str) -> list[int]:
    """The silhouette as one bit per cell, row 0 at the ground.

    A cell is filled when a triangle covers its centre. Cheap, exact enough at
    this resolution, and free of any anti-aliasing that would let a sliver of
    geometry half-fill a cell and make the score sensitive to detailing.
    """
    cell = (VIEW_HALF_WIDTH_M * 2.0) / GRID_WIDE
    grid = [0] * (GRID_WIDE * GRID_HIGH)
    for tri in tris:
        (ax, ay), (bx, by), (cx, cy) = (_project(v, view) for v in tri)
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-12:
            continue
        col_lo = max(0, int((min(ax, bx, cx) + VIEW_HALF_WIDTH_M) / cell))
        col_hi = min(GRID_WIDE - 1, int((max(ax, bx, cx) + VIEW_HALF_WIDTH_M) / cell))
        row_lo = max(0, int(min(ay, by, cy) / cell))
        row_hi = min(GRID_HIGH - 1, int(max(ay, by, cy) / cell))
        for row in range(row_lo, row_hi + 1):
            py = (row + 0.5) * cell
            base = row * GRID_WIDE
            for col in range(col_lo, col_hi + 1):
                if grid[base + col]:
                    continue
                px = (col + 0.5) * cell - VIEW_HALF_WIDTH_M
                w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / area
                w1 = ((cx - bx) * (py - by) - (px - bx) * (cy - by)) / area
                w2 = ((ax - cx) * (py - cy) - (px - cx) * (ay - cy)) / area
                if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) \
                        or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
                    grid[base + col] = 1
    return grid


def silhouettes(machine_ids=None,
                machine_dir: Path = MACHINE_DIR) -> dict[str, dict[str, list[int]]]:
    """Every Machine's silhouette in every view, keyed by id then by view."""
    paths = sorted(Path(machine_dir).glob("*.glb"))
    if machine_ids is not None:
        wanted = set(machine_ids)
        paths = [p for p in paths if p.stem in wanted]
    out: dict[str, dict[str, list[int]]] = {}
    for path in paths:
        tris = triangles(path)
        out[path.stem] = {view: rasterise(tris, view) for view in VIEWS}
    return out


def jaccard_distance(left: list[int], right: list[int]) -> float:
    """1 - intersection over union. 0.0 is the same outline, 1.0 shares no cell."""
    intersection = sum(1 for a, b in zip(left, right) if a and b)
    union = sum(1 for a, b in zip(left, right) if a or b)
    if union == 0:
        return 0.0
    return 1.0 - intersection / union


def separation(left: dict[str, list[int]], right: dict[str, list[int]]) -> float:
    """How far apart two Machines look: the best view disagrees this much.

    The *best* view rather than the average, because a player walks around a
    Factory. Two Machines that are identical head-on but obviously different from
    the side are still tellable apart; two that match from every angle are not.
    """
    return max(jaccard_distance(left[view], right[view]) for view in VIEWS)


def separation_matrix(shapes: dict[str, dict[str, list[int]]]) -> dict[tuple[str, str], float]:
    """Every unordered pair's separation, keyed by the pair in sorted order."""
    ids = sorted(shapes)
    return {(a, b): separation(shapes[a], shapes[b])
            for i, a in enumerate(ids) for b in ids[i + 1:]}


def ascii_art(grid: list[int]) -> str:
    rows = []
    for row in range(GRID_HIGH - 1, -1, -1):
        rows.append("".join("#" if grid[row * GRID_WIDE + col] else "."
                            for col in range(GRID_WIDE)))
    return "\n".join(rows)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ascii", action="store_true",
                        help="print every silhouette as text as well")
    parser.add_argument("--machine-dir", default=str(MACHINE_DIR))
    args = parser.parse_args(argv)
    shapes = silhouettes(machine_dir=Path(args.machine_dir))
    if args.ascii:
        for machine_id, views in shapes.items():
            for view in VIEWS:
                print(f"\n=== {machine_id} ({view}) ===")
                print(ascii_art(views[view]))
        print()
    matrix = separation_matrix(shapes)
    ids = sorted(shapes)
    width = max(len(i) for i in ids)
    print(" " * (width + 1) + " ".join(f"{i[:5]:>5}" for i in ids))
    for a in ids:
        cells = []
        for b in ids:
            cells.append("    -" if a == b
                         else f"{matrix[(min(a, b), max(a, b))]:5.2f}")
        print(f"{a:<{width}} " + " ".join(cells))
    worst = sorted(matrix.items(), key=lambda kv: kv[1])[:10]
    print("\nclosest pairs (1.00 = no cell in common):")
    for (a, b), value in worst:
        print(f"  {value:5.2f}  {a} / {b}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
