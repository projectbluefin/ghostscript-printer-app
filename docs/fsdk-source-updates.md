# FSDK source updates

Renovate ([`renovate.json`](../renovate.json)) is the sole proposal owner. A
`git-refs` custom manager tracks `elements/fsdk-containers.bst`'s `ref:` against
the head of fsdk-containers `main`, rather than filtering FSDK releases to a
local `26.08*` selector. A later compatible FSDK line enters this appliance when
the shared base adopts it. Do not add a second FSDK junction, override
Ghostscript's source, or build a second Ghostscript artifact here. The shared
base owns its FSDK selector and printing patches; requests to adopt a newer line
belong in [fsdk-containers](https://github.com/projectbluefin/fsdk-containers).

A bump changes only the junction ref, and nothing else is ever committed for it,
including one that moves FSDK's Ghostscript:

- `elements/printer-app/version.bst` derives the application version at build
  time as `<gs --version>-<revision>`, where [`VERSION`](../VERSION) holds only
  the packaging revision (raised by hand for packaging-only changes). The
  application binary and the `org.opencontainers.image.version` label read it;
  the publish workflow tags from that label.
- `elements/printer-app/ijs.bst` includes FSDK's `components/ghostscript.bst`
  through the junction for its ghostpdl source, so IJS always matches the shipped
  Ghostscript.
- The publish workflow reads the FSDK version and ref from
  `elements/freedesktop-sdk.bst` at the pinned fsdk-containers commit and stamps
  them as the `io.projectbluefin.fsdk.*` labels and index annotations.

Renovate automerges the PR once the merge queue's full native amd64 and arm64
build and `just verify` pass; the push to `testing` then publishes it. Reverting
the PR is the rollback. Hosted Renovate cannot run repository scripts, so the
bump must stay a complete, buildable change on its own.

Real print-to-socket-sink output is tested; physical paper output remains
unverified without hardware.
