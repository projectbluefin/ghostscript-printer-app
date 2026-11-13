kind: import

# The signed shared printing runtime layer, staged by
# scripts/fetch-runtime-parent.sh (`just prepare-parent`) as an OCI layout at
# `runtime-parent`. build-oci mounts it at /parent so its layer is copied
# byte-for-byte into this image's layer 0 (issue #207). Consumers then share
# one download instead of each rebuilding the full FSDK printing runtime
# (docs/skills/printing-base.md "Consumer wiring").

sources:
  - kind: local
    path: runtime-parent
