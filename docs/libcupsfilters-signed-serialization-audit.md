# Signed CUPS raster parameter serialization audit

Issue: [#45](https://github.com/projectbluefin/ghostscript-printer-app/issues/45), child of the FSDK appliance epic (#12). This is a records-only audit: no build graph, patch, or element change was made.

## Reviewed sources

| Component | Reviewed version | Location |
| --- | --- | --- |
| Shared libcupsfilters pin | 2.2.1-0-g2a00cf6aa4234e2e0ac91b9844ab8990d04c7089 (tag `2.2.1`) | FSDK `freedesktop-sdk-26.08.1-0-gb02b59ffe19a49a402f357fd5fcb1d552ebc50d7`, reached through the `fsdk-containers.bst` junction, `elements/components/libcupsfilters.bst` |
| Upstream signed-serialization commit | [OpenPrinting/libcupsfilters@318cd5b](https://github.com/OpenPrinting/libcupsfilters/commit/318cd5b581d4261700add229ad23513cd30a0275) | `cupsfilters/ghostscript.c`, `header_to_gs_args()` |
| Ghostscript raster parameter parser | [ghostpdl-10.07.1](https://github.com/ArtifexSoftware/ghostpdl/releases/tag/ghostpdl-10.07.1) (the appliance's Ghostscript pin) | `cups/gdevcups.c`, `intoption()` → `param_read_int()` |
| Filter chain caller | [OpenPrinting/pappl-retrofit](https://github.com/OpenPrinting/pappl-retrofit.git) `pappl-retrofit.h` `PR_CONVERT_*`, `PR_STREAM_*` | Sole filter-chain owner for the four retrofitted printer applications |
| Standalone gstoraster wrapper | cups-filters 2.0.1-0-g5a73330fbd0cde494d984141f9add1565aef8171, `filter/gstoraster.c` | FSDK `elements/components/cups-filters.bst` |

## Failure mechanism

Ghostscript's `gdevcups` reads every numeric CUPS raster parameter with `param_read_int()` through the `intoption()` macro. A serialized value at or above 2^31 (for example `4294967295`, the unsigned rendering of `-1`) fails the signed-integer read with `gs_error_rangecheck` ("ERROR: Error setting cupsMediaType" and peers), aborting the job. Printing the same 32-bit pattern with `%d` parses as a negative `int` and lands in the raster header bit-identically, so switching `%u` to `%d` can only change behavior for values that would otherwise fail — never for valid non-negative values. The shared fsdk-containers printing base applies that change to the `cupsMediaType` site only (first carried here by PR #44).

## Inventory of the remaining `%u` sites in cfFilterGhostscript 2.2.1

All remaining sites are in `header_to_gs_args()` and are guarded by `if (field)`, so a zero field is never serialized. The value producers are all in `cfRasterPrepareHeader()` (`cupsfilters/raster.c` at 2.2.1):

| Parameter | Value producer in 2.2.1 | Valid negative sentinel possible? |
| --- | --- | --- |
| `AdvanceDistance` | Hard-coded `0` ("TODO - Support") | No; never serialized |
| `AdvanceMedia` | Hard-coded `CUPS_ADVANCE_NONE` (0) | No; never serialized |
| `CutMedia` | Hard-coded `CUPS_ADVANCE_NONE`-style zero (no option source) | No; never serialized |
| `Jog` | No producer; remains 0 from `memset` | No; never serialized |
| `LeadingEdge` | `CUPS_EDGE_TOP` (0) / `CUPS_EDGE_RIGHT` (1) from options | No; enum 0..1 |
| `MediaPosition` | PWG `media-source`/`InputSlot` mapping to 0..49 | No; enum 0..49 |
| `MediaWeight` | `atol()` of `media-weight`/`media-weight-metric` options; no appliance chain or PPD option mapping supplies them, so it remains 0 | No realistic source |
| `NumCopies` | `%%PDFTOPDFNumCopies` comment written by `cfFilterPDFToPDF()`, always ≥ 1 | No |
| `Orientation` | `CUPS_ORIENT_0` (0) | No; enum 0..3 |
| `cupsCompression`, `cupsRowCount`, `cupsRowFeed`, `cupsRowStep` | Hard-coded `0` ("TODO - Support for these parameters") | No; never serialized |
| `cupsInteger[0]` | `job-impressions` option, gated `>= 0` | No |
| `cupsInteger[1]`, `cupsInteger[2]` | Duplex back-side transform (`pwg-raster-document-sheet-back` / `urf-supported` `DM2`/`DM3`/`DM4` mapping), **can be `-1`** | Yes — but the mapping runs only inside `if (pwg_raster)` |
| `cupsInteger[3..6]`, `cupsInteger[8..15]` | Hard-coded `0` ("TODO") | No; never serialized |
| `cupsInteger[7]` | `alternate-primary` option (sRGB value, ≤ 0xFFFFFF in the PWG raster stream); debug/development option only | No realistic negative source |

The single field that can legitimately hold a negative value is `cupsInteger[2]` (and `cupsInteger[1]`) from the duplex back-side transform, and only when `cfFilterGhostscript` runs with `CF_FILTER_OUT_FORMAT_PWG_RASTER` (or a CUPS-raster job carrying a `MediaClass` containing `pwg`).

## Reachability in the four appliances

`cfRasterPrepareHeader()` sets `pwg_raster` from the final output format; every filter chain the appliance can execute resolves `cfFilterGhostscript` to CUPS raster:

1. `pappl-retrofit` builds its conversion chains from hard-coded tables: `PR_CONVERT_PDF_TO_RASTER` and `PR_CONVERT_PS_TO_RASTER` pass `CF_FILTER_OUT_FORMAT_CUPS_RASTER` explicitly; the remaining `cfFilterGhostscript` call sites use `CF_FILTER_OUT_FORMAT_PDF` and `CF_FILTER_OUT_FORMAT_PDF_IMAGE`, which never reach the raster `%u` block. `cfFilterUniversal` — the only code path that can hand `cfFilterGhostscript` a `CF_FILTER_OUT_FORMAT_PWG_RASTER` parameter — is not used by pappl-retrofit.
2. The standalone `gstoraster` CUPS filter binary shipped by the junction (cups-filters 2.0.1 wrapper) passes `NULL` parameters, so `cfFilterGhostscript` derives its output format from `data->final_content_type`. Every driver payload PPD of the four appliances declares `application/vnd.cups-raster` (or a printer-language type) as the raster target — none of the legacy drivers (hpcups, rastertogutenprint, foomatic-rip, foo2*, splix, pxljr, c2esp, c2050, dymo, OKI, ptouch, m2300w, min12xxw, pnm2ppa, brlaser, cjet, fxlinuxprint) consumes PWG raster — so the format resolves to `CF_FILTER_OUT_FORMAT_CUPS_RASTER`.
3. Numeric PPD choices are irrelevant to these sites in 2.2.1: `cfRasterPrepareHeader()` implements none of the numeric PPD mappings (`TODO - Support for MediaType number`, `TODO - Support for these parameters`), so no shipped PPD option value can reach the remaining `%u` serializations. Drivers that do read numeric `cups*` PPD choices (hpcups, foomatic-rip's generated Ghostscript command lines, rastertogutenprint, the foo2* wrappers) serialize them in their own code, outside libcupsfilters' `header_to_gs_args()` and outside this patch's scope.

## Conclusion

No failure was demonstrated and none is reachable through the appliance's filter chains: after the `cupsMediaType` fix carried by the shared printing base, no remaining `%u` serialization in libcupsfilters 2.2.1 can receive a negative or automatic sentinel value in a job the four appliances can produce, because the only producer of `-1` (`cupsInteger[1]`/`cupsInteger[2]` duplex back-side transforms) is gated behind PWG-raster output that the appliances never request. Accordingly, per the acceptance criteria, no additional upstream hunks were backported and the build graph is unchanged. The observed `cupsMediaType` regression remains the only consumer-visible member of this failure class.

## Future-compatibility and re-audit triggers

- The only serialization patch, fsdk-containers `patches/printing/libcupsfilters/serialize-signed-cups-media-type.patch`, touches only the `cupsMediaType` hunk of `header_to_gs_args()`; the remaining hunks of upstream 318cd5b apply cleanly to the same function with `-p1` and can be added to that one patch file in fsdk-containers if ever needed. Because `%d` serialization is bit-identical for every value below 2^31, pre-applying them would not change behavior for valid inputs — but the evidence discipline for this repository requires an observed failure first, so they stay out.
- Re-run this audit before adopting an fsdk-containers bump (Renovate's `elements/fsdk-containers.bst` PR) that changes the libcupsfilters source ref, and additionally when:
  - an appliance chain starts invoking `cfFilterGhostscript` with PWG, Apple, or PCLm raster output formats, or a driver payload PPD targets `image/pwg-raster`;
  - upstream libcupsfilters implements the numeric `TODO` mappings for `cupsMediaType`, `cupsCompression`, `cupsRowCount`, `cupsRowFeed`, or `cupsRowStep` in `cfRasterPrepareHeader()`, which would let PPD numeric choices (including negative HPLIP- and GDI-style sentinels) reach the serialization sites directly;
  - a driver family is added whose filter consumes PWG raster or invokes `cfFilterUniversal`-built chains.
- Signed serialization of `cupsInteger[1]`/`cupsInteger[2]` is the first candidate: any duplex job over a PWG-raster Ghostscript chain with `pwg-raster-document-sheet-back` `Flipped`/`Rotated` (or URF `DM2`/`DM3`) sets them to `-1` and would reproduce the `cupsMediaType` failure mode.
