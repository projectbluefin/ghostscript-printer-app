#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-stateful-drivers"
port="${PORT:-18040}"
state_dir="$(mktemp -d)"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status != 0)) && podman container exists "$name"; then
    podman exec "$name" /usr/bin/bash -c '
      for log in /tmp/stateful-drivers/*.log /tmp/m2300w.log; do
        [[ -f "$log" ]] || continue
        printf "==> %s\n" "$log" >&2
        cat "$log" >&2
      done
    ' || true
    podman logs "$name" >&2 || true
  fi
  podman rm -f "$name" >/dev/null 2>&1 || true
  podman unshare rm -rf "$state_dir"
  exit "$status"
}
trap cleanup EXIT

wait_for_http() {
  for _ in $(seq 1 60); do
    curl --fail --silent "http://127.0.0.1:${port}/" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

just build

require_runtime_deps() {
  local element="$1" graph dependency
  shift
  graph="$(just bst show --deps run --format '%{name}' "printer-app/$element.bst")"
  for dependency in "$@"; do
    [[ "$graph" == *"$dependency"* ]]
  done
}

require_runtime_deps hpijs \
  fsdk-containers.bst:freedesktop-sdk.bst:components/jpeg.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
require_runtime_deps foo2zjs \
  printer-app/jbigkit.bst \
  printer-app/psutils.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/bc.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/file.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/grep.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/lcms.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
require_runtime_deps m2300w \
  printer-app/psutils.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst \
  fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
chmod 0777 "$state_dir"
podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
wait_for_http

podman exec "$name" /usr/bin/bash -c '
  set -euo pipefail
  export PATH=/usr/lib/cups/filter:/usr/bin:/bin
  state=/var/lib/ghostscript-printer-app
  work=/tmp/stateful-drivers
  mkdir -p "$work"

  test -L /etc/hp/hplip.conf
  [[ "$(readlink /etc/hp/hplip.conf)" == "$state/hplip/hplip.conf" ]]
  test -f "$state/hplip/hplip.conf"
  test -d /usr/share/hplip
  grep -Fxq "home=/usr/share/hplip" "$state/hplip/hplip.conf"
  test -f "$state/foo2zjs/foo2zjs/gamma.ps"
  test -f "$state/foo2zjs/foo2zjs/crd/screen1200.ps"
  test -f "$state/m2300w/0.51/psfiles/prolog.ps"
  ! grep -R "/ghostscript-printer-app/current" /etc/hp "$state/hplip" /usr/bin/*-wrapper

  binaries=(
    hpijs psnup
    foo2zjs zjsdecode arm2hpdl foo2hp foo2xqx xqxdecode
    foo2lava lavadecode foo2qpdl qpdldecode opldecode
    foo2oak oakdecode foo2slx slxdecode foo2hiperc hipercdecode
    foo2hbpl2 hbpldecode gipddecode foo2ddst ddstdecode usb_printerid
    m2300w m2400w
  )
  for executable in "${binaries[@]}"; do
    path="$(command -v "$executable")"
    dependencies="$(ldd "$path")"
    [[ "$dependencies" != *"not found"* ]]
  done
  command_dependencies="$(ldd /usr/lib/cups/filter/command2foo2lava-pjl)"
  [[ "$command_dependencies" != *"not found"* ]]
  wrappers=(
    foo2zjs-wrapper foo2oak-wrapper foo2hp2600-wrapper
    foo2xqx-wrapper foo2lava-wrapper foo2qpdl-wrapper
    foo2slx-wrapper foo2hiperc-wrapper foo2hbpl2-wrapper
    foo2ddst-wrapper foo2zjs-pstops m2300w-wrapper
  )
  for wrapper in "${wrappers[@]}"; do
    path="$(command -v "$wrapper")"
    read -r shebang < "$path"
    [[ "$shebang" == "#!/bin/sh" ]]
  done
  for helper in basename bc cat dc dd expr file foomatic-rip grep gs psicc psnup sed tee tr; do
    command -v "$helper" >/dev/null
  done

  foo_entries="$(/usr/share/ppd/foo2zjs-ppds list)"
  [[ "$foo_entries" == *"Minolta magicolor 2300 DL"* ]]
  m2300_entries="$(/usr/share/ppd/m2300w-ppds list)"
  [[ "$m2300_entries" == *"KONICA MINOLTA magicolor 2300W"* ]]

  printf "%s\n" \
    "%!PS-Adobe-3.0" \
    "%%Pages: 1" \
    "%%Page: 1 1" \
    "newpath 10 10 moveto 60 60 lineto stroke" \
    "showpage" \
    "%%EOF" > "$work/page.ps"

  assert_repeatable() {
    local first_hash second_hash
    test -s "$1"
    test -s "$2"
    read -r first_hash _ < <(sha256sum "$1")
    read -r second_hash _ < <(sha256sum "$2")
    [[ "$first_hash" == "$second_hash" ]]
  }

  /usr/share/ppd/foomatic-ppds cat \
    foomatic-ppds:0/Generic-PCL_5e_Printer-hpijs-pcl5e.ppd > "$work/hpijs.ppd"
  for suffix in first second; do
    PPD="$work/hpijs.ppd" foomatic-rip 1 test test 1 "" "$work/page.ps" \
      > "$work/hpijs-$suffix.prn" 2> "$work/hpijs-$suffix.log"
  done
  assert_repeatable "$work/hpijs-first.prn" "$work/hpijs-second.prn"
  [[ "$(od -An -tx1 -N 16 "$work/hpijs-first.prn")" == " 1b 25 2d 31 32 33 34 35 58 40 50 4a 4c 20 53 45" ]]
  (("$(stat -c %s "$work/hpijs-first.prn")" > 10000))
  printf "OK: full-page HPIJS conversion\n"

  for suffix in first second; do
    foo2zjs-wrapper -z0 -c -C1 "$work/page.ps" \
      > "$work/foo2zjs-$suffix.prn" 2> "$work/foo2zjs-$suffix.log"
  done
  assert_repeatable "$work/foo2zjs-first.prn" "$work/foo2zjs-second.prn"
  [[ "$(od -An -tx1 -N 4 "$work/foo2zjs-first.prn")" == " 4a 5a 4a 5a" ]]
  (("$(stat -c %s "$work/foo2zjs-first.prn")" > 500))
  printf "OK: foo2zjs profile-backed conversion\n"

  # The OAKT header records wall-clock time, so byte-for-byte repeats are invalid.
  foo2oak-wrapper "$work/page.ps" > "$work/foo2oak.prn" 2> "$work/foo2oak.log"
  for suffix in first second; do
    foo2hiperc-wrapper "$work/page.ps" > "$work/foo2hiperc-$suffix.prn" 2> "$work/foo2hiperc-$suffix.log"
  done
  [[ "$(od -An -tx1 -N 4 "$work/foo2oak.prn")" == " 4f 41 4b 54" ]]
  (("$(stat -c %s "$work/foo2oak.prn")" > 1000))
  assert_repeatable "$work/foo2hiperc-first.prn" "$work/foo2hiperc-second.prn"
  [[ "$(od -An -tx1 -N 8 "$work/foo2hiperc-first.prn")" == " 1b 25 2d 31 32 33 34 35" ]]
  (("$(stat -c %s "$work/foo2hiperc-first.prn")" > 1000))

  for suffix in first second; do
    m2300w-wrapper "$work/page.ps" \
      > "$work/m2300w-$suffix.prn" 2> "$work/m2300w-$suffix.log"
  done
  assert_repeatable "$work/m2300w-first.prn" "$work/m2300w-second.prn"
  [[ "$(od -An -tx1 -N 4 "$work/m2300w-first.prn")" == " 1b 40 00 02" ]]
  (("$(stat -c %s "$work/m2300w-first.prn")" > 1000))
  psnup -d2 -2 -m.2in -q < "$work/page.ps" > "$work/psnup.ps" 2> "$work/psnup.log"
  [[ "$(od -An -tc -N 4 "$work/psnup.ps")" == "   %   !   P   S" ]]
  (("$(stat -c %s "$work/psnup.ps")" > 1000))
  m2300w-wrapper -2 "$work/page.ps" > "$work/m2300w-nup.prn" 2> "$work/m2300w-nup.log"
  [[ "$(od -An -tx1 -N 4 "$work/m2300w-nup.prn")" == " 1b 40 00 02" ]]
  (("$(stat -c %s "$work/m2300w-nup.prn")" > 1000))
  test -s /tmp/m2300w.log
  if grep -Eqi "command not found|fatal|error" /tmp/m2300w.log; then
    cat /tmp/m2300w.log >&2
    exit 1
  fi
  printf "OK: m2300w profile-backed and psnup conversions\n"

  printf "# persistence-probe\n" >> "$state/hplip/hplip.conf"
  printf "%% persistence-probe\n" >> "$state/foo2zjs/foo2zjs/gamma.ps"
  printf "%% persistence-probe\n" >> "$state/m2300w/0.51/psfiles/prolog.ps"
'

drivers="$(podman exec "$name" ghostscript-printer-app -u "ipp://127.0.0.1:${port}/ipp/system" drivers)"
for marker in "hpijs-pcl5e" "foo2zjs" "m2300w"; do
  [[ "$drivers" == *"$marker"* ]]
done

podman stop --time 15 "$name" >/dev/null
podman rm "$name" >/dev/null
podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
wait_for_http
podman exec "$name" /usr/bin/bash -c '
  set -euo pipefail
  for file in \
    /var/lib/ghostscript-printer-app/hplip/hplip.conf \
    /var/lib/ghostscript-printer-app/foo2zjs/foo2zjs/gamma.ps \
    /var/lib/ghostscript-printer-app/m2300w/0.51/psfiles/prolog.ps; do
    found=0
    while IFS= read -r line; do
      [[ "$line" == "# persistence-probe" || "$line" == "% persistence-probe" ]] && found=1
    done < "$file"
    [[ "$found" == 1 ]]
  done
'

printf 'OK: stateful drivers execute and preserve user configuration\n'
