#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-smoke"
failure_name="ghostscript-printer-app-child-failure"
invalid_name="ghostscript-printer-app-invalid-port"
state_failure_name="ghostscript-printer-app-state-failure"
port="${PORT:-18000}"
failure_port="$((port + 1))"
state_dir="$(mktemp -d)"
empty_state_dir="$(mktemp -d)"

cleanup() {
  podman rm -f "$name" "$failure_name" "$invalid_name" "$state_failure_name" >/dev/null 2>&1 || true
  podman unshare chmod -R u+w "$state_dir" "$empty_state_dir"
  podman unshare rm -rf "$state_dir" "$empty_state_dir"
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

# Use the image's numeric user and real entrypoint, with a bounded wait so a
# regression that reaches readiness cannot hang verification indefinitely.
expect_state_failure() {
  local volume="$1" expected_path="$2"
  local running status logs
  podman run -d --name "$state_failure_name" -v "$volume" "$image" >/dev/null
  for _ in $(seq 1 100); do
    running="$(podman inspect "$state_failure_name" --format '{{.State.Running}}')"
    [[ "$running" == false ]] && break
    sleep 0.1
  done
  read -r running status <<< "$(podman inspect "$state_failure_name" --format '{{.State.Running}} {{.State.ExitCode}}')"
  logs="$(podman logs "$state_failure_name" 2>&1)"
  if [[ "$running" != false || "$status" -ne 73 || "$logs" != *"Persistent state is not writable: $expected_path;"* ]]; then
    printf '%s\nFAIL: unwritable state must exit 73 with a path-specific diagnostic (running=%s, status=%s)\n' "$logs" "$running" "$status" >&2
    exit 1
  fi
  podman rm "$state_failure_name" >/dev/null
}

wait_for_https() {
  local target_port="$1"
  local response
  for _ in $(seq 1 60); do
    # The appliance generates its own certificate on the persistent volume.
    if response="$(curl --insecure --fail --silent --show-error "https://127.0.0.1:${target_port}/" 2>/dev/null)" && [[ "$response" == *'<title>Ghostscript Printer Application</title>'* ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

check_private_state() {
  if ! podman exec "$1" /usr/bin/bash -c '
    set -euo pipefail
    state=/var/lib/ghostscript-printer-app
    for dir in "$state/cups" "$state/cups/ssl" "$state/.cups" "$state/.cups/ssl" "$state/spool"; do
      test "$(stat -c %a "$dir")" = 700
      test "$(stat -c %u:%g "$dir")" = 65532:65532
    done
    shopt -s nullglob
    keys=("$state/.cups/ssl/"*.key)
    (( ${#keys[@]} > 0 ))
    for key in "${keys[@]}"; do
      test -s "$key"
      test "$(stat -c %a "$key")" = 600
      test "$(stat -c %u:%g "$key")" = 65532:65532
    done
  '; then
    printf 'FAIL: private state is not restricted to the runtime user\n' >&2
    podman exec "$1" /usr/bin/bash -c 'cd /var/lib/ghostscript-printer-app && stat -c "%a %u:%g %n" . cups cups/ssl .cups .cups/ssl spool .cups/ssl/* cups/ssl/*' >&2 || true
    return 1
  fi
}

just build
# Inspect the shipped layer before its entrypoint can alter the filesystem.
podman run --rm --entrypoint /usr/bin/bash "$image" -ec '
  test ! -e /etc/avahi/services/ssh.service
  test ! -e /etc/avahi/services/sftp-ssh.service
'
chmod 0777 "$state_dir" "$empty_state_dir"
expect_state_failure "$empty_state_dir:/var/lib/ghostscript-printer-app:ro,Z" /var/lib/ghostscript-printer-app

podman run -d \
  --name "$name" \
  --network host \
  -e PORT="$port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

wait_for_http "$port"
wait_for_https "$port"
check_private_state "$name"
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
podman exec "$name" /usr/bin/bash -c '
  set -e
  state=/var/lib/ghostscript-printer-app
  test -d "$state/ppd"
  test -s "$state/cups/snmp.conf"
  test -s "$state/usb/org.cups.usb-quirks"
  printf "private job\n" > "$state/spool/permission-probe"
'
keys_before="$(podman exec "$name" /usr/bin/bash -c 'sha256sum /var/lib/ghostscript-printer-app/.cups/ssl/*.key')"
podman exec "$name" /usr/bin/bash -c 'command -v avahi-browse' >/dev/null
podman exec "$name" /usr/bin/bash -c 'printf "%s\n" "# preserved" > /var/lib/ghostscript-printer-app/cups/snmp.conf'
podman exec "$name" /usr/bin/bash -c 'printf "%s\n" "# preserved USB quirks" > /var/lib/ghostscript-printer-app/usb/org.cups.usb-quirks'
podman stop --time 15 "$name" >/dev/null
read -r running exit_status <<< "$(podman inspect "$name" --format '{{.State.Running}} {{.State.ExitCode}}')"
if [[ "$running" != false || "$exit_status" -ne 143 ]]; then
  podman logs "$name" >&2
  printf 'FAIL: TERM shutdown ended in state %s with status %s, expected false 143\n' "$running" "$exit_status" >&2
  exit 1
fi

# Simulate an older volume with exposed keys and nested queued-job state.
podman run --rm --entrypoint /usr/bin/bash \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" -c '
    set -e
    state=/var/lib/ghostscript-printer-app
    mkdir -p "$state/spool/legacy"
    printf "nested job\n" > "$state/spool/legacy/job"
    chmod 0777 "$state/cups" "$state/cups/ssl" "$state/.cups" "$state/.cups/ssl" "$state/spool" "$state/spool/legacy"
    chmod 0666 "$state/.cups/ssl/"*.key "$state/spool/permission-probe" "$state/spool/legacy/job"
  '

podman run -d \
  --name "$failure_name" \
  --network host \
  -e PORT="$failure_port" \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null

wait_for_http "$failure_port"
wait_for_https "$failure_port"
check_private_state "$failure_name"
keys_after="$(podman exec "$failure_name" /usr/bin/bash -c 'sha256sum /var/lib/ghostscript-printer-app/.cups/ssl/*.key')"
test "$keys_before" = "$keys_after"
podman exec "$failure_name" /usr/bin/bash -c '
  set -e
  state=/var/lib/ghostscript-printer-app
  test "$(stat -c %a "$state/spool/legacy")" = 700
  test "$(stat -c %a "$state/spool/legacy/job")" = 600
  test "$(stat -c %a "$state/spool/permission-probe")" = 600
  test "$(cat "$state/spool/permission-probe")" = "private job"
  test "$(cat "$state/spool/legacy/job")" = "nested job"
'
podman exec "$failure_name" /usr/bin/bash -c 'test "$(< /var/lib/ghostscript-printer-app/cups/snmp.conf)" = "# preserved"'
podman exec "$failure_name" /usr/bin/bash -c 'test "$(< /var/lib/ghostscript-printer-app/usb/org.cups.usb-quirks)" = "# preserved USB quirks"'
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

# A populated read-only volume must fail too: mkdir and default seeding can
# otherwise be no-ops, letting the application appear ready.
expect_state_failure "$state_dir:/var/lib/ghostscript-printer-app:ro,Z" /var/lib/ghostscript-printer-app
podman run --rm --entrypoint /usr/bin/bash \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" \
  -c 'chmod a-w /var/lib/ghostscript-printer-app/spool'
expect_state_failure "$state_dir:/var/lib/ghostscript-printer-app:Z" /var/lib/ghostscript-printer-app/spool
podman run --rm --entrypoint /usr/bin/bash \
  -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" \
  -c 'chmod u+w /var/lib/ghostscript-printer-app/spool'

for state_file in ghostscript-printer-app.state ghostscript-printer-app.log; do
  podman run --rm --entrypoint /usr/bin/bash \
    -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" \
    -c 'touch "$1"; chmod a-w "$1"' -- "/var/lib/ghostscript-printer-app/$state_file"
  expect_state_failure "$state_dir:/var/lib/ghostscript-printer-app:Z" "/var/lib/ghostscript-printer-app/$state_file"
  podman run --rm --entrypoint /usr/bin/bash \
    -v "$state_dir:/var/lib/ghostscript-printer-app:Z" "$image" \
    -c 'chmod u+w "$1"' -- "/var/lib/ghostscript-printer-app/$state_file"
done

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
