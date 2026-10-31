# BOSS — план нового проекта

Дата: 2026-10-25. Основа: [BOSS_PLAN.md](../BOSS_PLAN.md).
Статус: Phoenix/SQLite, native folder selection, immutable source revisions,
автоматический Sync specs, task board/drawer, CLI detection и ручные Codex runs,
checks/review. Managed macOS workflow включает plan, checks, bounded fixes,
review, explicit integration и Done. При изменившемся target новый merge candidate
проходит сохранённые checks и свежий review до публикации. Pinned dependencies блокируют
новый Start до завершения prerequisite. Явная очередь сохраняет параметры и допускает
1–3 managed worker (default2); после restart ожидающие заявки требуют Resume. Manual runs и
интеграция остаются эксклюзивными. Явный Autopilot последовательно доводит текущий
Backlog до проверенного Done через те же delivery/integration gates. Linux/provider/recovery/release gates
остаются открыты; подробные verified increments приведены ниже.
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
| Предсказанные file scopes не гарантируют безопасность | Default2, configurable1–3. DAG + эксклюзивная интеграция обязательны. Известные пересечения ожидают до implementation; неизвестные scopes показывают риск, merge checks обязательны. |
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
evidence на том checkpoint ещё не производилось: переходы, включая approved/done, были закрыты и не
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

## BOSS-013a — явные проверки результата

Первый checks producer хранит source run, pinned spec, config hash и candidate SHA.
Пользователь явно задаёт команду; BOSS создаёт отдельный snapshot без изменения
исходного run и проверяет неизменность Git tree после завершения. Это ручной
receipt, не task transition или независимое review. Верификация, ограничения и
точный следующий шаг фиксируются в todo/worklog; контракт — MANUAL_CHECKS.md.

## BOSS-014a — ручное review проверенного commit

Отдельный свежий Codex reviewer получает сохранённый spec, полный base→candidate
diff и check receipt. Read-only sandbox, строгий JSON-отчёт, неизменность candidate
и общий Stop/recovery отделяют model assessment от workflow approval.
Refined plan, raw test output и автоматический fix-loop пока отсутствуют;
полный BOSS review gate не заявлен. Контракт — [MANUAL_REVIEWS.md](../docs/MANUAL_REVIEWS.md).

BOSS-014a проверен на local main b365058:293 application tests passed/1 Linux skip,
native CLI fixtures и browser smoke. Следующий проход возвращается к BOSS-011:
сохранённый typed Architect plan с критериями, без изменения original spec.
Только после полного набора producer evidence открывать workflow/fix-loop gates.

## BOSS-011/014b/016a — управляемый Codex workflow

Добавлен минимальный последовательный путь: typed read-only Architect plan,
реализация, immutable snapshot, заданные пользователем checks, независимый fresh
review и до трёх циклов исправления. Fix начинается от отклонённого commit;
review получает исходный spec, plan/criteria, полный diff от original base,
полные bounded check output/receipt и предыдущую обратную связь. Raw output
существует только в памяти. Исходный spec и старые worktree сохраняются.

Готовый результат ждёт ручного Integrate. Первый вариант — fast-forward точного
reviewed SHA при неизменном target, без checkout пользователя на этой ветке.
Сохранённый intent, резервирующий worktree, expected-old-SHA CAS и postchecks
предшествуют Done; собственный checkout затем detach с сохранением файлов.
После публикации ошибки не откатывают target. Unknown receipt/Repo loss дают
quarantine без restart/retry. Stale approval не переиспользуется.

Область включает shared delivery migration/context/task events/Manager,
независимые pipeline/Git/UI writers и связанные regression tests. Это осознанное
объединение зависимых producers для полного пользовательского результата, а не
реализация DAG, Claude, двух worker или divergent integration queue. Эти задачи,
Linux/provider/release acceptance и безопасное снятие quarantine остаются открыты.
Контракт: [MANAGED_DELIVERIES.md](../docs/MANAGED_DELIVERIES.md).

## BOSS-015a — зависимости перед явным запуском

Первый проход BOSS-015 добавляет проверку готовности без автоматического scheduler
или расширения concurrency. `depends_on` из pinned source задаёт до 32 уникальных
explicit IDs в своём проекте. Исходник уже неизменяем и сохранён, поэтому отдельная
таблица edges и backfill не нужны. Текущий filename не используется как alias.

Новые manual/managed starts проверяют bounded reachable graph внутри admission
transaction: только Done удовлетворяет dependency; missing/invalid/cycle/limit
отказывают до записи run/delivery/event. Replay имеет приоритет. Drawer показывает
причины и ссылки на известные задачи, используя pinned revision, а не открытую
в селекторе. При ожидании task state не меняется автоматически.

Отдельно остаются explicit revision adoption, DAG scheduler, два worker и
divergent integration. Изменение latest source пока не исправляет ошибку в
прикреплённом snapshot. Контракт: [TASK_DEPENDENCIES.md](../docs/TASK_DEPENDENCIES.md).

## Explicit task revision adoption

Новая исходная revision принимается отдельной командой после просмотра source.
Одна immediate transaction проверяет task version/target ownership/idle history,
сохраняет old+target receipt, меняет title/pin, сбрасывает task в New и отменяет
неинтегрированный Ready result. Done, active/unknown cleanup и незавершённый
integration intent блокируют adoption. Старые manual checks/reviews продолжают
использовать свои parent snapshots. Подробности: [TASK_REVISIONS.md](../docs/TASK_REVISIONS.md).

## BOSS-012a — Claude как независимый reviewer

Managed workflow сохраняет reviewer Codex/Claude при admission и не позволяет
сменить его через replay. Codex продолжает plan/implement/fix; manual flow прежний.
Claude получает полные сохранённые evidence через stdin без model filesystem/shell
tools в private scratch cwd. Terminal structured output валидируется отдельно от
exit/EOF/cleanup и exact candidate. Permissions Claude не выдаются за OS sandbox;
managed host startup policy остаётся внешней границей. Контракт:
[CLAUDE_REVIEW.md](../docs/CLAUDE_REVIEW.md). Реальные provider calls — отдельный opt-in;
Claude implementer, scheduler/two-worker и divergent integration не входят в 012a.

## BOSS-015b — явная очередь и два managed worker

Queue workflow сохраняет UUID, source revision/task version, reviewer и checks
до effects. Atomic claim связывает заявку с delivery; replay и Cancel не создают
второй запуск. Bounded rotating sweep ждёт Done dependencies и свободного места.
После restart незапущенные заявки становятся Paused и требуют Resume с прежними
параметрами. Pending заявка блокирует другой Start и source adoption той же задачи.

Manager держит максимум два managed worker до фактического EXIT; manual work и
integration остаются эксклюзивными. Unknown cleanup можно сохранить при работающем
соседе, но он блокирует новый запуск. Stop адресует отдельного live owner; Repo loss
останавливает обоих. Рабочие каталоги и private indexes различаются. Общие родительские
директории создаются с повторной проверкой типа при конкурентном mkdir.

Typed file scopes ещё отсутствуют; предсказание пересечений не заявлено. В проходе
015b другой старый candidate после публикации соседа требовал нового workflow;
016b добавляет отдельную merge/check/review цепочку. Автоматический rebase,
настройки числа worker и реальные provider acceptance остаются отдельными проходами.
Контракт: [WORKFLOW_QUEUE.md](../docs/WORKFLOW_QUEUE.md).

## BOSS-016b — интеграция при изменившемся target

Явная Integrate сохраняет исходное одобрение и pin текущего target. Новый
двухродительский merge candidate проходит сохранённые checks и свежий выбранный
reviewer; публикация разрешена только этой новой цепочкой evidence. Все этапы
остаются `integrating`, сохраняя глобальную эксклюзивность. Новый drift, конфликт,
отклонение review или failed checks останавливают попытку без повторного запуска
и без отката target. Неизменившийся target сохраняет существующий fast-forward.

Git helper:34 native Git/workspace tests и mutation guard. Контекст/протокол/pooled
persistence:31 tests; новые native merge lifecycle + LiveView:30; combined queue,
protocol/Git integration:19. Независимый review проверил исходники и SQL; браузерный
проход завершил две задачи через FF и свежий merge до Done. Полный общий прогон:
510 passed/1 existing Linux-only skip,seed798224,816.5s. Реальные provider calls,
автоматическое исправление merge-конфликтов и packaging остаются открыты.

## BOSS-015c — file scopes и настройка capacity

Сохранённый глобальный лимит1–3(default2) согласован между Manager, admission и SQL.
Настройки обновляются по ожидаемой версии; уменьшение ниже числа живых workers
отклоняется. Typed plan содержит file_scopes: null или bounded literal file/directory
paths. Старые планы остаются unknown. Первый implement-step атомарно закрепляет
scope до Ready/terminal; planning-only peers не блокируют друг друга. Пересечение
ожидает без новых записей или model calls, с работающим Stop. Неизвестные и
неполные прогнозы не гарантируют отсутствие конфликтов. Проверки:
[todo.md](todo.md), контракт [WORKFLOW_QUEUE.md](../docs/WORKFLOW_QUEUE.md).

## Autopilot — весь текущий Backlog последовательно

Явный Start сохраняет полный набор присутствующих New задач (до 256), pinned
revision/version, checks, reviewer и UUID. Один workflow проходит plan, implement,
checks, исправления и review; затем существующая exact-SHA integration с postchecks
доводит его до Done. Только после этого начинается следующий. Готовность зависимостей
может менять порядок; новые импорты и Failed задачи автоматически не добавляются.

Pause позволяет текущему workflow дойти до approval, затем запрещает интеграцию и
следующий запуск. Stop адресует live worker и отменяет остаток batch. Restart
приостанавливает незапущенную работу; неизвестные последствия не повторяются.
Неполный batch, изменившийся Backlog, занятый target, terminal failure и неизвестный
cleanup дают явный отказ. Ручная Queue сохраняет прежнюю семантику.

Кнопка Autopilot находится рядом с Sync specs; панель показывает сохранённые задачи
и переходы, drawer — plan, проверки и review. Контракт: [AUTOPILOT.md](../docs/AUTOPILOT.md).

## BOSS-017a — авария backend и видимое восстановление

Расширить существующие Repo-loss проверки настоящим SIGKILL отдельной BEAM VM:
во время implementation и после публикации перед финальным postcheck receipt.
Новый экземпляр приложения должен удержать историю и worktrees, пометить неизвестный
исход, приостановить Autopilot и не повторять CLI или публикацию. Только собственные
временные Git/SQLite и конечные тестовые CLI; пользовательский сервер не является fixture.

Исправить подтверждённые ошибки UI: после coordinator-only restart сохранённые
Interrupted/Paused должны дойти до открытых страниц; вложенная или откатившаяся
транзакция не может сообщить о committed success. Отказ Autopilot должен учитывать
paused ownership и unknown cleanup, без совета просто подождать. Автоматическое
снятие quarantine не входит в этот проход. Контракт: [RECOVERY.md](../docs/RECOVERY.md).

## BOSS-017b — незавершённые этапы и сохранённый Ready

Расширить native crash acceptance на plan/check/review. Валидный файл отчёта и
терминальное событие CLI без exit/EOF/cleanup не дают одобрение. Отдельный сценарий
завершает workflow до Ready, аварийно останавливает backend и проверяет сохранность
точного review/check/candidate. До явного Resume интеграция запрещена, включая
сохранённый UUID; после Resume неизменившийся target получает исходный approved SHA
и обязательный postcheck без повторного model call. Это проверка существующего
контракта; автоматическое снятие quarantine и повторение interrupted stages не добавляются.

## BOSS-017c — Git изменился во время остановки BOSS

После настоящего backend kill в Ready изменить только тестовый Git: candidate tree,
candidate ref, линейно продвинувшийся target или переписанную историю target.
До явного Resume старые receipts и UUID должны оставаться неизменными, без новых
процессов. Изменённый candidate и переписанный target должны блокироваться до новых
checks/review. Продвинувшийся target требует отдельного merge с родителями
`[target, original candidate]`, свежими checks/review и публикацией только нового
проверенного SHA. Сохранить прежнее одобрение и пользовательский checkout.

## BOSS-018a — подготовка macOS release candidate

По запросу пользователя перейти к упаковке0.1.0-rc.1 и проверке готовности релиза.
Собрать OTP archive с ERTS, native guardian, assets и миграциями; проверить запуск
распакованного пакета и устранить внешние Homebrew library paths. Сохранить notices
и факты сборки. Устранить найденные dependency advisories, выполнить полный набор
application tests и подготовить macOS CI/инструкции установки и обновления.
Пользователь выбрал Apache-2.0; полный текст хранится в LICENSE и включается в пакет.
Публичная публикация, signing/notarization, чистая машина, реальные
provider calls и Linux execution требуют собственного подтверждения, а не нового
названия для незакрытого gate. Контракт: [RELEASE.md](../docs/RELEASE.md).

## BOSS-018c — явная подготовка подписанного macOS пакета

Проверить доступность GitHub/Developer ID без remote writes, подписания и provider
effects. Подготовить отдельный opt-in шаг: исходный tar неизменяем, каждый native
image получает один Developer ID Team и runtime flags, только BEAM получает
allow-jit. После строгой проверки и packaged smoke создать подписанный UDZO DMG.
Нотарификация, staple/Gatekeeper и clean-machine проверяются отдельно; частичный
результат и timeout не становятся успешным релизом. Fixture tests проверяют сам
шаг без приватного ключа, а не заменяют реальную signing/provider acceptance.
Локальный merge6a29dac проверен4 fixture tests, AST и CI YAML; runtime/dependency
tree не изменён. На момент этого fixture increment реальная Developer ID подпись
ещё не выполнялась; последующее подписание CI-пакета записано в018d ниже.
Нотарификация остаётся отдельным открытым этапом.

## BOSS-018d — опубликованный RC и ограниченная provider acceptance

Пользователь разрешил отдельную RC-ветку/draft PR/CI и один реальный Codex workflow
до7 CLI вызовов/10минут. Remote main/site сохранить. Использовать проверенный
распакованный archive, новый repository/data/TMPDIR, реальный выбранный CLI account,
сохранённый check и независимый review. Счётчик вне model-writable paths, общий
deadline и прямой Stop защищают бюджет; terminal failure не даёт нового paid retry.
Сохранять только sanitized receipts/SHAs/usage и проверять actual target/Done,
checkout пользователя, cleanup и точную идентичность CI head/merge/artifact.

## Cuckoding marketing site — 2026-10-29

Separate static GitHub Pages presentation in site/ for the current BOSS restart.
User-directed satire pairs original robot-resort artwork with truthful workflow
information. Dependency-free HTML/CSS/JS, responsive layouts, native FAQs,
interactive illustrative workflow and bounded reduced-motion-aware parallax.
Deployment remains main-only with a site-only artifact. See docs/SITE.md and
.worklog/2026-10-29-marketing.md; this is not runtime/release acceptance.

Publication completed after explicit website-only authorization: commitdcdb0a3,
GitHub Pages run40939216125,9 exact HTTPS resource matches and live browser smoke.
The public application history remains based oncc71b4f; local BOSS changes were
excluded. Future website-only updates must retain this publication boundary.

The Deus Machina gallery extends the satire with laptop offerings and human
power generation; the footer credits Austin, Texas. Publish these site changes
from current origin/main with an explicit path allowlist, excluding local BOSS
history and task/worklog documentation.

Deus Machina publication verified: public45e83e3, Pages40947674513 passed,
13 exact HTTPS resources and live browser smoke. Only seven website/artwork
documentation files were published; local BOSS history remains excluded.

### BOSS-018d acceptance snapshot — 2026-10-29

Frozen RC head1ef9f9533896465669ed32ed7d2083acfdc292e1 passed CI40980336307:
594 application cases,1 skipped, all package/smoke/upload gates. Tested merge and
BUILD_INFO5cbe5906d32f667613e9a00572ba287f17a0cd39 have the same complete tree.
Actual downloaded CI tar passed independent closure/license/provenance review and
host smoke. Approved Developer ID signing produced a DMG and passed signed-payload
smoke; independent strict signature/mounted-payload review approved the exact DMG.
Keep notarization, staple/Gatekeeper,
clean-machine, fresh provider and Linux acceptance as separate open gates. No paid
workflow repeat or stable release/tag. Detailed receipts: docs/RELEASE.md and
.worklog/evidence/2026-10-29-release-acceptance.json.

### BOSS-018e — notarization credential preflight

Owner authorized one upload of the exact signed DMG266d4abd…03043 and supplied a
Keychain profile. Read-only notarytool history returned exit69/missing profile;
no submit/upload occurred. Keep the signed image unchanged. Resume the already
authorized upload after the owner configures the selected profile or gives its
correct existing name; never infer it from the signing identity/account name.
Persist exact-hash intent and submission ID before polling. Accepted, copy-only
stapling/validation, Gatekeeper and clean-machine acceptance remain distinct.

018e continuation: owner confirmed the earlier name belongs to Apple Account's
App-Specific Passwords list. Generated value entry was reserved for private user
Terminal; the third guarded setup subsequently exited1. The latest explicit
profile name remains unresolved in both service and Terminal contexts. Obtain only
its safe save-confirmation line or separate Keychain location, then revalidate
actual authentication before the unused authorized upload.

### Local package/run and checked-out-target recovery — 2026-10-29

Clean source3d2a249 was packaged with the retained secure runtime; unpacked-release
smoke passed. The local macOS27/arm64 archive and independent port4001 launch use
fresh private data, preserving the occupied old server/data. No new signing,
notarization or provider workflow. Evidence: `docs/RELEASE.md` and worklog JSON.

The reported Autopilot blocker was the registered project's clean main checkout.
An explicitly authorized switch to a new observer branch at the same commit freed
main without moving its ref or changing files. The packaged integration preflight
then returned `:ok`. A blocked batch requires a new user Start; recovery does not
restart agents or change task receipts. Runbook: `docs/AUTOPILOT.md`.

### Autopilot readiness follow-up — 2026-10-31

Port4001 and packaged integration preflight remain healthy; no fresh workflow has
started since the branch repair. Legacy failures came from candidate build output
without ignore rules; the current saved-check prompt and diagnostics already
cover this refusal. Preserve the receipts and require a fresh explicit workflow.
README now matches recorded secure-runtime packaging/signing evidence and links
check-integrity setup. No new application change or provider acceptance claim.

### Autopilot — lost Start reply and available Stop

A lost admission reply must not leave Stop disabled after the exact committed batch
is loaded. Reconcile UUID/project/tasks/check config/reviewer in the current read,
then clear uncertainty and renew the next Start UUID. Preserve mismatched/null/
stale reads and other uncertain actions. Drain refreshes held during the action;
confirmation is read-only and never creates a second request or provider effect.
