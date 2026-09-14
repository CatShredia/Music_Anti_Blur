#!/usr/bin/env bash
# Поднимает Postgres/Redis/MailHog/MinIO, API и Flutter (hot reload).
# В режиме local после healthy API импортирует no_commit/music (если папка есть).
# Аргумент (необязательно): local | deploy | 1 | 2
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

ensure_dotenv() {
  if [[ ! -f "$ROOT/.env" ]]; then
    if [[ ! -f "$ROOT/.env.example" ]]; then
      err "Нет .env и .env.example в корне репозитория."
      exit 1
    fi
    cp "$ROOT/.env.example" "$ROOT/.env"
    warn "Создан .env из .env.example. Проверьте секреты перед продом."
  fi
}

choose_mode() {
  local raw="${1:-}"
  if [[ -n "$raw" ]]; then
    raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
      1|local|dev|--local) echo local; return ;;
      2|deploy|--deploy) echo deploy; return ;;
      *)
        err "Неизвестный режим '$1'. Используйте local или deploy."
        exit 1
        ;;
    esac
  fi

  echo >&2
  printf '\033[32mMusic Anti Blur\033[0m\n' >&2
  echo "Режим:" >&2
  echo "  [1] Локальная разработка   (по умолчанию, Enter)" >&2
  echo "  [2] Развертывание" >&2
  local choice=""
  read -r -p "Выбор [1]: " choice || true
  case "${choice:-1}" in
    ""|1) echo local ;;
    2) echo deploy ;;
    *)
      warn "Неизвестный пункт, берём локальную разработку."
      echo local
      ;;
  esac
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

start_flutter_dev() {
  mkdir -p "$RUN_DIR"
  local device_arg=""
  if [[ -n "${FLUTTER_DEVICE:-}" ]]; then
    device_arg=" -d ${FLUTTER_DEVICE}"
  fi

  cat >"$RUN_DIR/flutter-run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo \$\$ >$(printf '%q' "$RUN_DIR/flutter.pid")
cd $(printf '%q' "$MOBILE_DIR")
flutter pub get
flutter run${device_arg}
EOF
  chmod +x "$RUN_DIR/flutter-run.sh"
  local runner
  printf -v runner '%q' "$RUN_DIR/flutter-run.sh"

  info "Запуск Flutter в отдельном терминале..."
  if open_in_terminal "Music Anti Blur — Flutter" "$runner"; then
    return 0
  fi

  warn "Оконный терминал не найден, Flutter в фоне. Лог: $RUN_DIR/flutter.log"
  nohup bash "$RUN_DIR/flutter-run.sh" >"$RUN_DIR/flutter.log" 2>&1 &
}

need_cmd docker
need_cmd dotnet
need_cmd flutter
ensure_dotenv

selected="$(choose_mode "${1:-}")"
echo
if [[ "$selected" == "local" ]]; then
  info "Режим: локальная разработка"
else
  info "Режим: развертывание (Release API + Flutter hot reload)"
  warn "Production без смены Jwt/паролей из .env.example небезопасен."
fi

start_infra

if [[ "$selected" == "local" ]]; then
  start_api_local
else
  start_api_deploy
fi

wait_api

if [[ "$selected" == "local" ]]; then
  info "После API: импорт no_commit/music (минимум 4 трека из каждой папки)..."
  if bash "$DEVOPS_ROOT/seed-local-music.sh"; then
    :
  else
    warn "Импорт no_commit/music завершился с ошибкой. Flutter всё равно запускаем."
  fi
fi

start_flutter_dev

echo
echo "HTTP API     http://127.0.0.1:5080"
echo "Swagger      http://127.0.0.1:5080/swagger  (только Development)"
echo "MailHog      http://127.0.0.1:8025"
echo "MinIO S3     http://127.0.0.1:9000"
echo "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)"
echo "Hangfire     http://127.0.0.1:5080/hangfire"
info "API и Flutter запущены отдельно. Остановка: bash devops/stop.sh"
