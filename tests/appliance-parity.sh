#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"

expect_equal() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s: got %q, expected %q\n' "$label" "$actual" "$expected" >&2
    exit 1
  fi
}
size_limit_bytes="${IMAGE_SIZE_LIMIT_BYTES:-524288000}"

just build

advertised_ghostscript_drivers="$(python3 - <<'PY'
import pathlib
import re

readme = pathlib.Path("README.md").read_text()
match = re.search(
    r"### Contained Printer Drivers.*?- \*\*Ghostscript built-in\*\*:\s*```(.*?)```",
    readme,
    re.DOTALL,
)
if match is None:
    raise SystemExit("FAIL: README Ghostscript driver inventory is missing")
print(" ".join(match.group(1).replace(",", " ").split()))
PY
)"

# FSDK is pinned by fsdk-containers' own junction; read it from the resolved graph.
fsdk_source_info="$(just bst show --deps none --format '%{source-info}' fsdk-containers.bst:freedesktop-sdk.bst)"
read -r fsdk_version fsdk_ref < <(FSDK_SOURCE_INFO="$fsdk_source_info" python3 - <<'PY'
import os
import re

match = re.search(
    r"^- kind: git_repo\n  url: https://gitlab\.com/freedesktop-sdk/freedesktop-sdk\.git\n"
    r"(?:  .*\n)*?  version: ([0-9a-f]{40})\n(?:  .*\n)*?    tag-name: freedesktop-sdk-(\S+)\n    commit-offset: 0$",
    os.environ["FSDK_SOURCE_INFO"],
    re.MULTILINE,
)
if match is None:
    raise SystemExit("FAIL: pinned freedesktop-sdk release is missing")
print(match.group(2), match.group(1))
PY
)

size_bytes="$(podman image inspect "$image" --format '{{.Size}}')"
if ((size_bytes > size_limit_bytes)); then
  printf 'FAIL: uncompressed image is %s bytes; limit is %s bytes\n' "$size_bytes" "$size_limit_bytes" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) expected_arch=amd64 ;;
  aarch64) expected_arch=arm64 ;;
  *) printf 'FAIL: unsupported verification architecture %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

expect_equal architecture "$(podman image inspect "$image" --format '{{.Architecture}}')" "$expected_arch"
expect_equal user "$(podman image inspect "$image" --format '{{.Config.User}}')" 65532:65532
expect_equal entrypoint "$(podman image inspect "$image" --format '{{json .Config.Entrypoint}}')" '["/usr/bin/catatonit","--","/usr/bin/bash","/usr/libexec/ghostscript-printer-app/container-entrypoint"]'
expect_equal title "$(podman image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.title"}}')" ghostscript-printer-app
expect_equal source "$(podman image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')" https://github.com/projectbluefin/ghostscript-printer-app
expect_equal license "$(podman image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.licenses"}}')" Apache-2.0
application_version="$(podman run --rm --entrypoint /usr/bin/ghostscript-printer-app "$image" --version)"
expect_equal binary-version "$application_version" "$(< VERSION)"
expect_equal image-version "$(podman image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" "$application_version"
expect_equal fsdk-version "$(podman image inspect "$image" --format '{{index .Config.Labels "io.projectbluefin.fsdk.version"}}')" "$fsdk_version"
expect_equal fsdk-ref "$(podman image inspect "$image" --format '{{index .Config.Labels "io.projectbluefin.fsdk.ref"}}')" "$fsdk_ref"

podman run --rm --user 0:0 --entrypoint /usr/bin/bash \
  -e ADVERTISED_GHOSTSCRIPT_DRIVERS="$advertised_ghostscript_drivers" \
  "$image" -c '
  set -euo pipefail

  backends=(dnssd ipp ipps lpd snmp socket usb)
  for backend in "${backends[@]}"; do
    test -x "/usr/lib/cups/backend/$backend" || { printf "FAIL: missing CUPS backend %s\n" "$backend" >&2; exit 1; }
  done

  filters=(
    c2esp c2espC command2esp command2foo2lava-pjl
    foomatic-rip gstoraster pdftopdffx pdftops
    pstoqpdl raster2dymolm raster2dymolw rastertobrlaser
    rastertoepson rastertoescpx rastertohp rastertolabel
    rastertookidotmatrix rastertookimonochrome rastertopclx
    rastertoptch rastertoqpdl rastertosag-gdi
  )
  for filter in "${filters[@]}"; do
    test -x "/usr/lib/cups/filter/$filter" || { printf "FAIL: missing CUPS filter %s\n" "$filter" >&2; exit 1; }
  done

  commands=(
    c2050 cjet foo2zjs-wrapper gs hpijs m2300w-wrapper
    min12xxw pnm2ppa psnup ijs_pxljr
  )
  for command in "${commands[@]}"; do
    command -v "$command" >/dev/null || { printf "FAIL: missing driver command %s\n" "$command" >&2; exit 1; }
  done

  ppd_providers=(
    KodakESP_16.drv KodakESP_C_07.drv brlaser.drv
    cups-filters-ppds dymo-ppds foo2zjs-ppds foomatic-ppds
    fxlinuxprint-ppds m2300w-ppds manufacturer-ppds oki-ppds
    ptouch-ppds pxljr-ppds rastertosag-gdi-ppds splix-ppds
  )
  for provider in "${ppd_providers[@]}"; do
    test -e "/usr/share/ppd/$provider" || { printf "FAIL: missing PPD provider %s\n" "$provider" >&2; exit 1; }
  done

  provider_contains() {
    local path="$1" marker="${2,,}" contents
    if [[ -x "$path" ]]; then
      contents="$("$path" list)"
    else
      contents="$(cat "$path")"
    fi
    if [[ "${contents,,}" != *"$marker"* ]]; then
      printf "FAIL: %s does not contain advertised family %s\n" "$path" "$2" >&2
      exit 1
    fi
  }
  provider_contains /usr/share/ppd/KodakESP_16.drv Kodak
  provider_contains /usr/share/ppd/KodakESP_C_07.drv Kodak
  provider_contains /usr/share/ppd/brlaser.drv Brother
  provider_contains /usr/share/ppd/cups-filters-ppds "PCL 6 CUPS"
  provider_contains /usr/share/ppd/dymo-ppds Dymo
  provider_contains /usr/share/ppd/foo2zjs-ppds Minolta
  provider_contains /usr/share/ppd/foomatic-ppds Foomatic
  provider_contains /usr/share/ppd/fxlinuxprint-ppds "Fuji Xerox"
  provider_contains /usr/share/ppd/m2300w-ppds "KONICA MINOLTA"
  for manufacturer in Gestetner InfoPrint Infotec Lanier NRG Ricoh Savin Samsung; do
    provider_contains /usr/share/ppd/manufacturer-ppds "$manufacturer"
  done
  provider_contains /usr/share/ppd/oki-ppds Oki
  provider_contains /usr/share/ppd/ptouch-ppds Brother
  provider_contains /usr/share/ppd/pxljr-ppds "HP Color LaserJet"
  provider_contains /usr/share/ppd/rastertosag-gdi-ppds Ricoh
  provider_contains /usr/share/ppd/splix-ppds Samsung
  provider_contains /usr/share/cups/drv/sample.drv Intellitech
  provider_contains /usr/share/cups/drv/sample.drv Zebra
  provider_contains /usr/share/ppd/foomatic-ppds Epson
  provider_contains /usr/share/ppd/foomatic-ppds "HP DesignJet"

  devices=" $(gs -h 2>&1 | tr "\n" " ") "
  foomatic_entries="$(/usr/share/ppd/foomatic-ppds list)"
  read -r -a ghostscript_drivers <<< "$ADVERTISED_GHOSTSCRIPT_DRIVERS"
  ((${#ghostscript_drivers[@]} >= 90)) || {
    printf "FAIL: README exposed only %s Ghostscript drivers; expected at least 90\n" "${#ghostscript_drivers[@]}" >&2
    exit 1
  }
  for driver in "${ghostscript_drivers[@]}"; do
    if [[ "$devices" != *" $driver "* && "$foomatic_entries" != *"Foomatic/$driver "* && "$foomatic_entries" != *"Foomatic/$driver\""* ]]; then
      printf "FAIL: advertised Ghostscript driver %s has no device or PPD entry\n" "$driver" >&2
      exit 1
    fi
  done

  command -v bash >/dev/null
  command -v python3 >/dev/null
  for interpreter in perl ruby node lua tclsh wish; do
    ! command -v "$interpreter" >/dev/null 2>&1
  done
  for tool in apt apt-get apk dnf dpkg pacman rpm pip pip3 cc c++ gcc g++ clang make cmake meson ninja pkg-config autoconf automake libtool ld ar as nm objcopy ranlib strip; do
    ! command -v "$tool" >/dev/null 2>&1
  done

  python3 - <<"PY"
import os
import subprocess
import sys

forbidden = []
unresolved = []
for root, dirs, files in os.walk("/"):
    if root == "/":
        dirs[:] = [name for name in dirs if name not in {"dev", "proc", "run", "sys", "tmp"}]
    if root.startswith("/usr/share/licenses/"):
        dirs[:] = []
        continue
    if root == "/usr/include" or root.startswith("/usr/include/"):
        forbidden.extend(os.path.join(root, name) for name in files)
    if root == "/usr/lib/debug" or root.startswith("/usr/lib/debug/"):
        forbidden.extend(os.path.join(root, name) for name in files)
    for directory in dirs:
        if directory.lower() in {"test", "tests", "testing"}:
            forbidden.append(os.path.join(root, directory))
    for name in files:
        path = os.path.join(root, name)
        if name.endswith((".a", ".la", ".test")):
            forbidden.append(path)
        if os.path.islink(path):
            continue
        try:
            with open(path, "rb") as stream:
                is_elf = stream.read(4) == b"\x7fELF"
        except OSError as error:
            unresolved.append(f"{path}: audit failed: {error}")
            continue
        if not is_elf:
            continue
        result = subprocess.run(
            ["/usr/bin/ldd", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        output = result.stdout.strip()
        if "not found" in output:
            unresolved.append(f"{path}: {output}")
        elif result.returncode != 0 and "not a dynamic executable" not in output and "statically linked" not in output:
            unresolved.append(f"{path}: ldd exited {result.returncode}: {output}")

if forbidden:
    print("FAIL: forbidden runtime payload:\n" + "\n".join(forbidden), file=sys.stderr)
if unresolved:
    print("FAIL: unresolved ELF dependencies:\n" + "\n".join(unresolved), file=sys.stderr)
if forbidden or unresolved:
    raise SystemExit(1)
PY
'

printf 'OK: complete appliance inventory, metadata, size, and runtime closure (%s bytes)\n' "$size_bytes"
