#!/usr/bin/env python3
"""Structural and failure-path checks, not physical USB evidence."""
import configparser
import contextlib
import io
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("usb", ROOT / "scripts/check-rootless-usb.py")
usb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usb)


class RootlessUSB(unittest.TestCase):
    def test_quadlet_matches_probe(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(ROOT / "examples/ghostscript-printer-app-usb.container")
        container = config["Container"]
        with patch.object(usb.subprocess, "run") as run:
            run.return_value.stdout = "true\n"
            usb.check(container["Image"], "/dev/bus/usb/001/002")
        args = run.call_args.args[0]
        for key, flag in [("AddDevice", "--device"), ("GroupAdd", "--group-add"),
                          ("User", "--user"), ("Network", "--network")]:
            self.assertEqual(args[args.index(flag) + 1], container[key])
        self.assertIn(container["Image"], config["Service"]["ExecStartPre"])
        self.assertEqual(container["Image"], "ghcr.io/projectbluefin/ghostscript-printer-app:stable")
        self.assertEqual(container["AutoUpdate"], "registry")
        self.assertTrue(config["Service"]["ExecStartPre"].startswith(
            "/usr/bin/python3 %h/.local/libexec/check-rootless-usb.py "))
        self.assertEqual(container["AddDevice"], "/dev/bus/usb")
        self.assertEqual(container["GroupAdd"], "keep-groups")
        self.assertEqual(container["User"], "65532:65532")
        self.assertNotIn("PodmanArgs", container)
        self.assertNotIn("SecurityLabelDisable", container)
        self.assertNotIn("--privileged", args)

    def test_denial_is_actionable_without_retry(self):
        with patch.object(sys, "argv", ["check", "image", "/dev/bus/usb/001/002"]), \
             patch.object(usb.subprocess, "run") as run, \
             patch("sys.stderr") as stderr:
            run.side_effect = [subprocess.CompletedProcess([], 0, stdout="true\n"),
                               subprocess.CalledProcessError(1, ["podman", "run"])]
            self.assertEqual(usb.main(), 1)
            self.assertEqual(run.call_count, 2)
            message = "".join(call.args[0] for call in stderr.write.call_args_list)
            for word in ["udev", "group", "crun", "SELinux", "FAIL"]:
                self.assertIn(word, message)

    def test_rootful_rejected(self):
        with patch.object(usb.subprocess, "run") as run:
            run.return_value.stdout = "false\n"
            with self.assertRaisesRegex(ValueError, "rootless"):
                usb.check("image", "/dev/bus/usb/001/002")
            self.assertEqual(run.call_count, 1)

    def test_invalid_node_rejected_before_launch(self):
        with patch.object(usb.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                usb.check("image", "/dev/null")
            run.assert_not_called()

    def test_probe_open_denial(self):
        # Exercise the actual probe without requiring or claiming USB hardware.
        with patch("os.stat") as stat, patch("os.open", side_effect=PermissionError("denied")), \
             patch.object(sys, "argv", ["probe", "/dev/bus/usb/001/002"]), \
             patch("sys.stderr"):
            stat.return_value.st_mode = 0o020660
            with self.assertRaises(SystemExit) as result:
                exec(usb.PROBE, {})
            self.assertEqual(result.exception.code, 1)


    def test_success_runs_probe_as_appliance_user(self):
        out = io.StringIO()
        with patch.object(sys, "argv", ["check", "img@sha256:abc", "/dev/bus/usb/003/017"]), \
             patch.object(usb.subprocess, "run") as run, contextlib.redirect_stdout(out):
            run.return_value.stdout = "true\n"
            self.assertEqual(usb.main(), 0)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0].args[0][:2], ["podman", "info"])
        probe = run.call_args.args[0]
        self.assertEqual(probe[-4:], ["img@sha256:abc", "-c", usb.PROBE, "/dev/bus/usb/003/017"])
        self.assertTrue(run.call_args.kwargs["check"])
        self.assertIn("OK: rootless USB node opens read/write", out.getvalue())
        self.assertIn("physical printing remains unverified", out.getvalue())

    def test_podman_info_failure_is_actionable(self):
        err = io.StringIO()
        with patch.object(sys, "argv", ["check", "image", "/dev/bus/usb/001/002"]), \
             patch.object(usb.subprocess, "run",
                          side_effect=subprocess.CalledProcessError(125, ["podman", "info"])) as run, \
             contextlib.redirect_stderr(err):
            self.assertEqual(usb.main(), 1)
        self.assertEqual(run.call_count, 1)
        self.assertIn("FAIL: rootless USB preflight", err.getvalue())
        self.assertIn(usb.REMEDIATION, err.getvalue())

    def test_malformed_nodes_fail_through_main_without_podman(self):
        for device in ["/dev/bus/usb/1/2", "/dev/bus/usb/001/0020", "/dev/bus/usb/001/002/",
                       "/dev/bus/usb/001", "dev/bus/usb/001/002", "/dev/bus/usb/001/../..",
                       "/dev/bus/usb", "/dev/bus/usb/001/002\n"]:
            with self.subTest(device=device):
                err = io.StringIO()
                with patch.object(sys, "argv", ["check", "image", device]), \
                     patch.object(usb.subprocess, "run") as run, contextlib.redirect_stderr(err):
                    self.assertEqual(usb.main(), 1)
                run.assert_not_called()
                self.assertIn("/dev/bus/usb/BBB/DDD", err.getvalue())

    def test_probe_rejects_non_character_device(self):
        err = io.StringIO()
        with patch("os.stat") as stat, patch("os.open") as open_, \
             patch.object(sys, "argv", ["probe", "/dev/bus/usb/001/002"]), \
             contextlib.redirect_stderr(err):
            stat.return_value.st_mode = 0o100644
            with self.assertRaises(SystemExit) as result:
                exec(usb.PROBE, {})
        self.assertEqual(result.exception.code, 1)
        open_.assert_not_called()
        self.assertIn("not a character device", err.getvalue())

    def test_probe_missing_node(self):
        err = io.StringIO()
        with patch("os.stat", side_effect=FileNotFoundError("gone")), patch("os.open") as open_, \
             patch.object(sys, "argv", ["probe", "/dev/bus/usb/001/002"]), \
             contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit) as result:
                exec(usb.PROBE, {})
        self.assertEqual(result.exception.code, 1)
        open_.assert_not_called()
        self.assertIn("/dev/bus/usb/001/002: gone", err.getvalue())

    def test_probe_opens_read_write_nonblocking_and_closes(self):
        with patch("os.stat") as stat, patch("os.open", return_value=42) as open_, \
             patch("os.close") as close, patch.object(sys, "argv", ["probe", "/dev/bus/usb/001/002"]):
            stat.return_value.st_mode = 0o020660
            exec(usb.PROBE, {})
        open_.assert_called_once_with("/dev/bus/usb/001/002", os.O_RDWR | os.O_NONBLOCK)
        close.assert_called_once_with(42)


if __name__ == "__main__":
    result = unittest.main(exit=False).result
    evidence = "Physical USB evidence: unavailable (no hardware test performed).\n"
    print(evidence, end="")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write(evidence)
    sys.exit(not result.wasSuccessful())
