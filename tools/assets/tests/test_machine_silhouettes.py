"""Every Machine must be identifiable from its outline alone.

This is a gameplay gate, not a polish one. The core skill in a factory game is
reading your own production line at a glance: a player has to know what a
building is from its silhouette, at distance, in peripheral vision, while
something is chasing them. Two Machines that are the same black shape are two
Machines a player cannot plan around.

Seam: the committed `.glb` files, same as the rest of the asset suite. Nothing
here imports Blender or calls the generator — it rasterises the shipped meshes
and compares them, so the thing under test is what the game loads.

The measurement is deliberately coarse (28 cm a cell): a chimney moves the score
and a rivet cannot, so the only way to pass is to change the gross form. See
`tools/assets/machine_silhouette.py`, and
`docs/images/machine_silhouettes_front.png` for the same claim in a picture.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import machine_silhouette  # noqa: E402
import machine_specs  # noqa: E402

#: How far apart two Machines' outlines must be, as 1 - intersection over union
#: of their occupancy grids in the better of two orthogonal views.
#:
#: Where the number comes from: before this gate existed the Factory's closest
#: pair sat at 0.29 and four bodies read as "a dark box with a chimney". The
#: redesigned set's closest pair is 0.42. 0.38 is below that with room to tune a
#: Machine, and well above the state this gate was written to reject — so it
#: fails the geometry it was written against and passes the geometry that
#: replaced it, which is the only way a threshold means anything.
MINIMUM_SEPARATION = 0.38


class EveryPairOfMachines(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shapes = machine_silhouette.silhouettes()
        cls.matrix = machine_silhouette.separation_matrix(cls.shapes)

    def test_is_measured_from_every_declared_machine(self):
        """The gate is worthless if it quietly stops covering a Machine, so the
        set it measured must be the set that was declared."""
        self.assertEqual(set(self.shapes),
                         {m.machine_id for m in machine_specs.load()})

    def test_casts_a_different_shadow_from_every_other_machine(self):
        """The acceptance criterion, as a number. A failure here names the pair,
        and the fix is to change one of their gross forms — height, roof, mass,
        what projects from the body — not to add detail to either."""
        for (left, right), separation in sorted(self.matrix.items()):
            with self.subTest(pair=f"{left} / {right}"):
                self.assertGreaterEqual(
                    separation, MINIMUM_SEPARATION,
                    f"{left} and {right} are the same shape to within "
                    f"{separation:.2f}; they will not be told apart across a "
                    f"Factory floor. Vary the gross form, not the detailing.")

    def test_fills_a_plausible_share_of_its_own_footprint(self):
        """A silhouette that is nearly empty, or that fills its whole frame, is a
        mesh that went wrong in a way the extent tests cannot see."""
        cells = machine_silhouette.GRID_WIDE * machine_silhouette.GRID_HIGH
        for machine_id, views in self.shapes.items():
            for view, grid in views.items():
                with self.subTest(machine=machine_id, view=view):
                    filled = sum(grid)
                    # A Belt is one 2 m tile of hip-high trestle, so it is the
                    # floor this bound is set against; anything that reads as
                    # less than a Belt has lost its geometry.
                    self.assertGreaterEqual(filled, 4, "almost nothing was drawn")
                    self.assertLess(filled, cells * 0.6,
                                    "the Machine fills the whole frame")


class TheMeasurementItself(unittest.TestCase):
    """A gate that cannot fail is not a gate. These are the measurement's own
    contract, asserted against hand-built grids rather than against meshes."""

    def _grid(self, filled) -> list[int]:
        grid = [0] * (machine_silhouette.GRID_WIDE * machine_silhouette.GRID_HIGH)
        for index in filled:
            grid[index] = 1
        return grid

    def test_calls_a_shape_identical_to_itself_zero_apart(self):
        shape = self._grid(range(40))
        self.assertEqual(machine_silhouette.jaccard_distance(shape, shape), 0.0)

    def test_calls_two_shapes_sharing_no_cell_one_apart(self):
        self.assertEqual(
            machine_silhouette.jaccard_distance(self._grid(range(0, 10)),
                                                self._grid(range(10, 20))),
            1.0)

    def test_scores_half_overlap_at_a_third(self):
        """Two ten-cell shapes sharing five cells intersect in 5 and unite in 15,
        so the distance is 1 - 5/15. A worked example, not a recomputation."""
        self.assertAlmostEqual(
            machine_silhouette.jaccard_distance(self._grid(range(0, 10)),
                                                self._grid(range(5, 15))),
            2.0 / 3.0, places=6)

    def test_reports_the_view_that_tells_two_machines_apart(self):
        """A player walks around a Factory. Two Machines identical head-on but
        obviously different from the side are still tellable apart, so the
        separation is the best view's and not the average."""
        same = self._grid(range(0, 10))
        other = self._grid(range(10, 20))
        self.assertEqual(
            machine_silhouette.separation({"front": same, "side": same},
                                          {"front": same, "side": other}),
            1.0)


if __name__ == "__main__":
    unittest.main()
