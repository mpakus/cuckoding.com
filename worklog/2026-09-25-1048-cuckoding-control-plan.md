# 1048 — Board controller plan

## Acceptance and scope

Deliver `docs/CUCKODING-CONTROL.md` with current-source analysis, the agreed
behavior and architecture, seven dependency-ordered implementation tasks,
per-task acceptance checklists, and an integrated verification checklist.
Feature implementation and runtime acceptance must remain unchecked. Validate
documentation links/paths, claims, dependencies, and whitespace only.

## Baseline and method

Started from clean local main at `caed0e7`, five commits ahead of origin/main;
created `feature/1048-cuckoding-control-plan`. Claimed only task 1048. No existing
task or worklog was modified.

Applied Ponytail 4.10.0 full (MIT), workflow-and-kanban,
cuckoding-architecture, security-review, observability, local-runner, and
quality-gates guidance read during planning. Retain existing runtime/workflow,
command/event, Git, LiveView, motion, and telemetry mechanisms; describe only
the missing board orchestration. No new dependency or runtime code is needed
for this documentation delivery. No peer implementation is copied or adapted;
implementation tasks retain the reference-coding prerequisite for unfamiliar
work. Every shell command is RTK-prefixed; no `rtk proxy` exception was used.

Read the actual admission, run control, default workflow, Git preparation,
metrics/accounting, Agent Floor, and UI motion source. Rechecked the current
checkout before writing; older autonomy documents are not treated as proof of
current behavior. Source anchors and the baseline revision are in the proposal.

## Validation

The proposal contains the source baseline, seven implementation slices with
28 unchecked per-task acceptance items, and 13 unchecked integrated acceptance
items. Its lifecycle diagram, skip/dependency rules, reviewed commit provenance,
command ownership, and telemetry semantics match the user's selected decisions.
Checked off only the five documentation acceptance items in task 1048.

Read-only claim review used:

```sh
rtk rg -n 'def (start|dispatch_once|start_queued|prepare_task|start_run|task_counts|control|admit)|defp (start_queued|settlement|task_order_key|capacity_for_queued)|@maximum_(cards|operations)|def (prepare|capture_base)|base_matches|duration: 200|def complete_locally|@max_review_attempts' lib/cuckoding/project_autopilot.ex lib/cuckoding/project_workflow.ex lib/cuckoding/execution/scheduler.ex lib/cuckoding/execution/git_service.ex lib/cuckoding/agent_floor.ex lib/cuckoding/run_control.ex lib/cuckoding/walking_skeleton.ex assets/js/app.js
```

Together with the planning source reads, this confirmed separate queued
admission, project-level control, default-branch base checks, existing local
completion, three review attempts, 100-session/50-run display caps, and 200 ms
motion. These are source observations, not runtime acceptance results.

The exact structural validation command was:

```sh
rtk python3 - <<'PY'
from pathlib import Path
import re

root = Path.cwd()
files = [
    root / 'docs/CUCKODING-CONTROL.md',
    root / 'tasks/phase-10-hardening-beta/1048-cuckoding-control-plan.md',
    root / 'worklog/2026-09-25-1048-cuckoding-control-plan.md',
]
links = 0
for file in files:
    body = file.read_text()
    assert body.endswith('\n'), file
    assert not any(line.rstrip() != line for line in body.splitlines()), file
    assert sum(line.startswith('```') for line in body.splitlines()) % 2 == 0, file
    for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', body):
        path, _, anchor = target.partition('#')
        assert not path.startswith(('/', 'file:')), (file, target)
        resolved = (file.parent / path).resolve()
        assert resolved.is_relative_to(root), (file, target)
        assert resolved.is_file(), (file, target)
        if anchor:
            assert re.fullmatch(r'L\d+', anchor), (file, target)
            assert 1 <= int(anchor[1:]) <= len(resolved.read_text().splitlines()), target
        links += 1

proposal = files[0].read_text()
assert not re.search(r'^- \[[xX]\]', proposal, re.M)
assert 'Status: **Proposed; feature implementation is not complete.**' in proposal
assert 'Files remain unchanged in Plan mode' not in proposal
sections = re.findall(r'^### (CTRL-\d{2}) — [^\n]+\n(.*?)(?=^### CTRL-|^## 8\.)', proposal, re.M | re.S)
assert [key for key, _ in sections] == [f'CTRL-{i:02d}' for i in range(1, 8)]
seen = set()
checks = 0
for key, body in sections:
    dependency_line = re.search(r'^Dependencies: (.+)$', body, re.M).group(1)
    dependencies = set(re.findall(r'CTRL-\d{2}', dependency_line))
    assert dependencies <= seen, (key, dependencies, seen)
    assert ('none' in dependency_line) == (key == 'CTRL-01'), key
    count = len(re.findall(r'^- \[ \]', body, re.M))
    assert count >= 4, (key, count)
    checks += count
    seen.add(key)
assert len(re.findall(r'^- \[ \]', proposal.split('## 8. Integrated verification checklist')[1], re.M)) == 13
anchors = {
    'lib/cuckoding/project_autopilot.ex': {118: 'def dispatch_once', 263: 'defp start_queued'},
    'lib/cuckoding/execution/scheduler.ex': {90: 'def plan', 453: 'def control'},
    'lib/cuckoding/run_control.ex': {39: 'def admit', 95: 'def control'},
    'lib/cuckoding/walking_skeleton.ex': {87: '@doc', 367: 'def complete_locally'},
    'lib/cuckoding/project_workflow.ex': {267: 'def prepare_task'},
    'lib/cuckoding/execution/git_service.ex': {91: 'def prepare'},
    'lib/cuckoding/agent_floor.ex': {21: '@maximum_cards 100'},
    'assets/js/app.js': {91: 'duration: 200'},
}
for path, expected in anchors.items():
    lines = (root / path).read_text().splitlines()
    for number, fragment in expected.items():
        assert fragment in lines[number - 1], (path, number, fragment)
print(f'PASS: {len(files)} Markdown files, {links} local links, {sum(map(len, anchors.values()))} source anchors, 7 ordered tasks, {checks} task checks, 13 integrated checks; all feature checks unchecked.')
PY
```

Result: passed, 3 Markdown files, 27 local links, 12 source anchors, 7 ordered
tasks, 28 task checks, and 13 integrated checks; all feature checks unchecked.

After recording this script and completing task 1048, reran the same validation
directly from this worklog (the fence check counts line-start fences so the
script can inspect its own recorded source):

```sh
rtk python3 - <<'PY'
from pathlib import Path
worklog = Path('worklog/2026-09-25-1048-cuckoding-control-plan.md').read_text()
script = worklog.split("rtk python3 - <<'PY'\n", 1)[1].split('\nPY\n', 1)[0]
exec(compile(script, '<documentation-validation>', 'exec'))
PY
```

Result: passed with the same counts.

`rtk git add -N -- docs/CUCKODING-CONTROL.md tasks/phase-10-hardening-beta/1048-cuckoding-control-plan.md worklog/2026-09-25-1048-cuckoding-control-plan.md`
made the new files visible to diff review without staging their contents.
`rtk git diff --check` passed. `rtk git diff --stat` confirmed only the three
documentation/task/worklog files were added.

Skipped as inapplicable to this documentation-only change: Mix formatter,
compiler, product tests, static analysis, migration tests, browser/native
execution, motion tests, packaging, and real-provider runs. Their future
acceptance gates remain unchecked in the proposal. No test pass is inferred
from the earlier baseline or from this structural validation.

## Delivery state

Documentation task complete in the working tree on the feature branch; changes
are uncommitted. No feature implementation, product test result, migration,
main integration, remote publication, Pages deployment, native rebuild/restart,
or real-provider acceptance is claimed. Implementation starts at CTRL-01; all
seven feature tasks and their runtime acceptance gates remain open.
