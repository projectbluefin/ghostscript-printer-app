#!/usr/bin/env bash
#
# Ghostscript Printer Application default-port coexistence (issue #17,
# "Default port and coexistence case").
#
# PR #57 proved two explicit-port Ghostscript instances do not compete for a
# synthetic printer, but left the entrypoint's no-PORT path untested: PAPPL
# supplies server-port only when PORT is set and otherwise lets the OS assign a
# random ephemeral listener port. This exercises that actual default against a
# second Ghostscript instance (and, when its image is built, another rootless
# app) on host networking and asserts distinct ephemeral ports and exactly one
# owning DNS-SD advertisement per synthetic printer.
#
# DNS-SD verification runs avahi-browse inside each container (its own
# avahi-daemon), so the per-instance count is deterministic. The cross-host
# probe is best-effort: it fails only on a real duplicate advertisement, never
# when mDNS is quiet. Opt-in, not part of `just verify` (needs host Avahi and
# multicast); see verify-service-advertisements for the same pattern.
set -euo pipefail

image="ghcr.io/projectbluefin/ghostscript-printer-app:build"
model="generic--pcl-6-pcl-xl-printer--pxlcolor-recommended-en"

state_a="$(mktemp -d)"
state_b="$(mktemp -d)"
state_other="$(mktemp -d)"
output_file="$(mktemp)"
sink_pid=""

cleanup() {
  for name in gs-a gs-b probe; do
    podman rm -f "$name" >/dev/null 2>&1 || true
  done
  if [[ -n "$sink_pid" ]]; then
    kill "$sink_pid" >/dev/null 2>&1 || true
    wait "$sink_pid" 2>/dev/null || true
  fi
  podman unshare rm -rf "$state_a" "$state_b" "$state_other" 2>/dev/null || true
  rm -f "$output_file"
}
trap cleanup EXIT

just build

# Synthetic backend target: print jobs route here; no real hardware.
python3 tests/socket-sink.py "$((18060))" "$output_file" &
sink_pid=$!

# --- helpers -------------------------------------------------------------

wait_http() { # name port
  local name="$1" port="$2"
  for _ in $(seq 1 60); do
    curl --fail --silent --show-error "http://127.0.0.1:${port}/" >/dev/null 2>&1 && return 0
    sleep 1
  done
  podman logs "$name" >&2 || true
  return 1
}

# Discover the ephemeral listener port a no-PORT container bound, excluding the
# ports already taken by the other instances and the sink.
discover_port() { # name exclude...( port ... )
  local name="$1"; shift
  local -a exclude=("$@")
  local p
  for _ in $(seq 1 60); do
    while read -r p; do
      local skip=0 e
      for e in "${exclude[@]}"; do [[ "$p" == "$e" ]] && { skip=1; break; }; done
      [[ "$skip" == 0 ]] && { printf '%s' "$p"; return 0; }
    done < <(podman exec "$name" bash -c '
      awk "NR>1 && $4==\"0A\" {split($2,a,\":\"); print a[2]}" /proc/net/tcp /proc/net/tcp6 2>/dev/null \
      | while read -r h; do printf "%d\n" "0x$h"; done | sort -un
    ')
    sleep 0.5
  done
  return 1
}

add_printer() { # name port queue sink_port
  podman exec "$1" ghostscript-printer-app \
    -u "ipp://127.0.0.1:${2}/ipp/system" \
    -d "$3" -m "$model" \
    -v "cups:socket://127.0.0.1:${4}" add
}

# Own _ipp._tcp advertisements for queue, seen by a container's own avahi.
# dns_sd_name is the printer name (papplPrinterCreate), so this is exact even
# if mDNS propagates between containers.
own_ad_count() { # name queue
  podman exec "$1" avahi-browse -p -a -t _ipp._tcp 2>/dev/null \
    | grep -cF "\"$2\"" || true
}

wait_count() { # name queue expected
  local name="$1" queue="$2" expected="$3" got
  for _ in $(seq 1 30); do
    got="$(own_ad_count "$name" "$queue")"
    [[ "$got" == "$expected" ]] && return 0
    sleep 1
  done
  printf 'FAIL: expected %s advertisement for %s, observed %s\n' "$expected" "$queue" "$got" >&2
  podman logs "$name" >&2 || true
  return 1
}

# All _ipp._tcp instance names visible on the host network namespace.
host_ads() {
  podman run --rm --network host --entrypoint /usr/bin/avahi-browse \
    "$image" -p -a -t _ipp._tcp 2>/dev/null \
    | grep '_ipp._tcp' | grep -oE '"[^"]+"' | sort || true
}

# --- instance A: default (no PORT) ephemeral port ------------------------

podman run -d --name gs-a --network host \
  -v "$state_a:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
port_a="$(discover_port gs-a "$((18060))")" || { printf 'FAIL: no ephemeral port discovered for gs-a\n'; exit 1; }
wait_http gs-a "$port_a"
add_printer gs-a "$port_a" discovery-default-a "$((18060))"
wait_count gs-a discovery-default-a 1
printf 'OK: no-PORT Ghostscript binds an ephemeral port (%s) and advertises its printer once\n' "$port_a"

# --- restart A: state persists, still exactly one advertisement ----------

podman stop --time 10 gs-a >/dev/null
podman rm gs-a >/dev/null
podman run -d --name gs-a --network host \
  -v "$state_a:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
port_a="$(discover_port gs-a "$((18060))")" || { printf 'FAIL: no ephemeral port after restart\n'; exit 1; }
wait_http gs-a "$port_a"
# Printer must already exist from persisted state; a duplicate would show twice.
wait_count gs-a discovery-default-a 1
printf 'OK: gs-a state and single advertisement persist across restart (default port)\n'

# --- instance B: another default (no PORT) instance, distinct port -------

podman run -d --name gs-b --network host \
  -v "$state_b:/var/lib/ghostscript-printer-app:Z" "$image" >/dev/null
port_b="$(discover_port gs-b "$port_a" "$((18060))")" || { printf 'FAIL: no ephemeral port discovered for gs-b\n'; exit 1; }
wait_http gs-b "$port_b"
add_printer gs-b "$port_b" discovery-default-b "$((18060))"
wait_count gs-b discovery-default-b 1
[[ "$port_b" != "$port_a" ]] || { printf 'FAIL: default ports collide: %s\n' "$port_a"; exit 1; }
printf 'OK: second no-PORT Ghostscript binds a distinct ephemeral port (%s)\n' "$port_b"

# --- coexistence on the shared host network ------------------------------

dups="$(host_ads | uniq -d)"
[[ -z "$dups" ]] || { printf 'FAIL: duplicate DNS-SD advertisement on host networking: %s\n' "$dups"; exit 1; }
printf 'OK: distinct ephemeral ports and no competing advertisement across no-PORT instances\n'

# --- coexistence with another rootless app, when its image is built ------

for app in gutenprint-printer-app hplip-printer-app ps-printer-app; do
  if podman image inspect "ghcr.io/projectbluefin/${app}:build" >/dev/null 2>&1; then
    podman run -d --name probe --network host \
      -v "$state_other:/var/lib/${app}:Z" "ghcr.io/projectbluefin/${app}:build" >/dev/null
    sleep 5
    dups="$(host_ads | uniq -d)"
    [[ -z "$dups" ]] || { printf 'FAIL: %s collides with a Ghostscript advertisement: %s\n' "$app" "$dups"; exit 1; }
    printf 'OK: %s coexists with no-PORT Ghostscript without DNS-SD collision\n' "$app"
    break
  fi
done

printf 'NOTE: real USB interface claiming and GNOME print dialog behavior are unverified here; both require physical hardware and a desktop session.\n'
printf 'OK: default-port Ghostscript discovery does not compete for one synthetic printer\n'
