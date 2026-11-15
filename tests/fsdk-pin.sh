#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
script="$PWD/scripts/fsdk-pin.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" config user.name 'Test'
git -C "$tmp" config user.email 'test@example.invalid'
mkdir -p "$tmp/elements"
ref=0123456789abcdef0123456789abcdef01234567
printf 'ref: freedesktop-sdk-26.08.4-3-g%s\n' "$ref" > "$tmp/elements/freedesktop-sdk.bst"
git -C "$tmp" add elements/freedesktop-sdk.bst
git -C "$tmp" commit -qm valid
commit="$(git -C "$tmp" rev-parse HEAD)"
[[ "$("$script" "$commit" "$tmp")" == "26.08.4 $ref" ]]
printf 'ref: invalid\n' > "$tmp/elements/freedesktop-sdk.bst"
git -C "$tmp" commit -qam invalid
commit="$(git -C "$tmp" rev-parse HEAD)"
if "$script" "$commit" "$tmp" > /dev/null 2>&1; then
  echo 'invalid FSDK ref was accepted' >&2
  exit 1
fi
git -C "$tmp" rm -q elements/freedesktop-sdk.bst
git -C "$tmp" commit -qm missing
commit="$(git -C "$tmp" rev-parse HEAD)"
if "$script" "$commit" "$tmp" > /dev/null 2>&1; then
  echo 'missing FSDK junction was accepted' >&2
  exit 1
fi
