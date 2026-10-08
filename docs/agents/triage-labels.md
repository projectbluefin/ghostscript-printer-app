# Triage Labels

Prow drives issues and pull requests in this repository. Labels are set with `/` commands in a
comment, not by hand. See
[Prow commands](https://github.com/cncf/prow-github-actions/blob/v3.0.1/docs/commands.md).

The catalog comes from `projectbluefin/.project/prow.yaml`, with repository overrides in
`.github/prow.yaml`. The empty `area` section excludes OS-image categories. Human-only
preferences are recorded in the issue body and handled through human assignment, not an
extra label or an automatic agent opt-out.

The skills speak in terms of five triage roles. These are descriptive roles, not GitHub
label names; use the Prow actions and assignment below.

| Role in mattpocock/skills | Prow action and assignment | Meaning |
| ----------------------- | -------------------------- | ------- |
| `needs-triage` | No `triage/accepted` yet | Maintainer needs to evaluate this issue |
| `needs-info` | Ask in a comment; `/label blocked` while waiting | Waiting on reporter for more information |
| `ready-for-agent` | `/triage accepted`; assign an agent | Accepted, ready for an agent |
| `ready-for-human` | `/triage accepted`; record the human-only preference and assign a human | Accepted, requires human implementation |
| `wontfix`                 | `/close` with a comment explaining why                | Will not be actioned                     |

Every issue also needs a kind (`/kind bug`, `/kind feature`, `/kind cleanup`, ...); Prow adds
`needs-kind` until one is set.
