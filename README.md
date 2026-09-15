# Music Anti Blur

Перед работой агентам: [docs/00-ai-agents.md](docs/00-ai-agents.md).

Sprint 01: каркас API + Flutter auth. Локальный бакет — MinIO в Compose. Yandex Object Storage / CDN — позже, когда подключаем облако: [devops/yandex-storage-cdn.md](devops/yandex-storage-cdn.md).

## Локальный запуск

Предпочтительно из корня репозитория:

- Windows: `devops\start.cmd`
- Linux / macOS: `bash devops/start.sh`

В консоли меню: **1** локальная разработка (Enter по умолчанию), **2** развертывание. Без меню: `devops\start.cmd -Mode local` или `bash devops/start.sh deploy`.

Скрипт поднимает Docker Compose (Postgres, Redis, MailHog, MinIO), затем API и `flutter run` **в отдельных окнах**. В режиме **локальная разработка** после healthy API импортируются треки из `no_commit/music` (если папка есть): из каждой папки с аудио минимум 4 файла. Стартовый скрипт после этого завершается. Нужны Docker Desktop / daemon, .NET 10 SDK, Flutter и FFmpeg в PATH. Устройство для Flutter: переменная `FLUTTER_DEVICE` или интерактивный выбор `flutter run`.

Остановка (API + Flutter + Compose, тома Postgres и MinIO сохраняются):

- Windows: `devops\stop.cmd`
- Linux / macOS: `bash devops/stop.sh`

Стереть данные БД и бакет MinIO: `devops\stop.cmd -Volumes` или `bash devops/stop.sh --volumes`. После этого в приложении нужно **войти заново**: JWT со старого user id в новой базе больше не действует.

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

В Development API при старте заполняет фейковый каталог и помечает имена префиксом **`[SEED DATA]`** (артисты, альбомы, треки). В Production / режиме развертывания этот каталог не создаётся. Уже существующие seed-строки с фиксированными GUID при следующем старте Development переименовываются с тем же префиксом.

Реальные файлы для прослушивания кладите в `no_commit/music` (gitignore). После того как API отвечает, `devops\start.cmd` / `start.sh` в local-режиме сами создают артистов/альбомы/треки и заливают исходники через admin multipart. Повторный запуск пропускает треки, у которых уже есть качества. Вручную:

```powershell
devops\seed-local-music.ps1
```

```bash
bash devops/seed-local-music.sh
```

FFmpeg и ffprobe должны быть в PATH (Windows: winget/choco; Linux: пакет `ffmpeg`). Если бинаря нет, джоба пишет `ffmpeg not found` в статус generation. В Development лимит admin-import 10/час не действует, чтобы локальный импорт мог залить больше пяти файлов за раз.

Залить исходник на конкретный каталожный трек (после `dotnet run` и healthy MinIO), в том числе на seed Neon Pulse:

```powershell
devops\upload-catalog-source.ps1 -Path C:\path\to\track.mp3
```

Скрипт логинится как admin, грузит multipart в MinIO и ждёт транскод. `POST /api/v1/tracks/{id}/playback-url` отдаёт signed URL (локально MinIO GET, не тело аудио через API). Play на карточке трека и «Играть альбом» в приложении берут этот URL через `just_audio` / `audio_service`. API байты аудио не стримит.

Host внутри подписи URL должен быть тем, куда ходит **плеер**, не API. При `Storage__UseCdn=false` API берёт hostname из запроса к себе (`Host`): эмулятор Android ходит на `http://10.0.2.2:5080` — в URL MinIO попадёт `http://10.0.2.2:9000`. Windows desktop с `http://127.0.0.1:5080` получит `127.0.0.1:9000`. Явный `Storage__PresignEndpoint` по-прежнему перекрывает это. Не подменяйте hostname у уже подписанного URL на клиенте — сломается SigV4.

Для next/prev по seed-альбому `[SEED DATA] Night Signals` залейте **два** Ready-трека (Neon Pulse по умолчанию и Glass Rain):

```powershell
devops\upload-catalog-source.ps1 -Path C:\path\to\one.mp3
devops\upload-catalog-source.ps1 -Path C:\path\to\two.mp3 -TrackId d1111111-1111-4111-8111-111111111112
```

Фон: iOS `UIBackgroundModes = audio`; Android media notification через `audio_service`. На Android 13+ запрашивается `POST_NOTIFICATIONS`; если отказать, трек всё равно играет, notification может не появиться. Windows desktop играет в процессе приложения, lock screen там не критерий.

3. Flutter:

```bash
cd src/mobile
flutter pub get
flutter run
```

Эмулятор Android сам ходит на `http://10.0.2.2:5080`. На Windows/iOS simulator — `http://127.0.0.1:5080`. Физическое устройство: `--dart-define=API_BASE_URL=http://<LAN-IP-ПК>:5080`. Тот же `API_BASE_URL` нужен, чтобы плеер ходил в API по LAN; signed MinIO URL берёт hostname из `Host` запроса к API (эмулятор → `10.0.2.2:9000`).

На карточке трека: **Выбрать файл** копирует аудио в каталог приложения (Android ещё берёт persistable SAF URI). Play в airplane mode играет эту копию, если источник Авто или Local. Чип **Catalog** всегда берёт CDN/MinIO и игнорирует файл на устройстве. **Загрузить на сервер** — отдельный шаг: multipart в `users/{userId}/overrides/.../generations/{id}/`, не автозагрузка из picker. Чужой аккаунт на том же `trackId`: `GET /tracks/{id}/override` и private playback-url дают **404** `not_found`, не 403. Проверка: второй пользователь в приложении, поиск/карточка без подмены, Play идёт в каталог.

Два клиента одного user (эмулятор Android + Windows или Chrome debug): у каждого свой `deviceId` в secure storage. Play на A обновляет now playing на B без автозвука (SignalR `PlaybackSnapshot`). **Играть здесь** на B забирает writer; A ставит паузу. Список «Это устройство / Другое устройство» — presence, не remote-control. Local-файл живёт только на том устройстве, где выбран picker: на B без файла «Играть здесь» берёт **ваш** private Ready или каталог и показывает «Локальный файл на другом устройстве», это не подмена каталога для всех. Chrome/Windows годится как второй экран now playing; браузер не продукт MVP.

Письма verification/reset содержат 6-значный код для ввода в приложении. Смотреть в MailHog.

Переменные окружения: см. `.env.example`. Локальный S3 и (позже) Yandex: [devops/yandex-storage-cdn.md](devops/yandex-storage-cdn.md).

## CI

GitHub Actions (`.github/workflows/ci.yml`) на ветке `develop`: push и pull request.

- API: `dotnet restore`, `dotnet build -c Release` и `dotnet test` проекта `src/api/MusicAntiBlur.Api.Tests`
- Flutter: `flutter pub get`, `flutter analyze --fatal-infos`, `flutter test` в `src/mobile`

