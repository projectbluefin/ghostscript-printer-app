#!/usr/bin/env bash
# Host-only checks for ci/seed-printing-base.sh against stubbed just, skopeo
# and cosign. The seed must never fail the caller, and it must only unpack a
# bundle into the BuildStream cache after cosign accepts that exact digest as
# signed by fsdk-containers' printing-base.yml on main.
set -Eeuo pipefail

seed="$(cd "$(dirname "$0")/.." && pwd)/ci/seed-printing-base.sh"
key="$(printf 'a%.0s' {1..64})"
digest="sha256:$(printf 'b%.0s' {1..64})"
failures=0

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"

# just: STUB_KEY is the full key; the state is "cached" once STUB_STATE_FILE
# exists or the BuildStream cache holds the unpacked marker.
cat > "${work}/bin/just" <<'EOF'
#!/usr/bin/env bash
[[ "${STUB_JUST_FAIL:-0}" == 1 ]] && exit 1
case "$*" in
  *%\{full-key\}*) printf '\033[1m%s\033[0m\n' "${STUB_KEY}" ;;
  *%\{state\}*)
    if [[ -e "${HOME}/.cache/buildstream/seeded" || "${STUB_CACHED:-0}" == 1 ]]; then
      echo cached
    else
      echo buildable
    fi ;;
  *) exit 2 ;;
esac
EOF

cat > "${work}/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
echo "skopeo $*" >> "${STUB_LOG}"
case "$1" in
  inspect) echo "${STUB_DIGEST}" ;;
  copy)
    dir="${3#dir:}"
    layer="$(printf 'c%.0s' {1..64})"
    payload="$(mktemp -d)"
    touch "${payload}/seeded"
    tar -C "${payload}" -cf "${dir}/${layer}" seeded
    rm -rf "${payload}"
    printf '{"layers":[{"digest":"sha256:%s"}]}\n' "${layer}" > "${dir}/manifest.json" ;;
esac
EOF

cat > "${work}/bin/cosign" <<'EOF'
#!/usr/bin/env bash
echo "cosign $*" >> "${STUB_LOG}"
[[ "${STUB_COSIGN_FAIL:-0}" == 1 ]] && exit 1
exit 0
EOF
chmod +x "${work}/bin/"*

# run_case <name> <expected output substring> <expect seeded: 0|1> VAR=VALUE...
run_case() {
  local name="$1" expected="$2" want_seeded="$3"
  shift 3
  local home="${work}/${name}" output status
  mkdir -p "${home}/.cache/buildstream"
  : > "${work}/${name}.log"
  set +e
  output="$(env -i PATH="${work}/bin:${PATH}" HOME="${home}" ARCH=x86_64 \
    STUB_KEY="${key}" STUB_DIGEST="${digest}" STUB_LOG="${work}/${name}.log" \
    "$@" bash "${seed}" 2>&1)"
  status=$?
  set -e
  local seeded=0
  [[ -e "${home}/.cache/buildstream/seeded" ]] && seeded=1
  if [[ "${status}" -ne 0 ]]; then
    echo "FAIL ${name}: exit ${status}, want 0" >&2; failures=$((failures + 1))
  elif [[ "${output}" != *"${expected}"* ]]; then
    echo "FAIL ${name}: output lacks '${expected}':" >&2; echo "${output}" >&2
    failures=$((failures + 1))
  elif [[ "${seeded}" != "${want_seeded}" ]]; then
    echo "FAIL ${name}: seeded=${seeded}, want ${want_seeded}" >&2; failures=$((failures + 1))
  else
    echo "ok ${name}"
  fi
}

run_case missing-key "cannot compute the x86_64 key" 0 STUB_KEY=
run_case bst-fails "cannot compute the x86_64 key" 0 STUB_JUST_FAIL=1
run_case already-cached "printing base x86_64-${key} is already cached" 0 STUB_CACHED=1
run_case cosign-rejects "seeding x86_64-${key} failed" 0 STUB_COSIGN_FAIL=1
run_case seeded "printing base seeded from x86_64-${key}" 1

# cosign must accept only the publishing workflow on main, and the verified
# digest, not the mutable tag, must be the one copied.
identity="--certificate-identity https://github.com/projectbluefin/fsdk-containers/.github/workflows/printing-base.yml@refs/heads/main"
if ! grep -qx "cosign verify ${identity} .*ghcr.io/projectbluefin/printing-base-devel@${digest}" "${work}/seeded.log" ||
   ! grep -qx "skopeo copy docker://ghcr.io/projectbluefin/printing-base-devel@${digest} dir:.*" "${work}/seeded.log"; then
  echo "FAIL seeded: cosign did not pin the publisher identity, or cosign/skopeo did not both use ${digest}:" >&2; cat "${work}/seeded.log" >&2
  failures=$((failures + 1))
fi
if grep -q "^skopeo copy" "${work}/cosign-rejects.log"; then
  echo "FAIL cosign-rejects: bundle was copied after cosign refused it" >&2
  failures=$((failures + 1))
fi

if ! env -i PATH="${PATH}" bash "${seed}" >/dev/null 2>&1; then
  echo "ok missing-arch"
else
  echo "FAIL missing-arch: ran without ARCH" >&2; failures=$((failures + 1))
fi

[[ "${failures}" -eq 0 ]] || { echo "${failures} seed-printing-base case(s) failed" >&2; exit 1; }
