# Руководство для ИИ-агентов

Перед кодом, миграциями и советами по архитектуре прочитай этот файл, затем документы из §2. Если внутренний документ и внешняя статья расходятся — **побеждает `docs/` этого репозитория**.

Рабочий язык репозитория: русский (продукт, комменты к доменам). Идентификаторы кода, таблиц и HTTP — английский, как в [02-database-overview.md](02-database-overview.md).

---

## 1. Что это за продукт (коротко)

**Music Anti Blur** — стриминг с каталогом на сервере. Отличие: пользователь подменяет каталожный трек **своим** файлом (локально и/или приватной копией в Object Storage) и выбирает источник: `catalog` | `local` | `private`.

MVP-клиент — только **Flutter**. API — **ASP.NET Core**. Аудиобайты API не стримит: метаданные + короткий signed URL, плеер качает с **Yandex CDN**.

Не выдумывай фичи из «типичного Spotify». Список вне MVP и out of scope — в [01-product-plan.md](01-product-plan.md) §5.

---

## 2. Документы репозитория (`docs/`)

Читать в этом порядке, если задача не указывает иное.

| Документ | Зачем агенту |
|---|---|
| [00-ai-agents.md](00-ai-agents.md) | Этот файл: приоритет источников, стек, внешние паттерны |
| [01-product-plan.md](01-product-plan.md) | Скоуп MVP, стек, auth, качества, подмена, SignalR, критерии готовности |
| [02-database-overview.md](02-database-overview.md) | Целевая схема Postgres: таблицы, CHECK, индексы, каскады, ключи S3, чего не создавать |

Якоря, которые чаще всего нужны:

- Стек и схема компонентов: [01-product-plan.md §2](01-product-plan.md)
- Ограничения разработчика (нет дизайна, нет веба, нет reco): [01-product-plan.md §3](01-product-plan.md)
- Регистрация email **или** login, reset по почте: [01-product-plan.md §4.1](01-product-plan.md)
- Качества и профили FFmpeg: [01-product-plan.md §4.4](01-product-plan.md)
- Local / private upload: [01-product-plan.md §4.5](01-product-plan.md)
- ER и DDL: [02-database-overview.md §4](02-database-overview.md) и [§16](02-database-overview.md)
- Таблицы, которых нет в MVP: [02-database-overview.md §14](02-database-overview.md)

Спринты разработки лежат в `no_commit/sprints/` (каталог в `.gitignore`). Это рабочие заметки для людей. Если `docs/` и спринт противоречат — правь код и схему по **`docs/`**, спринт не расширяет скоуп.

---

## 3. Жёсткие правила скоупа

Делай, только если это есть в product plan / database overview:

- Flutter + ASP.NET Core + EF Core + PostgreSQL + Redis + Hangfire + SignalR + FFmpeg + Yandex Object Storage + Yandex CDN + SMTP.
- Вход: явный `identifierType` `email` | `login`, без угадывания по `@`.
- Восстановление пароля по email.
- Несколько качеств (`aac_128`, `aac_256`, опционально `src`).
- Подмена трека + опциональный private upload, ACL только владелец (чужому 404).
- UI: Material 3 из коробки, без визуальной полировки.

Не делай «заодно», пока нет явного запроса и правки `docs/`:

- Blazor / любой браузерный клиент
- плейлисты и избранное
- рекомендации, `listen_events`, `pgvector`, отдельный ML
- OAuth Яндекса
- импорт Spotify / Яндекс Музыки / Apple Music
- микросервисы, Kubernetes, HLS/DASH
- публичный шаринг пользовательских файлов
- хранение аудиобайтов в PostgreSQL
- стриминг аудио телом HTTP-ответа API

Схему БД не «улучшать» в обход [02-database-overview.md](02-database-overview.md): не переименовывать таблицы, не менять каскады, не добавлять ENUM PostgreSQL вместо `text`+CHECK, не класть Hangfire-entity в DbContext.

Секреты (JWT, S3, SMTP, Redis) — только env / user-secrets, не в git.

---

## 4. Стек → официальная документация

Версии в коде фиксируй по `csproj` / `pubspec.yaml`, когда они появятся. Ниже — канонические источники, не блоги как истина.

### 4.1. ASP.NET Core, C#, API

| Тема | Ссылка |
|---|---|
| ASP.NET Core | https://learn.microsoft.com/aspnet/core/introduction-to-aspnet-core |
| Minimal APIs | https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis |
| OpenAPI / Swashbuckle | https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis/openapi |
| Аутентификация | https://learn.microsoft.com/aspnet/core/security/authentication/ |
| JWT Bearer | https://learn.microsoft.com/aspnet/core/security/authentication/jwt-authn |
| `PasswordHasher<T>` | https://learn.microsoft.com/dotnet/api/microsoft.aspnetcore.identity.passwordhasher-1 |
| Авторизация | https://learn.microsoft.com/aspnet/core/security/authorization/introduction |
| Rate limiting | https://learn.microsoft.com/aspnet/core/performance/rate-limit |
| Options / конфигурация | https://learn.microsoft.com/dotnet/core/extensions/options |
| Health checks | https://learn.microsoft.com/aspnet/core/host-and-deploy/health-checks |
| Docker | https://learn.microsoft.com/aspnet/core/host-and-deploy/docker/building-net-docker-images |

Паттерны (не раздувать до микросервисов; у нас **один API-процесс**):

| Тема | Ссылка |
|---|---|
| Типовые архитектуры веб-приложений | https://learn.microsoft.com/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures |
| Модульный монолит vs микросервисы | https://learn.microsoft.com/dotnet/architecture/microservices/architect-microservice-container-applications/monolithic-application |
| REST-соглашения Microsoft | https://github.com/microsoft/api-guidelines/blob/vNext/azure/Guidelines.md |
| Problem Details (ошибки API) | https://www.rfc-editor.org/rfc/rfc9457.html |
| OWASP API Security | https://owasp.org/API-Security/ |

Для MVP достаточно: тонкие endpoints → сервисы приложения → EF `DbContext`. Не внедрять MediatR/CQRS/Clean Architecture «слои ради слоёв», пока нет боли.

### 4.2. EF Core + PostgreSQL + Npgsql

| Тема | Ссылка |
|---|---|
| EF Core | https://learn.microsoft.com/ef/core/ |
| Модели и Fluent API | https://learn.microsoft.com/ef/core/modeling/ |
| Миграции | https://learn.microsoft.com/ef/core/managing-schemas/migrations/ |
| Npgsql EF provider | https://www.npgsql.org/efcore/ |
| Naming (snake_case) | https://www.npgsql.org/efcore/modeling/naming.html |
| JSON / `jsonb` | https://www.npgsql.org/efcore/mapping/json.html |
| PostgreSQL 16 | https://www.postgresql.org/docs/16/index.html |
| `pg_trgm` | https://www.postgresql.org/docs/16/pgtrgm.html |
| Partial indexes | https://www.postgresql.org/docs/16/indexes-partial.html |
| Constraints | https://www.postgresql.org/docs/16/ddl-constraints.html |

Паттерн: **миграции EF — единственный способ менять схему** ([01-product-plan.md §7](01-product-plan.md)). Целевой DDL в overview — ориентир, не копипаста в обход EF.

### 4.3. Redis

| Тема | Ссылка |
|---|---|
| Redis docs | https://redis.io/docs/latest/ |
| StackExchange.Redis | https://stackexchange.github.io/StackExchange.Redis/ |
| IDistributedCache + Redis | https://learn.microsoft.com/aspnet/core/performance/caching/distributed |
| SignalR Redis backplane | https://learn.microsoft.com/aspnet/core/signalr/redis-backplane |

В Postgres не дублировать rate limit и presence. Signed URL в Redis кэшировать с TTL **короче** подписи.

### 4.4. SignalR

| Тема | Ссылка |
|---|---|
| Обзор хабов | https://learn.microsoft.com/aspnet/core/signalr/introduction |
| Хабы | https://learn.microsoft.com/aspnet/core/signalr/hubs |
| Auth на хабе | https://learn.microsoft.com/aspnet/core/signalr/authn-and-authz |
| Масштаб / backplane | https://learn.microsoft.com/aspnet/core/signalr/scale |
| .NET клиент | https://learn.microsoft.com/aspnet/core/signalr/dotnet-client |
| Flutter-клиент (пакет) | https://pub.dev/packages/signalr_netcore |

Паттерн: сервер **не играет аудио**. Хаб = снимок `playback_states` + broadcast. Last-write-wins по `updated_at`. Не сериализовать `IHubContext` в Hangfire — джоба резолвит хаб через DI ([Hangfire + IHubContext](https://docs.hangfire.io/en/latest/getting-started/aspnet-core-applications.html)).

### 4.5. Hangfire

| Тема | Ссылка |
|---|---|
| Документация | https://docs.hangfire.io/en/latest/ |
| ASP.NET Core | https://docs.hangfire.io/en/latest/getting-started/aspnet-core-applications.html |
| Dashboard + auth | https://docs.hangfire.io/en/latest/configuration/using-dashboard.html |
| Storage PostgreSQL | https://github.com/hangfire-postgres/Hangfire.PostgreSql |
| Best practices | https://docs.hangfire.io/en/latest/best-practices.html |

Паттерн: идемпотентные джобы транскода (`trackId` / `(userId, trackId)`), лимит параллелизма (`WorkerCount` / `DisableConcurrentExecution`). Схема `hangfire` не в EF. Письма reset — тоже Hangfire, состояние токена в `password_reset_tokens`.

### 4.6. Object Storage, CDN, Range, signed URL

Yandex Object Storage — S3-совместимый API, регион подписи обычно `ru-central1`, endpoint `https://storage.yandexcloud.net`.

| Тема | Ссылка |
|---|---|
| Object Storage | https://yandex.cloud/ru/docs/storage/ |
| S3 API | https://yandex.cloud/ru/docs/storage/s3/ |
| Pre-signed URLs | https://yandex.cloud/ru/docs/storage/concepts/pre-signed-urls |
| Подпись запросов (SigV4) | https://yandex.cloud/ru/docs/storage/s3/signing-requests |
| Скачать по pre-signed | https://yandex.cloud/ru/docs/storage/operations/objects/link-for-download |
| Cloud CDN | https://yandex.cloud/ru/docs/cdn/ |
| CDN + bucket origin | https://yandex.cloud/ru/docs/cdn/quickstart/bucket |
| AWS pre-signed GET (совместимая модель) | https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html |
| AWS SDK for .NET, S3 | https://docs.aws.amazon.com/sdk-for-net/v3/developer-guide/s3-apis-intro.html |
| HTTP Range | https://httpwg.org/specs/rfc9110.html#range.requests |

Паттерн: бакет **приватный**; API отдаёт JSON `{ url, expiresAt, quality }`; плеер делает Range GET на **CDN**. Каталог: ключи `tracks/{trackId}/...`. Private: `users/{userId}/overrides/{trackId}/...`. Публичных вечных URL нет.

### 4.7. FFmpeg

| Тема | Ссылка |
|---|---|
| Документация | https://ffmpeg.org/documentation.html |
| CLI | https://ffmpeg.org/ffmpeg.html |
| ffprobe | https://ffmpeg.org/ffprobe.html |
| AAC | https://trac.ffmpeg.org/wiki/Encode/AAC |

Профили продукта: `aac_128`, `aac_256` (см. план). Не включать HLS, пока его нет в скоупе. Не запускать тяжёлый транскод в HTTP-request; только Hangfire.

### 4.8. Почта

| Тема | Ссылка |
|---|---|
| MailKit | https://github.com/jstedfast/MailKit |
| MailHog (локалка) | https://github.com/mailhog/MailHog |
| smtp4dev | https://github.com/rnwood/smtp4dev |

Паттерн: `forgot-password` всегда 200. Токен в БД только хеш. Письмо простое текстовое. Токены и пароли не логировать.

### 4.9. Flutter (единственный клиент MVP)

| Тема | Ссылка |
|---|---|
| Flutter | https://docs.flutter.dev/ |
| Material 3 | https://docs.flutter.dev/ui/design/material |
| Навигация | https://docs.flutter.dev/ui/navigation |
| iOS background audio | https://docs.flutter.dev/platform-integration/ios/background |
| Android background | https://docs.flutter.dev/platform-integration/android/background |
| `just_audio` | https://pub.dev/packages/just_audio |
| `audio_service` | https://pub.dev/packages/audio_service |
| Tutorial audio_service | https://github.com/ryanheise/audio_service/wiki/Tutorial |
| `audio_session` | https://pub.dev/packages/audio_session |
| `dio` | https://pub.dev/packages/dio |
| `flutter_secure_storage` | https://pub.dev/packages/flutter_secure_storage |
| `file_picker` | https://pub.dev/packages/file_picker |
| `go_router` | https://pub.dev/packages/go_router |
| Android SAF | https://developer.android.com/training/data-storage/shared/documents-files |
| iOS security-scoped bookmarks | https://developer.apple.com/documentation/foundation/url/1779698-startaccessingsecurityscopedreso |

Паттерн плеера: один `AudioHandler` (`audio_service` + `just_audio`). В очередь класть `trackId`, URL резолвить в момент play. Смена качества — новый файл, seek в **секундах**. Локальный path в API не отправлять.

### 4.10. Auth, пароли, JWT (безопасность)

| Тема | Ссылка |
|---|---|
| JWT (RFC 7519) | https://datatracker.ietf.org/doc/html/rfc7519 |
| OWASP Password Storage | https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html |
| OWASP Authentication | https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html |
| OWASP Forgot Password | https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html |

Паттерн продукта: refresh в БД (хеш), logout-all = revoke; одинаковое сообщение на неверный логин/пароль; login и forgot — rate limit через Redis.

### 4.11. Инфра локально

| Тема | Ссылка |
|---|---|
| Docker Compose | https://docs.docker.com/compose/ |
| PostgreSQL Docker | https://hub.docker.com/_/postgres |
| Redis Docker | https://hub.docker.com/_/redis |

Ожидаемый compose: Postgres 16 + Redis + MailHog. FFmpeg — на машине/образе API, не в письмах.

---

## 5. Как агенту принимать решения

1. Задача меняет скоуп продукта? Сначала [01-product-plan.md](01-product-plan.md), не «как в Spotify».
2. Задача про таблицы, индексы, FK? Только [02-database-overview.md](02-database-overview.md).
3. Задача про «как это принято в .NET / Flutter / S3»? Таблица §4, затем официальный doc, не случайный Medium.
4. Не уверен, в MVP ли фича — **не делать**. Список «вне MVP» в плане.
5. Дизайн экранов не изобретать: стандартные виджеты Material 3, стабильные имена роутов.
6. Не коммить `no_commit/` и секреты.

Когда добавляешь новую технологию в стек — сначала правка product plan, потом код, и добавь строку в §4 этого файла.

---

## 6. Карта «фича → где правда»

| Фича | Документ |
|---|---|
| Регистрация / login type / reset | [01-product-plan.md §4.1](01-product-plan.md), таблицы `users`, `*_tokens` в overview |
| Каталог, поиск | план §4.2, `artists` / `albums` / `tracks` |
| Качества, transcode | план §4.4, `track_renditions` |
| Плеер, очередь | план §4.3, `playback_states` |
| Local + private | план §4.5, `user_track_overrides`, `user_private_renditions` |
| SignalR | план §4.6 |
| Что не создавать в БД | overview §14 |
