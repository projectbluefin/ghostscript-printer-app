"""tests/snap-parity-matrix.py must fail whenever the matrix drifts from its sources.

Each case copies the checker, the matrix and both sources into a scratch tree,
introduces one drift, and runs the checker there as `just validate` does.
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MATRIX = "docs/snap-parity-matrix.md"
SNAPCRAFT = "snap/snapcraft.yaml"


class SnapParityMatrixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        (self.tmp / "tests").mkdir()
        shutil.copy(ROOT / "tests/snap-parity-matrix.py", self.tmp / "tests")
        for tree in ("docs", "elements/printer-app", "snap"):
            shutil.copytree(ROOT / tree, self.tmp / tree)

    def edit(self, name, old, new):
        path = self.tmp / name
        text = path.read_text()
        self.assertEqual(text.count(old), 1, f"{old!r} must occur once in {name}")
        path.write_text(text.replace(old, new))

    def check(self):
        return subprocess.run(
            [sys.executable, "tests/snap-parity-matrix.py"],
            cwd=self.tmp, capture_output=True, text=True,
        )

    def assertDrift(self, message):
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(message, result.stderr)

    def test_repository_matrix_passes(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("agrees with its sources", result.stdout)

    def test_element_ref_bump(self):
        self.edit("elements/printer-app/splix.bst", "ref: debian/2.0.1-2-0-g", "ref: debian/2.0.1-3-0-g")
        self.assertDrift("SpliX: matrix says debian/2.0.1-2, splix.bst pins ref debian/2.0.1-3-0-g")

    def test_element_tag_extending_the_matrix_tag(self):
        self.edit("elements/printer-app/c2esp.bst", "ref: debian/27-11-0-g", "ref: debian/27-11-1-0-g")
        self.assertDrift("c2esp: matrix says debian/27-11, c2esp.bst pins ref debian/27-11-1-0-g")

    def test_element_upstream_moved(self):
        self.edit("elements/printer-app/brlaser.bst", "Owl-Maintain/brlaser", "pdewacht/brlaser")
        self.assertDrift("brlaser: matrix names upstream Owl-Maintain/brlaser, brlaser.bst builds from")

    def test_element_missing(self):
        (self.tmp / "elements/printer-app/pxljr.bst").unlink()
        self.assertDrift("pxljr: elements/printer-app/pxljr.bst does not exist")

    def test_commit_and_track_drift(self):
        self.edit(MATRIX, "commit `e4e7b9cd` (tracks `master`)", "commit `e4e7b9ce` (tracks `main`)")
        self.assertDrift("matrix says commit e4e7b9ce, foomatic-db-engine.bst pins ref")
        self.assertDrift("matrix says it tracks main, foomatic-db-engine.bst tracks master")

    def test_snap_tag_bump(self):
        self.edit(SNAPCRAFT, "source-tag: 'v11.10.1'", "source-tag: 'v11.10.2'")
        self.assertDrift("qpdf: matrix says qpdf part v11.10.1, snapcraft.yaml pins v11.10.2")

    def test_snap_upstream_moved(self):
        self.edit(MATRIX, "`brlaser` part: `Owl-Maintain/brlaser`", "`brlaser` part: `pdewacht/brlaser`")
        self.assertDrift("brlaser: matrix names upstream pdewacht/brlaser, snapcraft.yaml brlaser part builds from")

    def test_snap_part_missing(self):
        self.edit(MATRIX, "`pyppd` part: `release-1-1-0`", "`pyppd2` part: `release-1-1-0`")
        self.assertDrift("pyppd: snap/snapcraft.yaml has no part named pyppd2")

    def test_unpinned_snap_part_gains_a_tag(self):
        self.edit(MATRIX, "`pappl-retrofit` part: unpinned `master` (no `source-tag`)",
                  "`pyppd` part: unpinned `master` (no `source-tag`)")
        self.assertDrift("matrix says the pyppd part is unpinned, snapcraft.yaml pins source-tag release-1-1-0")

    def test_status_contradicts_refs(self):
        self.edit(MATRIX, "| `pyppd` part: `release-1-1-0` | match |", "| `pyppd` part: `release-1-1-0` | differs |")
        self.assertDrift("pyppd: matrix status is 'differs' but the FSDK ref release-1-1-0")

    def test_differs_prose_out_of_step(self):
        self.edit(MATRIX, "`pappl-retrofit`, `Ghostscript", "`Ghostscript")
        self.assertDrift('the "Differs" prose names')

    def test_differs_prose_missing(self):
        self.edit(MATRIX, '- "Differs" rows — ', '- Differing rows — ')
        self.assertDrift("no machine-checkable")

    def test_malformed_row_is_not_skipped(self):
        self.edit(MATRIX, "| SpliX | ", "| SpliX |")
        self.assertDrift("table row does not have 4 cells: | SpliX |")

    def test_matrix_section_missing(self):
        self.edit(MATRIX, "## Driver/component matrix", "## Drivers")
        self.assertDrift("no '## Driver/component matrix' section")
        self.assertDrift("no directly-pinned rows were compared")

    def test_snapcraft_without_parts(self):
        (self.tmp / SNAPCRAFT).write_text("name: x\n")
        self.assertDrift("snap/snapcraft.yaml: no parts parsed")


if __name__ == "__main__":
    unittest.main()
