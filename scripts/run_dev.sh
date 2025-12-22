#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from .env file
load_env_vars() {
  if [ -f .env ]; then
    while IFS= read -r line; do
      line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      if [[ $line =~ ^# || -z $line ]]; then continue; fi
      if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)\= ]]; then
        key="${BASH_REMATCH[1]}"
        value="${line#*=}"
        if [ -z "${!key:-}" ]; then
          export "$line"
        fi
      fi
    done < .env
  fi
}

# Setup configuration variables
setup_config() {
  BACKEND_PORT="${PNAS_PORT:-8000}"
  FRONTEND_PORT=5173
  DEV_PG_NAME="${DEV_PG_NAME:-pnas_dev_pg}"
  DEV_PG_PORT="${DEV_PG_PORT:-5432}"
  DEV_PG_IMAGE="${DEV_PG_IMAGE:-postgres:16-alpine}"
  DEV_PG_DB="${DEV_PG_DB:-pnas}"
  DEV_PG_USER="${DEV_PG_USER:-postgres}"
  DEV_PG_PASSWORD="${DEV_PG_PASSWORD:-${POSTGRES_PASSWORD:-postgres}}"
  DEV_PG_HOST="${DEV_PG_HOST:-127.0.0.1}"
  DEV_PG_PORT_ALT="${DEV_PG_PORT_ALT:-55432}"
}

# Kill processes on a given port
kill_by_port() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids=$(lsof -ti tcp:"$port" || true)
    if [ -n "$pids" ]; then
      kill -9 $pids || true
    fi
  elif command -v fuser >/dev/null 2>&1; then
    fuser -k "${port}/tcp" || true
  else
    local pids
    pids=$(ss -lntp | awk -v p=":${port}" '$4 ~ p {print $NF}' | sed -E 's/.*pid=([0-9]+).*/\1/' | tr '\n' ' ')
    if [ -n "$pids" ]; then
      kill -9 $pids || true
    fi
  fi
}

# Check if a port is open on a host
is_port_open() {
  local host="$1"
  local port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z "$host" "$port" >/dev/null 2>&1
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP -sTCP:LISTEN -nP | grep -q ":$port"
    return $?
  fi
  timeout 1 bash -c ">/dev/tcp/${host}/${port}" >/dev/null 2>&1
}

# Check if a port is in use
port_in_use() {
  local port="$1"
  ss -lntp | awk -v p=":${port}" '$4 ~ p {f=1} END {exit f?0:1}'
}

# Check if we can authenticate to postgres
can_auth_postgres() {
  local host="$1"
  local port="$2"
  local user="$3"
  local db="$4"
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="${DEV_PG_PASSWORD}" psql -h "$host" -p "$port" -U "$user" -d "$db" -c '\q' >/dev/null 2>&1
    return $?
  fi
  return 1
}

# Setup and start database container
setup_database() {
  if port_in_use "$DEV_PG_PORT"; then
    ALT_NAME="${DEV_PG_NAME}_${DEV_PG_PORT_ALT}"
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$ALT_NAME"; then
      docker run -d --name "$ALT_NAME" -p "${DEV_PG_PORT_ALT}:5432" \
        -e POSTGRES_USER="$DEV_PG_USER" \
        -e POSTGRES_PASSWORD="$DEV_PG_PASSWORD" \
        -e POSTGRES_DB="$DEV_PG_DB" \
        "$DEV_PG_IMAGE"
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$ALT_NAME")" != "true" ]; then
      docker start "$ALT_NAME"
    fi
    until docker exec "$ALT_NAME" pg_isready -U "$DEV_PG_USER" >/dev/null 2>&1; do
      sleep 1
    done
    export DATABASE_URL="postgres://${DEV_PG_USER}:${DEV_PG_PASSWORD}@127.0.0.1:${DEV_PG_PORT_ALT}/${DEV_PG_DB}"
  else
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$DEV_PG_NAME"; then
      docker run -d --name "$DEV_PG_NAME" -p "${DEV_PG_PORT}:5432" \
        -e POSTGRES_USER="$DEV_PG_USER" \
        -e POSTGRES_PASSWORD="$DEV_PG_PASSWORD" \
        -e POSTGRES_DB="$DEV_PG_DB" \
        "$DEV_PG_IMAGE"
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$DEV_PG_NAME")" != "true" ]; then
      docker start "$DEV_PG_NAME"
    fi
    until docker exec "$DEV_PG_NAME" pg_isready -U "$DEV_PG_USER" >/dev/null 2>&1; do
      sleep 1
    done
    export DATABASE_URL="postgres://${DEV_PG_USER}:${DEV_PG_PASSWORD}@127.0.0.1:${DEV_PG_PORT}/${DEV_PG_DB}"
  fi
}

# Start backend and frontend services
start_services() {
  pushd ./nasserver
  PNAS_PORT="$BACKEND_PORT" cargo run &
  SERVER_PID=$!
  popd
  
  pushd ./webdesktop
  npm install
  VITE_PNAS_PORT="$BACKEND_PORT" npm run dev -- --host --port "${FRONTEND_PORT}" &
  WEB_PID=$!
  echo "Backend: http://localhost:${BACKEND_PORT}"
  echo "Frontend: http://localhost:${FRONTEND_PORT}"
  echo "Database: ${DATABASE_URL}"
  popd
  
  # Cleanup function to kill background processes
  cleanup() {
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    kill "$WEB_PID" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT
  
  # Wait for background processes
  wait
}

# Main function to orchestrate the dev environment setup
main() {
  load_env_vars
  setup_config
  
  # Kill processes on backend and frontend ports
  kill_by_port "$BACKEND_PORT"
  kill_by_port "$FRONTEND_PORT"
  
  setup_database
  
  # Setup additional environment variables
  export JWT_SECRET="${JWT_SECRET:-dev-secret}"
  export PNAS_DEV_STORAGE_PATH="${PNAS_DEV_STORAGE_PATH:-$(pwd)/devdata}"
  mkdir -p "$PNAS_DEV_STORAGE_PATH"
  
  start_services
}

# Run the main function
main