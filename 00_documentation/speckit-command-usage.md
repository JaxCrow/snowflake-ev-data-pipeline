# SpecKit Command Usage in This Repository

## Why `speckit.tasks` failed in terminal

`speckit.tasks` is a chat prompt/agent command in this repository, not a terminal CLI executable.

- In terminal (PowerShell), `speckit.tasks` fails because no CLI binary named `speckit.tasks` exists on PATH.
- In Copilot Chat, slash prompts are loaded from `.github/prompts/`.

## Commands to use in Copilot Chat

Prefer these aliases (hyphen form) for maximum compatibility across chat hosts:

- `/speckit-specify`
- `/speckit-plan`
- `/speckit-tasks`
- `/speckit-implement`
- `/speckit-clarify`
- `/speckit-analyze`
- `/speckit-checklist`
- `/speckit-converge`
- `/speckit-constitution`

Legacy dotted forms are also present when supported:

- `/speckit.specify`
- `/speckit.plan`
- `/speckit.tasks`
- `/speckit.implement`

## Strict hook policy

Mandatory hooks are configured in `.specify/extensions.yml` and are expected to run before/after each workflow phase.

## Recommended flow

1. `/speckit-specify`
2. `/speckit-plan`
3. `/speckit-tasks`
4. `/speckit-implement`

Use `/speckit-clarify`, `/speckit-checklist`, and `/speckit-analyze` at their configured hook points.
