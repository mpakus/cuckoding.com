# BOSS — план нового проекта

Дата: 2026-10-25. Основа: [BOSS_PLAN.md](../BOSS_PLAN.md).
Статус: анализ и подготовка reference coding; приложение ещё не создано.
Задачи: [todo.md](todo.md). Источники: [RESEARCH.md](../docs/RESEARCH.md).

## Вывод

План задаёт правильную основу: локальный детерминированный координатор,
существующие CLI, Git worktrees, независимое review и проверяемый результат.
Elixir/OTP + Phoenix LiveView + SQLite соответствует этой задаче. Перенос старой
архитектуры Cuckoding не нужен: в текущей ветке нет кода приложения.

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

Это предлагаемые правила реализации, не утверждение о готовом поведении.
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
- UI сначала: добавление пути, board, детали task и понятные ошибки. Browser
  не может молча читать произвольный локальный путь: вначале поле пути с серверной
  проверкой, native folder picker — только при появлении desktop wrapper.

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
- Начать с явного Sync и небольшого polling с debounce. `FileSystem` добавлять,
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

На этой машине обнаружены Elixir 1.20.4 (сборка под OTP 29), запущенный OTP 28,
Phoenix generator 1.8.13, Codex 0.146.0, Claude Code 2.1.142. Версии dependencies
приложения пока не выбраны: `mix.exs` и lockfile отсутствуют. Согласованность
Elixir/OTP проверить до bootstrap и закрепить toolchain; сам `--version` не
доказывает работоспособность NIF/release.

Проверены help-контракты CLI, но не authentication, live streaming, расход
токенов, permissions, cancellation и packaging. Исследованные конкуренты не
запускались и их тесты здесь не выполнялись. Source review не заменяет spike.

Ключевые проверки до выбора runner: потеря backend после spawn до записи PID;
потомок, переживший родителя; stderr flood; invalid/oversized JSONL; долгий тихий
run; auth/quota error без бесконечного retry. До integration: target drift,
checked-out target, dirty checkout, конфликт и падение checks после публикации.
