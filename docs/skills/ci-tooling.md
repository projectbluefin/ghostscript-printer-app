---
name: ghostscript-printer-app-ci-tooling
description: Use when changing pull-request validation, FSDK source updates, OCI release publication, signatures, SBOMs, or provenance for ghostscript-printer-app.
metadata:
  context7-sources:
    - /websites/github_en_actions
    - /apache/buildstream
---

# CI tooling

## When to Use

- Changing `.github/workflows/ci.yml`, `bst-cache.yml`, `registry-actions.yml`, or `renovate.json`.
- Changing `VERSION`, FSDK release metadata, GHCR tags, SBOM attachment, signing, or provenance.

## When NOT to Use

- Local BuildStream element work that does not change CI or release behavior.
- Non-OCI packaging outside the container release lane.

## Core Process

1. Keep pull-request CI credential-free: `contents: read`, native amd64/arm64 runners, and `just verify`.
2. Publish only from pushes to `testing` (`registry-actions.yml`); its publish job `needs` both native builds, each of which runs `just verify` first. `VERSION` is the application version; the metadata job rejects any other ref before a write-capable job starts.
3. Grant `packages: write`, `id-token: write`, and `attestations: write` only to the publish job.
4. Refuse an existing immutable `sha-<commit>` tag. Proceed only when the authenticated registry response explicitly reports a missing manifest or repository; network and authentication failures are fatal. Move `<VERSION>`, `<VERSION>-x86_64`, `<VERSION>-aarch64` and `stable` only after every check passes.
5. Add version, revision, creation time, license, source URL, FSDK version, and FSDK ref to every architecture image config and to the multi-architecture index.
6. Generate one BuildStream-native SPDX JSON document for the complete dependency graph, attach it to the index, keyless-sign the index and SBOM artifact, publish GitHub provenance with `actions/attest`, then verify all three forms of evidence against the `registry-actions.yml@refs/heads/testing` identity.
7. Renovate tracks `elements/fsdk-containers.bst` (FSDK and the shared printing base) with a `git-refs` custom manager and automerges behind the merge queue's full build and `just verify`. Keep `custom.regex` in `enabledManagers` (otherwise the manager is silently disabled), `minimumReleaseAge` unset for it (git-refs digests have no release timestamp), and every required check unfiltered so automerge never waits on a pending context.
8. Obsolete upstream package automation must not publish or gate a container-only release.
9. Give every external BuildStream source a project alias. Prefer an authoritative, checksummed release archive over a personal Git mirror when upstream Git is unreliable.
10. Give pull-request CI a PR-scoped concurrency group with `cancel-in-progress: true`; stacked force-pushes must not leave duplicate multi-hour architecture jobs consuming the runner pool.
11. Seed `fsdk-containers.bst:printing/base.bst` before the merge-queue, publish and cache-refill builds from `ghcr.io/projectbluefin/printing-base-devel:<arch>-<full-key>`, only after `cosign verify` of its digest against fsdk-containers' workflow identity. The seed step never fails the job: any error is a `::warning::` and BuildStream builds the base locally.
12. Never commit `io.projectbluefin.fsdk.*` labels: the publish metadata job reads them from `elements/freedesktop-sdk.bst` at the pinned fsdk-containers commit, so a bare Renovate bump is complete. Hosted Renovate runs no repository scripts.
13. Treat `oras discover --format json` as a referrer-tree response and query its top-level `.referrers[]`; `.manifests[]` belongs to OCI index JSON, not ORAS discovery output.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| “A failed registry lookup means the tag is absent.” | Authentication and network failures also return nonzero; accept only explicit manifest/name-not-found responses. |
| “The index inherits child labels.” | GHCR renders index metadata; copy required OCI labels into index annotations explicitly. |
| “One host can emulate both architectures.” | Native runners expose architecture-specific source and runtime failures that emulation can hide. |
| “Signing the image covers the SBOM.” | The SBOM is a separate OCI referrer and must be signed and verified separately. |
| “A personal mirror is reachable, so it is a safe fallback.” | Reachability is not provenance. Use an authoritative archive with a verified digest or an organization-controlled mirror. |
| “Renovate can run the metadata script after a bump.” | Hosted Renovate runs no repository commands; derive metadata at build or publish time instead. |

## Red Flags

- Registry login, package write permission, or OIDC access in a pull-request job.
- A publish trigger other than a push to `testing`, or a publish job without `needs` on the verified builds.
- `latest` or `edge` in the OCI publish workflow.
- Unpinned third-party actions.
- Committed FSDK metadata that a junction bump must rewrite.
- Index creation without checking both native architecture manifests and their config labels.
- An SBOM generated for only the runner's architecture.
- An unaliased external source URL or a source pinned only to a personal fork.
- Pull-request CI without cancellation of superseded runs.
- An ORAS discovery assertion that reads `.manifests[]` instead of `.referrers[]`.

## Verification

- [ ] `actionlint .github/workflows/*.yml` succeeds.
- [ ] `just verify` succeeds locally.
- [ ] Pull-request CI completes on native amd64 and arm64 runners without registry credentials.
- [ ] BuildStream resolves and fetches every repository-owned source without `[unaliased-url]` warnings.
- [ ] Pushing a replacement commit cancels the superseded run for the same pull request.
- [ ] `npx --yes --package renovate -- renovate-config-validator renovate.json` succeeds.
- [ ] SBOM discovery selects the expected digest and `application/vnd.spdx+json` type from `.referrers[]`.
- [ ] A run on any ref other than `testing` fails in the metadata job before any write-capable job.
- [ ] The published index contains exactly amd64 and arm64 and has the required annotations.
- [ ] `cosign verify` succeeds for the index and SBOM artifact.
- [ ] `gh attestation verify oci://<image>@<digest> --repo <owner/repo>` succeeds.
