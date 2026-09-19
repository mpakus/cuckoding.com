# Worklog — 1015 current product-flow documentation

## Scope and acceptance

Docs-only audit of the new project, saved-agent, board, planning, task, and monitoring flow. Acceptance is accurate routes/actions, explicit snapshot and authentication boundaries, current implementation versus pending evidence, and passing structural checks.

## Baseline and method

- Baseline: `57bac64` on `main`; task branch `feature/1015-current-flow-docs`.
- Preserve unrelated untracked `icon.png`; no application, database, credentials, or runtime state changes.
- Applied Ponytail full, quality-gates, and security-review. OpenAI Docs used for the credential-store documentation check.
- Inspected router, setup/edit LiveViews, ProjectOnboarding, ProjectWorkflow, BoardTaskIntake, GuidedRun, AgentRuntime, adapter and test evidence. Cross-checked product, workflow, UI, architecture, configuration, security, execution, plan, testing, and beta documentation.
- Exact reads use `rtk proxy cat` / `rtk proxy sed` to avoid truncating source and Markdown; read-only structural scripts use `rtk proxy ruby` for exact results. Other repository commands use RTK normally.
- No unfamiliar implementation or peer code adaptation: this change documents existing code only. XERJ reindexing and runtime changes are outside scope.

## Findings

- Old documentation still conflated the wizard with agent configuration and called the live GuidedRun launcher test-only.
- Board creation/task preparation are implemented, but real-provider beta acceptance remains open.
- Saved agent metadata is reusable; project/board/run snapshots do not automatically refresh. Legacy boards retain run-scoped authentication when their snapshots lack account IDs.
- Codex account authorization and run probes use different homes. Existing mocked checks do not demonstrate credential reuse across those homes; successful account login alone is insufficient evidence.
- Global authorization status is a current projection, not an append-only audit or a guarantee that a later run can start.
- `Definition.default/0` includes Review returns, but the live GuidedRun → WalkingSkeleton launch path does not call its evaluator to schedule them. The launcher waits for release approval; local completion without release is also missing. Kept the Phase 10 product-flow parent open and documented this implementation gap.

## Verification

- `rtk git diff --check` — passed.
- Structural check below — passed: 19 Markdown files, 17 local links, 21 source references, balanced code fences (before adding this command transcript).
- Source review confirmed every new route against `lib/cuckoding_web/router.ex`; action labels against the corresponding LiveViews; planning tool policy against `BoardTaskIntake`; snapshot behavior against `ProjectWorkflow` and `AgentRuntime`; sequential execution against `WalkingSkeleton.run/2`.
- No new compiler, test-suite, provider, browser, or packaging run is claimed for this documentation-only task. Prior task 1014 results are explicitly dated historical evidence.

```sh
rtk proxy ruby - <<'RUBY'
require 'open3'
files, status = Open3.capture2('git', 'ls-files', '--modified', '--others', '--exclude-standard')
abort 'Cannot list changes' unless status.success?
files = files.lines.map(&:strip).grep(/\.md\z/)
links = refs = 0
files.each do |file|
  body = File.read(file)
  abort "Unbalanced fences: #{file}" if body.lines.count { |line| line.start_with?('```') }.odd?
  body.scan(/\[[^\]]+\]\(([^\s)]+)\)/).flatten.each do |target|
    next if target.match?(/\A(?:https?:|mailto:|#)/)
    links += 1
    abort "Missing link: #{file}: #{target}" unless File.exist?(File.expand_path(target.split('#', 2).first, File.dirname(file)))
  end
  body.scan(/`((?:lib|test)\/[\w\/.\-]+\.(?:ex|exs))(?::\d+(?:-\d+)?)?`/).flatten.each do |path|
    refs += 1
    abort "Missing source: #{path}" unless File.file?(path)
  end
end
puts "PASS: #{files.size} Markdown files; #{links} local links; #{refs} source references; balanced fences"
RUBY
```

## Handoff

Documentation is complete; no runtime behavior was changed. Prioritize real cross-home authentication verification and connecting Review-return/local-complete branches to the live launcher. Preserve existing tasks and immutable snapshots. Shared-account lifecycle and broader beta/release evidence remain open in `docs/PLAN.md` and `docs/DOCUMENTATION_AUDIT.md`.
