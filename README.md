# Music Anti Blur

Перед работой агентам: [docs/00-ai-agents.md](docs/00-ai-agents.md).

Sprint 01: каркас API + Flutter auth. Локальный бакет — MinIO в Compose. Yandex Object Storage / CDN — позже, когда подключаем облако: [devops/yandex-storage-cdn.md](devops/yandex-storage-cdn.md).

## Локальный запуск

Предпочтительно из корня репозитория:

- Windows: `devops\start.cmd`
- Linux / macOS: `bash devops/start.sh`

В консоли меню: **1** локальная разработка (Enter по умолчанию), **2** развертывание. Без меню: `devops\start.cmd -Mode local` или `bash devops/start.sh deploy`.

Скрипт поднимает Docker Compose (Postgres, Redis, MailHog, MinIO), затем API и `flutter run` **в отдельных окнах**. Стартовый скрипт после этого завершается. Нужны Docker Desktop / daemon, .NET 10 SDK и Flutter. Устройство для Flutter: переменная `FLUTTER_DEVICE` или интерактивный выбор `flutter run`.

Остановка (API + Flutter + Compose, тома Postgres и MinIO сохраняются):

- Windows: `devops\stop.cmd`
- Linux / macOS: `bash devops/stop.sh`

Стереть данные БД и бакет MinIO: `devops\stop.cmd -Volumes` или `bash devops/stop.sh --volumes`.

Развертывание сейчас — это Release/Production API на этой же машине плюс Flutter в режиме разработки. Отдельного Kubernetes/образа API ещё нет.

Ручной запуск по шагам:

1. Docker Desktop должен быть запущен.

```bash
docker compose up -d
```

Сервисы: PostgreSQL `localhost:5432`, Redis `6379`, MailHog SMTP `1025` / UI http://localhost:8025, MinIO S3 `9000` / консоль http://localhost:9001 (`minio` / `minio-local-only`). Бакет `music-anti-blur` создаётся автоматически, анонимного чтения нет.

Учётные данные Postgres задаются в `.env`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`. Их же нужно продублировать в `ConnectionStrings__Postgres` / `ConnectionStrings__Hangfire`. Образ читает пароль только при первом создании volume; смена пароля — новый volume (`docker compose down -v`).

Если Windows уже занимает `5432`, задайте другой хостовый порт в `.env`:

```
POSTGRES_PORT=5433
ConnectionStrings__Postgres=Host=localhost;Port=5433;Database=music_anti_blur;Username=music;Password=music
ConnectionStrings__Hangfire=Host=localhost;Port=5433;Database=music_anti_blur;Username=music;Password=music
```

2. API (.NET 10). В Development процесс читает корневой `.env` (порт/пароль Postgres), иначе берёт `appsettings.Development.json`.

```bash
dotnet run --project src/api/MusicAntiBlur.Api
```

- HTTP: http://localhost:5080
- Swagger (Development): http://localhost:5080/swagger
- Health: http://localhost:5080/health
- Hangfire: http://localhost:5080/hangfire (Basic `admin` / `admin-local-only`)

Миграции применяются при старте API.

Sandbox admin (Development): login `admin`, password `AdminPassword123`.

3. Flutter:

```bash
cd src/mobile
flutter pub get
flutter run
```

Эмулятор Android сам ходит на `http://10.0.2.2:5080`. На Windows/iOS simulator — `http://127.0.0.1:5080`. Физическое устройство: `--dart-define=API_BASE_URL=http://<LAN-IP-ПК>:5080`.

Письма verification/reset содержат 6-значный код для ввода в приложении. Смотреть в MailHog.

Переменные окружения: см. `.env.example`. Локальный S3 и (позже) Yandex: [devops/yandex-storage-cdn.md](devops/yandex-storage-cdn.md).

## CI

GitHub Actions (`.github/workflows/ci.yml`) на ветке `develop`: push и pull request.

- API: `dotnet restore` и `dotnet build -c Release` проекта `src/api/MusicAntiBlur.Api`
- Flutter: `flutter pub get`, `flutter analyze --fatal-infos`, `flutter test` в `src/mobile`

