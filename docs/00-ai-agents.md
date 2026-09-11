# Руководство для ИИ-агентов

Перед кодом, миграциями и советами по архитектуре прочитай этот файл, затем документы из §2. Если внутренний документ и внешняя статья расходятся — **побеждает `docs/` этого репозитория**.

Рабочий язык репозитория: русский (продукт, комменты к доменам). Идентификаторы кода, таблиц и HTTP — английский, как в [02-database-overview.md](02-database-overview.md).

---

## 1. Что это за продукт (коротко)

**Music Anti Blur** — стриминг с каталогом на сервере. Отличие: пользователь подменяет каталожный трек **своим** файлом (локально и/или приватной копией в Object Storage) и выбирает preference: `auto` | `catalog` | `local` | `private`.

MVP-клиент — только **Flutter**. API — **ASP.NET Core**. Аудиобайты API не принимает и не стримит: upload идёт presigned multipart прямо в Object Storage, playback — по Yandex CDN secure-token URL.

Не выдумывай фичи из «типичного Spotify». Список вне MVP и out of scope — в [01-product-plan.md](01-product-plan.md) §5.

---

## 2. Документы репозитория (`docs/`)

Читать в этом порядке, если задача не указывает иное.

| Документ | Зачем агенту |
|---|---|
| [00-ai-agents.md](00-ai-agents.md) | Этот файл: приоритет источников, стек, внешние паттерны |
| [01-product-plan.md](01-product-plan.md) | Скоуп MVP, стек, auth, качества, подмена, SignalR, критерии готовности |
| [02-database-overview.md](02-database-overview.md) | Целевая схема Postgres: таблицы, CHECK, индексы, каскады, ключи S3, чего не создавать |
| [03-api-contract.md](03-api-contract.md) | Нормативные HTTP/SignalR routes, DTO, ошибки, idempotency и rate limits |
| [04-operations.md](04-operations.md) | FFmpeg boundary, jobs, CDN/S3, telemetry, backup, deploy и retention |

Якоря, которые чаще всего нужны:

- Стек и схема компонентов: [01-product-plan.md §2](01-product-plan.md)
- Ограничения разработчика (нет дизайна, нет веба, нет reco): [01-product-plan.md §3](01-product-plan.md)
- Регистрация email **или** login, reset по почте: [01-product-plan.md §4.1](01-product-plan.md)
- Качества и профили FFmpeg: [01-product-plan.md §4.4](01-product-plan.md)
- Local / private upload: [01-product-plan.md §4.5](01-product-plan.md)
- ER и DDL: [02-database-overview.md §4](02-database-overview.md) и [§16](02-database-overview.md)
- Таблицы, которых нет в MVP: [02-database-overview.md §14](02-database-overview.md)
- HTTP/SignalR: [03-api-contract.md](03-api-contract.md)
- Production-инварианты и cleanup: [04-operations.md](04-operations.md)

Спринты разработки лежат в `no_commit/sprints/` (каталог в `.gitignore`). Это рабочие заметки для людей. Если `docs/` и спринт противоречат — правь код и схему по **`docs/`**, спринт не расширяет скоуп.

---

## 3. Жёсткие правила скоупа

Делай, только если это есть в product plan / database overview:

- Flutter + ASP.NET Core + EF Core + PostgreSQL + Redis + Hangfire + SignalR + FFmpeg + Yandex Object Storage + Yandex CDN + SMTP.
- Регистрация: обязательны `login` и `email`. Вход: явный `identifierType` `email` | `login`, без угадывания по `@`.
- Verified email, одноразовая refresh rotation и атомарный reset с отзывом сессий.
- Несколько качеств (`aac_128`, `aac_256`, опционально `src`).
- Подмена + presigned multipart private upload с immutable generation, ACL только владелец (чужому 404).
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

В Postgres не дублировать rate limit и presence. CDN URL cache key включает owner/rendition/generation; ACL проверять до lookup, TTL кэша короче подписи. При отказе Redis auth/upload/private URL и playback writer mutation fail closed по `03-api-contract.md`; GET snapshot может работать degraded.

### 4.4. SignalR

| Тема | Ссылка |
|---|---|
| Обзор хабов | https://learn.microsoft.com/aspnet/core/signalr/introduction |
| Хабы | https://learn.microsoft.com/aspnet/core/signalr/hubs |
| Auth на хабе | https://learn.microsoft.com/aspnet/core/signalr/authn-and-authz |
| Масштаб / backplane | https://learn.microsoft.com/aspnet/core/signalr/scale |
| .NET клиент | https://learn.microsoft.com/aspnet/core/signalr/dotnet-client |
| Flutter-клиент (пакет) | https://pub.dev/packages/signalr_netcore |

Паттерн: сервер **не играет аудио**. Хаб = versioned snapshot `playback_states` + broadcast после DB commit. Порядок задаёт монотонная `revision`, stale event клиент игнорирует; `updated_at` не используется для конкуренции. Не сериализовать `IHubContext` в Hangfire — job резолвит хаб через DI.

### 4.5. Hangfire

| Тема | Ссылка |
|---|---|
| Документация | https://docs.hangfire.io/en/latest/ |
| ASP.NET Core | https://docs.hangfire.io/en/latest/getting-started/aspnet-core-applications.html |
| Dashboard + auth | https://docs.hangfire.io/en/latest/configuration/using-dashboard.html |
| Storage PostgreSQL | https://github.com/hangfire-postgres/Hangfire.PostgreSql |
| Best practices | https://docs.hangfire.io/en/latest/best-practices.html |

Паттерн: transcode job всегда получает `generationId`, использует lease + CAS и пишет только generation-aware keys. `DisableConcurrentExecution` не заменяет идемпотентность. Удаление S3 — только через `object_deletions`; recovery и лимиты — в `04-operations.md`. Схема `hangfire` не в EF.

### 4.6. Object Storage upload, CDN secure token, Range

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
| CDN secure tokens | https://yandex.cloud/ru/docs/cdn/concepts/secure-tokens |
| AWS SDK for .NET, S3 | https://docs.aws.amazon.com/sdk-for-net/v3/developer-guide/s3-apis-intro.html |
| HTTP Range | https://httpwg.org/specs/rfc9110.html#range.requests |

Паттерн:

- Бакет и origin приватные.
- Upload: S3 SigV4 presigned multipart PUT, API bytes не проксирует.
- Playback: **CDN secure token**, не S3 pre-signed GET с заменой hostname.
- Ответ discriminated по `delivery`: для CDN — `{ url, expiresAt, resolvedSource, resolvedQuality, generationId }`, для local — `url/expiresAt/generationId = null`. Плеер делает Range GET и re-resolve после expiry/первого 401/403.
- Ключи включают immutable `generations/{generationId}`; original filename в key не использовать.

### 4.7. FFmpeg

| Тема | Ссылка |
|---|---|
| Документация | https://ffmpeg.org/documentation.html |
| CLI | https://ffmpeg.org/ffmpeg.html |
| ffprobe | https://ffmpeg.org/ffprobe.html |
| AAC | https://trac.ffmpeg.org/wiki/Encode/AAC |

Профили продукта: `aac_128`, `aac_256` (см. план). Не включать HLS. Не запускать транскод в HTTP-request; только Hangfire. Вход недоверенный: HEAD/size, full-file SHA-256 при чтении, ffprobe, allowlist, sandbox, timeout и resource limits из `04-operations.md`.

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

Паттерн плеера: один `AudioHandler`. Queue item имеет `itemId` + `trackId`, snapshot — `currentItemId` + `revision`. URL резолвить в момент play и обновлять по expiry. Позиции в API/DB — **миллисекунды**; при смене файла clamp к duration. Локальный URI в API не отправлять.

### 4.10. Auth, пароли, JWT (безопасность)

| Тема | Ссылка |
|---|---|
| JWT (RFC 7519) | https://datatracker.ietf.org/doc/html/rfc7519 |
| OWASP Password Storage | https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html |
| OWASP Authentication | https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html |
| OWASP Forgot Password | https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html |

Паттерн продукта: email verification + recent re-auth для bind; refresh hash с family/rotation/reuse detection; reset атомарно отзывает все sessions; одинаковое сообщение на неверный login/password. Полная rate-limit matrix — `03-api-contract.md`.

### 4.11. Инфра локально

| Тема | Ссылка |
|---|---|
| Docker Compose | https://docs.docker.com/compose/ |
| PostgreSQL Docker | https://hub.docker.com/_/postgres |
| Redis Docker | https://hub.docker.com/_/redis |

Ожидаемый compose: Postgres 16 + Redis + MailHog. FFmpeg pin в API image. Production probes, backup, graceful deploy и restore drill — `04-operations.md`.

---

## 5. Как агенту принимать решения

1. Задача меняет скоуп продукта? Сначала [01-product-plan.md](01-product-plan.md), не «как в Spotify».
2. Задача про таблицы, индексы, FK? Только [02-database-overview.md](02-database-overview.md).
3. Задача про route/DTO/status/SignalR event? Только [03-api-contract.md](03-api-contract.md).
4. Задача про FFmpeg/CDN/jobs/deploy/backup? [04-operations.md](04-operations.md).
5. Задача про «как это принято в .NET / Flutter / S3»? Таблица §4, затем официальный doc.
6. Не уверен, в MVP ли фича — **не делать**. Список «вне MVP» в плане.
7. Дизайн экранов не изобретать: Material 3, стабильные имена роутов.
8. Не коммить `no_commit/` и секреты.

Когда добавляешь новую технологию в стек — сначала правка product plan, потом код, и добавь строку в §4 этого файла.

---

## 6. Карта «фича → где правда»

| Фича | Документ |
|---|---|
| Регистрация / login type / reset | [01-product-plan.md §4.1](01-product-plan.md), таблицы `users`, `*_tokens` в overview |
| Каталог, поиск | план §4.2, `artists` / `albums` / `tracks` |
| Качества, transcode | план §4.4, `track_renditions` |
| Плеер, очередь | план §4.3, `playback_states` |
| Local + private | план §4.5, upload/rendition tables, API §5 |
| SignalR | план §4.6, API §6 |
| HTTP errors / rate limits | API contract |
| Cleanup / backup / deploy | operations |
| Что не создавать в БД | overview §14 |
