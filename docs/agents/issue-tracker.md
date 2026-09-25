# Issue tracker: GitHub Issues

Use [projectbluefin/ghostscript-printer-app Issues](https://github.com/projectbluefin/ghostscript-printer-app/issues) for Bluefin OCI bugs, specs/PRDs, and implementation work. GitHub Issues are enabled on this fork. The `upstream` remote points to OpenPrinting; do not file Bluefin OCI issues there. Historical `.scratch/` notes are not the active issue tracker.

## Conventions

- Keep each spec/PRD and actionable work item in a GitHub issue; link dependent issues rather than duplicating their content.
- Use the canonical triage labels in `docs/agents/triage-labels.md` and record prerequisites in the issue body or comments.
- Discuss progress and decisions in the issue comments; close with the outcome when resolved.

## Skill operations

- **Publish a spec:** create an issue with the scope, acceptance criteria, and linked work items.
- **Fetch a ticket:** read the issue body and comments from this fork.
- **Block:** link all prerequisite issues and apply `needs-info` if reporter input is needed.
- **Claim:** assign the issue to the implementer when permitted and note the claim in a comment.
- **Resolve:** close the issue with a comment summarizing the outcome.
