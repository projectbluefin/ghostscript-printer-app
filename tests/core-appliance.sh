#!/usr/bin/env bash
set -Eeuo pipefail

image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
name="ghostscript-printer-app-smoke"
failure_name="ghostscript-printer-app-child-failure"
invalid_name="ghostscript-printer-app-invalid-port"
state_failure_name="ghostscript-printer-app-state-failure"
no_web_name="ghostscript-printer-app-no-web-interface"
rejected_name="ghostscript-printer-app-rejected-setting"
large_output_name="ghostscript-printer-app-large-log"
port="${PORT:-18000}"
failure_port="$((port + 1))"
no_web_port="$((port + 2))"
no_web_sink_port="$((no_web_port + 1000))"
no_web_output="$(mktemp)"
no_web_sink_pid=""
state_dir="$(mktemp -d)"
empty_state_dir="$(mktemp -d)"
no_web_state_dir="$(mktemp -d)"

# On any failure, name the failing command and dump the appliance state so a
# CI failure explains itself. Subshells inherit the ERR trap (-E); only the top
# level records, so the reported line is the script's own.
failed_command=""
record_failure() {
  ((BASH_SUBSHELL == 0)) && [[ -z "$failed_command" ]] && failed_command="line $1: ${2%%$'\n'*}"
  return 0
}

dump_diagnostics() {
  local container
  printf 'FAIL: %s\n' "${failed_command:-explicit exit}" >&2
  podman ps -a >&2 || true
  for container in "$name" "$failure_name" "$invalid_name" "$state_failure_name" "$no_web_name" "$rejected_name"; do
    podman container exists "$container" 2>/dev/null || continue
    printf -- '--- %s: %s\n' "$container" \
      "$(podman inspect "$container" --format '{{.State.Status}} exit={{.State.ExitCode}}' 2>&1)" >&2
    podman logs --tail 50 "$container" >&2 2>&1 || true
  done
  printf -- '--- state volume\n' >&2
  podman unshare find "$state_dir" "$state_dir/cups" "$state_dir/.cups/ssl" "$state_dir/spool" \
    -maxdepth 1 -printf '%m %U:%G %p\n' >&2 2>/dev/null || true
  if podman unshare test -s "$state_dir/ghostscript-printer-app.log"; then
    printf -- '--- application log\n' >&2
    podman unshare tail -n 50 "$state_dir/ghostscript-printer-app.log" >&2 || true
  fi
}

cleanup() {
  local status=$?
  trap - ERR
  ((status == 0)) || dump_diagnostics
  podman rm --force --ignore "$name" "$failure_name" "$invalid_name" "$state_failure_name" "$no_web_name" "$rejected_name" "$large_output_name" >/dev/null 2>&1 || true
  if [[ -n "$no_web_sink_pid" ]]; then
    kill "$no_web_sink_pid" >/dev/null 2>&1 || true
    wait "$no_web_sink_pid" 2>/dev/null || true
  fi
  podman unshare chmod -R u+w "$state_dir" "$empty_state_dir" "$no_web_state_dir"
  podman unshare rm -rf "$state_dir" "$empty_state_dir" "$no_web_state_dir"
  rm -f "$no_web_output"
}
trap 'record_failure "$LINENO" "$BASH_COMMAND"' ERR
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

http_status() {
  local scheme="$1" target_port="$2" path="$3"
  curl --insecure --silent --output /dev/null --write-out '%{http_code}' \
    "${scheme}://127.0.0.1:${target_port}${path}" 2>/dev/null || printf '000'
}

# A rejected setting must exit before any service starts, with the named
# status and a diagnostic that explains the refusal.
expect_rejected_setting() {
  local expected_status="$1" expected_message="$2"
  shift 2
  local status logs
  set +e
  podman run --name "$rejected_name" "$@" "$image" >/dev/null 2>&1
  status=$?
  set -e
  logs="$(podman logs "$rejected_name" 2>&1)"
  if [[ "$status" -ne "$expected_status" || "$logs" != *"$expected_message"* ]]; then
    printf '%s\nFAIL: %s must exit %s with "%s" (status=%s)\n' "$logs" "$*" "$expected_status" "$expected_message" "$status" >&2
    exit 1
  fi
  podman rm "$rejected_name" >/dev/null
}

# Buffer container logs completely before matching to avoid SIGPIPE (exit 141)
# under pipefail when grep -q exits early while podman logs is streaming.
assert_container_log() {
  local container="$1" expected="$2"
  local logs
  logs="$(podman logs "$container" 2>&1)"
  if [[ "$logs" != *"$expected"* ]]; then
    printf 'FAIL: %s logs do not contain %q\n%s\n' "$container" "$expected" "$logs" >&2
    exit 1
  fi
}

assert_container_log_absent() {
  local container="$1" unexpected="$2"
  local logs
  logs="$(podman logs "$container" 2>&1)"
  if [[ "$logs" == *"$unexpected"* ]]; then
    printf 'FAIL: %s logs unexpectedly contain %q\n%s\n' "$container" "$unexpected" "$logs" >&2
    exit 1
  fi
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
# Without a credential or no-web-interface the web admin is LAN-reachable on
# host networking; the entrypoint must say so.
assert_container_log "$name" 'NOTICE: web administration is reachable'
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
# PAPPL keeps one key per server hostname and names itself twice at startup:
# first the resolver's FQDN, then Avahi's ".local" name once the Avahi client
# is running. Whether an HTTPS request lands before that switch is timing, so
# a restart may add the other name's key. Every existing key must survive
# byte-identical; new keys are covered by check_private_state above.
while read -r key_line; do
  if [[ $'\n'"$keys_after"$'\n' != *$'\n'"$key_line"$'\n'* ]]; then
    printf 'FAIL: TLS key was lost or regenerated across restart: %s\nbefore:\n%s\nafter:\n%s\n' \
      "$key_line" "$keys_before" "$keys_after" >&2
    exit 1
  fi
done <<< "$keys_before"
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
assert_container_log "$invalid_name" 'PORT must be numeric'

# Web administration knobs (ChairLift ADR-0016). Malformed or unsupported
# values fail closed instead of starting an unauthenticated web admin.
expect_rejected_setting 64 "unsupported option 'no-tls'" -e PRINTER_APP_SERVER_OPTIONS=no-web-interface,no-tls
# The shared printing base builds PAPPL without PAM, so no auth service can
# authenticate anyone in this image; refuse it rather than lock every
# administrator out with 401. /etc/pam.d/cups ships with CUPS, so the refusal
# must not depend on whether the named service file exists.
podman run --rm --entrypoint /usr/bin/bash "$image" -c 'test -f /etc/pam.d/cups && test ! -e /etc/pam.d/chairlift-printer'
expect_rejected_setting 78 'PAPPL is built without PAM' -e PRINTER_APP_AUTH_SERVICE=cups
expect_rejected_setting 78 'PAPPL is built without PAM' -e PRINTER_APP_AUTH_SERVICE=chairlift-printer
expect_rejected_setting 78 'PRINTER_APP_ADMIN_GROUP requires PRINTER_APP_AUTH_SERVICE' -e PRINTER_APP_ADMIN_GROUP=nonroot

# With the web interface disabled, every admin page is gone while IPP keeps
# accepting and printing jobs.
chmod 0777 "$no_web_state_dir"
python3 tests/socket-sink.py "$no_web_sink_port" "$no_web_output" &
no_web_sink_pid=$!
podman run -d \
  --name "$no_web_name" \
  --network host \
  -e PORT="$no_web_port" \
  -e PRINTER_APP_SERVER_OPTIONS=no-web-interface \
  -v "$no_web_state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null
no_web_system_uri="ipp://127.0.0.1:${no_web_port}/ipp/system"
no_web_printer_uri="ipp://127.0.0.1:${no_web_port}/ipp/print/no-web-test"
ready=0
for _ in $(seq 1 60); do
  if [[ "$(http_status http "$no_web_port" /)" == 404 && "$(http_status https "$no_web_port" /)" == 404 ]]; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  printf 'FAIL: listener did not answer (with 404) after starting with no-web-interface\n' >&2
  exit 1
fi
assert_container_log_absent "$no_web_name" 'NOTICE: web administration is reachable'
podman exec "$no_web_name" ghostscript-printer-app \
  -u "$no_web_system_uri" \
  -d no-web-test \
  -m generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en \
  -v "cups:socket://127.0.0.1:${no_web_sink_port}" \
  add
for scheme in http https; do
  for path in / /addprinter /config /network /security /no-web-test/ /no-web-test/config /no-web-test/device; do
    status="$(http_status "$scheme" "$no_web_port" "$path")"
    if [[ "$status" != 404 ]]; then
      printf 'FAIL: %s://127.0.0.1:%s%s returned %s with no-web-interface, expected 404\n' "$scheme" "$no_web_port" "$path" "$status" >&2
      exit 1
    fi
  done
done
podman exec "$no_web_name" ghostscript-printer-app -u "$no_web_printer_uri" \
  submit /usr/share/ghostscript-printer-app/testpage.ps >/dev/null
for _ in $(seq 1 120); do
  [[ -s "$no_web_output" ]] && break
  sleep 0.5
done
if [[ ! -s "$no_web_output" ]]; then
  podman exec "$no_web_name" ghostscript-printer-app -u "$no_web_printer_uri" jobs >&2 || true
  printf 'FAIL: IPP print job produced no socket output with no-web-interface\n' >&2
  exit 1
fi
wait "$no_web_sink_pid"
no_web_sink_pid=""
python3 -c 'import pathlib, sys; assert pathlib.Path(sys.argv[1]).read_bytes().startswith(b"\x1b%-12345X")' "$no_web_output"
podman stop --time 15 "$no_web_name" >/dev/null

# Verify that log assertions safely handle container output exceeding a standard
# 64 KiB pipe buffer without SIGPIPE (exit 141) under pipefail for both positive
# and negative matches against the actual image container.
podman run --name "$large_output_name" "$image" /usr/bin/bash -c '
  printf "BEGIN_LARGE_OUTPUT\n"
  for i in $(seq 1 1200); do
    printf "padding-line-%04d-0123456789abcdef0123456789abcdef0123456789abcdef\n" "$i"
  done
  printf "END_LARGE_OUTPUT\n"
' >/dev/null
assert_container_log "$large_output_name" "BEGIN_LARGE_OUTPUT"
assert_container_log "$large_output_name" "padding-line-0600"
assert_container_log "$large_output_name" "END_LARGE_OUTPUT"
assert_container_log_absent "$large_output_name" "NONEXISTENT_MARKER"
podman rm "$large_output_name" >/dev/null

printf 'OK: core FSDK Printer Application passed lifecycle verification\n'
