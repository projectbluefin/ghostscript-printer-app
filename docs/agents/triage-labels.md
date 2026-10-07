# Triage Labels

Prow drives issues and pull requests in this repository. Labels are set with `/` commands in a
comment, not by hand. See
[how issues and PRs work here](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).

Exception: `needs-human` has no Prow command and no bot removes it here. Issue templates add it;
a maintainer removes it by hand in the GitHub UI once an issue is accepted and agent-eligible.
This overrides the "let the bot do it" note in the linked workflow doc for this repository.

The skills speak in terms of five canonical triage roles. On
`projectbluefin/ghostscript-printer-app` they map to these labels:

| Role in mattpocock/skills | On GitHub                                             | Meaning                                  |
| ------------------------- | ----------------------------------------------------- | ---------------------------------------- |
| `needs-triage`            | `needs-human`, no `triage/accepted`                   | Maintainer needs to evaluate this issue  |
| `needs-info`              | ask in a comment; `needs-human` stays                 | Waiting on reporter for more information |
| `ready-for-agent`         | `triage/accepted` (`/triage accepted`), `needs-human` removed by a maintainer | Accepted, ready for an agent |
| `ready-for-human`         | `triage/accepted`, `needs-human` kept                 | Accepted, requires human implementation  |
| `wontfix`                 | `/close` with a comment explaining why                | Will not be actioned                     |

Every issue also needs a kind (`/kind bug`, `/kind feature`, `/kind cleanup`, ...); Prow adds
`needs-kind` until one is set.
