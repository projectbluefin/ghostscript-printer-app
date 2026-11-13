#!/usr/bin/env bash
# Fetch cosign-verify the shared printing runtime layer and stage it as an OCI
# layout at `runtime-parent/` for elements/printer-app/runtime-parent.bst to
# mount at /parent (issue #207). Mirrors docs/skills/printing-base.md
# "Consumer wiring": compute the key, resolve + cosign-verify the digest, then
# skopeo writes the layout. The doc requires this to abort on any failed
# command (set -euo pipefail, no fallback): a partial or missing parent would
# silently break the shared-digest contract, so a fetch failure must fail.
set -euo pipefail

cd "$(dirname "$0")/.."
arch="$(uname -m)"
case "$arch" in x86_64|aarch64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac

# The tag is <arch>-<full-key> of fsdk-containers' printing-runtime-layer. The
# element lives under the fsdk-containers junction, so the key is computed from
# it. Fail explicitly on an empty/invalid key so we never build a tag like
# `${arch}-` (an empty key would slip past `set -e` through jq).
key="$(just bst -o arch "$arch" show --deps none --format '%{full-key}' \
  fsdk-containers.bst:oci/printing-runtime-layer.bst | tail -n 1 | sed 's/\x1b\[[0-9;]*m//g')"
[[ "$key" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid runtime layer key: '${key}'" >&2; exit 1; }

repo=ghcr.io/projectbluefin/printing-runtime-layer
digest="$(skopeo inspect --format '{{.Digest}}' "docker://${repo}:${arch}-${key}")"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "Invalid runtime layer digest: '${digest}'" >&2; exit 1; }
ref="${repo}@${digest}"

cosign verify \
  --certificate-identity https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-runtime-layer.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com "$ref" >/dev/null

# skopeo writes the OCI layout to a temp dir, then we move it into place so a
# crash never leaves a half-fetched `runtime-parent/` behind.
tmp="$(mktemp -d "${PWD}/.runtime-parent.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
skopeo copy --preserve-digests "docker://${ref}" "oci:${tmp}:layer"
# Keep the staged layout tracked by git even though it is a build artifact.
touch "$tmp/.gitkeep"
rm -rf runtime-parent
mv "$tmp" runtime-parent
