#!/usr/bin/env bash
set -euo pipefail

cups_base_target="fsdk-containers.bst:freedesktop-sdk.bst:components/_private/cups-base.bst"
dependent_target="fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst"
source_dir=".bst/cups-patch-chain-source"

resolved="$(just bst show --deps none --format '%{name}' "$dependent_target")"
if ! grep -qxF "$dependent_target" <<<"$resolved"; then
  printf 'FAIL: expected resolved target %s\n' "$dependent_target" >&2
  printf '%s\n' "$resolved" >&2
  exit 1
fi

deps="$(just bst show --deps all --format '%{name}' "$dependent_target")"
cups_base_count="$(grep -c '^fsdk-containers\.bst:freedesktop-sdk\.bst:components/_private/cups-base\.bst$' <<<"$deps" || true)"
if [[ "$cups_base_count" != 1 ]]; then
  printf 'FAIL: expected one CUPS base provider, found %s\n' "$cups_base_count" >&2
  exit 1
fi

cups_public="$(just bst show --deps none --format '%{public}' "$cups_base_target")"
grep -q 'cups-libs' <<<"$cups_public"
grep -q 'cups-license' <<<"$cups_public"

rm -rf "$source_dir"
just bst source checkout --force --directory "$source_dir" "$cups_base_target"
cups_source="$source_dir/fsdk-containers/freedesktop-sdk/components-_private-cups-base"
grep -q 'getenv("USB_QUIRK_DIR")' "$cups_source/backend/usb-libusb.c"
grep -q 'browsers = /\*6\*/1' "$cups_source/backend/dnssd.c"

app_deps="$(just bst show --deps all --format '%{name}' oci/ghostscript-printer-app.bst)"
if ! grep -qxF 'fsdk-containers.bst:printing/base.bst' <<<"$app_deps"; then
  printf 'FAIL: the image does not build on fsdk-containers.bst:printing/base.bst\n' >&2
  exit 1
fi
# Both avahi elements install avahi-daemon; only the printing one may be staged.
if grep -qxF 'fsdk-containers.bst:freedesktop-sdk.bst:components/avahi.bst' <<<"$app_deps"; then
  printf 'FAIL: components/avahi.bst is staged next to avahi-printing.bst\n' >&2
  exit 1
fi

printf 'OK: patched CUPS graph resolves with one provider, stable split rules, and patched sources\n'
