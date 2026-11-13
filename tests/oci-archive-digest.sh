#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/release"
digest="sha256:$(printf 'a%.0s' {1..64})"
printf '{"manifests":[{"digest":"%s"}]}' "$digest" > "$tmp/release/index.json"
# Match the archive construction in the release build job.
tar -C "$tmp/release" -cf "$tmp/image.oci" .
[[ "$("$root/scripts/oci-archive-digest.sh" "$tmp/image.oci")" == "$digest" ]]
printf '{"manifests":[]}' > "$tmp/release/index.json"
tar -C "$tmp/release" -cf "$tmp/image.oci" .
if "$root/scripts/oci-archive-digest.sh" "$tmp/image.oci" >/dev/null; then
    echo 'empty archive index was accepted' >&2
    exit 1
fi
