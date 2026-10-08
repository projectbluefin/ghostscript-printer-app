# Issue tracker: GitHub Issues

Issues, PRDs, and specs for this repo live as **GitHub Issues** on the
`projectbluefin/ghostscript-printer-app` repository. GitHub Issues are enabled
for mass contributions, so use them as the primary tracker — do not open a
second copy of a ticket in `.scratch/`.

## Conventions

- One feature per issue; link related issues and reference the parent epic
  (`#12`) and the program suite (`projectbluefin/common#1209`) where relevant.
- Record triage state as a label, set with a Prow `/` command (see
  `docs/agents/triage-labels.md`), and an `assignees:` field on the issue.
- Comments and conversation history happen in the issue thread.

## Skill operations

- **Open a ticket:** create the issue with the standard headings (Outcome,
  Evidence, Acceptance criteria, Dependencies, Contribution path).
- **Claim:** assign the issue to yourself before implementation.
- **Resolve:** the merging PR closes the issue; add the outcome in the PR body
  (`Closes #NN`).

## Target branch and promotion gate

- **Submit contributor PRs to `testing`.** This is the active development
  branch and the repository default.
- **`stable` is a separate promotion gate.** Maintainers promote an exact,
  merge-queue-verified `testing` commit by dispatching `promote-stable.yml`,
  which rebuilds and verifies both native architectures before fast-forwarding
  `stable`. Only a Git tag on `stable` matching `v$(cat VERSION)` publishes a
  release: an immutable application-version GHCR
  multi-architecture index with keyless signature, SPDX SBOM, provenance, and
  verified OCI referrers. There is **no** `latest`, `edge`, or mutable
  `stable` OCI tag, and contributors should not open `stable` PRs or publish
  channel aliases.

## Smoke evidence

Real-image behavior, not synthetic mock echoes, proves shipping behavior:

- Pull requests run `just validate`; the merge queue runs the full native
  build and `just verify` before a change lands on `testing`.
- `just verify` is the authoritative appliance gate: it validates the
  BuildStream graph and CUPS patch chain, starts the **real** OCI image,
  exercises every driver slice, verifies lifecycle and persistence, audits the
  advertised payload and complete ELF closure, and enforces the uncompressed
  size ceiling.
- `just verify-core`, `just verify-payload`, `just verify-raster-drivers`,
  `just verify-packaged-drivers`, and `just verify-stateful-drivers` run the
  individual slices.
- For actual hardware, follow
  [docs/oci-physical-validation.md](../oci-physical-validation.md). Never call
  a synthetic CI pass a hardware validation.

## Local Markdown tracker (legacy, optional)

The older local-tracker convention — one feature per directory under
`.scratch/<feature-slug>/`, with `spec.md` and `issues/<NN>-<slug>.md` files —
is retained only for local spec authoring and is intentionally git-ignored
(see `.gitignore`). It is **not** a substitute for GitHub Issues and must not
be used to claim that Issues are disabled. Preserve these notes during migration;
do not delete them without moving any live content into a GitHub issue first.
