# BuildStream runs in the pinned freedesktop-sdk builder image. The tag names
# the source commit for readability, but a registry tag is mutable — the
# @sha256 digest is the immutable pin podman actually pulls by. When bumping
# the tag, refresh the digest too:
#   skopeo inspect --format '{{.Digest}}' docker://<image>:<tag>
bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d@sha256:2ca3b449b594e9284bd60f436a4efad1365116b7d3d7129fd08b7a4f459d3561")
image_ref := "ghcr.io/projectbluefin/ghostscript-printer-app:build"

default:
    @just --list

# BST_FLAGS adds global bst options, e.g. CI's `--config /src/ci/buildstream.conf`.
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    RE_FLAG=()
    PF_PID=""
    cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true; }
    trap cleanup EXIT
    if [[ "${BST_REMOTE:-0}" == "1" ]]; then
        export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/bluespeed.yaml}"
        kubectl port-forward -n buildbarn svc/frontend 18980:8980 >/dev/null 2>&1 &
        PF_PID=$!
        for _ in $(seq 1 20); do
            (echo > /dev/tcp/127.0.0.1/18980) 2>/dev/null && break
            sleep 0.5
        done
        cat > .bst-re.conf <<'EOF'
    remote-execution:
      execution-service:
        url: grpc://127.0.0.1:18980
      storage-service:
        url: grpc://127.0.0.1:18980
      action-cache-service:
        url: grpc://127.0.0.1:18980
    EOF
        RE_FLAG=(--config /src/.bst-re.conf)
    fi
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{ bst2_image }}" \
        bash -c 'bst "$@"' -- --no-interactive ${BST_FLAGS:-} "${RE_FLAG[@]}" {{ ARGS }}

# Every check here runs on the host in seconds with no image and no printer, so
# the pull-request gate runs it before the 360-minute appliance build. Keep it
# that way: anything needing the built image belongs in `just verify`.
# Needs PyYAML for tests/test_python_install_pins.py: pip install -r .github/requirements-ci.txt
validate:
    just verify-rootless-usb
    just verify-entrypoint-validation
    tests/seed-printing-base.sh
    tests/oci-archive-digest.sh
    python3 tests/snap-parity-matrix.py
    python3 tests/test_snap_parity_matrix.py
    PYTHONDONTWRITEBYTECODE=1 python3 tests/renovate.py
    python3 tests/test_python_install_pins.py
    just bst show --deps all oci/ghostscript-printer-app.bst

# Never fails: falls back to building the base locally (see ci/seed-printing-base.sh).
# Seed the BuildStream cache with the cosign-verified printing base for ARCH.
seed-printing-base ARCH:
    ARCH={{ ARCH }} ci/seed-printing-base.sh

fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    for attempt in 1 2 3; do
        if just bst source fetch --ignore-project-source-remotes \
            --source-remote https://cache.projectbluefin.io:11001 \
            --deps all oci/ghostscript-printer-app.bst; then
            exit 0
        fi
        echo "source fetch failed (attempt ${attempt}/3)" >&2
        if [[ "$attempt" -lt 3 ]]; then sleep 15; fi
    done
    exit 1


build:
    #!/usr/bin/env bash
    set -euo pipefail
    # Fetch the shared printing runtime layer (issue #207) before building so
    # elements/printer-app/runtime-parent.bst can stage its layout at /parent.
    # Needs skopeo + cosign.
    just prepare-parent
    just bst build oci/ghostscript-printer-app.bst
    just export

export:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build-out
    just bst artifact checkout oci/ghostscript-printer-app.bst --directory /src/.build-out
    IMAGE_ID=$(podman pull -q oci:.build-out)
    # Keep .build-out: releases publish this layout directly, since container
    # storage may recompress layer 0 and break the shared digest.
    podman tag "$IMAGE_ID" "{{ image_ref }}"

# Fetch the shared printing runtime layer (issue #207) before building.
# Cosign verifies the signature, then skopeo writes the OCI layout to
# runtime-parent/ for elements/printer-app/runtime-parent.bst to mount at
# /parent. Needs skopeo + cosign.
prepare-parent:
    bash scripts/fetch-runtime-parent.sh

# Layer 0 of the built image must be the shared runtime layer, byte for byte,
# so families pinned to the same fsdk-containers ref share one download.
check-shared-layer layout=".build-out":
    #!/usr/bin/env bash
    set -euo pipefail
    parent="$(skopeo inspect --raw oci:runtime-parent:layer | jq -r '.layers[0].digest')"
    child="$(skopeo inspect --raw "oci:{{ layout }}" | jq -r '.layers[0].digest')"
    echo "parent=${parent} child=${child}"
    [[ "${parent}" == sha256:* && "${parent}" == "${child}" ]]

verify-core:
    tests/core-appliance.sh

# Requires host Avahi and avahi-browse; see docs/oci-discovery-validation.md.
verify-service-advertisements:
    just build
    tests/service-advertisements.sh

verify-payload:
    tests/core-payload.sh

verify-raster-drivers:
    tests/standalone-raster-drivers.sh

verify-packaged-drivers:
    tests/packaged-drivers.sh

verify-stateful-drivers:
    tests/stateful-drivers.sh

verify-ghostscript-romfs:
    tests/ghostscript-romfs.sh

# The driver auto-add picks from an IEEE-1284 device ID: model-specific PPD
# first, then the Generic PostScript, PCL XL, PCL 5c and PCL 5e fallbacks.
verify-driver-autoselect:
    tests/driver-autoselect.sh

verify-cups-patch-chain:
    tests/cups-patch-chain.sh

# Default (no-PORT) port coexistence (issue #17, "Default port and coexistence
# case"): PAPPL's default listener starts at 7999 + UID % 1000 (8532 for 65532)
# and steps to the next free port; PR #57 only exercised explicit ports. Host
# Avahi + multicast; opt-in, not part of `just verify`.
verify-discovery-default-port:
    tests/discovery-default-port.sh

# fsdk-containers printing-base contract rule 5: the image composes runtime
# domains only, so no headers, static/libtool archives, pkg-config or CMake
# files may reach it (license texts are exempt). Run after an image build (`just build`).
verify-no-devel:
    #!/usr/bin/env bash
    set -euo pipefail
    IMAGE="{{ image_ref }}"
    root="$(mktemp -d)"
    ctr="$(podman create "${IMAGE}" /none)"
    trap 'podman rm "${ctr}" >/dev/null; chmod -R u+rwX "${root}"; rm -rf "${root}"' EXIT
    podman export "${ctr}" | tar -C "${root}" -xf -
    bad="$(cd "${root}" && find . -path ./usr/share/licenses -prune -o \( -path ./usr/include -o -name '*.a' -o -name '*.la' \
          -o -type d -name pkgconfig -o -type d -name cmake \) -print -quit)"
    [ -z "${bad}" ] || { echo "devel content in ${IMAGE}: ${bad}" >&2; exit 1; }
    echo "OK: no devel content in ${IMAGE}"

# Check the shared and application-specific removal lists against the export;
# paths the element restores on purpose (`app-kept-paths`) are exempt.
verify-slim:
    #!/usr/bin/env bash
    set -euo pipefail
    IMAGE="{{ image_ref }}"
    root="$(mktemp -d)"
    patterns="$(mktemp)"
    kept_patterns="$(mktemp)"
    ctr=""
    cleanup() {
        [[ -z "${ctr}" ]] || podman rm "${ctr}" >/dev/null
        chmod -R u+rwX "${root}"
        rm -rf "${root}" "${patterns}" "${kept_patterns}"
    }
    trap cleanup EXIT
    vars="$(just bst show --deps none --format '%{vars}' oci/ghostscript-printer-app.bst)"
    python3 -c 'import sys, yaml; v = yaml.safe_load(sys.stdin); print(v["slim-printing-forbidden-paths"]); print(v["app-forbidden-paths"])' <<< "${vars}" > "${patterns}"
    python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["app-kept-paths"])' <<< "${vars}" > "${kept_patterns}"
    ctr="$(podman create "${IMAGE}" /none)"
    podman export "${ctr}" | tar -C "${root}" -xf -
    shopt -s nullglob globstar
    declare -A kept=()
    while IFS= read -r pattern; do
        [[ -n "${pattern}" ]] || continue
        for match in "${root}"/${pattern}; do kept["${match}"]=1; done
    done < "${kept_patterns}"
    bad=0
    while IFS= read -r pattern; do
        [[ -n "${pattern}" ]] || continue
        for match in "${root}"/${pattern}; do
            [[ -e "${match}" || -L "${match}" ]] || continue
            [[ -z "${kept[${match}]:-}" ]] || continue
            echo "forbidden path in ${IMAGE}: ${match#"${root}"}" >&2
            bad=1
        done
    done < "${patterns}"
    [[ "${bad}" -eq 0 ]]
    echo "OK: no forbidden slim content in ${IMAGE}"


# Needs host networking with multicast (the probe runs the image's own
# avahi-browse); not part of `just verify` (see verify-service-advertisements
# for the same pattern). The script itself runs `just build`.
verify-discovery:
    tests/discovery-no-competition.sh

verify-rootless-usb:
    python3 tests/rootless-usb.py

# Host-only: the entrypoint must reject malformed web-administration settings
# before it touches the image or persistent state, and must launch, supervise
# and stop its daemons as tests/entrypoint-supervisor.sh specifies.
verify-entrypoint-validation:
    tests/entrypoint-validation.sh
    tests/entrypoint-supervisor.sh

verify:
    just validate
    just verify-cups-patch-chain
    just verify-ghostscript-romfs
    just verify-core
    just verify-payload
    just verify-raster-drivers
    just verify-packaged-drivers
    just verify-stateful-drivers
    just verify-driver-autoselect
    tests/appliance-parity.sh
    just verify-no-devel
    just verify-slim


sbom:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream" "${HOME}/.cache/pip"
    git_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -v "${HOME}/.cache/pip:/root/.cache/pip:rw" \
        -w /src \
        -e GIT_SHA="$git_sha" \
        "{{ bst2_image }}" \
        bash -c '
            installed=0
            for attempt in 1 2 3; do
                if pip install --quiet \
                    git+https://gitlab.com/BuildStream/buildstream-sbom.git@0706fec3bedf6f73bd9d2fed32c2aed585feef8d; then
                    installed=1
                    break
                fi
                echo "buildstream-sbom install failed (attempt ${attempt}/3)" >&2
                if [[ "$attempt" -lt 3 ]]; then sleep 5; fi
            done
            if [[ "$installed" != 1 ]]; then
                echo "buildstream-sbom installation failed after 3 attempts" >&2
                exit 1
            fi
            buildstream-sbom oci/ghostscript-printer-app.bst \
                --spdx-name ghostscript-printer-app \
                --spdx-namespace "https://github.com/projectbluefin/ghostscript-printer-app/sbom/${GIT_SHA}" \
                --spdx-creator "Tool: buildstream-sbom" \
                --spdx-creator "Organization: projectbluefin" \
                --deps all \
                --output /src/ghostscript-printer-app.spdx.json
        '
