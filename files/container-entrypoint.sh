#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PORT:-}" && ! "$PORT" =~ ^[0-9]+$ ]]; then
  printf 'PORT must be numeric\n' >&2
  exit 64
fi

state_dir=/var/lib/ghostscript-printer-app
mkdir -p "$state_dir/ppd" "$state_dir/spool" "$state_dir/usb" "$state_dir/cups/ssl" "$state_dir/pnm2ppa" "$state_dir/hplip/run" "$state_dir/foo2zjs" "$state_dir/m2300w" /run/dbus /run/avahi-daemon /run/ghostscript-printer-app
if [[ ! -e "$state_dir/cups/snmp.conf" ]]; then
  cp /etc/cups/snmp.conf "$state_dir/cups/snmp.conf"
fi
if [[ ! -e "$state_dir/pnm2ppa/pnm2ppa.conf" ]]; then
  cp /usr/share/ghostscript-printer-app/pnm2ppa.conf "$state_dir/pnm2ppa/pnm2ppa.conf"
fi
if [[ ! -e "$state_dir/hplip/hplip.conf" ]]; then
  cp /usr/share/ghostscript-printer-app/defaults/hplip/hplip.conf "$state_dir/hplip/hplip.conf"
fi
cp -a --update=none /usr/share/ghostscript-printer-app/defaults/foo2zjs/. "$state_dir/foo2zjs/"
cp -a --update=none /usr/share/ghostscript-printer-app/defaults/m2300w/. "$state_dir/m2300w/"
if [[ -d /usr/share/cups/usb ]]; then
  cp -a --update=none /usr/share/cups/usb/. "$state_dir/usb/"
fi

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
