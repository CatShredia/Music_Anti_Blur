# Music Anti Blur

Стриминг с каталогом на сервере. Пользователь может подменить каталожный трек **своим** файлом (локально и/или приватной копией в Object Storage) и выбрать источник: `auto` | `catalog` | `local` | `private`.

Клиент MVP — **Flutter**. API — **ASP.NET Core**. Аудиобайты API не принимает и не стримит.

## Документация

Перед работой агентам: [docs/00-ai-agents.md](docs/00-ai-agents.md). Если документ и код расходятся — побеждает `docs/`.

| Файл | Содержание |
|---|---|
| [docs/00-ai-agents.md](docs/00-ai-agents.md) | Карта репозитория, стек, правила для агентов |
| [docs/01-product-plan.md](docs/01-product-plan.md) | Скоуп MVP, стек, auth, плеер, подмена, SignalR |
| [docs/02-database-overview.md](docs/02-database-overview.md) | Схема Postgres |
| [docs/03-api-contract.md](docs/03-api-contract.md) | HTTP / SignalR, ошибки, rate limits |
| [docs/04-operations.md](docs/04-operations.md) | FFmpeg, jobs, CDN/S3, health, backup, deploy |
| [docs/05-local-setup.md](docs/05-local-setup.md) | Локальный запуск стека |

## Репозиторий

| Путь | Зачем |
|---|---|
| [docs/05-local-setup.md](docs/05-local-setup.md) | Как поднять Compose, API и Flutter |
| [docker-compose.yml](docker-compose.yml) | Postgres, Redis, MailHog, MinIO |
| [.env.local.example](.env.local.example) | Шаблон секретов для локалки (копировать в `.env`) |
| [.env.example](.env.example) | Имена переменных окружения |
| [devops/](devops/) | `start` / `stop`, seed, upload в каталог |
| [devops/yandex-storage-cdn.md](devops/yandex-storage-cdn.md) | Локальный MinIO и (позже) Yandex |
| [src/api/](src/api/) | ASP.NET Core (.NET 10) |
| [src/mobile/](src/mobile/) | Flutter-клиент |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | CI на ветке `develop` |
