#!/usr/bin/env python3
"""Assert that promote-stable.yml verify job context matches ci.yml.

Stable branch protection enforces required status check contexts:
  - FSDK (x86_64)
  - FSDK (aarch64)

The promotion workflow's pre-push verification job must produce these exact
check-run contexts before fast-forwarding stable; otherwise GitHub's protected
branch hook rejects the push with GH006 (as seen in run 37175625052).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CI_WORKFLOW = ROOT / ".github/workflows/ci.yml"
PROMOTE_WORKFLOW = ROOT / ".github/workflows/promote-stable.yml"


def extract_job_name(workflow_path, job_id):
    content = workflow_path.read_text()
    pattern = rf"^\s*{re.escape(job_id)}:\s*\n\s*name:\s*(.+)$"
    match = re.search(pattern, content, re.MULTILINE)
    if not match:
        raise ValueError(f"Could not find job '{job_id}' in {workflow_path}")
    return match.group(1).strip()


def main():
    ci_name = extract_job_name(CI_WORKFLOW, "build-fsdk")
    promote_name = extract_job_name(PROMOTE_WORKFLOW, "verify")

    if ci_name != promote_name:
        print(
            f"FAIL: promote-stable.yml verify job name '{promote_name}' "
            f"does not match ci.yml build-fsdk job name '{ci_name}'",
            file=sys.stderr,
        )
        return 1

    expected_contexts = [
        promote_name.replace("${{ matrix.arch }}", arch)
        for arch in ("x86_64", "aarch64")
    ]
    required_contexts = ["FSDK (x86_64)", "FSDK (aarch64)"]
    if expected_contexts != required_contexts:
        print(
            f"FAIL: generated contexts {expected_contexts} do not match "
            f"required stable branch protection contexts {required_contexts}",
            file=sys.stderr,
        )
        return 1

    print(
        f"OK: promote-stable.yml job name '{promote_name}' matches ci.yml "
        f"and generates required contexts: {', '.join(required_contexts)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
