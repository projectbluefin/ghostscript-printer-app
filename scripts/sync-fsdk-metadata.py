#!/usr/bin/env python3
"""Move VERSION and IJS with the Ghostscript that the fsdk-containers pin resolves.

FSDK labels are derived at publish time, so a junction bump needs no metadata
change unless it moves Ghostscript; then the appliance parity gate fails until
this runs.
"""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GHOSTSCRIPT = "fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst"
IJS = "elements/printer-app/ijs.bst"
PATHS = ("VERSION", IJS)


def release(info, url, prefix):
    """Require one exact release, never infer a version from a branch commit."""
    pattern = (
        r"^- kind: (?:git_repo|git)\n  url: " + re.escape(url) + r"\n"
        r"(?:  .*\n)*?  version: ([0-9a-f]{40})\n"
        r"(?:  .*\n)*?    tag-name: " + re.escape(prefix)
        + r"([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:rc\.[0-9]+)?)\n"
        r"    commit-offset: 0$"
    )
    matches = re.findall(pattern, info, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"expected one exact {prefix} release in resolved provenance")
    commit, version = matches[0]
    return version, commit


def source_info(target):
    return subprocess.check_output(
        ["just", "bst", "--no-colors", "show", "--deps", "none",
         "--format", "%{source-info}", target], cwd=ROOT, text=True,
    )


def replace(text, pattern, replacement):
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"expected one metadata field matching {pattern}")
    return updated


def synchronize(root, gs_info):
    gs_version, gs_ref = release(
        gs_info, "https://github.com/ArtifexSoftware/ghostpdl.git", "ghostpdl-")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", gs_version):
        raise ValueError("Ghostscript must be a stable three-component release")
    originals = {name: (root / name).read_text() for name in PATHS}
    current = originals["VERSION"].strip()
    match = re.fullmatch(r"([0-9]+\.[0-9]+\.[0-9]+)-([1-9][0-9]*)", current)
    if not match:
        raise ValueError("VERSION must be a Ghostscript release plus positive revision")
    # The packaging revision restarts with each Ghostscript release and is
    # otherwise only raised by hand.
    version = current if gs_version == match[1] else f"{gs_version}-1"
    ijs = replace(originals[IJS], r"^    track: .+$", f"    track: ghostpdl-{gs_version}")
    updates = {
        "VERSION": version + "\n",
        IJS: replace(ijs, r"^    ref: .+$", f"    ref: ghostpdl-{gs_version}-0-g{gs_ref}"),
    }
    # Validate all fields before writing; restore on a failed write as well.
    try:
        for name, contents in updates.items():
            if contents != originals[name]:
                (root / name).write_text(contents)
    except BaseException:
        for name, contents in originals.items():
            (root / name).write_text(contents)
        raise
    return f"Ghostscript {gs_version} ({gs_ref}); application {version}"


if __name__ == "__main__":
    print(synchronize(ROOT, source_info(GHOSTSCRIPT)))
