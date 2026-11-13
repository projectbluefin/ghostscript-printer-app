#!/usr/bin/env bash
set -euo pipefail

# The build archives the layout with `tar -C release ... .`, so its members
# have a ./ prefix. Read the index without unpacking the image layers.
layout="$(tar -xOf "$1" ./index.json)"
jq -e '.manifests | length == 1' <<< "$layout" >/dev/null
digest="$(jq -r '.manifests[0].digest' <<< "$layout")"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
printf '%s\n' "$digest"
