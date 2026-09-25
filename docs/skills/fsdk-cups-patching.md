---
name: fsdk-cups-patching
description: Use when changing the freedesktop-sdk junction, CUPS or cups-filters build configuration, Ghostscript compression ownership, CUPS backends, filters, or print-stack source patches for the OCI appliance.
metadata:
  context7-sources:
    - /apache/buildstream
---

# FSDK CUPS Patching

## When to Use

- Changing the pinned freedesktop-sdk junction.
- Changing CUPS TLS configuration, backends, filters, or source patches.
- Diagnosing CUPS graph or source-staging failures in the OCI build.
- Changing FSDK-owned cups-filters or Ghostscript behavior required by a legacy driver.

## When NOT to Use

- Snap-only dependency changes unrelated to CUPS.
- Printer Application behavior implemented in `ghostscript-printer-app.c`.
- Legacy driver elements that do not alter CUPS.

## Core Process

1. Treat `snap/snapcraft.yaml`, the FSDK elements, and root `patches/` as the current behavior contract; consult Git history only when auditing the retired OCI implementation.
2. Keep one CUPS artifact owner. The FSDK junction must continue to own CUPS so its reverse dependencies build against the same libraries.
3. Keep CUPS-only source patches under `patches/cups/`. The `patch_queue` plugin applies every file in its directory, so unrelated patches must stay elsewhere.
4. Stage `patches/cups/` into the FSDK junction with a `local` source. Apply `patches/freedesktop-sdk/` at the junction project level; that project patch injects the nested CUPS source `patch_queue` and adjusts FSDK's CUPS configuration.
5. Do not use `config.overrides` for small CUPS patches or feature switches. BuildStream documents overrides as complete downstream ownership that stops inheriting upstream element updates.
6. Do not stage a second CUPS implementation. Duplicate `libcups.so*` ownership creates an artifact overlap and can compile reverse dependencies against a different library than the application receives.
7. Shared CUPS patches remain under `patches/cups/` for both Snap and FSDK. Apply patches from the source root when their paths start with `a/backend/` and use `-p1`.
8. Cross-junction source checkouts nest under `<junction>/<element-path>/`; the CUPS probe therefore checks `freedesktop-sdk/components-_private-cups-base/`, not the checkout root.
9. Match FSDK's multiarch install layout for every repository-built library. Define `gcc-triplet`, `lib`, and `libdir` in the root project and pass `--libdir=%{libdir}` to Autotools; FSDK's `pkg-config` searches `/usr/lib/<gcc-triplet>/pkgconfig`, not `/usr/lib/pkgconfig`.
10. Do not `chown` high numeric runtime IDs inside the BuildStream sandbox; user-namespace mappings can reject them with `EINVAL`. After composition, reapply writable directory modes in the final OCI layer. Remove inherited `/run` service directories and let the numeric runtime user recreate them so ownership checks observe the actual user.
11. Avahi's `--no-drop-root` still resolves its compiled `AVAHI_USER`/`AVAHI_GROUP` and requires its runtime directory to have those numeric IDs. Configure FSDK's Avahi build with `--with-avahi-user=nonroot --with-avahi-group=nonroot`; never create a second passwd/group name with UID/GID `65532`. Remove D-Bus's `<user>` directive so it does not attempt a second privilege drop, and patch Avahi policy at `/etc/dbus-1/system.d/avahi-dbus.conf`.
12. Install repository-built CUPS filters into `/usr/lib/cups/filter`. The appliance exposes `/usr/lib/ghostscript-printer-app` as a symlink to `/usr/lib/cups`; creating a real `/usr/lib/ghostscript-printer-app/filter` directory in another artifact conflicts with that symlink during composition.
13. Stage component-specific source patches in separate junction directories. `patches/cups-filters/` is injected into FSDK's existing `components/cups-filters.bst`; never mix it with CUPS or libcupsfilters patches.
14. Keep Ghostscript on its bundled zlib. FSDK's zlib-ng compatibility library corrupts compiled Ghostscript ROMFS reads when a full-size IJS page lazily loads an ICC profile; the failure appears as `free(): invalid size` from `s_block_read_process`. A default Letter pxljr conversion is the regression probe.
15. Treat filter executables by format: use `ldd` only for ELF binaries, and resolve script shebangs plus every invoked command separately. Generated pyppd archives use `#!/usr/bin/env python3`, so each owning element declares the Python runtime even when another aggregate currently supplies it.
16. Maintain verified source-cache failover in the FSDK junction. Apply patches in `patches/freedesktop-sdk/` to configure trusted Project Bluefin (`https://cache.projectbluefin.io:11001`) and GNOME Build Meta (`https://gbm.gnome.org:11003`) CAS servers in the junction's `project.conf`. This prevents `DEADLINE_EXCEEDED` hangs on missing FSDK blobs and ensures fallback to authoritative pinned upstream sources.

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
- An FSDK junction update lands without rerunning the patch-chain verification.
- Repository-built `.pc` files under `/usr/lib/pkgconfig` while the FSDK build sandbox searches only `/usr/lib/<gcc-triplet>/pkgconfig` and `/usr/share/pkgconfig`.
- `chown 65532:65532` in a BuildStream build command; unprivileged sandbox UID maps do not guarantee that numeric owner exists.
- Pre-creating Avahi's runtime directory as root; Avahi verifies it belongs to its compiled service UID even with `--no-drop-root`.
- Giving `avahi` and `nonroot` the same UID/GID; numeric-to-name lookup becomes ambiguous and can hide a broken OCI identity.
- Editing `/usr/share/dbus-1/system.d/avahi-dbus.conf`; the FSDK runtime installs that policy under `/etc/dbus-1/system.d/`.
- Installing a driver artifact beneath `/usr/lib/ghostscript-printer-app/filter`; the canonical artifact path is `/usr/lib/cups/filter`, reached at runtime through the application symlink.
- Running `ldd` on shell or Python filters; `not a dynamic executable` is not an ELF closure result.
- Letting aggregate composition mask an undeclared pyppd Python runtime or shell-filter command dependency.
- Building Ghostscript against FSDK's zlib-ng compatibility library when the appliance ships an IJS driver.

## Verification

- [ ] `just verify-cups-patch-chain` exits successfully.
- [ ] The CUPS-dependent Ghostscript element resolves.
- [ ] The graph contains exactly one FSDK private CUPS base.
- [ ] The staged CUPS source contains the DNS-SD and `USB_QUIRK_DIR` changes.
- [ ] The CUPS base still exposes `cups-libs` and `cups-license`.
- [ ] The Snap and FSDK CUPS source versions both accept the canonical patches.
- [ ] Repository-built libraries install their `.pc` files in FSDK's multiarch pkg-config directory and are discoverable from a dependent element's build sandbox.
- [ ] The exported image runs with the numeric UID/GID, creates runtime directories, and reaches application readiness.
- [ ] TERM yields signal exit status `143`, not Podman's SIGKILL timeout status `137`; killing a required child makes the container exit nonzero.
