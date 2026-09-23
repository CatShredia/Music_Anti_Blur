#!/usr/bin/env bash
# Поднимает Postgres/Redis/MailHog/MinIO и API.
# Локально — опционально 0–2 Flutter-клиента; публикация — только сервер.
#
# Usage:
#   bash devops/start.sh
#   bash devops/start.sh local|publish|dual|api
#   LANG=en DEVICE1=chrome DEVICE2=none bash devops/start.sh local
#   START_LANG=en START_DEVICE1=windows START_DEVICE2=emulator bash devops/start.sh
set -euo pipefail

DEVOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DEVOPS_ROOT/.." && pwd)"
RUN_DIR="$DEVOPS_ROOT/.run"
API_PROJECT="$ROOT/src/api/MusicAntiBlur.Api/MusicAntiBlur.Api.csproj"
MOBILE_DIR="$ROOT/src/mobile"
HEALTH_URL="http://127.0.0.1:5080/health"
API_PID=""
UI_LANG="ru"

MODE_ARG="${1:-}"
LANG_ARG="${START_LANG:-${LANG_UI:-}}"
DEVICE1_ARG="${START_DEVICE1:-${DEVICE1:-}}"
DEVICE2_ARG="${START_DEVICE2:-${DEVICE2:-}}"

cd "$ROOT"

# --- i18n ---
t() {
  local key="$1"
  shift || true
  local fmt=""
  case "$UI_LANG" in
    en)
      case "$key" in
        title) fmt="Music Anti Blur" ;;
        choose_lang) fmt="Language / Язык" ;;
        lang_prompt) fmt="Choice [RU]" ;;
        env_missing) fmt=".env is missing or empty." ;;
        env_offer) fmt="Copy a template to .env?" ;;
        env_local) fmt=".env.local.example (local defaults, Postgres 5433) — continue" ;;
        env_example) fmt=".env.example — copy and exit (fill in manually)" ;;
        env_abort) fmt="Aborted: without .env the script will not start infrastructure." ;;
        env_prompt) fmt="Choice" ;;
        env_created_local) fmt="Created .env from .env.local.example." ;;
        env_created_example) fmt="Created .env from .env.example. Fill in secrets/ports and run start again." ;;
        env_no_templates) fmt="Neither .env.local.example nor .env.example found. Create .env manually." ;;
        env_no_tty) fmt="No .env and no interactive input. Copy a template to .env manually." ;;
        choose_kind) fmt="Deployment type" ;;
        kind_local) fmt="Local development" ;;
        kind_publish) fmt="Publish (server only)" ;;
        kind_prompt) fmt="Choice [1]" ;;
        mode_local) fmt="Mode: local development" ;;
        mode_publish) fmt="Mode: publish (Compose + Production API)" ;;
        publish_warn) fmt="Production is unsafe without changing Jwt/passwords from the .env template." ;;
        device_slot) fmt="Flutter client" ;;
        device_none) fmt="Do not start Flutter" ;;
        device_chrome) fmt="Chrome" ;;
        device_windows) fmt="Windows" ;;
        device_emulator_run) fmt="Android emulator (already running: %s)" ;;
        device_emulator_start) fmt="Launch Android emulator (AVD)" ;;
        device_usb) fmt="USB: %s" ;;
        device_prompt) fmt="Choice [0]" ;;
        device_default_hint) fmt="default — none" ;;
        no_flutter) fmt="No Flutter selected — API + Docker only." ;;
        need_cmd) fmt="Command '%s' not found. Install it and retry." ;;
        yes_unknown) fmt="Unknown answer, treating as yes." ;;
        ffmpeg_missing) fmt="FFmpeg not found (need ffmpeg and ffprobe on PATH for Hangfire transcode)." ;;
        ffmpeg_ask) fmt="Install FFmpeg now?" ;;
        ffmpeg_skip) fmt="Continuing without FFmpeg. Hangfire transcode will not finish." ;;
        ffmpeg_no_tty) fmt="No interactive input — skipping install. Install FFmpeg manually." ;;
        ffmpeg_fail) fmt="Could not install FFmpeg automatically. Linux/macOS: package ffmpeg or brew install ffmpeg." ;;
        ffmpeg_ready) fmt="FFmpeg ready: %s" ;;
        ffmpeg_path) fmt="FFmpeg installed but not on PATH in this session. Open a new terminal and run start again." ;;
        brew_install) fmt="Installing FFmpeg via Homebrew..." ;;
        apt_install) fmt="Installing FFmpeg via apt..." ;;
        dnf_install) fmt="Installing FFmpeg via dnf..." ;;
        pacman_install) fmt="Installing FFmpeg via pacman..." ;;
        apk_install) fmt="Installing FFmpeg via apk..." ;;
        no_pkg_mgr) fmt="No brew/apt/dnf/pacman/apk — automatic install unavailable." ;;
        infra_start) fmt="Docker Compose: Postgres, Redis, MailHog, MinIO..." ;;
        docker_down) fmt="Docker is not running. Start Docker Desktop and retry." ;;
        docker_wait_ask) fmt="Docker is not running. Start Docker Desktop. Wait until it is up?" ;;
        docker_wait) fmt="Waiting for Docker. The script will continue when the engine is ready (Ctrl+C to quit)..." ;;
        docker_wait_tick) fmt="Docker is still not answering — waiting..." ;;
        docker_open) fmt="Opening Docker Desktop..." ;;
        docker_ready) fmt="Docker is running." ;;
        docker_no_tty) fmt="Docker is not running and there is no interactive input. Start Docker Desktop and retry." ;;
        infra_wait) fmt="Waiting for Postgres, Redis and MinIO to become healthy..." ;;
        infra_fail) fmt="Postgres/Redis/MinIO were not healthy within 90s. docker compose ps" ;;
        api_wait) fmt="Waiting for API %s ..." ;;
        api_ok) fmt="API is up." ;;
        api_fail) fmt="API did not answer %s within 90s. Log: %s" ;;
        api_local) fmt="Starting API (Development). Log: %s" ;;
        api_publish) fmt="Starting API (Production). Log: %s" ;;
        publish_build) fmt="dotnet publish -c Release -> %s" ;;
        seed) fmt="After API: importing no_commit/music (at least 4 tracks per folder)..." ;;
        seed_ask) fmt="Import tracks from no_commit/music?" ;;
        seed_skip) fmt="Skipping no_commit/music import." ;;
        seed_fail) fmt="no_commit/music import failed." ;;
        emu_already) fmt="Android emulator already running (%s)." ;;
        emu_none) fmt="No Android AVD. Create one in Android Studio, then flutter emulators." ;;
        emu_start) fmt="Launching emulator %s..." ;;
        emu_wait) fmt="Waiting for Android emulator in flutter devices..." ;;
        emu_found) fmt="Emulator: %s" ;;
        emu_timeout) fmt="Emulator did not appear in flutter devices within 120s." ;;
        flutter_pub) fmt="flutter pub get..." ;;
        flutter_pub_offline) fmt="No network (pub.dev) — skipping flutter pub get, using local cache." ;;
        flutter_pub_fail) fmt="flutter pub get failed." ;;
        flutter_start) fmt="Starting Flutter (%s) in a new terminal..." ;;
        flutter_bg) fmt="No windowed terminal found, Flutter (%s) in background. Log: %s" ;;
        chrome_missing) fmt="chrome not found in flutter devices." ;;
        done_server) fmt="Server running without Flutter. Stop: bash devops/stop.sh" ;;
        done_clients) fmt="API and Flutter started separately. Stop: bash devops/stop.sh" ;;
        phone_header) fmt="Phone (USB or Wi‑Fi on the same network):" ;;
        phone_apk_default) fmt="  Default APK targets http://10.0.2.2:5080 (emulator)." ;;
        phone_build) fmt="  Build for this laptop:" ;;
        phone_usb) fmt="  USB without LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000" ;;
        phone_usb_then) fmt="    then use http://127.0.0.1:5080 in the app" ;;
        adb_missing) fmt="adb not found. USB phone: install platform-tools or use LAN IP over Wi‑Fi." ;;
        adb_no_device) fmt="adb found, but no device in 'device' state. Enable USB debugging." ;;
        adb_reverse_fail) fmt="adb reverse failed. Use the laptop LAN IP on the phone." ;;
        adb_reverse_ok) fmt="USB: forwarded 5080 (API) and 9000 (MinIO) → phone http://127.0.0.1:5080" ;;
        unknown_mode) fmt="Unknown mode '%s'. Use local, publish, dual, api." ;;
        emulator_once) fmt="Emulator already selected in the other slot." ;;
        exit) fmt="Exit." ;;
        *) fmt="$key" ;;
      esac
      ;;
    *)
      case "$key" in
        title) fmt="Music Anti Blur" ;;
        choose_lang) fmt="Язык / Language" ;;
        lang_prompt) fmt="Выбор [RU]" ;;
        env_missing) fmt="Файл .env не найден или пуст." ;;
        env_offer) fmt="Скопировать шаблон в .env?" ;;
        env_local) fmt=".env.local.example (локальные дефолты, Postgres 5433) — продолжить" ;;
        env_example) fmt=".env.example — скопировать и выйти (заполните вручную)" ;;
        env_abort) fmt="Прервано: без .env скрипт не запускает инфраструктуру." ;;
        env_prompt) fmt="Выбор" ;;
        env_created_local) fmt="Создан .env из .env.local.example." ;;
        env_created_example) fmt="Создан .env из .env.example. Заполните секреты/порты и запустите start снова." ;;
        env_no_templates) fmt="Нет .env.local.example и .env.example. Создайте .env вручную." ;;
        env_no_tty) fmt="Нет .env и нет интерактивного ввода. Скопируйте шаблон в .env вручную." ;;
        choose_kind) fmt="Тип развертывания" ;;
        kind_local) fmt="Локальная разработка" ;;
        kind_publish) fmt="Публикация (только сервер)" ;;
        kind_prompt) fmt="Выбор [1]" ;;
        mode_local) fmt="Режим: локальная разработка" ;;
        mode_publish) fmt="Режим: публикация (Compose + Production API)" ;;
        publish_warn) fmt="Production без смены Jwt/паролей из шаблона .env небезопасен." ;;
        device_slot) fmt="Клиент Flutter" ;;
        device_none) fmt="Ничего не запускать" ;;
        device_chrome) fmt="Chrome" ;;
        device_windows) fmt="Windows" ;;
        device_emulator_run) fmt="Эмулятор Android (уже запущен: %s)" ;;
        device_emulator_start) fmt="Запустить Android-эмулятор (AVD)" ;;
        device_usb) fmt="USB: %s" ;;
        device_prompt) fmt="Выбор [0]" ;;
        device_default_hint) fmt="по умолчанию — ничего" ;;
        no_flutter) fmt="Flutter не выбран — только API + Docker." ;;
        need_cmd) fmt="Не найдена команда '%s'. Установите её и повторите." ;;
        yes_unknown) fmt="Неизвестный ответ, считаем да." ;;
        ffmpeg_missing) fmt="FFmpeg не найден (нужны ffmpeg и ffprobe в PATH для транскода Hangfire)." ;;
        ffmpeg_ask) fmt="Установить FFmpeg сейчас?" ;;
        ffmpeg_skip) fmt="Продолжаем без FFmpeg. Транскод Hangfire не завершится." ;;
        ffmpeg_no_tty) fmt="Нет интерактивного ввода — установку пропускаем. Поставьте FFmpeg вручную." ;;
        ffmpeg_fail) fmt="Не удалось установить FFmpeg автоматически. Linux/macOS: пакет ffmpeg или brew install ffmpeg." ;;
        ffmpeg_ready) fmt="FFmpeg готов: %s" ;;
        ffmpeg_path) fmt="FFmpeg установлен, но не виден в PATH этого сеанса. Откройте новый терминал и повторите start." ;;
        brew_install) fmt="Установка FFmpeg через Homebrew..." ;;
        apt_install) fmt="Установка FFmpeg через apt..." ;;
        dnf_install) fmt="Установка FFmpeg через dnf..." ;;
        pacman_install) fmt="Установка FFmpeg через pacman..." ;;
        apk_install) fmt="Установка FFmpeg через apk..." ;;
        no_pkg_mgr) fmt="Нет brew/apt/dnf/pacman/apk — автоматическая установка невозможна." ;;
        infra_start) fmt="Docker Compose: Postgres, Redis, MailHog, MinIO..." ;;
        docker_down) fmt="Docker не запущен. Откройте Docker Desktop и повторите." ;;
        docker_wait_ask) fmt="Docker не запущен. Запустите Docker Desktop. Ждать, пока он поднимется?" ;;
        docker_wait) fmt="Ждём Docker. Когда демон будет готов, скрипт продолжит (Ctrl+C — выход)..." ;;
        docker_wait_tick) fmt="Docker ещё не отвечает — ждём..." ;;
        docker_open) fmt="Открываем Docker Desktop..." ;;
        docker_ready) fmt="Docker запущен." ;;
        docker_no_tty) fmt="Docker не запущен, нет интерактивного ввода. Запустите Docker Desktop и повторите." ;;
        infra_wait) fmt="Ждём healthy у Postgres, Redis и MinIO..." ;;
        infra_fail) fmt="Postgres/Redis/MinIO не стали healthy за 90 с. docker compose ps" ;;
        api_wait) fmt="Ждём API %s ..." ;;
        api_ok) fmt="API отвечает." ;;
        api_fail) fmt="API не ответил на %s за 90 с. Лог: %s" ;;
        api_local) fmt="Запуск API (Development). Лог: %s" ;;
        api_publish) fmt="Запуск API (Production). Лог: %s" ;;
        publish_build) fmt="dotnet publish -c Release -> %s" ;;
        seed) fmt="После API: импорт no_commit/music (минимум 4 трека из каждой папки)..." ;;
        seed_ask) fmt="Импортировать треки из no_commit/music?" ;;
        seed_skip) fmt="Импорт no_commit/music пропущен." ;;
        seed_fail) fmt="Импорт no_commit/music завершился с ошибкой." ;;
        emu_already) fmt="Android-эмулятор уже запущен (%s)." ;;
        emu_none) fmt="Нет Android-эмулятора (AVD). Создайте его в Android Studio, затем flutter emulators." ;;
        emu_start) fmt="Запускаем эмулятор %s..." ;;
        emu_wait) fmt="Ждём Android-эмулятор в flutter devices..." ;;
        emu_found) fmt="Эмулятор: %s" ;;
        emu_timeout) fmt="Эмулятор не появился в flutter devices за 120 с." ;;
        flutter_pub) fmt="flutter pub get..." ;;
        flutter_pub_offline) fmt="Нет сети (pub.dev) — flutter pub get пропускаем, используем локальный кэш." ;;
        flutter_pub_fail) fmt="flutter pub get не удался." ;;
        flutter_start) fmt="Запуск Flutter (%s) в отдельном терминале..." ;;
        flutter_bg) fmt="Оконный терминал не найден, Flutter (%s) в фоне. Лог: %s" ;;
        chrome_missing) fmt="В flutter devices нет chrome." ;;
        done_server) fmt="Сервер запущен без Flutter. Остановка: bash devops/stop.sh" ;;
        done_clients) fmt="API и Flutter запущены отдельно. Остановка: bash devops/stop.sh" ;;
        phone_header) fmt="Телефон (USB или Wi‑Fi в той же сети):" ;;
        phone_apk_default) fmt="  APK по умолчанию ходит на http://10.0.2.2:5080 (это эмулятор)." ;;
        phone_build) fmt="  Сборка под этот ноутбук:" ;;
        phone_usb) fmt="  USB без LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000" ;;
        phone_usb_then) fmt="    тогда в приложении http://127.0.0.1:5080" ;;
        adb_missing) fmt="adb не найден. USB-телефон: поставьте platform-tools или ходите по Wi‑Fi на LAN IP." ;;
        adb_no_device) fmt="adb есть, телефон не в состоянии device. USB + отладка по USB." ;;
        adb_reverse_fail) fmt="adb reverse не удался. На телефоне используйте LAN IP ноутбука." ;;
        adb_reverse_ok) fmt="USB: проброшены порты 5080 (API) и 9000 (MinIO) → на телефоне http://127.0.0.1:5080" ;;
        unknown_mode) fmt="Неизвестный режим '%s'. Используйте local, publish, dual, api." ;;
        emulator_once) fmt="Эмулятор уже выбран в другом слоте." ;;
        exit) fmt="Выход." ;;
        *) fmt="$key" ;;
      esac
      ;;
  esac
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
}

info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "$(t need_cmd "$1")"
    exit 1
  }
}

confirm_yes() {
  local prompt="$1"
  local unknown_hint="${2:-$(t yes_unknown)}"
  local choice="" raw
  read -r -p "$prompt [Y]: " choice || true
  raw="$(printf '%s' "${choice:-}" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    ""|y|yes|д|да) return 0 ;;
    n|no|н|нет|0|q|quit) return 1 ;;
    *)
      warn "$unknown_hint"
      return 0
      ;;
  esac
}

env_usable() {
  [[ -f "$ROOT/.env" ]] || return 1
  grep -q '[^[:space:]]' "$ROOT/.env" 2>/dev/null
}

choose_language() {
  if [[ -n "$LANG_ARG" ]]; then
    local v
    v="$(printf '%s' "$LANG_ARG" | tr '[:upper:]' '[:lower:]')"
    case "$v" in
      en|english) UI_LANG=en; return ;;
      ru|russian|рус|русский) UI_LANG=ru; return ;;
    esac
    UI_LANG=ru
    return
  fi
  if [[ ! -t 0 ]]; then
    UI_LANG=ru
    return
  fi
  echo >&2
  printf '\033[32m%s\033[0m\n' "$(t title)" >&2
  echo "$(t choose_lang)" >&2
  echo "  [1] Русский  (Enter)" >&2
  echo "  [2] English" >&2
  local choice=""
  read -r -p "$(t lang_prompt): " choice || true
  case "$(printf '%s' "${choice:-}" | tr '[:upper:]' '[:lower:]')" in
    ""|1|ru|рус|русский) UI_LANG=ru ;;
    2|en|english) UI_LANG=en ;;
    *) UI_LANG=ru ;;
  esac
}

ensure_dotenv() {
  if env_usable; then
    return 0
  fi

  warn "$(t env_missing)"
  local has_local=0 has_plain=0
  [[ -f "$ROOT/.env.local.example" ]] && has_local=1
  [[ -f "$ROOT/.env.example" ]] && has_plain=1
  if [[ "$has_local" -eq 0 && "$has_plain" -eq 0 ]]; then
    err "$(t env_no_templates)"
    exit 1
  fi
  if [[ ! -t 0 ]]; then
    err "$(t env_no_tty)"
    exit 1
  fi

  echo "$(t env_offer)" >&2
  local keys=() labels=() i=0
  if [[ "$has_local" -eq 1 ]]; then
    keys+=("local"); labels+=("$(t env_local)")
  fi
  if [[ "$has_plain" -eq 1 ]]; then
    keys+=("example"); labels+=("$(t env_example)")
  fi
  keys+=("abort"); labels+=("$(t env_abort)")
  for i in "${!keys[@]}"; do
    echo "  [$((i + 1))] ${labels[$i]}" >&2
  done
  local choice="" idx=0
  read -r -p "$(t env_prompt): " choice || true
  if [[ "${choice:-}" =~ ^[0-9]+$ ]]; then
    idx=$((choice - 1))
  fi
  if [[ "$idx" -lt 0 || "$idx" -ge "${#keys[@]}" ]]; then
    err "$(t env_abort)"
    exit 1
  fi
  case "${keys[$idx]}" in
    abort)
      err "$(t env_abort)"
      exit 1
      ;;
    local)
      cp "$ROOT/.env.local.example" "$ROOT/.env"
      info "$(t env_created_local)"
      ;;
    example)
      cp "$ROOT/.env.example" "$ROOT/.env"
      info "$(t env_created_example)"
      exit 0
      ;;
  esac
}

resolve_kind() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|local|dev|--local) echo local ;;
    2|publish|deploy|--deploy|--publish) echo publish ;;
    3|dual|emulator|chrome|emulator-chrome|--dual) echo dual ;;
    4|api|backend|no-flutter|phone|--api) echo api ;;
    0|exit|q|quit|--exit) echo exit ;;
    *) echo "" ;;
  esac
}

choose_kind() {
  if [[ -n "$MODE_ARG" ]]; then
    local parsed
    parsed="$(resolve_kind "$MODE_ARG")"
    if [[ -z "$parsed" ]]; then
      err "$(t unknown_mode "$MODE_ARG")"
      exit 1
    fi
    echo "$parsed"
    return
  fi
  if [[ ! -t 0 ]]; then
    echo local
    return
  fi
  echo >&2
  echo "$(t choose_kind)" >&2
  echo "  [1] $(t kind_local)  (Enter)" >&2
  echo "  [2] $(t kind_publish)" >&2
  local choice=""
  read -r -p "$(t kind_prompt): " choice || true
  if [[ -z "${choice:-}" ]]; then
    echo local
    return
  fi
  local parsed
  parsed="$(resolve_kind "$choice")"
  case "$parsed" in
    local|publish|exit) echo "$parsed" ;;
    *) echo local ;;
  esac
}

ffmpeg_ready() {
  command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1
}

install_ffmpeg() {
  if command -v brew >/dev/null 2>&1; then
    info "$(t brew_install)"
    brew install ffmpeg
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    info "$(t apt_install)"
    sudo apt-get update
    sudo apt-get install -y ffmpeg
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    info "$(t dnf_install)"
    sudo dnf install -y ffmpeg || sudo dnf install -y ffmpeg-free
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    info "$(t pacman_install)"
    sudo pacman -S --noconfirm ffmpeg
    return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    info "$(t apk_install)"
    sudo apk add ffmpeg
    return 0
  fi
  warn "$(t no_pkg_mgr)"
  return 1
}

ensure_ffmpeg() {
  if ffmpeg_ready; then
    return 0
  fi
  warn "$(t ffmpeg_missing)"
  if [[ ! -t 0 ]]; then
    warn "$(t ffmpeg_no_tty)"
    return 0
  fi
  if ! confirm_yes "$(t ffmpeg_ask)"; then
    warn "$(t ffmpeg_skip)"
    return 0
  fi
  if ! install_ffmpeg; then
    warn "$(t ffmpeg_fail)"
    return 0
  fi
  hash -r || true
  if ffmpeg_ready; then
    info "$(t ffmpeg_ready "$(command -v ffmpeg)")"
    return 0
  fi
  warn "$(t ffmpeg_path)"
}

docker_ready() {
  docker info >/dev/null 2>&1
}

open_docker_desktop() {
  case "$(uname -s)" in
    Darwin)
      if open -a Docker >/dev/null 2>&1; then
        info "$(t docker_open)"
      fi
      ;;
  esac
}

ensure_docker() {
  if docker_ready; then
    return 0
  fi
  warn "$(t docker_down)"
  if [[ ! -t 0 ]]; then
    err "$(t docker_no_tty)"
    exit 1
  fi
  if ! confirm_yes "$(t docker_wait_ask)"; then
    err "$(t docker_down)"
    exit 1
  fi
  open_docker_desktop
  info "$(t docker_wait)"
  local ticks=0
  while ! docker_ready; do
    sleep 3
    ticks=$((ticks + 1))
    if (( ticks % 5 == 0 )); then
      info "$(t docker_wait_tick)"
    fi
  done
  info "$(t docker_ready)"
}

start_infra() {
  info "$(t infra_start)"
  ensure_docker
  docker compose --env-file .env up -d
  info "$(t infra_wait)"
  local i pg rd mn
  for i in $(seq 1 45); do
    pg="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(docker compose ps -q postgres)")"
    rd="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(docker compose ps -q redis)")"
    mn="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(docker compose ps -q minio)")"
    if [[ "$pg" == "healthy" && "$rd" == "healthy" && "$mn" == "healthy" ]]; then
      return 0
    fi
    sleep 2
  done
  err "$(t infra_fail)"
  exit 1
}

http_ok() {
  if command -v curl >/dev/null 2>&1; then
    curl -sf "$HEALTH_URL" >/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null "$HEALTH_URL"
  else
    return 1
  fi
}

wait_api() {
  info "$(t api_wait "$HEALTH_URL")"
  local i
  for i in $(seq 1 45); do
    if http_ok; then
      info "$(t api_ok)"
      return 0
    fi
    sleep 2
  done
  err "$(t api_fail "$HEALTH_URL" "$RUN_DIR/api.log")"
  exit 1
}

start_api_local() {
  mkdir -p "$RUN_DIR"
  info "$(t api_local "$RUN_DIR/api.log")"
  ASPNETCORE_ENVIRONMENT=Development \
    nohup dotnet run --project "$API_PROJECT" >"$RUN_DIR/api.log" 2>&1 &
  API_PID=$!
  echo "$API_PID" >"$RUN_DIR/api.pid"
}

start_api_publish() {
  mkdir -p "$RUN_DIR/api"
  info "$(t publish_build "$RUN_DIR/api")"
  dotnet publish "$API_PROJECT" -c Release -o "$RUN_DIR/api" --nologo
  info "$(t api_publish "$RUN_DIR/api.log")"
  ASPNETCORE_ENVIRONMENT=Production \
    nohup dotnet "$RUN_DIR/api/MusicAntiBlur.Api.dll" >"$RUN_DIR/api.log" 2>&1 &
  API_PID=$!
  echo "$API_PID" >"$RUN_DIR/api.pid"
}

open_in_terminal() {
  local title="$1"
  local command="$2"
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="$title" -- bash -lc "$command; echo; read -r -p 'Enter...' _"
    return 0
  fi
  if command -v konsole >/dev/null 2>&1; then
    konsole --title "$title" -e bash -lc "$command; echo; read -r -p 'Enter...' _" &
    return 0
  fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal --title="$title" -e "bash -lc $(printf '%q' "$command; echo; read -r -p 'Enter...' _")" &
    return 0
  fi
  if command -v xterm >/dev/null 2>&1; then
    xterm -T "$title" -e bash -lc "$command; echo; read -r -p 'Enter...' _" &
    return 0
  fi
  if command -v kitty >/dev/null 2>&1; then
    kitty --title "$title" bash -lc "$command; echo; read -r -p 'Enter...' _" &
    return 0
  fi
  return 1
}

android_emulator_id() {
  command -v flutter >/dev/null 2>&1 || return 0
  flutter devices 2>/dev/null | grep -E '•[[:space:]]*emulator-[0-9]+[[:space:]]*•' | head -n 1 | awk -F'•' '{gsub(/^ +| +$/,"",$2); print $2}'
}

first_android_avd() {
  command -v flutter >/dev/null 2>&1 || return 0
  flutter emulators 2>/dev/null | awk -F'•' '
    {
      line = tolower($0)
      if (line ~ /android/ || line ~ /pixel/) {
        gsub(/^ +| +$/, "", $1)
        if ($1 != "" && $1 !~ /^Id$/ && $1 !~ /^---/) { print $1; exit }
      }
    }
  '
}

has_device_id() {
  local want="$1"
  command -v flutter >/dev/null 2>&1 || return 1
  flutter devices 2>/dev/null | awk -F'•' -v w="$want" '
    {
      gsub(/^ +| +$/, "", $2)
      if ($2 == w) { found=1 }
    }
    END { exit found ? 0 : 1 }
  '
}

list_usb_android_ids() {
  command -v flutter >/dev/null 2>&1 || return 0
  flutter devices 2>/dev/null | awk -F'•' '
    {
      name=$1; id=$2; plat=$3
      gsub(/^ +| +$/, "", name)
      gsub(/^ +| +$/, "", id)
      gsub(/^ +| +$/, "", plat)
      if (id == "" || id ~ /^emulator-[0-9]+$/) next
      if (id ~ /^(chrome|windows|edge|linux|macos|web-server)$/) next
      low = tolower(name " " plat)
      if (plat ~ /android/ || id ~ /^[0-9a-fA-F]{6,}$/ || low ~ /android|phone|pixel|samsung|xiaomi/) {
        print id "\t" name
      }
    }
  '
}

start_android_emulator_if_needed() {
  local running
  running="$(android_emulator_id || true)"
  if [[ -n "$running" ]]; then
    info "$(t emu_already "$running")"
    return 0
  fi
  local avd
  avd="$(first_android_avd || true)"
  if [[ -z "$avd" ]]; then
    err "$(t emu_none)"
    exit 1
  fi
  info "$(t emu_start "$avd")"
  flutter emulators --launch "$avd" || true
}

wait_android_emulator() {
  info "$(t emu_wait)" >&2
  local i id
  for i in $(seq 1 40); do
    id="$(android_emulator_id || true)"
    if [[ -n "$id" ]]; then
      info "$(t emu_found "$id")" >&2
      echo "$id"
      return 0
    fi
    sleep 3
  done
  err "$(t emu_timeout)"
  exit 1
}

write_flutter_runner() {
  local script_path="$1"
  local pid_file="$2"
  local device_id="$3"
  cat >"$script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo \$\$ >$(printf '%q' "$pid_file")
cd $(printf '%q' "$MOBILE_DIR")
flutter run -d $(printf '%q' "$device_id")
EOF
  chmod +x "$script_path"
}

has_pub_network() {
  if command -v curl >/dev/null 2>&1; then
    curl -sI --max-time 5 --connect-timeout 5 https://pub.dev >/dev/null 2>&1
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q --spider --timeout=5 https://pub.dev >/dev/null 2>&1
    return $?
  fi
  return 1
}

run_flutter_pub_get() {
  if ! has_pub_network; then
    warn "$(t flutter_pub_offline)"
    return 0
  fi
  info "$(t flutter_pub)"
  if (cd "$MOBILE_DIR" && flutter pub get); then
    return 0
  fi
  if ! has_pub_network; then
    warn "$(t flutter_pub_offline)"
    return 0
  fi
  err "$(t flutter_pub_fail)"
  exit 1
}

start_flutter_dev() {
  mkdir -p "$RUN_DIR"
  local devices=("$@")
  [[ "${#devices[@]}" -eq 0 ]] && return 0

  run_flutter_pub_get

  local id safe runner slot=0
  for id in "${devices[@]}"; do
    [[ -z "$id" || "$id" == "none" ]] && continue
    slot=$((slot + 1))
    safe="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '-')"
    runner="$RUN_DIR/flutter-run-$slot-$safe.sh"
    write_flutter_runner "$runner" "$RUN_DIR/flutter-$slot-$safe.pid" "$id"
    info "$(t flutter_start "$id")"
    if open_in_terminal "Music Anti Blur — Flutter ($id)" "$(printf '%q' "$runner")"; then
      continue
    fi
    warn "$(t flutter_bg "$id" "$RUN_DIR/flutter-$slot-$safe.log")"
    nohup bash "$runner" >"$RUN_DIR/flutter-$slot-$safe.log" 2>&1 &
  done
}

lan_ipv4() {
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | grep -vE '^(127\.|169\.254\.)' || true
}

try_adb_reverse() {
  if ! command -v adb >/dev/null 2>&1; then
    warn "$(t adb_missing)"
    return 0
  fi
  if ! adb devices 2>/dev/null | grep -qE $'\tdevice$'; then
    warn "$(t adb_no_device)"
    return 0
  fi
  if adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000; then
    info "$(t adb_reverse_ok)"
  else
    warn "$(t adb_reverse_fail)"
  fi
}

write_phone_hints() {
  echo
  echo "$(t phone_header)"
  echo "$(t phone_apk_default)"
  echo "$(t phone_build)"
  local ip any=0
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    any=1
    echo "    flutter build apk --release --dart-define=API_BASE_URL=http://${ip}:5080"
  done < <(lan_ipv4)
  if [[ "$any" -eq 0 ]]; then
    echo "    flutter build apk --release --dart-define=API_BASE_URL=http://<LAN-IP>:5080"
  fi
  echo "$(t phone_usb)"
  echo "$(t phone_usb_then)"
  try_adb_reverse
}

build_device_menu() {
  # prints lines: index|resolve|label
  local exclude_emu="${1:-0}"
  local idx=0
  echo "$idx|none|$(t device_none) ($(t device_default_hint))"
  idx=1
  if ! command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  if has_device_id chrome; then
    echo "$idx|chrome|$(t device_chrome)"
    idx=$((idx + 1))
  fi
  if has_device_id windows; then
    echo "$idx|windows|$(t device_windows)"
    idx=$((idx + 1))
  fi
  if [[ "$exclude_emu" != "1" ]]; then
    local running
    running="$(android_emulator_id || true)"
    if [[ -n "$running" ]]; then
      echo "$idx|$running|$(t device_emulator_run "$running")"
      idx=$((idx + 1))
    elif [[ -n "$(first_android_avd || true)" ]]; then
      echo "$idx|emulator:launch|$(t device_emulator_start)"
      idx=$((idx + 1))
    fi
  fi
  while IFS=$'\t' read -r uid uname; do
    [[ -z "$uid" ]] && continue
    echo "$idx|$uid|$(t device_usb "$uname ($uid)")"
    idx=$((idx + 1))
  done < <(list_usb_android_ids)
}

resolve_device_token() {
  local token="$1"
  local allow_emu="$2"
  if [[ -z "$token" ]]; then
    echo none
    return
  fi
  local tl
  tl="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
  case "$tl" in
    none|0|-) echo none; return ;;
    chrome) echo chrome; return ;;
    windows) echo windows; return ;;
    emulator)
      if [[ "$allow_emu" != "1" ]]; then
        err "$(t emulator_once)"
        exit 1
      fi
      echo emulator:launch
      return
      ;;
  esac
  if [[ "$token" =~ ^emulator-[0-9]+$ ]]; then
    if [[ "$allow_emu" != "1" ]]; then
      err "$(t emulator_once)"
      exit 1
    fi
    echo "$token"
    return
  fi
  echo "$token"
}

choose_device_slot() {
  local slot="$1"
  local exclude_emu="$2"
  local param=""
  if [[ "$slot" == "1" ]]; then
    param="$DEVICE1_ARG"
  else
    param="$DEVICE2_ARG"
  fi
  if [[ -n "$param" ]]; then
    if [[ "$exclude_emu" == "1" ]]; then
      resolve_device_token "$param" 0
    else
      resolve_device_token "$param" 1
    fi
    return
  fi
  if [[ ! -t 0 ]]; then
    echo none
    return
  fi

  echo >&2
  echo "$(t device_slot) #$slot" >&2
  local lines=()
  mapfile -t lines < <(build_device_menu "$exclude_emu")
  local line
  for line in "${lines[@]}"; do
    local i r l
    i="${line%%|*}"
    r="${line#*|}"
    l="${r#*|}"
    r="${r%%|*}"
    echo "  [$i] $l" >&2
  done
  local choice=""
  read -r -p "$(t device_prompt): " choice || true
  if [[ -z "${choice:-}" ]]; then
    echo none
    return
  fi
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    for line in "${lines[@]}"; do
      local i r
      i="${line%%|*}"
      r="${line#*|}"
      r="${r%%|*}"
      if [[ "$i" == "$choice" ]]; then
        echo "$r"
        return
      fi
    done
  fi
  if [[ "$exclude_emu" == "1" ]]; then
    resolve_device_token "$choice" 0
  else
    resolve_device_token "$choice" 1
  fi
}

is_emulator_choice() {
  local c="$1"
  [[ "$c" == "emulator:launch" || "$c" == "emulator" || "$c" =~ ^emulator-[0-9]+$ ]]
}

expand_device_choice() {
  local choice="$1"
  case "$choice" in
    none|"") echo ""; return ;;
    emulator:launch|emulator)
      start_android_emulator_if_needed
      wait_android_emulator
      return
      ;;
    chrome)
      if ! has_device_id chrome; then
        err "$(t chrome_missing)"
        exit 1
      fi
      echo chrome
      return
      ;;
    *)
      echo "$choice"
      return
      ;;
  esac
}

is_usb_device_id() {
  local id="$1"
  [[ -z "$id" || "$id" == "chrome" || "$id" == "windows" || "$id" == "none" ]] && return 1
  [[ "$id" =~ ^emulator ]] && return 1
  list_usb_android_ids | awk -F'\t' -v w="$id" '$1==w {found=1} END{exit found?0:1}'
}

# --- main ---

choose_language
need_cmd docker
need_cmd dotnet
ensure_dotenv

kind_raw="$(choose_kind)"
if [[ "$kind_raw" == "exit" ]]; then
  info "$(t exit)"
  exit 0
fi

kind="$kind_raw"
preset1=""
preset2=""
if [[ "$kind_raw" == "dual" ]]; then
  kind=local
  preset1=chrome
  preset2=emulator:launch
elif [[ "$kind_raw" == "api" ]]; then
  kind=local
  preset1=none
  preset2=none
elif [[ "$kind_raw" == "deploy" ]]; then
  kind=publish
fi

d1=none
d2=none
if [[ "$kind" == "local" ]]; then
  if [[ -n "$MODE_ARG" && -z "$DEVICE1_ARG" && -z "$DEVICE2_ARG" && -n "$preset1" ]]; then
    d1="$preset1"
    d2="$preset2"
  else
    d1="$(choose_device_slot 1 0)"
    exclude=0
    if is_emulator_choice "$d1"; then
      exclude=1
    fi
    d2="$(choose_device_slot 2 "$exclude")"
  fi
fi

need_flutter=0
for d in "$d1" "$d2"; do
  if [[ -n "$d" && "$d" != "none" ]]; then
    need_flutter=1
  fi
done
if [[ "$need_flutter" -eq 1 ]]; then
  need_cmd flutter
fi

ensure_ffmpeg

echo
if [[ "$kind" == "publish" ]]; then
  info "$(t mode_publish)"
  warn "$(t publish_warn)"
else
  info "$(t mode_local)"
  if [[ "$need_flutter" -eq 0 ]]; then
    info "$(t no_flutter)"
  fi
fi

start_infra

if [[ "$kind" == "publish" ]]; then
  start_api_publish
else
  start_api_local
fi

wait_api

if [[ "$kind" == "local" ]]; then
  do_seed=1
  if [[ -t 0 ]]; then
    if confirm_yes "$(t seed_ask)"; then
      do_seed=1
    else
      do_seed=0
    fi
  fi
  if [[ "$do_seed" -eq 1 ]]; then
    info "$(t seed)"
    if bash "$DEVOPS_ROOT/seed-local-music.sh"; then
      :
    else
      warn "$(t seed_fail)"
    fi
  else
    info "$(t seed_skip)"
  fi
fi

resolved=()
want_usb=0
if [[ "$kind" == "local" && "$need_flutter" -eq 1 ]]; then
  for choice in "$d1" "$d2"; do
    id="$(expand_device_choice "$choice")"
    if [[ -n "$id" ]]; then
      resolved+=("$id")
      if is_usb_device_id "$id"; then
        want_usb=1
      fi
    fi
  done
  start_flutter_dev "${resolved[@]}"
fi

echo
echo "HTTP API     http://127.0.0.1:5080"
echo "Swagger      http://127.0.0.1:5080/swagger  (Development)"
echo "MailHog      http://127.0.0.1:8025"
echo "MinIO S3     http://127.0.0.1:9000"
echo "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)"
echo "Hangfire     http://127.0.0.1:5080/hangfire"

if [[ "$want_usb" -eq 1 || ( "$need_flutter" -eq 0 && "$kind" == "local" ) ]]; then
  write_phone_hints
fi

if [[ "$need_flutter" -eq 1 ]]; then
  info "$(t done_clients)"
else
  info "$(t done_server)"
fi
