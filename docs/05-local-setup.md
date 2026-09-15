# Music Anti Blur — локальный запуск стека

Связанные документы: [00-ai-agents.md](00-ai-agents.md), [01-product-plan.md](01-product-plan.md), [04-operations.md](04-operations.md). Секреты — корневой `.env` (в git не коммитить). Локальный бакет — MinIO в Compose; Yandex Object Storage / CDN — [devops/yandex-storage-cdn.md](../devops/yandex-storage-cdn.md).

Production-инварианты (health, backup, deploy) — [04-operations.md](04-operations.md). Этот файл — как поднять стек на машине разработчика.

---

## 1. Что поднимается

| Компонент | Где | Порт / URL |
|---|---|---|
| PostgreSQL 16 | Compose | `localhost:${POSTGRES_PORT}` (часто `5433`, чтобы не конфликтовать с системным `5432`) |
| Redis 7 | Compose | `6379` |
| MailHog SMTP / UI | Compose | `1025` / http://localhost:8025 |
| MinIO S3 / консоль | Compose | `9000` / http://localhost:9001 |
| ASP.NET Core API | хост | http://localhost:5080 |
| Flutter | хост | `flutter run` (устройство выбирается) |

API **не** стримит аудиобайты. Playback URL — S3 presigned GET в MinIO (`Storage__UseCdn=false`). Host внутри подписи берётся из запроса к API (`Host`): эмулятор Android → `http://10.0.2.2:9000`, Windows/Chrome → `127.0.0.1:9000`. Явный `Storage__PresignEndpoint` перекрывает это. Не подменяйте hostname у уже подписанного URL на клиенте — сломается SigV4.

---

## 2. Требования

- Docker Desktop / daemon
- .NET 10 SDK
- Flutter
- FFmpeg и ffprobe в PATH (Windows: winget/choco; Linux: пакет `ffmpeg`). Без них Hangfire пишет `ffmpeg not found` в статус generation
- Для пункта меню «эмулятор + Chrome»: Google Chrome и Android emulator (`emulator-*`)

---

## 3. Быстрый старт

Из корня репозитория:

| ОС | Запуск | Остановка |
|---|---|---|
| Windows | `devops\start.cmd` | `devops\stop.cmd` |
| Linux / macOS | `bash devops/start.sh` | `bash devops/stop.sh` |

Меню:

| Клавиша | Режим |
|---|---|
| **1** (Enter по умолчанию) | локальная разработка |
| **2** | развертывание (Release/Production API на этой машине + Flutter в режиме разработки) |
| **3** | эмулятор Android + Chrome |
| **0** | выход |

Без меню: `devops\start.cmd -Mode local` или `bash devops/start.sh deploy` / `dual`.

Если корневого `.env` нет, скрипт предлагает скопировать [`.env.local.example`](../.env.local.example) в `.env` (Enter — да, `n` — прервать). Имена переменных также в [`.env.example`](../.env.example).

Скрипт поднимает Compose, затем API и `flutter run` **в отдельных окнах**. После этого стартовый скрипт завершается.

В режимах **1** и **3**, когда API healthy, импортируются треки из `no_commit/music` (если папка есть): из каждой папки с аудио минимум 4 файла. Пункт **3** поднимает AVD (если ещё не запущен) и два `flutter run`: `-d chrome` и `-d emulator-*`.

Устройство для Flutter в режимах 1–2: переменная `FLUTTER_DEVICE` или интерактивный выбор `flutter run`.

Развертывание сейчас — Release/Production API на этой же машине плюс Flutter в режиме разработки. Отдельного Kubernetes/образа API ещё нет.

---

## 4. Остановка

`stop` гасит API, Flutter и Compose. Тома Postgres и MinIO **сохраняются**.

Стереть данные БД и бакет MinIO: `devops\stop.cmd -Volumes` или `bash devops/stop.sh --volumes`. После этого нужно **войти заново**: JWT со старого user id в новой базе больше не действует.

Образ Postgres читает пароль только при первом создании volume; смена `POSTGRES_PASSWORD` — новый volume (`docker compose down -v` или `stop --volumes`).

---

## 5. Ручной запуск

### 5.1. Compose

Docker Desktop должен быть запущен.

```bash
docker compose up -d
```

Сервисы: PostgreSQL, Redis, MailHog, MinIO. Бакет `music-anti-blur` создаётся автоматически, анонимного чтения нет. Консоль MinIO: `minio` / `minio-local-only` (из `.env`).

Учётные данные Postgres задаются в `.env`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`. Их же нужно продублировать в `ConnectionStrings__Postgres` / `ConnectionStrings__Hangfire`.

Если Windows уже занимает `5432`:

```
POSTGRES_PORT=5433
ConnectionStrings__Postgres=Host=localhost;Port=5433;Database=music_anti_blur;Username=music;Password=music
ConnectionStrings__Hangfire=Host=localhost;Port=5433;Database=music_anti_blur;Username=music;Password=music
```

### 5.2. API

В Development процесс читает корневой `.env` (порт/пароль Postgres), иначе берёт `appsettings.Development.json`.

```bash
dotnet run --project src/api/MusicAntiBlur.Api
```

| Что | URL |
|---|---|
| HTTP | http://localhost:5080 |
| Swagger (Development) | http://localhost:5080/swagger |
| Health | http://localhost:5080/health |
| Hangfire | http://localhost:5080/hangfire — Basic `admin` / `admin-local-only` |

Миграции применяются при старте API.

Sandbox admin (Development): login `admin`, password `AdminPassword123`. Сырой пароль только здесь и в `.env`, не в таблицах БД.

В Development API при старте заполняет фейковый каталог и помечает имена префиксом **`[SEED DATA]`**. В Production / режиме развертывания этот каталог не создаётся. Уже существующие seed-строки с фиксированными GUID при следующем старте Development переименовываются с тем же префиксом.

В Development лимит admin-import 10/час не действует, чтобы локальный импорт мог залить больше пяти файлов за раз.

### 5.3. Каталог из файлов

Реальные файлы для прослушивания — в `no_commit/music` (gitignore). `start` в local/dual сам создаёт артистов/альбомы/треки и заливает исходники через admin multipart. Повторный запуск пропускает треки, у которых уже есть качества. Вручную:

```powershell
devops\seed-local-music.ps1
```

```bash
bash devops/seed-local-music.sh
```

Залить исходник на конкретный каталожный трек (после `dotnet run` и healthy MinIO), в том числе на seed Neon Pulse:

```powershell
devops\upload-catalog-source.ps1 -Path C:\path\to\track.mp3
```

Скрипт логинится как admin, грузит multipart в MinIO и ждёт транскод. `POST /api/v1/tracks/{id}/playback-url` отдаёт signed URL (локально MinIO GET). Play на карточке трека и «Играть альбом» берут этот URL через `just_audio` / `audio_service`.

Для next/prev по seed-альбому `[SEED DATA] Night Signals` залейте **два** Ready-трека (Neon Pulse по умолчанию и Glass Rain):

```powershell
devops\upload-catalog-source.ps1 -Path C:\path\to\one.mp3
devops\upload-catalog-source.ps1 -Path C:\path\to\two.mp3 -TrackId d1111111-1111-4111-8111-111111111112
```

### 5.4. Flutter

```bash
cd src/mobile
flutter pub get
flutter run
```

| Устройство | `API_BASE_URL` |
|---|---|
| Эмулятор Android | сам ходит на `http://10.0.2.2:5080` |
| Windows / iOS simulator | `http://127.0.0.1:5080` |
| Физическое устройство | `--dart-define=API_BASE_URL=http://<LAN-IP-ПК>:5080` |

Тот же `API_BASE_URL` нужен, чтобы плеер ходил в API по LAN; signed MinIO URL берёт hostname из `Host` запроса к API.

Фон: iOS `UIBackgroundModes = audio`; Android media notification через `audio_service`. На Android 13+ запрашивается `POST_NOTIFICATIONS`; если отказать, трек всё равно играет, notification может не появиться. Windows desktop играет в процессе приложения, lock screen там не критерий.

Письма verification/reset содержат 6-значный код. Смотреть в MailHog: http://localhost:8025.

---

## 6. Клиент: подмена и два устройства

На карточке трека: **Выбрать файл** копирует аудио в каталог приложения (Android ещё берёт persistable SAF URI). Play в airplane mode играет эту копию, если источник Авто или Local. Чип **Catalog** всегда берёт CDN/MinIO и игнорирует файл на устройстве. **Загрузить на сервер** — отдельный шаг: multipart в `users/{userId}/overrides/.../generations/{id}/`, не автозагрузка из picker. Чужой аккаунт на том же `trackId`: `GET /tracks/{id}/override` и private playback-url дают **404** `not_found`, не 403.

Два клиента одного user (эмулятор Android + Chrome debug, пункт меню **3**): у каждого свой `deviceId` в secure storage. Play на A обновляет now playing на B без автозвука (SignalR `PlaybackSnapshot`). **Играть здесь** на B забирает writer; A глушит звук. Play/pause на ведомом недоступны — нет remote-control. Список «Это устройство / Другое устройство» — presence. Local-файл живёт только на том устройстве, где выбран picker: на B без файла «Играть здесь» берёт **ваш** private Ready или каталог и показывает «Локальный файл на другом устройстве». Chrome/Windows годится как второй экран now playing; браузер не продукт MVP.

Норматив sync: [03-api-contract.md](03-api-contract.md) §6.

---

## 7. CI

GitHub Actions ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) на ветке `develop`: push и pull request.

- API: `dotnet restore`, `dotnet build -c Release` и `dotnet test` проекта `src/api/MusicAntiBlur.Api.Tests`
- Flutter: `flutter pub get`, `flutter analyze --fatal-infos`, `flutter test` в `src/mobile`
