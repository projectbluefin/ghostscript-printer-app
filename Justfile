# BuildStream runs in the pinned freedesktop-sdk builder image.
bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")
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

validate:
    just bst show --deps all oci/ghostscript-printer-app.bst

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
    just bst build oci/ghostscript-printer-app.bst
    just export

export:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build-out
    just bst artifact checkout oci/ghostscript-printer-app.bst --directory /src/.build-out
    IMAGE_ID=$(podman pull -q oci:.build-out)
    rm -rf .build-out
    podman tag "$IMAGE_ID" "{{ image_ref }}"

verify-core:
    tests/core-appliance.sh

verify-payload:
    tests/core-payload.sh

verify-raster-drivers:
    tests/standalone-raster-drivers.sh

verify-packaged-drivers:
    tests/packaged-drivers.sh

verify-stateful-drivers:
    tests/stateful-drivers.sh

verify-cups-patch-chain:
    tests/cups-patch-chain.sh

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

verify:
    just validate
    just verify-cups-patch-chain
    just verify-core
    just verify-payload
    just verify-raster-drivers
    just verify-packaged-drivers
    just verify-stateful-drivers
    tests/appliance-parity.sh
    just verify-no-devel


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