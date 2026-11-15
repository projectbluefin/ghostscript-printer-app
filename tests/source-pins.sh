#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
junction=elements/fsdk-containers.bst
FSDK_CONTAINERS_REMOTE="${FSDK_CONTAINERS_REMOTE:-https://github.com/projectbluefin/fsdk-containers.git}"
fail() { printf 'source-pins: %s\n' "$*" >&2; exit 1; }
sha40='^[0-9a-f]{40}$'

# Publishing derives its FSDK metadata from this exact junction commit.
junction_ref="$(sed -n -E 's/^ +ref: .*([0-9a-f]{40})$/\1/p' "$junction")"
[[ "$junction_ref" =~ $sha40 ]] || fail "$junction does not pin a full fsdk-containers commit"
# Assign first: a failure inside a here-string's $(...) would not stop set -e.
fsdk_pin="$(scripts/fsdk-pin.sh "$junction_ref" "$FSDK_CONTAINERS_REMOTE")"
read -r fsdk_version fsdk_ref <<< "$fsdk_pin"
[[ -n "$fsdk_version" && "$fsdk_ref" =~ $sha40 ]] || fail "invalid FSDK metadata: $fsdk_pin"
printf 'OK: FSDK %s@%s via fsdk-containers %s\n' "$fsdk_version" "$fsdk_ref" "$junction_ref"
