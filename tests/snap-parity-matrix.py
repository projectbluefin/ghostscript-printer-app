#!/usr/bin/env python3
"""Derive docs/snap-parity-matrix.md's literal columns from their sources.

The matrix reproduces two sets of literals that live elsewhere in this
repository: every directly-pinned element ref under `elements/printer-app/`
and every Snap part version in `snap/snapcraft.yaml`. Nothing compared those
copies against their sources, so the document could drift silently against
both. This check makes the document a derived view: it re-reads the sources
and fails when a reproduced literal, a Status verdict, or the "Differs" list
in the prose no longer follows from them.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MATRIX = ROOT / "docs/snap-parity-matrix.md"
ELEMENTS = ROOT / "elements/printer-app"
SNAPCRAFT = ROOT / "snap/snapcraft.yaml"

BACKTICKED = re.compile(r"`([^`]+)`")
ELEMENT_CELL = re.compile(r"`elements/printer-app/([\w.+-]+)\.bst`: (.*)")
SNAP_CELL = re.compile(r"`([\w.+-]+)` part: (.*)")
DIFFERS_PROSE = re.compile(r'^- "Differs" rows — (.*?) — are known,', re.MULTILINE)

errors = []


def fail(message):
    errors.append(message)


def read_element(name):
    """Return (url, track, ref) for elements/printer-app/<name>.bst."""
    path = ELEMENTS / f"{name}.bst"
    if not path.exists():
        return None
    fields = {}
    for key in ("url", "track", "ref"):
        found = re.search(rf"^\s*{key}:\s*(\S+)\s*$", path.read_text(), re.MULTILINE)
        fields[key] = found.group(1) if found else None
    return fields


def read_snap_parts():
    """Return {part: {field: value}} for snapcraft's source pinning fields."""
    parts = {}
    current = None
    in_parts = False
    for line in SNAPCRAFT.read_text().splitlines():
        if re.match(r"^\w", line):
            in_parts = line.startswith("parts:")
            current = None
            continue
        if not in_parts:
            continue
        part = re.match(r"^  ([\w.+-]+):\s*$", line)
        if part:
            current = part.group(1)
            parts[current] = {}
            continue
        field = re.match(r"^    (source-tag|source-commit|source-branch):\s*(\S+)\s*$", line)
        if field and current:
            parts[current][field.group(1)] = field.group(2).strip("'\"")
    return parts


def element_ref_matches(ref, literal):
    """BuildStream git refs are `<tag>-<depth>-g<sha>` or a bare commit sha."""
    return ref == literal or ref.startswith(f"{literal}-")


def table_rows(text):
    """Yield the four cells of every row in the driver/component matrix."""
    section = text.split("## Driver/component matrix", 1)
    if len(section) != 2:
        fail("docs/snap-parity-matrix.md: no '## Driver/component matrix' section")
        return
    body = section[1].split("\n## ", 1)[0]
    for line in body.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split(" | ")]
        if len(cells) != 4 or cells[0] in ("Component", "---"):
            continue
        yield cells


def check_fsdk_cell(component, cell):
    """Verify a reproduced elements/printer-app literal. Returns its tag."""
    match = ELEMENT_CELL.search(cell)
    if not match:
        return None
    name, rest = match.group(1), match.group(2)
    element = read_element(name)
    if element is None:
        fail(f"{component}: elements/printer-app/{name}.bst does not exist")
        return None

    commit = re.search(r"commit `([0-9a-f]+)`", rest)
    if commit:
        if not element["ref"] or not element["ref"].startswith(commit.group(1)):
            fail(
                f"{component}: matrix says commit {commit.group(1)}, "
                f"{name}.bst pins ref {element['ref']}"
            )
        tracks = re.search(r"tracks `([^`]+)`", rest)
        if tracks and element["track"] != tracks.group(1):
            fail(
                f"{component}: matrix says it tracks {tracks.group(1)}, "
                f"{name}.bst tracks {element['track']}"
            )
        return None

    literals = BACKTICKED.findall(rest)
    if not literals:
        return None
    tag = literals[-1]
    for upstream in literals[:-1]:
        if upstream not in (element["url"] or ""):
            fail(
                f"{component}: matrix names upstream {upstream}, "
                f"{name}.bst builds from {element['url']}"
            )
    if not element["ref"] or not element_ref_matches(element["ref"], tag):
        fail(f"{component}: matrix says {tag}, {name}.bst pins ref {element['ref']}")
    return tag


def check_snap_cell(component, cell, parts):
    """Verify a reproduced snapcraft.yaml literal. Returns its tag."""
    match = SNAP_CELL.search(cell)
    if not match:
        return None
    name, rest = match.group(1), match.group(2)
    if name not in parts:
        fail(f"{component}: snap/snapcraft.yaml has no part named {name}")
        return None
    part = parts[name]

    if "no `source-tag`" in rest:
        if "source-tag" in part:
            fail(
                f"{component}: matrix says the {name} part is unpinned, "
                f"snapcraft.yaml pins source-tag {part['source-tag']}"
            )
        return None

    literals = BACKTICKED.findall(rest)
    if not literals:
        return None
    tag = literals[-1]
    if part.get("source-tag") != tag:
        fail(
            f"{component}: matrix says {name} part {tag}, "
            f"snapcraft.yaml pins {part.get('source-tag')}"
        )
    return tag


def main():
    text = MATRIX.read_text()
    parts = read_snap_parts()
    if not parts:
        fail("snap/snapcraft.yaml: no parts parsed")

    differs = []
    compared = 0
    for component, fsdk_cell, snap_cell, status in table_rows(text):
        fsdk_tag = check_fsdk_cell(component, fsdk_cell)
        snap_tag = check_snap_cell(component, snap_cell, parts)
        verdict = status.split("—")[0].strip().strip("*").lower()
        if verdict == "differs":
            differs.append(BACKTICKED.sub(r"\1", component))
        if fsdk_tag is None or snap_tag is None:
            continue
        compared += 1
        expected = "match" if fsdk_tag == snap_tag else "differs"
        if verdict != expected:
            fail(
                f"{component}: matrix status is '{verdict}' but the FSDK ref "
                f"{fsdk_tag} and the Snap ref {snap_tag} say '{expected}'"
            )

    if compared == 0:
        fail("docs/snap-parity-matrix.md: no directly-pinned rows were compared")

    prose = DIFFERS_PROSE.search(text)
    if not prose:
        fail('docs/snap-parity-matrix.md: no machine-checkable \'"Differs" rows — ... —\' bullet')
    else:
        listed = [name.strip() for name in BACKTICKED.findall(prose.group(1))]
        if sorted(listed) != sorted(differs):
            fail(
                f"the \"Differs\" prose names {listed}, but the table marks "
                f"{differs} as differs"
            )

    if errors:
        for error in errors:
            print(f"snap-parity-matrix: {error}", file=sys.stderr)
        return 1
    print(f"OK: docs/snap-parity-matrix.md agrees with its sources ({compared} pinned rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
