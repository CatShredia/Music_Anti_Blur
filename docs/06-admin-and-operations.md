# Music Anti Blur — админ-инструменты, скрипты запуска и проверка квот

Практическое руководство для разработчика и администратора. Что запускать, куда заходить и как проверить. Нормативные контракты — в [03-api-contract.md](03-api-contract.md) и [04-operations.md](04-operations.md); локальный запуск стека — в [05-local-setup.md](05-local-setup.md).

> **Веб-админка каталога** — раздел Flutter web, описан в [разделе 9](#9-веб-админка-каталога). Кроме неё «админ-панель» — это админ-API со Swagger, Hangfire Dashboard, Grafana и скрипты в `devops/`. Все они описаны ниже.

## Содержание

1. [Доступы и адреса](#1-доступы-и-адреса)
2. [Админ-API и Swagger](#2-админ-api-и-swagger)
3. [Hangfire Dashboard](#3-hangfire-dashboard)
4. [Grafana, Prometheus, Loki](#4-grafana-prometheus-loki)
5. [Скрипты запуска и остановки](#5-скрипты-запуска-и-остановки)
6. [Скрипты наполнения каталога](#6-скрипты-наполнения-каталога)
7. [Проверка квот загрузки](#7-проверка-квот-загрузки)
8. [Типичные проблемы](#8-типичные-проблемы)
9. [Веб-админка каталога](#9-веб-админка-каталога)

---

## 1. Доступы и адреса

Адреса и учётные данные для локальной разработки (режим Development). Значения берутся из `.env` (шаблон — [.env.local.example](../.env.local.example)). **Не используйте их в проде.**

| Что | Адрес | Вход |
|---|---|---|
| API | http://localhost:5080 | — |
| Swagger UI | http://localhost:5080/swagger | только Development |
| Hangfire Dashboard | http://localhost:5080/hangfire | Basic: `Hangfire__DashboardUser` / `Hangfire__DashboardPassword` (локально `admin` / `admin-local-only`) |
| Health | `GET /health`, `GET /health/deps` | — |
| Метрики | `GET /metrics` | токен `Metrics__ScrapeToken`; без токена открыт только в Development |
| Grafana | http://localhost:3000 | `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` (локально `admin` / `admin-local-only`) |
| Prometheus | http://localhost:9090 | — |
| MailHog (письма) | http://localhost:8025 | — |
| MinIO консоль | http://localhost:9001 | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |

**Администратор приложения.** В Development при старте API сидер создаёт пользователя из `Seed__AdminIdentifier` / `Seed__AdminPassword` (локально `admin` / `AdminPassword123`) с ролью `admin`. В Production сидер **не работает**: роль выдаётся вручную в БД.

```sql
update users set role = 'admin' where login = '<логин>';
```

Роль попадает в JWT при входе. Если вы меняли её у уже вошедшего пользователя, войдите заново.

`GET /health/deps` проверяет Redis, SMTP, Hangfire и S3. При проблеме любой из зависимостей отвечает `503` с разбивкой по полям.

---

## 2. Админ-API и Swagger

Все эндпоинты `/api/v1/admin/*` требуют JWT с ролью `admin`. Без токена — `401`, с токеном обычного пользователя — `403 admin_required`.

### 2.1. Получить токен

Локально (Git Bash):

```bash
API=http://127.0.0.1:5080/api/v1
ADMIN=$(curl -s -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d '{"identifierType":"login","identifier":"admin","password":"AdminPassword123"}' \
  | python -c "import sys,json;print(json.load(sys.stdin)['accessToken'])")
```

Если у админа включена 2FA, ответ будет `{ "twoFactorRequired": true, "challengeId": ... }`. Завершите вход через `POST /auth/2fa/verify` (см. [03-api-contract.md](03-api-contract.md) §2.3).

В Swagger нажмите **Authorize** и вставьте только `accessToken`, без слова `Bearer`. Токен сохраняется между перезагрузками страницы. Access-токен живёт недолго; при `401` получите новый.

### 2.2. Что умеет админ-API

| Группа | Запросы | Назначение |
|---|---|---|
| Каталог | `POST /admin/artists`, `PUT /admin/artists/{id}` | создать и изменить исполнителя |
| | `POST /admin/albums`, `PUT /admin/albums/{id}` | альбом |
| | `PUT /admin/albums/{id}/cover` | обложка (тело — файл изображения) |
| | `POST /admin/tracks`, `PUT /admin/tracks/{id}` | трек (метаданные) |
| Исходники | `POST /admin/tracks/{trackId}/uploads` | начать multipart-загрузку исходника |
| | `POST …/uploads/{generationId}/parts` | получить presigned URL для частей |
| | `POST …/uploads/{generationId}/complete` | завершить, ставит перекодирование в очередь |
| | `GET …/uploads/{generationId}` | статус загрузки |
| | `DELETE …/uploads/{generationId}` | отменить |
| Рендиции | `GET /admin/tracks/{trackId}/renditions` | статусы качеств (`pending`, `processing`, `ready`, `failed`) и `ErrorMessage` |
| | `POST /admin/tracks/{trackId}/transcode` | перезапустить перекодирование (например, после `failed`) |
| Квоты | `GET /admin/users/{userId}/quota` | занято и лимит пользователя |
| | `PUT /admin/users/{userId}/quota` | задать или снять лимит |

Форматы тел запросов смотрите в Swagger, там схемы всех DTO. Загрузка исходника идёт по тому же протоколу, что и приватная копия пользователя: initiate → parts → PUT в S3 → complete. Заголовок `Idempotency-Key` (GUID) нужен у `initiate` и `complete`. Лимиты: файл до 100 МБ, части 5–16 МиБ.

### 2.3. Типовые сценарии

**Завести альбом с нуля.** Создать исполнителя → альбом → трек → загрузить исходник → дождаться рендиций. Для массового наполнения используйте скрипты из [раздела 6](#6-скрипты-наполнения-каталога).

**Трек не играет.** Откройте `GET /admin/tracks/{id}/renditions`. Если все качества `failed`, причина в `ErrorMessage` (чаще всего FFmpeg не найден или файл повреждён). Исправьте и вызовите `POST /admin/tracks/{id}/transcode`. Ход задачи виден в Hangfire (раздел 3).

**Сменить квоту пользователю.** См. [раздел 7](#7-проверка-квот-загрузки).

---

## 3. Hangfire Dashboard

`/hangfire` показывает фоновые задачи: перекодирование каталога и приватных копий, письма, уборку.

Что смотреть:

- **Jobs → Failed**: упавшие задачи с трассировкой. Задачи перекодирования повторяются до 5 раз, затем остаются в Failed.
- **Jobs → Processing / Enqueued**: очередь. Воркеров 2, поэтому длинные перекодирования ставятся в очередь друг за другом.
- **Recurring Jobs**: регулярные задачи.

| Задача | Расписание | Что делает |
|---|---|---|
| `ping` | каждые 5 мин | проверка планировщика |
| `cleanup-unverified` | каждый час | удаляет аккаунты с неподтверждённой почтой старше 24 ч |
| `cleanup-auth-tokens` | :15 каждого часа | чистит старые токены |
| `storage-sweep` | каждые 5 мин | возвращает в работу зависшие перекодирования, отменяет старые незавершённые multipart-загрузки, чистит выполненные записи очереди удаления |
| `cleanup-login-events` | 03:30 ежедневно | удаляет журнал входов старше 90 дней |
| `purge-deleted-tracks` | 03:45 ежедневно | стирает треки из корзины старше `Catalog__DeletedRetentionDays` (180) и ставит их файлы в очередь удаления S3; метрика `mab_tracks_purged` |

Дашборд защищён Basic-авторизацией. Обязательно задайте непустой `Hangfire__DashboardPassword`: с пустым паролем подойдёт пустой пароль. Каждая задача, поставленная HTTP-запросом, хранит его `RequestId`: по нему в Loki находятся и запрос, и его задачи (раздел 4).

---

## 4. Grafana, Prometheus, Loki

Стек наблюдаемости в Compose-профиле `observability`: он не поднимается по умолчанию. Подробности запуска — [05-local-setup.md](05-local-setup.md) §8.

### 4.1. Включить

В `.env` добавьте:

```env
COMPOSE_PROFILES=observability
Loki__Url=http://localhost:3100
```

После этого `devops\start.cmd` / `start.sh` поднимает стек вместе с остальным, а `stop` гасит. Разово, без правки `.env`:

```bash
docker compose --profile observability up -d
```

Чтобы логи API попадали в Loki, переменная `Loki__Url` должна быть задана до запуска API. Если Prometheus не видит API (в Grafana алерт «API down»), проверьте, что API слушает `0.0.0.0:5080`, а при заданном `Metrics__ScrapeToken` значение совпадает в `.env`.

### 4.2. Дашборды

Grafana → папка **MusicAntiBlur**:

| Дашборд | Что показывает |
|---|---|
| **API** | запросы в секунду по маршрутам, латентность p50 и p95, доля 5xx, топ маршрутов с ошибками, отказы rate limiter |
| **Фоновые задачи** | перекодирование по результатам и длительности, очередь Hangfire, письма, загрузки исходников |
| **Плеер** | число подключений SignalR, выданные playback URL по источникам (`catalog`, `private`, `local`) |

Метрики, которых нет на дашбордах, но которые собираются: `mab_quota_rejections_total` (отказы по квоте), `mab_rate_limited_total{scope}` (разбивка по типам лимитов).

### 4.3. Алерты

Алерты приходят письмом на `ALERT_EMAIL_TO` через SMTP Grafana. Локально письма доходят в MailHog (http://localhost:8025), для реального ящика задайте `GRAFANA_SMTP_*` (см. `.env.local.example`).

| Алерт | Срабатывает, когда |
|---|---|
| Transcode failed | за 10 мин хотя бы одно перекодирование ушло в `failed` |
| Hangfire failed jobs grow | за 15 мин прибавились упавшие задачи |
| API 5xx ratio | доля 5xx выше 5 % за 5 мин |
| API p95 latency | p95 выше 2 с 10 мин подряд |
| API down | Prometheus не получает метрики 2 мин |
| Emails failing | за 15 мин были ошибки отправки писем |

В тексте алерта есть ссылка на дашборд и на Hangfire. Правила лежат в [devops/observability/grafana/provisioning/alerting/rules.yml](../devops/observability/grafana/provisioning/alerting/rules.yml).

### 4.4. Найти все логи запроса

1. Возьмите `X-Request-Id` из заголовка ответа или `requestId` из тела ошибки.
2. Grafana → Explore → источник Loki:

```text
{app="musicantiblur-api"} | json | RequestId="<id>"
```

В выдачу попадают и строки фоновых задач, поставленных этим запросом.

---

## 5. Скрипты запуска и остановки

Скрипты лежат в [devops/](../devops/). Windows: `devops\start.cmd`, `devops\stop.cmd` (запускают `.ps1`). Git Bash, Linux, macOS: `bash devops/start.sh`, `bash devops/stop.sh`. Команды выполняются из корня репозитория.

### 5.1. `start`

Без аргументов запускается мастер: язык → тип запуска → 0–2 Flutter-клиента → импорт музыки. Мастер запоминает выбор в `devops/.run/last-start.env` и в следующий раз предлагает «Запустить конфигурацию с прошлого раза». Ответьте **N**, чтобы пройти мастер заново.

Что делает скрипт: проверяет Docker (при необходимости ждёт Docker Desktop) → поднимает Compose (Postgres, Redis, MailHog, MinIO) и ждёт их `healthy` до 90 с → проверяет FFmpeg (предлагает установить) → запускает API и ждёт `/health` до 90 с → при согласии импортирует музыку → запускает Flutter.

| Режим | Что запускается |
|---|---|
| `local` | инфраструктура + API (Development) + выбранные Flutter-клиенты |
| `api` | то же, но без Flutter: только сервер и данные |
| `dual` | `local` с двумя клиентами: Chrome и Android-эмулятор |
| `publish` | инфраструктура + API в режиме **Production** (`dotnet publish -c Release` в `devops/.run/api`), без Flutter. В Production нужны настроенные Storage и, при `Storage__UseCdn=true`, Cdn |

Режим и устройства можно задать аргументами, без мастера:

Локально (Git Bash):

```bash
bash devops/start.sh api
START_LANG=en START_DEVICE1=chrome START_DEVICE2=emulator bash devops/start.sh local
```

Локально (PowerShell):

```powershell
devops\start.cmd -Mode local -Lang ru -Device1 chrome -Device2 none
```

`Device`: `chrome`, `windows`, `emulator` (запуск или использование уже запущенного эмулятора), id устройства из `flutter devices` (например, `emulator-5554` или USB-телефон) или `none`. Только один клиент может быть эмулятором.

Логи и PID-файлы: `devops/.run/` (`api.log`, `api.pid`, `flutter-*.log`). Flutter открывается в отдельном окне терминала; если окно открыть нельзя, он работает в фоне, а лог лежит в `devops/.run/flutter-*.log`.

### 5.2. `stop`

Останавливает API, Flutter, приложение в эмуляторе и Compose.

```bash
bash devops/stop.sh            # данные сохраняются
bash devops/stop.sh --volumes  # ещё и удалить данные Postgres, MinIO и стека наблюдаемости
```

В PowerShell флаг называется `-Volumes`. **С `--volumes` пропадают пользователи, каталог, загруженные файлы и ключи Data Protection.** После этого у всех пользователей слетает 2FA по приложению, а локальный API сам создаст чистую БД при следующем старте.

### 5.3. Сброс «с нуля» в разработке

```bash
bash devops/stop.sh --volumes && bash devops/start.sh
```

---

## 6. Скрипты наполнения каталога

### 6.1. `seed-local-music`

Создаёт исполнителей, альбомы и треки по папкам с аудио и загружает исходники и обложки через админ-API. Запускается мастером после старта API или вручную:

```bash
bash devops/seed-local-music.sh
```

Настройка через переменные окружения:

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `API_BASE` | `http://127.0.0.1:5080` | адрес API |
| `MUSIC_ROOT` | `no_commit/music` | корневая папка с музыкой |
| `LOGIN` / `PASSWORD` | `admin` / `AdminPassword123` | учётка админа |
| `MIN_TRACKS` | `4` | сколько треков брать из каждой папки (если файлов меньше, то все) |

Форматы: `mp3`, `m4a`, `mp4`, `flac`, `wav`, `ogg`, `aac`. Обложка берётся из картинки в папке или из тегов файла. Нужен `pwsh` или `python3` плюс `curl`. Папки `no_commit/` в git нет: музыку нужно положить самому. Если папки нет, скрипт сообщает об этом и ничего не делает.

В Development лимиты на импорт (`admin-import`, `private-import`) не применяются, поэтому массовая загрузка не упирается в «10 в час».

### 6.2. `upload-catalog-source`

Загружает **один** файл как исходник трека и запускает перекодирование.

```bash
TRACK_ID=<uuid трека> bash devops/upload-catalog-source.sh /path/to/file.mp3
```

`TRACK_ID` по умолчанию — id трека из сид-данных Development. Остальные переменные (`API_BASE`, `LOGIN`, `PASSWORD`) те же, что выше. Результат — готовые рендиции: проверьте `GET /admin/tracks/{id}/renditions` или Hangfire.

---

## 7. Проверка квот загрузки

Квота ограничивает **приватные копии**, которые пользователь загружает на сервер. По умолчанию **2 ГБ и 500 файлов на пользователя**; отдельный файл — не больше 100 МБ. Квота считает активную копию каждого трека и загрузки в процессе; заменённые и упавшие копии не считаются.

Настройки по умолчанию: `Storage__PrivateQuotaBytes` и `Storage__PrivateQuotaFiles` в `.env`. Переопределение на пользователя хранится в таблице `user_quotas`.

### 7.1. Скрипт `no_commit/upload-private.ps1`

Скрипт загружает приватные копии под выбранным пользователем и умеет менять его квоту. Он лежит в `no_commit/`, то есть **вне git**: скопируйте его себе или перенесите в `devops/`, если он нужен команде. Запуск из PowerShell, API должен работать.

Настройки в начале файла (или параметры командной строки):

| Параметр | По умолчанию | Смысл |
|---|---|---|
| `-Mode` | `Random` | `File` — загрузить файл с диска; `Random` — сгенерировать mp3 через ffmpeg; `Quota` — только изменить квоту, без загрузки |
| `-FilePath` | `no_commit\music\track.mp3` | путь к файлу в режиме `File` |
| `-SizeMB` | `20` | размер сгенерированного файла, 1–100 МБ |
| `-Count` | `1` | сколько файлов загрузить; каждый раз новый файл и новый трек |
| `-TrackId` | пусто | трек, к которому привязать копию; пусто — взять из каталога |
| `-SetQuotaMB` | `-1` (не менять) | задать лимит объёма в МБ |
| `-SetQuotaFiles` | `-1` (не менять) | задать лимит числа файлов |
| `-ResetQuota` | выкл. | вернуть квоту к значениям по умолчанию |
| `-ApiBase`, `-Login`, `-Password` | `127.0.0.1:5080`, `admin` | куда и под кем загружать |
| `-Ffmpeg` | `ffmpeg` | путь к ffmpeg для режима `Random` |

Скрипт печатает квоту до и после каждой загрузки. Менять квоту может только пользователь с ролью `admin`, и меняется она у пользователя `-Login`. Запрос задаёт оба поля сразу: если указать только `-SetQuotaMB`, лимит файлов вернётся к умолчанию. Чтобы изменить одно значение и сохранить другое, укажите оба параметра. Если у пользователя включена 2FA, скрипт спросит код.

### 7.2. Сценарии проверки

Локально (PowerShell):

```powershell
# 1. Упереться в лимит объёма: квота 25 МБ, три файла по 20 МБ
powershell -ExecutionPolicy Bypass -File no_commit\upload-private.ps1 `
  -SetQuotaMB 25 -SetQuotaFiles 500 -Mode Random -SizeMB 20 -Count 3

# 2. Упереться в лимит числа файлов: один файл на пользователя
powershell -ExecutionPolicy Bypass -File no_commit\upload-private.ps1 `
  -SetQuotaMB 2048 -SetQuotaFiles 1 -Mode Random -SizeMB 1 -Count 3

# 3. Загрузить свой файл
powershell -ExecutionPolicy Bypass -File no_commit\upload-private.ps1 -Mode File -FilePath "D:\music\song.mp3"

# 4. Только поменять квоту / вернуть по умолчанию
powershell -ExecutionPolicy Bypass -File no_commit\upload-private.ps1 -Mode Quota -SetQuotaMB 25 -SetQuotaFiles 1
powershell -ExecutionPolicy Bypass -File no_commit\upload-private.ps1 -Mode Quota -ResetQuota
```

**Ожидаемый результат при превышении:** скрипт печатает «СЕРВЕР ОТКЛОНИЛ ЗАГРУЗКУ: квота исчерпана (HTTP 413)» и останавливается. В бакете новый объект не создаётся. API отвечает `413 quota_exceeded` с блоком `quota: { usedBytes, maxBytes, usedFiles, maxFiles }`.

Учтите, что в квоту входят и **все прежние** загрузки этого пользователя. Если вы уже загружали файлы под `admin`, проверка упрётся в лимит раньше, чем ожидается. Это видно по строке «Квота: X из Y МБ». Чтобы начать с чистого листа, удалите копии в приложении или пересоздайте данные (`stop --volumes`).

### 7.3. Без скрипта

Локально (Git Bash), токен админа из [п. 2.1](#21-получить-токен):

```bash
# текущее состояние пользователя
curl -s $API/admin/users/<USER_ID>/quota -H "Authorization: Bearer $ADMIN"

# квота 5 МБ и 1 файл
curl -X PUT $API/admin/users/<USER_ID>/quota -H "Authorization: Bearer $ADMIN" \
  -H 'Content-Type: application/json' -d '{"maxBytes":5242880,"maxFiles":1}'

# снять переопределение (вернуть значения по умолчанию)
curl -X PUT $API/admin/users/<USER_ID>/quota -H "Authorization: Bearer $ADMIN" \
  -H 'Content-Type: application/json' -d '{}'
```

`<USER_ID>` — `select id, login from users;` в Postgres или поле `id` из `GET /me`. Пользователь видит свою квоту через `GET /me/quota` и в приложении: **Настройки → Хранилище**. Приложение проверяет квоту ещё до расчёта хеша файла, а сервер перепроверяет её при `initiate`.

### 7.4. Сгенерировать файл вручную

ffmpeg нужен API для перекодирования, поэтому он уже установлен. Сервер проверяет файл ffprobe, так что случайные байты не подойдут: нужен настоящий звук.

Локально (Git Bash):

```bash
# ≈ 2,4 МБ на минуту при 320 кбит/с; 2400 секунд ≈ 95 МБ
ffmpeg -f lavfi -i "sine=frequency=440:duration=2400" -b:a 320k test-95mb.mp3
```

### 7.5. Что ещё смотреть

- Метрика `mab_quota_rejections_total` растёт при каждом отказе по квоте (Grafana → Explore → Prometheus).
- В Postgres: `select * from user_quotas;` показывает переопределения.
- Правила и граничные случаи квоты — [03-api-contract.md](03-api-contract.md) §5.

---

## 8. Типичные проблемы

| Симптом | Причина и что делать |
|---|---|
| `start` не видит устройства Flutter | из Git Bash, запущенного через PowerShell, раньше `flutter` не находился из-за порядка `PATH`. Исправлено в скриптах (`/usr/bin` первым). Если повторяется, проверьте `flutter devices` в том же терминале |
| «Оконный терминал не найден, Flutter в фоне» | `start.sh` умеет открывать окна только в Linux-терминалах. Flutter при этом работает, лог в `devops/.run/flutter-*.log`. Для окон и hot reload используйте `devops\start.cmd` |
| `403 admin_required` | у пользователя нет роли `admin` или токен выдан до её присвоения. Войдите заново |
| `401` на всех запросах админа | access-токен истёк, либо включена 2FA и вход не завершён вторым шагом |
| `413 quota_exceeded` | квота пользователя исчерпана. Проверьте `GET /me/quota`, увеличьте лимит или удалите копии |
| Hangfire не открывается | неверные Basic-учётные данные: проверьте `Hangfire__DashboardUser` и `Hangfire__DashboardPassword` |
| `/metrics` отвечает `404` | вне Development без `Metrics__ScrapeToken` эндпоинт закрыт намеренно |
| Grafana: «API down» при работающем API | Prometheus не достучался до `host.docker.internal:5080` или токен `/metrics` не совпадает |
| Перекодирование `failed` | `ErrorMessage` в рендиции. Частая причина: FFmpeg не найден (`Media__FfmpegPath`). Исправить и вызвать `POST /admin/tracks/{id}/transcode` |
| Не приходят письма-алерты | локально смотрите MailHog (http://localhost:8025); для реального ящика заданы ли `GRAFANA_SMTP_*` |

---

## 9. Веб-админка каталога

Запуск: локально `devops/start.*` поднимает её сам на `http://127.0.0.1:8090`; вручную — `cd src/mobile && flutter run -d chrome -t lib/main_admin.dart --web-port 8090` (адрес API — `--dart-define=API_BASE_URL=...`). Вход обычной формой, с 2FA тоже. Пользователь без роли `admin` видит экран «403 · нужна роль admin».

| Раздел | Что делает |
|---|---|
| **Каталог** | исполнители (создать, переименовать, удалить) → альбомы (название, год, обложка JPEG/PNG до 5 МБ) → треки (название, номер, ISRC). У трека статус: «Нет файла», «В работе», Ready, Failed; список сам обновляется, пока идёт перекодирование |
| **Трек** | таблица рендиций: качество, статус, битрейт, активность, `ErrorMessage`. Для `failed` есть «Повторить» (одна генерация) и «Перекодировать» (все). «Новый файл» загружает исходник заново |
| **Корзина** | удалённые треки; «Восстановить» возвращает трек, если его номер и ISRC не заняты. Срок хранения 6 месяцев, затем файлы и запись стираются |
| **Импорт** | выбор папки целиком, предпросмотр, запуск |

**Загрузка исходника.** Файл до 100 МБ читается в память, считается SHA-256, части (5–16 МиБ) уходят по presigned URL по 3 параллельно; сбойная часть повторяется до 3 раз с новым URL; кнопка «Отменить» вызывает `DELETE` загрузки.

**Импорт папки.** Структура `Исполнитель/Альбом/01 - Трек.mp3`; рядом `cover.jpg` (имена `cover`, `folder`, `front`, `album`, `artwork`). Одна папка с аудио — один альбом; исполнитель берётся из имени родительской папки, его и название альбома можно поправить до запуска. Номер и название трека берутся из имени файла (`01 - Intro.mp3`, `2. Song.flac`), теги аудио в браузере не читаются; без номера трек получает свободный. Исполнитель с таким именем (без учёта регистра) переиспользуется, иначе создаётся. Треки грузятся по 2 параллельно; сбой одного не останавливает остальные, «Повторить неудачные» перезапускает только их. Выбор папки работает в Chrome и Edge; в других браузерах доступен выбор отдельных файлов (структура папок теряется, один альбом на выбор).

**Ограничения.** Повторный импорт той же папки создаёт альбом заново (дедупликации нет). Альбом и исполнителя нельзя удалить, пока есть треки (в том числе в корзине) или альбомы: `409 has_dependents`.

**Жанры.** Раздел «Жанры»: справочник (добавить, переименовать, удалить с предупреждением о числе затронутых треков и альбомов). На страницах альбома и трека кнопка «Жанры» открывает выбор до 10 жанров. При загрузке файла с тегом `genre` жанр создаётся и ставится сам, ручной выбор не затирается. У уже загруженных треков жанры появятся при перетранскоде или вручную; отдельной команды «перечитать теги» нет.

**Поиск.** Строка поиска на странице «Каталог» ищет по исполнителям, альбомам, трекам и жанрам, в том числе по треку из корзины (метка «удалён», переход в корзину).

**Если не загружается.** `ETag` не виден браузеру или PUT блокируется: проверьте CORS бакета (`PUT`, `ExposeHeaders: ETag`) и `Cors__AllowedOrigins` для API.
