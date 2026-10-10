# AGENTS.md

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub Issues on this repository. See
`docs/agents/issue-tracker.md`.

### Issues, pull requests and labels

Prow drives review and merge commands: `/` commands in comments set labels, reviewers and approvals, and Prow merges through the merge queue on `lgtm` + `approved` (approvers come from `OWNERS`). See [Prow commands](https://github.com/cncf/prow-github-actions/blob/v3.0.1/docs/commands.md). Hive manages contributor work and its metadata labels, including the `needs-human` agent opt-out; do not remove these merely because they are outside Prow's catalog. Repository Prow overrides live in `.github/prow.yaml`; triage roles and the human-only gate are documented in `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root, created lazily by domain modeling. See `docs/agents/domain.md`.

### OCI container build

Before changing the BuildStream/FSDK graph or CUPS integration, read `docs/skills/fsdk-cups-patching.md`.

### Branches and releases

Target `testing` for development PRs; Renovate proposes and automerges fsdk-containers junction bumps there. Pull requests run `just validate`; the merge queue runs the full OCI appliance gate before a change lands on `testing`. Every push to `testing` rebuilds, re-verifies and publishes the signed image (`registry-actions.yml`): immutable `sha-<commit>`, moving `<VERSION>` and `stable`. Reverting a PR is the rollback. Keep `main` while existing feature branches or workflows still reference it.
