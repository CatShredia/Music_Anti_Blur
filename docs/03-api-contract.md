# Music Anti Blur — API contract

Версия: 1.0
Формат: JSON over HTTPS, UTF-8
Связанные документы: [01-product-plan.md](01-product-plan.md), [02-database-overview.md](02-database-overview.md), [04-operations.md](04-operations.md)

Документ нормативен для HTTP/SignalR MVP. OpenAPI, backend и Flutter должны ему соответствовать. Аудиобайты через API не проходят.

---

## 1. Общие соглашения

- Base path `/api/v1`; hub `/hubs/playback`.
- UUID — lowercase canonical string, время — ISO 8601 UTC, позиции/длительности — целые миллисекунды.
- Enum-коды lowercase. Auth: `Authorization: Bearer`; access TTL 15 минут.
- Retryable authenticated mutation принимает `Idempotency-Key` UUID, scoped по `(user, route)` на 24 часа. Login/refresh и другие ответы с token secrets используют собственную атомарность и не кэшируются idempotency layer. Тот же key с иным body → `409 idempotency_conflict`.
- `X-Request-Id` возвращается сервером. Обычный JSON body ≤ 256 KiB.
- Успехи: `200` чтение/команда, `201` создание, `202` асинхронно принято, `204` удаление/выход.

Ошибки — `application/problem+json` RFC 9457:

`errors` — карта поле → массив **машинных кодов** (клиент переводит их на язык UI):

```json
{
  "type": "https://music-anti-blur/errors/validation-failed",
  "title": "Validation failed",
  "status": 400,
  "code": "validation_failed",
  "requestId": "uuid",
  "errors": {
    "login": ["login_format"],
    "password": ["password_length"]
  }
}
```

Поля: `login`, `email`, `identifier`, `identifierType`, `password`, `newPassword`, `currentPassword`, `code`, `preferredQuality`, `refreshToken`.

Коды в `errors`: `required`, `login_format`, `email_format`, `password_length`, `password_common`, `code_format`, `identifier_type`, `preferred_quality`, `identifier_taken`. Для неверного/истёкшего кода подтверждения: HTTP `400` `invalid_token` и `errors.code = ["invalid_token"]`.

Слои одной и той же политики: Flutter (до запроса), API (до записи), Postgres CHECK/UNIQUE (гонка и обход клиента). Unique violation → `409 identifier_taken` с полем `login` или `email`. CHECK violation → `400 validation_failed`.

| HTTP | Коды |
|---|---|
| 400 | `validation_failed`, `invalid_token` |
| 401 | `invalid_credentials`, `invalid_token` |
| 403 | `email_not_verified`, `admin_required` |
| 404 | `not_found`, включая чужой private resource |
| 409 | `identifier_taken`, `revision_conflict`, `not_writer`, `invalid_state`, `idempotency_conflict` |
| 413 | `file_too_large`, `quota_exceeded` |
| 422 | `unsupported_audio`, `duration_exceeded`, `quality_unavailable`, `source_unavailable`, `checksum_mismatch` |
| 429 | `rate_limited`, обязательно `Retry-After` |
| 503 | `dependency_unavailable`, `queue_overloaded` |

Idempotency records хранятся в PostgreSQL (`idempotency_records`). Транзакция берёт advisory lock по `(user, route, key)`, проверяет replay, выполняет DB mutation и сохраняет response до commit. Конкурент ждёт lock и возвращает committed response; durable `in_progress` нет. Потеря Redis не повторяет mutation.

---

## 2. Auth

### 2.1. Регистрация и email

`POST /auth/register`:

```json
{ "login": "user", "email": "user@example.com", "password": "..." }
```

`login` и `email` обязательны. Тип по `@` не угадывается. Email = `lower(trim)`. Пароль 12–128 Unicode-символов, не нормализуется. Успех → `201` + access/refresh (вход по login сразу). `email_verified_at` пуст, пока не пройдёт `email/verify`; вход и reset по email до verification запрещены.

- `POST /auth/email/verify { code }` → `204`, atomic consume. `code` — 6 цифр из письма.
- `POST /auth/email/resend { email }` → всегда `202`; старые registration codes инвалидируются.

Смена и привязка login/email после регистрации (`POST /me/identifiers/*`) — вне MVP, см. [01-product-plan.md §5.2](01-product-plan.md).

### 2.2. Сессии и reset

`POST /auth/login { identifierType, identifier, password }` → `{ accessToken, accessExpiresAt, refreshToken, refreshExpiresAt, user }`. Неверные identifier/password имеют одинаковые status/body/timing class.

`POST /auth/refresh { refreshToken }` атомарно гасит текущий token и выдаёт потомка. Повтор rotated token → `401` и revoke family. Из двух конкурентных refresh успешен один.

- `POST /auth/logout` → revoke family, `204`.
- `POST /auth/logout-all` → revoke всех refresh пользователя, `204`.
- `POST /auth/forgot-password { email }` → всегда одинаковый `200`; письмо только verified email.
- `POST /auth/reset-password { code, newPassword }` → одной транзакцией consume, смена password, invalidate reset codes и revoke всех refresh.

---

## 3. Каталог и поиск

- `GET /artists`, `GET /artists/{id}`
- `GET /albums?artistId=`, `GET /albums/{id}`
- `GET /tracks/{id}`
- `GET /search?q=&cursor=&limit=20`

`limit` 1..50; cursor opaque. Search `q` 2..100 символов, wildcard экранируются. Результаты track/album/artist сортируются по rank DESC, display name, id:

```json
{ "items": [{ "type": "track", "id": "uuid", "title": "...", "subtitle": "...", "rank": 0.87 }], "nextCursor": null }
```

Private metadata не включается. Admin catalog upload использует тот же generation-aware multipart flow под `/admin/tracks/{trackId}/uploads`.

---

## 4. Override, source и quality

- `GET /me/settings` → `{ preferredQuality }`.
- `PATCH /me/settings { preferredQuality }` → `200`; допустимы `auto|aac_128|aac_256|src`.
- `GET /tracks/{trackId}/override` — owner-scoped override + private status/qualities.
- `PUT /tracks/{trackId}/override { sourcePreference, displayName?, durationMs?, sizeBytes? }`.
- `DELETE /tracks/{trackId}/private-copy` — сохраняет local binding, `202`.
- `DELETE /tracks/{trackId}/override` — удаляет всю привязку, `202`.

`POST /tracks/{trackId}/playback-url`:

```json
{ "sourcePreference": "auto", "qualityPreference": "auto", "localAvailable": false }
```

Ответ — discriminated union. Remote:

```json
{
  "resolvedSource": "private",
  "delivery": "cdn",
  "resolvedQuality": "aac_256",
  "url": "https://cdn.example/path?secure-token=...",
  "expiresAt": "2026-09-10T12:10:00Z",
  "generationId": "uuid",
  "durationMs": 180000
}
```

Local:

```json
{
  "resolvedSource": "local",
  "delivery": "local",
  "url": null,
  "expiresAt": null,
  "generationId": null,
  "fallbackReason": null
}
```

`auto` source = Local → active Ready Private → Catalog. Для явного недоступного source используется тот же безопасный fallback и `fallbackReason`: `local_unavailable`, `private_not_ready` или `catalog_unavailable`; UI обязан показать его. Quality = `aac_256` → `aac_128`; при понижении ответ содержит `qualityFallbackFrom`. `src` только явно и после stream eligibility. URL — CDN secure token, не S3 pre-signed GET. ACL проверяется до owner-aware cache lookup. Flutter re-resolve до expiry или один раз после 401/403 и продолжает Range с сохранённой позиции.

Если Local недоступен, active Ready Private отсутствует и Catalog не имеет подходящей Ready-рендиции, endpoint возвращает `422 source_unavailable` с безопасными полями `{ localAvailable, privateReady, catalogReady }`, без bucket keys.

---

## 5. Private multipart upload

Лимиты: source ≤ 100 MiB, duration ≤ 60 минут, private quota ≤ 2 GiB. Part 5–16 MiB, кроме последней; ≤ 10 000 частей.

1. `POST /tracks/{trackId}/private-uploads` + idempotency key:

```json
{ "fileName": "display-only.m4a", "sizeBytes": 73400320, "contentType": "audio/mp4", "checksumSha256": "base64-of-full-file" }
```

`201 { generationId, partSizeBytes, partCount, expiresAt }`. Initiate под user-scoped DB lock резервирует заявленный размер, поэтому конкурентные uploads не обходят квоту. Серверный key не содержит fileName. Старая active generation играет до publish новой.

2. `POST /tracks/{trackId}/private-uploads/{generationId}/parts { partNumbers }` возвращает short-lived presigned S3 PUT. Клиент сохраняет ETag; URL можно запросить повторно. Чужая generation → 404.

3. `POST /tracks/{trackId}/private-uploads/{generationId}/complete`:

```json
{ "parts": [{ "partNumber": 1, "etag": "\"...\"" }] }
```

Multipart ETag не считается SHA-256. После S3 complete сервер проверяет HEAD/size, а worker при чтении source вычисляет SHA-256 полного файла и сравнивает с ожидаемым hash из DB **до** ffprobe/transcode; ответ `202`. Несовпадение → `422 checksum_mismatch` + outbox cleanup.

- `DELETE /tracks/{trackId}/private-uploads/{generationId}` → abort/cancel, `202`.
- `GET /tracks/{trackId}/private-uploads/{generationId}` → safe status/error.

States: `initiated|uploading|uploaded|validating|processing|ready|failed|cancelled|deleting`. Notification содержит generationId; publish только через CAS своей generation.

Admin catalog использует идентичные routes/DTO под ролью `admin`:

- `POST /admin/tracks/{trackId}/uploads`;
- `POST /admin/tracks/{trackId}/uploads/{generationId}/parts`;
- `POST /admin/tracks/{trackId}/uploads/{generationId}/complete`;
- `GET|DELETE /admin/tracks/{trackId}/uploads/{generationId}`.

Ошибки state/idempotency/checksum те же; owner isolation заменяется `admin_required`, audit обязателен.

---

## 6. Playback snapshot и SignalR

Полный snapshot:

```json
{
  "revision": 41,
  "writerSessionId": "uuid-or-null",
  "deviceId": "uuid-or-null",
  "trackId": "uuid-or-null",
  "positionMs": 12000,
  "isPlaying": true,
  "qualityCode": "auto",
  "source": "catalog",
  "queue": {
    "schemaVersion": 1,
    "repeat": "off",
    "shuffle": false,
    "currentItemId": "uuid-or-null",
    "items": [{ "itemId": "uuid", "trackId": "uuid", "sourcePreference": "auto" }]
  },
  "updatedAt": "2026-09-10T12:00:00Z"
}
```

Максимум 500 items / 256 KiB. Shuffle хранит фактический порядок. Snapshot нужен для продолжения на другом устройстве, но не даёт remote-control первого.

- `GET /playback-state` → snapshot + `revision`.
- `POST /playback-sessions { deviceId }` → server-generated `writerSessionId` + current snapshot; создание не захватывает writer.
- `POST /playback-sessions/{sessionId}/claim { expectedRevision }` вызывается только после локального действия Play и атомарно назначает writer.
- `PUT /playback-state { expectedRevision, writerSessionId, kind, state }`.

Только текущий writer отправляет `command|progress`; non-writer получает `409 not_writer` и snapshot. Claim нового устройства — явный handoff: прежняя session получает committed `PlaybackSnapshot` и прекращает publish. Отдельного endpoint для pause/seek другого устройства нет. Успех увеличивает revision. Revision conflict → `409 revision_conflict` с snapshot. `progress` содержит только `{ positionMs, currentItemId }`; `command` содержит полный state без server fields.

Инвариант: при непустой queue `trackId` равен `trackId` элемента `currentItemId`; при `currentItemId=null` — `trackId=null`, `isPlaying=false`, `positionMs=0`. Hub events: `PlaybackSnapshot` содержит **тот же полный DTO**, `RenditionReady`, `DevicePresence`. Broadcast только после commit; stale revision игнорируется. Reconnect: exponential backoff + jitter, refreshed JWT token factory, затем authoritative snapshot и новая session.

---

## 7. Rate limits

| Группа | Лимит MVP |
|---|---|
| register | 30/час/IP |
| login | 10/5 мин/IP+identifier |
| verification resend, forgot | 3/час/email hash+IP |
| reset, verify | 10/15 мин/IP |
| refresh | 30/5 мин/family+IP |
| playback URL | 60/мин/user |
| upload initiate | 10/час/user |
| part URL | 120/мин/user |
| admin import | 10/час/admin |
| SignalR connect | 20/5 мин/user+IP |
| state update | 2/сек sustained, burst 10/user |

При отказе Redis auth/upload/admin/private URL, создание/claim writer session и `PUT /playback-state` fail closed с `503 dependency_unavailable`. `GET /playback-state` и catalog read могут работать degraded. OpenAPI генерируется и проверяется diff в CI; breaking changes требуют новой API version.
