# Music Anti Blur — эксплуатационный контракт

Версия: 1.1
Связанные документы: [00-ai-agents.md](00-ai-agents.md), [01-product-plan.md](01-product-plan.md), [02-database-overview.md](02-database-overview.md), [03-api-contract.md](03-api-contract.md). Локальный стек — [05-local-setup.md](05-local-setup.md).

Документ фиксирует минимальные production-инварианты MVP. Конкретный провайдер мониторинга/backup может измениться, семантика проверок и восстановления — нет.

---

## 1. Topology и конфигурация

- MVP — один deployable ASP.NET Core: HTTP API, SignalR и Hangfire server. PostgreSQL 16, Redis, Yandex Object Storage/CDN и SMTP — внешние зависимости.
- Локально API и FFmpeg работают **на хосте** (не в Compose). Production-цель: FFmpeg/ffprobe pin в container image; образ непривилегированный, read-only root, отдельный temp volume. Образа API в репозитории ещё нет.
- Секреты только env/secret store. При старте валидируются issuer/audience JWT, длина signing key, S3/CDN/SMTP/Redis config; секреты не печатаются.
- Production bucket и CDN origin закрыты. CORS bucket разрешает только необходимые multipart methods/headers приложения.
- Часы всех nodes синхронизируются NTP; допустимый CDN token clock skew фиксируется конфигурацией и тестом.

---

## 2. Недоверенное аудио и FFmpeg

Пользовательские и admin source считаются недоверенными независимо от extension/MIME.

До транскода:

1. S3 HEAD: key/generation и фактический размер. Multipart ETag не трактуется как full-file hash.
2. Worker при чтении source вычисляет SHA-256 полного файла и сравнивает с обязательным expected hash из initiate.
3. Magic bytes + ffprobe JSON; allowlist контейнеров `m4a/mp4`, `mp3`, `flac`, `ogg/opus`, `wav`.
4. Ровно один выбранный audio stream; video/subtitle/data streams игнорируются.
5. Private: ≤ 100 MiB, ≤ 3 600 000 ms; quota ≤ 2 GiB. Невозможные/отрицательные metadata отклоняются.
6. `src` streamable только для поддерживаемого контейнера/кодека, MP4 fast-start и успешного Range/seek probe.

Запуск:

- Аргументы FFmpeg строятся только сервером без shell interpolation.
- Process timeout: ffprobe 30 секунд, private transcode 15 минут, catalog 30 минут.
- На job: максимум 2 CPU, 1 GiB RAM, 2 GiB temp disk; общий `WorkerCount` по capacity.
- Network для media process отключён. stdout/stderr ограничены по размеру; секреты/URL не передаются в аргументах.
- Timeout/OOM/invalid media дают безопасный error code, не raw stderr пользователю.

Ready публикуется одним DB update только после успешного encode, S3 upload, HEAD и metadata validation.

---

## 3. Generation-aware jobs

- Аргументы job: scope, owner при private, trackId, generationId, profileCode.
- Claim: atomic status update + `lease_expires_at`; job продлевает lease heartbeat.
- Stale `processing` после истечения lease может забрать retry той же generation.
- Максимум 5 attempts с exponential backoff + jitter. Invalid media не retry; timeout/network/S3 5xx retry.
- Перед каждым DB transition и publish проверяется generation. Stale job не меняет active generation и перечисляет каждый известный object своей generation в outbox.
- `DisableConcurrentExecution` — дополнительная оптимизация, не гарантия exactly-once.
- `RenditionReady` публикуется после commit и содержит generationId; повтор события безопасен.

Sweeper каждые 5 минут:

- reclaim stale processing;
- abort multipart старше 24 часов;
- переводит generation в failed/cancelled;
- ставит temp objects в `object_deletions`.

---

## 4. Object Storage, CDN и удаление

### 4.1. Upload

- Flutter использует S3 presigned multipart PUT; API не проксирует bytes.
- URL части TTL 15 минут и ограничен exact bucket/key/uploadId/partNumber.
- Complete идемпотентен по `Idempotency-Key`; сервер не доверяет заявленным ETag/size без S3 response/HEAD.
- Original filename не входит в key и проходит sanitization только для UI.

### 4.2. Playback

- API выдаёт Yandex CDN secure-token URL TTL 10 минут, не S3 SigV4 URL. Локально (`Storage__UseCdn=false`) — S3 presigned GET; JSON-поле `delivery` остаётся `cdn`, см. [03-api-contract.md](03-api-contract.md) §4 и [05-local-setup.md](05-local-setup.md).
- CDN валидирует token до cache lookup; unsigned request и token другого path отклоняются.
- Cache identity — object path/generation, auth query не создаёт публичный bypass. Origin принимает чтение только от настроенного CDN.
- Проверяются GET, HEAD, `Range: bytes=...`, 206/416, seek, token expiry и clock skew.
- Redis key включает owner для private, track/rendition/generation/quality; ACL выполняется до lookup; cache TTL ≤ 8 минут.

### 4.3. Outbox и reconciliation

- Request не удаляет S3 напрямую. DB metadata change и `object_deletions` commit одной транзакцией.
- Worker claim использует lease; S3 404 = success; прочие ошибки retry/backoff.
- `done` outbox хранится 30 дней, затем удаляется housekeeping.
- Daily reconciler сравнивает DB generations/outbox с разрешёнными bucket prefixes и ставит каждый orphan object отдельной строкой на удаление после safety window 24 часа.
- Bucket lifecycle abort incomplete multipart через 24 часа; temp/inactive generations удаляются только после outbox/reconciliation.

---

## 5. Health и degraded mode

Endpoints:

Сейчас в коде (локальный `start` ждёт `/health`):

- `GET /health` — PostgreSQL `CanConnect`; 200 `{ status: ok }` или 503. Это текущий readiness-lite, не liveness без зависимостей.
- `GET /health/deps` — Redis ping, SMTP connect, Hangfire storage, S3 HEAD bucket; 200 только если все true. **Не** закрыт отдельной auth.

Production-цель (ещё не разведена в коде):

- `/health/live`: процесс отвечает, без внешних dependencies.
- `/health/ready`: PostgreSQL доступен и migrations совместимы; API может принимать traffic.
- `/health/deps`: диагностирует Redis, S3/CDN, SMTP и Hangfire storage; защищён от публичного доступа.

Политика:

- PostgreSQL недоступен → readiness false, API `503`.
- Redis недоступен → auth mutation, upload/admin, private/CDN URL и playback session create/claim/update fail closed; catalog и `GET playback-state` могут degraded.
- S3/CDN недоступен → metadata read работает, upload/URL issue `503`.
- SMTP недоступен → forgot всё равно не раскрывает email; job retry, alert.
- Hangfire backlog сам по себе не роняет API readiness, но включает alert и блокирует новые uploads при превышении safety threshold.

---

## 6. Логи, метрики и tracing

Structured logs обязательны: timestamp UTC, level, service/version, requestId/traceId, route template, status, duration, userId hash, generationId/jobId. Запрещены password/token, email body, raw private filename, full object URL/query signature и media bytes.

Минимальные метрики:

- HTTP RPS/error/latency p50/p95/p99 по route/status;
- active SignalR connections, reconnects, rejected stale revisions;
- Hangfire queue age, retries, failed/stale jobs, transcode duration/CPU outcome;
- multipart initiated/completed/aborted, bytes/quota rejects;
- CDN URL issues, playback 401/403/404/416, renew success;
- outbox pending age/failures, orphan count;
- PostgreSQL pool/locks/migration version, Redis latency/errors, SMTP failures.

OpenTelemetry trace связывает HTTP initiate/complete → Hangfire job → S3 operation → SignalR event без записи signed query. Alerts:

- oldest transcode/outbox > 15 минут;
- failed jobs > 5% за 15 минут;
- CDN 403/416 > 2% за 10 минут;
- PostgreSQL/Redis errors > 1% за 5 минут;
- quota/storage growth anomaly и backup failure.

---

## 7. Backup и restore

Цели MVP: PostgreSQL RPO ≤ 15 минут, RTO ≤ 4 часа.

- PostgreSQL: daily full backup + continuous WAL/PITR, encryption, retention 30 дней.
- Object Storage: versioning для production media; noncurrent retention 30 дней. Доступ к backup отдельной service account.
- Redis не является source of truth и не восстанавливается из backup.
- Hangfire storage входит в PostgreSQL backup, но после restore jobs обязаны быть generation-idempotent.
- Ежемесячный restore drill в изолированное окружение: восстановить DB, проверить counts/FK, выбор active generations, sample S3 HEAD/Range и reconciliation dry-run.
- После point-in-time restore reconciler не удаляет «будущие» objects раньше safety window и operator approval.

Backup считается успешным только после проверки возможности чтения и зафиксированного отчёта, не по факту запуска job.

---

## 8. Deployment и migrations

- Версии runtime, NuGet/Dart dependencies, PostgreSQL image и FFmpeg pin.
- EF migration запускается отдельным one-shot step до включения новой версии, не каждым API replica. Локальный `dotnet run` / `start` сейчас вызывает `MigrateAsync` при старте процесса — [05-local-setup.md](05-local-setup.md).
- Изменения schema — expand/contract: сначала совместимые nullable/new fields/index concurrently где возможно, затем код, backfill, и только позже удаление старого.
- Перед остановкой instance: снять readiness, прекратить новые jobs, дать active HTTP/SignalR завершиться, выполнить Hangfire drain до 30 секунд; незавершённые jobs восстанавливаются lease/retry.
- Rollback приложения не откатывает destructive migration. Для несовместимой schema deployment блокируется.
- Smoke после deploy: register/login sandbox user, catalog read, one CDN Range, SignalR connect, Hangfire enqueue/execute и health.

---

## 9. Retention, privacy и права

- Expired verification/reset tokens: удаление через 7 дней; revoked/expired refresh: через 30 дней.
- Unverified email-only account: удалить через 24 часа, если verification не завершён.
- Failed/cancelled uploads и temp objects: outbox после 24 часов; operational logs — 30 дней.
- Delete account: немедленно revoke tokens, создать outbox для всех private keys и удалить DB rows транзакционно. S3 purge SLO ≤ 24 часа; completion виден оператору без раскрытия content.
- Не хранить raw local URI, signed URLs и private filenames в telemetry/audit.

До production владелец продукта документально подтверждает права на каталожные исходники, обложки и их CDN-раздачу. Пользовательские условия должны разрешать хранение/транскод личной копии и запрещать публичное распространение. Это release gate, а не новая фича MVP.

---

## 10. Обязательные проверки

- Integration: конкурентные reset/refresh; stale generation; outbox crash between commit/job; tenant 404; quota race.
- Storage spike: private origin, unsigned denial, CDN secure token, Range/seek/expiry/renew.
- Mobile: Android/iOS background, call/audio focus, unplug, Bluetooth, reboot/process kill, URI/bookmark loss.
- Disaster recovery: restore drill и reconciliation dry-run.
- Security: global private rendition id не принимается; owner входит в query/cache key; malicious media не выходит за process limits.
