#!/usr/bin/env bash
set -Eeuo pipefail

image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-packaged-drivers"
port="${PORT:-18030}"
state_dir="$(mktemp -d)"

# On any failure, name the failing command and dump the appliance state so a
# CI failure explains itself. Subshells inherit the ERR trap (-E); only the top
# level records, so the reported line is the script's own.
failed_command=""
record_failure() {
  ((BASH_SUBSHELL == 0)) && [[ -z "$failed_command" ]] && failed_command="line $1: ${2%%$'\n'*}"
  return 0
}

dump_diagnostics() {
  printf 'FAIL: %s\n' "${failed_command:-explicit exit}" >&2
  podman ps -a >&2 || true
  if podman container exists "$name" 2>/dev/null; then
    printf -- '--- %s: %s\n' "$name" \
      "$(podman inspect "$name" --format '{{.State.Status}} exit={{.State.ExitCode}}' 2>&1)" >&2
    podman logs --tail 50 "$name" >&2 2>&1 || true
  fi
  if podman unshare test -s "$state_dir/ghostscript-printer-app.log"; then
    printf -- '--- application log\n' >&2
    podman unshare tail -n 50 "$state_dir/ghostscript-printer-app.log" >&2 || true
  fi
}

cleanup() {
  local status=$?
  trap - ERR
  ((status == 0)) || dump_diagnostics
  podman rm -f "$name" >/dev/null 2>&1 || true
  podman unshare rm -rf "$state_dir"
}
trap 'record_failure "$LINENO" "$BASH_COMMAND"' ERR
trap cleanup EXIT

# Both catalog phases reuse one port, so require this container's own web UI;
# a timeout fails here instead of surfacing as a confusing drivers query error.
wait_for_app() {
  local response
  for _ in $(seq 1 60); do
    [[ "$(podman inspect "$name" --format '{{.State.Running}}')" == true ]] || break
    if response="$(curl --fail --silent "http://127.0.0.1:${port}/" 2>/dev/null)" &&
      [[ "$response" == *'<title>Ghostscript Printer Application</title>'* ]]; then
      return 0
    fi
    sleep 1
  done
  printf 'FAIL: %s did not serve its web UI on port %s\n' "$name" "$port" >&2
  return 1
}

just build

for element in \
  dymo-cups-drivers \
  fxlinuxprint \
  printer-driver-oki \
  ptouch-driver \
  pxljr \
  rastertosag-gdi \
  splix; do
  runtime_graph="$(just bst show --deps run --format '%{name}' "printer-app/$element.bst")"
  [[ "$runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst"* ]]
done
oki_runtime_graph="$(just bst show --deps run --format '%{name}' printer-app/printer-driver-oki.bst)"
[[ "$oki_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/grep.bst"* ]]
[[ "$oki_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst"* ]]
for element in fxlinuxprint ptouch-driver pxljr; do
  runtime_graph="$(just bst show --deps run --format '%{name}' "printer-app/$element.bst")"
  [[ "$runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst"* ]]
done
for element in ptouch-driver pxljr; do
  runtime_graph="$(just bst show --deps run --format '%{name}' "printer-app/$element.bst")"
  [[ "$runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst"* ]]
done
[[ "$oki_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst"* ]]
[[ "$oki_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst"* ]]
[[ "$oki_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/cups-daemon-only.bst"* ]]
c2esp_runtime_graph="$(just bst show --deps run --format '%{name}' printer-app/c2esp.bst)"
[[ "$c2esp_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/zlib.bst"* ]]
splix_runtime_graph="$(just bst show --deps run --format '%{name}' printer-app/splix.bst)"
[[ "$splix_runtime_graph" == *"printer-app/jbigkit.bst"* ]]
[[ "$splix_runtime_graph" == *"fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst"* ]]

chmod 0777 "$state_dir"
podman run --rm --entrypoint /usr/bin/bash \
  -v "$state_dir:/state:Z" "$image" -c '
  set -Eeuo pipefail
  # Name the failing check (and its caller); the host otherwise sees only a status.
  trap '\''status=$?; ((BASH_SUBSHELL)) || printf "FAIL: in-container line %s%s exited %s: %s\n" "$LINENO" "${FUNCNAME:+ (${FUNCNAME[0]} called from line ${BASH_LINENO[0]})}" "$status" "$BASH_COMMAND" >&2'\'' ERR

  filter_dir=/usr/lib/cups/filter
  ppd_dir=/usr/share/ppd
  work=/tmp/packaged-drivers
  export PATH="$filter_dir:/usr/bin:/bin"
  export TMPDIR=/tmp
  mkdir -p "$work" /state/ppd

  printf "%s\n" \
    "%!PS-Adobe-3.0" \
    "%%Pages: 1" \
    "%%Page: 1 1" \
    "newpath 10 10 moveto 60 60 lineto stroke" \
    "showpage" \
    "%%EOF" > "$work/page.ps"

  assert_prefix() {
    local file="$1" bytes="$2" expected="$3"
    test -s "$file"
    [[ "$(od -An -tx1 -N "$bytes" "$file")" == "$expected" ]]
  }

  assert_suffix() {
    local file="$1" bytes="$2" expected="$3" size
    size="$(stat -c %s "$file")"
    ((size >= bytes))
    [[ "$(od -An -tx1 -j "$((size - bytes))" -N "$bytes" "$file")" == "$expected" ]]
  }

  assert_repeatable() {
    local first_hash second_hash
    read -r first_hash _ < <(sha256sum "$1")
    read -r second_hash _ < <(sha256sum "$2")
    [[ "$first_hash" == "$second_hash" ]]
  }

  assert_archive() {
    local archive="$ppd_dir/$1" marker="$2" entries
    test -x "$archive"
    entries="$("$archive" list)"
    [[ "$entries" == *"$marker"* ]]
    cp "$archive" /state/ppd/
  }

  extract_ppd() {
    "$ppd_dir/$1" cat "$2" > "$3"
    test -s "$3"
  }

  make_raster() {
    local ppd="$1" resolution="$2" geometry="$3" output="$4"
    shift 4
    PPD="$ppd" gs -q -dSAFER -dNOPAUSE -dBATCH -sDEVICE=cups \
      -r"$resolution" -g"$geometry" "$@" \
      -sOutputFile="$output" "$work/page.ps" 2>"$output.log"
    test -s "$output"
  }

  run_filter() {
    local filter="$1" ppd="$2" options="$3" input="$4" stem="$5" suffix
    for suffix in first second; do
      if ! PPD="$ppd" DEVICE_URI=file:/dev/null \
        "$filter" 1 test test 1 "$options" "$input" \
        3</dev/null 4<>/dev/null \
        >"$work/$stem-$suffix.prn" 2>"$work/$stem-$suffix.log"; then
        cat "$work/$stem-$suffix.log" >&2
        return 1
      fi
    done
    assert_repeatable "$work/$stem-first.prn" "$work/$stem-second.prn"
  }

  filters=(c2esp c2espC command2esp raster2dymolm raster2dymolw pstopdffx pdftopjlfx pdftopdffx okijobaccounting rastertookidotmatrix rastertookimonochrome rastertoptch rastertosag-gdi pstoqpdl rastertoqpdl rastertobrlaser)
  for filter in "${filters[@]}"; do
    test -x "$filter_dir/$filter"
  done

  binaries=(c2esp c2espC command2esp raster2dymolm raster2dymolw pstopdffx pdftopjlfx pdftopdffx rastertoptch pstoqpdl rastertoqpdl rastertobrlaser /usr/bin/ijs_pxljr)
  for binary in "${binaries[@]}"; do
    [[ "$binary" == /* ]] || binary="$filter_dir/$binary"
    dependencies="$(ldd "$binary")"
    [[ "$dependencies" != *"not found"* ]]
  done

  test -x /bin/sh
  test -x /bin/grep
  test -x /bin/sed
  test -x /usr/bin/python3
  test -x "$filter_dir/rastertohp"
  for devel_path in \
    /usr/include/ijs \
    /usr/include/jbig85.h \
    /usr/include/jbig_ar.h \
    /usr/lib/*-linux-gnu/libijs.so \
    /usr/lib/*-linux-gnu/libjbig85.so; do
    test ! -e "$devel_path"
  done
  read -r shebang < "$filter_dir/okijobaccounting"
  [[ "$shebang" == "#!/bin/sh" ]]
  for script in rastertookidotmatrix rastertookimonochrome; do
    read -r shebang < "$filter_dir/$script"
    [[ "$shebang" == "#!/bin/sh" ]]
  done
  read -r shebang < "$filter_dir/rastertosag-gdi"
  [[ "$shebang" == "#!/usr/bin/python3 -u" ]]
  for archive in dymo-ppds fxlinuxprint-ppds oki-ppds ptouch-ppds pxljr-ppds rastertosag-gdi-ppds splix-ppds; do
    read -r shebang < "$ppd_dir/$archive"
    [[ "$shebang" == "#!/usr/bin/env python3" ]]
  done

  assert_archive dymo-ppds "DYMO LabelMANAGER 400"
  assert_archive fxlinuxprint-ppds "Fuji Xerox PDF Printer"
  assert_archive oki-ppds "OKI B2200"
  assert_archive ptouch-ppds "Brother PT-1500PC"
  assert_archive pxljr-ppds "HP Color LaserJet 3500"
  assert_archive rastertosag-gdi-ppds "Ricoh Aficio SP 1000S"
  assert_archive splix-ppds "Dell 1100"
  test -f "$ppd_dir/brlaser.drv"
  test -f "$ppd_dir/KodakESP_16.drv"
  test -f "$ppd_dir/KodakESP_C_07.drv"
  test -f /usr/share/cups/mime/mimefx.types
  test -f /usr/share/cups/mime/mimefx.convs

  mkdir "$work/c2esp" "$work/brlaser"
  ppdc -d "$work/c2esp" "$ppd_dir/KodakESP_16.drv"
  ppdc -d "$work/brlaser" "$ppd_dir/brlaser.drv"
  cp "$work/c2esp"/*.ppd "$work/brlaser"/*.ppd /state/ppd/

  c2esp_ppd="$work/c2esp/Kodak_ESP_3.ppd"
  make_raster "$c2esp_ppd" 300x1200 300x1200 "$work/c2esp.ras"
  run_filter "$filter_dir/c2esp" "$c2esp_ppd" "" "$work/c2esp.ras" c2esp
  assert_prefix "$work/c2esp-first.prn" 16 " 4c 6f 63 6b 50 72 69 6e 74 65 72 57 61 69 74 3f"
  printf "OK: c2esp conversion\n"

  extract_ppd dymo-ppds dymo-ppds:0/lm400.ppd "$work/dymo-lm.ppd"
  make_raster "$work/dymo-lm.ppd" 180 170x630 "$work/dymo-lm.ras"
  run_filter "$filter_dir/raster2dymolm" "$work/dymo-lm.ppd" "PageSize=w68h252.2" "$work/dymo-lm.ras" dymo-lm
  assert_prefix "$work/dymo-lm-first.prn" 16 " 00 00 00 00 00 00 00 00 00 00 00 00 1b 43 00 1b"

  extract_ppd dymo-ppds dymo-ppds:0/lw400.ppd "$work/dymo-lw.ppd"
  make_raster "$work/dymo-lw.ppd" 300 300x300 "$work/dymo-lw.ras"
  run_filter "$filter_dir/raster2dymolw" "$work/dymo-lw.ppd" "PageSize=w72h72" "$work/dymo-lw.ras" dymo-lw
  assert_prefix "$work/dymo-lw-first.prn" 16 " 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b 1b"
  printf "OK: Dymo LabelManager and LabelWriter conversions\n"

  extract_ppd fxlinuxprint-ppds fxlinuxprint-ppds:0/fxlinuxprint.ppd "$work/fx.ppd"
  if ! PPD="$work/fx.ppd" TMPDIR=/tmp \
    "$filter_dir/pstopdffx" 1 test test 1 "" "$work/page.ps" \
    >"$work/fx-postscript.prn" 2>"$work/fx-postscript.log"; then
    cat "$work/fx-postscript.log" >&2
    exit 1
  fi
  assert_prefix "$work/fx-postscript.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 0a 40 50"
  gs -q -dSAFER -dNOPAUSE -dBATCH -sDEVICE=pdfwrite \
    -sOutputFile="$work/fx.pdf" "$work/page.ps"
  run_filter "$filter_dir/pdftopjlfx" "$work/fx.ppd" "" "$work/fx.pdf" fx
  assert_prefix "$work/fx-first.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 0a 40 50"
  printf "OK: fxlinuxprint conversion\n"

  extract_ppd oki-ppds oki-ppds:0/B2200PCL.ppd "$work/oki.ppd"
  make_raster "$work/oki.ppd" 600 600x600 "$work/oki.ras"
  for suffix in first second; do
    if ! PPD="$work/oki.ppd" TMPDIR=/tmp \
      "$filter_dir/rastertookimonochrome" 1 test test 1 "" \
      < "$work/oki.ras" \
      > "$work/oki-$suffix.prn" 2> "$work/oki-$suffix.log"; then
      cat "$work/oki-$suffix.log" >&2
      exit 1
    fi
  done
  assert_repeatable "$work/oki-first.prn" "$work/oki-second.prn"
  assert_prefix "$work/oki-first.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 20 43 4f"
  (("$(stat -c %s "$work/oki-first.prn")" > 1000))
  printf "%s\n" "@PJL ENTER LANGUAGE = POSTSCRIPT" "showpage" > "$work/oki.ps"
  for suffix in first second; do
    TMPDIR=/tmp "$filter_dir/okijobaccounting" 1 test test 1 "" \
      < "$work/oki.ps" > "$work/oki-accounting-$suffix.prn"
  done
  assert_repeatable "$work/oki-accounting-first.prn" "$work/oki-accounting-second.prn"
  accounting="$(cat "$work/oki-accounting-first.prn")"
  [[ "$accounting" == *"@PJL OKIJOBACCOUNTJOB"* ]]
  printf "OK: Oki raster and accounting conversions\n"

  extract_ppd ptouch-ppds ptouch-ppds:0/Brother-PT-1500PC-ptouch-pt.ppd "$work/ptouch.ppd"
  run_filter "$filter_dir/foomatic-rip" "$work/ptouch.ppd" "" "$work/page.ps" ptouch
  assert_suffix "$work/ptouch-first.prn" 2 " 5a 1a"
  printf "OK: P-Touch conversion\n"

  extract_ppd pxljr-ppds pxljr-ppds:0/HP-Color_LaserJet_3500-pxljr.ppd "$work/pxljr.ppd"
  run_filter "$filter_dir/foomatic-rip" "$work/pxljr.ppd" "" "$work/page.ps" pxljr
  assert_prefix "$work/pxljr-first.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 20 53 45"
  printf "OK: pxljr default conversion\n"

  extract_ppd rastertosag-gdi-ppds rastertosag-gdi-ppds:0/rsp1000s.ppd "$work/sag.ppd"
  make_raster "$work/sag.ppd" 600 600x600 "$work/sag.ras"
  run_filter "$filter_dir/rastertosag-gdi" "$work/sag.ppd" "" "$work/sag.ras" sag
  assert_prefix "$work/sag-first.prn" 9 " 29 20 53 41 47 2d 47 44 49"
  printf "OK: rastertosag-gdi conversion\n"

  extract_ppd splix-ppds splix-ppds:0/1100.ppd "$work/splix.ppd"
  make_raster "$work/splix.ppd" 600 600x600 "$work/splix.ras" \
    -dcupsCompression=17 -dcupsColorSpace=3 -dcupsColorOrder=0
  run_filter "$filter_dir/rastertoqpdl" "$work/splix.ppd" "ColorModel=Gray Resolution=600dpi" "$work/splix.ras" splix
  assert_prefix "$work/splix-first.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 20 44 45"
  run_filter "$filter_dir/pstoqpdl" "$work/splix.ppd" "ColorModel=Gray Resolution=600dpi" "$work/page.ps" splix-ps
  assert_prefix "$work/splix-ps-first.prn" 16 " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 20 44 45"
  printf "OK: SpliX conversion\n"

  brlaser_ppd=
  for candidate in "$work/brlaser"/*.ppd; do
    brlaser_ppd="$candidate"
    break
  done
  test -n "$brlaser_ppd"
  make_raster "$brlaser_ppd" 600 600x600 "$work/brlaser.ras"
  run_filter "$filter_dir/rastertobrlaser" "$brlaser_ppd" "" "$work/brlaser.ras" brlaser
  assert_suffix "$work/brlaser-first.prn" 10 " 1b 25 2d 31 32 33 34 35 58 0a"
  printf "OK: brlaser conversion\n"
'

podman run -d --name "$name" --network host -e PORT="$port" \
  -e PPD_PATHS=/var/lib/ghostscript-printer-app/ppd \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
wait_for_app
drivers="$(podman exec "$name" ghostscript-printer-app -u "ipp://127.0.0.1:${port}/ipp/system" drivers)"
for marker in \
  "Kodak ESP 3" \
  "DYMO LabelMANAGER 400" \
  "Fuji Xerox PDF Printer" \
  "OKI B2200" \
  "Brother 1500PC" \
  "HP Color LaserJet 3500" \
  "Ricoh Aficio SP 1000S" \
  "Dell 1100" \
  "brlaser"; do
  if [[ "$drivers" != *"$marker"* ]]; then
    printf 'Missing live driver: %s\n' "$marker" >&2
    exit 1
  fi
done

podman stop --time 15 "$name" >/dev/null
podman rm "$name" >/dev/null
podman run -d --name "$name" --network host -e PORT="$port" \
  -e PPD_PATHS=/usr/share/ppd/ \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
wait_for_app
installed_drivers="$(podman exec "$name" ghostscript-printer-app -u "ipp://127.0.0.1:${port}/ipp/system" drivers)"
[[ "$installed_drivers" == *"kodak--esp-3-aio--en"* ]]
[[ "$installed_drivers" == *"brlaser"* ]]

printf 'OK: packaged drivers convert, resolve dependencies, and appear in the live catalog\n'
