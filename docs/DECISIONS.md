# Current decisions

Accepted product reset: 2026-10-06. Earlier ADRs remain in Git history; they do
not establish implementation or acceptance of this rebuild.

| ID | Decision | Reason / consequence |
| --- | --- | --- |
| D001 | Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2 | User requested the same stack; no replacement frontend/control plane |
| D002 | Arena = project, Tabula = board, battle = execution, Tabula Gladiatorum = global/Arena dashboard | One consistent product vocabulary; Area interpreted as Arena |
| D003 | Speculator → Implementor → Secutor; distinct Summa Rudis coordinator | Separate planning, writing, completion judgment and coordination |
| D004 | One Start battle authorizes bounded ordinary local work | No competing manual/prepared/project start modes or repeated task approvals |
| D005 | Phoenix validates agent proposals; SQLite owns durable state | Model output cannot command the host or fabricate completion |
| D006 | Parallel task workers; serialized reviewed battle-branch integration | Deliver concurrency without shared writable worktrees or stale-review acceptance |
| D007 | One active battle per Arena initially | Keeps integration ownership simple; independent Arenas/tasks still run concurrently |
| D008 | Ordered custom columns/roles with mandatory final review | Meet extensibility need without a general workflow graph editor |
| D009 | Readable Markdown specs/evidence, scoped file search, RTK and Ponytail full | No XERJ, embeddings service, plugin marketplace or autonomous memory pipeline |
| D010 | Source reset preserves old application data; use a separate rebuild data root | No inferred permission to destroy databases/profiles/worktrees |
| D011 | Ten minutes from first launch to ready with runtime/account prerequisites stated | Measurable setup target; also report full installation timing |
| D012 | Provider capabilities require per-version real evidence | Named runtimes are targets, not unsupported promises; transport stays adapter-specific |
| D013 | Append-only scoped team adoptions override creation defaults for future work | Explicit confirmation and revision guards; Arena changes affect new boards, Tabula changes affect new planning, historical receipts stay unchanged |
| D014 | Explicit selected-document snapshots feed the existing no-tools planning turn | Local preview reads bounded text using pinned descriptors; separate provider consent freezes the scoped snapshot reference. Documents are untrusted evidence, never filesystem or execution authority |
| D015 | Draft prerequisites live in immutable draft revision content | Reuse the existing save transaction and current-revision projection; validate same-board references and acyclicity before saving. No scheduler or new execution authority is implied |
| D016 | New Speculator proposals reference earlier tasks and selected snapshots by bounded indices | A versioned contract binds references to the frozen request; import resolves prerequisites through same-board receipts and retains source provenance. No arbitrary path, task ID or execution authority comes from provider output |

The first release scope and deferred features are in [Product](PRODUCT.md).
[Flow](FLOW.md) owns state, defaults and limits. Changes to settled boundaries
must update this file before implementation and preserve the user-approved scope.
