# FSDK source updates

Renovate ([`renovate.json`](../renovate.json)) is the sole proposal owner. A
`git-refs` custom manager tracks `elements/fsdk-containers.bst`'s `ref:` against
the head of fsdk-containers `main`, rather than filtering FSDK releases to a
local `26.08*` selector. A later compatible FSDK line enters this appliance when
the shared base adopts it. Do not add a second FSDK junction, override
Ghostscript's source, or build a second Ghostscript artifact here. The shared
base owns its FSDK selector and printing patches; requests to adopt a newer line
belong in [fsdk-containers](https://github.com/projectbluefin/fsdk-containers).

A bump changes only the junction ref. Nothing else is committed per bump: the
publish workflow reads the FSDK version and ref from `elements/freedesktop-sdk.bst`
at the pinned fsdk-containers commit and stamps them as the
`io.projectbluefin.fsdk.*` labels and index annotations. Renovate automerges the
PR once the merge queue's full native amd64 and arm64 build and `just verify`
pass; the push to `testing` then publishes it. Reverting the PR is the rollback.
Hosted Renovate cannot run repository scripts, so the bump must stay a complete,
buildable change on its own.

The exception is a bump that moves FSDK's Ghostscript: `tests/appliance-parity.sh`
fails because the binary no longer matches `VERSION`, so the PR does not merge.
Check out the Renovate branch, run `python3 scripts/sync-fsdk-metadata.py`, and
push. It reads the resolved Ghostscript source with BuildStream's
`show --format '%{source-info}'`, requires an exact tagged release, resets
`VERSION` to `<ghostscript>-1` and moves `elements/printer-app/ijs.bst` to the
same ghostpdl release. An unchanged Ghostscript leaves both files untouched; the
packaging revision is otherwise raised by hand.

Real print-to-socket-sink output is tested; physical paper output remains
unverified without hardware.

Local deterministic metadata checks: `just verify-fsdk-metadata`. These exercise
both transitions and rejection without partial writes; they do not substitute for
real OCI verification.
