# BOSS — исследование референсов

Дата: 2026-10-25. Область: чтение исходников, лицензий и CLI help; проверка xerj
retrieval. Приложения конкурентов и их suites не запускались. Скриншоты не
снимались. Это основания для собственных тестов BOSS, не доказательство
надёжности чужих продуктов.

## Снимки

| Репозиторий | Commit | LICENSE в checkout | Зачем он нужен |
|---|---|---|---|
| [Agetor](https://github.com/alamops/agetor) | `fbd68603afef778a618a94ca88e0c00997956afd` | MIT | Ближайший local CLI + worktree + board workflow |
| [Kander](https://github.com/dualface/kander) | `dea0ba6b885c39a56ee769223f7fa5c054e68c70` | MIT | Проверяемое независимое review и завершение |
| [Orchestrator.inc](https://github.com/OrchestratorInc/agent-orchestrator) | `7193eff4e08f1481944845ee058fe6fd18930b6d` | Apache-2.0 | Session lifecycle и производное состояние UI |
| [Backlog](https://github.com/osmove/backlog) | `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7` | Apache-2.0 | Dependencies, scopes, claims |

URL Backlog проверен через GitHub-ссылку на [backlog.so](https://backlog.so/).
Эти четыре проекта закрывают ключевые вопросы плана; дополнительные большие
репозитории пока не нужны. Команды поиска и восстановления — в
[examples/README.md](../examples/README.md), manifest — рядом с ним.

## Agetor: протокол, работа процесса и Git

- [`mapCodexEvent`, строки 111–153](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/codex-tmux.ts#L111):
  thread ID, terminal turn event и item ID разбираются отдельно; event type
  участвует в ключе дедупликации. **Берём:** явный normalizer и устойчивую
  идентичность событий. **Не переносим:** привязку нормализации к tmux.
- [Death watch, строка 366](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/codex-tmux.ts#L366):
  после исчезновения session дочитывается хвост лога; отсутствие terminal event
  по умолчанию считается ошибкой. **Для BOSS:** отдельно runner result, agent
  protocol result и task acceptance. Exit 0 не означает выполненную задачу.
- [Worktree reuse, строка 985](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/worktree.ts#L985):
  используется закреплённая base, существующая ветка присоединяется повторно
  без принудительного rewind. **Берём:** сохранить изменения при Retry/recovery.
- [Local auth, строка 403](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/server.ts#L403):
  loopback дополняется origin allowlist и token gate. **Для BOSS:** использовать
  Phoenix session/CSRF/origin; URL-token fallback для SSE не нужен LiveView.
- [Discovery](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/agent-discovery.ts#L31):
  probe ограничен временем. **Берём:** быстрый install/version/capability probe;
  неизвестную auth нельзя показывать как verified. Не переносим каталог всех моделей.

Точки для следующего чтения тестов:
[`codex-tmux.test.ts`](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/codex-tmux.test.ts),
[`worktree.test.ts`](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/worktree.test.ts),
[`server-auth.test.ts`](https://github.com/alamops/agetor/blob/fbd68603afef778a618a94ca88e0c00997956afd/src/bun/server-auth.test.ts).

## Kander: одобрение относится к конкретным доказательствам

- [`validateContextMode`](https://github.com/dualface/kander/blob/dea0ba6b885c39a56ee769223f7fa5c054e68c70/internal/review/validate.go#L14)
  проверяет role, spec/worktree paths, полные Git object IDs и ancestry.
  **Берём:** проверку review envelope и связи с original spec/base/candidate.
- [`verifyClosureHead` / `closeWithGit`](https://github.com/dualface/kander/blob/dea0ba6b885c39a56ee769223f7fa5c054e68c70/internal/review/disposition.go#L196)
  требуют clean worktree на ожидаемом HEAD и повторяют проверку после долгой
  Git-работы перед закрытием. **Берём:** повторную проверку актуальности evidence
  и compare-and-swap переход; одно текстовое `approved` недостаточно.
- [Schema generation](https://github.com/dualface/kander/blob/dea0ba6b885c39a56ee769223f7fa5c054e68c70/internal/review/schema.go#L37)
  строится вокруг типизированных evidence structures. **Для BOSS:** достаточно
  маленького фиксированного verdict contract; многоуровневый DSL не нужен.

Independent review в BOSS — отдельный run без developer conversation, на
зафиксированном коде, без write permissions. Другой provider полезен, но не
заменяет независимый контекст и детерминированные gates. Не копируем большой
role/configuration matrix Kander. Rejected→repair→approved ещё нужно воспроизвести
на BOSS fake CLI и затем на реальном провайдере.

## Orchestrator.inc: факты отдельно от представления

- [`DeriveKanbanPresentation`](https://github.com/OrchestratorInc/agent-orchestrator/blob/7193eff4e08f1481944845ee058fe6fd18930b6d/backend/pkg/contract/kanban.go#L235)
  сначала выводит колонку из lifecycle facts, затем статус внутри неё; завершённый
  PR не скрывает другую активную работу. **Берём:** чистое отображение persisted
  task/run facts в board. Не позволять drag-and-drop присваивать Done.
- [Status recovery](https://github.com/OrchestratorInc/agent-orchestrator/blob/7193eff4e08f1481944845ee058fe6fd18930b6d/backend/internal/session_manager/status_readiness.go#L56)
  различает pending, failure и готовность новых sessions во время startup recovery.
  **Берём:** явное «восстановление / требуется действие», а не готовность по умолчанию.
  Не переносим PR/cloud/mobile/provider-switch подсистемы.

Точка проверки presentation behavior:
[`kanban_test.go`](https://github.com/OrchestratorInc/agent-orchestrator/blob/7193eff4e08f1481944845ee058fe6fd18930b6d/backend/pkg/contract/kanban_test.go#L16).
Полный crash-recovery путь и SQLite event reconstruction здесь не аудированы.

## Backlog: scheduler объясняет, почему задача ждёт

- [`dependencyReasons`](https://github.com/osmove/backlog/blob/3580cfbbb1be4144a5cca5b49190e1f8158e4cf7/packages/core/src/scheduler.ts#L108)
  различает missing dependency, failed dependency и обычное ожидание.
  **Берём:** эти причины для UI и retry policy. У BOSS зависимость удовлетворяется
  после delivery policy, не просто после завершения agent run.
- [`isAlreadyHandled`](https://github.com/osmove/backlog/blob/3580cfbbb1be4144a5cca5b49190e1f8158e4cf7/packages/core/src/scheduler.ts#L48)
  исключает running/review из повторного планирования. **Берём:** идемпотентный
  launch claim в SQLite, не только фильтр состояния в памяти.
- [`scopesOverlap`](https://github.com/osmove/backlog/blob/3580cfbbb1be4144a5cca5b49190e1f8158e4cf7/packages/claims/src/overlap-detector.ts#L12)
  консервативно сравнивает статические префиксы glob. **Берём:** простую оценку
  известного пересечения; не выдаём её за доказательство отсутствия конфликтов.
- [Claims и expiry](https://github.com/osmove/backlog/blob/3580cfbbb1be4144a5cca5b49190e1f8158e4cf7/packages/claims/src/claim-store.ts#L39):
  битый JSON перемещается в quarantine и исключается из active claims. Это
  конкретный компромисс источника. **Для BOSS выбираем иначе:** неизвестное
  владение worktree блокирует новый запуск до reconciliation. Один истёкший TTL
  не доказывает, что старый процесс прекратил запись.

## Ответы на вопросы BOSS_PLAN §2

| Вопрос | Основание и решение BOSS |
|---|---|
| Exit success vs task success? | Agetor normalizer/death watch + Kander closure: хранить раздельные runner/protocol/check/review/integration результаты. |
| Идентичность после рестарта? | Agetor имеет tmux+thread/log identity; BOSS сначала direct runner и interrupted reconciliation, без обещания прозрачного reattach. |
| Permissions / credentials? | Agetor показывает, что loopback требует auth. Help наших CLI подтверждает отдельные permission modes; BOSS не читает provider auth files и не включает bypass по умолчанию. |
| Worktree / integration collisions? | Agetor сохраняет base и ветку; Backlog выявляет известное scope overlap. Serialized integration и защита target в BOSS ещё требуют отдельного spike. |
| Verdict validation? | Kander проверяет typed evidence и актуальный HEAD. BOSS валидирует schema и commit/spec binding. |
| Transactions / восстановление? | Исследованные фрагменты не доказывают полную reconstructability. BOSS сам проверяет atomic state+event, intent-before-effect и reconcile; не наследует гарантию из README. |
| Лёгкое подключение CLI? | Bounded discovery; PATH/version/help сейчас доступны. Auth status может быть unknown, login остаётся в официальном CLI. |

## Проверка инструментария

`xerj 1.0.0-rc.98`, prefix `bossrefs`, lexical search. Первый build:
8 098 файлов, 87 778 records; exit 3 (`completed-with-junk`), 80 skipped files.
Причины включают migration SQL без извлечённых records, PDF parser errors,
бинарные/XML файлы и zip. Основной исходный код доступен; полнота всех форматов
не заявляется. `ax` пользователя сохранён.

Проверенные запросы (все exit 0, релевантный source в выдаче):

| Запрос | Возвращённая реализация |
|---|---|
| `mapCodexEvent` | `agetor/src/bun/codex-tmux.ts:123` |
| `verifyClosureHead` | `kander/internal/review/disposition.go:196` |
| `DeriveKanbanPresentation` | `agent-orchestrator/backend/pkg/contract/kanban.go:242` |
| `dependencyReasons` | `backlog/packages/core/src/scheduler.ts:108` |

Широкий запрос `worktree base commit` вернул нерелевантные top-3 фрагменты.
Для этого corpus подтверждён поиск по именам символов; обычный вопрос нужно
уточнять терминами и проверять исходником/`rg`.

Это smoke index coverage, не benchmark качества поиска по произвольному вопросу.
До production code нужно искать конкретную задачу, читать тесты и заново
проверять соответствие нашим constraints.

## Implementation evidence — first increment

The pinned references above remain unchanged. Source research led to executable
checks in [Git spike](../spikes/git/README.md) and
[runner spike](../spikes/runner/README.md). The first is a conservative policy
experiment; the second leaves memory/EOF/descendant safety unresolved. Neither
module is part of the application's runtime.

Project registration additionally used Agetor's `identifier-input.ts` distinction
between literal paths/refs and prose. The browser form disables autocorrection
for these fields. Backlog's stable source identity informed the upcoming spec
design; revisions/import have deliberately not been scaffolded prematurely.
Exact queries, mutations and adopted/rejected tradeoffs are in
[project worklog](../.worklog/2026-10-25-projects.md).


## BOSS-003a: полный scan, frontmatter и ручной Sync

- Kander `dea0ba6b885c39a56ee769223f7fa5c054e68c70`,
  `internal/board/scan.go:30`, `summary_refresh.go:17`,
  `summary_cache_test.go:325`: публиковать только полный валидный scan.
  `internal/fs/posix.go:222` и `fifo_unix_test.go:15` показывают более строгие
  O_NOFOLLOW/O_NONBLOCK guards. BOSS проверяет типы и ограничивает чтение, но
  portable Elixir implementation не равна этим OS-гарантиям.
- Agent Orchestrator `7193eff4e08f1481944845ee058fe6fd18930b6d`,
  `frontend/src/renderer/lib/markdown-frontmatter.ts` и тест: anchored delimiter,
  BOM/CRLF и сохранение source. Не переносим handwritten subset YAML.
- Backlog `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`,
  `packages/server/src/routes/integrations.ts:164`, `IntegrationsView.svelte:545`,
  `source-state.test.ts:128`: busy → counts → refresh. Cloud integration и raw
  exception reflection не нужны локальному Sync.
- [yaml-elixir 2.12.2 source](https://github.com/KamilLelonek/yaml-elixir/blob/4c5ee0408014a6e999dca4869e39eeca0e58a2c2/lib/yaml_elixir.ex),
  MIT; yamerl 0.10.0 commit `39981b9cb9d9edc227cf43a3e19dd16869493553`, BSD-2-Clause.
  Реальный parser используется с сохранением пар для проверки duplicate keys;
  type-erasing binary tags и aliases отклоняются до Mapper. Regression tests
  воспроизводят оба обнаруженных edge cases, atom creation отключён.
- [OTP file docs](https://www.erlang.org/doc/apps/kernel/file.html#list_dir_all/1):
  `list_dir` исключает raw names; `list_dir_all` включает их. BOSS отклоняет
  non-UTF8 имена вместо молчаливого неполного scan. macOS сам запрещает такой
  filename (`eilseq`); Linux-specific тест остаётся непроверенным на Linux.

Запросы xerj: `frontmatter parse`, `scan duplicate identity`, `frontmatter`,
`ScanTargets`, `RegularFileExists`, `importPulledTasks`. Слабые попадания первых
запросов дополнены `rg` и чтением pinned source, не трактуются как доказательство.
Собственный код реализует patterns; чужие source/tests не копировались.


## BOSS-003b: polling и согласованное обновление UI

Запросы xerj `debounce watcher`, `debounce polling refresh watcher`, `serialPoll`,
`subscribe refresh stale request` проверены по исходникам; найденный planning doc
не считается доказательством реализации.

- Agent Orchestrator `7193eff4e08f1481944845ee058fe6fd18930b6d`,
  `packages/mobile/lib/session/serialPoll.ts:1`, `serialPoll.test.ts:27`: первый
  read сразу, следующий timer после завершения, продолжение после ошибки. Fixed
  interval с отменой медленного чтения может не дать применить ни одного результата.
- Тот же SHA, `frontend/src/renderer/hooks/useUpdateStatus.ts:31` и
  `useUpdateStatus.test.tsx:19/34/62`: подписка перед initial read, предыдущий
  snapshot при ошибке и защита от устаревшего ответа. BOSS использует стандартные
  LiveView async refs, один активный read и один ожидающий refresh.
- Kander `dea0ba6b885c39a56ee769223f7fa5c054e68c70`,
  `internal/tui/refresh.go:68`, `refresh_test.go:71`: объединение refresh requests,
  latest-result handling и сохранение предыдущих данных при ошибке.

BOSS не переносит React/IPC или filesystem watcher зависимости. Один связанный
OTP Task обходит проекты; lifecycle/DB остаются в существующем приложении.
Одинаковые counts не обозначают одинаковое состояние: публикуется каждый успех,
подавляются только повторные одинаковые ошибки. No-op сравнивает точные present
identity/path/source и не выполняет UPDATE. Полные чтения и settle pause остаются
под SQLite write lock; это обозначенный компромисс локального MVP.

## BOSS-004: task commands и immutable events

Запрос `transition expected state completion evidence` дал слабые updater/UI
попадания; `verifyClosureHead`, `transition stale expected revision` и
`TestDispatchIntentIdempotencyAndGlobalConflict` уточнены чтением pinned Kander
`dea0ba6b885c39a56ee769223f7fa5c054e68c70` (MIT):

- `internal/board/transaction.go:214` — expected revision/state перед изменением.
- `internal/board/dispatch_test.go:54/110` — concurrent identical intents возвращают
  одинаковый receipt; изменённый payload и stale completion отклоняются.
- `internal/review/disposition.go:196` и `internal/board/review_closure.go:431` —
  реальные Git/persisted review checks перед закрытием, без доверия одному verdict.

BOSS использует SQLite version/CAS, task-scoped command IDs и append-only events
в одной immediate-транзакции. File journal, dispatch authorization epochs и
полный review engine Kander не переносились. До появления собственных producers
все execution/success gates закрыты; caller evidence отвергается. Исходники
референса не копировались. Контракт: [TASK_WORKFLOW.md](TASK_WORKFLOW.md).

## BOSS-005: board, scoped details и native drawer

Запросы xerj: `TaskDetailDrawer` (miss), `drawer selectedTask`,
`Kanban drawer focus DialogContent`, `kanbanColumn`, `task detail revision history`,
`getTask taskId projectId`, `showModal focus return dialog`,
`kanban columns status group tasks`. Слабые результаты дополнены чтением source/tests.

- Agent Orchestrator (Apache-2.0),
  `7193eff4e08f1481944845ee058fe6fd18930b6d`,
  `backend/pkg/contract/kanban.go:5`, `packages/product-ui/src/SessionsBoardView.tsx:193`
  и `SessionsBoardView.test.tsx:93`: группировать реальные states, стабильные IDs,
  подписанные колонки. PR/mergeability семантика не заменяет BOSS completion gates.
- Backlog (Apache-2.0), `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`,
  `packages/server/src/routes/tasks.ts:187`, `board-multi-project.test.ts:26`:
  project-scoped detail lookup. `packages/board-ui/src/lib/DialogShell.svelte:23`
  не принят: одного aria-modal недостаточно для modality/inert/focus. Drag/drop
  из App/Column не нужен read-only доске.
- Kander (MIT), `dea0ba6b885c39a56ee769223f7fa5c054e68c70`,
  `internal/board/snapshot.go:21`, `snapshot_context_test.go:36/196`: coherent read.
  BOSS использует deferred SQLite transaction на одном Repo PID; файловые locks
  и полный board/run snapshot не нужны.
- Agetor (MIT), `fbd68603afef778a618a94ca88e0c00997956afd`,
  `src/mainview/components/ui/dialog.tsx`: label/Escape/focus return. Собственный
  focus trap не переносится; выбран native `<dialog>.showModal()`.
- [MDN dialog](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog)
  и установленный LiveView `lib/phoenix_live_view/js.ex:1050`:
  `JS.ignore_attributes("open")` сохраняет native modal при обновлении содержимого.
  [Tailwind has](https://tailwindcss.com/docs/hover-focus-and-other-states#has)
  расширяет общий layout только при наличии board, в том числе после live navigation.
- LiveView `assets/js/phoenix_live_view/dom.ts:637` и `dom_patch.ts:477` сохраняют
  focused SELECT вместе с атрибутами. Поэтому desired revision хранится на dialog,
  а `updated` hook синхронизирует value без смены фокуса или нового change event.
  Необходимость подтверждена browser Back/Forward regression.

Код референсов не копировался; зависимости не добавлялись. UI показывает saved
snapshot и latest source отдельно, последние 50 transitions, escaped Markdown;
никакие agent/check/review данные не выдумываются.

## BOSS-006: локальное обнаружение CLI

Запросы xerj: `detect agent cli version capability`, `detectCodex auth status`
дали слабые общие попадания; `probeVersion`, `codexLoginMethod`,
`claudeAuthReportFromOutput` уточнили конкретные источники. UI query
`agent detect version authentication capabilities installed cli` привёл к
`agent-select-options.test.ts`; каждое решение проверено по source/tests.

- Agetor MIT `fbd68603afef778a618a94ca88e0c00997956afd`,
  `src/bun/agent-status.ts:89/430`, `agent-status.test.ts:44`: короткий probe и
  отдельное неизвестное auth-состояние. Не переносим available=true для /bin/echo,
  чтение account/auth files, переопределение HOME или tmux-зависимость.
- Agent Orchestrator Apache-2.0 `7193eff4e08f1481944845ee058fe6fd18930b6d`,
  `backend/internal/adapters/agent/claudecode/auth.go:372`, `auth_test.go:139`:
  credentials configured не означает authorized. `agent/codex/codex.go:320`
  и `codex_test.go:73` показывают local status и unknown при непонятном ответе.
  Credential-file/network fallback и account enrichment не нужны BOSS.
- Тот же AO SHA, `frontend/src/renderer/lib/agent-select-options.ts:108`,
  `agent-select-options.test.ts`, `CreateProjectAgentSheet.test.ts:199`:
  configured/unknown показывать отдельно от verified availability. Не переносим
  ranking, role selection или разрешение запуска из этой UI-модели.
- `backend/internal/process/command.go:23`, `tree_test.go:17` демонстрируют
  явную process-group ownership. BOSS metadata Port пока очищает только direct
  child; это не доказательство полноценной очистки потомков production runner.
- Проверены реальные `--version`/`--help` у Codex 0.146.0 и Claude Code 2.1.142,
  Codex `exec --help`/`login --help`, Claude `auth --help`/`auth status --help`.
  [Codex reference](https://developers.openai.com/codex/cli/reference/) и
  [Claude reference](https://code.claude.com/docs/en/cli-reference) дополняют
  installed help; новые онлайн-флаги не приписываются старому бинарнику.

Код референсов не копировался, зависимости не добавлялись. Локальный status не
доказывает доступ к модели/квоту; CLI-help не доказывает working adapter. Детали
контракта и ограничений — [AGENT_DETECTION.md](AGENT_DETECTION.md).


## BOSS-007a: demand-driven transport and lifecycle boundaries

Before implementation, xerj query `process stdout stderr backpressure EOF cancellation`
located Agent Orchestrator's process wrappers. `ConfigureTreeCancellation WaitDelay`
then located `backend/internal/process/command.go`. At pinned Apache-2.0 SHA
`7193eff4e08f1481944845ee058fe6fd18930b6d`, read
`backend/pkg/agentruntime/process.go`, `backend/internal/process/tree_unix.go`
and `backend/internal/session_manager/workspace_cleanup.go`. Adopt independent
stream/exit observations and explicit group cleanup; reject treating leader exit
or a forced pipe-close timeout as success. Source patterns were not copied.

Two additional clean read-only snapshots are pinned in
[repositories.json](../examples/repositories.json):

| Candidate | Source evidence | Decision for this slice |
|---|---|---|
| Exile 0.15.0, Apache-2.0, `a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413` | `lib/exile/process.ex:468/548`, `c_src/exile.c:258/330`, `test/exile/process_test.exs:89/103`: separate demand reads and actual zero-byte read EOF. `await_exit` closes caller-owned pipes. `c_src/spawner.c:199` execs the command; `lib/exile/watcher.ex:26` watches only a direct PID. | Separate one-credit readers passed the isolated 12-test fixture suite. Do not select it as the production runner or infer EOF from await/close. |
| NetRunner, Apache-2.0, `5f12e06aabb70f2aafde023bf547aaaa6f8fcb36` | `c_src/shepherd.c:492/700`: native guardian observes BEAM connection loss, but escalation waits only for the direct child; normal exit does not clear a macOS process group. `cgroup_cleanup` logs failures without a cleanup-result acknowledgment. `test/robustness_test.exs` includes manually killed orphans. | Useful ownership reference, not a complete solution to stubborn children after leader exit or helper death. No dependency or runtime comparison added. |

Versioned Exile source: [Process API](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/lib/exile/process.ex),
[NIF](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/c_src/exile.c),
[tests](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/test/exile/process_test.exs).
NetRunner [guardian](https://github.com/nyo16/net_runner/blob/5f12e06aabb70f2aafde023bf547aaaa6f8fcb36/c_src/shepherd.c)
and [robustness tests](https://github.com/nyo16/net_runner/blob/5f12e06aabb70f2aafde023bf547aaaa6f8fcb36/test/robustness_test.exs).

Exile's default GenServer state retains arguments/environment and pending writes;
no `format_status` redaction was found. Its socket binds directly under `System.tmp_dir` without creating its own
private directory; platform directory permissions and peer identity need review.
These need separate secret-handling/ownership validation before any
real prompts or credentials. A wrapper cannot sanitize a dependency's own crash
report. Public Port exit status also cannot distinguish every explicit exit code
from a signal-derived code; do not decode 137 as proven SIGKILL. This experiment
uses only public synthetic fixture data.

The reference reindex command refused before walking/writing because the existing
node reached its 95% disk flood-stage watermark (45.8 GB free). Old `bossrefs`
queries still succeeded, but the new snapshots are **not indexed**. Read the new
sources directly with `rg` until disk capacity is resolved and reindex can run.
No watermark was weakened and no unrelated index or data was deleted.

Production acceptance still needs OS ownership beyond direct PIDs, descendant
cleanup after leader exit, backend/helper failure handling, private IPC/redaction,
and committed launch intent plus safe reconciliation. Process groups alone do
not contain a child that creates a new session. Transport exit/EOF cannot stand
in for adapter completion, checks, review or verified delivery.

The [transport experiment](../spikes/transport/README.md) passed 12 local macOS
tests. With ACKs withheld, producer progress plateaued and sampled queues stayed
empty; sustained drain kept reader stacks constant after a meaningful RED/GREEN
regression. Exit notification was delayed with descendant-held pipes, so the
proof checks actual parent death and exact late bytes instead of assuming a
notification order. These results do not approve a production runner.

## BOSS-007b: manual Codex attempts

Search `launch run worktree process group` in `bossrefs` produced weak matches;
read pinned source instead. Agetor `fbd68603afef778a618a94ca88e0c00997956afd`,
`src/bun/codex-tmux.ts:123-166` supplies the Codex event vocabulary. Adopted bounded
allowlisted metadata; rejected forwarding raw tool/model output. NetRunner
`5f12e06aabb70f2aafde023bf547aaaa6f8fcb36` shepherd ownership and Agent Orchestrator
`7193eff4e08f1481944845ee058fe6fd18930b6d` Unix process-group cancellation informed
an independently implemented macOS guardian. Retaining the unreaped leader closes
PGID reuse before cleanup; process-group proof is explicitly narrower than all
arbitrary detached descendants. No reference code became a runtime dependency.
Workspace patterns use saved immutable base/branch/path intent and ordinary Git
worktrees; review rejected executable filters/conditional includes rather than
executing unknown checkout commands. Branch reviews and precise source/test
pointers are in the 2026-10-26 writer worklogs. The newer Exile/NetRunner corpus
update remains blocked by the shared xerj disk watermark; no indexing claim.

## BOSS-013a: candidate-bound checks

`xerj search --prefix bossrefs verifyClosureHead -k 3 --full 2200` found Kander
`dea0ba6b885c39a56ee769223f7fa5c054e68c70` (MIT),
`internal/review/disposition.go:196-205`, repeated at237, and dirty-closure test
`internal/review/disposition_test.go:60-70`. Adopt exact clean target checks on both
sides of long-running work; reject importing the full role/closure protocol.
Independent implementation additionally rebuilds a private index to detect tracked
edits hidden by index flags. No competitor code copied. The existing four bossrefs
corpora remain searchable; Exile/NetRunner indexing still awaits disk capacity.

## BOSS-014a: strict independent review

Searches used the existing authenticated `bossrefs` index: `review verdict schema`,
`verifyClosureHead`, `DecodeReviewJSON`, `FinalizeReviewRun`,
`reviewValidationError`. Weak lexical matches were followed by direct `rg` and
source/test reads. The index map still records the four original repositories;
Exile/NetRunner remain outside that index. A fresh disk check reports 96% used,
44 GiB available; no flood-stage bypass, unrelated deletion or reindex was attempted.

| Reference and pinned license | Useful source/test | Applied in BOSS / omitted |
|---|---|---|
| Kander `dea0ba6b885c39a56ee769223f7fa5c054e68c70`, MIT | `internal/review/validate.go:130–209`, `execute.go:103–126`, `codex_test.go:172–211` | Fresh read-only reviewer, exact candidate check before and after cleanup; reused BOSS's stronger fresh-index verifier. No role/launcher framework. |
| Same Kander snapshot | `internal/board/review_findings.go:43–78,157+`, duplicate-key regression `review_gate_test.go:396–413` | Preserve JSON pairs until duplicate/unknown-key rejection; bounded exact schema and criterion/issue consistency. No Markdown-fence extraction, legacy interpretation or finding ledger. |
| Same Kander snapshot | `internal/board/reviews.go:28–49,77–95,502–569`, `review_crash_test.go:22–90,139–161` | Immutable invocation pins; execution status distinct from verdict; final receipt after actual cleanup. No raw transcript archive. |
| Agetor `fbd68603afef778a618a94ca88e0c00997956afd`, MIT | `src/bun/github.ts:627–637`, `github.test.ts:220–231` | Small allowlist and mandatory actionable rejection; no GitHub submission or PR model. |
| Agent Orchestrator `7193eff4e08f1481944845ee058fe6fd18930b6d`, Apache-2.0 | `backend/internal/adapters/reviewer/codex/codex.go:49–67,123+` | Enforced read-only CLI flag. Omitted auto permissions, review publication and resumed developer context. |

These patterns were independently implemented in Elixir; no competitor modules
or code were copied and no runtime dependency was added. Reference applications
and their test suites were not executed.

Official Codex source for the installed 0.146.0, tag `rust-v0.146.0`, commit
`e363b08c9175ac1cbe5893615dd2cb9ddf95043b`, clarified an important limit:
[`exec_events.rs:138`](https://github.com/openai/codex/blob/e363b08c9175ac1cbe5893615dd2cb9ddf95043b/codex-rs/exec/src/exec_events.rs#L138)
has no final-answer phase in JSONL agent messages. The
[JSONL output processor](https://github.com/openai/codex/blob/e363b08c9175ac1cbe5893615dd2cb9ddf95043b/codex-rs/exec/src/event_processor_with_jsonl_output.rs#L514)
allows last-message output after completed turns, clears it on failure/interruption,
and writes it at shutdown. The
[writer](https://github.com/openai/codex/blob/e363b08c9175ac1cbe5893615dd2cb9ddf95043b/codex-rs/exec/src/event_processor.rs#L31)
may produce an empty file or merely log a write failure. BOSS therefore validates
the explicit output artifact after protocol/exit/EOF/cleanup, rather than guessing
which streamed message is final. This does not prove a `final_answer` phase or
model correctness. Only local help/source and finite fixtures were verified.
