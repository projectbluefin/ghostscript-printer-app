#!/usr/bin/env python3
"""Synchronize application metadata from the resolved, FSDK-owned sources."""

import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FSDK = "fsdk-containers.bst:freedesktop-sdk.bst"
# `examples/ghostscript-printer-app-usb.container` carries the published OCI
# tag in two places (Image= and the `ExecStartPre=` argument). The Quadlet
# tracks VERSION, so the example never references a tag the appliance has not
# yet published (#82).
QUADLET_PATH = "examples/ghostscript-printer-app-usb.container"
PATHS = ("VERSION", "elements/printer-app/ijs.bst",
         "elements/oci/ghostscript-printer-app.bst", "README.md", QUADLET_PATH)
QUADLET_IMAGE = "ghcr.io/projectbluefin/ghostscript-printer-app"
QUADLET_TAG_RE = re.compile(
    re.escape(QUADLET_IMAGE) + r":[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*"
)


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


def synchronize(root, old, new, fsdk_info, gs_info):
    for commit in (old, new):
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValueError("base refs must be full commits")
    fsdk_version, fsdk_ref = release(
        fsdk_info, "https://gitlab.com/freedesktop-sdk/freedesktop-sdk.git", "freedesktop-sdk-")
    gs_version, gs_ref = release(
        gs_info, "https://github.com/ArtifexSoftware/ghostpdl.git", "ghostpdl-")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", gs_version):
        raise ValueError("Ghostscript must be a stable three-component release")
    originals = {name: (root / name).read_text() for name in PATHS}
    current = originals["VERSION"].strip()
    match = re.fullmatch(r"([0-9]+\.[0-9]+\.[0-9]+)-([1-9][0-9]*)", current)
    if not match:
        raise ValueError("VERSION must be a Ghostscript release plus positive revision")
    if old == new:
        raise ValueError("metadata synchronization requires a changed base commit")
    revision = int(match[2]) + 1 if gs_version == match[1] else 1
    version = f"{gs_version}-{revision}"
    updates = {"VERSION": version + "\n"}
    ijs = replace(originals[PATHS[1]], r"^    track: .+$", f"    track: ghostpdl-{gs_version}")
    updates[PATHS[1]] = replace(ijs, r"^    ref: .+$", f"    ref: ghostpdl-{gs_version}-0-g{gs_ref}")
    oci = originals[PATHS[2]]
    for key, value in (("version", fsdk_version), ("ref", fsdk_ref)):
        oci = replace(oci, rf"^(\s*'io\.projectbluefin\.fsdk\.{key}': )'[^']+'$",
                      rf"\g<1>'{value}'")
    updates[PATHS[2]] = oci
    updates["README.md"] = replace(originals["README.md"], r"^version=[0-9].*$", f"version={version}")
    # The Quadlet example pins the OCI tag in both Image= and ExecStartPre=
    # (`tests/rootless-usb.py` already enforces both lines agree on the same
    # value). Replace every occurrence so a release-bump cannot leave the
    # example referencing an older appliance than VERSION documents (#82).
    quadlet, count = QUADLET_TAG_RE.subn(f"{QUADLET_IMAGE}:{version}", originals[QUADLET_PATH])
    if count != 2:
        raise ValueError(
            f"expected exactly two image tags in {QUADLET_PATH} "
            f"(Image= and ExecStartPre=); found {count}"
        )
    updates[QUADLET_PATH] = quadlet
    # Validate all fields before writing; restore on a failed write as well.
    try:
        for name, contents in updates.items():
            (root / name).write_text(contents)
    except BaseException:
        for name, contents in originals.items():
            (root / name).write_text(contents)
        raise
    return f"FSDK {fsdk_version} ({fsdk_ref}); Ghostscript {gs_version} ({gs_ref}); application {version}"


def upstream_release(url, prefix):
    """Observe stable upstream tags without making them source inputs."""
    try:
        refs = subprocess.check_output(
            ["git", "ls-remote", "--tags", "--refs", url, f"refs/tags/{prefix}*"],
            text=True, timeout=60,
        )
        versions = re.findall(r"refs/tags/" + re.escape(prefix)
                              + r"([0-9]+\.[0-9]+(?:\.[0-9]+)?)$", refs, re.MULTILINE)
        return max(versions, key=lambda v: tuple(map(int, v.split("."))))
    except (subprocess.SubprocessError, ValueError):
        return "unknown (upstream lookup failed)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    args = parser.parse_args()
    print(synchronize(ROOT, args.old, args.new, source_info(FSDK),
                      source_info(FSDK + ":components/ghostscript.bst")))
    for label, url, prefix in (
        ("Upstream FSDK", "https://gitlab.com/freedesktop-sdk/freedesktop-sdk.git", "freedesktop-sdk-"),
        ("Upstream Ghostscript", "https://github.com/ArtifexSoftware/ghostpdl.git", "ghostpdl-"),
    ):
        print(f"{label} latest stable tag: {upstream_release(url, prefix)}")


if __name__ == "__main__":
    main()
