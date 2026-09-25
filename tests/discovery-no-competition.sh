#!/usr/bin/env bash
set -euo pipefail


image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
alpha_name="ghostscript-printer-app-discovery-alpha"
beta_name="ghostscript-printer-app-discovery-beta"
alpha_port="${PORT:-18050}"
beta_port="$((alpha_port + 1))"
alpha_sink_port="$((alpha_port + 1000))"
beta_sink_port="$((beta_port + 1000))"
alpha_state_dir="$(mktemp -d)"
beta_state_dir="$(mktemp -d)"
alpha_queue="discovery-alpha"
beta_queue="discovery-beta"

cleanup() {
  podman rm -f "$alpha_name" "$beta_name" >/dev/null 2>&1 || true
  podman unshare rm -rf "$alpha_state_dir" "$beta_state_dir"
}
trap cleanup EXIT

wait_for_http() {
  local target_port="$1" target_name="$2"
  for _ in $(seq 1 60); do
    curl --fail --silent --show-error "http://127.0.0.1:${target_port}/" >/dev/null 2>&1 && return 0
    sleep 1
  done
  podman logs "$target_name" >&2 || true
  return 1
}

start_container() {
  local container_name="$1" container_port="$2" container_state_dir="$3"
  chmod 0777 "$container_state_dir"
  podman run -d \
    --name "$container_name" \
    --network host \
    -e PORT="$container_port" \
    -v "$container_state_dir:/var/lib/ghostscript-printer-app:Z" \
    "$image" >/dev/null
  wait_for_http "$container_port" "$container_name"
}

add_printer() {
  local container_name="$1" container_port="$2" queue="$3" sink_port="$4"
  podman exec "$container_name" ghostscript-printer-app \
    -u "ipp://127.0.0.1:${container_port}/ipp/system" \
    -d "$queue" \
    -m generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en \
    -v "cups:socket://127.0.0.1:${sink_port}" \
    add
}

# Count distinct DNS-SD advertisement names for a given queue substring, as
# seen by an Avahi client on the host network namespace. avahi-browse
# auto-renames a real name collision to "name #2"; counting distinct
# resolved names (not raw lines, which vary with interface/address family)
# distinguishes one owning advertisement from a competing duplicate.
count_advertisements() {
  local observer="$1" queue="$2"
  podman exec "$observer" /usr/bin/bash -c '
    set -euo pipefail
    avahi-browse --parsable --resolve --terminate _ipp._tcp 2>/dev/null \
      | awk -F";" -v marker="'"$queue"'" '"'"'$1 == "=" && index($4, marker) { print $4 }'"'"' \
      | sort -u
  '
}

wait_for_advertisement_count() {
  local observer="$1" queue="$2" expected="$3"
  local names count
  for _ in $(seq 1 30); do
    names="$(count_advertisements "$observer" "$queue" || true)"
    count="$(grep -c . <<<"$names" || true)"
    [[ -z "$names" ]] && count=0
    if [[ "$count" -eq "$expected" ]]; then
      printf '%s\n' "$names"
      return 0
    fi
    sleep 1
  done
  printf 'FAIL: expected %s advertisement(s) for %s, observed %s: %s\n' \
    "$expected" "$queue" "$count" "$names" >&2
  return 1
}

just build

start_container "$alpha_name" "$alpha_port" "$alpha_state_dir"
start_container "$beta_name" "$beta_port" "$beta_state_dir"

add_printer "$alpha_name" "$alpha_port" "$alpha_queue" "$alpha_sink_port"
add_printer "$beta_name" "$beta_port" "$beta_queue" "$beta_sink_port"

wait_for_advertisement_count "$alpha_name" "$alpha_queue" 1 >/dev/null
wait_for_advertisement_count "$beta_name" "$beta_queue" 1 >/dev/null
printf 'OK: two distinct synthetic printers each hold exactly one DNS-SD advertisement\n'

for cycle in 1 2 3; do
  podman stop --time 15 "$alpha_name" >/dev/null
  wait_for_advertisement_count "$beta_name" "$alpha_queue" 0 >/dev/null
  podman rm "$alpha_name" >/dev/null
  start_container "$alpha_name" "$alpha_port" "$alpha_state_dir"
  wait_for_advertisement_count "$beta_name" "$alpha_queue" 1 >/dev/null
  wait_for_advertisement_count "$beta_name" "$beta_queue" 1 >/dev/null
  printf 'OK: restart cycle %s left exactly one advertisement for %s and did not disturb %s\n' \
    "$cycle" "$alpha_queue" "$beta_queue"
done

podman exec "$alpha_name" /usr/bin/bash -c '
  test -d /var/lib/ghostscript-printer-app/spool
'
podman exec "$beta_name" /usr/bin/bash -c '
  test -d /var/lib/ghostscript-printer-app/spool
'
[[ "$alpha_port" != "$beta_port" ]]
[[ "$alpha_state_dir" != "$beta_state_dir" ]]
printf 'OK: distinct ports and state volumes persisted across restart without a duplicate IPP queue advertisement\n'

podman stop --time 15 "$alpha_name" "$beta_name" >/dev/null
podman run -d \
  --name "$alpha_name" \
  --network host \
  -e PORT="$alpha_port" \
  -v "$alpha_state_dir:/var/lib/ghostscript-printer-app:Z" \
  "$image" >/dev/null
wait_for_http "$alpha_port" "$alpha_name"
wait_for_advertisement_count "$alpha_name" "$alpha_queue" 1 >/dev/null
wait_for_advertisement_count "$alpha_name" "$beta_queue" 0 >/dev/null
printf 'OK: stopping both services and restarting one alone leaves no orphaned advertisement for the stopped peer\n'

printf 'NOTE: real USB interface claiming and GNOME print dialog behavior are unverified here; both require physical hardware and a desktop session.\n'
printf 'OK: repeated Ghostscript Printer Application discovery does not compete for one synthetic printer\n'
