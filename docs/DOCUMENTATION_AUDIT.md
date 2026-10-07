# Documentation reset audit

Date: 2026-10-06. Scope: surviving documentation, contributor guidance, role
templates and stale configuration/CI references after the user's source removal.

## Findings

The baseline had **44 Markdown documents / 92,233 words under docs/** and 700
tracked files already deleted by the user, including the application, tests,
native shell, site, tasks and worklogs. Remaining prose still said those
features were implemented, linked to absent evidence and offered incompatible
Start board / Start project / prepared-run / autonomous-goal flows.

The old Speculator doubled as controller, the final role was Reviewer, the main
board path was sequential, and the UI included several dashboards/knowledge views.
That did not match the requested distinct Summa Rudis, Secutor, parallel workers,
ten-minute setup and minimal interface. Configuration examples also sent review
directly to implementation or a mandatory release-approval stage, conflicting
with the requested correction loop and automatic local completion.

## Retained and compressed sources of truth

| Document | Owns |
| --- | --- |
| [PRODUCT](PRODUCT.md) | Eight-step story, names, roles, scope and success |
| [FLOW](FLOW.md) | Planning, battle authority, states, review, controls, parallel integration |
| [ARCHITECTURE](ARCHITECTURE.md) | Stack, components and durable effects |
| [DB](DB.md) | Minimal records, integrity, retention and old-data protection |
| [SECURITY](SECURITY.md) | Trust boundaries, permissions, secrets and audit |
| [EXECUTION_ENVIRONMENTS](EXECUTION_ENVIRONMENTS.md) | Host processes/worktrees, RTK, sleep and cleanup |
| [AGENT_AUTHORIZATION_FLOW](AGENT_AUTHORIZATION_FLOW.md) | Login reuse, model cache and setup |
| [AGENT_RUNTIME_ADAPTERS](AGENT_RUNTIME_ADAPTERS.md) | Runtime contract and per-provider evidence |
| [UI_DASHBOARD](UI_DASHBOARD.md) | Tabula Gladiatorum and minimal interaction |
| [PLAN](PLAN.md) | Ordered R010–R100 checklist and story traceability |
| [TESTING](TESTING.md) | Focused gates and complete story acceptance |
| [DEVELOPMENT](DEVELOPMENT.md) | Contributor workflow and safe runtime/data handling |
| [REFERENCE_CODING](REFERENCE_CODING.md) | Direct local/primary-source search and license checks |
| [SKILLS](SKILLS.md) | Existing engineering tools and when to use them |
| [DECISIONS](DECISIONS.md) | Current decisions replacing obsolete ADR history |
| This audit | Reset rationale and removal map |

README is the short entry point. AGENTS and Cursor rules now use the same names,
scope and status. The four role templates use Speculator, Implementor, Secutor
and Summa Rudis. Application gates remain unchecked.

## Removed material and destination

Names below are historical files, not live links. Git retains their prior text;
no second archive copy is added to the working tree.

| Removed group | Treatment |
| --- | --- |
| AUTONOMOUS_PROJECT_FLOW, CUCKODING-CONTROL, PAPERCLIP_ADOPTION_PLAN | Useful bounded autonomy/recovery and evidence rules merged into FLOW/PLAN; competing controllers/start modes removed |
| BETA_REPORT, BETA_RUNBOOK, RELEASE_READINESS, IMPLEMENTATION_READINESS, WALKING_SKELETON | Historical acceptance claims retired; new acceptance lives in PLAN/TESTING |
| HOST_AGENT_RUNTIME_SPIKE, MENUBAR_SHELL_SPIKE, SLEEP_WAKE_POWER_SPIKE | Old measured results retired; relevant safety constraints retained in architecture/execution/testing |
| SECURITY_TEST_MATRIX, TRUSTED_HOST_THREAT_MODEL, RECOVERY_DRILLS | Boundary/failure gates consolidated into SECURITY/TESTING |
| DESKTOP_SHELL, DISTRIBUTION, LONG_RUNNING_AND_POWER | Necessary shell/recovery/distribution requirements merged into architecture/execution/plan |
| CONFIGURATION, TELEMETRY | Saved revisions, limits and honest public activity covered by DB/FLOW/UI |
| KNOWLEDGE_COMPRESSION, PLUGINS, CONTAINER_RUNNER_CONTRACT | Separate speculative subsystem specifications removed; explicitly deferred in PRODUCT |
| MVP_BOUNDARY_AND_POSITIONING, REFERENCES, CHANGES | Competitive/commercial/historical narrative removed; current decisions and targeted reference workflow retained |
| plugins/PONYTAIL, plugins/RTK, plugins/MCP_FILESYSTEM, plugins/XERJ | RTK/Ponytail requirements consolidated into execution/skills; unused connector plans removed |
| reference-corpus.yml | Stale index namespaces/pins removed; search the actual source when needed |

Removed the four old executable-looking YAML examples from `.cuckoding/`;
normal configuration is UI-first and the new schema must be implemented/tested
before publishing examples. Replaced the old spec-writer/implementer/reviewer
prompts with the requested names; removed release-handoff as an agent template
because publication is outside the local battle.

Removed the two remaining release/Pages workflow files: they invoked deleted
scripts or uploaded a deleted site. R100 explicitly restores release CI only
with a verified pipeline. No deployed site, remote release, installed tool,
existing application data or running application was changed.

Updated local skills only where they referenced deleted docs, obsolete behavior
or falsely assumed implementation. Deferred plugin/knowledge skills remain
available but cannot expand rebuild scope. XERJ is no longer a project dependency
or contributor workflow. `rtk rg` and direct file reads are sufficient; no new
plugin, provider or indexing replacement was installed.

## Verification and limits

See [R001 worklog](../worklog/2026-10-06-R001-documentation-reset.md) for exact
checks, final compression counts and results. Documentation validation does not
prove implementation, runtime support, ten-minute setup or packaged-app behavior.
This reset preserves the user's original deletions and leaves application work
at R010. No commit or remote publication is implied.
