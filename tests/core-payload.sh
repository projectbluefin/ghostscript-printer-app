#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-payload"
port="${PORT:-18010}"
state_dir="$(mktemp -d)"
sink_port="$((port + 1000))"
output_file="$(mktemp)"
cookie_file="$(mktemp)"
sink_pid=""

cleanup() {
  podman rm -f "$name" >/dev/null 2>&1 || true
  if [[ -n "$sink_pid" ]]; then
    kill "$sink_pid" >/dev/null 2>&1 || true
    wait "$sink_pid" 2>/dev/null || true
  fi
  podman unshare rm -rf "$state_dir"
  rm -f "$output_file" "$cookie_file"
}
trap cleanup EXIT

just build

podman run --rm --entrypoint /usr/bin/bash "$image" -c '
  set -euo pipefail
  test -L /usr/lib/ghostscript-printer-app
  test "$(readlink /usr/lib/ghostscript-printer-app)" = /usr/lib/cups
  test -f /usr/share/ghostscript-printer-app/testpage.ps
  test -x /usr/bin/python3
  test -x /usr/bin/xz
  test -s /usr/share/cups/usb/org.cups.usb-quirks

  executables=(
    /usr/bin/ghostscript-printer-app
    /usr/bin/gs
    /usr/bin/python3
    /usr/bin/xz
    /usr/lib/cups/backend/dnssd
    /usr/lib/cups/backend/ipp
    /usr/lib/cups/backend/ipps
    /usr/lib/cups/backend/lpd
    /usr/lib/cups/backend/snmp
    /usr/lib/cups/backend/socket
    /usr/lib/cups/backend/usb
    /usr/lib/cups/filter/foomatic-rip
    /usr/lib/cups/filter/gstoraster
    /usr/lib/cups/filter/pdftops
    /usr/lib/cups/filter/rastertoepson
    /usr/lib/cups/filter/rastertohp
    /usr/lib/cups/filter/rastertolabel
    /usr/lib/cups/filter/rastertoescpx
    /usr/lib/cups/filter/rastertopclx
  )
  for executable in "${executables[@]}"; do
    test -x "$executable"
    dependencies="$(ldd "$executable")"
    [[ "$dependencies" != *"not found"* ]]
  done
  [[ "$(ldd /usr/lib/cups/backend/usb)" == *"libusb-1.0.so"* ]]

  devices="$(gs -h 2>&1)"
  [[ "$devices" == *"cups"* ]]
  [[ "$devices" == *"pxlcolor"* ]]

  archives=(cups-filters-ppds foomatic-ppds manufacturer-ppds)
  for archive_name in "${archives[@]}"; do
    archive="/usr/share/ppd/$archive_name"
    test -x "$archive"
    mapfile -t entries < <("$archive" list)
    ((${#entries[@]} > 0))
    uri="${entries[0]%% *}"
    uri="${uri#\"}"
    uri="${uri%\"}"
    ppd="$("$archive" cat "$uri")"
    [[ "$ppd" == *"*PPD-Adobe:"* ]]
  done

  /usr/share/ppd/foomatic-ppds cat \
    foomatic-ppds:0/Generic-PCL_6_PCL_XL_Printer-pxlcolor.ppd \
    > /tmp/foomatic.ppd
  if ! PPD=/tmp/foomatic.ppd /usr/lib/cups/filter/foomatic-rip \
    1 nonroot core-conversion 1 "" \
    /usr/share/ghostscript-printer-app/testpage.ps \
    > /tmp/foomatic-output.pcl 2>/tmp/foomatic.log; then
    cat /tmp/foomatic.log >&2
    exit 1
  fi
  test -s /tmp/foomatic-output.pcl

  # Direct gstoraster PDF regression probe. This is the filter that caught the
  # libcupsfilters temp-file page-count bug (upstream fix e14bad406189a66b),
  # so it must stay focused on cfFilterGhostscript rather than a Foomatic-only
  # route. Bound the resolution to the lowest PrinterResolution choice the
  # generic pxlcolor PPD advertises (300x300dpi) instead of its 1200dpi
  # default: at 1200dpi a Letter page renders to roughly 358 MB of raster,
  # which needlessly burns runner /tmp space and time; 300x300dpi keeps the
  # same code path with a page in the tens of megabytes.
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite \
    -sOutputFile=/tmp/pdf-filter-input.pdf \
    /usr/share/ghostscript-printer-app/testpage.ps
  test "$(stat -c %s /tmp/pdf-filter-input.pdf)" -gt 8192
  if ! PPD=/tmp/foomatic.ppd /usr/lib/cups/filter/gstoraster \
    1 nonroot pdf-regression 1 "PrinterResolution=300x300dpi Resolution=300x300dpi" \
    /tmp/pdf-filter-input.pdf \
    > /tmp/pdf-output.raster 2>/tmp/pdf-filter.log; then
    cat /tmp/pdf-filter.log >&2
    exit 1
  fi
  raster_bytes="$(stat -c %s /tmp/pdf-output.raster)"
  printf "INFO: gstoraster PDF regression output is %s bytes\n" "$raster_bytes"

  # Assert a real rendered page, not only a bare sync word: decode the CUPS
  # raster page header and require positive pixel dimensions plus a page
  # payload consistent with those dimensions. Before the upstream flush fix
  # this filter either failed outright ("Missing Root object") or emitted a
  # zero-page raster stream; a bare sync-word check would not have caught
  # either failure mode as reliably as a real header decode does.
  python3 - /tmp/pdf-output.raster <<"PY"
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 4:
    raise SystemExit(f"FAIL: raster output is only {len(data)} bytes")

sync = data[:4]
if sync in (b"RaS2", b"RaS3"):
    endian = ">"
elif sync in (b"2SaR", b"3SaR"):
    endian = "<"
else:
    raise SystemExit(f"FAIL: unrecognized raster sync word {sync!r}")

header_size = 1796
header = data[4:4 + header_size]
if len(header) < header_size:
    raise SystemExit("FAIL: raster output is missing a full page header")

cups_width, cups_height, _media_type, _bpc, _bpp, bytes_per_line = struct.unpack_from(
    endian + "6I", header, 372
)
compression = struct.unpack_from(endian + "I", header, 404)[0]

if cups_width == 0 or cups_height == 0:
    raise SystemExit(
        f"FAIL: raster page header reports empty page "
        f"({cups_width}x{cups_height}); PDF likely did not render"
    )
if bytes_per_line == 0:
    raise SystemExit("FAIL: raster page header reports zero bytes per line")

payload = data[4 + header_size:]
if not payload:
    raise SystemExit("FAIL: raster output has a header but no page data")

if compression == 0:
    # Version 3 headers (and version 2 with cupsCompression=0) are always
    # stored uncompressed: exactly cupsBytesPerLine * cupsHeight bytes.
    expected = bytes_per_line * cups_height
    if len(payload) != expected:
        raise SystemExit(
            f"FAIL: uncompressed raster payload is {len(payload)} bytes, "
            f"expected {expected} ({bytes_per_line} x {cups_height})"
        )

print(
    f"OK: rendered {cups_width}x{cups_height} page, "
    f"{bytes_per_line} bytes/line, {len(payload)} bytes of page data"
)
PY
'
chmod 0777 "$state_dir"

python3 tests/socket-sink.py "$sink_port" "$output_file" &
sink_pid=$!

podman run -d \
  --name "$name" \
  --network host \
  -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

ready=0
for _ in $(seq 1 60); do
  http="$(curl --fail --silent --show-error "http://127.0.0.1:${port}/" 2>/dev/null || true)"
  https="$(curl --insecure --fail --silent --show-error "https://127.0.0.1:${port}/" 2>/dev/null || true)"
  if [[ "$http" == *'<title>Ghostscript Printer Application</title>'* && "$https" == *'<title>Ghostscript Printer Application</title>'* ]]; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  podman logs "$name" >&2
  printf 'FAIL: HTTP/HTTPS readiness was not reached\n' >&2
  exit 1
fi

system_uri="ipp://127.0.0.1:${port}/ipp/system"
printer_uri="ipp://127.0.0.1:${port}/ipp/print/core-test"
podman exec "$name" ghostscript-printer-app \
  -u "$system_uri" \
  -d core-test \
  -m generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en \
  -v "cups:socket://127.0.0.1:${sink_port}" \
  add
printer_page="$(curl --fail --silent --show-error \
  --cookie-jar "$cookie_file" \
  "http://127.0.0.1:${port}/core-test/")"
session="${printer_page#*name=\"session\" value=\"}"
session="${session%%\"*}"
[[ -n "$session" && "$session" != "$printer_page" ]]
curl --fail --silent --show-error \
  --cookie "$cookie_file" \
  --data-urlencode "session=$session" \
  --data 'action=print-test-page' \
  "http://127.0.0.1:${port}/core-test/" >/dev/null

for _ in $(seq 1 120); do
  [[ -s "$output_file" ]] && break
  sleep 0.5
done
if [[ ! -s "$output_file" ]]; then
  podman exec "$name" ghostscript-printer-app -u "$printer_uri" jobs >&2 || true
  podman exec "$name" cat /var/lib/ghostscript-printer-app/ghostscript-printer-app.log >&2 || true
  printf 'FAIL: print job produced no socket output\n' >&2
  exit 1
fi

wait "$sink_pid"
sink_pid=""
python3 -c 'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x1b%-12345X")' "$output_file"

jobs=""
for _ in $(seq 1 120); do
  jobs="$(podman exec "$name" ghostscript-printer-app -u "$printer_uri" jobs)"
  [[ "$jobs" == *"completed"* ]] && break
  sleep 0.5
done
[[ "$jobs" == *"completed"* ]]

# No separate IPP/socket PDF job here: the queue exercised above is a
# Foomatic PCL-XL (pxlcolor) queue, which routes through pdftopdffx /
# foomatic-rip and never enters cfFilterGhostscript, so it cannot stand in
# for the PDF-to-raster regression. That regression is covered directly and
# deterministically by the bounded gstoraster probe earlier in this script
# (the real filter that caught the libcupsfilters temp-file page-count bug),
# together with the downstream HPLIP (tests/stateful-drivers.sh) and
# Gutenprint/packaged raster-driver image jobs (tests/packaged-drivers.sh),
# which already print real image-backed jobs end to end. A redundant
# Foomatic-routed PDF IPP job here would cost real CI time and disk without
# adding coverage of cfFilterGhostscript.
printf 'OK: core driver payload, HTTPS, and print conversion are available\n'
