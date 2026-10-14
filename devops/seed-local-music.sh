#!/usr/bin/env bash
# После старта API создаёт каталог из no_commit/music и заливает исходники.
# Каждая папка с аудио — минимум 4 трека (или все, если файлов меньше).
set -euo pipefail

DEVOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DEVOPS_ROOT/.." && pwd)"
API_BASE="${API_BASE:-http://127.0.0.1:5080}"
MUSIC_ROOT="${MUSIC_ROOT:-$ROOT/no_commit/music}"
LOGIN="${LOGIN:-admin}"
PASSWORD="${PASSWORD:-AdminPassword123}"
MIN_TRACKS="${MIN_TRACKS:-4}"

info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$DEVOPS_ROOT/seed-local-music.ps1" \
    -ApiBase "$API_BASE" -MusicRoot "$MUSIC_ROOT" -Login "$LOGIN" -Password "$PASSWORD" \
    -MinTracksPerFolder "$MIN_TRACKS"
fi

if [[ ! -d "$MUSIC_ROOT" ]]; then
  warn "Нет $MUSIC_ROOT — локальные треки не импортируются."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  err "Нужен pwsh или python3, чтобы импортировать no_commit/music."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  err "Нужен curl."
  exit 1
fi

export API_BASE MUSIC_ROOT LOGIN PASSWORD MIN_TRACKS DEVOPS_ROOT
info "Импорт из $MUSIC_ROOT"
python3 - <<'PY'
import hashlib, json, os, re, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

API = os.environ["API_BASE"].rstrip("/")
MUSIC = os.environ["MUSIC_ROOT"]
LOGIN = os.environ["LOGIN"]
PASSWORD = os.environ["PASSWORD"]
MIN_TRACKS = int(os.environ["MIN_TRACKS"])
AUDIO_EXT = {".mp3", ".m4a", ".mp4", ".flac", ".wav", ".ogg", ".aac"}
NAME_MAX = 200
TOKEN = ""

def info(msg):
    print(msg, flush=True)

def warn(msg):
    print(msg, file=sys.stderr, flush=True)

def limit_name(value):
    t = (value or "Untitled").strip()
    return t[:NAME_MAX] if t else "Untitled"

def audio_files(path):
    if not os.path.isdir(path):
        return []
    files = []
    for name in sorted(os.listdir(path)):
        full = os.path.join(path, name)
        if os.path.isfile(full) and os.path.splitext(name)[1].lower() in AUDIO_EXT:
            files.append(full)
    return files

def select_tracks(path):
    files = audio_files(path)
    if not files:
        return []
    if len(files) < MIN_TRACKS:
        warn(f"В «{os.path.basename(path)}» только {len(files)} аудио (ожидали минимум {MIN_TRACKS}). Берём все.")
    return files[:MIN_TRACKS]

def split_artist_folder(name):
    if " - " in name:
        artist, album = name.split(" - ", 1)
        album = re.sub(r"\s*\((?:iTunes|CD|WEB|FLAC|AAC|MP3|Vinyl)[^)]*\)\s*$", "", album).strip()
        return artist.strip(), album
    return name, name

def album_meta(folder_name, fallback):
    m = re.match(r"^(\d{4})\s*-\s*(.+)$", folder_name)
    if m:
        return m.group(2).strip(), int(m.group(1))
    return fallback, None

def track_meta(path, index):
    base = os.path.splitext(os.path.basename(path))[0]
    number = index
    m = re.match(r"^(\d{1,2})-(\d{2})\b", base)
    if m:
        number = int(m.group(2))
        base = base[m.end():]
    else:
        m = re.match(r"^(\d{1,3})[.\)]\s*", base)
        if m:
            number = int(m.group(1))
            base = base[m.end():]
        else:
            m = re.match(r"^(\d{1,3})\s+-\s+", base)
            if m:
                number = int(m.group(1))
                base = base[m.end():]
    base = base.strip(" .-_") or os.path.splitext(os.path.basename(path))[0]
    if number < 1:
        number = index
    return limit_name(base), number

def login():
    global TOKEN
    body = json.dumps({"identifierType": "login", "identifier": LOGIN, "password": PASSWORD}).encode()
    req = urllib.request.Request(API + "/api/v1/auth/login", data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as resp:
        TOKEN = json.load(resp)["accessToken"]

def api(method, url, body=None, idem=None):
    global TOKEN
    for attempt in range(2):
        headers = {"Authorization": "Bearer " + TOKEN}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        if idem:
            headers["Idempotency-Key"] = idem
        req = urllib.request.Request(API + url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                return json.loads(raw.decode()) if raw else None
        except urllib.error.HTTPError as e:
            if e.code == 401 and attempt == 0:
                login()
                continue
            err = e.read().decode("utf-8", "replace")
            raise RuntimeError(f"{method} {url} -> {e.code}: {err}") from e

def all_artists():
    items, cursor = [], None
    while True:
        url = "/api/v1/artists?limit=50"
        if cursor:
            url += "&cursor=" + urllib.parse.quote(cursor)
        page = api("GET", url)
        items.extend(page.get("items") or [])
        cursor = page.get("nextCursor")
        if not cursor:
            return items

def get_or_create_artist(name):
    name = limit_name(name)
    for a in all_artists():
        if a.get("name") == name:
            return a["id"]
    created = api("POST", "/api/v1/admin/artists", {"name": name})
    info("артист " + name)
    return created["id"]

def get_or_create_album(artist_id, title, year):
    title = limit_name(title)
    artist = api("GET", f"/api/v1/artists/{artist_id}")
    for album in artist.get("albums") or []:
        if album.get("title") == title:
            return album["id"]
    body = {"artistId": artist_id, "title": title}
    if year is not None:
        body["year"] = year
    created = api("POST", "/api/v1/admin/albums", body)
    info("альбом " + title)
    return created["id"]

COVER_NAMES = ("cover.jpg", "cover.jpeg", "cover.png", "folder.jpg", "folder.png")

def find_cover_file(folder):
    if not os.path.isdir(folder):
        return None
    wanted = {name.lower() for name in COVER_NAMES}
    for name in sorted(os.listdir(folder)):
        full = os.path.join(folder, name)
        if os.path.isfile(full) and name.lower() in wanted:
            return full
    return None

def extract_embedded_cover(audio_path):
    if not shutil.which("ffmpeg"):
        return None
    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"mab-cover-{os.urandom(8).hex()}.jpg")
    try:
        proc = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", audio_path,
             "-an", "-frames:v", "1", "-f", "image2", tmp],
            check=False,
        )
        if proc.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
            return tmp
    except OSError:
        pass
    if os.path.isfile(tmp):
        os.remove(tmp)
    return None

def upload_cover(album_id, path):
    url = f"{API}/api/v1/admin/albums/{album_id}/cover"
    def run():
        return subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
             "-X", "PUT", "-H", f"Authorization: Bearer {TOKEN}",
             "-F", f"file=@{path}", url],
            check=False, capture_output=True, text=True,
        )
    res = run()
    code = (res.stdout or "").strip()
    if code == "401":
        login()
        res = run()
        code = (res.stdout or "").strip()
    if code != "200":
        warn(f"обложка {album_id} -> HTTP {code}")
    else:
        info("обложка альбома " + album_id)

def ensure_album_cover(album_id, folder, files):
    album = api("GET", f"/api/v1/albums/{album_id}")
    if album.get("coverObjectKey"):
        return
    path = find_cover_file(folder)
    tmp = None
    if not path and files:
        tmp = extract_embedded_cover(files[0])
        path = tmp
    if not path:
        return
    try:
        upload_cover(album_id, path)
    finally:
        if tmp and os.path.isfile(tmp):
            os.remove(tmp)

def get_or_create_track(album_id, artist_id, title, number):
    title = limit_name(title)
    album = api("GET", f"/api/v1/albums/{album_id}")
    for track in album.get("tracks") or []:
        if track.get("title") == title:
            return track["id"]
    created = api("POST", "/api/v1/admin/tracks", {
        "albumId": album_id, "artistId": artist_id, "title": title, "trackNumber": number
    })
    info("трек " + title)
    return created["id"]

def track_ready(track_id):
    track = api("GET", f"/api/v1/tracks/{track_id}")
    return bool(track.get("availableQualities"))

def upload_file(path, track_id):
    size = os.path.getsize(path)
    sha = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            sha.update(chunk)
    ext = os.path.splitext(path)[1].lower()
    content_type = {
        ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".mp4": "audio/mp4",
        ".flac": "audio/flac", ".wav": "audio/wav", ".ogg": "audio/ogg",
    }.get(ext, "application/octet-stream")
    init = api("POST", f"/api/v1/admin/tracks/{track_id}/uploads", {
        "fileName": os.path.basename(path),
        "sizeBytes": size,
        "contentType": content_type,
        "checksumSha256": sha.hexdigest(),
    }, idem=os.urandom(16).hex())
    generation = init["generationId"]
    part_size = int(init["partSizeBytes"])
    part_count = int(init["partCount"])
    etags = []
    with open(path, "rb") as f:
        for n in range(1, part_count + 1):
            chunk = f.read(part_size)
            parts = api("POST", f"/api/v1/admin/tracks/{track_id}/uploads/{generation}/parts",
                        {"partNumbers": [n]})
            url = parts["parts"][0]["url"]
            tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"mab-part-{generation}-{n}.bin")
            with open(tmp, "wb") as out:
                out.write(chunk)
            hdr = tmp + ".hdr"
            subprocess.check_call(["curl", "-sS", "-D", hdr, "-o", "/dev/null", "-X", "PUT",
                                   "--data-binary", "@" + tmp, "--url", url])
            etag = None
            with open(hdr, "r", encoding="utf-8", errors="replace") as hf:
                for line in hf:
                    if line.lower().startswith("etag:"):
                        etag = line.split(":", 1)[1].strip()
                        break
            os.remove(tmp)
            os.remove(hdr)
            if not etag:
                raise RuntimeError(f"no ETag for part {n}")
            etags.append({"partNumber": n, "etag": etag})
            info(f"uploaded part {n} etag {etag}")
    api("POST", f"/api/v1/admin/tracks/{track_id}/uploads/{generation}/complete",
        {"parts": etags}, idem=os.urandom(16).hex())
    info(f"queued generation {generation} track {track_id}")

def import_album(artist_id, title, year, files, folder):
    if not files:
        return []
    album_id = get_or_create_album(artist_id, title, year)
    ensure_album_cover(album_id, folder, audio_files(folder))
    pending = []
    for i, path in enumerate(files, start=1):
        title_t, number = track_meta(path, i)
        track_id = get_or_create_track(album_id, artist_id, title_t, number)
        if track_ready(track_id):
            info(f"skip ready {title_t}")
            continue
        info(f"upload {os.path.basename(path)} -> {title_t}")
        upload_file(path, track_id)
        pending.append(track_id)
    return pending

login()
pending = []
if not shutil.which("ffmpeg"):
    warn("ffmpeg не в PATH — Hangfire не соберёт качества. Установите FFmpeg и повторите.")
for artist_name in sorted(os.listdir(MUSIC)):
    artist_dir = os.path.join(MUSIC, artist_name)
    if not os.path.isdir(artist_dir):
        continue
    artist, album_hint = split_artist_folder(artist_name)
    artist_id = get_or_create_artist(artist)
    album_dirs = []
    for name in sorted(os.listdir(artist_dir)):
        full = os.path.join(artist_dir, name)
        if os.path.isdir(full) and audio_files(full):
            album_dirs.append(full)
    direct = select_tracks(artist_dir)
    if album_dirs:
        for album_dir in album_dirs:
            files = select_tracks(album_dir)
            title, year = album_meta(os.path.basename(album_dir), os.path.basename(album_dir))
            pending.extend(import_album(artist_id, title, year, files, album_dir))
        if direct:
            pending.extend(import_album(artist_id, album_hint, None, direct, artist_dir))
    else:
        pending.extend(import_album(artist_id, album_hint, None, direct, artist_dir))

pending = list(dict.fromkeys(pending))
if not pending:
    info("Новых загрузок нет (всё уже Ready или папки без аудио).")
    sys.exit(0)

if not shutil.which("ffmpeg"):
    warn(f"Загрузки приняты, но без ffmpeg транскод не завершится. Hangfire: {API}/hangfire")
    sys.exit(1)

info(f"Ждём транскод Hangfire для {len(pending)} трек(ов)...")
deadline = time.time() + 15 * 60
left = list(pending)
while left and time.time() < deadline:
    still = []
    for track_id in left:
        if track_ready(track_id):
            info("ready " + track_id)
        else:
            still.append(track_id)
    left = still
    if left:
        time.sleep(3)

if left:
    warn("Не дождались Ready: " + ", ".join(left) + f". Hangfire: {API}/hangfire")
    sys.exit(1)

info("Локальные треки из no_commit/music готовы.")
PY
