#!/usr/bin/env python3
"""Deterministic metadata transitions; these do not claim OCI verification."""
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sync", ROOT / "scripts/sync-fsdk-metadata.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


def info(url, tag, commit="a" * 40, offset=0):
    return (f"- kind: git_repo\n  url: {url}\n  medium: git\n"
            f"  version: {commit}\n  extra-data:\n    tag-name: {tag}\n"
            f"    commit-offset: {offset}\n")


class Metadata(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in sync.PATHS:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text((ROOT / name).read_text())
        (self.root / "VERSION").write_text("10.07.1-2\n")
        self.gs = info("https://github.com/ArtifexSoftware/ghostpdl.git", "ghostpdl-10.07.1")

    def snapshot(self):
        return {name: (self.root / name).read_bytes() for name in sync.PATHS}

    def run_sync(self):
        return sync.synchronize(self.root, self.gs)

    def test_unchanged_ghostscript_keeps_revision(self):
        self.run_sync()
        before = self.snapshot()
        self.run_sync()
        self.assertEqual((self.root / "VERSION").read_text(), "10.07.1-2\n")
        self.assertEqual(before, self.snapshot())

    def test_new_ghostscript_resets_revision_and_synchronizes_ijs(self):
        self.gs = self.gs.replace("10.07.1", "10.08.0")
        self.run_sync()
        self.assertEqual((self.root / "VERSION").read_text(), "10.08.0-1\n")
        ijs = (self.root / sync.IJS).read_text()
        self.assertIn("track: ghostpdl-10.08.0", ijs)
        self.assertIn("ref: ghostpdl-10.08.0-0-g" + "a" * 40, ijs)

    def test_malformed_metadata_leaves_all_files_unchanged(self):
        self.gs = self.gs.replace("10.07.1", "10.08.0")
        path = self.root / sync.IJS
        path.write_text(path.read_text().replace("    ref:", "    missing:"))
        before = self.snapshot()
        with self.assertRaises(ValueError):
            self.run_sync()
        self.assertEqual(before, self.snapshot())

    def test_unreleased_source_is_rejected(self):
        self.gs = self.gs.replace("commit-offset: 0", "commit-offset: 1")
        with self.assertRaises(ValueError):
            self.run_sync()

    def test_malformed_or_duplicate_provenance_is_rejected(self):
        url = "https://github.com/ArtifexSoftware/ghostpdl.git"
        for value in ("", self.gs + self.gs, self.gs.replace("a" * 40, "short")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                sync.release(value, url, "ghostpdl-")


if __name__ == "__main__":
    unittest.main()
