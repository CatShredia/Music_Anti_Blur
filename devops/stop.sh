#!/usr/bin/env bash
# Останавливает API, Flutter и Docker Compose (Postgres, Redis, MailHog, MinIO).
# --volumes | -v  — также удалить volumes Postgres и MinIO.
set -euo pipefail

DEVOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DEVOPS_ROOT/.." && pwd)"
RUN_DIR="$DEVOPS_ROOT/.run"
API_PID_FILE="$RUN_DIR/api.pid"
REMOVE_VOLUMES=0

cd "$ROOT"

info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

for arg in "${@:-}"; do
  case "$arg" in
    --volumes|-v|-Volumes) REMOVE_VOLUMES=1 ;;
    -h|--help)
      echo "Использование: bash devops/stop.sh [--volumes]"
      exit 0
      ;;
    "")
      ;;
    *)
      err "Неизвестный аргумент '$arg'."
      exit 1
      ;;
  esac
done

stop_pid_tree() {
  local pid="$1"
  local label="${2:-процесс}"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    warn "Процесс $pid ($label) уже не запущен, пропускаем."
    return 0
  fi
  info "Останавливаем $label (pid $pid)..."
  local child
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    stop_pid_tree "$child" "$label"
  done
  kill "$pid" 2>/dev/null || true
  sleep 0.3
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
}

stop_pid_file() {
  local file="$1"
  local label="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  local pid
  pid="$(tr -d '[:space:]' <"$file" || true)"
  stop_pid_tree "$pid" "$label"
  rm -f "$file"
}

stop_pattern() {
  local pattern="$1"
  local label="$2"
  if ! command -v pgrep >/dev/null 2>&1; then
    return 0
  fi
  local extra
  extra="$(pgrep -f "$pattern" || true)"
  if [[ -z "$extra" ]]; then
    return 0
  fi
  local pid
  for pid in $extra; do
    stop_pid_tree "$pid" "$label"
  done
}

stop_api() {
  stop_pid_file "$API_PID_FILE" "API"
  stop_pattern "MusicAntiBlur.Api" "API"
}

stop_flutter() {
  local f
  for f in "$RUN_DIR"/flutter*.pid; do
    [[ -f "$f" ]] || continue
    stop_pid_file "$f" "Flutter"
  done
  stop_pattern "flutter-run" "Flutter"
  stop_pattern "flutter run" "Flutter"
}

stop_infra() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker не найден, Compose пропускаем."
    return 0
  fi
  if ! docker info >/dev/null 2>&1; then
    warn "Docker не запущен, Compose пропускаем."
    return 0
  fi

  local args=(compose)
  if [[ -f "$ROOT/.env" ]]; then
    args+=(--env-file .env)
  fi
  args+=(down)
  if [[ "$REMOVE_VOLUMES" -eq 1 ]]; then
    args+=(--volumes)
    info "Docker Compose down --volumes (данные Postgres будут удалены)..."
  else
    info "Docker Compose down (тома сохраняются)..."
  fi
  docker "${args[@]}" || warn "docker compose down завершился с ошибкой, продолжаем."
}

echo
printf '\033[32mMusic Anti Blur — остановка\033[0m\n'
stop_api || warn "Остановка API прошла с ошибкой, продолжаем."
stop_flutter || warn "Остановка Flutter прошла с ошибкой, продолжаем."
stop_infra
info "Инфраструктура выключена."
if [[ "$REMOVE_VOLUMES" -eq 0 ]]; then
  warn "Тома Postgres и MinIO на месте. Полная очистка: bash devops/stop.sh --volumes"
fi
