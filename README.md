# Music Anti Blur

Перед работой агентам: [docs/00-ai-agents.md](docs/00-ai-agents.md).

Sprint 01: каркас API + Flutter auth. FFmpeg, Object Storage и CDN появятся в спринте 03.

## Локальный запуск

1. Docker Desktop должен быть запущен.

```bash
docker compose up -d
```

Сервисы: PostgreSQL `localhost:5432`, Redis `6379`, MailHog SMTP `1025`, UI http://localhost:8025.

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

Переменные окружения: см. `.env.example`.
