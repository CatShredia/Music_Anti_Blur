# Object Storage: локальный MinIO и Yandex (позже)

Норматив продукта: [docs/01-product-plan.md](../docs/01-product-plan.md) §2, [docs/04-operations.md](../docs/04-operations.md) §4 — **Yandex Object Storage + Yandex CDN**. Локальная разработка **сейчас** идёт через MinIO в Compose. Yandex CDN не блокер спринта 03 на этой машине. План: [no_commit/plans/sprint-03-storage.md](../no_commit/plans/sprint-03-storage.md) (не в git).

Секреты только в корневой `.env`, не в этот файл и не в git.

MinIO — не прод и не замена CDN в `docs/`. Когда появится облачный бакет, заполнить блок Yandex ниже и поставить `Storage__UseCdn=true`.

---

## Локально: MinIO (Compose)

`devops/start` поднимает MinIO вместе с Postgres / Redis / MailHog. Образ в compose — `pgsty/minio` (официальный `minio/minio` на Docker Hub больше не публикуется; API S3 тот же).

| Что | Значение по умолчанию |
|---|---|
| S3 API | http://127.0.0.1:9000 |
| Консоль | http://127.0.0.1:9001 |
| Логин / пароль | `minio` / `minio-local-only` |
| Бакет | `music-anti-blur` (создаёт `minio-init`, **без** anonymous download) |
| API на хосте | `Storage__Endpoint=http://127.0.0.1:9000` — не `http://minio:9000` |
| Подпись | `Storage__Region=us-east-1`, `Storage__ForcePathStyle=true` |
| Playback | `Storage__UseCdn=false` → S3 presigned GET |

Консоль: логин root user/password из `.env`. Объекты смотреть в бакете `music-anti-blur`.

AWS CLI к локальному бакету:

```bash
aws --endpoint-url=http://127.0.0.1:9000 s3 ls s3://music-anti-blur
aws --endpoint-url=http://127.0.0.1:9000 s3 cp test.mp3 s3://music-anti-blur/spike/test.mp3
curl -I "http://127.0.0.1:9000/music-anti-blur/spike/test.mp3"
```

Без подписи объект **не** должен открываться (403/403-like), бакет не публичный.

FFmpeg на машине разработчика (Hangfire в процессе API на хосте):

```bash
ffmpeg -version
ffprobe -version
```

Не нужно заранее: Flutter-плеер, private-бакет пользователя, аккаунт Yandex Cloud, кастомный домен.

Часы машины — примерно NTP: и CDN token, и S3 presign считают Unix `expires`.

---

## Два разных механизма

Их нельзя подменять друг другом. Продукт:

| Задача | Как в продукте | Как локально сейчас |
|---|---|---|
| Загрузка исходника | S3 presigned multipart PUT на Yandex | Тот же SDK, endpoint MinIO |
| Прослушивание | **CDN secure-token URL**, TTL 10 минут | S3 presigned GET на MinIO, `UseCdn=false` |

JSON `POST /playback-url` тот же: `{ url, expiresAt, ... }`. Поле `delivery` остаётся `cdn` (ветка remote HTTP URL), даже когда URL указывает на MinIO. Не выдавать SigV4 с подменённым hostname за CDN.

API не принимает и не стримит аудиобайты.

Ключи объектов (имя файла в key **не** входит):

```
tracks/{trackId}/generations/{generationId}/source
tracks/{trackId}/generations/{generationId}/aac_128.m4a
tracks/{trackId}/generations/{generationId}/aac_256.m4a
```

---

## Yandex (когда подключаем облако)

Официальные гайды:

- [Создать бакет](https://yandex.cloud/docs/storage/operations/buckets/create)
- [S3 API и статические ключи](https://yandex.cloud/docs/storage/s3/)
- [Роли Object Storage](https://yandex.cloud/docs/storage/security/)
- [AWS CLI](https://yandex.cloud/docs/storage/quickstart/quickstart-aws-cli)
- [CDN-ресурс](https://yandex.cloud/docs/cdn/operations/resources/create-resource)
- [Secure tokens](https://yandex.cloud/docs/cdn/concepts/secure-tokens)
- [Host к origin](https://yandex.cloud/docs/cdn/concepts/servers-to-origins-host)

Не блокер локального спринта 03. Нужны: каталог Cloud с биллингом, отдельный **dev**-бакет, сервисный аккаунт + статический ключ, CDN-ресурс с **secure token**.

---

## 1. Сервисный аккаунт и ключи

1. Консоль → IAM → сервисный аккаунт, например `mab-storage-dev`.
2. Роль на каталог или на бакет: **`storage.editor`** (загрузка, HEAD, multipart, удаление). Для приложения не назначать `storage.admin`.
3. «Создать новый ключ» → **статический ключ**. Сохранить `key_id` и `secret` сразу: секрет повторно не показывают.

Это `Storage__AccessKey` и `Storage__SecretKey`.

---

## 2. Бакет

Object Storage → создать бакет:

- Имя уникально глобально, например `mab-dev-<суффикс>`.
- Класс STANDARD, регион фактически `ru-central1`.
- Анонимный доступ сначала **выключен**.
- **Не** включать static website hosting (другой Host: `*.website.yandexcloud.net`).

Endpoint SDK/CLI:

- URL: `https://storage.yandexcloud.net`
- Region: **`ru-central1`** (иначе SigV4 часто ломается)
- Path-style: `https://storage.yandexcloud.net/<bucket>/<key>`

AWS CLI:

```bash
aws configure
# Access Key ID / Secret, Default region: ru-central1
aws configure set endpoint_url https://storage.yandexcloud.net
```

Залить тестовый файл:

```bash
aws --endpoint-url=https://storage.yandexcloud.net s3 cp test.mp3 s3://BUCKET/spike/test.mp3
```

Без ключей объект не должен открываться:

```bash
curl -I "https://storage.yandexcloud.net/BUCKET/spike/test.mp3"
```

Ожидание: **403**, не 200.

### CORS

Нужен, когда клиент (потом Flutter) делает PUT с устройства. Для curl/AWS CLI с той же машины не обязателен.

Разрешить `PUT`, `POST`, `HEAD`; `ExposeHeaders`: `ETag`; заголовки `*` или `Content-Type` и `x-amz-*`. Origin в dev можно широким, в проде сузить.

### Lifecycle

Abort неполного multipart через **1 сутки**. Иначе зависшие загрузки копятся в бакете.

---

## 3. CDN

1. Cloud CDN → ресурс, доступ к контенту включён.
2. Один origin, тип **Bucket**, выбрать бакет.
3. Протокол к origin: HTTP.
4. **Host:** Custom = `<bucket>.storage.yandexcloud.net`. Неверный Host → `NoSuchBucket` / `NoSuchKey`.
5. Включить **доступ по secure token**. Ключ — строка **6–32 символов** (`Cdn__SecureTokenKey`). Это **не** секрет S3.
6. Для аудио включить **slice** (Range на origin для файлов > 10 МиБ), если есть в UI.
7. Домен ресурса (свой или выданный CDN) → `Cdn__BaseUrl`.

Документы требуют закрытый origin. Quickstart Яндекса для origin типа Bucket часто просит **публичное чтение объектов**, иначе CDN не забирает файл. Это риск spike.

Целевые проверки:

| Запрос | Ожидание |
|---|---|
| Прямой URL бакета без подписи | отказ |
| CDN без token | **403** |
| CDN + token + `Range: bytes=0-1` | **206** |
| Истёкший token | **403**, VLC не играет |

Если полностью private origin CDN не читает: включить **публичное чтение объектов**, **список объектов оставить выключенным**. Не выдавать S3 SigV4 с подменённым hostname за CDN.

Формула token: [Secure tokens](https://yandex.cloud/docs/cdn/concepts/secure-tokens) (`md5` + `expires`). После сборки URL:

```bash
curl -I -H "Range: bytes=0-1" "https://CDN-HOST/spike/test.mp3?md5=...&expires=..."
```

Нужен **206**. Тот же URL после `expires` — 403. В VLC — перемотка.

---

## 4. Переменные `.env`

Имена — [`.env.example`](../.env.example). По умолчанию там **MinIO**. Для Yandex заменить endpoint/region/ключи и включить CDN:

```
Storage__Endpoint=https://storage.yandexcloud.net
Storage__Region=ru-central1
Storage__Bucket=
Storage__AccessKey=
Storage__SecretKey=
Storage__ForcePathStyle=true
Storage__UseCdn=true
Cdn__BaseUrl=https://
Cdn__SecureTokenKey=
Cdn__UrlTtlSeconds=600
Cdn__CacheTtlSeconds=480
Media__FfmpegPath=ffmpeg
Media__FfprobePath=ffprobe
```

TTL URL 10 минут, кэш Redis в коде будет короче (≤ 8 мин).

---

## Локальная приёмка хранилища (спринт 03)

- [ ] MinIO healthy, бакет `music-anti-blur` есть, без anonymous GET
- [ ] Presigned GET `Range: bytes=0-1` → **206**
- [ ] Истёкший presigned URL → **403**, VLC не играет
- [ ] Ключи не в git (`.env` локальный)

## Yandex CDN (позже, не блокер локального 03)

- [ ] mp3 лежит в dev-бакете Yandex
- [ ] CDN Range `bytes=0-1` → 206
- [ ] истёкший secure-token URL → 403
- [ ] в README зафиксирован тип подписи в проде: **CDN secure token**
