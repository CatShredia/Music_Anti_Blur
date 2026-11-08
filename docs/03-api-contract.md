# Music Anti Blur — API contract

Версия: 1.1
Формат: JSON over HTTPS, UTF-8
Связанные документы: [00-ai-agents.md](00-ai-agents.md), [01-product-plan.md](01-product-plan.md), [02-database-overview.md](02-database-overview.md), [04-operations.md](04-operations.md), [05-local-setup.md](05-local-setup.md)

Документ нормативен для HTTP/SignalR MVP. OpenAPI/Swagger в Development (`/swagger`) — подсказка, не замена этому файлу. Аудиобайты через API не проходят.

---

## 1. Общие соглашения

- Base path `/api/v1`; hub `/hubs/playback`.
- UUID — lowercase canonical string, время — ISO 8601 UTC, позиции/длительности — целые миллисекунды.
- Enum-коды lowercase. Auth: `Authorization: Bearer`; access TTL 15 минут.
- Retryable authenticated mutation принимает `Idempotency-Key` UUID, scoped по `(user, route)` на 24 часа. Login/refresh и другие ответы с token secrets используют собственную атомарность и не кэшируются idempotency layer. Тот же key с иным body → `409 idempotency_conflict`.
- `X-Request-Id` возвращается сервером. Клиент шлёт `X-Device-Id` (UUID) на auth и playback; без заголовка сервер генерирует новый id на запрос.
- Обычный JSON body ≤ 256 KiB.
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

`POST /auth/login { identifierType, identifier, password }` → `{ accessToken, accessExpiresAt, refreshToken, refreshExpiresAt, user }`. Неверные identifier/password имеют одинаковые status/body/timing class. Если у аккаунта подтверждён email, после выдачи сессии в очередь ставится письмо о входе. Ответ не ждёт SMTP. `POST /auth/refresh` письмо не шлёт. Нет email или он не подтверждён — письма нет.

`POST /auth/refresh { refreshToken }` атомарно гасит текущий token и выдаёт потомка. Повтор rotated token → `401` и revoke family. Из двух конкурентных refresh успешен один.

- `POST /auth/logout` → revoke family, `204`.
- `POST /auth/logout-all` → revoke всех refresh пользователя, `204`.
- `GET /me/devices` → активные сессии: `[{ deviceId, lastSeenAt, current }]`. `current` — устройство из заголовка `X-Device-Id`.
- `DELETE /me/devices/{deviceId}` → `204`, гасит все живые refresh этого устройства и после commit шлёт SignalR `AccessRevoked` `{ "deviceId" }` в группу пользователя. Клиент с этим `deviceId` сбрасывает локальную сессию и уходит на вход. Чужой или уже погашенный id → `404`. Если клиент не подключён к хабу, access-токен доживает до своего срока; refresh уже не действует.
- `POST /auth/forgot-password { email }` → всегда одинаковый `200`; письмо только verified email.
- `POST /auth/reset-password { code, newPassword }` → одной транзакцией consume, смена password, invalidate reset codes и revoke всех refresh. Сброс пароля **не** выключает 2FA.

### 2.3. Двухфакторная защита

Если у аккаунта включён второй фактор, `POST /auth/login` после верного пароля отвечает `200`, но вместо сессии:

```json
{ "twoFactorRequired": true, "challengeId": "uuid", "methods": ["totp", "email", "recovery"], "expiresAt": "…" }
```

`methods` — доступные способы в этом порядке: `totp` (приложение), `email` (только при подтверждённой почте), `recovery` (если остались коды). Аккаунты без 2FA получают прежний ответ с сессией. Challenge живёт 5 минут в Redis; письмо о входе ставится в очередь только после второго шага.

- `POST /auth/2fa/email { challengeId }` → `202`, код на почту (6 цифр, 5 минут). `409 method_unavailable`, если `email` нет в `methods`.
- `POST /auth/2fa/verify { challengeId, method, code }` → сессия, как у login. Неверный код → `400 invalid_token`. После 5 неверных попыток challenge удаляется: эта и следующие попытки → `401 challenge_expired`, нужен новый login. TOTP: окно ±1 шаг (30 с), один и тот же шаг дважды не принимается. Резервный код одноразовый, регистр и дефис не важны.

Управление (`/me/2fa`, нужен access token):

| Запрос | Ответ |
|---|---|
| `GET /me/2fa` | `{ totp, email, recoveryCodesLeft }` |
| `POST /me/2fa/totp/setup { currentPassword }` | `{ secret, otpauthUri }`; ещё не включает TOTP, черновик живёт 10 минут |
| `POST /me/2fa/totp/confirm { code }` | включает TOTP, `{ codes: [10 резервных кодов] }` — показываются один раз. `409 totp_setup_expired`, если черновик истёк |
| `POST /me/2fa/email/enable { currentPassword }` | `200 { codes }`, если резервных кодов ещё не было, иначе `204`. `409 email_not_verified` без подтверждённой почты |
| `POST /me/2fa/email/disable { currentPassword }` | `204` |
| `POST /me/2fa/recovery-codes/regenerate { currentPassword }` | `{ codes }`, старые коды гаснут. `409 two_factor_disabled` |
| `POST /me/2fa/disable { currentPassword, code }` | `204`, выключает всё. При включённом TOTP `code` — TOTP или резервный код |

Неверный `currentPassword` → `401 invalid_credentials`. Потеряны все факторы — 2FA выключает администратор вручную (удалить строки `user_two_factor` и `user_recovery_codes` пользователя).

### 2.4. Журнал входов

- `GET /me/login-events?cursor&limit` → `{ items: [{ id, at, ip, userAgent, result, method, deviceId, currentDevice, notMeAt }], nextCursor }`, новые первыми. `result`: `success`, `bad_password`, `2fa_required`, `2fa_failed`, `refresh_reuse`. `method`: `password`, `totp`, `email`, `recovery`, `refresh`. Неудачный пароль пишется, только если пользователь найден. Хранение 90 дней.
- `POST /me/login-events/{id}/not-me` → `204`. Гасит refresh-сессии устройства события и шлёт `AccessRevoked` (как `DELETE /me/devices/{id}`), отмечает `notMeAt`, отправляет письмо с советом сменить пароль. Повтор — тоже `204`.

Письмо о входе содержит время, IP, устройство (по `User-Agent`) и способ входа.

---

## 3. Каталог и поиск

- `GET /artists`, `GET /artists/{id}`
- `GET /albums?artistId=`, `GET /albums/{id}`
- `GET /tracks/{id}` → включает `liked: bool` для текущего пользователя
- `GET /search?q=&cursor=&limit=20`

Альбом (list/detail) и альбомы в `GET /artists/{id}` отдают `coverObjectKey` (ключ в бакете) и, если ключ есть, `coverUrl` + `coverUrlExpiresAt` (presign/CDN, TTL 1 час, host как у playback). `GET /tracks/{id}` повторяет `coverObjectKey` / `coverUrl` / `coverUrlExpiresAt` с альбома. Поиск обложку не включает.

Лайки и плейлист «Мне нравится»:

- `PUT /tracks/{trackId}/like` → `{ liked: true }`; добавляет трек в `liked_tracks` и в системный плейлист kind=`liked`
- `DELETE /tracks/{trackId}/like` → `204`
- `GET /tracks/{trackId}/like` → `{ liked: bool }`
- `GET /me/playlists` → список плейлистов пользователя (liked всегда первый)
- `GET /me/playlists/liked?cursor=&limit=` → детали «Мне нравится» + треки (новые сверху)
- `GET /me/playlists/{playlistId}` → то же для своего плейлиста (сейчас только liked)

`limit` 1..50; cursor opaque. Search `q` 2..100 символов, wildcard экранируются. Результаты track/album/artist сортируются по rank DESC, display name, id:

```json
{ "items": [{ "type": "track", "id": "uuid", "title": "...", "subtitle": "...", "rank": 0.87 }], "nextCursor": null }
```

Private metadata не включается.

Admin metadata (роль `admin`, использует seed/upload-скрипты):

- `POST /admin/artists`, `PUT /admin/artists/{id}`
- `POST /admin/albums`, `PUT /admin/albums/{id}`
- `PUT /admin/albums/{id}/cover` — multipart поле `file` (JPEG/PNG, до 5 МБ). Пишет `catalog/covers/{albumId}`, ставит `coverObjectKey`. `400` `cover_type` / `file_too_large`; `404` нет альбома.
- `POST /admin/tracks`, `PUT /admin/tracks/{id}`
- `GET /admin/albums/{id}/tracks` — треки альбома со сводкой рендиций: `status` (`none` | `processing` | `ready` | `failed` по последней не отменённой загрузке), `readyRenditions`, `totalRenditions`.
- `DELETE /admin/tracks/{id}` → `204`. Мягкое удаление (`deleted_at`): трек исчезает из каталога, поиска, лайков, плейлистов и playback-url. Хранится `Catalog__DeletedRetentionDays` (по умолчанию 180 дней), затем задача `purge-deleted-tracks` удаляет запись и ставит файлы в очередь удаления S3.
- `GET /admin/tracks/deleted` — корзина (до 200 записей): `id`, `title`, `trackNumber`, `artist`, `album`, `deletedAt`, `purgeAt`.
- `POST /admin/tracks/{id}/restore` → `200` с карточкой трека. `409 restore_conflict` (поля `trackNumber` / `isrc` = `taken`), если номер в альбоме или ISRC уже заняты; `404`, если трека нет в корзине.
- `DELETE /admin/albums/{id}`, `DELETE /admin/artists/{id}` → `204`. `409 has_dependents`, если есть треки (для альбома считаются и удалённые, ещё не стёртые) или альбомы. Файл обложки альбома уходит в очередь удаления S3.

CORS для браузерного клиента: в Development открыт loopback; в остальных режимах — только origin из `Cors__AllowedOrigins` (через запятую).

Admin catalog upload — тот же generation-aware multipart flow, что private, под `/admin/tracks/{trackId}/uploads` (см. §5).

---

## 4. Override, source и quality

- `GET /me` → `{ id, login, email, role, emailVerifiedAt }`.
- `GET /me/settings` → `{ preferredQuality }`.
- `PATCH /me/settings { preferredQuality }` → `200`; допустимы `auto|aac_128|aac_256|src`.
- `POST /me/plays { trackId }` → `204`. Счётчик прослушиваний пользователя и строка истории. Повтор того же трека в 30 с игнорируется. Лимит 60/мин.
- `GET /me/history?cursor=&limit=` → `{ items: [{ id, trackId, title, artistId, artistName, albumId, albumTitle, coverUrl, coverUrlExpiresAt, playedAt, playCount }], nextCursor }`.

Обложка артиста в `GET /artists` и `GET /artists/{id}` — signed URL альбома, который этот пользователь слушает чаще всего (сумма `play_count` по трекам альбома); если прослушиваний нет — альбом с обложкой (год DESC, название).
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

`auto` source = Local → active Ready Private → Catalog. Для явного недоступного source используется тот же безопасный fallback и `fallbackReason`: `local_unavailable`, `private_not_ready` или `catalog_unavailable`; UI обязан показать его. Quality = `aac_256` → `aac_128`; при понижении ответ содержит `qualityFallbackFrom`. `src` только явно и после stream eligibility. В **продукте** URL — Yandex CDN secure token, не S3 SigV4 GET. Локально (`Storage__UseCdn=false`) URL — S3 presigned GET на MinIO; поле **`delivery` всё равно `cdn`** (discriminated union remote vs `local`). Host в подписи берётся из `Host` запроса к API, см. [05-local-setup.md](05-local-setup.md). ACL проверяется до owner-aware cache lookup. Flutter re-resolve до expiry или один раз после 401/403 и продолжает Range с сохранённой позиции.

Если Local недоступен, active Ready Private отсутствует и Catalog не имеет подходящей Ready-рендиции, endpoint возвращает `422 source_unavailable` с безопасными полями `{ localAvailable, privateReady, catalogReady }`, без bucket keys.

---

## 5. Private multipart upload

Лимиты: source ≤ 100 MiB, duration ≤ 60 минут, private quota по умолчанию 2 GiB и 500 файлов (`Storage__PrivateQuotaBytes`, `Storage__PrivateQuotaFiles`, переопределение на пользователя). Part 5–16 MiB, кроме последней; ≤ 10 000 частей.

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

Повтор транскода (после `ffmpeg not found` / failed generation):

- `POST /admin/tracks/{trackId}/transcode { generationId? }` → `202`
- `GET /admin/tracks/{trackId}/renditions`
- `POST /tracks/{trackId}/private-uploads/{generationId}/transcode` → `202` (только владелец)

Квота считает active generation каждого трека и uploads в работе (`initiated`…`processing`). Заменённая или failed generation не учитывается, поэтому замена файла не съедает квоту дважды. Превышение → `413 quota_exceeded` с полем `quota: { usedBytes, maxBytes, usedFiles, maxFiles }`; объект в бакете не создаётся.

- `GET /me/quota` → `{ usedBytes, maxBytes, usedFiles, maxFiles }`.
- `GET /admin/users/{userId}/quota`, `PUT /admin/users/{userId}/quota { maxBytes?, maxFiles? }` (admin). `null` в поле — значение по умолчанию; пустое тело снимает переопределение.

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

Инвариант: при непустой queue `trackId` равен `trackId` элемента `currentItemId`; при `currentItemId=null` — `trackId=null`, `isPlaying=false`, `positionMs=0`. Hub events: `PlaybackSnapshot` содержит **тот же полный DTO**, `RenditionReady`, `DevicePresence`, `AccessRevoked` `{ "deviceId" }`. Broadcast только после commit; stale revision игнорируется. `AccessRevoked` получает вся группа пользователя; сессию сбрасывает только устройство с этим `deviceId`. Reconnect: exponential backoff + jitter, refreshed JWT token factory, затем authoritative snapshot и новая session.

---

## 7. Rate limits

| Группа | Лимит MVP |
|---|---|
| register | 30/час/IP |
| login | 10/5 мин/IP+identifier |
| verification resend, forgot | 3/час/email hash+IP |
| reset, verify | 10/15 мин/IP |
| refresh | 30/5 мин/family+IP |
| playback sessions create | 20/мин/user |
| playback URL | 60/мин/user |
| upload initiate | 10/час/user (`rl:private-import` / `rl:admin-import`) |
| part URL | 120/мин/user |
| admin import | 10/час/admin |
| SignalR connect | 20/5 мин/user+IP |
| playback progress (`kind=progress`) | 2/сек sustained, burst 10/user |
| playback claim + command | 20/10 сек/user |
| 2FA verify | 20/15 мин/IP; плюс 5 попыток на challenge |
| 2FA email code | 3/15 мин/challenge, 10/15 мин/IP |
| управление 2FA (`/me/2fa/*`) | 10/15 мин/user |
| bind email/login (`/me/identifiers/*`) | 5/час/user |
| «Это не я» | 10/час/user |

Все отказы — `429 rate_limited` с `Retry-After` в секундах. IP берётся из соединения. `X-Forwarded-For` учитывается только от прокси из `ForwardedHeaders__KnownProxies` (через запятую); пустой список — заголовок игнорируется, подделать IP нельзя.

В **Development** лимиты initiate (`admin-import` и `private-import`) не применяются — иначе `seed-local-music` упирается в 10/час. Остальные лимиты действуют.

При отказе Redis auth/upload/admin/private URL, создание/claim writer session и `PUT /playback-state` fail closed с `503 dependency_unavailable`. `GET /playback-state` и catalog read могут работать degraded. Breaking changes контракта требуют новой API version. CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) сейчас: `dotnet build`/`test` и `flutter analyze`/`test`; **OpenAPI diff в CI нет**.
