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
event schema, tests (5 файлов).

- [ ] Разрешённые переходы и task event сохраняются одной транзакцией;
  устаревшая команда и повтор completion не применяются дважды.
- [ ] Done требует commit-bound evidence; invalid/failed reviewer не даёт approval.
- [ ] `ready_to_merge`, cancelled, failed и interrupted не разблокируют зависимости;
  причины attention и разрешённые Retry/Resume определяются явно.

**Проверка:** table-driven transition tests, concurrency/CAS и rollback.
**Сбой:** сохраняется последнее подтверждённое состояние, ошибка возвращается вызывающему.

## Checkpoint 1

- [x] `mix test`, compile warnings, `mix format --check-formatted` проходят.
- [ ] Три specs, edit, повтор Sync, restart и недопустимый переход проверены.
- [x] Review текущего изменения выполнено; журнал содержит фактические результаты.

Application suite: 113 passed, 1 Linux-only skipped после BOSS-003b; последние отдельные проверки
spikes: 12 Git + 14 runner (предыдущий increment, их код не менялся).
Checkpoint 1 ещё не завершён: 004 и полноценный task board отсутствуют.
Ближайший проход: BOSS-004 persisted transitions + task events.
Runner reliability продолжать отдельным исследованием.

## Следующие рабочие проходы

Детализировать перед реализацией; не генерировать все модули заранее.

| Порядок | Tickets | Зависит от | Проверяемый результат / отказ |
|---|---|---|---|
| 1 | 005: board + task drawer | 003, 004 | Три карточки, revisions, keyboard navigation; refresh не теряет состояние. |
| 2 | 006–010: detector, runner, Codex, worktree, journal | 000, 004, 005 | Один isolated run, live events, Stop/Retry; crash → attention, source checkout цел. |
| 3 | 011–014: plan, Claude, checks, review loop | 006–010 | Неполная реализация отвергается, исправленная проходит; invalid verdict и 3 исчерпанных цикла блокируют. |
| 4 | 015: DAG и два worker | 011–014 | Independent tasks параллельны; cycle/missing/failed dependency запрещает запуск; повтор tick не дублирует run. |
| 5 | 016: integration queue | 015, Git spike | Один repo интегрируется последовательно; target drift, conflict и failed checks не дают Done. |
| 6 | 017–018: recovery matrix, packaging | 016 | Kill/restart на каждой опасной границе; fresh macOS/Linux установка и полный spec→review→integrate проход. |
