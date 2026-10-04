#!/usr/bin/env python3
"""Deterministic metadata transitions; these do not claim OCI verification."""
import importlib.util
from pathlib import Path
import tempfile
import sys
from unittest.mock import patch
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
        self.fsdk = info("https://gitlab.com/freedesktop-sdk/freedesktop-sdk.git", "freedesktop-sdk-27.08.1")
        self.gs = info("https://github.com/ArtifexSoftware/ghostpdl.git", "ghostpdl-10.07.1")

    def run_sync(self):
        return sync.synchronize(self.root, "b" * 40, "c" * 40, self.fsdk, self.gs)

    def test_fsdk_only_increments_revision_and_accepts_new_line(self):
        self.run_sync()
        self.assertEqual((self.root / "VERSION").read_text(), "10.07.1-3\n")
        self.assertIn("version=10.07.1-3", (self.root / "README.md").read_text())
        self.assertIn("'27.08.1'", (self.root / sync.PATHS[2]).read_text())
        self.assertIn("'" + "a" * 40 + "'", (self.root / sync.PATHS[2]).read_text())
        quadlet = (self.root / sync.QUADLET_PATH).read_text()
        self.assertIn("Image=ghcr.io/projectbluefin/ghostscript-printer-app:10.07.1-3", quadlet)
        self.assertIn("check-rootless-usb.py ghcr.io/projectbluefin/ghostscript-printer-app:10.07.1-3 ", quadlet)

    def test_new_ghostscript_resets_revision_and_synchronizes_ijs(self):
        self.gs = self.gs.replace("10.07.1", "10.08.0")
        self.run_sync()
        self.assertEqual((self.root / "VERSION").read_text(), "10.08.0-1\n")
        ijs = (self.root / sync.PATHS[1]).read_text()
        self.assertIn("track: ghostpdl-10.08.0", ijs)
        self.assertIn("ref: ghostpdl-10.08.0-0-g" + "a" * 40, ijs)
        self.assertIn("version=10.08.0-1", (self.root / "README.md").read_text())
        quadlet = (self.root / sync.QUADLET_PATH).read_text()
        self.assertIn("Image=ghcr.io/projectbluefin/ghostscript-printer-app:10.08.0-1", quadlet)
        self.assertIn("check-rootless-usb.py ghcr.io/projectbluefin/ghostscript-printer-app:10.08.0-1 ", quadlet)

    def test_quadlet_drift_is_corrected_even_when_tag_differs(self):
        # The Quadlet pinned an older release than VERSION; sync must rewrite
        # both occurrences in lockstep so the example matches the documented
        # version (#82). Seed drift through sync.QUADLET_TAG_RE so the test
        # stays meaningful after VERSION moves off the literal in the original
        # Quadlet -- a literal contents.replace("X", "Y") becomes a no-op the
        # first time the Quadlet stops carrying X.
        quadlet_path = self.root / sync.QUADLET_PATH
        original = quadlet_path.read_text()
        drifted = sync.QUADLET_TAG_RE.sub(
            f"{sync.QUADLET_IMAGE}:9.99.9-99", original, count=2
        )
        self.assertNotEqual(drifted, original)
        quadlet_path.write_text(drifted)
        self.run_sync()
        updated = quadlet_path.read_text()
        self.assertNotIn("9.99.9-99", updated)
        version = (self.root / sync.PATHS[0]).read_text().strip()
        new_tag = f"{sync.QUADLET_IMAGE}:{version}"
        self.assertEqual(updated.count(new_tag), 2)

    def test_quadlet_without_two_image_tags_is_rejected(self):
        # Drift between Image= and ExecStartPre= would break the verifier and
        # the documented behavior; fail closed so the drift cannot slip
        # through metadata synchronization.
        quadlet_path = self.root / sync.QUADLET_PATH
        contents = quadlet_path.read_text()
        lines = [line for line in contents.splitlines()
                 if "ExecStartPre=" not in line]
        quadlet_path.write_text("\n".join(lines) + "\n")
        before = {name: (self.root / name).read_bytes() for name in sync.PATHS}
        with self.assertRaisesRegex(ValueError, "exactly two image tags"):
            self.run_sync()
        self.assertEqual(before, {name: (self.root / name).read_bytes() for name in sync.PATHS})

    def test_malformed_metadata_leaves_all_files_unchanged(self):
        path = self.root / sync.PATHS[2]
        path.write_text(path.read_text().replace("io.projectbluefin.fsdk.ref", "missing"))
        before = {name: (self.root / name).read_bytes() for name in sync.PATHS}
        with self.assertRaises(ValueError):
            self.run_sync()
        self.assertEqual(before, {name: (self.root / name).read_bytes() for name in sync.PATHS})

    def test_unreleased_source_is_rejected(self):
        self.gs = self.gs.replace("commit-offset: 0", "commit-offset: 1")
        with self.assertRaises(ValueError):
            self.run_sync()

    def test_malformed_or_duplicate_provenance_is_rejected(self):
        for value in ("", self.fsdk + self.fsdk, self.fsdk.replace("a" * 40, "short")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                sync.release(value, "https://gitlab.com/freedesktop-sdk/freedesktop-sdk.git",
                             "freedesktop-sdk-")

    def test_upstream_discovery_is_not_bounded_to_current_line(self):
        refs = "\n".join("a" * 40 + "\trefs/tags/freedesktop-sdk-" + version
                         for version in ("26.08.1", "27.08.1", "28.08rc.1", "9.08.1"))
        with patch.object(sync.subprocess, "check_output", return_value=refs):
            self.assertEqual(sync.upstream_release("https://example.test", "freedesktop-sdk-"),
                             "27.08.1")

    def test_unchanged_base_cannot_increment_revision(self):
        with self.assertRaises(ValueError):
            sync.synchronize(self.root, "b" * 40, "b" * 40, self.fsdk, self.gs)


if __name__ == "__main__":
    unittest.main()
