#!/usr/bin/env python3
"""Execute the release workflow's tag-and-metadata gate against fixture repos.

registry-actions.yml publishes an immutable OCI release for a pushed tag only
after its "Validate release tag and metadata" step proves the tag is on
stable, names the application VERSION, and finds the FSDK pin labels in the
OCI element. That step runs only on a real tag push, so this test lifts its
run block out of the workflow verbatim and runs it in throwaway git
repositories: a change to the gate is tested as written, with no copy to
drift from it.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/registry-actions.yml"
ELEMENT = Path("elements/oci/ghostscript-printer-app.bst")
STEP_NAME = "Validate release tag and metadata"


def step_script(workflow, step_name):
    """Return the dedented `run: |` body of the named step."""
    lines = workflow.read_text().splitlines()
    starts = [i for i, line in enumerate(lines)
              if re.fullmatch(rf"\s*- name: {re.escape(step_name)}", line)]
    if len(starts) != 1:
        raise ValueError(f"expected one step named {step_name!r} in {workflow}")
    step_indent = len(lines[starts[0]]) - len(lines[starts[0]].lstrip())
    run_at = None
    for i in range(starts[0] + 1, len(lines)):
        line = lines[i]
        indent = len(line) - len(line.lstrip())
        if line.strip() and indent <= step_indent:
            break
        if re.fullmatch(r"\s*run: \|", line):
            run_at = i
            break
    if run_at is None:
        raise ValueError(f"step {step_name!r} has no `run: |` block")
    run_indent = len(lines[run_at]) - len(lines[run_at].lstrip())
    body = []
    for line in lines[run_at + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) <= run_indent:
            break
        body.append(line)
    while body and not body[-1].strip():
        body.pop()
    block_indent = min(len(l) - len(l.lstrip()) for l in body if l.strip())
    return "\n".join(l[block_indent:] for l in body) + "\n"


def fsdk_labels(element_text):
    labels = {}
    for key in ("version", "ref"):
        match = re.search(rf"'io\.projectbluefin\.fsdk\.{key}':\s*'([^']*)'", element_text)
        labels[key] = match.group(1) if match else None
    return labels


def git(cwd, *args):
    return subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid",
         "-c", "init.defaultBranch=stable", "-c", "commit.gpgsign=false", *args],
        cwd=cwd, check=True, capture_output=True, text=True,
    ).stdout.strip()


class ReleaseMetadataGate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = step_script(WORKFLOW, STEP_NAME)
        cls.element_text = (ROOT / ELEMENT).read_text()
        cls.version = (ROOT / "VERSION").read_text().strip()

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="release-metadata."))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.origin = self.tmp / "origin.git"
        self.work = self.tmp / "work"
        git(self.tmp, "init", "--quiet", "--bare", str(self.origin))
        git(self.tmp, "init", "--quiet", str(self.work))
        git(self.work, "remote", "add", "origin", str(self.origin))
        self.commit(self.version, self.element_text, "release")
        git(self.work, "push", "--quiet", "origin", "HEAD:refs/heads/stable")

    def commit(self, version, element_text, message):
        (self.work / "VERSION").write_text(f"{version}\n")
        (self.work / ELEMENT).parent.mkdir(parents=True, exist_ok=True)
        (self.work / ELEMENT).write_text(element_text)
        git(self.work, "add", "-A")
        git(self.work, "commit", "--quiet", "--allow-empty", "-m", message)
        return git(self.work, "rev-parse", "HEAD")

    def run_gate(self, ref_name):
        output = self.tmp / "github_output"
        output.write_text("")
        env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.tmp),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GITHUB_REF_NAME": ref_name,
            "GITHUB_OUTPUT": str(output),
        }
        result = subprocess.run(["bash", "-c", self.script], cwd=self.work, env=env,
                                capture_output=True, text=True)
        outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
        return result, outputs

    def assert_refused(self, result, outputs, message):
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn(message, result.stderr)
        self.assertEqual(outputs, {}, "a refused tag must not publish any step output")

    def test_real_element_carries_both_fsdk_labels(self):
        labels = fsdk_labels(self.element_text)
        self.assertTrue(labels["version"], f"{ELEMENT} has no io.projectbluefin.fsdk.version label")
        self.assertRegex(labels["ref"] or "", r"^[0-9a-f]{40}$",
                         f"{ELEMENT} io.projectbluefin.fsdk.ref is not a full commit SHA")

    def test_stable_head_tagged_with_version_publishes_metadata(self):
        head = git(self.work, "rev-parse", "HEAD")
        result, outputs = self.run_gate(f"v{self.version}")
        self.assertEqual(result.returncode, 0, result.stderr)
        labels = fsdk_labels(self.element_text)
        self.assertEqual(outputs["version"], self.version)
        self.assertEqual(outputs["revision"], head)
        self.assertEqual(outputs["created"], git(self.work, "show", "-s", "--format=%cI", "HEAD"))
        self.assertEqual(outputs["fsdk_version"], labels["version"])
        self.assertEqual(outputs["fsdk_ref"], labels["ref"])

    def test_tag_on_earlier_stable_commit_is_accepted(self):
        tagged = git(self.work, "rev-parse", "HEAD")
        self.commit("99.0.0-1", self.element_text, "later stable work")
        git(self.work, "push", "--quiet", "origin", "HEAD:refs/heads/stable")
        git(self.work, "checkout", "--quiet", "--detach", tagged)
        result, outputs = self.run_gate(f"v{self.version}")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["revision"], tagged)

    def test_tag_off_stable_is_refused(self):
        git(self.work, "checkout", "--quiet", "-b", "feature")
        self.commit(self.version, self.element_text, "unreviewed")
        result, outputs = self.run_gate(f"v{self.version}")
        self.assert_refused(result, outputs, "must point to a commit on stable")

    def test_stale_local_stable_ref_is_not_trusted(self):
        # The gate must ask the remote: a local origin/stable that still lists
        # the commit after stable was rewound must not let the tag through.
        git(self.work, "checkout", "--quiet", "-b", "feature")
        self.commit(self.version, self.element_text, "briefly on stable")
        git(self.work, "push", "--quiet", "origin", "HEAD:refs/heads/stable")
        git(self.work, "push", "--quiet", "--force", "origin", "HEAD~1:refs/heads/stable")
        git(self.work, "update-ref", "refs/remotes/origin/stable", "HEAD")
        result, outputs = self.run_gate(f"v{self.version}")
        self.assert_refused(result, outputs, "must point to a commit on stable")

    def test_tag_not_matching_version_is_refused(self):
        for ref_name in ("v0.0.0-1", self.version, f"v{self.version}-rc1", f"V{self.version}"):
            with self.subTest(ref_name=ref_name):
                result, outputs = self.run_gate(ref_name)
                self.assert_refused(result, outputs, "does not match application version")

    def test_missing_fsdk_label_is_refused(self):
        for key in ("version", "ref"):
            with self.subTest(label=key):
                stripped = re.sub(rf"^.*'io\.projectbluefin\.fsdk\.{key}'.*\n", "",
                                  self.element_text, flags=re.MULTILINE)
                self.assertNotEqual(stripped, self.element_text)
                self.commit(self.version, stripped, f"drop fsdk {key} label")
                git(self.work, "push", "--quiet", "origin", "HEAD:refs/heads/stable")
                result, outputs = self.run_gate(f"v{self.version}")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(outputs, {}, "metadata must not be published without both labels")
                git(self.work, "reset", "--quiet", "--hard", "HEAD~1")
                git(self.work, "push", "--quiet", "--force", "origin", "HEAD:refs/heads/stable")

    def test_empty_fsdk_label_is_refused(self):
        emptied = re.sub(r"('io\.projectbluefin\.fsdk\.ref':\s*)'[^']*'", r"\1''", self.element_text)
        self.assertNotEqual(emptied, self.element_text)
        self.commit(self.version, emptied, "empty fsdk ref")
        git(self.work, "push", "--quiet", "origin", "HEAD:refs/heads/stable")
        result, outputs = self.run_gate(f"v{self.version}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})


if __name__ == "__main__":
    unittest.main()
