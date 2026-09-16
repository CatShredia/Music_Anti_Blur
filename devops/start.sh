#!/usr/bin/env bash
# Поднимает Postgres/Redis/MailHog/MinIO и API.
# Режимы local/dual/deploy ещё запускают Flutter.
# В режиме local и api после healthy API импортирует no_commit/music (если папка есть).
# Аргумент (необязательно): local | deploy | dual | api | 1 | 2 | 3 | 4 | 0
set -euo pipefail

DEVOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DEVOPS_ROOT/.." && pwd)"
RUN_DIR="$DEVOPS_ROOT/.run"
API_PROJECT="$ROOT/src/api/MusicAntiBlur.Api/MusicAntiBlur.Api.csproj"
MOBILE_DIR="$ROOT/src/mobile"
HEALTH_URL="http://127.0.0.1:5080/health"
API_PID=""

cd "$ROOT"

info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Не найдена команда '$1'. Установите её и повторите."
    exit 1
  }
}

confirm_yes() {
  local prompt="$1"
  local unknown_hint="${2:-Неизвестный ответ, считаем да.}"
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

ffmpeg_ready() {
  command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1
}

install_ffmpeg() {
  if command -v brew >/dev/null 2>&1; then
    info "Установка FFmpeg через Homebrew..."
    brew install ffmpeg
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    info "Установка FFmpeg через apt..."
    sudo apt-get update
    sudo apt-get install -y ffmpeg
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    info "Установка FFmpeg через dnf..."
    sudo dnf install -y ffmpeg || sudo dnf install -y ffmpeg-free
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    info "Установка FFmpeg через pacman..."
    sudo pacman -S --noconfirm ffmpeg
    return 0
  fi
  if command -v apk >/dev/null 2>&1; then
    info "Установка FFmpeg через apk..."
    sudo apk add ffmpeg
    return 0
  fi
  warn "Нет brew/apt/dnf/pacman/apk — автоматическая установка невозможна."
  return 1
}

ensure_ffmpeg() {
  if ffmpeg_ready; then
    return 0
  fi

  warn "FFmpeg не найден (нужны ffmpeg и ffprobe в PATH для транскода Hangfire)."
  if [[ ! -t 0 ]]; then
    warn "Нет интерактивного ввода — установку пропускаем. Поставьте FFmpeg вручную."
    return 0
  fi

  if ! confirm_yes "Установить FFmpeg сейчас?"; then
    warn "Продолжаем без FFmpeg. Транскод Hangfire не завершится."
    return 0
  fi

  if ! install_ffmpeg; then
    warn "Не удалось установить FFmpeg автоматически. Linux/macOS: пакет ffmpeg или brew install ffmpeg."
    return 0
  fi

  hash -r || true
  if ffmpeg_ready; then
    info "FFmpeg готов: $(command -v ffmpeg)"
    return 0
  fi

  warn "FFmpeg установлен, но не виден в PATH этого сеанса. Откройте новый терминал и повторите start."
}

ensure_dotenv() {
  if [[ -f "$ROOT/.env" ]]; then
    return 0
  fi

  warn "Файл .env не найден."
  if [[ ! -f "$ROOT/.env.local.example" ]]; then
    err "Нет .env.local.example. Создайте .env вручную и повторите."
    exit 1
  fi

  if [[ ! -t 0 ]]; then
    err "Нет .env и нет интерактивного ввода. Скопируйте .env.local.example в .env вручную."
    exit 1
  fi

  if ! confirm_yes "Скопировать .env.local.example в .env и продолжить?" "Неизвестный ответ, копируем .env."; then
    err "Прервано: без .env скрипт не запускает инфраструктуру."
    exit 1
  fi

  cp "$ROOT/.env.local.example" "$ROOT/.env"
  info "Создан .env из .env.local.example."
}

resolve_start_mode() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|local|dev|--local) echo local ;;
    2|deploy|--deploy) echo deploy ;;
    3|dual|emulator|chrome|emulator-chrome|--dual) echo dual ;;
    4|api|backend|no-flutter|phone|--api) echo api ;;
    0|exit|q|quit|--exit) echo exit ;;
    *) echo "" ;;
  esac
}

choose_mode() {
  local raw="${1:-}"
  if [[ -n "$raw" ]]; then
    local parsed
    parsed="$(resolve_start_mode "$raw")"
    if [[ -z "$parsed" ]]; then
      err "Неизвестный режим '$1'. Используйте local, deploy, dual, api или exit."
      exit 1
    fi
    echo "$parsed"
    return
  fi

  echo >&2
  printf '\033[32mMusic Anti Blur\033[0m\n' >&2
  echo "Режим:" >&2
  echo "  [1] Локальная разработка   (по умолчанию, Enter)" >&2
  echo "  [2] Развертывание" >&2
  echo "  [3] Эмулятор Android + Chrome" >&2
  echo "  [4] API + Docker (без Flutter, телефон)" >&2
  echo "  [0] Выход" >&2
  local choice=""
  read -r -p "Выбор [1]: " choice || true
  if [[ -z "${choice:-}" ]]; then
    echo local
    return
  fi
  local parsed
  parsed="$(resolve_start_mode "$choice")"
  if [[ -n "$parsed" ]]; then
    echo "$parsed"
    return
  fi
  warn "Неизвестный пункт, берём локальную разработку."
  echo local
}

start_infra() {
  info "Docker Compose: Postgres, Redis, MailHog, MinIO..."
  if ! docker info >/dev/null 2>&1; then
    err "Docker не запущен."
    exit 1
  fi
  docker compose --env-file .env up -d

  info "Ждём healthy у Postgres, Redis и MinIO..."
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
  err "Postgres/Redis/MinIO не стали healthy за 90 с. docker compose ps"
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
  info "Ждём API $HEALTH_URL ..."
  local i
  for i in $(seq 1 45); do
    if http_ok; then
      info "API отвечает."
      return 0
    fi
    sleep 2
  done
  err "API не ответил на $HEALTH_URL за 90 с. Лог: $RUN_DIR/api.log"
  exit 1
}

start_api_local() {
  mkdir -p "$RUN_DIR"
  info "Запуск API (Development). Лог: $RUN_DIR/api.log"
  ASPNETCORE_ENVIRONMENT=Development \
    nohup dotnet run --project "$API_PROJECT" >"$RUN_DIR/api.log" 2>&1 &
  API_PID=$!
  echo "$API_PID" >"$RUN_DIR/api.pid"
}

start_api_deploy() {
  mkdir -p "$RUN_DIR/api"
  info "dotnet publish -c Release -> $RUN_DIR/api"
  dotnet publish "$API_PROJECT" -c Release -o "$RUN_DIR/api" --nologo
  info "Запуск API (Production). Лог: $RUN_DIR/api.log"
  ASPNETCORE_ENVIRONMENT=Production \
    nohup dotnet "$RUN_DIR/api/MusicAntiBlur.Api.dll" >"$RUN_DIR/api.log" 2>&1 &
  API_PID=$!
  echo "$API_PID" >"$RUN_DIR/api.pid"
}

open_in_terminal() {
  local title="$1"
  local command="$2"

  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="$title" -- bash -lc "$command; echo; read -r -p 'Enter чтобы закрыть...' _"
    return 0
  fi
  if command -v konsole >/dev/null 2>&1; then
    konsole --title "$title" -e bash -lc "$command; echo; read -r -p 'Enter чтобы закрыть...' _" &
    return 0
  fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal --title="$title" -e "bash -lc $(printf '%q' "$command; echo; read -r -p 'Enter чтобы закрыть...' _")" &
    return 0
  fi
  if command -v xterm >/dev/null 2>&1; then
    xterm -T "$title" -e bash -lc "$command; echo; read -r -p 'Enter чтобы закрыть...' _" &
    return 0
  fi
  if command -v kitty >/dev/null 2>&1; then
    kitty --title "$title" bash -lc "$command; echo; read -r -p 'Enter чтобы закрыть...' _" &
    return 0
  fi
  return 1
}

has_chrome_device() {
  flutter devices 2>/dev/null | grep -qE '•[[:space:]]*chrome[[:space:]]*•'
}

android_emulator_id() {
  flutter devices 2>/dev/null | grep -E '•[[:space:]]*emulator-[0-9]+[[:space:]]*•' | head -n 1 | awk -F'•' '{gsub(/^ +| +$/,"",$2); print $2}'
}

assert_chrome_device() {
  if has_chrome_device; then
    return 0
  fi
  err "В flutter devices нет chrome. Нужен Google Chrome и включённый web: flutter config --enable-web."
  exit 1
}

first_android_avd() {
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

start_android_emulator_if_needed() {
  local running
  running="$(android_emulator_id || true)"
  if [[ -n "$running" ]]; then
    info "Android-эмулятор уже запущен ($running)."
    return 0
  fi

  local avd
  avd="$(first_android_avd || true)"
  if [[ -z "$avd" ]]; then
    err "Нет Android-эмулятора (AVD). Создайте его в Android Studio, затем flutter emulators."
    exit 1
  fi
  info "Запускаем эмулятор $avd..."
  flutter emulators --launch "$avd"
}

wait_android_emulator() {
  info "Ждём Android-эмулятор в flutter devices..." >&2
  local i id
  for i in $(seq 1 40); do
    id="$(android_emulator_id || true)"
    if [[ -n "$id" ]]; then
      info "Эмулятор: $id" >&2
      echo "$id"
      return 0
    fi
    sleep 3
  done
  err "Эмулятор не появился в flutter devices за 120 с."
  exit 1
}

write_flutter_runner() {
  local script_path="$1"
  local pid_file="$2"
  local device_arg="$3"
  local pub_get="$4"
  cat >"$script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo \$\$ >$(printf '%q' "$pid_file")
cd $(printf '%q' "$MOBILE_DIR")
EOF
  if [[ "$pub_get" == "1" ]]; then
    cat >>"$script_path" <<'EOF'
flutter pub get
EOF
  fi
  cat >>"$script_path" <<EOF
flutter run${device_arg}
EOF
  chmod +x "$script_path"
}

start_flutter_dev() {
  mkdir -p "$RUN_DIR"
  local devices=("$@")
  if [[ "${#devices[@]}" -eq 0 ]]; then
    local device_arg=""
    if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
      device_arg=" -d ${FLUTTER_DEVICE}"
    fi
    write_flutter_runner "$RUN_DIR/flutter-run.sh" "$RUN_DIR/flutter.pid" "$device_arg" "1"
    info "Запуск Flutter в отдельном терминале..."
    if open_in_terminal "Music Anti Blur — Flutter" "$(printf '%q' "$RUN_DIR/flutter-run.sh")"; then
      return 0
    fi
    warn "Оконный терминал не найден, Flutter в фоне. Лог: $RUN_DIR/flutter.log"
    nohup bash "$RUN_DIR/flutter-run.sh" >"$RUN_DIR/flutter.log" 2>&1 &
    return 0
  fi

  info "flutter pub get..."
  (cd "$MOBILE_DIR" && flutter pub get)

  local id safe runner
  for id in "${devices[@]}"; do
    safe="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '-')"
    runner="$RUN_DIR/flutter-run-$safe.sh"
    write_flutter_runner "$runner" "$RUN_DIR/flutter-$safe.pid" " -d $id" "0"
    info "Запуск Flutter ($id) в отдельном терминале..."
    if open_in_terminal "Music Anti Blur — Flutter ($id)" "$(printf '%q' "$runner")"; then
      continue
    fi
    warn "Оконный терминал не найден, Flutter ($id) в фоне. Лог: $RUN_DIR/flutter-$safe.log"
    nohup bash "$runner" >"$RUN_DIR/flutter-$safe.log" 2>&1 &
  done
}

lan_ipv4() {
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | grep -vE '^(127\.|169\.254\.)' || true
}

try_adb_reverse() {
  if ! command -v adb >/dev/null 2>&1; then
    warn "adb не найден. USB-телефон: поставьте platform-tools или ходите по Wi‑Fi на LAN IP."
    return 0
  fi
  if ! adb devices 2>/dev/null | grep -qE $'\tdevice$'; then
    warn "adb есть, телефон не в состоянии device. USB + отладка по USB."
    return 0
  fi
  if adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000; then
    info "USB: проброшены порты 5080 (API) и 9000 (MinIO) → на телефоне http://127.0.0.1:5080"
  else
    warn "adb reverse не удался. На телефоне используйте LAN IP ноутбука."
  fi
}

write_phone_hints() {
  echo
  echo "Телефон (USB или Wi‑Fi в той же сети):"
  echo "  APK по умолчанию ходит на http://10.0.2.2:5080 (это эмулятор)."
  echo "  Сборка под этот ноутбук:"
  local ip any=0
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    any=1
    echo "    flutter build apk --release --dart-define=API_BASE_URL=http://${ip}:5080"
  done < <(lan_ipv4)
  if [[ "$any" -eq 0 ]]; then
    echo "    flutter build apk --release --dart-define=API_BASE_URL=http://<LAN-IP>:5080"
  fi
  echo "  USB без LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000"
  echo "    тогда в приложении http://127.0.0.1:5080"
  try_adb_reverse
}

need_cmd docker
need_cmd dotnet

selected="$(choose_mode "${1:-}")"
if [[ "$selected" == "exit" ]]; then
  info "Выход."
  exit 0
fi

if [[ "$selected" != "api" ]]; then
  need_cmd flutter
fi

ensure_dotenv
ensure_ffmpeg

echo
if [[ "$selected" == "local" ]]; then
  info "Режим: локальная разработка"
elif [[ "$selected" == "dual" ]]; then
  info "Режим: эмулятор Android + Chrome"
  assert_chrome_device
  start_android_emulator_if_needed
elif [[ "$selected" == "api" ]]; then
  info "Режим: API + Docker (без Flutter)"
else
  info "Режим: развертывание (Release API + Flutter hot reload)"
  warn "Production без смены Jwt/паролей из .env.example небезопасен."
fi

start_infra

if [[ "$selected" == "deploy" ]]; then
  start_api_deploy
else
  start_api_local
fi

wait_api

if [[ "$selected" != "deploy" ]]; then
  info "После API: импорт no_commit/music (минимум 4 трека из каждой папки)..."
  if bash "$DEVOPS_ROOT/seed-local-music.sh"; then
    :
  else
    warn "Импорт no_commit/music завершился с ошибкой."
  fi
fi

if [[ "$selected" == "dual" ]]; then
  emulator_id="$(wait_android_emulator)"
  start_flutter_dev chrome "$emulator_id"
elif [[ "$selected" != "api" ]]; then
  start_flutter_dev
fi

echo
echo "HTTP API     http://127.0.0.1:5080"
echo "Swagger      http://127.0.0.1:5080/swagger  (только Development)"
echo "MailHog      http://127.0.0.1:8025"
echo "MinIO S3     http://127.0.0.1:9000"
echo "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)"
echo "Hangfire     http://127.0.0.1:5080/hangfire"
if [[ "$selected" == "api" ]]; then
  write_phone_hints
  info "API запущен без Flutter. Остановка: bash devops/stop.sh"
else
  info "API и Flutter запущены отдельно. Остановка: bash devops/stop.sh"
fi
