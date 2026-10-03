#!/usr/bin/env python3
"""Deterministic metadata transitions; these do not claim OCI verification."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
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

    def test_new_ghostscript_resets_revision_and_synchronizes_ijs(self):
        self.gs = self.gs.replace("10.07.1", "10.08.0")
        self.run_sync()
        self.assertEqual((self.root / "VERSION").read_text(), "10.08.0-1\n")
        ijs = (self.root / sync.PATHS[1]).read_text()
        self.assertIn("track: ghostpdl-10.08.0", ijs)
        self.assertIn("ref: ghostpdl-10.08.0-0-g" + "a" * 40, ijs)
        self.assertIn("version=10.08.0-1", (self.root / "README.md").read_text())

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


    def snapshot(self):
        return {name: (self.root / name).read_bytes() for name in sync.PATHS}

    def test_base_refs_must_be_full_commits(self):
        before = self.snapshot()
        for old, new in (("b" * 39, "c" * 40), ("b" * 40, "C" * 40), ("main", "c" * 40)):
            with self.subTest(old=old, new=new), self.assertRaisesRegex(ValueError, "full commits"):
                sync.synchronize(self.root, old, new, self.fsdk, self.gs)
        self.assertEqual(before, self.snapshot())

    def test_ghostscript_must_be_a_stable_three_component_release(self):
        before = self.snapshot()
        for tag in ("ghostpdl-10.08", "ghostpdl-10.08.0rc.1"):
            self.gs = info("https://github.com/ArtifexSoftware/ghostpdl.git", tag)
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "stable three-component"):
                self.run_sync()
        self.assertEqual(before, self.snapshot())

    def test_version_file_must_carry_a_positive_revision(self):
        for current in ("10.07.1\n", "10.07.1-0\n", "10.07-2\n", "v10.07.1-2\n"):
            (self.root / "VERSION").write_text(current)
            before = self.snapshot()
            with self.subTest(current=current), self.assertRaisesRegex(ValueError, "positive revision"):
                self.run_sync()
            self.assertEqual(before, self.snapshot())

    def test_failed_write_restores_every_file(self):
        before = self.snapshot()
        write_text = Path.write_text
        failed = []

        def fail_on_readme(path, contents, *args, **kwargs):
            if path.name == "README.md" and not failed:
                failed.append(path)
                raise OSError("disk full")
            return write_text(path, contents, *args, **kwargs)

        with patch.object(Path, "write_text", fail_on_readme), self.assertRaises(OSError):
            self.run_sync()
        self.assertEqual(failed, [self.root / "README.md"])
        self.assertEqual(before, self.snapshot())

    def test_upstream_lookup_failure_is_reported_not_raised(self):
        for outcome in (subprocess.CalledProcessError(128, "git"),
                        subprocess.TimeoutExpired("git", 60), ""):
            kwargs = ({"return_value": outcome} if isinstance(outcome, str)
                      else {"side_effect": outcome})
            with self.subTest(outcome=type(outcome).__name__), \
                    patch.object(sync.subprocess, "check_output", **kwargs):
                self.assertEqual(sync.upstream_release("https://example.test", "ghostpdl-"),
                                 "unknown (upstream lookup failed)")

    def test_main_synchronizes_from_fsdk_and_its_ghostscript(self):
        shown = []

        def source_info(target):
            shown.append(target)
            return self.fsdk if target == sync.FSDK else self.gs

        out = io.StringIO()
        argv = ["sync-fsdk-metadata.py", "--old", "b" * 40, "--new", "c" * 40]
        with patch.object(sync, "ROOT", self.root), patch.object(sys, "argv", argv), \
                patch.object(sync, "source_info", source_info), \
                patch.object(sync, "upstream_release", return_value="1.2.3"), \
                contextlib.redirect_stdout(out):
            sync.main()
        self.assertEqual(shown, [sync.FSDK, sync.FSDK + ":components/ghostscript.bst"])
        self.assertEqual((self.root / "VERSION").read_text(), "10.07.1-3\n")
        self.assertEqual(out.getvalue().splitlines(), [
            "FSDK 27.08.1 (" + "a" * 40 + "); Ghostscript 10.07.1 (" + "a" * 40
            + "); application 10.07.1-3",
            "Upstream FSDK latest stable tag: 1.2.3",
            "Upstream Ghostscript latest stable tag: 1.2.3",
        ])

    def test_source_info_asks_bst_for_resolved_provenance_only(self):
        with patch.object(sync.subprocess, "check_output", return_value="x") as run:
            self.assertEqual(sync.source_info(sync.FSDK), "x")
        run.assert_called_once_with(
            ["just", "bst", "--no-colors", "show", "--deps", "none",
             "--format", "%{source-info}", sync.FSDK], cwd=sync.ROOT, text=True)

if __name__ == "__main__":
    unittest.main()
