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

## Следующие рабочие проходы

Детализировать перед реализацией; не генерировать все модули заранее.

| Порядок | Tickets | Зависит от | Проверяемый результат / отказ |
|---|---|---|---|
| 1 | 007–010: runner, Codex, worktree, journal | 000, 004, 006 | Один isolated run, live events, Stop/Retry; crash → attention, source checkout цел. |
| 2 | 011–014: plan, Claude, checks, review loop | 006–010 | Неполная реализация отвергается, исправленная проходит; invalid verdict и 3 исчерпанных цикла блокируют. |
| 3 | 015: DAG и два worker | 011–014 | Independent tasks параллельны; cycle/missing/failed dependency запрещает запуск; повтор tick не дублирует run. |
| 4 | 016: integration queue | 015, Git spike | Один repo интегрируется последовательно; target drift, conflict и failed checks не дают Done. |
| 5 | 017–018: recovery matrix, packaging | 016 | Kill/restart на каждой опасной границе; fresh macOS/Linux установка и полный spec→review→integrate проход. |
