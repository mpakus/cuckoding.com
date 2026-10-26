# BOSS — план нового проекта

Дата: 2026-10-25. Основа: [BOSS_PLAN.md](../BOSS_PLAN.md).
Статус: Git/runner эксперименты, Phoenix/SQLite, проекты, revisions, автоматический
Sync specs, persisted task commands, read-only board/drawer и CLI detection. Ручные Codex attempts на macOS теперь доступны в task drawer;
проверки/review/integration и workflow evidence gates остаются закрыты.
Задачи: [todo.md](todo.md). Источники: [RESEARCH.md](../docs/RESEARCH.md).

## Вывод

План задаёт правильную основу: локальный детерминированный координатор,
существующие CLI, Git worktrees, независимое review и проверяемый результат.
Elixir/OTP + Phoenix LiveView + SQLite соответствует этой задаче. Перенос старой
архитектуры Cuckoding не нужен: BOSS строится отдельными проверяемыми проходами.

Полный v0.1 — уже значительный продукт. Самый рискованный участок — управление
процессами и переходами между БД, Git и агентом. Его надо доказать до расширения UI.
Список модулей и таблиц в исходном плане — ориентир, а не список заготовок,
которые нужно создать сразу. Создаём контекст при появлении первого потребителя.

## Что уточнить в реализации

| Пробел исходного плана | Рабочее решение / проверка |
|---|---|
| Security и recovery стоят в Phase 5 | Loopback, сессия, CSRF, WebSocket origin — с BOSS-001; reconciliation и отмена — с первым runner. В Phase 5 остаётся расширенная проверка и упаковка. |
| Review может устареть после изменения кода | Checks и review фиксируют spec revision, base SHA, candidate SHA и конфигурацию проверок. Изменение любого из них инвалидирует относящееся к нему одобрение. |
| SQLite-транзакция не охватывает запуск процесса или Git | Сначала сохранить намерение и attempt ID, затем выполнить эффект, затем записать результат. После сбоя сверить эффект; не запускать повторно по одному статусу `running`. |
| PID не является устойчивой идентичностью процесса | Хранить attempt ID, PID, время старта и подтверждённую принадлежность. Не посылать сигнал произвольному PID после рестарта. Неизвестный исход → attention, не success. |
| Процесс завершился, но последнее событие ещё не прочитано | Завершать run после EOF обоих потоков и exit status; отдельно валидировать терминальный протокол адаптера. Ограничить размер строки/буфера и поток событий. |
| В модели нет постоянной истории переходов и результатов checks | Добавлять task events и check results вместе с первым workflow. State + transition event — одна транзакция. JSONL — экспорт/диагностика, БД — источник истины. Полное event sourcing не требуется. |
| «Ready to Merge» неоднозначен | По умолчанию manual integration: `ready_to_merge` ждёт действия, не считается Done и не разблокирует зависимые задачи. Done — только после интеграции и проверок результата. |
| Постинтеграционный тест падает уже после изменения target | Сначала собрать merge candidate в отдельном integration worktree и проверить. Публиковать только при совпадении ожидаемого target; сохранять before/after SHA. Если проверка после публикации упала — blocked, без автоматического reset пользовательской ветки. |
| Два экземпляра Boss / два Project указывают на один репозиторий | Первый MVP допускает одного владельца data directory. Идентичность репозитория определяется canonical Git common directory; очередь интеграции общая для его worktrees. Второй владелец получает явную ошибку. |
| Предсказанные file scopes не гарантируют безопасность | Сначала один worker; затем максимум 2 по плану. DAG + одна integration queue обязательны. Известные пересечения сериализуются; неизвестные scopes показывают риск, merge checks остаются обязательными. |
| Importer не определяет rename/delete/дубликаты ID | Explicit ID уникален внутри проекта; без ID ключ — относительный путь. Rename без ID — новая identity. Delete помечает missing, сохраняет историю; активный snapshot неизменяем. Ошибка одного файла не стирает предыдущий импорт. |
| Повтор A → B → A нельзя потерять из-за уникальности hash | Новая ревизия создаётся при изменении текущего содержимого. Hash обнаруживает no-op, но не заменяет последовательность revisions и stable spec identity. |
| Pause/Resume обещают больше возможностей, чем есть у CLI | Pause останавливает выдачу новых runs; текущий заканчивает шаг. Stop отменяет process group и сохраняет worktree. Resume продолжает разрешённый persisted шаг; session resume доступен только при capability адаптера. |
| Новый проект vs existing Git | Первый проход — existing Git с хотя бы одним commit. Для unborn/не-Git папки показывать причину. Создание репозитория — отдельный последующий сценарий. |

Это правила реализации; проверенные части отмечаются в `todo.md` и `.worklog/`.
Исходный BOSS_PLAN.md сохранён без изменений.

## Минимальная архитектура

- Один Phoenix/OTP application, один Ecto Repo на SQLite, один владелец БД.
- `Boss.Projects`: проверенный путь Git, spec identity, revisions, импорт.
- `Boss.Tasks`: task state, разрешённые переходы и сохранённые причины.
- `Boss.Agents`: два явных адаптера, детектор и runner. Общий интерфейс только
  по реально используемым операциям; никаких подключаемых plugin registries.
- Coordinator появляется вместе с первым run; DynamicSupervisor управляет
  жизненным циклом. Durable решение хранится в БД, PubSub обновляет интерфейс.
- Git и review выделяются при реализации соответствующего рабочего прохода.
- UI сначала: выбор папки проекта, board, детали task и понятные ошибки.
  По уточнению пользователя пути выбираются системным диалогом на машине BOSS;
  browser показывает их read-only. Локальный supervised helper вызывает macOS
  chooser или Linux Zenity, без desktop wrapper. Выбор хранится на сервере,
  регистрация повторно проверяет Git и границу specs внутри проекта.

Не создавать сразу все 11 таблиц из исходного плана. В первой цепочке нужны
projects, stable spec identity, revisions, tasks и task events; runs/checks/reviews
добавляются по мере реализации gates. Agent capabilities можно сначала хранить
как результат probe и snapshot в run, без отдельного справочника агентов.

## Решения о зависимостях

- `ecto_sqlite3` — Ecto adapter; `Exqlite` — нижележащий driver. Указать оба уровня
  правильно; не писать собственный SQLite adapter. Короткие транзакции,
  ограниченная конкуренция записи, тесты busy/rollback.
- Обычный Markdown хранится как текст. Markdown parser нужен при рендеринге,
  frontmatter parser — при включении optional metadata; не писать YAML regex-парсер.
- Ручной Sync реализован с yaml_elixir 2.12.2/yamerl 0.10.0. Полный bounded scan
  и запись выполняются в одной immediate-транзакции; explicit ID сохраняет identity
  при move, missing не стирает history, task остаётся pinned. Polling с debounce
  использует один owned sweep: повтор через 2 секунды после завершения, changed
  source проверяется повторным полным scan через 300 ms. No-op не пишет в БД.
  `FileSystem` добавлять,
  только если polling не удовлетворяет проверяемому требованию.
- Прямой supervised process — первый кандидат. `ex_cmd` проверяется spike:
  backpressure полезен, но его public stream options не доказывают независимый
  захват stderr и убийство всего дерева. Выбор Port/ex_cmd — после теста, не сейчас.
- tmux, ACP, desktop shell, workflow canvas, remote workers и plugin marketplace
  не нужны для первого полного прохода. Без tmux не обещать автоматическое
  переподключение к stdout процесса после аварии backend.

Официальные источники: [SQLite adapter](https://hexdocs.pm/ecto_sqlite3/Ecto.Adapters.SQLite3.html),
[ExCmd stream](https://hexdocs.pm/ex_cmd/ExCmd.html).

## Порядок реализации

1. **Phase 0:** source research + runner/worktree spike. Реальный harmless run,
   split JSONL, stderr, exit, timeout, descendant cancellation и авария backend.
2. **BOSS-001 → 004:** минимальный Phoenix/SQLite; проект, revisions и task;
   идемпотентный импорт; persisted transitions. Защита loopback включена сразу.
3. **BOSS-005 → 010:** пользователь импортирует 3 specs, видит board; один Codex
   run в отдельном worktree; logs, Stop/Retry и честный interrupted после сбоя.
4. **BOSS-011 → 014:** architect → developer → checks → independent reviewer;
   отдельно обработать invalid verdict, changes requested, spec revision и лимит 3.
5. **BOSS-015 → 016:** DAG, максимум 2 workers и сериализованная интеграция.
6. **BOSS-017 → 018:** расширенная матрица восстановления, UX и macOS/Linux release.
   Базовые recovery/security к этому моменту уже существуют.

Критерий первого полезного результата: три spec создают ровно три устойчивые
карточки, одна задача проходит отдельный worktree и проверки, ошибка не маскируется
как Done. Полный MVP дополнительно требует независимого review и интеграции.

## Доказательства и открытые проверки

Первый проход закрепил Elixir 1.20.3/OTP 28, Phoenix 1.8.16, LiveView 1.2.13 и
ecto_sqlite3 0.26.0 в lockfile. `asdf exec` обходит конфликт Homebrew PATH.
Приложение имеет локальный вход, регистрацию проектов и backend API для хранения
spec identity, точного source text, append-only revisions и pinned task. Исходный
Git checkout не меняется. SQLite migrations стартуют под application-lifetime owner lock,
WAL инициализируется до открытия пула из двух соединений.

Git spike: 12 проверок, отказ при checked-out target и сохранение failed/dirty
worktrees. Runner spike: 14 проверок, один успешный harmless Codex 0.146.0 run,
Claude 2.1.142 capability probe. erlexec остаётся экспериментом: bounded mailbox,
независимый EOF и очистка всех потомков не доказаны. На историческом checkpoint006 coding runs ещё не были включены;
текущий ручной Codex проход описан в007b ниже. Bootstrap и проекты не зависят от выбора runner и были завершены
при открытом Phase 0 gate. BOSS-002b проверен 13 новыми тестами, включая отдельный
committed Repo restart, конкурентную запись и migration upgrade/down/up.
Markdown/YAML import и список specs добавлены в BOSS-003a, автоматический refresh
и startup rescan — в BOSS-003b. Основа BOSS-004 сохраняет state/version/event одной
транзакцией, проверяет stale commands, возвращает исходный receipt при replay и
сохраняет recovery target. Конкретный Repo PID закреплён на всю команду; смена
зарегистрированного Repo не переносит остаток операции в новый pool. Task events
неизменяемы; rollback миграции отказывается терять уже записанную историю.
BOSS-005 добавляет пять колонок, project-scoped task drawer, pinned/selected/latest
revisions и последние 50 events из одного согласованного DB snapshot. URL хранит
выбор; refresh, Back/Forward и reload его сохраняют. Source остаётся escaped text.
Poller и ручной Sync используют один importer, фактические
scans сериализованы SQLite. PubSub публикует только после завершения транзакции.

Application tests (181 passed, 1 Linux-only skipped) и compile/format проверены
после BOSS-006 на macOS. В BOSS-004 добавлены 13 policy + 7 context + 7 real-pool tests:
они проверяют
таблицу отказов, replay/CAS, rollback и restart. Positive run/check/review/integration
evidence ещё не производится: переходы, включая approved/done, закрыты и не
принимают caller-provided evidence. Полная проверка commit-bound evidence остаётся
за соответствующими рабочими проходами 006–016; контракт —
[TASK_WORKFLOW.md](../docs/TASK_WORKFLOW.md).

Assets.deploy повторно прошёл в BOSS-005. Browser подтвердил три карточки,
keyboard/Escape/focus return, URL revision history/reload, refresh при edit/rename/
missing/restore и отсутствие page overflow на 320/768/1024/1440 px. Исправлена
рассинхронизация focused SELECT при Back/Forward. Startup rescan/offline edit
проверены в 003b. В IAB снова появилась прежняя MutationObserver error без source
URL; атрибуция остаётся открытой. Другие браузеры не проверялись. Следующий
продуктовый проход — BOSS-007, production runner; его reliability gates остаются открыты.
BOSS-006 проверяет только локальные metadata/status по явному Detect agents:
Codex 0.146.0 и Claude Code 2.1.142 распознаны в browser smoke. Configured не равно
provider-ready, help flags не доказывают working adapter; usage остаётся Unknown.
Один supervised scan, time/output bounds, private scratch cwd, fixed argv и
redacted diagnostics. 17 новых backend + 5 UI tests, production assets и browser
keyboard/reload/320–1440 px проверены; нет model calls и credential-file reads.
Контракт и границы: [AGENT_DETECTION.md](../docs/AGENT_DETECTION.md).
Committed Repo restart и полный owned-server restart с offline edit проверены.
Linux, release packaging и end-to-end agent→review→integration остаются открыты.
Конкурентные repositories исследованы как source; их приложения и suites не запускались.

BOSS-007a выделен в отдельный fixture-only transport experiment:
[spikes/transport/README.md](../spikes/transport/README.md). Два bounded demand
reader проверяются отдельно от будущей process-tree ownership. Нельзя считать
закрытие pipe настоящим EOF или выводить сигнал из одного integer exit status.
Следующий gate — lifecycle: cleanup после выхода leader, backend/helper death,
подтверждение ownership/cleanup до retry и committed launch-intent recovery.
Exile/NetRunner source pinned; новый xerj index update отказал до записи из-за
95% disk flood-stage. Старые datasets доступны; новые источники читаются через rg.

Ключевые проверки до выбора runner: потеря backend после spawn до записи PID;
потомок, переживший родителя; stderr flood; invalid/oversized JSONL; долгий тихий
run; auth/quota error без бесконечного retry. До integration: target drift,
checked-out target, dirty checkout, конфликт и падение checks после публикации.

## BOSS-007b — ручной Codex запуск

Добавлены native macOS process-group guardian, durable admission/replay/recovery,
проверяемое создание Git worktree, bounded Codex JSONL и Start/Stop в task drawer.
Это первый ручной проход, отдельный от task workflow: завершённый CLI не даёт
Done, checks/review/integration evidence. Контракт и ограничения —
[MANUAL_RUNS.md](../docs/MANUAL_RUNS.md). Исторические ограничения 007a выше
относятся к Exile spike; новый guardian проверяется в application suite.
Следующий проход — проверяемые checks на retained workspace и привязка результатов
к конкретному Git commit, затем независимый reviewer. Linux/release и безопасное
разрешение interrupted quarantine остаются открыты.
