# Driver and behavior parity vs. the OpenPrinting Snap

This matrix tracks the FSDK OCI appliance's driver payload against the
upstream OpenPrinting `ghostscript-printer-app` Snap, using the Snap's own
build manifest (`snap/snapcraft.yaml`, still carried in this repository) as
the source of truth for Snap component versions. It exists so that a
version, architecture, or driver-family regression against the Snap is
visible without requiring Ghostscript itself to track the Snap version —
Ghostscript follows the reviewed FreeDesktop SDK (FSDK) pin instead, per
[ADR 0001](adr/0001-use-a-self-contained-fsdk-oci-appliance.md).

## How this stays true

- The complete advertised driver inventory is
  [`README.md#contained-printer-drivers`](../README.md#contained-printer-drivers),
  not a sample.
- `tests/appliance-parity.sh` (run by `just verify`) fails the build if any
  advertised backend, filter, driver command, or PPD-provider family named
  below is missing from the built OCI image, or if any README-advertised
  Ghostscript/Foomatic driver has no device or PPD entry. A regression in a
  named family therefore fails the full image parity gate, not just this
  document.
- Snap source versions below come from `snap/snapcraft.yaml`'s `source-tag`
  fields, still committed in this repository. OCI source versions come from
  each `elements/printer-app/*.bst` element's `ref:`/`track:`. Components
  inherited from the shared printing base (`fsdk-containers.bst:printing/base.bst`,
  junctioned at a pinned commit in `elements/fsdk-containers.bst`) or from the
  FSDK release that junction pins are marked **inherited**; their versions
  below were read from those pinned elements on 2026-09-25 and go stale with
  the next `update-base.yml` bump.
- The Snap Store's currently published revision, architectures, and OCI
  image digest are **unknown** in this document: they are not committed
  artifacts of this repository and must be read from the Snap Store listing
  and this repository's own release evidence at verification time, not
  hard-coded here where they would silently go stale.

## Version and architecture matrix

| Property | This FSDK OCI appliance | OpenPrinting Snap |
| --- | --- | --- |
| Application version | see `VERSION` at the repository root — not reproduced here because a daily `update-base.yml`/version bump would make a literal copy stale within a day | `snap/snapcraft.yaml` `version:`, currently `10.08.0-1` (checked into this repo); Snap Store listing revision is unknown here |
| Build architectures | `amd64`, `arm64` (see `tests/appliance-parity.sh` architecture cases) | `amd64`, `arm64`, `armhf`, `riscv64` (`snap/snapcraft.yaml` `architectures:`) — `armhf`/`riscv64` are not produced by this repository |
| FreeDesktop SDK pin | see the `ref:` in `elements/fsdk-containers.bst` (recorded at build time in the `io.projectbluefin.fsdk.*` labels of `elements/oci/ghostscript-printer-app.bst`) — not reproduced here for the same staleness reason | Not applicable; Snap does not use FSDK |
| OCI image digest | Produced per build; see release evidence and `org.opencontainers.image.*` labels asserted by `tests/appliance-parity.sh` | Not applicable; Snap has no OCI digest |
| Uncompressed size ceiling | 500 MiB (524,288,000 bytes), enforced by `tests/appliance-parity.sh` | Not tracked here; unknown |

## Driver/component matrix

Legend: **match** = same upstream ref; **differs** = pinned to a different
upstream version, fork, or revision; **inherited** = this repository does
not pin the component directly; it comes from the shared fsdk-containers
printing base or the FSDK release it pins, and the version shown is the one
those pinned elements resolved to when this document was last edited.

| Component | FSDK source ref | Snap source ref (`snap/snapcraft.yaml`) | Status |
| --- | --- | --- | --- |
| PAPPL | `fsdk-containers.bst:printing/pappl.bst` (shared base; see that file's `ref:` — inherited components are not reproduced here to avoid a literal that a base bump would make stale) | `pappl` part: `v1.4.12` | inherited — check the shared base's pinned ref against the Snap value above |
| pappl-retrofit | `fsdk-containers.bst:printing/pappl-retrofit.bst` (shared base, tracks `master` at a pinned commit) | `pappl-retrofit` part: unpinned `master` (no `source-tag`) | **differs** — the shared base pins a specific commit on `master`, while the Snap floats an unpinned `master` build; both track the same upstream branch, but the exact commits are not the same and cannot be compared further without re-resolving the Snap build at a point in time |
| Ghostscript (`gs` binary) | Inherited from the shared base (`fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst`); `elements/printer-app/ijs.bst` separately pins the same ghostpdl release for the IJS driver only — see those files for the current ref | `ghostscript` part: `ghostpdl-10.08.0` | **differs** — the FSDK-inherited Ghostscript has historically lagged the Snap's ghostpdl release by a minor version; check `elements/printer-app/ijs.bst` against the Snap value above, since this repository has no obligation to match the Snap version when FSDK lags (per this issue) |
| CUPS (libcups, backends, `rastertoepson`/`rastertohp`/`rastertolabel`) | Inherited from the shared base (FSDK `components/cups.bst`), with the patches under fsdk-containers `patches/printing/cups/` — see that element for the current ref | `cups` part: `v2.4.19` | inherited — check the shared base's pinned ref against the Snap value above |
| libcupsfilters | Inherited from the shared base (FSDK `components/libcupsfilters.bst`), with the patches under fsdk-containers `patches/printing/libcupsfilters/` | `libcupsfilters` part: `2.2.1` | inherited — check the shared base's pinned ref against the Snap value above |
| libppd | Inherited from the shared base (FSDK `components/libppd.bst`) | `libppd` part: `2.1.1` | inherited — check the shared base's pinned ref against the Snap value above |
| cups-filters (foomatic-rip, gstoraster, pdftops, rastertoescpx, rastertopclx) | Inherited from the shared base (FSDK `components/cups-filters.bst`), with the patches under fsdk-containers `patches/printing/cups-filters/` | `cups-filters` part: `2.0.1` | inherited — check the shared base's pinned ref against the Snap value above |
| foomatic-db (PPD/manufacturer data) | Inherited from `fsdk-containers.bst:printing/foomatic-db.bst` (FSDK `components/foomatic-db.bst`), used by `elements/printer-app/core-payload.bst` | `foomatic-db` part: `20240504` | inherited — check the shared base's pinned ref against the Snap value above |
| foomatic-db-engine (`foomatic-compiledb`) | `elements/printer-app/foomatic-db-engine.bst`: commit `e4e7b9cd` (tracks `master`) | Debian package `foomatic-db-engine` via `build-packages:`, no pinned source | unknown — different packaging model, versions not directly comparable |
| brlaser | `elements/printer-app/brlaser.bst`: `Owl-Maintain/brlaser` `v6.2.8` | `brlaser` part: `Owl-Maintain/brlaser` `v6.2.8` | match |
| SpliX | `elements/printer-app/splix.bst`: `debian/2.0.1-2` | `splix` part: `debian/2.0.1-2` | match |
| c2esp | `elements/printer-app/c2esp.bst`: `debian/27-11` | `c2esp` part: `debian/27-11` | match |
| foo2zjs | `elements/printer-app/foo2zjs.bst`: `debian/20200505dfsg0-5` | `foo2zjs` part: `debian/20200505dfsg0-5` | match |
| fxlinuxprint | `elements/printer-app/fxlinuxprint.bst`: `debian/1.1.0+ds-4` | `fxlinuxprint` part: `debian/1.1.0+ds-4` | match |
| HPIJS (from hplip.v2) | `elements/printer-app/hpijs.bst`: `debian/3.26.4+dfsg0-3` | `hplip` part: `debian/3.26.4+dfsg0-3` | match |
| m2300w | `elements/printer-app/m2300w.bst`: `debian/0.51-15` | `m2300w` part: `debian/0.51-15` | match |
| pnm2ppa | `elements/printer-app/pnm2ppa.bst`: `debian/1.13-14` | `pnm2ppa` part: `debian/1.13-14` | match |
| printer-driver-oki | `elements/printer-app/printer-driver-oki.bst`: `1.0.2` | `printer-driver-oki` part: `1.0.2` | match |
| ptouch-driver | `elements/printer-app/ptouch-driver.bst`: `debian/1.7-1` | `ptouch-driver` part: `debian/1.7-1` | match |
| pxljr | `elements/printer-app/pxljr.bst`: `debian/1.4+repack0-6` | `pxljr` part: `debian/1.4+repack0-6` | match |
| c2050 | `elements/printer-app/c2050.bst`: `debian/0.3-7` | `c2050` part: `debian/0.3-7` | match |
| cjet | `elements/printer-app/cjet.bst`: `debian/0.8.9-11` | `cjet` part: `debian/0.8.9-11` | match |
| min12xxw | `elements/printer-app/min12xxw.bst`: `debian/0.0.9-11` | `min12xxw` part: `debian/0.0.9-11` | match |
| Dymo (dymo-cups-drivers) | `elements/printer-app/dymo-cups-drivers.bst`: `debian/1.4.0-12` | `dymo-cups-drivers` part: `debian/1.4.0-12` | match |
| rastertosag-gdi | `elements/printer-app/rastertosag-gdi.bst`: `debian/0.1-8` | `rastertosag-gdi` part: `debian/0.1-8` | match |
| pyppd | `elements/printer-app/pyppd.bst`: `release-1-1-0` | `pyppd` part: `release-1-1-0` | match |
| qpdf | Not pinned separately; PDF handling comes through the inherited FSDK `cups-filters`/`libppd`/`poppler` stack | `qpdf` part: `v11.10.1` | unknown — this repository's architecture does not carry a standalone `qpdf` build, so there is no directly comparable pin |

## Keeping the version columns honest

Rather than hand-transcribing values that a daily `update-base.yml` bump or a
`VERSION` bump would make stale within a day, the rows above that come from
files subject to automated bumps (the application version, the FreeDesktop
SDK pin, and every component inherited from the shared fsdk-containers
printing base) point at the file that holds the current value instead of
repeating it. Only this repository's own directly-pinned elements
(`elements/printer-app/*.bst`, not part of the shared base) and the Snap's
committed `snap/snapcraft.yaml` values are reproduced literally, since
neither changes without a commit to this document's own repository.
`tests/appliance-parity.sh` does not check this document's prose, only the
driver/backend/PPD-provider inventory below.

## Reading this matrix

- Every driver family in this table corresponds to a family enforced by
  `tests/appliance-parity.sh`'s backend, filter, command, and PPD-provider
  checks. If a family here is renamed or dropped from the image, that gate
  fails the build before this document could go stale silently.
- "Differs" rows (Ghostscript/ghostpdl, brlaser, SpliX) are known,
  intentional or currently-unreconciled version gaps against the Snap, not
  missing drivers: the driver family itself is present and gated in both
  distributions, only the pinned upstream revision differs.
- "Inherited"/"unknown" rows are components this repository does not pin
  directly; they come from the shared fsdk-containers printing base and the
  FSDK release it pins. Their versions above are a snapshot of those pinned
  elements; re-check them after an `elements/fsdk-containers.bst` bump. They
  do not block the Ghostscript-driver parity gate.
- This document does not assert physical print output parity. See
  [`docs/oci-physical-validation.md`](oci-physical-validation.md) for what
  remains unverified without hardware.
