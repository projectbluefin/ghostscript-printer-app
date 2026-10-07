#!/usr/bin/env python3
"""Execute update-base.yml's "Propose the update" step against fixture repos.

That step is the only place in this repository that pushes with a write
credential on a schedule. It decides which deps/fsdk-containers* branch it may
overwrite (only one whose tip was authored AND committed by mergeraptor[bot]),
force-pushes with a lease so a concurrent reviewer edit is never lost, opens a
fresh branch instead of clobbering a reviewer's amendment, and comments on the
reviewer's PR only once. It runs only when fsdk-containers actually moves, so
none of those branches had ever executed outside production.

The test lifts the step's run block out of the workflow verbatim and runs it
with bash in throwaway repositories: https://github.com/ is redirected to a
local bare repository through git's url.<base>.insteadOf, and `gh` is a stub
that records its arguments. A change to the step is tested as written.
"""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/update-base.yml"
STEP_NAME = "Propose the update"
REPOSITORY = "example/ghostscript-printer-app"
BOT_NAME = "mergeraptor[bot]"
BOT_EMAIL = "267480593+mergeraptor[bot]@users.noreply.github.com"
HUMAN_EMAIL = "reviewer@example.invalid"
OLD = "1" * 40
NEW = "abcdef0123456789" + "2" * 24
TOKEN = "fixture-token-not-a-secret-0123"
STAGED = [
    "elements/fsdk-containers.bst",
    "VERSION",
    "elements/printer-app/ijs.bst",
    "elements/oci/ghostscript-printer-app.bst",
    "README.md",
    "examples/ghostscript-printer-app-usb.container",
]

GH_STUB = """#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["GH_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["pr", "list"]:
    head = args[args.index("--head") + 1]
    prs = json.loads(open(os.environ["GH_PRS"]).read())
    # gh's --jq prints a bare newline for null, as on an empty result.
    print(prs.get(head, ""))
"""

# Moves the remote branch named in MOVE_BRANCH right before the step's push,
# reproducing a reviewer edit that lands between inspection and push.
GIT_WRAPPER = """#!/usr/bin/env bash
if [[ -n "${MOVE_BRANCH:-}" && " $* " == *" push "* && ! -e "$MOVE_DONE" ]]; then
  : > "$MOVE_DONE"
  "$REAL_GIT" --git-dir="$ORIGIN" update-ref "refs/heads/$MOVE_BRANCH" "$MOVE_TO"
fi
exec "$REAL_GIT" "$@"
"""


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
    block_indent = min(len(line) - len(line.lstrip()) for line in body if line.strip())
    return "\n".join(line[block_indent:] for line in body) + "\n"


class UpdateBaseProposal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = step_script(WORKFLOW, STEP_NAME)
        cls.real_git = shutil.which("git")

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="update-base-proposal."))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.work = self.tmp / "work"
        self.gitconfig = self.tmp / "gitconfig"
        self.gitconfig.write_text(
            f'[url "file://{self.tmp}/"]\n'
            f"\tinsteadOf = https://github.com/{REPOSITORY.split('/')[0]}/\n"
            "[init]\n\tdefaultBranch = testing\n"
            "[commit]\n\tgpgsign = false\n"
            "[advice]\n\tdetachedHead = false\n"
        )
        # The redirect maps https://github.com/<owner>/<repo>.git to
        # <tmp>/<repo>.git, so name the bare repository after the repo.
        self.origin = self.tmp / f"{REPOSITORY.split('/')[1]}.git"
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.install(self.bin / "gh", GH_STUB)
        self.install(self.bin / "git", GIT_WRAPPER)
        self.gh_log = self.tmp / "gh.log"
        self.gh_log.write_text("")
        self.gh_prs = self.tmp / "gh-prs.json"
        self.gh_prs.write_text("{}")

        self.git(self.tmp, "init", "--quiet", "--bare", str(self.origin))
        self.git(self.tmp, "init", "--quiet", str(self.work))
        for path in STAGED:
            target = self.work / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"{path}\n")
        (self.work / "elements/fsdk-containers.bst").write_text(f"  ref: {OLD}\n")
        self.git(self.work, "add", "-A")
        self.git(self.work, "commit", "--quiet", "-m", "base",
                 env=self.identity(HUMAN_EMAIL, HUMAN_EMAIL))
        self.base = self.git(self.work, "rev-parse", "HEAD")
        self.git(self.work, "push", "--quiet", str(self.origin), "HEAD:refs/heads/testing")
        # What the "Track fsdk-containers" and "Synchronize source metadata"
        # steps leave behind for this one.
        (self.work / "elements/fsdk-containers.bst").write_text(f"  ref: {NEW}\n")
        (self.work / ".bst/update-evidence").mkdir(parents=True)
        (self.work / ".bst/update-evidence/sources.txt").write_text("SOURCES-EVIDENCE\n")

    @staticmethod
    def install(path, text):
        path.write_text(text)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def base_env(self):
        return {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(self.tmp),
            "GIT_CONFIG_GLOBAL": str(self.gitconfig),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TEMPLATE_DIR": "",
            "REAL_GIT": self.real_git,
            "ORIGIN": str(self.origin),
            "MOVE_DONE": str(self.tmp / "moved"),
        }

    @staticmethod
    def identity(author, committer):
        return {
            "GIT_AUTHOR_NAME": "a", "GIT_AUTHOR_EMAIL": author,
            "GIT_COMMITTER_NAME": "c", "GIT_COMMITTER_EMAIL": committer,
        }

    def git(self, cwd, *args, env=None):
        full_env = self.base_env()
        full_env.update(env or {})
        full_env["PATH"] = os.environ["PATH"]
        return subprocess.run([self.real_git, *args], cwd=cwd, env=full_env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def seed_branch(self, name, author, committer, message="seed"):
        """Create refs/heads/<name> on origin with one commit on top of testing."""
        scratch = self.tmp / f"seed-{name.replace('/', '_')}"
        self.git(self.tmp, "clone", "--quiet", "--branch", "testing", str(self.origin), str(scratch))
        (scratch / "README.md").write_text(f"{message}\n")
        self.git(scratch, "commit", "--quiet", "-am", message, env=self.identity(author, committer))
        self.git(scratch, "push", "--quiet", "origin", f"HEAD:refs/heads/{name}")
        return self.git(scratch, "rev-parse", "HEAD")

    def remote_head(self, name):
        return self.git(self.tmp, "--git-dir", str(self.origin), "rev-parse", "--verify",
                        "--quiet", f"refs/heads/{name}")

    def has_remote_branch(self, name):
        return subprocess.run(
            [self.real_git, "--git-dir", str(self.origin), "rev-parse", "--verify", "--quiet",
             f"refs/heads/{name}"], capture_output=True).returncode == 0

    def run_step(self, open_prs=None, extra_env=None):
        self.gh_prs.write_text(json.dumps(open_prs or {}))
        env = self.base_env()
        env.update({
            "GH_TOKEN": TOKEN,
            "GH_LOG": str(self.gh_log),
            "GH_PRS": str(self.gh_prs),
            "REPOSITORY": REPOSITORY,
            "OLD": OLD,
            "NEW": NEW,
            "GITHUB_RUN_ID": "4242",
        })
        env.update(extra_env or {})
        result = subprocess.run(["bash", "-c", self.script], cwd=self.work, env=env,
                                capture_output=True, text=True)
        calls = [json.loads(line) for line in self.gh_log.read_text().splitlines()]
        return result, calls

    def body_of(self, call):
        return Path(call[call.index("--body-file") + 1]).read_text()

    def assert_bot_commit(self, branch):
        head = self.remote_head(branch)
        fmt = self.git(self.tmp, "--git-dir", str(self.origin), "log", "-1",
                       "--format=%an|%ae|%cn|%ce|%s%n%b", head)
        first, _, trailer = fmt.partition("\n")
        self.assertEqual(
            first,
            f"{BOT_NAME}|{BOT_EMAIL}|{BOT_NAME}|{BOT_EMAIL}|"
            f"chore(deps): update fsdk-containers to {NEW[:12]}")
        self.assertIn(f"Signed-off-by: {BOT_NAME} <{BOT_EMAIL}>", trailer)
        parent = self.git(self.tmp, "--git-dir", str(self.origin), "rev-parse", f"{head}^")
        self.assertEqual(parent, self.base, "the proposal must sit directly on the checked-out base")
        files = self.git(self.tmp, "--git-dir", str(self.origin), "show", f"{head}:elements/fsdk-containers.bst")
        self.assertEqual(files, f"ref: {NEW}")
        changed = self.git(self.tmp, "--git-dir", str(self.origin), "diff", "--name-only", f"{head}^", head)
        self.assertEqual(changed.splitlines(), ["elements/fsdk-containers.bst"])

    def test_step_is_extracted(self):
        self.assertIn("--force-with-lease", self.script)
        self.assertIn("gh pr create", self.script)

    def test_first_run_creates_branch_and_opens_pr(self):
        result, calls = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_bot_commit("deps/fsdk-containers")
        self.assertNotIn("::warning::", result.stdout + result.stderr)
        self.assertEqual([c[:2] for c in calls], [["pr", "list"], ["pr", "create"]])
        create = calls[1]
        self.assertEqual(create[create.index("--base") + 1], "testing")
        self.assertEqual(create[create.index("--head") + 1], "deps/fsdk-containers")
        self.assertEqual(create[create.index("--title") + 1],
                         f"chore(deps): update fsdk-containers to {NEW[:12]}")
        body = self.body_of(create)
        self.assertIn(f"https://github.com/projectbluefin/fsdk-containers/compare/{OLD}...{NEW}", body)
        self.assertIn("SOURCES-EVIDENCE", body)
        self.assertIn(f"https://github.com/{REPOSITORY}/actions/runs/4242", body)
        self.assertNotIn("fresh proposal branch", body)

    def test_token_is_masked_and_never_persisted(self):
        result, _ = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        self.assertIn("::add-mask::", result.stdout)
        self.assertNotIn("extraheader", (self.work / ".git/config").read_text())
        for path in (self.work / ".git").rglob("*"):
            if path.is_file() and path.suffix not in {".pack", ".idx"}:
                self.assertNotIn(TOKEN.encode(), path.read_bytes(), path)

    def test_bot_owned_branch_is_reused_with_lease_and_pr_edited(self):
        old_head = self.seed_branch("deps/fsdk-containers", BOT_EMAIL, BOT_EMAIL)
        result, calls = self.run_step(open_prs={"deps/fsdk-containers": 17})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.remote_head("deps/fsdk-containers"), old_head)
        self.assert_bot_commit("deps/fsdk-containers")
        self.assertFalse(self.has_remote_branch("deps/fsdk-containers-2"))
        self.assertEqual([c[:2] for c in calls], [["pr", "list"], ["pr", "edit"]])
        self.assertEqual(calls[1][2], "17")
        self.assertIn("Updated dependency PR #17", result.stdout)

    def test_reviewer_authored_tip_is_left_alone(self):
        human_head = self.seed_branch("deps/fsdk-containers", HUMAN_EMAIL, HUMAN_EMAIL)
        result, calls = self.run_step(open_prs={"deps/fsdk-containers": 21})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), human_head)
        self.assert_bot_commit("deps/fsdk-containers-2")
        self.assertIn("::warning::deps/fsdk-containers has commits not authored and committed by "
                      "mergeraptor[bot]", result.stdout)
        kinds = [c[:2] for c in calls]
        self.assertEqual(kinds, [["pr", "list"], ["pr", "comment"], ["pr", "list"], ["pr", "create"]])
        self.assertEqual(calls[1][2], "21")
        self.assertIn("deps/fsdk-containers-2", calls[1][calls[1].index("--body") + 1])
        create = calls[3]
        self.assertEqual(create[create.index("--head") + 1], "deps/fsdk-containers-2")
        self.assertIn("`deps/fsdk-containers` has commits not authored and committed by",
                      self.body_of(create))

    def test_bot_author_with_reviewer_committer_counts_as_reviewer_owned(self):
        # An amend or rebase keeps the bot as author but changes the committer.
        amended = self.seed_branch("deps/fsdk-containers", BOT_EMAIL, HUMAN_EMAIL)
        result, calls = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), amended)
        self.assert_bot_commit("deps/fsdk-containers-2")
        create = [c for c in calls if c[:2] == ["pr", "create"]]
        self.assertEqual(len(create), 1)
        self.assertEqual(create[0][create[0].index("--head") + 1], "deps/fsdk-containers-2")

    def test_reviewer_author_with_bot_committer_counts_as_reviewer_owned(self):
        amended = self.seed_branch("deps/fsdk-containers", HUMAN_EMAIL, BOT_EMAIL)
        result, _ = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), amended)
        self.assert_bot_commit("deps/fsdk-containers-2")

    def test_existing_bot_fallback_branch_is_reused_without_repeating_the_notice(self):
        human_head = self.seed_branch("deps/fsdk-containers", HUMAN_EMAIL, HUMAN_EMAIL)
        self.seed_branch("deps/fsdk-containers-2", BOT_EMAIL, BOT_EMAIL)
        result, calls = self.run_step(open_prs={"deps/fsdk-containers": 21,
                                                "deps/fsdk-containers-2": 22})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), human_head)
        self.assert_bot_commit("deps/fsdk-containers-2")
        self.assertIn("::warning::", result.stdout)
        self.assertNotIn(["pr", "comment"], [c[:2] for c in calls],
                         "the notice must be posted only when the fallback branch is first created")
        self.assertEqual([c[:3] for c in calls if c[:2] == ["pr", "edit"]], [["pr", "edit", "22"]])

    def test_skips_every_reviewer_owned_branch_and_reports_the_first(self):
        first = self.seed_branch("deps/fsdk-containers", HUMAN_EMAIL, HUMAN_EMAIL)
        second = self.seed_branch("deps/fsdk-containers-2", HUMAN_EMAIL, HUMAN_EMAIL)
        result, calls = self.run_step(open_prs={"deps/fsdk-containers": 21,
                                                "deps/fsdk-containers-2": 22})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), first)
        self.assertEqual(self.remote_head("deps/fsdk-containers-2"), second)
        self.assert_bot_commit("deps/fsdk-containers-3")
        self.assertIn("::warning::deps/fsdk-containers has commits", result.stdout)
        comments = [c for c in calls if c[:2] == ["pr", "comment"]]
        self.assertEqual([c[2] for c in comments], ["21"])
        self.assertIn("deps/fsdk-containers-3", comments[0][comments[0].index("--body") + 1])

    def test_conflict_without_an_open_pr_posts_no_comment(self):
        self.seed_branch("deps/fsdk-containers", HUMAN_EMAIL, HUMAN_EMAIL)
        result, calls = self.run_step()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(["pr", "comment"], [c[:2] for c in calls])
        self.assertIn(["pr", "create"], [c[:2] for c in calls])

    def test_branch_moved_after_inspection_is_not_overwritten(self):
        self.seed_branch("deps/fsdk-containers", BOT_EMAIL, BOT_EMAIL)
        reviewer_edit = self.seed_branch("reviewer-edit", HUMAN_EMAIL, HUMAN_EMAIL, "reviewer edit")
        result, calls = self.run_step(
            open_prs={"deps/fsdk-containers": 17},
            extra_env={"MOVE_BRANCH": "deps/fsdk-containers", "MOVE_TO": reviewer_edit})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("::error::Refusing to force-push deps/fsdk-containers", result.stdout)
        self.assertEqual(self.remote_head("deps/fsdk-containers"), reviewer_edit)
        self.assertEqual(calls, [], "a refused push must not create or edit any PR")


if __name__ == "__main__":
    unittest.main()
