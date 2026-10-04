# FSDK source updates

`update-base.yml` is the sole proposal owner. It tracks the shared
`fsdk-containers` main branch, rather than filtering FSDK releases to a local
`26.08*` selector. A later compatible FSDK line enters this appliance when the
shared base adopts it. Do not add a second FSDK junction, override Ghostscript's
source, or build a second Ghostscript artifact here. The shared base owns its
FSDK selector and printing patches; requests to adopt a newer line belong in
[fsdk-containers](https://github.com/projectbluefin/fsdk-containers).

For each changed base commit, the updater reads both nested source pins with
BuildStream's `show --format '%{source-info}'`, as the appliance parity gate
already does. Exact tagged releases are required; an unrecognized source format
or an offset from a release fails before proposal credentials are minted.
`VERSION`, the README invocation, IJS's matching Ghostscript source, the OCI
FSDK labels, and the rootless USB Quadlet example are updated together. An unchanged Ghostscript version increments
the packaging revision, including a shared-base-only change; a new Ghostscript
version resets it to `-1`. Each daily proposal starts from `testing`, so rerunning
an unmerged proposal does not repeatedly increment its revision. The OCI
application label and binary already read `VERSION`.

The proposal reports the selected FSDK/Ghostscript sources alongside the newest
stable upstream tags observed at update time. There are two distinct kinds of
lag: the shared base may follow an older FSDK release, and even the newest FSDK
may package an older Ghostscript than Artifex. A tag lookup failure is reported
as unknown, never as zero lag. These observations do not change source pins.
In particular, tag discovery
does not satisfy adoption of a newer FSDK line: the shared base's `26.08*`
selector remains unchanged. Issue #14's release-line acceptance criterion
remains open for a maintainer decision or a companion shared-base change.
Future-line compatibility is decided by patch-chain, fetch and full real-image
verification, not by version ordering alone.

For changed candidates, the updater first restores the x86_64 BuildStream
cache using the same keys as CI and seeds the printing base from a
cosign-verified bundle for its exact artifact key. Cache misses or unavailable
bundles fall back to a local build, as in CI. The restore and seed step logs
record the initial cache state; these are separate from FSDK remote CAS pulls.

Before minting the proposal token, the updater runs `just verify-cups-patch-chain`,
`just fetch` and `just verify`. Its `fsdk-update-evidence` workflow artifact retains
the source report and complete logs, even on failure. Inspect BuildStream's
initial cached elements and its **Pull** and **Build** queue session summaries:
successful remote artifact pulls are measured remote cache hits; locally cached
elements and successful source downloads are separate quantities. Report the
run URL, architecture, base commit, initial local cache state, successful pulls
and local builds with any cache-reuse claim. Repeated `just build` calls later in
verification normally hit local cache and must not be counted as remote hits.
A patched Ghostscript is not assumed to reuse FSDK's unpatched artifact key.
No numeric hit rate is claimed without a completed run and its logs.

The updater verifies native x86_64 before proposing; the merge queue verifies
both native architectures before landing on `testing`, and promotion separately
verifies `stable`. Real print-to-socket-sink output is tested; physical paper
output remains unverified without hardware.

Local deterministic metadata checks: `just verify-fsdk-metadata`. These exercise
both revision transitions and rejection without partial writes; they do not
substitute for real OCI verification.
