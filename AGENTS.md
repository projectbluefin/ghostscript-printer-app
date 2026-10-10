# AGENTS.md

## Checks and CI

Every change is gated by CI plus a pre-commit hygiene pass:

- **`validate`** (`.github/workflows/validate.yml`): runs `pre-commit run --all-files` on `pull_request` and `merge_group`. Runs `actionlint`, YAML/JSON/toml hygiene, and blocks floating GitHub Action tags — third-party actions must be pinned to a full SHA (`no-floating-action-tags`). This check is required in the `main` ruleset.
- **Scorecard** (`.github/workflows/scorecard.yml`): OpenSSF Scorecard supply-chain check.
- **CI** (`.github/workflows/ci.yml`): FSDK appliance build and snap.
- **`.pre-commit-config.yaml`**: the checks above. Run `pre-commit run --all-files` before every commit.

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

Target `main` for fsdk-containers updates and development PRs; promote verified commits to `stable` with `promote-stable.yml`. Pull requests run `validate` and CI; the merge queue runs the full OCI appliance gate before a change lands on `main`, and the promotion workflow runs it again before fast-forwarding `stable`. Only version tags on `stable` publish immutable OCI releases.
