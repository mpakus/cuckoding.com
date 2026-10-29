# BOSS — задачи

Чекбокс означает проверенный результат. Детали решений — [plan.md](plan.md).
Отмечаем только выполненные acceptance checks; частичный эксперимент описываем отдельно.

## Подготовка

- [x] Прочитать новый BOSS_PLAN.md и текущую ветку без переноса старой архитектуры.
- [x] Проверить RTK/Ponytail и включить постоянный `.worklog/`.
- [x] Зафиксировать 4 reference repositories, SHA и лицензии; добавить отсутствующие.
- [x] Завершить xerj index и проверить retrieval по всем четырём репозиториям.
- [x] Записать source findings, пробелы плана и порядок реализации.

## BOSS-000a — доказать runner до выбора библиотеки

**Зависимости:** подготовка. **Область:** `spikes/runner/`, focused fixtures,
`.worklog/` (до 5 файлов; spike не является новым runtime framework).
**Цель:** выбрать простейший процессный adapter по фактическому поведению.

- [ ] Fake CLI: chunked/invalid JSONL, stdout+stderr, exit!=0, stall и
  descendant cancellation дают точный исход и ограниченную память.
- [ ] Backend crash не даёт ложного success и не запускает новый процесс,
  пока принадлежность старого процесса не выяснена.
- [x] Один harmless Codex run в scratch worktree даёт streamed event и exit;
  Claude capability probe записывает version/flags и не читает auth-файлы.

Эксперимент: `spikes/runner/`, 14 проверок macOS. erlexec пока не выбран для
production: transport mailbox и независимый EOF не доказаны; detached/stubborn
descendants могут пережить остановку. Отмена хранит явную причину, потому что
библиотека может вернуть exit 0. Два первых пункта остаются открыты.

**Проверка:** assert-based spike с timeout, затем opt-in live smoke;
результат и ограничения macOS/Linux записаны отдельно.
**Сбой:** остановить только собственную группу процессов, сохранить данные
диагностики без секретов, не повторять provider invocation автоматически.

## BOSS-000b — Git spike

**Зависимости:** подготовка. **Область:** `spikes/git/`, `.worklog/` (до 3 файлов).

- [x] Scratch repository: два worktree на записанных SHA; исходный checkout неизменен.
- [x] Повторное открытие сохраняет commits; dirty worktree не удаляется.
- [x] Конфликт и target drift блокируют интеграцию; проверяется policy для
  target branch, уже checked out в пользовательской папке.

Доказательство: 12 real-Git tests и mutation checks. Уже checked-out target
отклоняется обычным `git worktree add`; очередь и crash recovery ещё не реализованы.

**Проверка:** настоящие throwaway Git repos, argv arrays, assert-based сценарии.
**Сбой:** сохранить failed worktree; никакого reset/clean существующих репозиториев.

## Checkpoint 0

- [ ] Runner выбран по spike, ограничения записаны, source references найдены.
- [x] Безопасная integration policy сформулирована до реализации очереди.

Независимый bootstrap/project слой готовится при открытом runner gate.
Запуск coding agents в приложении до его закрытия не включать.

## BOSS-001a — Phoenix + SQLite bootstrap

**Зависимости:** Checkpoint 0. **Область:** стандартные файлы `mix phx.new`,
`mix.exs`, lockfile, config, Repo, `.tool-versions`. Исключение по числу файлов:
generator создаёт согласованный skeleton; ручные feature-заготовки не добавлять.

- [x] Совместимый Elixir/OTP закреплён; Phoenix LiveView и SQLite запускаются
  без внешней БД, артефакты приложения лежат в пользовательском data directory.
- [x] Сервер слушает только loopback; restart сохраняет SQLite данные.

**Проверка:** `rtk mix test`, `rtk mix compile --warnings-as-errors`, local boot.
**Сбой:** ясная ошибка конфигурации/занятого data directory, без удаления БД.

## BOSS-001b — доступ к локальному приложению

**Зависимости:** 001a. **Область:** endpoint/router/session/bootstrap + focused tests
(до 5 файлов).

- [x] Browser session проходит локальный bootstrap; mutating endpoints требуют
  session/CSRF; WebSocket проверяет origin; произвольный сайт не может запускать CLI.
- [x] Закрытие вкладки не останавливает backend, повторное открытие восстанавливает UI.

**Проверка:** Phoenix request/LiveView tests и browser smoke чужого Origin.
**Сбой:** отказ в доступе, без side effect. Токены не пишутся в логи.

Одноразовый bootstrap token выводится только в терминал владельца. Request logs
фильтруют token/CSRF/session. Real HTTP/WS probes и IAB login/reopen проверены.
Неатрибутированная MutationObserver ошибка IAB отмечена в worklog; clean-console
и отдельный Chrome/Firefox acceptance не заявляются.

## BOSS-002a — проекты

**Зависимости:** 001b. **Область:** project schema, context, migration, tests (4 файла).

- [x] Принимается только доступный Git repository с проверенным base ref;
  canonical root/common Git directory препятствует дублированию одного repo.
- [x] specs path остаётся внутри выбранного проекта; traversal/symlink escape
  отвергается; unborn repository получает понятную ошибку.

**Проверка:** focused ExUnit с temporary repos, включая linked worktree.
**Сбой:** ошибка changeset без частичной регистрации.

Добавлен минимальный LiveView consumer: список и форма проектов, inline errors,
сброс после успеха. 8 core + 5 UI тестов; реальные browser/restart сценарии.
Это узкое расширение области 002a, а не реализация task board 005.

- [x] Repository и specs выбираются через OS dialog, поля путей read-only.
  Server-side selection нельзя заменить form params; cancel/error сохраняют
  форму. Один диалог, timeout и остановка owned helper при потере caller.
  7 helper tests + 5 LiveView tests; полный application suite — 39 passed.
  macOS browser показал путь, возвращённый настоящим chooser. Автоматический
  выбор/Cancel в окне osascript и Linux GUI acceptance не подтверждены.

## BOSS-002b — spec identity, revisions и task

**Зависимости:** 002a. **Область:** spec/revision/task schemas, Projects context,
migration, domain + durable-pool tests (7 implementation/test файлов).

- [x] Уникальная identity внутри проекта, неизменяемые revisions;
  original text отдельно от будущих plan/refined text.
- [x] Task связан с конкретной revision; explicit ID conflict не сливает задачи.

**Проверка:** schema/constraint tests, rollback и roundtrip после перезапуска Repo.
**Сбой:** транзакция откатывается целиком; существующая history сохраняется.

`Projects.record_spec/2` сохраняет одну observation, `list_spec_revisions/1` читает
историю. 10 domain tests + 3 проверки на отдельной SQLite-базе с реальным pool:
A→B→A, no-op, pin/title, conflicts, rollback, cross-spec FK, immutable history,
8 одновременных вызовов, committed Repo restart и migration down/up. Удаление
каждого из UPDATE/DELETE guards по отдельности было обнаружено тестом.
В 002b завершён backend persistence; чтение Markdown/YAML, rename/delete и UI
добавлены следующим проходом 003a.

## BOSS-003a — синхронизация Markdown

**Зависимости:** 002b. **Область:** importer, parser/dependency, missing migration,
context, supervised workers и ручной Sync UI. Область расширена до 16
implementation/test файлов: отдельные parser/UI writers, общий storage у parent.

- [x] Три `.md` → три tasks; повторный ручной Sync → без дублей.
  Автоматические проверки добавлены в следующем проходе 003b.
- [x] Edit и A→B→A создают корректную последовательность revisions; активный
  snapshot не меняется; delete сохраняет history и помечает missing.
- [x] Rename без ID создаёт новую identity; rename с ID сохраняет её;
  duplicate IDs/нечитаемый файл не вызывают массовое удаление tasks.

**Проверка:** focused importer tests с настоящими временными файлами.
**Сбой:** ошибка файла видна, предыдущая валидная revision остаётся.

19 parser tests, 14 importer tests (ещё один Linux-only пропущен на macOS),
5 real-pool persistence tests и 7 новых UI tests. Complete scan и reconciliation
сериализованы одной immediate-транзакцией; пределы traversal/bytes/parser/worker
проверены. После interrupted outcome UI перечитывает БД. Browser: три specs,
повторный Sync, edit/pinned snapshot, missing, duplicate-ID error/retry, reload;
в текущем IAB прогоне нет console errors/warnings. Source никогда не перезаписывается.
YAML priority/depends_on остаются source-only; board/execution не включены.
Polling добавлен отдельным проходом 003b ниже.

## BOSS-003b — автоматический refresh

**Зависимости:** 003a. **Область:** polling worker, importer no-op/settle,
app/config, LiveView notifications и focused/real-pool/UI tests (10 code/test файлов).

- [x] Изменение `.md` обнаруживается автоматически с debounce; burst событий
  не создаёт дублей и не запускает две одновременные синхронизации проекта.
- [x] Restart делает безопасный rescan, ошибка доступа не считается удалением всех specs.

**Проверка:** timer/import integration tests; интервал вынесен в app config.
**Сбой:** показать проблему и повторить scan с ограниченной частотой.

10 watcher tests + 2 importer regressions + 2 real-pool checks + 5 новых UI tests.
Один owned sweep; интервал 2000 ms после завершения, повторное чтение изменённого
набора через 300 ms. No-op не меняет timestamps. Current worker может закончить
bounded import после остановки только watcher; старый sweep не переходит к
следующим проектам. Application shutdown завершает оба слоя до Repo.
Реальный browser smoke: import/edit/delete/error/recovery без ручного Sync,
затем stop → offline edit → restart → новая revision при прежнем task pin.
Три UI guard mutations и importer settle mutation обнаружены тестами.
IAB сообщил MutationObserver error без source URL; код приложения/bundle и
live_reload/live_view assets такого вызова не содержат, происхождение не установлено.

## BOSS-004 — разрешённые переходы

**Зависимости:** 002b. **Область:** transition module, Tasks context, event migration,
task/event schema, focused и real-pool tests (8 code/test файлов).

- [x] Разрешённые команды и task event сохраняются одной транзакцией;
  устаревшая команда и повтор команды не применяются дважды.
- [x] До появления producers все execution/evidence transitions, включая
  completion, закрыты. Поддельные flags/verdict/evidence не дают approval или Done.
- [ ] Done требует commit-bound evidence; invalid/failed reviewer не даёт approval.
  Положительный путь требует реальных producers из 006–016; пока проверен только
  отказ без них. Источники evidence и полноценный review loop не созданы.
- [x] `ready_to_merge`, cancelled, failed и interrupted не разблокируют зависимости;
  причины attention и разрешённые Retry/Resume определяются явно.

**Проверка:** table-driven transition tests, concurrency/CAS и rollback.
**Сбой:** transaction failure сохраняет последнее подтверждённое состояние;
при потере соединения исход может быть неизвестен — повторить тот же command ID/input.

Основа завершена: 13 policy + 7 context + 7 новых real-pool tests. Все 14 real-pool
tests проходят, включая upgrade/down/up, committed same-file restart, replay,
конкурентные команды и отказ downgrade при сохранённой истории. Отдельная regression
проверяет смену named Repo на копию committed DB: до PID pinning получалась task
без event; после исправления новый pool не меняется. Retry/resume сохраняют pin и
используют saved target; пока доступно только возвращение к `new`.
UI действий/запуск агентов отсутствуют; [контракт](../docs/TASK_WORKFLOW.md).

## BOSS-005 — board и task drawer

**Зависимости:** 003, 004. **Область:** Tasks detail read, board/drawer,
ProjectLive, hook/router/layout и focused/real-pool/UI tests (10 code/test файлов).

- [x] Три specs дают три карточки; все сохранённые states имеют ровно одну колонку.
- [x] Drawer показывает pinned/latest/selected source, current reason и настоящие
  последние 50 events; чужие task/revision не раскрываются.
- [x] URL, Back/Forward и reload сохраняют выбор; background refresh не закрывает
  drawer и не меняет selected revision при edit/rename/missing/restore.
- [x] Keyboard opening, native modal, Escape, возврат focus и горизонтальная
  прокрутка на узком экране проверены в браузере.
- [x] Wrong cached source, stale async results, cancelled reads, storage failure
  и concurrent task/source commits проверены regression tests.

8 detail tests, 1 новый real-pool snapshot test и 10 новых board LiveView tests;
22 focused UI tests вместе с прежними Sync checks. Native dialog без новой UI
зависимости; Markdown остаётся escaped text. Browser обнаружил focused SELECT,
сохранявший revision 2 при Back к pin 1; hook синхронизации прошёл повторную проверку.
Все состояния покрыты тестами, browser fixture использует реальные `new`/`needs_input`.
Execution controls, agent/run/check/review metadata и global light/dark polish
не добавлялись. Прежняя неатрибутированная IAB MutationObserver error сохраняется.

## Checkpoint 1

- [x] `mix test`, compile warnings, `mix format --check-formatted` проходят.
- [x] Три specs, edit, повтор Sync и restart проверены browser smoke в 003;
  недопустимые переходы проверены backend tests в 004.
- [x] Review текущего изменения выполнено; журнал содержит фактические результаты.

Application suite: 181 passed, 1 Linux-only skipped после BOSS-006; последние
отдельные проверки spikes: 12 Git + 14 runner (их код не менялся).
Storage/negative-transition и board проверки Checkpoint 1 выполнены. Ближайший
проход: BOSS-007 production runner с закрытием reliability gates. Positive quality gates BOSS-004 остаются
открыты до реализации producers; это не proof of Done.
Runner reliability продолжать отдельным исследованием.

## BOSS-006 — agent detector и capability probe UI

**Зависимости:** 005. **Область:** detector/metadata process lifecycle, AgentsLive,
Home navigation, application/router и focused fixtures/tests; без DB migrations.

- [x] Detect agents явно проверяет Codex и Claude, показывает path и распознанную
  version; отсутствующий/неизвестный CLI не выглядит готовым к работе.
- [x] Capabilities отражают только advertised help flags. Local auth status
  показывается отдельно от model/quota proof; непонятный ответ остаётся Unknown.
- [x] Нет чтения credential files, model/install/login/doctor команд или raw output
  в браузере/логах. Setup/sign-in guidance ведёт к официальным инструкциям.
- [x] Один scan, ограниченные время/output; timeout/overflow/caller down/shutdown
  освобождают owned direct child. Process-tree guarantees остаются runner gate.
- [x] Loading/busy/partial failure/retry и navigation проверены тестами; реальные
  metadata probes, keyboard/focus и narrow UI проверены в браузере.

17 backend tests и 5 Agents LiveView tests; root suite 181 passed / 1 Linux-only
skip. Реальный macOS browser detect: Codex 0.146.0 и Claude Code 2.1.142, оба CLI
сообщили configured; пять capabilities advertised, usage Unknown. Keyboard,
reload reset и 320–1440 px проверены. Прежняя IAB MutationObserver error остаётся
неатрибутированной. Direct-child cleanup проверен fixtures; descendant/VM crash
гарантии не заявлены. Role assignment, production adapters и запуск задач входят
в следующие проходы. Ближайший шаг — BOSS-007 с закрытием runner gates.

## BOSS-007a — проверка транспорта перед production runner

**Зависимости:** 006 и runner spike. **Область:** отдельный `spikes/transport/`,
fixtures, reference snapshots и документация. Application dependencies/UI не меняются.

- [x] Отдельные bounded stdout/stderr reads и настоящий EOF каждого потока.
- [x] Ранний EOF и уже завершившийся leader не теряют поздний inherited output;
  сохраняется реальный nonzero status без обещания порядка уведомлений.
- [x] Stalled consumer останавливает upstream output без растущей mailbox.
- [x] Stop/timeout отвечают при stalled consumer; forced closure не считается EOF.
- [x] Независимое review, macOS fixture suite, merge/verification/cleanup.

Local main `4f5a317`: 181 application tests прошли / 1 Linux-only skip;
macOS suite: 12 transport tests прошли. При withheld ACKs producer остановился
на 77,824 bytes, четыре sampled mailbox были пусты; при drain от 2 до 8 MiB
stack samples оставались `[20, 8]` words. Это fixture evidence, не whole-VM memory
proof. Независимые reader-failure / Stop-after-EOF / 100 sequential cancelled→binary
проверки прошли; integer exit не классифицируется как доказанный signal.

Производственный BOSS-007 остаётся открытым: process-tree ownership, backend/
helper death, безопасная identity/recovery и committed launch intent пока не
доказаны. Новый Exile/NetRunner source сохранён, но обновление xerj отказало до
записи из-за disk flood-stage; это не подтверждение индексации новых snapshots.
Подробности: [transport worklog](../.worklog/2026-10-25-runner-transport.md).

## BOSS-007b — первый ручной Codex run (macOS)

- [x] Durable admission/replay, pinned revision/base commit before side effects.
- [x] Fresh retained worktree; source checkout and local user edits preserved.
- [x] Native group owner, bounded stdout/stderr, EOF/exit/signal distinction.
- [x] Stop bypasses Manager/DB; requester death does not cancel the worker.
- [x] Restart quarantines unfinished attempts and never automatically relaunches.
- [x] Start/Stop/history/events in task drawer; keyboard/reload/320 px browser smoke.
- [x] Final native backpressure/recovery regression and combined main verification.

Local main9d567cb:238 passed,1 Linux-only skip; compile/format/assets.deploy passed.
Browser использовал только конечный fake CLI: Stop → retained edits и finished →
unverified, source checkout цел. Ни одного model call. Task state остаётся new;
checks, review, интеграция, Done и Linux runner здесь не заявлены. Контракт:
[MANUAL_RUNS.md](../docs/MANUAL_RUNS.md). После завершения этого прохода ближайшая
продуктовая задача — commit-bound checks для retained workspace.

## BOSS-013a — явные проверки immutable candidate

- [x] User command → normalized argv/config hash; общий admission/Stop/recovery.
- [x] Private-index snapshot сохраняет source HEAD/index/files; отдельный commit/ref/worktree.
- [x] Exact clean HEAD/ref/tree до/после command; index flags не скрывают edits.
- [x] Immutable parent/revision/config/candidate и idempotent replay без нового запуска.
- [x] Real-pool checks success/failure/Stop/Repo-loss/migration and UI/browser verification.
- [x] Independent review and combined local-main checks.
- [ ] Archive remaining app-held writer worktrees after Codex releases them.

Без автоматического запуска команд из repo/model и без provider calls. Один
explicit command на попытку; результат относится только к candidate SHA. Task
workflow/check approval/review/integration gates остаются закрыты. Контракт:
[MANUAL_CHECKS.md](../docs/MANUAL_CHECKS.md).

Local main `a42899e`: 264 passed, 1 existing Linux-only skip; compile/format/assets
passed. Browser verified passing checks, dirty-candidate exit-0 failure, reload,
Stop, keyboard and 320px layout using finite local fixtures only. All three merged
branches removed; UI worktree archived. Codex still refuses to archive the clean
snapshot writer and two previous writer worktrees as in use by another task.

## BOSS-014a — ручное review проверенного candidate

- [x] Source research through xerj; pinned source/test patterns and license recorded.
- [x] Explicit fresh read-only Codex request; immutable check/spec/config/candidate pins.
- [x] Bounded strict report, unique criteria and actionable issue coverage.
- [x] Shared Stop/quarantine; actual native fixture success/rejection/drift/Repo-loss.
- [x] Final storage regression, browser scenario and independent review.
- [x] Combined local-main verification, documentation and merged-branch cleanup.
- [ ] Archive two review writer worktrees after Codex releases their active-task hold.

Контракт — [MANUAL_REVIEWS.md](../docs/MANUAL_REVIEWS.md). Это model assessment по
saved spec/full diff/check receipt; refined plan, raw test output, automatic fix
loop, workflow approval и Done не заявлены. Provider calls остаются opt-in.

Local main `b365058`:293 passed,1 existing Linux-only skip (seed36841); compile,
format, assets.deploy and diff checks passed. Browser:approved/rejected report,
Stop after reload, keyboard/focus,320px, source/task preservation. All three merged
review branches deleted. Codex refused archival of both clean/detached review
writers and the three older worktrees as still used by another active task.

Этот исторический проход дополнен managed workflow ниже; отдельные manual
assessments по-прежнему не дают Done.

## BOSS-011/014b/016a — managed workflow, fixes и ручная интеграция

- [x] Typed Architect plan/criteria сохранены отдельно от pinned original source.
- [x] Полные source/plan/diff/check output/receipt/feedback в fresh review; raw output не хранится.
- [x] Исправление от rejected candidate, полный base diff, максимум 3 цикла и остановка повторной ошибки.
- [x] Ready только при matching evidence; ручной Integrate точного SHA, reservation/CAS и postchecks перед Done.
- [x] Освобождение target через detach собственного checkout; source/failed worktrees сохраняются.
- [x] Native real-Git/real-pool fixtures: replay, Stop, drift, checked-out target, postcheck failure, Repo/receipt loss.
- [x] UI: saved plan/report, Start/Stop/Integrate, unknown-request replay, late Stop и следующая задача после Done.
- [x] Итоговая browser/full-suite проверка, local main merge и уборка веток.
- [ ] Архивировать 3 delivery worktree после снятия Codex active-task hold.

Контракт: [MANAGED_DELIVERIES.md](../docs/MANAGED_DELIVERIES.md).
Проверки используют конечный fake CLI; реальные model calls не выполнялись.
macOS, один активный workflow, unchanged-target fast-forward. DAG/Claude/Linux,
divergent merge, automatic crash recovery и packaging пока не включены.

Local main `b4145ea`: root full suite361 passed/1 Linux skip (seed678162),
последние context/UI изменения30 passed (seed298435), combined main37 passed
(seed163005), включая7 реальных Git/SQLite/native integration scenarios.
Compile без warnings, format, assets и diff checks прошли. Browser показал
rejected→fix→Ready→Integrate→Done, повторное открытие, следующую задачу и Stop,
320px/focus. Четыре merged branches удалены. Три новых и пять старых чистых
writer worktree удерживаются Codex; force removal не выполнялся.

## BOSS-015a — готовность зависимостей перед Start

- [x] Strict depends_on sequence, literal project-local IDs and immutable source pins.
- [x] Reachable cycle/missing/invalid/limit detection; only Done satisfies an edge.
- [x] New manual/managed admission checks atomically before effects, after replay.
- [x] Drawer reasons/links and Start guards; unknown request reconciliation retained.
- [x] Focused regressions, independent review, browser/full-suite verification.
- [x] Merge local main, verify combined result and clean merged branches.
- [ ] Archive dependency writer worktrees after Codex releases them.

Один глобальный worker остаётся. Нет новых таблиц, автоматического scheduler,
provider calls или implicit revision adoption. Контракт:
[TASK_DEPENDENCIES.md](../docs/TASK_DEPENDENCIES.md).

Local main `3b2ece2`: full suite 391 passed / 1 existing Linux-only skip
(seed 100342); combined main 47 passed (seed 446152). Compile without warnings,
format, assets and diff checks passed. Browser verified Ready still waits,
Integrate/postchecks → Done unlocks the open dependent drawer, reload, new Start,
Stop, keyboard links and 320px. Three branches deleted. Two clean detached
worktrees remain app-held: Codex refused archive as used by another active task.

## Explicit task revision adoption

- [x] Atomic expected-version command, old/target revision receipt and exact replay.
- [x] Idle-task admission; Ready retirement; active/unknown/integration-intent refusal.
- [x] Historical check/review pins preserved by a constrained migration.
- [x] Explicit source action, immutable pending request, refresh and accessible drawer.
- [x] Focused durability/concurrency/UI tests, independent review and browser verification.
- [x] Combined local-main verification and merged-branch cleanup.
- [ ] Archive adoption writer worktrees.

Local main `21deb31`: full suite 416 passed / 1 existing Linux-only skip
(seed 756580); combined main 46 passed (seed 927416). Compile without warnings,
format, assets and diff checks passed. Browser verified Ready retirement,
dependency repair, two-tab refresh, active/Stop gating, historical checks/review,
reload/old-source selection and 320px/Escape focus. Three branches deleted;
two clean detached writer worktrees remain held by Codex's active-task check.
Restart the running BOSS server to apply the new startup migrations.

## BOSS-012a — выбор Claude reviewer в managed workflow

- [x] Reviewer сохраняется до effects; allowlist/immutable migration, точный replay.
- [x] Fresh-pool upgrade/restart/downgrade/quarantine verification.
- [x] Выбор reviewer, locked request и исторические labels; focused UI regressions.
- [x] Bounded Claude structured stream, native fixture pipeline/Stop and independent review.
- [x] Browser, combined suite, local main merge and merged-branch cleanup.
- [ ] Archive the two clean Claude reviewer worktrees after Codex releases them.
- [ ] Real-provider acceptance (отдельный opt-in).

Codex остаётся planner/implementer/fixer; manual Codex flow прежний. Claude
reviewer получает полные saved evidence без model filesystem/shell tools.
Контракт: [CLAUDE_REVIEW.md](../docs/CLAUDE_REVIEW.md).

Local main4319960: full suite448 passed/1 existing Linux-only skip(seed616578).
Only final account-copy/regression followed; focused root44 passed(seed616639),
combined main44 passed(seed342131). Compile without warnings, format, assets and
diff checks passed. Browser verified Claude rejection→Codex fix→Claude approval→
Ready→explicit Integrate/postchecks→Done, restart/history, Stop, keyboard and320px.
Three merged branches deleted. Both clean detached writer worktrees are retained:
Codex refused archive as another active task still uses them. No provider calls;
restart the running BOSS server for the new reviewer migration.

## BOSS-015b — явная очередь и два managed worker

Контракт: [WORKFLOW_QUEUE.md](../docs/WORKFLOW_QUEUE.md).

- [x] Durable queued/paused request, exact replay, cancellation and source/version pins.
- [x] Atomic dispatch, Done dependencies, bounded fair scan and restart pause/Resume.
- [x] Two managed workers; exclusive manual/integration; unknown-cleanup quarantine.
- [x] Explicit Queue UI, frozen uncertain action/input and persisted history.
- [x] Independent review, native process/SQLite tests, browser and combined full suite.
- [x] Merge local main, verify combined result and remove merged branches.
- [x] Archive the two queue writer worktrees (reused and archived during BOSS-016b).

Combined root suite:483 passed/1 existing Linux-only skip,seed276199,741.0s.
The first full run exposed a test-Sandbox timer leak; the final run includes its
closed-owner regressions. Native acceptance also exposed shared-directory mkdir
races, fixed with directory-only revalidation and independently proven mutation
tests. Browser verified queue/cancel/history, two processes, Stop freeing a slot,
restart pause/Resume, Ready waiting, Done dispatch and refusal after target drift.
Local main447754a: combined queue/native/LiveView lifecycle focus39 passed,
seed803248,38.8s. Compile, format, assets and diff checks passed. Three merged
branches removed. Both clean detached queue writer worktrees remain app-held:
Codex refused archive because another active task still uses them. No force removal.
Restart BOSS to apply the new queue migration; user server/data were not restarted
or modified by this development run.

No automatic divergent integration, typed file-scope prediction, configurable worker
count or actual provider calls in this increment.

## BOSS-016b — current-target merge evidence

- [x] Reference research and isolated two-parent Git candidate with conflict/driver guards.
  Native Git/workspace focus34 passed; independent review and guard mutation verified.
- [x] Immutable merge/check/review lineage and migration guards.
  Context/SQL and fresh pooled upgrade/restart tests:31 passed(seed50302).
- [x] Fresh saved-reviewer validation before expected-old target publication.
  Native Codex/Claude lifecycle + web:30 passed(seed530960); browser2 Done verified.
- [x] Native lifecycle, persistence, browser and combined-suite verification.
  Full combined suite510 passed/1 existing Linux-only skip,seed798224,816.5s.
- [x] Update contracts, merge local main and clean merged branches/worktrees.
  Main86873db:41 focused context/pooled/native queue/LiveView tests passed,
  seed852899,54.4s; compile/format/assets passed. Three merged branches deleted,
  both reused writer worktrees archived and confirmed absent from Git worktree list.

Restart BOSS to apply migration20261027050000. No real-provider calls or remote
publishing were performed. Next development increment:015c typed file scopes and
capacity controls, preserving explicit inputs and integration evidence.

## BOSS-015c — predicted file scopes и capacity1–3

- [x] Bounded typed scopes, legacy/null unknown, native wait before first write.
  Protocol5 passed(seed100900); parser mutation caught and restored.
- [x] Persisted capacity CAS, atomic claims, SQL quarantine/JSON/REPLACE guards.
  Backend21 passed(seed846041), real-pool concurrency/restart included; corrected
  raw SQL probes assert the intended guards, with independent mutation proof.
- [x] Capacity controls, saved predictions, true wait state, live release refresh.
  Full web127 passed(seed929551); browser capacity1→3, overlap wait/release,
  unknown warning, Stop, two-tab sync, reload and320px verified with finite CLIs.
- [x] Peer loss before first write and before a later fix preserves known own cleanup.
  Native lifecycle2 passed(seed11250,11.0s); isolated final native/SQL/pool18
  passed(seed213515,81.5s). Later-fix guard mutation failed, restored rerun passed.
- [x] Complete combined suite, final review and documentation evidence.
  Full535 passed/1 existing skip(seed418426,836.9s); final narrow worker/SQL
  refinements verified separately in native/SQL/pool18(seed213515).
- [x] Merge local main and verify the final combined result.
  Main b7e028a:39 passed(seed151074,77.7s), compile/format/assets/diff passed.
- [x] Delete three merged temporary branches.
- [ ] Archive the two clean detached scope writer worktrees. Codex refused twice
  because another active task still uses them, including after agent completion
  and primary reattachment. No force deletion; retry after its hold is released.

Scope predictions are advisory. Unknown scopes may still overlap; Unicode known
scopes serialize conservatively. Waiting uses a worker slot. No provider calls,
Linux acceptance or automatic quarantine recovery. Migration20261027060000 requires
BOSS restart. Contract: [WORKFLOW_QUEUE.md](../docs/WORKFLOW_QUEUE.md).

## Autopilot — текущий Backlog до Done

- [x] Atomic full-Backlog snapshot, exact replay, bounded dependency ordering.
- [x] Sequential existing delivery → review → integration → postchecks → Done.
- [x] Pause/Resume/Stop, restart pause and immutable SQL ownership guards.
- [x] Prominent project button, frozen uncertain inputs, saved progress and task links.
- [x] Native finite-CLI acceptance: dependency order, two verified Done commits,
  review rejection → repair, selected Stop and preflight refusal before model calls.
  Root3 passed(seed695059,100.7s); combined context/UI/native19(seed715326,105.6s).
  Backend42(seed669880), final Autopilot16(seed179266), full web135(seed411624).
- [x] Complete regression diagnosis, browser acceptance and final documentation.
  Browser:2 Done, review repair, Pause/Resume/reload and320px. Full561/565 passed,
  1 skipped,4 fixture failures(seed887626); after fixture-only fixes all4 reruns
  passed(seed610996), complete web/context/pool152 and upgrade pool21 passed.
  Compile/format/assets/diff passed. Full suite not repeated after fixture fixes.
- [x] Merge local main, verify and restart localhost:4000 with no active runs.
  Main dcf72f9:169 passed(seed352781,113.1s), compile/format/assets passed.
  Backup saved before migration20261027070000; actual project page shows button.
- [x] Delete all three merged temporary Autopilot branches.
- [x] Archive the engine writer worktree during BOSS-017c; app attachment and Git
  inventory confirm removal.
- [ ] Archive the remaining clean detached UI writer worktree. The app still refuses
  because another active task holds it; preserved safely.

The first combined run exposed stale fixture aliases and an incomplete legacy
migration fixture; both are fixed without weakening production gates. Combined
main acceptance passed169 tests. Real-provider calls remain opt-in.
Contract: [AUTOPILOT.md](../docs/AUTOPILOT.md).

## BOSS-017a — backend crash и recovery UI

- [x] Reproduce missing notifications and misleading refusal with10 failing
  regressions(seed290114); fix after top-level commit without weakening quarantine.
- [x] Real-pool rollback/commit/no-op and connected UI verification:59 passed,
  seed898791,10.5s. Manual, managed, queue and Autopilot recovery are covered.
- [x] Actual child BEAM SIGKILL during implementation and after publication;
  restart preserves history/checkout, stops owned descendants and refuses automatic retry.
  New backend2 + manual recovery1 + pooled Autopilot7 passed10(seed580569,35.6s).
  Removing startup pause failed both new tests(seed129180); source restored.
- [x] Independent review, combined focused acceptance and final documentation.
  Broader affected suites195(seed907420,102.9s); combined web/native/recovery173
  (seed675757,46.1s). Browser confirms Manager restart → Paused/Resume without
  reload or provider effects. Full suite not rerun for this increment.
- [x] Merge local main (`9f9042d`) and verify the combined result:53 passed,
  seed175589,40.5s; compile warnings-as-errors and format passed. Local server updated.
- [x] Delete both merged recovery branches; retain clean detached checkouts.
- [ ] Finish archiving the reused writer worktrees once the app releases its hold.
  Engine archived in017c; the older UI checkout is still held. No forced deletion.

## BOSS-017b — interruption versus completed approval

- [x] Kill the actual backend during plan/check/review; preserve earlier evidence,
  reject incomplete approval and retain cleanup quarantine without repeated effects.
- [x] Kill after a complete Ready result; restart preserves its exact report/commit,
  does nothing until explicit Resume, then integrates through existing gates.
- [x] Independent review and guard mutations: three unfinished-stage regressions
  fail with missing receipts; paused integration guard mutation fails the Ready case.
  Restored combined native/persistence18 passed(seed615806,86.8s); format, compile
  warnings-as-errors, Python AST and diff passed. Contracts updated.
- [x] Merge local main (`1e04ef8`) and verify: native6 + persistence11 passed17
  (seed277660,66.1s), format/diff passed; no recovery fixture VM remains.
- [x] Delete both merged temporary recovery branches.
- [x] Archive the clean detached reused engine writer worktree: completed in017c
  after the earlier app ownership hold was released.

## BOSS-017c — offline candidate и target drift

- [x] Native restart after dirty candidate/moved candidate ref: no stale publication,
  model/check rerun or change to the user's checkout.
- [x] Advanced target requires fresh merge/check/review and exact new SHA publication;
  rewritten target history blocks without repeating work or resetting Git.
- [x] Independent review, guard mutation and documentation. Final native10 passed
  (seed130744,168.1s); ancestry mutation caught the extra merge step
  (seed52840,16.4s), production restored. Baseline integration/persistence16 passed
  (seed777880,143.7s). Format/diff passed; no runtime changes.
- [x] Merge local main (`a018a9e`): Ready drift5 passed(seed910197,118.6s), merge
  persistence2 passed(seed485152,0.4s), compile warnings-as-errors/format/diff passed.
- [x] Delete both merged branches and archive the clean engine writer worktree.
  App reports archived; directory and Git registration are absent. No fixture VM remains.

## BOSS-018a — macOS0.1.0-rc.1

- [x] Audit release blockers and official build/runtime contracts. Bandit1.13.1
  advisory findings require1.14.1; npm audit found0 vulnerabilities.
- [x] Update only Bandit lock to1.14.1; Hex audit now reports no retired/advisory packages.
- [x] Assemble ERTS/guardian/assets/migrations with relocated native dependencies,
  notices, platform facts and source provenance.
- [x] Actual unpacked package smoke, isolated restart/durability and no-build-tools runtime.
  Parent clean-tree archive6d84f4 passed auth/assets, native guardian, dump suppression,
  restart/integrity and graceful stop. Production browser board/Autopilot/drawer
  connected without console warnings/errors; owned fixture stopped and removed.
- [x] Full integrated application regression:585 passed/1 skipped(seed329391,1023.8s).
  Independent packaging review approved; archive smoke/guard mutation, compile,
  format, Python AST and workflow validation passed.
- [x] Merge local main41efa84, rebuild clean-source RC and pass final unpacked smoke.
  Main compile/format passed; application/packaging/dependency sources exactly match
  the full-suite tree6d84f4. Artifact/checksum are recorded in2026-10-29 worklog.
- [x] Delete both merged release branches; original parent checkout detached at main.
- [ ] Archive the clean detached release writer. App refuses because another active
  task holds it; preserved without force deletion. No release/recovery fixture VM remains.
- [x] Project owner selected Apache-2.0; canonical root LICENSE and documentation added.
- [ ] Remote macOS CI, clean-machine/provider acceptance and public signing.
  Preparation is local; no tag/upload/publication is authorized by these checkboxes.

## BOSS-018b — Apache-2.0 selection

- [x] Add unchanged official ASF Apache-2.0 text; update project/release licensing docs.
- [ ] Independent byte-for-byte review, clean-main archive rebuild and smoke/checksum.
- [ ] Local merge and temporary branch cleanup. No public tag/push/release.

## Следующие рабочие проходы

Детализировать перед реализацией; не генерировать все модули заранее.

| Порядок | Tickets | Зависит от | Проверяемый результат / отказ |
|---|---|---|---|
| 1 | 012: provider acceptance | Claude reviewer 012a | Реальный opt-in проход с сохранёнными provenance/cleanup gates; никакого paid auto-retry. Claude implementer требует отдельной проверенной границы записи. |
| 2 | 017: recovery acceptance | 015c, 016b | Подтверждённый отказ/restart на каждой границе, без повторного платного запуска и без потери истории. |
| 3 | 018: packaging | 017 | Fresh macOS/Linux установка и полный spec→review→integrate проход. |
