#!/usr/bin/env bash
# Pin the driver the appliance picks for a printer from its IEEE-1284 device
# ID: ghostscript_autoadd() first asks for a model-specific PPD and otherwise
# falls back, in order, to the Generic PostScript, PCL 6/PCL XL, PCL 5c and
# PCL 5e drivers named in the printer's command set; a printer speaking none of
# those languages gets no driver. Auto-add and "Add Printer" with the "auto"
# driver both go through this callback, so a broken fallback or a reordered
# driver_selection_regex_list silently leaves printers unconfigured or on a
# worse driver. PAPPL's "drivers -o device-id=..." subcommand runs the same
# callback without a server, a device or a network.
set -euo pipefail

image="ghcr.io/projectbluefin/ghostscript-printer-app:build"

# Always build from this checkout's graph. Never test an unrelated pulled image.
just build

podman run --rm --entrypoint /usr/bin/bash -e PPD_PATHS=/usr/share/ppd/ "$image" -c '
  set -euo pipefail
  export TMPDIR=/tmp
  failures=0

  # The option value is quoted for cupsParseOptions(): unquoted, a space in a
  # model name ("MDL:PostScript Printer") ends the value and nothing matches.
  selected() {
    /usr/bin/ghostscript-printer-app drivers -o "device-id='"'"'$1'"'"'" 2>/dev/null |
      cut -d" " -f1
  }

  expect() {
    local label="$1" device_id="$2" expected="$3" actual
    actual="$(selected "$device_id")"
    if [[ "$actual" == "$expected" ]]; then
      printf "ok: %s -> %s\n" "$label" "${expected:-<no driver>}"
    else
      printf "FAIL: %s: device ID %s selected %q, expected %q\n" \
        "$label" "$device_id" "$actual" "$expected" >&2
      failures=$((failures + 1))
    fi
  }

  ps=generic--postscript-printer--postscript-recommended-en
  pclxl=generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en
  pcl5c=generic--pcl-5-c-printer--hpijs-pcl-5-c-recommended-en
  pcl5e=generic--pcl-5-e-printer--hpijs-pcl-5-e-recommended-en
  unknown="MFG:Acme;MDL:Nonexistent 1;"

  # A model-specific PPD wins over every generic fallback, including a
  # PostScript one the same printer also qualifies for.
  expect "model match (Foomatic)" "MFG:Kyocera;MDL:FS-1020D;CMD:PJL,PCLXL;" \
    kyocera--fs-1020-d--postscript-kyocera-recommended-en
  expect "model match (packaged brlaser)" "MFG:Brother;MDL:HL-1110 series;CMD:PJL,HBP;" \
    brother--hl-1110--using-owl-maintain-brlaser-v-6-2-8-en

  # Each generic fallback, reached through both device ID spellings.
  expect "PostScript fallback" "${unknown}CMD:POSTSCRIPT;" "$ps"
  expect "BR-Script fallback (COMMAND SET)" "${unknown}COMMAND SET:BRSCRIPT;" "$ps"
  expect "PCL XL fallback" "${unknown}CMD:PCLXL;" "$pclxl"
  expect "PCL 6 fallback" "${unknown}CMD:PCL 6;" "$pclxl"
  expect "PCL 5c fallback" "${unknown}CMD:PCL5C;" "$pcl5c"
  expect "PCL 5e fallback" "${unknown}CMD:PCL5E;" "$pcl5e"
  expect "plain PCL fallback" "${unknown}CMD:PCL;" "$pcl5e"

  # The fallback order: PostScript, then PCL XL, then PCL 5c, then PCL 5e.
  expect "PostScript before PCL XL and PCL" "${unknown}CMD:PCL,PCLXL,POSTSCRIPT;" "$ps"
  expect "PCL XL before PCL" "${unknown}CMD:PCL,PCLXL;" "$pclxl"
  expect "PCL 5c before PCL 5e" "${unknown}CMD:PCL,PCL5C;" "$pcl5c"

  # No supported page description language: no driver, not a wrong one.
  expect "unsupported language" "${unknown}CMD:ESCPL2;" ""
  expect "no command set" "$unknown" ""

  if ((failures)); then
    printf "FAIL: %d driver selection case(s) failed\n" "$failures" >&2
    exit 1
  fi
'

printf 'OK: automatic driver selection follows the model match and generic fallback order\n'
