#!/usr/bin/env bash
# SynaptixLabs project start script (Linux/macOS/CI)
# Generic scaffold — edit the CONFIGURATION section for your project.
# Based on AGENTS project start.sh patterns.
#
# Usage:
#   ./start.sh              # Production (default for Docker/CI)
#   ./start.sh dev          # Local dev: backend (--reload)
#   ./start.sh dev --ui     # Local dev: backend + frontend
#   ./start.sh test         # Run tests
#   ./start.sh stop         # Kill project processes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# CONFIGURATION — Edit this section per project
# ============================================================================
PROJECT_NAME="{{PROJECT_NAME}}"
BACKEND_TYPE="python"           # "python" | "node"
BACKEND_DIR="backend"           # "." for monolith
BACKEND_CMD="uvicorn app.main:app"  # Python entrypoint
RELOAD_DIRS="app modules"       # Space-separated --reload-dir targets (empty = watch all)
FRONTEND_DIR="frontend"         # matches the shipped skeleton; "" if no separate frontend
DEFAULT_PORT=8000
UI_PORT=5173
HEALTH_PATH="/health"
ENV_FILE=".env"
# ============================================================================

: "${PORT:=$DEFAULT_PORT}"
log() { echo "[start.sh] $*"; }

find_python() {
  for p in "$SCRIPT_DIR/$BACKEND_DIR/.venv/bin/python" "$SCRIPT_DIR/$BACKEND_DIR/venv/bin/python"; do
    [ -x "$p" ] && echo "$p" && return
  done
  echo "python3"
}

kill_port() {
  local pid; pid=$(lsof -ti :"$1" 2>/dev/null || true)
  [ -n "$pid" ] && { log "Port $1 in use by PID $pid — killing..."; kill -9 "$pid" 2>/dev/null || true; sleep 1; }
}

cleanup() { log "Shutting down..."; jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true; }
trap cleanup EXIT

# ── Commands ──────────────────────────────────────────
cmd_stop() { kill_port "$PORT"; [ -n "$FRONTEND_DIR" ] && kill_port "$UI_PORT"; log "Done."; exit 0; }

cmd_status() {
  local be_up=false fe_up=false
  lsof -ti :"$PORT" >/dev/null 2>&1 && be_up=true
  [ -n "$FRONTEND_DIR" ] && lsof -ti :"$UI_PORT" >/dev/null 2>&1 && fe_up=true
  log "Backend  (port $PORT):   $($be_up && echo 'UP' || echo 'DOWN')"
  [ -n "$FRONTEND_DIR" ] && log "Frontend (port $UI_PORT): $($fe_up && echo 'UP' || echo 'DOWN')"
  if $be_up; then
    local health; health=$(curl -sf "http://localhost:$PORT$HEALTH_PATH" 2>/dev/null)
    if [ -n "$health" ]; then
      log "Health: $(echo "$health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('status','?')} | build={d.get('build_stamp','?')}\")" 2>/dev/null || echo "$health")"
    else
      log "Health: endpoint unreachable"
    fi
  fi
  exit 0
}

cmd_test() {
  local PY; PY="$(find_python)"
  if [ "$BACKEND_TYPE" = "python" ]; then
    cd "$SCRIPT_DIR/$BACKEND_DIR" && "$PY" -m pytest -v --tb=short
  else
    cd "$SCRIPT_DIR" && npm test
  fi
}

cmd_production() {
  local be_dir="$SCRIPT_DIR/$BACKEND_DIR"
  [ "$BACKEND_DIR" = "." ] && be_dir="$SCRIPT_DIR"
  cd "$be_dir"
  if [ "$BACKEND_TYPE" = "python" ]; then
    [ -f requirements.txt ] && pip install --no-cache-dir -r requirements.txt
    log "Starting $BACKEND_CMD on 0.0.0.0:${PORT} (production)"
    exec python -m $BACKEND_CMD --host 0.0.0.0 --port "${PORT}"
  else
    npm run build && exec npm run start
  fi
}

cmd_dev() {
  local with_ui=false
  [[ "${1:-}" == "--ui" ]] && with_ui=true

  local PY=""
  if [ "$BACKEND_TYPE" = "python" ]; then
    PY="$(find_python)"
    log "Python: $PY | Port: $PORT"
  else
    log "Node | Port: $PORT"
  fi

  # Kill stale, clean caches
  kill_port "$PORT"
  $with_ui && kill_port "$UI_PORT"
  local be_dir="$SCRIPT_DIR/$BACKEND_DIR"
  [ "$BACKEND_DIR" = "." ] && be_dir="$SCRIPT_DIR"
  if [ "$BACKEND_TYPE" = "python" ]; then
    export PYTHONDONTWRITEBYTECODE=1
    find "$be_dir" -type d -name __pycache__ -not -path '*/.venv/*' -exec rm -rf {} + 2>/dev/null || true
  fi

  # Build stamp
  BUILD_STAMP=$(date "+%Y-%m-%d_%H:%M:%S"); export BUILD_STAMP
  log "Build stamp: $BUILD_STAMP"

  # Start frontend in background
  if $with_ui && [ -n "$FRONTEND_DIR" ]; then
    local fe_dir="$SCRIPT_DIR/$FRONTEND_DIR"
    [ ! -d "$fe_dir/node_modules" ] && (cd "$fe_dir" && npm install)
    log "Starting frontend on http://localhost:$UI_PORT"
    (cd "$fe_dir" && npx vite --port "$UI_PORT" --host) &
  fi

  # Banner
  echo ""
  echo "  ============================================"
  echo "   $PROJECT_NAME"
  echo "  --------------------------------------------"
  echo "   Build:    $BUILD_STAMP"
  echo "   Backend:  http://localhost:$PORT"
  $with_ui && echo "   Frontend: http://localhost:$UI_PORT"
  echo "   Press Ctrl+C to stop"
  echo "  ============================================"
  echo ""

  cd "$be_dir"
  if [ "$BACKEND_TYPE" = "python" ]; then
    local reload_args="--reload"
    for rd in $RELOAD_DIRS; do
      [ -n "$rd" ] && reload_args="$reload_args --reload-dir $rd"
    done
    "$PY" -m $BACKEND_CMD --host 0.0.0.0 --port "${PORT}" $reload_args
  else
    PORT="$PORT" npm run dev
  fi
}

# ── Main dispatch ─────────────────────────────────────
case "${1:-production}" in
  stop)       cmd_stop ;;
  status)     cmd_status ;;
  test)       shift; cmd_test "$@" ;;
  dev)        shift; cmd_dev "$@" ;;
  production|*) cmd_production ;;
esac
