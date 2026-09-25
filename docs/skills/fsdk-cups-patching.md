---
name: fsdk-cups-patching
description: Use when changing the fsdk-containers junction, CUPS or cups-filters build configuration, Ghostscript compression ownership, CUPS backends, filters, or print-stack source patches for the OCI appliance.
metadata:
  context7-sources:
    - /apache/buildstream
---

# FSDK CUPS Patching

## When to Use

- Changing the pinned fsdk-containers junction, which also pins FSDK and the shared printing base.
- Changing CUPS TLS configuration, backends, filters, or source patches.
- Diagnosing CUPS graph or source-staging failures in the OCI build.
- Changing FSDK-owned cups-filters or Ghostscript behavior required by a legacy driver.

## When NOT to Use

- Snap-only dependency changes unrelated to CUPS.
- Printer Application behavior implemented in `ghostscript-printer-app.c`.
- Legacy driver elements that do not alter CUPS.

## Core Process

CUPS, cups-filters, libcupsfilters, libppd, Ghostscript, mutool, the nonroot `avahi-printing` daemon, PAPPL and pappl-retrofit come from `fsdk-containers.bst:printing/base.bst`. Their FSDK project patch (`patches/freedesktop-sdk/0002-printing-*.patch`) and source patch queues (`patches/printing/`) live in [fsdk-containers](https://github.com/projectbluefin/fsdk-containers); change them there, then bump `elements/fsdk-containers.bst`. Follow its consumer contract (`docs/skills/printing-base.md`): no patches, overrides or options besides `arch` on the junction, FSDK only through `fsdk-containers.bst:freedesktop-sdk.bst:...`, and a final compose that excludes `devel`, `debug`, `doc` and `static-blocklist`.

1. Treat `snap/snapcraft.yaml`, the FSDK elements, and root `patches/` as the current behavior contract; consult Git history only when auditing the retired OCI implementation.
2. Keep one CUPS artifact owner. fsdk-containers' printing base owns CUPS so its reverse dependencies build against the same libraries. A second FSDK junction would be a second CUPS.
3. `patches/cups/` stays in this repository only for the Snap build; the OCI build applies fsdk-containers' `patches/printing/cups/`. Keep the two copies identical. The `patch_queue` plugin applies every file in its directory, so unrelated patches must stay elsewhere.
4. fsdk-containers stages `patches/printing/cups/` into its FSDK junction with a `local` source and applies `patches/freedesktop-sdk/` at the junction project level; that project patch injects the nested CUPS source `patch_queue` and adjusts FSDK's CUPS configuration.
5. Do not use `config.overrides` for small CUPS patches or feature switches. BuildStream documents overrides as complete downstream ownership that stops inheriting upstream element updates.
6. Do not stage a second CUPS implementation. Duplicate `libcups.so*` ownership creates an artifact overlap and can compile reverse dependencies against a different library than the application receives.
7. Apply patches from the source root when their paths start with `a/backend/` and use `-p1`.
8. Cross-junction source checkouts nest under `<junction>/<element-path>/`; the CUPS probe therefore checks `fsdk-containers/freedesktop-sdk/components-_private-cups-base/`, not the checkout root.
9. Match FSDK's multiarch install layout for every repository-built library. Define `gcc-triplet`, `lib`, and `libdir` in the root project and pass `--libdir=%{libdir}` to Autotools; FSDK's `pkg-config` searches `/usr/lib/<gcc-triplet>/pkgconfig`, not `/usr/lib/pkgconfig`.
10. Do not `chown` high numeric runtime IDs inside the BuildStream sandbox; user-namespace mappings can reject them with `EINVAL`. After composition, reapply writable directory modes in the final OCI layer. Remove inherited `/run` service directories and let the numeric runtime user recreate them so ownership checks observe the actual user.
11. Avahi's `--no-drop-root` still resolves its compiled `AVAHI_USER`/`AVAHI_GROUP` and requires its runtime directory to have those numeric IDs. fsdk-containers builds it as `components/avahi-printing.bst` with `--with-avahi-user=nonroot --with-avahi-group=nonroot`; never stage `components/avahi.bst` next to it, since both install `avahi-daemon`, and never create a second passwd/group name with UID/GID `65532`. Remove D-Bus's `<user>` directive so it does not attempt a second privilege drop, and patch Avahi policy at `/etc/dbus-1/system.d/avahi-dbus.conf`.
12. Install repository-built CUPS filters into `/usr/lib/cups/filter`. The appliance exposes `/usr/lib/ghostscript-printer-app` as a symlink to `/usr/lib/cups`; creating a real `/usr/lib/ghostscript-printer-app/filter` directory in another artifact conflicts with that symlink during composition.
13. fsdk-containers stages component-specific source patches in separate junction directories. `patches/printing/cups-filters/` is injected into FSDK's existing `components/cups-filters.bst`; never mix it with CUPS or libcupsfilters patches.
14. Keep Ghostscript on its bundled zlib. FSDK's zlib-ng compatibility library corrupts compiled Ghostscript ROMFS reads when a full-size IJS page lazily loads an ICC profile; the failure appears as `free(): invalid size` from `s_block_read_process`. A default Letter pxljr conversion is the regression probe.
15. Treat filter executables by format: use `ldd` only for ELF binaries, and resolve script shebangs plus every invoked command separately. Generated pyppd archives use `#!/usr/bin/env python3`, so each owning element declares the Python runtime even when another aggregate currently supplies it.
16. Keep `just fetch` on `--ignore-project-source-remotes --source-remote https://cache.projectbluefin.io:11001` rather than re-enabling the GBM source cache, which can stall with `DEADLINE_EXCEEDED`. BuildStream still falls back to upstream source URLs on a cache miss. If the source is absent and a runner cannot reach the upstream mirror, diagnose the pinned source and remote coverage; retries alone cannot repair a persistent missing cache entry or unreachable host. Use a separately verified FSDK update or repair the source mirror at its owner, never silently substitute an unverified tarball.
17. CUPS's USB backend executable is not proof of functional USB printing: without `libusb-1.0` at configure time, CUPS builds a stub and omits `org.cups.usb-quirks`. Add `components/libusb.bst` as a build dependency to FSDK's private CUPS base, configure with `--enable-libusb`, and add it as a runtime dependency of `cups-daemon-only.bst`. The same CUPS owner then installs `/usr/share/cups/usb/org.cups.usb-quirks`; seed that file into the persistent `USB_QUIRK_DIR/usb` only on first boot, preserving user edits across restarts.
18. In libcupsfilters 2.2.1, `cfPDFPagesFP()` copies PDF input into a buffered `FILE *` and immediately opens the pathname with PDFio before flushing the buffer. PDFio sees a truncated xref/trailer and reports `Missing Root object`; `gstoraster` then fails with `Unexpected page count`. Backport [OpenPrinting/libcupsfilters@e14bad4](https://github.com/OpenPrinting/libcupsfilters/commit/e14bad406189a66bdeb40131112944bfb58ee0cc) through fsdk-containers' `patches/printing/libcupsfilters/`, not in application-specific filter code. Test a multi-KB PDF through the real `gstoraster` wrapper; a PostScript-only socket print never enters the broken PDF page-count path.
19. HPLIP's valid `MediaType=Automatic` PPD value is `-1`. libcupsfilters 2.2.1 serializes its CUPS raster-header value as unsigned `4294967295` in `cfFilterGhostscript()`, beyond Ghostscript's signed integer parameter range; the print fails with `Error setting cupsMediaType`. Backport the `cupsMediaType` hunk of [OpenPrinting/libcupsfilters@318cd5b](https://github.com/OpenPrinting/libcupsfilters/commit/318cd5b581d4261700add229ad23513cd30a0275) to serialize the original signed `-1`. Verify a default-options HPLIP PDF test-page job through hpcups and the real socket backend; selecting `Plain` only in the test would hide the regression.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| “The public `cups.bst` exists, so it contains every needed tool.” | It is a filter for libraries and licenses; inspect the staged payload before relying on it. |
| “A local CUPS element is simpler.” | It overlaps FSDK's CUPS and breaks the single-owner dependency graph. |
| “`config.overrides` is cleaner than two patch levels.” | It replaces the entire upstream element and forfeits inherited maintenance for a small downstream delta. |
| “All patches can share one directory.” | `patch_queue` applies every file in its directory; an unrelated c2esp patch will fail against CUPS. |
| “`bst show` proves source patches apply.” | It proves graph and source-path resolution; source checkout proves the nested patches apply to CUPS. |

## Red Flags

- More than one element installs `libcups.so*`.
- An application element depends directly on `components/_private/cups-base.bst`.
- The FSDK project patch embeds a second copy of a CUPS source patch.
- `cups-libs` or `cups-license` disappears from the FSDK CUPS split rules.
- A manifest invokes a patch after changing into a subdirectory incompatible with its `a/...` paths.
- An fsdk-containers junction update lands without rerunning the patch-chain verification.
- A second FSDK junction in this project, or `components/avahi.bst` in the image graph.
- Repository-built `.pc` files under `/usr/lib/pkgconfig` while the FSDK build sandbox searches only `/usr/lib/<gcc-triplet>/pkgconfig` and `/usr/share/pkgconfig`.
- `chown 65532:65532` in a BuildStream build command; unprivileged sandbox UID maps do not guarantee that numeric owner exists.
- Pre-creating Avahi's runtime directory as root; Avahi verifies it belongs to its compiled service UID even with `--no-drop-root`.
- Giving `avahi` and `nonroot` the same UID/GID; numeric-to-name lookup becomes ambiguous and can hide a broken OCI identity.
- Editing `/usr/share/dbus-1/system.d/avahi-dbus.conf`; the FSDK runtime installs that policy under `/etc/dbus-1/system.d/`.
- Installing a driver artifact beneath `/usr/lib/ghostscript-printer-app/filter`; the canonical artifact path is `/usr/lib/cups/filter`, reached at runtime through the application symlink.
- Running `ldd` on shell or Python filters; `not a dynamic executable` is not an ELF closure result.
- Letting aggregate composition mask an undeclared pyppd Python runtime or shell-filter command dependency.
- Building Ghostscript against FSDK's zlib-ng compatibility library when the appliance ships an IJS driver.
- Removing the explicit Bluefin source-cache flags to work around an unrelated upstream mirror failure; this reintroduces the GBM source-cache timeout.
- Shipping an executable CUPS `usb` backend without a `libusb-1.0.so` link or the packaged default USB quirks table.

## Verification

- [ ] `just verify-cups-patch-chain` exits successfully.
- [ ] The CUPS-dependent Ghostscript element resolves.
- [ ] The graph contains exactly one FSDK private CUPS base.
- [ ] The staged CUPS source contains the DNS-SD and `USB_QUIRK_DIR` changes.
- [ ] The CUPS base still exposes `cups-libs` and `cups-license`.
- [ ] The Snap and FSDK CUPS source versions both accept the canonical patches.
- [ ] Source fetch succeeds on both native CI runners for the pinned FSDK release before claiming a downstream driver build is verified.
- [ ] The image has a libusb-linked CUPS USB backend and its nonempty default quirks table; an empty state volume receives the table, and a restart preserves edited quirks.
- [ ] A multi-KB PDF passes `gstoraster` with the real packaged PPD and emits a CUPS raster header; a real IPP PDF job also reaches the socket sink.
- [ ] An HPLIP PPD with default `MediaType=Automatic` prints through Ghostscript, hpcups and the CUPS socket without a media-type rangecheck.
- [ ] Repository-built libraries install their `.pc` files in FSDK's multiarch pkg-config directory and are discoverable from a dependent element's build sandbox.
- [ ] The exported image runs with the numeric UID/GID, creates runtime directories, and reaches application readiness.
- [ ] TERM yields signal exit status `143`, not Podman's SIGKILL timeout status `137`; killing a required child makes the container exit nonzero.
