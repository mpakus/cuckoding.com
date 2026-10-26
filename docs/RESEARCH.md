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
