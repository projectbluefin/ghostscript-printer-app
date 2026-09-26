#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PORT:-}" && ! "$PORT" =~ ^[0-9]+$ ]]; then
  printf 'PORT must be numeric\n' >&2
  exit 64
fi

# Web administration knobs (ChairLift ADR-0016). PAPPL serves IPP and the web
# interface on one listener, so on host networking the only boundary around the
# admin pages is authorization. Every value is validated here and the container
# exits non-zero rather than start with a setting the server would silently
# ignore or weaken: pappl-retrofit drops unknown server-options without a
# diagnostic, and PAPPL skips the group check for an admin-group it cannot
# resolve. Exit 64 marks a malformed value; exit 78 marks a value this image
# cannot honour.
usage_error() {
  printf '%s\n' "$1" >&2
  exit 64
}
config_error() {
  printf '%s\n' "$1" >&2
  exit 78
}

# PAPPL server options this appliance forwards. Everything else pappl-retrofit
# understands either weakens the appliance (no-tls, none) or is already the
# default (web-log, web-network, web-security), so it is not accepted.
allowed_server_options=(no-web-interface)
server_options=()
if [[ -n "${PRINTER_APP_SERVER_OPTIONS:-}" ]]; then
  [[ "$PRINTER_APP_SERVER_OPTIONS" =~ ^[a-z-]+(,[a-z-]+)*$ ]] \
    || usage_error 'PRINTER_APP_SERVER_OPTIONS must be a comma-separated list of PAPPL server options'
  IFS=, read -r -a requested_server_options <<< "$PRINTER_APP_SERVER_OPTIONS"
  for option in "${requested_server_options[@]}"; do
    allowed=0
    for candidate in "${allowed_server_options[@]}"; do
      [[ "$option" == "$candidate" ]] && allowed=1
    done
    ((allowed)) || usage_error "PRINTER_APP_SERVER_OPTIONS contains unsupported option '${option}'; supported: ${allowed_server_options[*]}"
    server_options+=("$option")
  done
fi

# Syntax first (exit 64), then what this image can honour (exit 78), so a
# malformed value is diagnosed the same way on any host.
if [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]]; then
  [[ "$PRINTER_APP_AUTH_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
    || usage_error 'PRINTER_APP_AUTH_SERVICE must be a PAM service name: letters, digits, "_", "." or "-", not starting with "." or "-"'
fi
if [[ -n "${PRINTER_APP_ADMIN_GROUP:-}" ]]; then
  [[ "$PRINTER_APP_ADMIN_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] \
    || usage_error 'PRINTER_APP_ADMIN_GROUP must be a group name: letters, digits, "_", "." or "-", starting with a letter or "_"'
fi

# A PAM service name is a file under /etc/pam.d. The shared printing base builds
# PAPPL with --disable-libpam and ships no PAM stack, so today no service can
# satisfy this check and no-web-interface is the only supported way to close
# the web admin surface. Forwarding the option anyway would lock every
# administrator out with 401 rather than authenticate anyone.
if [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]]; then
  [[ -f "/etc/pam.d/$PRINTER_APP_AUTH_SERVICE" ]] \
    || config_error "PRINTER_APP_AUTH_SERVICE=${PRINTER_APP_AUTH_SERVICE} names a PAM service this image does not ship (/etc/pam.d/${PRINTER_APP_AUTH_SERVICE} is missing); set PRINTER_APP_SERVER_OPTIONS=no-web-interface to disable web administration instead"
fi

# admin-group only restricts who may administer once auth-service authenticates
# them, and PAPPL treats an unresolvable group as "no group check", so both an
# unset auth service and an unknown group would start unauthenticated.
if [[ -n "${PRINTER_APP_ADMIN_GROUP:-}" ]]; then
  [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]] \
    || config_error 'PRINTER_APP_ADMIN_GROUP requires PRINTER_APP_AUTH_SERVICE; a group cannot be enforced without authentication'
  group_known=0
  while IFS=: read -r group_name _; do
    [[ "$group_name" == "$PRINTER_APP_ADMIN_GROUP" ]] && group_known=1
  done < /etc/group
  ((group_known)) \
    || config_error "PRINTER_APP_ADMIN_GROUP=${PRINTER_APP_ADMIN_GROUP} is not a group in this image's /etc/group; PAPPL would skip the group check and admit every authenticated user"
fi

# Keep newly created keys, jobs, and application state private to the runtime user.
umask 077

state_dir=/var/lib/ghostscript-printer-app
state_permission_error() {
  printf 'Persistent state is not writable: %s; mount a writable volume with permissions for UID:GID %s:%s\n' "$1" "$(id -u)" "$(id -g)" >&2
  exit 73
}

# mkdir alone succeeds for existing directories even on a read-only mount.
# Probe each mutable directory before starting any service, without touching
# existing settings. Include intermediate directories used by driver payloads.
for directory in "$state_dir" "$state_dir/ppd" "$state_dir/spool" \
  "$state_dir/usb" "$state_dir/cups" "$state_dir/cups/ssl" \
  "$state_dir/pnm2ppa" "$state_dir/hplip" "$state_dir/hplip/run" \
  "$state_dir/foo2zjs" "$state_dir/m2300w"; do
  mkdir -p "$directory" || state_permission_error "$directory"
  probe="$(mktemp "$directory/.write-check.XXXXXXXXXX")" || state_permission_error "$directory"
  rm -- "$probe" || state_permission_error "$directory"
done

# Existing application files can have different ownership than their parent.
for file in "$state_dir/ghostscript-printer-app.state" "$state_dir/ghostscript-printer-app.log"; do
  if [[ -e "$file" || -L "$file" ]]; then
    [[ -f "$file" && -w "$file" ]] || state_permission_error "$file"
  fi
done

mkdir -p /run/dbus /run/avahi-daemon /run/ghostscript-printer-app
# Repair volumes created by older images before starting any service. Fail closed
# if the runtime user cannot secure existing private state.
# CUPS keeps a non-root server's TLS credentials in "$HOME/.cups/ssl", and HOME is
# the state directory, so that is where the appliance's private keys live.
mkdir -p "$state_dir/.cups/ssl"
chmod 0700 "$state_dir/cups" "$state_dir/cups/ssl" "$state_dir/.cups" "$state_dir/.cups/ssl" "$state_dir/spool"
chmod -R u+rwX,go-rwx "$state_dir/cups/ssl" "$state_dir/.cups/ssl" "$state_dir/spool"

if [[ ! -e "$state_dir/cups/snmp.conf" ]]; then
  cp /etc/cups/snmp.conf "$state_dir/cups/snmp.conf"
fi
if [[ ! -e "$state_dir/usb/org.cups.usb-quirks" && ! -L "$state_dir/usb/org.cups.usb-quirks" ]]; then
  cp /usr/share/cups/usb/org.cups.usb-quirks "$state_dir/usb/org.cups.usb-quirks"
fi
if [[ ! -e "$state_dir/pnm2ppa/pnm2ppa.conf" ]]; then
  cp /usr/share/ghostscript-printer-app/pnm2ppa.conf "$state_dir/pnm2ppa/pnm2ppa.conf"
fi
if [[ ! -e "$state_dir/hplip/hplip.conf" ]]; then
  cp /usr/share/ghostscript-printer-app/defaults/hplip/hplip.conf "$state_dir/hplip/hplip.conf"
fi
cp -a --update=none /usr/share/ghostscript-printer-app/defaults/foo2zjs/. "$state_dir/foo2zjs/"
cp -a --update=none /usr/share/ghostscript-printer-app/defaults/m2300w/. "$state_dir/m2300w/"

export BACKEND_DIR=/usr/lib/ghostscript-printer-app/backend
export CUPS_SERVERBIN=/usr/lib/ghostscript-printer-app
export CUPS_SERVERROOT="$state_dir/cups"
export FILTER_DIR=/usr/lib/ghostscript-printer-app/filter
export PATH="$FILTER_DIR:$PATH"
export PPDC_DATADIR=/usr/share/ppdc
export PPD_PATHS="${PPD_PATHS:-/usr/share/ppd/:$state_dir/ppd/}"
export SPOOL_DIR="$state_dir/spool"
export STATE_DIR="$state_dir"
export STATE_FILE="$state_dir/ghostscript-printer-app.state"
export TESTPAGE_DIR=/usr/share/ghostscript-printer-app
export TMPDIR=/tmp
export USB_QUIRK_DIR="$state_dir"

children=()
stop_children() {
  local index pid
  for ((index = ${#children[@]} - 1; index >= 0; index--)); do
    pid="${children[index]}"
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait "${children[@]}" 2>/dev/null || true
}
handle_signal() {
  trap - TERM INT EXIT
  stop_children
  exit 143
}
trap handle_signal TERM INT
trap stop_children EXIT

dbus-daemon --system --nofork --nopidfile &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -S /run/dbus/system_bus_socket ]] && break
  sleep 0.1
done
[[ -S /run/dbus/system_bus_socket ]]

avahi-daemon --no-drop-root --no-chroot &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -f /run/avahi-daemon/pid ]] && break
  sleep 0.1
done
[[ -f /run/avahi-daemon/pid ]]

args=(-o "log-file=$state_dir/ghostscript-printer-app.log")
if [[ -n "${PORT:-}" ]]; then
  args+=(-o "server-port=$PORT")
fi
if ((${#server_options[@]} > 0)); then
  args+=(-o "server-options=$(IFS=,; printf '%s' "${server_options[*]}")")
fi
if [[ -n "${PRINTER_APP_AUTH_SERVICE:-}" ]]; then
  args+=(-o "auth-service=$PRINTER_APP_AUTH_SERVICE")
fi
if [[ -n "${PRINTER_APP_ADMIN_GROUP:-}" ]]; then
  args+=(-o "admin-group=$PRINTER_APP_ADMIN_GROUP")
fi
web_interface_disabled=0
for option in "${server_options[@]}"; do
  [[ "$option" == no-web-interface ]] && web_interface_disabled=1
done
if [[ -z "${PRINTER_APP_AUTH_SERVICE:-}" ]] && ((!web_interface_disabled)); then
  printf 'NOTICE: web administration is reachable by every client that can reach the IPP port; set PRINTER_APP_SERVER_OPTIONS=no-web-interface to disable it\n' >&2
fi
ghostscript-printer-app "${args[@]}" server &
children+=("$!")

if wait -n "${children[@]}"; then
  status=1
else
  status=$?
fi
stop_children
trap - TERM INT EXIT
exit "$status"
