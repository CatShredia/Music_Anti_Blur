# Music Anti Blur

Стриминг с каталогом на сервере; пользователь может подменить трек своим файлом. API — ASP.NET Core (.NET 10), клиент — Flutter. Подробная карта репозитория, стек и правила: [docs/00-ai-agents.md](docs/00-ai-agents.md). Если `docs/` и код расходятся, правьте код по `docs/`.

## Куда смотреть

| Что | Где |
|---|---|
| Контракт API, ошибки, лимиты | [docs/03-api-contract.md](docs/03-api-contract.md) |
| Схема БД | [docs/02-database-overview.md](docs/02-database-overview.md) |
| Джобы, S3/CDN, логи и метрики | [docs/04-operations.md](docs/04-operations.md) |
| Локальный запуск, CI, наблюдаемость | [docs/05-local-setup.md](docs/05-local-setup.md) |
| Админ-API, скрипты запуска, квоты | [docs/06-admin-and-operations.md](docs/06-admin-and-operations.md) |
| Спринты и планы (вне git) | `no_commit/sprints/`, `no_commit/plans/` |

## Команды

Из корня репозитория.

- Запуск стека: `devops\start.cmd` (Windows) или `bash devops/start.sh`. Остановка: `stop`; `--volumes` / `-Volumes` удаляет данные БД.
- API: `dotnet build src/api/MusicAntiBlur.Api/MusicAntiBlur.Api.csproj -c Release`, тесты `dotnet test src/api/MusicAntiBlur.Api.Tests -c Release`. Собирайте csproj, не solution.
- Миграции: `dotnet ef migrations add <Имя> --project src/api/MusicAntiBlur.Api`; перед PR `dotnet ef migrations has-pending-model-changes --project src/api/MusicAntiBlur.Api`.
- Flutter (`src/mobile`): `flutter analyze --fatal-infos`, `flutter test`.
- CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) гоняет API, Flutter и миграции на PR в `develop` и `main`.

## Подводные камни

- Пока API запущен, Debug-сборка заблокирована (`MSB3021`). Собирайте с `-c Release` или остановите API.
- `bash` из PowerShell подхватывает WSL-`bash.exe` из System32; в `devops/*.sh` в начало `PATH` уже добавлен `/usr/bin`.
- `no_commit/` в `.gitignore`: скрипты и заметки оттуда в git не попадут.
- В Development админ создаётся сидером: `admin` / `AdminPassword123`. В Production сидера нет, роль выдаётся в БД.
- Секреты только в `.env` (он в `.gitignore`), шаблоны — `.env.example`, `.env.local.example`.
- Секреты TOTP шифруются ключами из таблицы `data_protection_keys`; её нельзя чистить и нужно бэкапить с БД.
- Hangfire-задачи не должны терять `RequestId`; новые метрики добавляйте в `Observability/AppMetrics.cs`.

## Правила работы

- Отвечать кратко и по-русски. Перед задачей задавать уточняющие вопросы, если неясно.
- Коммиты: сообщения на английском, описывают изменение поведения, без процесса работы. Не пушить без явной просьбы.
- Менять схему БД, CI и конфигурацию хоста только после подтверждения плана.
- Новая функция = код + тесты + правка нужного файла в `docs/`.

## Состояние

Спринты MVP 01–06 закрыты. Ветка `sprint-07-08`: наблюдаемость и CI (07), 2FA, журнал входов, квоты (08); PR #11 в `develop`, черновик. Дальше по плану: `no_commit/sprints/01-post-mvp-roadmap.md`.
