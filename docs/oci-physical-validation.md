# OCI physical printer validation

`just verify` proves the automated appliance contract with synthetic jobs. It does not prove USB enumeration, network discovery, printer firmware behavior, ink or toner output, media handling, or device-specific color. Record those results only after testing real hardware.

## Automated baseline

Run:

```bash
just verify
```

The x86_64 image has a 500 MiB (524,288,000-byte) uncompressed ceiling. The implementation baseline measured 444,975,225 bytes on 2026-09-16. `tests/appliance-parity.sh` measures the local image through Podman and fails above that ceiling. The gate also checks OCI metadata, payload inventory, absence of development content, interpreter policy, and every ELF dependency.

The OCI driver contract is the complete list under [Contained Printer Drivers](../README.md#contained-printer-drivers), not a sample. The FSDK image must retain every listed Ghostscript/Foomatic driver and every named external driver family. The parity gate requires each legacy Ghostscript name as either a compiled Ghostscript device or an exact Foomatic PPD entry, then separately checks all external driver, filter, backend, and PPD-provider families.

## USB printer

1. Build the exact revision under test with `just build`.
2. Connect and power on the printer. Identify its current `/dev/bus/usb/BBB/DDD`
   node with `lsusb`, then inspect `ls -l /dev/bus/usb/BBB/DDD` and `id`.
   Complete the rootless permissions setup below. Record the immutable image
   reference (use `podman image inspect` to obtain `RepoDigests` for a pulled
   image; for a local build record its image ID and source commit).
   Run the access gate with that same image before starting the appliance:

   ```bash
   image=ghcr.io/projectbluefin/ghostscript-printer-app:build
   python3 scripts/check-rootless-usb.py "$image" /dev/bus/usb/001/002
   ```

   Replace `001/002` with the printer node. A successful open is permission
   evidence only: it does not claim enumeration, interface acquisition, or output.
3. Start the appliance with host networking, persistent state, and USB access:

   ```bash
   mkdir -p .state/physical-usb
   podman unshare chown -R 65532:65532 .state/physical-usb
   podman run --rm --name ghostscript-printer-app-usb \
     --network host \
     --device /dev/bus/usb \
     --group-add keep-groups \
     -e PORT=18080 \
     -v "$PWD/.state/physical-usb:/var/lib/ghostscript-printer-app:Z" \
     ghcr.io/projectbluefin/ghostscript-printer-app:build
   ```

4. Open `http://127.0.0.1:18080`, add the discovered USB device, and select its intended driver rather than a generic substitute.
5. Print the built-in test page. Confirm that the job completes, paper and resolution match the selected options, graphics and text are complete, and the device reports no protocol or filter error.
6. Restart the same command and confirm that the printer and any edited profile or configuration remain present.

If rootless device access is denied, fix host udev/group permissions. Do not validate with a privileged container because that hides the shipping access model.

## Rootless permissions and Quadlet

The service user needs read/write permission on the selected printer node.
Prefer the distribution's printer udev rules. If these do not cover the device,
ask the host administrator for a rule scoped to its USB vendor/product IDs,
using `MODE="0660"` and a dedicated printer group. Add the service user to that
group, reload the rules and reconnect the printer, then start a new login
session (including the user systemd manager) so supplementary groups are current.
Do not use world-writable device rules. A desktop-session `uaccess` ACL alone
may not grant access to the container's mapped UID 65532; test the actual image.

[`--group-add keep-groups`](https://docs.podman.io/en/latest/markdown/podman-run.1.html)
retains host supplementary groups and requires the **crun** OCI runtime. Confirm
`podman info` reports rootless operation and crun; configure that runtime before
using either the CLI or Quadlet example. Device mapping does not grant host
permissions. If group permissions are correct but access still fails on SELinux,
have the administrator inspect audit denials and approve an appropriate host
policy. Do not disable labeling or retry with root or a privileged container.

The access gate opens only the selected printer node and immediately closes it;
it sends no USB commands. It fails on a missing node, access denial, rootful
Podman, or container startup failure. Re-run it after reconnecting: USB bus/device
numbers may change. The mapping exposes the USB bus, so host permissions must
also restrict unrelated devices. Restart the appliance after a reconnect if the
new node is not visible in the container.

For a user service, install the checked
[Quadlet example](../examples/ghostscript-printer-app-usb.container):

```bash
mkdir -p ~/.local/libexec ~/.config/containers/systemd
install -m 644 scripts/check-rootless-usb.py ~/.local/libexec/
cp examples/ghostscript-printer-app-usb.container ~/.config/containers/systemd/
```

The example follows the moving `stable` tag with `AutoUpdate=registry`, so
`systemctl --user enable --now podman-auto-update.timer` moves it to each new
signed publication. For a validation record, instead edit **both** `Image=` and
the image argument in `ExecStartPre=` to the same immutable
`ghcr.io/projectbluefin/ghostscript-printer-app@sha256:...` reference and drop
`AutoUpdate=`. Replace the example node in `ExecStartPre=`. Then run:

```bash
systemctl --user daemon-reload
systemctl --user start ghostscript-printer-app-usb.service
journalctl --user -u ghostscript-printer-app-usb.service
```

[`AddDevice=` and `GroupAdd=`](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
match the CLI USB options. `ExecStartPre` blocks startup when the permission
probe fails; the unit uses the same numeric identity as the probe. Python 3 is
required on the host. Use the user manager, not a system-wide root service.

`just verify-rootless-usb` validates these options and failure handling without
hardware; `just verify` includes it alongside the existing real OCI
print-to-socket-sink tests. CI records **Physical USB evidence: unavailable** in
its log and step summary. Structural checks and injected-denial tests do not
replace full OCI verification or physical printing.

## Network printer

1. Build the exact revision under test with `just build`.
2. Start the appliance without USB access:

   ```bash
   mkdir -p .state/physical-network
   podman unshare chown -R 65532:65532 .state/physical-network
   podman run --rm --name ghostscript-printer-app-network \
     --network host \
     -e PORT=18081 \
     -v "$PWD/.state/physical-network:/var/lib/ghostscript-printer-app:Z" \
     ghcr.io/projectbluefin/ghostscript-printer-app:build
   ```

3. Open `http://127.0.0.1:18081`. Confirm DNS-SD discovery when the printer advertises itself; otherwise add its `socket://`, `ipp://`, or `ipps://` address manually.
4. Select the intended driver and print the built-in test page.
5. Confirm completed job state, physical output, selected media/resolution, and absence of backend or filter errors.
6. Restart with the same state directory and repeat one print to prove persisted configuration.

## Result record

Record the image digest, commit, date, printer make/model, connection type, device URI, selected driver, tested options, restart result, and observed output. Mark USB and network separately. A synthetic CI pass must never be recorded as physical validation.


Copy this record for each physical run; use `unavailable` for anything not tested:

```text
Date / tester:
Source commit:
Image digest (or local image ID):
Host distribution / Podman / OCI runtime / SELinux mode:
Printer make / model / firmware:
Connection (USB or network) / device node / device URI:
Host node owner / group / mode / service user groups:
Rootless access gate result and diagnostic:
Selected driver / media / resolution / other options:
Discovery and job completion result:
Observed paper output (text, graphics, color, defects):
Restart / reconnect / persistence result:
Logs or output photo reference:
Physical result: pass / fail / unavailable
```
