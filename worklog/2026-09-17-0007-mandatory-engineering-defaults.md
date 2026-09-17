# Worklog — 0007 Mandatory engineering defaults

## Metadata

- Date/time (UTC): 2026-09-17T04:28:43Z
- Task: 0007
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0007-mandatory-engineering-defaults`
- Start revision: `81b89da`
- End revision: commit containing this worklog
- Environment: documentation and Agent Skills rules only; RTK 0.49.0

## Intended outcome

Require RTK, Ponytail minimalism, focused regression coverage, and proportionate quality evidence for repository work while preserving Cuckoding's optional runtime-plugin boundary.

## Context inspected

- Root `AGENTS.md`, `docs/SKILLS.md`, `docs/plugins/PONYTAIL.md`, the repository Ponytail skill, task index, and worklog template.
- Upstream Ponytail and skill-creator instructions.
- Clean `main` at `81b89da` before creating the task branch.

## Work performed

- Made Ponytail full mode mandatory for every repository change and review.
- Defined minimalism as the smallest coherent root-cause solution, with security, durability, accessibility, observability, migrations, validation, and acceptance criteria preserved.
- Required focused runnable coverage for behavioral changes and proportionate structural checks for documentation-only changes.
- Kept the product's Ponytail integration optional and replaceable; contributor practice and runtime availability are separate concerns.
- Added task 0007 to the Phase 0 index.
- Rebuilt the project corpus under isolated prefix `cuckoding-project-v3` after XERJ safely rejected a retained `AGENTS.md` format-family change in the v2 journal; the durable v2 corpus was not deleted or overwritten.

## Artifacts

- Rules: `AGENTS.md`
- Skill: `.agents/skills/ponytail-minimalism/SKILL.md`
- Supporting docs: `docs/SKILLS.md`, `docs/plugins/PONYTAIL.md`, `docs/REFERENCE_CODING.md`, `docs/reference-corpus.yml`, `docs/IMPLEMENTATION_READINESS.md`, `docs/DOCUMENTATION_AUDIT.md`
- Task: `tasks/phase-00-discovery/0007-mandatory-engineering-defaults.md`

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk proxy /Users/mpak/.local/share/uv/tools/specify-cli/bin/python /Users/mpak/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/ponytail-minimalism` | pass | Skill front matter and structure are valid. |
| `rtk rg -n "Prefix every repository shell command|Ponytail skill|smallest coherent root-cause|focused runnable regression|quality-gates" AGENTS.md .agents/skills/ponytail-minimalism/SKILL.md docs/SKILLS.md docs/plugins/PONYTAIL.md` | pass | Mandatory rules and contributor/runtime distinction found. |
| `rtk rg -n "^# |^## Objective|^## Acceptance criteria|status:|worklog:" tasks/phase-00-discovery/0007-mandatory-engineering-defaults.md` | pass | Required task structure found. |
| `rtk proxy ruby -e 'files = Dir["tasks/**/[0-9][0-9][0-9][0-9]-*.md"]; bad = files.reject { \|path\| text = File.read(path); text.include?("## Objective") && text.include?("## Acceptance criteria") }; abort("invalid: #{bad.join(", ")}") unless bad.empty?; puts "#{files.size} task files valid"'` | pass | All 51 numbered task files contain Objective and Acceptance criteria sections. |
| `rtk git diff --check` | pass | No whitespace errors. |
| `rtk xerj autoindex . --dry-run --no-graph --prefix cuckoding-project-v3 --state-dir /Users/mpak/.local/share/cuckoding/xerj/autoindex/cuckoding-project-v3 --progress plain` | pass | 92 files discovered; 89 planned; three expected junk files; no writes. |
| `rtk xerj autoindex . --no-graph --prefix cuckoding-project-v3 --state-dir /Users/mpak/.local/share/cuckoding/xerj/autoindex/cuckoding-project-v3 --progress plain --yes` | pass | Initial generation 1 and final documented reconciliation generation 2 each committed 89 files and 184 records; exit 3 means completed with the three expected junk files. |
| `rtk xerj search --prefix cuckoding-project-v3 -k 5 "Ponytail full mode focused runnable regression quality gates"` | pass | Returned the updated Ponytail contributor rule from `docs/plugins/PONYTAIL.md`. |

## Telemetry and operational evidence

No runtime, cost, or performance telemetry applies to this rules-only change.

## Decisions and deviations

- Ponytail is mandatory for repository contributors and agents. Its product integration remains optional so failure or absence of one plugin cannot break Cuckoding core.
- Documentation-only work uses structural validation rather than artificial application tests.
- The validator could not run through the default `python` command, and system Python lacked PyYAML. It passed with an existing local tool environment that already includes PyYAML; no dependency was installed.
- XERJ's v2 journal refused an unsafe retained-file family change. Following the installed CLI's recovery guidance, v3 uses a new prefix and state directory; v2 remains intact and superseded.

## Risks and blockers

- None. Future tasks must enforce the rules through their worklogs and review evidence.

## Handoff

Apply RTK and Ponytail at the start of every subsequent repository task, search `cuckoding-project-v3` before unfamiliar implementation work, then run and record the relevant quality gates before completion.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
