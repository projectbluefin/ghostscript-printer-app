# Triage Labels

Prow drives issues and pull requests in this repository. Labels are set with `/` commands in a
comment, not by hand. See
[Prow commands](https://github.com/cncf/prow-github-actions/blob/v3.0.1/docs/commands.md).

The Prow catalog comes from `projectbluefin/.project/prow.yaml`, with repository overrides
in `.github/prow.yaml`. The empty `area` section excludes OS-image categories. Hive also
uses labels outside that catalog; absence from Prow configuration does not make them unused.

`needs-human` is the Hive agent opt-out. Issue templates apply it by default. A maintainer
removes it only when an issue is accepted and agent-eligible; keep it for human-only work.

The skills speak in terms of five triage roles. These are descriptive roles, not GitHub
label names; use the Prow actions and assignment below.

| Role in mattpocock/skills | Prow action and assignment | Meaning |
| ----------------------- | -------------------------- | ------- |
| `needs-triage` | `needs-human`, no `triage/accepted` | Maintainer needs to evaluate this issue |
| `needs-info` | Ask in a comment; keep `needs-human` | Waiting on reporter for more information |
| `ready-for-agent` | `/triage accepted`; a maintainer removes `needs-human` | Accepted, ready for an agent |
| `ready-for-human` | `/triage accepted`; keep `needs-human` | Accepted, requires human implementation |
| `wontfix`                 | `/close` with a comment explaining why                | Will not be actioned                     |

Every issue also needs a kind (`/kind bug`, `/kind feature`, `/kind cleanup`, ...); Prow adds
`needs-kind` until one is set.
