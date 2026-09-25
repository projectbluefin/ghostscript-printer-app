#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-smoke"
failure_name="ghostscript-printer-app-child-failure"
invalid_name="ghostscript-printer-app-invalid-port"
port="${PORT:-18000}"
failure_port="$((port + 1))"
state_dir="$(mktemp -d)"

cleanup() {
  podman rm -f "$name" "$failure_name" "$invalid_name" >/dev/null 2>&1 || true
  podman unshare rm -rf "$state_dir"
}
trap cleanup EXIT

wait_for_http() {
  local target_port="$1"
  local response
  for _ in $(seq 1 60); do
    if response="$(curl --fail --silent --show-error "http://127.0.0.1:${target_port}/" 2>/dev/null)" && [[ "$response" == *'<title>Ghostscript Printer Application</title>'* ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

just build
chmod 0777 "$state_dir"

podman run -d \
  --name "$name" \
  --network host \
  -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

wait_for_http "$port"
podman exec "$name" /usr/bin/bash -c '
  set -e
  test "$(id -u):$(id -g)" = 65532:65532
  test "$(id -un)" = nonroot
  passwd_ok=0
  while IFS=: read -r name password uid gid gecos home shell; do
    [[ "$name:$uid:$gid" == "nonroot:65532:65532" ]] && passwd_ok=1
  done < /etc/passwd
  group_ok=0
  while IFS=: read -r name password gid members; do
    [[ "$name:$gid" == "nonroot:65532" ]] && group_ok=1
  done < /etc/group
  (( passwd_ok && group_ok ))
'
test -d "$state_dir/ppd"
test -d "$state_dir/spool"
test -d "$state_dir/cups/ssl"
test -s "$state_dir/cups/snmp.conf"
test -d "$state_dir/usb"
test -s "$state_dir/usb/org.cups.usb-quirks"
podman exec "$name" /usr/bin/bash -c 'printf "%s\n" "# preserved" > /var/lib/ghostscript-printer-app/cups/snmp.conf'
podman exec "$name" /usr/bin/bash -c 'printf "%s\n" "# preserved" >> /var/lib/ghostscript-printer-app/usb/org.cups.usb-quirks'
podman stop --time 15 "$name" >/dev/null
read -r running exit_status <<< "$(podman inspect "$name" --format '{{.State.Running}} {{.State.ExitCode}}')"
if [[ "$running" != false || "$exit_status" -ne 143 ]]; then
  podman logs "$name" >&2
  printf 'FAIL: TERM shutdown ended in state %s with status %s, expected false 143\n' "$running" "$exit_status" >&2
  exit 1
fi

podman run -d \
  --name "$failure_name" \
  --network host \
  -e PORT="$failure_port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

wait_for_http "$failure_port"
podman exec "$failure_name" /usr/bin/bash -c 'test "$(< /var/lib/ghostscript-printer-app/cups/snmp.conf)" = "# preserved"'
podman exec "$failure_name" /usr/bin/bash -c 'grep -q "^# preserved$" /var/lib/ghostscript-printer-app/usb/org.cups.usb-quirks'
podman exec "$failure_name" /usr/bin/bash -c '
  for proc in /proc/[0-9]*; do
    read -r comm < "$proc/comm" || continue
    if [[ "$comm" == avahi-daemon ]]; then
      kill -TERM "${proc##*/}"
      exit 0
    fi
  done
  exit 1
'
for _ in $(seq 1 150); do
  running="$(podman inspect "$failure_name" --format '{{.State.Running}}')"
  [[ "$running" == false ]] && break
  sleep 0.1
done
read -r running failure_status <<< "$(podman inspect "$failure_name" --format '{{.State.Running}} {{.State.ExitCode}}')"
if [[ "$running" != false ]]; then
  podman logs "$failure_name" >&2
  printf 'FAIL: container stayed running after a required child died\n' >&2
  exit 1
fi
if [[ "$failure_status" -eq 0 ]]; then
  printf 'FAIL: required child failure returned success\n' >&2
  exit 1
fi

set +e
podman run --name "$invalid_name" -e PORT=invalid "$image" >/dev/null 2>&1
invalid_status=$?
set -e
if [[ "$invalid_status" -ne 64 ]]; then
  printf 'FAIL: invalid PORT exited %s instead of 64\n' "$invalid_status" >&2
  exit 1
fi
if ! podman logs "$invalid_name" 2>&1 | grep -q 'PORT must be numeric'; then
  printf 'FAIL: invalid PORT diagnostic missing\n' >&2
  exit 1
fi

printf 'OK: core FSDK Printer Application passed lifecycle verification\n'
